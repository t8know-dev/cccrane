-- crane-client.lua — Remote-controlled crane daemon
--
-- Connects to a crane control panel via ECNet2, receives commands,
-- and drives the crane hardware.
--
-- Usage: crane-client
--
-- Requires:
--   crane-remote-config.lua  (PANEL_ADDRESS, heartbeat, reconnect settings)
--   crane-lib.lua            (crane hardware control library)
--   ecnet/                   (ECNet2 networking framework)
--   ccryptolib/              (crypto primitives for ECNet2)

-- Bootstrap: set up package.path for ecnet2 and ccryptolib
dofile("/cccrane/init.lua")

local ecnet2 = require "ecnet2"
local random = require "ccryptolib/ccryptolib/random"
random.initWithTiming()

local rc = dofile("/cccrane/crane-remote-config.lua")
local crane = dofile("/cccrane/crane-lib.lua")

ecnet2.open("top")

local id = ecnet2.Identity("/.ecnet2")
local proto = id:Protocol {
    name = "crane_control",
    serialize = textutils.serialize,
    deserialize = textutils.unserialize,
}

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local conn = nil          -- active ECNet2 connection
local busy = false         -- true while executing a command
local heartbeatTimer = nil -- timer ID for periodic status

------------------------------------------------------------
-- CONNECTION HELPERS
------------------------------------------------------------

--- Try to connect to the panel. Keeps trying with exponential backoff.
--- @return table connection
local function connectToPanel()
    local backoff = rc.RECONNECT_BACKOFF_INITIAL
    while true do
        local ok, c = pcall(proto.connect, proto, rc.PANEL_ADDRESS, "top")
        if ok then
            local ok2, greeting = pcall(c.receive, c)
            if ok2 and greeting then
                print("Connected: " .. tostring(select(2, greeting)))
                local ok3 = pcall(c.send, c, {
                    type = "request",
                    body = {
                        message_type = "REGISTER",
                        crane_id = tostring(os.getComputerID()),
                        version = "1.0",
                    }
                })
                if ok3 then
                    return c
                end
            end
        end
        print("Reconnect in " .. backoff .. "s...")
        sleep(math.min(backoff, 5))
        backoff = math.min(backoff * rc.RECONNECT_BACKOFF_MULT, rc.RECONNECT_BACKOFF_MAX)
    end
end

--- Send a message with error handling. On failure, marks conn as nil and
--- starts reconnect on next main-loop iteration.
--- @param msg table
--- @return boolean ok
local function sendMessage(msg)
    if not conn then return false end
    local ok = pcall(conn.send, conn, msg)
    if not ok then
        print("WARNING: send failed, connection lost")
        conn = nil
    end
    return ok
end

--- Send a STATUS event to the panel.
local function sendStatus()
    local st = crane.getState()
    sendMessage({
        type = "event",
        body = {
            message_type = "STATUS",
            status = {
                position = { st.currentX, st.currentY },
                sticker = st.stickerOn,
                busy = busy,
            },
        },
    })
end

--- Try to re-establish connection. Blocks until connected.
local function tryReconnect()
    print("Attempting reconnect...")
    local backoff = rc.RECONNECT_BACKOFF_INITIAL
    while true do
        if conn then return end

        local ok, c = pcall(proto.connect, proto, rc.PANEL_ADDRESS, "top")
        if ok then
            local ok2, greeting = pcall(c.receive, c)
            if ok2 and greeting then
                conn = c
                print("Reconnected")

                pcall(c.send, c, {
                    type = "request",
                    body = {
                        message_type = "REGISTER",
                        crane_id = tostring(os.getComputerID()),
                        version = "1.0",
                    },
                })

                sendStatus()
                return
            end
        end

        sleep(backoff)
        backoff = math.min(backoff * rc.RECONNECT_BACKOFF_MULT, rc.RECONNECT_BACKOFF_MAX)
    end
end

------------------------------------------------------------
-- COMMAND EXECUTION
------------------------------------------------------------

--- Execute a crane command (blocks until complete).
--- @param command string
--- @param params table
--- @param seq number
local function executeCommand(command, params, seq)
    busy = true
    crane.clearStop()
    sendStatus()

    local ok, err = pcall(function()
        if command == "GOTO" then
            crane.gotoXY(params.x, params.y)
        elseif command == "PICKUP" then
            crane.pickup()
        elseif command == "DROP" then
            crane.drop()
        elseif command == "HOME" then
            crane.home()
        elseif command == "STATUS_QUERY" then
            -- nothing to do, status sent below
        else
            error("Unknown command: " .. tostring(command))
        end
    end)

    busy = false

    if not ok then
        sendMessage({
            type = "response",
            body = {
                message_type = "ACK",
                status = "error",
                message = tostring(err),
                command_seq = seq,
            },
        })
    else
        sendMessage({
            type = "response",
            body = {
                message_type = "ACK",
                status = "ok",
                command_seq = seq,
            },
        })
    end

    sendStatus()
end

------------------------------------------------------------
-- MESSAGE ROUTER (runs in parallel)
--
-- Catches ALL ecnet2_message events and:
--   - Handles EMERGENCY_STOP immediately (even during blocking ops)
--   - Re-queues everything else as "crane_msg" for the main loop
--
-- This is needed because the main loop is blocked inside
-- executeCommand() (which only does sleep()-based busy-waiting
-- and never calls pullEvent), so it cannot receive new messages
-- during a crane operation without this router thread.
------------------------------------------------------------

local function msgRouter()
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent("ecnet2_message")
        if conn and p1 == conn.id then
            if p3 and p3.type == "request" and p3.body
               and p3.body.message_type == "COMMAND"
               and p3.body.command == "EMERGENCY_STOP" then
                -- Handle emergency stop immediately, even during a blocking op
                crane.emergencyStop()
                pcall(conn.send, conn, {
                    type = "response",
                    body = {
                        message_type = "ACK",
                        status = "ok",
                        command_seq = p3.body.seq,
                    },
                })
            else
                -- Re-queue for the main loop under a different event name
                os.queueEvent("crane_msg", p1, p2, p3, p4, p5)
            end
        end
    end
end

------------------------------------------------------------
-- MAIN LOOP
------------------------------------------------------------

local function mainLoop()
    while true do
        -- Ensure we are connected before processing events
        if not conn then
            tryReconnect()
            heartbeatTimer = os.startTimer(rc.HEARTBEAT_INTERVAL)
        end

        local event, id, p2, p3, ch, dist = os.pullEvent()

        if event == "timer" and id == heartbeatTimer then
            sendStatus()
            heartbeatTimer = os.startTimer(rc.HEARTBEAT_INTERVAL)

        elseif event == "crane_msg" and conn and id == conn.id then
            local msg = p3
            if not msg or not msg.body then
                -- skip
            elseif msg.body.message_type == "COMMAND" then
                local cmd = msg.body.command
                local params = msg.body.params or {}
                local seq = msg.body.seq

                if cmd == "EMERGENCY_STOP" then
                    -- Handled by msgRouter, but just in case it arrives here:
                    crane.emergencyStop()
                    sendMessage({
                        type = "response",
                        body = {
                            message_type = "ACK",
                            status = "ok",
                            command_seq = seq,
                        },
                    })
                elseif busy then
                    sendMessage({
                        type = "response",
                        body = {
                            message_type = "ACK",
                            status = "error",
                            message = "Crane is busy",
                            command_seq = seq,
                        },
                    })
                elseif cmd == "STATUS_QUERY" then
                    sendStatus()
                else
                    executeCommand(cmd, params, seq)
                end
            elseif msg.body.message_type == "CONFIG_QUERY" then
                sendMessage({
                    type = "response",
                    body = {
                        message_type = "CONFIG_RESPONSE",
                        config = {
                            max_x = crane.config.MAX_X,
                            max_y = crane.config.MAX_Y,
                            lift_height = crane.config.LIFT_HEIGHT,
                            home_offset_x = crane.config.HOME_OFFSET_X,
                            home_offset_y = crane.config.HOME_OFFSET_Y,
                        },
                    },
                })
            end
        end
    end
end

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------

print("Crane client starting...")
crane.init()

-- Set timer BEFORE connecting so the first heartbeat catches the connect
heartbeatTimer = os.startTimer(1)

conn = connectToPanel()
print("Crane client ready, listening for commands.")

parallel.waitForAny(mainLoop, msgRouter, ecnet2.daemon)

-- Cleanup on exit (Ctrl+T / unexpected shutdown)
crane.done()
ecnet2.close("top")
