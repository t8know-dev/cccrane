-- crane-panel.lua — Crane control panel (ECNet2 server)
--
-- Full-screen terminal GUI for remotely controlling a crane via ECNet2.
-- Displays source/destination position fields, command buttons, crane status,
-- and an operation log.
--
-- Usage: crane-panel
--
-- The panel's ECNet2 address is printed on startup — copy it to
-- crane-remote-config.lua on the crane computer.

local ecnet2 = require "ecnet2"
local random = require "ccryptolib.random"
random.initWithTiming()

------------------------------------------------------------
-- CONSTANTS
------------------------------------------------------------

local TERM_W, TERM_H = term.getSize()

-- Layout rows (1-indexed)
local L = {
    HEADER     = 1,
    SEP1       = 2,
    LABEL      = 3,
    INPUT_SRCX = 4,
    INPUT_SRCY = 5,
    INPUT_DSTX = 6,
    INPUT_DSTY = 7,
    GAP1       = 8,
    BUTTONS    = 9,
    GAP2       = 10,
    STATUS     = 11,
    SEP2       = 12,
    LOG_START  = 13,
}

local LOG_HEIGHT = TERM_H - L.LOG_START  -- remaining rows

local SOURCE_LABEL = "SOURCE (Pickup)"
local DEST_LABEL   = "DEST (Drop)"
local EMPTY_FIELD  = "     "

-- Input field definitions
local FIELDS = {
    src_x = {
        label = "X", x = 5,  y = L.INPUT_SRCX,
        x_label = 3, width = 5, value = "",
    },
    src_y = {
        label = "Y", x = 5,  y = L.INPUT_SRCY,
        x_label = 3, width = 5, value = "",
    },
    dst_x = {
        label = "X", x = 30, y = L.INPUT_DSTX,
        x_label = 28, width = 5, value = "",
    },
    dst_y = {
        label = "Y", x = 30, y = L.INPUT_DSTY,
        x_label = 28, width = 5, value = "",
    },
}

-- Button definitions (label, column start, action name)
local BUTTON_DEFS = {
    { label = "GOTO",  action = "GOTO",  col = 3 },
    { label = "PICKUP", action = "PICKUP", col = 12 },
    { label = "DROP",  action = "DROP",  col = 22 },
    { label = "HOME",  action = "HOME",  col = 30 },
    { label = "EMRG",  action = "EMERGENCY_STOP", col = 39 },
}

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

    activeField = nil,       -- which field is being edited ("src_x", ...)

    -- Operation log: list of { text = str, color = int }
    logLines    = {},

    -- Pending command tracking
    pending         = false,  -- true while waiting for ACK
    pendingSeq      = 0,
    lastSeq         = 0,

    -- Disconnect watchdog
    lastMessageTime = nil,    -- os.epoch("utc") of last received message
    watchdogTimer   = nil,    -- timer ID for periodic disconnect checks
}

local CONNECTION_TIMEOUT = 15  -- seconds without message = disconnected

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
-- HELPERS
------------------------------------------------------------

--- Add a line to the operation log.
--- @param text string
--- @param color number|nil optional text color (default colors.lightGray)
local function addLog(text, color)
    table.insert(panelState.logLines, {
        text = text,
        color = color or colors.lightGray,
    })
    if #panelState.logLines > 50 then
        table.remove(panelState.logLines, 1)
    end
end

--- Format a timestamp for log lines.
local function timestamp()
    local t = os.time()
    local h = math.floor(t / 3600) % 24
    local m = math.floor(t / 60) % 60
    local s = t % 60
    return string.format("[%02d:%02d:%02d]", h, m, s)
end

--- Get the current source and destination coordinate values as numbers.
local function getSrcCoords()
    local x = tonumber(FIELDS.src_x.value)
    local y = tonumber(FIELDS.src_y.value)
    return x, y
end

local function getDstCoords()
    local x = tonumber(FIELDS.dst_x.value)
    local y = tonumber(FIELDS.dst_y.value)
    return x, y
end

------------------------------------------------------------
-- RENDERING
------------------------------------------------------------

--- Draw the header bar with title and connection status.
local function drawHeader()
    term.setCursorPos(1, L.HEADER)
    term.setTextColor(colors.white)

    -- Connection status dot
    if panelState.connected then
        term.setBackgroundColor(colors.green)
    else
        term.setBackgroundColor(colors.red)
    end

    local statusText = panelState.connected and " CONNECTED " or " DISCONNECTED "
    local title = " CRANE CONTROL PANEL "
    local padLen = TERM_W - #title - #statusText

    term.write(title)
    if padLen > 0 then
        term.write(string.rep(" ", padLen))
    end
    term.write(statusText)
    term.setBackgroundColor(colors.black)
end

--- Draw the separator line.
local function drawSep(row, char)
    term.setCursorPos(1, row)
    term.setTextColor(colors.gray)
    term.write(string.rep(char or "-", TERM_W))
end

--- Draw the section labels for source and destination.
local function drawLabels()
    term.setCursorPos(3, L.LABEL)
    term.setTextColor(colors.yellow)
    term.write(SOURCE_LABEL)
    term.setCursorPos(28, L.LABEL)
    term.write(DEST_LABEL)
end

--- Draw a single input field.
--- @param key string field key ("src_x", etc.)
local function drawField(key)
    local f = FIELDS[key]
    local isActive = (panelState.activeField == key)

    -- Label
    term.setCursorPos(f.x_label, f.y)
    term.setTextColor(isActive and colors.white or colors.lightGray)
    term.write(f.label .. ":")

    -- Display value (right-aligned within the field width)
    local display = f.value
    if display == "" then display = EMPTY_FIELD end
    display = string.rep(" ", f.width - #display) .. display

    term.setCursorPos(f.x, f.y)
    if isActive then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
    else
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
    end
    term.write(display)

    -- Reset background
    if isActive then
        term.setBackgroundColor(colors.black)
    end
end

--- Draw all input fields.
local function drawFields()
    for k in pairs(FIELDS) do
        drawField(k)
    end
end

--- Draw command buttons.
local function drawButtons()
    for _, b in ipairs(BUTTON_DEFS) do
        local label = " " .. b.label .. " "
        local bg, fg

        if panelState.connection == nil or b.action == "EMERGENCY_STOP" then
            -- EMERGENCY_STOP is always enabled if connected
            if b.action == "EMERGENCY_STOP" and panelState.connection then
                bg = colors.orange
                fg = colors.white
            elseif b.action == "EMERGENCY_STOP" then
                bg = colors.gray
                fg = colors.gray
            else
                bg = colors.gray
                fg = colors.gray
            end
        elseif b.action == "EMERGENCY_STOP" then
            bg = colors.orange
            fg = colors.white
        else
            bg = colors.blue
            fg = colors.white
        end

        term.setCursorPos(b.col, L.BUTTONS)
        term.setBackgroundColor(bg)
        term.setTextColor(fg)
        term.write(label)
    end
    term.setBackgroundColor(colors.black)
end

--- Draw the status bar.
local function drawStatus()
    term.setCursorPos(2, L.STATUS)
    term.setTextColor(colors.white)

    local status
    if panelState.connection == nil then
        status = "Status: ---"
    elseif panelState.craneError then
        status = "Status: ERROR (" .. panelState.craneErrorMsg .. ")"
    elseif panelState.craneBusy then
        status = "Status: BUSY"
    else
        status = "Status: IDLE"
    end

    local pos = string.format("Pos: (%d, %d)",
        panelState.cranePos[1], panelState.cranePos[2])
    local sticker = panelState.craneSticker and "ON" or "OFF"
    local stickerText = "Sticker: " .. sticker
    local idText = "Crane: " .. panelState.craneId

    local parts = { status, pos, stickerText, idText }
    local line = parts[1]
    for i = 2, #parts do
        if #line + #parts[i] + 3 <= TERM_W then
            line = line .. "  |  " .. parts[i]
        else
            break
        end
    end

    -- Pad to end of line
    term.write(line)
    if #line < TERM_W then
        term.write(string.rep(" ", TERM_W - #line))
    end
end

--- Draw the operation log (last LOG_HEIGHT lines).
local function drawLog()
    local lines = panelState.logLines
    local startIdx = math.max(1, #lines - LOG_HEIGHT + 1)

    for i = 1, LOG_HEIGHT do
        local row = L.LOG_START + i - 1
        if row > TERM_H then break end

        term.setCursorPos(1, row)
        local idx = startIdx + i - 1
        if idx <= #lines then
            local entry = lines[idx]
            term.setTextColor(entry.color)
            local text = entry.text
            if #text > TERM_W then
                text = text:sub(1, TERM_W)
            end
            term.write(text)
            if #text < TERM_W then
                term.write(string.rep(" ", TERM_W - #text))
            end
        else
            term.setTextColor(colors.black)
            term.write(string.rep(" ", TERM_W))
        end
    end
end

--- Full screen redraw.
local function fullRedraw()
    term.clear()
    drawHeader()
    drawSep(L.SEP1, "-")
    drawLabels()
    drawFields()
    drawButtons()
    drawSep(L.SEP2, "-")
    drawStatus()
    drawLog()
    term.setCursorPos(1, TERM_H)
end

--- Redraw only the elements that change frequently.
local function quickRedraw()
    drawHeader()
    drawStatus()
    drawLog()
    drawFields()
    drawButtons()
end

------------------------------------------------------------
-- SENDING COMMANDS
------------------------------------------------------------

--- Send a COMMAND request to the crane.
--- @param command string command name
--- @param params table|nil command parameters
local function sendCommand(command, params)
    if not panelState.connection then
        addLog("Cannot send: not connected", colors.red)
        quickRedraw()
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

    addLog(timestamp() .. " Sending: " .. command)
    local ok = pcall(panelState.connection.send, panelState.connection, msg)
    if not ok then
        addLog("SEND FAILED — connection lost", colors.red)
        panelState.connection = nil
        panelState.connected = false
        panelState.pending = false
    end
    quickRedraw()
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
        addLog(timestamp() .. " Registered: crane " .. panelState.craneId, colors.green)

    elseif body.message_type == "ACK" then
        panelState.pending = false
        local ackStatus = body.status or "?"
        local ackMsg = body.message or ""
        if ackStatus == "ok" then
            addLog(timestamp() .. "  " .. body.command_seq .. " OK", colors.green)
        else
            addLog(timestamp() .. "  " .. body.command_seq .. " ERROR: " .. ackMsg, colors.red)
        end

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

    elseif body.message_type == "CONFIG_RESPONSE" then
        local cfg = body.config or {}
        addLog(timestamp() .. " Config: " .. (cfg.max_x or "?")
            .. "x" .. (cfg.max_y or "?") .. " grid", colors.yellow)
    end
end

------------------------------------------------------------
-- TOUCH / INPUT HANDLING
------------------------------------------------------------

--- Check if a point is within a rectangular region.
local function hitRect(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw - 1 and y >= ry and y <= ry + rh - 1
end

--- Handle mouse click events.
--- @param mx number click x
--- @param my number click y
local function handleTouch(mx, my)
    -- Check input fields
    for key, f in pairs(FIELDS) do
        if hitRect(mx, my, f.x - 1, f.y, f.width + 2, 1) then
            panelState.activeField = key
            drawField(key)
            return
        end
    end

    -- Clicking elsewhere deactivates field
    if panelState.activeField then
        local oldField = panelState.activeField
        panelState.activeField = nil
        drawField(oldField)
    end

    -- Check buttons
    if my == L.BUTTONS and panelState.connection then
        for _, b in ipairs(BUTTON_DEFS) do
            local btnW = #b.label + 2  -- " LABEL " with spaces
            if mx >= b.col and mx < b.col + btnW then
                -- If connected, dispatch action
                if b.action == "GOTO" then
                    local x, y = getSrcCoords()
                    if x and y then
                        sendCommand("GOTO", { x = x, y = y })
                    else
                        addLog("Set source coordinates first", colors.red)
                        quickRedraw()
                    end
                elseif b.action == "PICKUP" then
                    sendCommand("PICKUP")
                elseif b.action == "DROP" then
                    sendCommand("DROP")
                elseif b.action == "HOME" then
                    sendCommand("HOME")
                elseif b.action == "EMERGENCY_STOP" then
                    sendCommand("EMERGENCY_STOP")
                end
                return
            end
        end
    end
end

--- Handle character input (for editing active field).
--- @param char string typed character
local function handleChar(char)
    local f = panelState.activeField
    if not f then return end
    local field = FIELDS[f]
    if not field then return end

    -- Only accept digits
    if char:match("^[0-9]$") and #field.value < field.width then
        field.value = field.value .. char
        drawField(f)
    end
end

--- Handle key events (backspace, enter).
--- @param keyCode number
local function handleKey(keyCode)
    local f = panelState.activeField
    if not f then return end
    local field = FIELDS[f]
    if not field then return end

    if keyCode == keys.enter or keyCode == keys.tab then
        -- Deactivate field
        panelState.activeField = nil
        drawField(f)

        -- Tab to next field
        if keyCode == keys.tab then
            local keys = { "src_x", "src_y", "dst_x", "dst_y" }
            for i, k in ipairs(keys) do
                if k == f then
                    local nextKey = keys[i + 1] or keys[1]
                    panelState.activeField = nextKey
                    drawField(nextKey)
                    break
                end
            end
        end
    elseif keyCode == keys.backspace then
        -- Remove last character
        field.value = field.value:sub(1, -2)
        drawField(f)
    end
end

------------------------------------------------------------
-- MAIN EVENT LOOP
------------------------------------------------------------

local function mainLoop()
    fullRedraw()
    addLog(timestamp() .. " Panel started — waiting for crane...", colors.yellow)
    addLog("Address: " .. (id.address or "unknown"), colors.yellow)
    quickRedraw()

    while true do
        local event, id, p2, p3, ch, dist = os.pullEvent()

        if event == "mouse_click" then
            handleTouch(p2, p3)   -- p2 = x, p3 = y
            -- quickRedraw() is called inside handleTouch/handleChar/handleKey

        elseif event == "char" then
            handleChar(p2)

        elseif event == "key" then
            handleKey(p2)

        elseif event == "ecnet2_request" and id == listener.id then
            if panelState.connection then
                -- Already have a crane — reject
                local dummy = listener:accept("busy", p2)
                addLog(timestamp() .. " Rejected extra connection", colors.yellow)
            else
                local conn = listener:accept("crane_panel_v1.0", p2)
                panelState.connection = conn
                panelState.connected = true
                panelState.pending = false
                panelState.lastMessageTime = os.epoch("utc")
                panelState.watchdogTimer = os.startTimer(CONNECTION_TIMEOUT)

                addLog(timestamp() .. " Crane connected!", colors.green)

                -- Request config
                pcall(conn.send, conn, {
                    type = "request",
                    body = { message_type = "CONFIG_QUERY" },
                })
                addLog(timestamp() .. " Sent config query", colors.lightGray)
            end
            quickRedraw()

        elseif event == "timer" and panelState.connected and id == panelState.watchdogTimer then
            -- Check disconnect watchdog
            local now = os.epoch("utc")
            local elapsed = (now - (panelState.lastMessageTime or now)) / 1000
            if elapsed >= CONNECTION_TIMEOUT then
                addLog(timestamp() .. " Crane disconnected (timeout)", colors.red)
                panelState.connection = nil
                panelState.connected = false
                panelState.craneId = "?"
            else
                -- Restart watchdog
                panelState.watchdogTimer = os.startTimer(CONNECTION_TIMEOUT)
            end
            quickRedraw()

        elseif event == "ecnet2_message" and panelState.connection
               and id == panelState.connection.id then
            handleMessage(p3)
            quickRedraw()
        end
    end
end

------------------------------------------------------------
-- STARTUP
------------------------------------------------------------

print("=== Crane Control Panel ===")
print("ECNet2 address: " .. (id.address or "unknown"))
print("Copy this address to crane-remote-config.lua on the crane.")
print("Waiting for connection...")

parallel.waitForAny(mainLoop, ecnet2.daemon)

-- Cleanup
if panelState.connection then
    pcall(panelState.connection.send, panelState.connection, {
        type = "request",
        body = { message_type = "COMMAND", command = "EMERGENCY_STOP" },
    })
end
ecnet2.close("top")
