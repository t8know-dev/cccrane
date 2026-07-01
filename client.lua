-- crane-client.lua — Remote-controlled crane daemon
--
-- Connects to a crane control panel via ECNet2, receives commands,
-- and drives the crane hardware.
--
-- Usage: crane-client
--
-- Requires:
--   src/remote_config.lua  (PANEL_ADDRESS, heartbeat, reconnect settings)
--   src/lib/crane.lua      (crane hardware control library)
--   ccryptolib/              (crypto primitives for ECNet2)

local ecnet2 = require "ecnet2"
local random = require "ccryptolib.random"
random.initWithTiming()

local rc = dofile("cccrane/src/remote_config.lua")
local crane = dofile("cccrane/src/lib/crane.lua")

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
local lastMessageTime = os.epoch("utc")  -- time of last received message (watchdog)

------------------------------------------------------------
-- CONNECTION HELPERS
------------------------------------------------------------

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
--- Must be called inside the parallel.waitForAny with ecnet2.daemon
--- so Connection:receive() can receive ecnet2_message events.
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
                lastMessageTime = os.epoch("utc")
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
    crane.markRunning()
    sendStatus()

    local aborted = false
    local ok, err = pcall(function()
        if command == "GOTO" then
            crane.gotoXY(params.x, params.y)
        elseif command == "PICKUP" then
            crane.pickup()
        elseif command == "DROP" then
            crane.drop()
        elseif command == "HOME" then
            crane.home()
        elseif command == "PICKANDDROP" then
            crane.gotoXY(params.src.x, params.src.y)
            if crane.isStopped() then aborted = true; return end
            sendStatus()
            crane.pickup()
            if crane.isStopped() then aborted = true; return end
            sendStatus()
            crane.gotoXY(params.dst.x, params.dst.y)
            if crane.isStopped() then aborted = true; return end
            sendStatus()
            crane.drop()
            sendStatus()
        elseif command == "STATUS_QUERY" then
            -- nothing to do, status sent below
        else
            error("Unknown command: " .. tostring(command))
        end
    end)

    busy = false

    if aborted then
        sendMessage({
            type = "response",
            body = {
                message_type = "ACK",
                status = "emergency_stop",
                command_seq = seq,
            },
        })
    elseif not ok then
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
    crane.markIdle()
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

-- How often msgRouter sends STATUS to the panel while the crane is busy.
local BUSY_STATUS_INTERVAL = 3

local function msgRouter()
    local busyTimer = nil
    while true do
        local event, p1, p2, p3, p4, p5 = os.pullEvent()

        if event == "ecnet2_message" then
            if conn and p1 == conn.id then
                -- Any message on this connection proves the link is alive
                lastMessageTime = os.epoch("utc")

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

        elseif event == "timer" and p1 == busyTimer then
            busyTimer = nil
        end

        -- If the crane is busy, send periodic STATUS to keep the panel's
        -- watchdog alive, and start a timer for the next one.
        if busy and conn then
            if not busyTimer then
                sendStatus()
                busyTimer = os.startTimer(BUSY_STATUS_INTERVAL)
            end
        else
            -- Not busy — cancel any pending timer
            if busyTimer then
                os.cancelTimer(busyTimer)
                busyTimer = nil
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
            -- Disconnect watchdog: if we haven't heard from the panel for
            -- more than CONNECTION_TIMEOUT seconds, assume connection is dead.
            local elapsed = os.epoch("utc") - lastMessageTime
            if elapsed > rc.CONNECTION_TIMEOUT * 1000 then
                print(string.format("Disconnect detected (%ds silence), reconnecting...", elapsed / 1000))
                conn = nil
                tryReconnect()
            end
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

                    -- Heartbeat timer may have been consumed/discarded while
                    -- executeCommand was blocking (sleep inside waitUntilStopped
                    -- consumes timer events that don't match its own timer ID).
                    -- Restart it explicitly so the panel doesn't time out.
                    if heartbeatTimer then os.cancelTimer(heartbeatTimer) end
                    heartbeatTimer = os.startTimer(rc.HEARTBEAT_INTERVAL)
                end
            elseif msg.body.message_type == "PING" then
                sendStatus()

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
crane.markIdle()

print("Starting connection loop...")

parallel.waitForAny(mainLoop, msgRouter, ecnet2.daemon)

-- Cleanup on exit (Ctrl+T / unexpected shutdown)
crane.done()
ecnet2.close("top")
