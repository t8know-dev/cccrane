-- panel_ui.lua — PixelUI-based crane control panel UI
--
-- A reusable UI module built on top of PixelUI for the crane control panel.
-- Expected to be loaded by crane-panel.lua, which provides ECNet2 logic
-- and business callbacks.
--
-- Usage:
--   local panelUI = require("panel_ui").create({
--       callbacks = {
--           onCommand  = function(action, params) ... end,
--           onFieldChange = function(key, value) ... end,
--           onConnectionRequest = function(request, side, ch, dist) ... end,
--           onMessage = function(msg) ... end,
--           onTimer   = function(timerId) ... end,
--       },
--   })
--   parallel.waitForAny(
--       function() panelUI:run() end,
--       ecnet2.daemon
--   )

local pixelui = require("pixelui")

---@class PanelUI
local PanelUI = {}
PanelUI.__index = PanelUI

local FIELDS = { "src_x", "src_y", "dst_x", "dst_y" }

local FIELD_DEFS = {
    src_x = { col = 6,  row = 4,  labelX = 3, label = "X" },
    src_y = { col = 6,  row = 5,  labelX = 3, label = "Y" },
    dst_x = { col = 31, row = 6,  labelX = 28, label = "X" },
    dst_y = { col = 31, row = 7,  labelX = 28, label = "Y" },
}

local BUTTON_DEFS = {
    { action = "PICKANDDROP",    label = "RUN",  col = 3 },
    { action = "GOTO",           label = "GOTO", col = 9 },
    { action = "HOME",           label = "HOME", col = 16 },
    { action = "EMERGENCY_STOP", label = "EMRG", col = 25 },
}

-- Layout: 1 = header, 2 = sep, 3 = labels, 4-7 = inputs, 8 = gap, 9 = buttons,
--          10 = gap, 11 = status, 12 = sep, 13+ = log
local L = { HEADER = 1, SEP1 = 2, LABEL = 3, INPUTS = { 4, 5, 6, 7 },
            GAP1 = 8, BUTTONS = 9, GAP2 = 10, STATUS = 11, SEP2 = 12, LOG_START = 13 }

local MAX_LOG = 50
local STATUS_W = 16

-- ── Constructor ──────────────────────────────────────────────────

---@param opts table
---@param opts.callbacks table
---@param opts.callbacks.onCommand fun(action:string, params:table|nil)
---@param opts.callbacks.onFieldChange fun(key:string, value:string)
---@param opts.callbacks.onConnectionRequest fun(...)
---@param opts.callbacks.onMessage fun(msg:table)
---@param opts.callbacks.onTimer fun(timerId:number)
---@return PanelUI
function PanelUI.create(opts)
    local self = setmetatable({}, PanelUI)
    opts = opts or {}
    self._callbacks = opts.callbacks or {}

    local TERM_W, TERM_H = term.getSize()
    self._termW = TERM_W
    self._logRows = math.max(1, TERM_H - L.LOG_START + 1)

    self._app = pixelui.create({ background = colors.black, rootBorder = { color = colors.gray } })
    self._root = self._app:getRoot()

    self._state = {
        connected     = false,
        registered    = false,
        pending       = false,
        cranePos      = { 0, 0 },
        craneSticker  = false,
        craneBusy     = false,
        craneError    = false,
        craneErrorMsg = "",
        craneId       = "?",
        logLines      = {},
    }

    self:_buildHeader()
    self:_buildSeparators()
    self:_buildLabels()
    self:_buildFields()
    self:_buildButtons()
    self:_buildStatus()
    self:_buildLogArea()
    self:_patchTextBoxTab()
    self:_patchRootEvents()
    self:_hookFieldChanges()

    self:_updateButtons()
    self:_updateStatus()

    return self
end

-- ── Widget Builders ───────────────────────────────────────────────

function PanelUI:_buildHeader()
    local a, r = self._app, self._root
    self._header = {
        title = a:createLabel({ x = 1, y = L.HEADER, width = self._termW - STATUS_W,
                                height = 1, text = " CRANE CONTROL PANEL ",
                                align = "left", bg = colors.black, fg = colors.white }),
        status = a:createLabel({ x = self._termW - STATUS_W + 1, y = L.HEADER,
                                 width = STATUS_W, height = 1, text = " DISCONNECTED ",
                                 align = "center", bg = colors.red, fg = colors.white }),
    }
    r:addChild(self._header.title)
    r:addChild(self._header.status)
end

function PanelUI:_buildSeparators()
    local a, r, w = self._app, self._root, self._termW
    local sepText = string.rep("-", w)
    self._sep1 = a:createLabel({ x = 1, y = L.SEP1, width = w, height = 1,
                                  text = sepText, bg = colors.black, fg = colors.gray })
    r:addChild(self._sep1)
    self._sep2 = a:createLabel({ x = 1, y = L.SEP2, width = w, height = 1,
                                  text = sepText, bg = colors.black, fg = colors.gray })
    r:addChild(self._sep2)
end

function PanelUI:_buildLabels()
    local a, r = self._app, self._root
    self._sourceLabel = a:createLabel({ x = 3, y = L.LABEL, width = 18, height = 1,
                                         text = "SOURCE (Pickup)", bg = colors.black, fg = colors.yellow })
    r:addChild(self._sourceLabel)
    self._destLabel = a:createLabel({ x = 28, y = L.LABEL, width = 14, height = 1,
                                       text = "DEST (Drop)", bg = colors.black, fg = colors.yellow })
    r:addChild(self._destLabel)
end

function PanelUI:_buildFields()
    local a, r = self._app, self._root
    self._fields = {}
    for _, key in ipairs(FIELDS) do
        local def = FIELD_DEFS[key]
        local label = a:createLabel({ x = def.labelX, y = def.row, width = 2, height = 1,
                                       text = def.label .. ":", bg = colors.black, fg = colors.lightGray })
        r:addChild(label)
        local tb = a:createTextBox({ x = def.col, y = def.row, width = 5, height = 1,
                                      numericOnly = true, maxLength = 5,
                                      placeholder = "     ", placeholderColor = colors.gray,
                                      bg = colors.black, fg = colors.white,
                                      border = { color = colors.gray } })
        r:addChild(tb)
        self._fields[key] = { tb = tb, label = label }
    end
end

function PanelUI:_buildButtons()
    local a, r = self._app, self._root
    self._btnMap = {}
    self._btnList = {}
    for _, bdef in ipairs(BUTTON_DEFS) do
        local w = #bdef.label + 2
        local btn = a:createButton({ x = bdef.col, y = L.BUTTONS, width = w, height = 1,
                                      label = " " .. bdef.label .. " ",
                                      bg = colors.blue, fg = colors.white })
        r:addChild(btn)
        local meta = { widget = btn, action = bdef.action }
        self._btnMap[bdef.action] = meta
        self._btnList[#self._btnList + 1] = meta
        btn:setOnClick(function() self:_onClick(bdef.action) end)
    end
end

function PanelUI:_buildStatus()
    local a, r = self._app, self._root
    self._statusLabel = a:createLabel({ x = 2, y = L.STATUS, width = self._termW - 3,
                                         height = 1, text = "Status: ---",
                                         bg = colors.black, fg = colors.white })
    r:addChild(self._statusLabel)
end

function PanelUI:_buildLogArea()
    local a, r = self._app, self._root
    self._logWidgets = {}
    for row = 0, self._logRows - 1 do
        local lw = a:createLabel({ x = 1, y = L.LOG_START + row, width = self._termW,
                                    height = 1, text = "", bg = colors.black, fg = colors.black })
        r:addChild(lw)
        self._logWidgets[row + 1] = lw
    end
end

-- ── Tab Key Patch ─────────────────────────────────────────────────
-- TextBox consumes Tab internally (inserts a literal tab). We patch
-- each field's TextBox to intercept Tab and cycle focus instead.

function PanelUI:_patchTextBoxTab()
    for _, meta in pairs(self._fields) do
        local tb = meta.tb
        local origHandle = tb.handleEvent
        local self_ = self
        function tb:handleEvent(event, ...)
            if event == "key" then
                local keyCode = ...
                if keyCode == keys.tab then
                    return self_:_cycleFocus()
                end
            end
            return origHandle(self, event, ...)
        end
    end
end

function PanelUI:_cycleFocus()
    local app = self._app
    local focus = app:getFocus()
    for i, key in ipairs(FIELDS) do
        local meta = self._fields[key]
        if meta and meta.tb == focus then
            local nextKey = FIELDS[i % #FIELDS + 1]
            local nextMeta = self._fields[nextKey]
            if nextMeta then app:setFocus(nextMeta.tb) end
            return true
        end
    end
    local first = self._fields[FIELDS[1]]
    if first then app:setFocus(first.tb) end
    return true
end

-- ── Root Event Patch ──────────────────────────────────────────────
-- PixelUI dispatches unrecognised events (ecnet2_request, ecnet2_message,
-- timer, term_resize) through root:handleEvent. We intercept them here
-- and forward to the application callbacks.

function PanelUI:_patchRootEvents()
    local self_ = self
    local orig = self._root.handleEvent
    function self._root:handleEvent(event, ...)
        if event == "ecnet2_request" then
            local rid, req = ...
            if self_._callbacks.onConnectionRequest then
                self_._callbacks.onConnectionRequest(req)
            end
            return true
        end
        if event == "ecnet2_message" then
            local cid, addr, msg = ...
            if self_._callbacks.onMessage then
                self_._callbacks.onMessage(cid, msg)
            end
            return true
        end
        if event == "timer" then
            local tid = ...
            if self_._callbacks.onTimer then
                self_._callbacks.onTimer(tid)
            end
            return true
        end
        if event == "term_resize" then
            self_:_onResize()
            -- fall through to orig so PixelUI also gets it
        end
        return orig and orig(self, event, ...) or false
    end
end

-- ── Resize ────────────────────────────────────────────────────────

function PanelUI:_onResize()
    local W, H = term.getSize()
    self._termW = W
    local newRows = math.max(1, H - L.LOG_START + 1)

    if newRows ~= self._logRows then
        for _, w in ipairs(self._logWidgets) do w.visible = false end
        self._logWidgets = {}
        self._logRows = newRows
        for row = 0, self._logRows - 1 do
            local lw = self._app:createLabel({ x = 1, y = L.LOG_START + row, width = W,
                                                height = 1, text = "", bg = colors.black, fg = colors.black })
            self._root:addChild(lw)
            self._logWidgets[row + 1] = lw
        end
        self:_refreshLog()
    end

    -- Fix header status position
    if self._header and self._header.status then
        self._header.status:setPosition(W - STATUS_W + 1, L.HEADER)
    end
    -- Fix separator widths
    local sepText = string.rep("-", W)
    if self._sep1 then self._sep1:setText(sepText) self._sep1:setSize(W, 1) end
    if self._sep2 then self._sep2:setText(sepText) self._sep2:setSize(W, 1) end
end

-- ── Field Change Hook ─────────────────────────────────────────────

function PanelUI:_hookFieldChanges()
    for key, meta in pairs(self._fields) do
        meta.tb:setOnChange(function(_, text)
            if self._callbacks.onFieldChange then
                self._callbacks.onFieldChange(key, text or "")
            end
        end)
    end
end

-- ── Button Click Dispatch ─────────────────────────────────────────

function PanelUI:_onClick(action)
    local cb = self._callbacks.onCommand
    if not cb then return end

    if action == "GOTO" then
        local x, y = self:getSrc()
        if x and y then return cb("GOTO", { x = x, y = y }) end
        cb("__ERROR", "Set source coordinates first")

    elseif action == "PICKANDDROP" then
        local sx, sy = self:getSrc()
        local dx, dy = self:getDst()
        if sx and sy and dx and dy then
            return cb("PICKANDDROP", { src = { x = sx, y = sy }, dst = { x = dx, y = dy } })
        end
        cb("__ERROR", "Set source AND destination coordinates first")

    elseif action == "HOME" then
        cb("HOME")
    elseif action == "EMERGENCY_STOP" then
        cb("EMERGENCY_STOP")
    end
end

-- ── Public API ────────────────────────────────────────────────────

function PanelUI:run()
    self._app:run()
end

function PanelUI:stop()
    local a = self._app
    if a and a.stop then a:stop() end
end

---@param connected boolean
---@param craneId string|nil
function PanelUI:setConnected(connected, craneId)
    self._state.connected = connected
    if connected and craneId then self._state.craneId = craneId end
    self:_redrawHeader()
    self:_updateButtons()
end

---@param registered boolean
function PanelUI:setRegistered(registered)
    self._state.registered = registered
    self:_redrawHeader()
    self:_updateButtons()
end

---@param pending boolean
function PanelUI:setPending(pending)
    self._state.pending = pending
    self:_updateButtons()
    self:_updateStatus()
end

---@param opts {pos?:number[], sticker?:boolean, busy?:boolean, error?:boolean, errorMsg?:string}
function PanelUI:setCraneStatus(opts)
    opts = opts or {}
    if opts.pos       then self._state.cranePos      =     opts.pos    end
    if opts.sticker   ~= nil then self._state.craneSticker = opts.sticker end
    if opts.busy      ~= nil then self._state.craneBusy    = opts.busy    end
    if opts.error     ~= nil then self._state.craneError   = opts.error   end
    if opts.errorMsg  ~= nil then self._state.craneErrorMsg= opts.errorMsg end
    self:_updateStatus()
end

---@param key "src_x"|"src_y"|"dst_x"|"dst_y"
---@return string
function PanelUI:getField(key)
    local m = self._fields[key]
    return m and m.tb:getText() or ""
end

---@param key string
---@param value string
function PanelUI:setField(key, value)
    local m = self._fields[key]
    if m then m.tb:setText(tostring(value)) end
end

function PanelUI:getSrc()
    return tonumber(self:getField("src_x")), tonumber(self:getField("src_y"))
end

function PanelUI:getDst()
    return tonumber(self:getField("dst_x")), tonumber(self:getField("dst_y"))
end

---@param text string
---@param color number|nil
function PanelUI:addLogLine(text, color)
    local lines = self._state.logLines
    table.insert(lines, { text = text, color = color or colors.lightGray })
    if #lines > MAX_LOG then table.remove(lines, 1) end
    self:_refreshLog()
end

-- ── Internal Render Updates ───────────────────────────────────────

function PanelUI:_redrawHeader()
    local h = self._header
    if not h then return end
    local st, bg
    if self._state.connected and self._state.registered then
        if self._state.craneId and self._state.craneId ~= "?" then
            st = " " .. self._state.craneId .. " "
        else
            st = " CONNECTED "
        end
        bg = colors.green
    else
        st = " DISCONNECTED "
        bg = colors.red
    end
    if st ~= h.status.text then
        h.status:setText(st)
    end
    h.status.bg = bg
end

function PanelUI:_updateButtons()
    local hasCrane = self._state.connected and self._state.registered
    local blocked = self._state.pending
    for _, m in ipairs(self._btnList) do
        local btn = m.widget
        if m.action == "EMERGENCY_STOP" then
            btn.bg = hasCrane and colors.orange or colors.gray
            btn.fg = colors.white
        elseif not hasCrane or blocked then
            btn.bg = colors.gray
            btn.fg = colors.gray
        else
            btn.bg = colors.blue
            btn.fg = colors.white
        end
    end
end

function PanelUI:_updateStatus()
    local s = self._state
    local sl = self._statusLabel
    if not sl then return end

    local status
    if not s.connected then
        status = "Status: ---"
    elseif s.craneError then
        status = "Status: ERROR (" .. s.craneErrorMsg .. ")"
    elseif s.pending then
        status = "Status: PENDING"
    elseif s.craneBusy then
        status = "Status: BUSY"
    else
        status = "Status: IDLE"
    end

    local pos = string.format("Pos: (%d, %d)", s.cranePos[1], s.cranePos[2])
    local parts = { status, pos, "Sticker: " .. (s.craneSticker and "ON" or "OFF"), "Crane: " .. s.craneId }
    local line = parts[1]
    for i = 2, #parts do
        if #line + #parts[i] + 3 <= sl.width then
            line = line .. "  |  " .. parts[i]
        else
            break
        end
    end
    sl:setText(line)
end

function PanelUI:_refreshLog()
    local lines = self._state.logLines
    local n = #self._logWidgets
    if n == 0 then return end
    local start = math.max(1, #lines - n + 1)
    for i = 1, n do
        local w = self._logWidgets[i]
        local idx = start + i - 1
        if idx <= #lines then
            w:setText(lines[idx].text)
            w.fg = lines[idx].color
        else
            w:setText("")
            w.fg = colors.black
        end
    end
end

return PanelUI
