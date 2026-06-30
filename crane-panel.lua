-- crane-panel.lua — v13 Crane control panel (ECNet2 server)
--
-- Full-screen terminal GUI for remotely controlling a crane via ECNet2.
-- Displays source/destination position fields, command buttons, crane status,
-- and an operation log. Uses PixelUI for all rendering.
--
-- Usage: crane-panel
--
-- The panel's ECNet2 address is printed on startup — copy it to
-- crane-remote-config.lua on the crane computer.

local ecnet2 = require "ecnet2"
local random = require "ccryptolib.random"
random.initWithTiming()

local PanelUI = require("panel_ui")

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local panelState = {
    connection  = nil,       -- active ECNet2 connection
    connected   = false,
    craneId     = "?",

    -- Crane status (last known)
    cranePos    = { 0, 0 },
    craneSticker = false,
    craneBusy   = false,
    craneError  = false,
    craneErrorMsg = "",

    -- Pending command tracking
    pending         = false,  -- true while waiting for ACK
    pendingSeq      = 0,
    lastSeq         = 0,

    -- Disconnect watchdog
    lastMessageTime = nil,    -- os.epoch("utc") of last received message
    watchdogTimer   = nil,    -- timer ID for periodic disconnect checks

    -- Keepalive
    keepAliveTimer  = nil,    -- timer ID for periodic keepalive pings

    -- Handshake completion
    pendingConfigQuery = false,  -- true if CONFIG_QUERY needs to be sent after handshake
    registered         = false,  -- true once REGISTER received (handshake fully done)
}

local CONNECTION_TIMEOUT = 15  -- seconds without message = disconnected
local KEEPALIVE_INTERVAL = 7   -- seconds between keepalive pings

------------------------------------------------------------
-- ECNet2 SETUP
------------------------------------------------------------

ecnet2.open("top")

local id = ecnet2.Identity("/.ecnet2")
local proto = id:Protocol {
    name = "crane_control",
    serialize = textutils.serialize,
    deserialize = textutils.unserialize,
}
local listener = proto:listen()

------------------------------------------------------------
-- UI INSTANCE (created early, callbacks filled below)
------------------------------------------------------------

local ui = PanelUI.create({ callbacks = {} })

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

--- Format a timestamp for log lines.
local function timestamp()
    local t = os.time()
    local h = math.floor(t / 3600) % 24
    local m = math.floor(t / 60) % 60
    local s = t % 60
    return string.format("[%02d:%02d:%02d]", h, m, s)
end

------------------------------------------------------------
-- SENDING COMMANDS
------------------------------------------------------------

--- Send a COMMAND request to the crane.
--- @param command string command name
--- @param params table|nil command parameters
local function sendCommand(command, params)
    if not panelState.connection then
        ui:addLogLine(timestamp() .. " Cannot send: not connected", colors.red)
        return
    end

    panelState.lastSeq = panelState.lastSeq + 1
    panelState.pending = true
    panelState.pendingSeq = panelState.lastSeq

    local msg = {
        type = "request",
        body = {
            message_type = "COMMAND",
            command = command,
            params = params or {},
            seq = panelState.lastSeq,
        },
    }

    ui:addLogLine(timestamp() .. " Sending: " .. command)
    ui:showLoading(true)
    local ok = pcall(panelState.connection.send, panelState.connection, msg)
    if not ok then
        ui:addLogLine("SEND FAILED — connection lost", colors.red)
        panelState.connection = nil
        panelState.connected = false
        panelState.registered = false
        panelState.pending = false
    end

    ui:setPending(panelState.pending)
    ui:setConnected(panelState.connected, nil)
    ui:setRegistered(panelState.registered)
end

------------------------------------------------------------
-- MESSAGE HANDLING
------------------------------------------------------------

--- Handle an incoming ECNet2 message.
--- @param msg table deserialized message
local function handleMessage(msg)
    -- Reset disconnect watchdog on any message
    panelState.lastMessageTime = os.epoch("utc")

    if not msg or not msg.type or not msg.body then return end
    local body = msg.body

    if body.message_type == "REGISTER" then
        panelState.craneId = body.crane_id or "?"
        panelState.registered = true
        ui:addLogLine(timestamp() .. " Registered: crane " .. panelState.craneId, colors.green)

        -- Handshake complete — start keepalive
        panelState.keepAliveTimer = os.startTimer(KEEPALIVE_INTERVAL)

        -- Send deferred CONFIG_QUERY now that the handshake is complete
        if panelState.pendingConfigQuery then
            panelState.pendingConfigQuery = false
            pcall(panelState.connection.send, panelState.connection, {
                type = "request",
                body = { message_type = "CONFIG_QUERY" },
            })
            ui:addLogLine(timestamp() .. " Sent config query", colors.lightGray)
        end

        ui:setRegistered(true)
        ui:setConnected(true, panelState.craneId)

    elseif body.message_type == "ACK" then
        panelState.pending = false
        local ackStatus = body.status or "?"
        local ackMsg = body.message or ""
        if ackStatus == "ok" then
            ui:addLogLine(timestamp() .. "  " .. body.command_seq .. " OK", colors.green)
        else
            ui:addLogLine(timestamp() .. "  " .. body.command_seq .. " ERROR: " .. ackMsg, colors.red)
        end
        ui:setPending(false)
        ui:showLoading(false)

    elseif body.message_type == "STATUS" then
        local st = body.status or {}
        if st.position then
            panelState.cranePos[1] = st.position[1] or 0
            panelState.cranePos[2] = st.position[2] or 0
        end
        panelState.craneSticker = st.sticker == true
        panelState.craneBusy = st.busy == true
        panelState.craneError = st.error == true
        panelState.craneErrorMsg = st.error_msg or ""

        ui:setCraneStatus({
            pos = panelState.cranePos,
            sticker = panelState.craneSticker,
            busy = panelState.craneBusy,
            error = panelState.craneError,
            errorMsg = panelState.craneErrorMsg,
        })

    elseif body.message_type == "CONFIG_RESPONSE" then
        local cfg = body.config or {}
        ui:setGridSize(cfg.max_x or 100, cfg.max_y or 100)
        ui:addLogLine(timestamp() .. " Config: " .. (cfg.max_x or "?")
            .. "x" .. (cfg.max_y or "?") .. " grid", colors.yellow)
    end
end

------------------------------------------------------------
-- CALLBACKS
------------------------------------------------------------

-- Wire up the real callbacks that close over `ui` and panelState
ui._callbacks.onCommand = function(action, params)
    if action == "__ERROR" then
        ui:addLogLine(timestamp() .. " " .. tostring(params), colors.red)
        return
    end
    sendCommand(action, params)
end

ui._callbacks.onConnectionRequest = function(request)
    if panelState.connection then
        -- Already have a crane — reject
        local dummy = listener:accept("busy", request)
        ui:addLogLine(timestamp() .. " Rejected extra connection", colors.yellow)
    else
        local conn = listener:accept("crane_panel_v1.0", request)
        panelState.connection = conn
        panelState.connected = true
        panelState.pending = false
        panelState.registered = false
        panelState.pendingConfigQuery = true
        panelState.watchdogTimer = os.startTimer(CONNECTION_TIMEOUT)

        ui:addLogLine(timestamp() .. " Crane connecting...", colors.yellow)
        ui:setConnected(true, nil)
        ui:setPending(false)
        ui:setRegistered(false)
    end
end

ui._callbacks.onMessage = function(cid, msg)
    -- Only process messages from the active connection
    if not panelState.connection or cid ~= panelState.connection.id then return end
    handleMessage(msg)
end

ui._callbacks.onTimer = function(timerId)
    -- Watchdog: check for connection timeout
    if timerId == panelState.watchdogTimer and panelState.connected then
        local now = os.epoch("utc")
        local elapsed = (now - (panelState.lastMessageTime or now)) / 1000
        if elapsed >= CONNECTION_TIMEOUT then
            ui:addLogLine(timestamp() .. " Crane disconnected (timeout)", colors.red)
            panelState.connection = nil
            panelState.connected = false
            panelState.registered = false
            panelState.craneId = "?"
            panelState.keepAliveTimer = nil
            ui:setConnected(false, nil)
            ui:setRegistered(false)
            ui:setPending(false)
        else
            -- Restart watchdog
            panelState.watchdogTimer = os.startTimer(CONNECTION_TIMEOUT)
        end
        return
    end

    -- Keepalive: send a ping
    if timerId == panelState.keepAliveTimer and panelState.connected then
        pcall(panelState.connection.send, panelState.connection, {
            type = "ping",
            body = { message_type = "PING" },
        })
        panelState.keepAliveTimer = os.startTimer(KEEPALIVE_INTERVAL)
    end
end

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------

-- Save panel address to file for easy retrieval
local addrFile = fs.open("panel_address.txt", "w")
if addrFile then
    addrFile.writeLine("=== Crane Control Panel ===")
    addrFile.writeLine("ECNet2 address: " .. (id.address or "unknown"))
    addrFile.writeLine("Copy this address to crane-remote-config.lua on the crane.")
    addrFile.close()
end

print("=== Crane Control Panel ===")
print("ECNet2 address: " .. (id.address or "unknown"))
print("Copy this address to crane-remote-config.lua on the crane.")
print("Waiting for connection...")

-- Show initial log lines
ui:addLogLine(timestamp() .. " Panel started — waiting for crane...", colors.yellow)
ui:addLogLine("Address: " .. (id.address or "unknown"), colors.yellow)

------------------------------------------------------------
-- EVENT LOOP
------------------------------------------------------------

parallel.waitForAny(
    function() ui:run() end,
    ecnet2.daemon
)

------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------

if panelState.connection then
    pcall(panelState.connection.send, panelState.connection, {
        type = "request",
        body = { message_type = "COMMAND", command = "EMERGENCY_STOP" },
    })
end
ecnet2.close("top")
