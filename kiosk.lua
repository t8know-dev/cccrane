-- crane-load-unload.lua — Monitor-based crane load/unload panel (ECNet2 server)
--
-- Completely independent from crane-panel.lua. Runs on a 2×1 monitor (30 lines)
-- and provides a wizard-style UI for loading/unloading containers from train wagons.
-- Uses point files (data/pickup_points.lua / data/drop_points.lua) for source/destination lists.
--
-- Usage: crane-load-unload
--
-- The panel's ECNet2 address is printed on startup — copy it to
-- src/remote_config.lua on the crane computer.

local ecnet2 = require "ecnet2"
local random = require "ccryptolib.random"
random.initWithTiming()

local pixelui = require("lib.pixelui")

-- Load config
local cfg = dofile("cccrane/src/config.lua")

-- Load state + UI modules (absolute paths for reliability, same pattern as ccunloader)
local function loadMod(path)
    local ok, mod = pcall(dofile, "cccrane/" .. path .. ".lua")
    if not ok then error("Failed to load " .. path .. ": " .. tostring(mod)) end
    return mod
end

local st = loadMod("modules/load_unload_state")
local ui = loadMod("modules/monitor_ui")
ui.init(pixelui)

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local panelState = {
    connection       = nil,       -- active ECNet2 connection
    connected        = false,
    craneId          = "?",
    registered       = false,

    -- Crane status (last known, for operation progress inference)
    cranePos         = { 0, 0 },
    craneSticker     = false,
    craneBusy        = false,
    craneError       = false,
    craneErrorMsg    = "",

    -- Pending command tracking
    pending          = false,     -- true while waiting for ACK
    pendingSeq       = 0,
    lastSeq          = 0,

    -- Operation execution phase tracking
    executing        = false,     -- true between RUN click and ACK
    execPhase        = 0,         -- 0=starting, 1=moving_to_src, 2=picking_up, 3=moving_to_dst, 4=dropping

    -- Disconnect watchdog
    lastMessageTime  = nil,       -- os.epoch("utc") of last received message
    watchdogTimer    = nil,       -- timer ID for periodic disconnect checks

    -- Keepalive
    keepAliveTimer   = nil,       -- timer ID for periodic keepalive pings

    -- Handshake completion
    pendingConfigQuery = false,   -- true if CONFIG_QUERY needs to be sent after handshake
}

local CONNECTION_TIMEOUT = 15     -- seconds without message = disconnected
local KEEPALIVE_INTERVAL = 7      -- seconds between keepalive pings

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
-- MONITOR DISCOVERY
------------------------------------------------------------

local monitorName = cfg.MONITOR_PERIPHERAL or "monitor_0"
print("Waiting for monitor '" .. monitorName .. "'...")
local mon = peripheral.wrap(monitorName)
local retries = 0
while not mon do
    retries = retries + 1
    if retries > 30 then
        print("Monitor not found after 30s. Give up.")
        return
    end
    os.sleep(1)
    mon = peripheral.wrap(monitorName)
end
print("Monitor found: " .. monitorName)

------------------------------------------------------------
-- LOAD POINT FILES
------------------------------------------------------------

local pickupFile = cfg.PICKUP_POINTS_FILE or "pickup_points.lua"
local dropFile = cfg.DROP_POINTS_FILE or "drop_points.lua"

local function loadPoints(path, label)
    local ok, points = pcall(dofile, path)
    if not ok or type(points) ~= "table" or #points == 0 then
        print("WARNING: " .. label .. " '" .. path .. "' not found or empty")
        return {
            { name = "Default " .. label, x = 10, y = 10 },
        }
    end
    print(label .. ": " .. tostring(#points) .. " points loaded from " .. path)
    return points
end

local sourcePoints = loadPoints(pickupFile, "Pickup")
local destPoints = loadPoints(dropFile, "Drop")

st.updateState({
    sourcePoints = sourcePoints,
    destPoints = destPoints,
    selectedSource = sourcePoints[1],
    selectedDest = destPoints[1],
})

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
-- INFER OPERATION PHASE FROM CRANE STATUS
------------------------------------------------------------

local function inferExecPhase(pos, sticker, srcPoint, dstPoint)
    local sx, sy = srcPoint.x, srcPoint.y
    local dx, dy = dstPoint.x, dstPoint.y
    local cx, cy = pos[1], pos[2]

    -- If near source and sticker is OFF → moving to or at source
    if cx == sx and cy == sy then
        if not sticker then
            return 1  -- "Moving to pickup point..." / arrived at source
        else
            return 2  -- "Picking up..." (sticker just engaged)
        end
    end

    -- If near destination
    if cx == dx and cy == dy then
        if sticker then
            return 3  -- "Moving to drop point..." / arrived at dest with load
        else
            return 4  -- "Dropping..." (sticker just released)
        end
    end

    -- If we have sticker on and are not at source → moving to dest
    if sticker then
        return 3
    end

    -- Default: moving to source
    return 1
end

local EXEC_LABELS = {
    [0] = "Starting...",
    [1] = "Moving to pickup point...",
    [2] = "Picking up...",
    [3] = "Moving to drop point...",
    [4] = "Dropping...",
    [5] = "Returning...",
    [6] = "Done!",
}

------------------------------------------------------------
-- SENDING COMMANDS
------------------------------------------------------------

--- Send a COMMAND request to the crane.
local function sendCommand(command, params)
    if not panelState.connection then
        print(timestamp() .. " Cannot send: not connected")
        return false
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

    print(timestamp() .. " Sending: " .. command)
    local ok = pcall(panelState.connection.send, panelState.connection, msg)
    if not ok then
        print("SEND FAILED — connection lost")
        panelState.connection = nil
        panelState.connected = false
        panelState.registered = false
        panelState.pending = false
        st.updateState({
            connected = false,
            registered = false,
            screen = "connection_lost",
        })
        return false
    end

    st.updateState({ connected = panelState.connected })
    return true
end

------------------------------------------------------------
-- MESSAGE HANDLING
------------------------------------------------------------

--- Handle an incoming ECNet2 message.
local function handleMessage(msg)
    -- Reset disconnect watchdog on any message
    panelState.lastMessageTime = os.epoch("utc")

    if not msg or not msg.type or not msg.body then return end
    local body = msg.body

    if body.message_type == "REGISTER" then
        panelState.craneId = body.crane_id or "?"
        panelState.registered = true
        print(timestamp() .. " Registered: crane " .. panelState.craneId)

        -- Handshake complete — start keepalive
        panelState.keepAliveTimer = os.startTimer(KEEPALIVE_INTERVAL)

        -- Send deferred CONFIG_QUERY
        if panelState.pendingConfigQuery then
            panelState.pendingConfigQuery = false
            pcall(panelState.connection.send, panelState.connection, {
                type = "request",
                body = { message_type = "CONFIG_QUERY" },
            })
        end

        st.updateState({
            registered = true,
            connected = true,
            craneId = panelState.craneId,
            screen = panelState.executing and st.getState("screen") or
                     (st.getState("screen") == "connection_lost" and "main" or st.getState("screen")),
        })
        -- If we were on connection_lost screen, go back to main
        if st.getState("screen") == "connection_lost" then
            st.updateState({ screen = "main" })
        end

    elseif body.message_type == "ACK" then
        panelState.pending = false
        panelState.executing = false

        local ackStatus = body.status or "?"
        local ackMsg = body.message or ""

        if ackStatus == "ok" then
            print(timestamp() .. "  " .. (body.command_seq or "?") .. " OK")
            st.updateState({
                operationDone = true,
                operationError = nil,
                operationStatus = "Done!",
                screen = "success",
            })
        elseif ackStatus == "emergency_stop" then
            print(timestamp() .. "  Emergency stopped")
            st.updateState({
                operationDone = true,
                operationError = nil,
                operationStatus = "Emergency stopped",
                screen = "success",
            })
        else
            print(timestamp() .. "  ERROR: " .. ackMsg)
            st.updateState({
                operationDone = true,
                operationError = ackMsg,
                screen = "error",
            })
        end

    elseif body.message_type == "STATUS" then
        local stBody = body.status or {}
        local newPos = stBody.position or panelState.cranePos
        local newSticker = stBody.sticker == true
        local newBusy = stBody.busy == true
        local newError = stBody.error == true
        local newErrorMsg = stBody.error_msg or ""
        local newPhase = stBody.phase  -- explicit phase from client (nil for non-PICKANDROP commands)

        panelState.cranePos = newPos
        panelState.craneSticker = newSticker
        panelState.craneBusy = newBusy
        panelState.craneError = newError
        panelState.craneErrorMsg = newErrorMsg

        -- If we're executing, determine the phase
        if panelState.executing then
            local phase
            if newPhase ~= nil then
                -- Use explicit phase from client (PICKANDROP sub-steps)
                phase = newPhase
            else
                -- Fall back to inference for other commands
                local src = st.getState("selectedSource") or { x = 0, y = 0 }
                local dst = st.getState("selectedDest") or { x = 0, y = 0 }
                phase = inferExecPhase(newPos, newSticker, src, dst)
            end
            if phase ~= panelState.execPhase then
                panelState.execPhase = phase
                local label = EXEC_LABELS[phase] or "Executing..."
                st.updateState({ operationStatus = label })
                ui.updateProgress(st.getState())
            end
        end

    elseif body.message_type == "CONFIG_RESPONSE" then
        local cfgBody = body.config or {}
        print(timestamp() .. " Config: " .. (cfgBody.max_x or "?") .. "x" .. (cfgBody.max_y or "?"))
    end
end

------------------------------------------------------------
-- CALLBACKS
------------------------------------------------------------

------------------------------------------------------------
-- EMERGENCY STOP
------------------------------------------------------------

local function sendEmergencyStop()
    if panelState.connection then
        pcall(panelState.connection.send, panelState.connection, {
            type = "request",
            body = { message_type = "COMMAND", command = "EMERGENCY_STOP" },
        })
        print(timestamp() .. " EMERGENCY STOP sent")
    end
end

------------------------------------------------------------
-- THREAD HELPERS (timed screen transitions)
------------------------------------------------------------

--- Cancel a thread handle if it is currently running.
local function cancelThread(handle)
    if handle and handle:isRunning() then
        handle:cancel()
    end
end

local function makeThreadOpts(name)
    return {
        name = name,
        onStatus = function(h, status)
            -- silent
        end,
    }
end

--- Spawn a thread that waits N seconds, then transitions to main.
local function spawnTransitionTimer(app, targetScreen, delay, nextScreen)
    local handle = app:spawnThread(function(ctx)
        ctx:sleep(delay)
        ctx:checkCancelled()
        if st.getState("screen") ~= targetScreen then return end
        st.updateState({ screen = nextScreen or "main" })
    end, makeThreadOpts("Transition Timer"))
    return handle
end

------------------------------------------------------------
-- WATCHDOG / KEEPALIVE TIMER HANDLER
------------------------------------------------------------

local function handleTimer(timerId)
    -- Watchdog: check for connection timeout
    if timerId == panelState.watchdogTimer and panelState.connected then
        local now = os.epoch("utc")
        local elapsed = (now - (panelState.lastMessageTime or now)) / 1000
        if elapsed >= CONNECTION_TIMEOUT then
            print(timestamp() .. " Crane disconnected (timeout)")
            panelState.connection = nil
            panelState.connected = false
            panelState.registered = false
            panelState.craneId = "?"
            panelState.keepAliveTimer = nil
            panelState.executing = false
            panelState.pending = false
            st.updateState({
                connected = false,
                registered = false,
                screen = "connection_lost",
            })
        else
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
-- PIXELUI EVENT INTERCEPTOR (ECNet2 + timer events)
------------------------------------------------------------

-- We need to intercept events that PixelUI doesn't handle natively.
-- Patch the root widget's handleEvent to catch ecnet2 events and timers.
-- This is the same pattern used by crane-panel.lua's panel_ui.

------------------------------------------------------------
-- UI CREATION (must happen after callbacks are set up)
------------------------------------------------------------

-- Create the PixelUI app on the monitor
local app = ui.createUI(mon, st)

-- Wire the emergency stop callback for the UI button
app._callbacks = app._callbacks or {}
app._callbacks.onEmergencyStop = sendEmergencyStop

------------------------------------------------------------
-- THREAD HANDLES
------------------------------------------------------------

local threadHandles = {}
app._threadHandles = threadHandles

------------------------------------------------------------
-- MAIN STATE SUBSCRIBER
------------------------------------------------------------

-- Wire up the primary state subscriber that:
--   1. Re-renders the UI on screen/item changes
--   2. Sends PICKANDDROP command when "executing" screen is entered
--   3. Spawns timed transition threads for success/error screens
st.subscribe(function(changes)
    -- If screen transitioned to "executing" and we haven't sent a command yet
    if changes.screen == "executing" and not panelState.executing then
        panelState.executing = true
        panelState.execPhase = 0

        local src = st.getState("selectedSource")
        local dst = st.getState("selectedDest")
        if src and dst then
            sendCommand("PICKANDDROP", {
                src = { x = src.x, y = src.y },
                dst = { x = dst.x, y = dst.y },
            })
            st.updateState({ operationStatus = EXEC_LABELS[1] })
        end
    end

    -- If leaving executing state, clear flag
    if changes.screen and changes.screen ~= "executing" and panelState.executing then
        panelState.executing = false
    end

    -- Handle timed transitions for success/error
    if changes.screen == "success" then
        cancelThread(threadHandles.transitionTimer)
        threadHandles.transitionTimer = spawnTransitionTimer(app, "success", 3, "main")
    elseif changes.screen == "error" then
        cancelThread(threadHandles.transitionTimer)
        threadHandles.transitionTimer = spawnTransitionTimer(app, "error", 5, "main")
    elseif changes.screen == "connection_lost" then
        cancelThread(threadHandles.transitionTimer)
        -- No auto-transition from connection_lost — wait for reconnection
    end

    -- Trigger UI screen update
    ui.updateScreen(st.getState())
end)

-- Patch root for ECNet2 and timer events
local root = app:getRoot()
local origHandleEvent = root.handleEvent
function root:handleEvent(event, ...)
    if event == "ecnet2_request" then
        local rid, req = ...
        -- Handle connection request
        if panelState.connection then
            local dummy = listener:accept("busy", req)
            print(timestamp() .. " Rejected extra connection")
        else
            local conn = listener:accept("crane_load_unload_v1.0", req)
            panelState.connection = conn
            panelState.connected = true
            panelState.pending = false
            panelState.registered = false
            panelState.pendingConfigQuery = true
            panelState.watchdogTimer = os.startTimer(CONNECTION_TIMEOUT)
            panelState.lastMessageTime = os.epoch("utc")
            print(timestamp() .. " Crane connecting...")
            st.updateState({ connected = true, registered = false })
        end
        return true
    end

    if event == "ecnet2_message" then
        local cid, addr, msg = ...
        if panelState.connection and cid == panelState.connection.id then
            handleMessage(msg)
        end
        return true
    end

    if event == "timer" then
        local tid = ...
        handleTimer(tid)
        return true
    end

    return origHandleEvent and origHandleEvent(self, event, ...) or false
end

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------

-- Save panel address to file
local addrFile = fs.open("panel_address.txt", "w")
if addrFile then
    addrFile:writeLine("=== Crane Load/Unload Panel ===")
    addrFile:writeLine("ECNet2 address: " .. (id.address or "unknown"))
    addrFile:writeLine("Copy this address to crane-remote-config.lua on the crane.")
    addrFile:close()
end

print("=== Crane Load/Unload Panel ===")
print("ECNet2 address: " .. (id.address or "unknown"))
print("Copy this address to crane-remote-config.lua on the crane.")
print("Waiting for connection...")

-- Initial UI render
ui.updateScreen(st.getState())

------------------------------------------------------------
-- EVENT LOOP
------------------------------------------------------------

parallel.waitForAny(
    function()
        app:run()
    end,
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
