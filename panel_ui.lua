-- panel_ui.lua — PixelUI-based crane control panel UI (v2)
--
-- Redesigned with visual hierarchy: bordered frames, progress bar,
-- loading indicator, and color-coded status elements.

local pixelui = require("pixelui")

---@class PanelUI
local PanelUI = {}
PanelUI.__index = PanelUI

local FIELDS = { "src_x", "src_y", "dst_x", "dst_y" }

local FIELD_DEFS = {
    src_x = { col = 3,  row = 2, label = "X", section = "source" },
    src_y = { col = 12, row = 2, label = "Y", section = "source" },
    dst_x = { col = 3,  row = 2, label = "X", section = "dest" },
    dst_y = { col = 12, row = 2, label = "Y", section = "dest" },
}

local BUTTON_DEFS = {
    { action = "PICKANDDROP", label = "RUN",  key = "run" },
    { action = "GOTO",        label = "GOTO", key = "goto" },
    { action = "HOME",        label = "HOME", key = "home" },
    { action = "EMERGENCY_STOP", label = "EMRG STOP", key = "emrg" },
}

local MAX_LOG = 50

-- ── Color palette ────────────────────────────────────────────────

local C = {
    bgDark    = colors.black,
    bgPanel   = colors.gray,
    bgBtn     = colors.blue,
    bgEmrg    = colors.red,
    fgWhite   = colors.white,
    fgLight   = colors.lightGray,
    fgGray    = colors.gray,
    fgYellow  = colors.yellow,
    fgCyan    = colors.cyan,
    fgGreen   = colors.green,
    fgRed     = colors.red,
    fgOrange  = colors.orange,
    border    = colors.lightGray,
    separator = colors.gray,
    ok        = colors.green,
    warn      = colors.yellow,
    err       = colors.red,
}

-- ── Constructor ──────────────────────────────────────────────────

function PanelUI.create(opts)
    local self = setmetatable({}, PanelUI)
    opts = opts or {}
    self._callbacks = opts.callbacks or {}

    local TERM_W, TERM_H = term.getSize()
    self._termW = TERM_W
    self._termH = TERM_H

    self._app = pixelui.create({
        background = C.bgDark,
        rootBorder = { color = C.separator },
    })
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
        gridMaxX      = 100,
        gridMaxY      = 100,
        severity      = "idle",
        logLines      = {},
    }

    self:_calcLayout()
    self:_buildHeader()
    self:_buildSourcePanel()
    self:_buildDestPanel()
    self:_buildProgressBar()
    self:_buildButtons()
    self:_buildStatusFrame()
    self:_buildLogArea()
    -- Loading visual handled by status dot + text, no physical ring widget

    self:_patchTextBoxTab()
    self:_patchRootEvents()
    self:_hookFieldChanges()

    self:_updateButtons()
    self:_updateStatus()

    return self
end

-- ── Layout Calculator ────────────────────────────────────────────

function PanelUI:_calcLayout()
    -- 1=header, 2=sep, 3-5=source+dest(3 rows w/ padding),
    -- 6=progress, 7=gap, 8-10=buttons(3 rows tall),
    -- 11=gap, 12-13=status(2 rows), 14+=log
    self._L = {
        HEADER    = 1,
        SEP1      = 2,
        INPUTS    = 3,     -- Source/Dest frame start (3 rows: title + pad + fields)
        INPUT_END = 5,
        PROGRESS  = 6,
        GAP_BTN   = 7,
        BUTTONS   = 8,     -- 3 rows tall (rows 8,9,10)
        GAP_BTN2  = 11,
        STATUS    = 12,
        STATUS_END= 13,
        LOG_START = 14,
    }
    self._logRows = 6  -- fixed 6 log lines (frame = 7 rows)
end

-- ── Widget Builders ──────────────────────────────────────────────

function PanelUI:_buildHeader()
    local a, r, W = self._app, self._root, self._termW
    local L = self._L

    -- Full-width header with border bottom only
    self._headerFrame = a:createFrame({
        x = 1, y = L.HEADER, width = W, height = 1,
        bg = C.bgDark,
        border = nil,
    })
    r:addChild(self._headerFrame)

    -- Status dot + text
    self._headerDot = a:createLabel({
        x = 1, y = L.HEADER,
        width = 3,
        height = 1,
        text = "  @",
        bg = C.bgDark,
        fg = C.fgRed,
    })
    r:addChild(self._headerDot)

    self._headerStatus = a:createLabel({
        x = 4, y = L.HEADER,
        width = 14,
        height = 1,
        text = "DISCONNECTED",
        align = "left",
        bg = C.bgDark,
        fg = C.fgGray,
    })
    r:addChild(self._headerStatus)

    self._headerTitle = a:createLabel({
        x = 19, y = L.HEADER,
        width = 30,
        height = 1,
        text = "CRANE CONTROL PANEL",
        align = "left",
        bg = C.bgDark,
        fg = C.fgWhite,
    })
    r:addChild(self._headerTitle)

    self._headerId = a:createLabel({
        x = W - 14, y = L.HEADER,
        width = 14,
        height = 1,
        text = "",
        align = "right",
        bg = C.bgDark,
        fg = C.fgCyan,
    })
    r:addChild(self._headerId)
end

function PanelUI:_buildSourcePanel()
    local a, r = self._app, self._root
    local L = self._L
    local W = self._termW

    local panW = math.floor((W - 3) / 2)  -- left half minus gap
    local height = 3                      -- 1 title + 1 pad + 1 fields

    self._sourceFrame = a:createFrame({
        x = 1, y = L.INPUTS,
        width = panW, height = height,
        bg = C.bgPanel,
        border = { color = C.border },
    })
    r:addChild(self._sourceFrame)

    -- Section title row
    self._sourceTitle = a:createLabel({
        x = 2, y = L.INPUTS,
        width = panW - 5,
        height = 1,
        text = "SOURCE (Pickup)",
        bg = C.bgPanel,
        fg = C.fgYellow,
    })
    r:addChild(self._sourceTitle)

    -- X field (padded down by 1)
    local lblX = a:createLabel({
        x = 2, y = L.INPUTS + 2,
        width = 2,
        height = 1,
        text = "X:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblX)

    local tbSrcX = a:createTextBox({
        x = 4, y = L.INPUTS + 2,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbSrcX)

    -- Y field (padded down by 1)
    local lblY = a:createLabel({
        x = 12, y = L.INPUTS + 2,
        width = 2,
        height = 1,
        text = "Y:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblY)

    local tbSrcY = a:createTextBox({
        x = 14, y = L.INPUTS + 2,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbSrcY)

    -- Current position preview (padded down by 1)
    self._srcPreview = a:createLabel({
        x = 22, y = L.INPUTS + 2,
        width = panW - 23,
        height = 1,
        text = "crn: (—, —)",
        bg = C.bgPanel,
        fg = C.fgCyan,
    })
    r:addChild(self._srcPreview)

    self._fields = {
        src_x = { tb = tbSrcX, label = lblX },
        src_y = { tb = tbSrcY, label = lblY },
    }
end

function PanelUI:_buildDestPanel()
    local a, r = self._app, self._root
    local L = self._L
    local W = self._termW

    local panW = math.floor((W - 3) / 2)
    local panX = W - panW
    local height = 3                      -- 1 title + 1 pad + 1 fields

    self._destFrame = a:createFrame({
        x = panX, y = L.INPUTS,
        width = panW, height = height,
        bg = C.bgPanel,
        border = { color = C.border },
    })
    r:addChild(self._destFrame)

    -- Section title
    self._destTitle = a:createLabel({
        x = panX + 2, y = L.INPUTS,
        width = panW - 5,
        height = 1,
        text = "DEST (Drop)",
        bg = C.bgPanel,
        fg = C.fgYellow,
    })
    r:addChild(self._destTitle)

    -- X field (padded down by 1)
    local lblX = a:createLabel({
        x = panX + 2, y = L.INPUTS + 2,
        width = 2,
        height = 1,
        text = "X:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblX)

    local tbDstX = a:createTextBox({
        x = panX + 4, y = L.INPUTS + 2,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbDstX)

    -- Y field (padded down by 1)
    local lblY = a:createLabel({
        x = panX + 12, y = L.INPUTS + 2,
        width = 2,
        height = 1,
        text = "Y:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblY)

    local tbDstY = a:createTextBox({
        x = panX + 14, y = L.INPUTS + 2,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbDstY)

    -- Current position preview (padded down by 1)
    self._dstPreview = a:createLabel({
        x = panX + 22, y = L.INPUTS + 2,
        width = panW - 23,
        height = 1,
        text = "crn: (—, —)",
        bg = C.bgPanel,
        fg = C.fgCyan,
    })
    r:addChild(self._dstPreview)

    self._fields.dst_x = { tb = tbDstX, label = lblX }
    self._fields.dst_y = { tb = tbDstY, label = lblY }
end

function PanelUI:_buildProgressBar()
    local a, r = self._app, self._root
    local W = self._termW
    local L = self._L

    self._progressBar = a:createProgressBar({
        x = 1, y = L.PROGRESS,
        width = W - 1,
        height = 1,
        min = 0,
        max = 100,
        value = 0,
        label = "(—, —)",
        showPercent = true,
        bg = C.bgDark,
        fg = C.fgWhite,
        trackColor = C.bgPanel,
        fillColor = C.ok,
        border = { color = C.border },
    })
    r:addChild(self._progressBar)
end

function PanelUI:_buildButtons()
    local a, r = self._app, self._root
    local L = self._L

    self._btnMap = {}
    self._btnList = {}

    -- RUN
    local runBtn = a:createButton({
        x = 2, y = L.BUTTONS,
        width = 7, height = 3,
        label = "\n  RUN  ",
        bg = C.bgBtn, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(runBtn)
    self._btnMap["PICKANDDROP"] = { widget = runBtn, action = "PICKANDDROP" }
    self._btnList[#self._btnList + 1] = self._btnMap["PICKANDDROP"]
    runBtn:setOnClick(function() self:_onClick("PICKANDDROP") end)

    -- GOTO
    local gotoBtn = a:createButton({
        x = 10, y = L.BUTTONS,
        width = 8, height = 3,
        label = "\n  GOTO  ",
        bg = C.bgBtn, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(gotoBtn)
    self._btnMap["GOTO"] = { widget = gotoBtn, action = "GOTO" }
    self._btnList[#self._btnList + 1] = self._btnMap["GOTO"]
    gotoBtn:setOnClick(function() self:_onClick("GOTO") end)

    -- HOME
    local homeBtn = a:createButton({
        x = 19, y = L.BUTTONS,
        width = 8, height = 3,
        label = "\n  HOME  ",
        bg = C.bgBtn, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(homeBtn)
    self._btnMap["HOME"] = { widget = homeBtn, action = "HOME" }
    self._btnList[#self._btnList + 1] = self._btnMap["HOME"]
    homeBtn:setOnClick(function() self:_onClick("HOME") end)

    -- EMRG STOP (right aligned, wider, red)
    local emrgBtn = a:createButton({
        x = self._termW - 12, y = L.BUTTONS,
        width = 11, height = 3,
        label = "\n  EMRG  ",
        bg = C.bgEmrg, fg = C.fgWhite,
        border = { color = C.fgOrange },
    })
    r:addChild(emrgBtn)
    self._btnMap["EMERGENCY_STOP"] = { widget = emrgBtn, action = "EMERGENCY_STOP" }
    self._btnList[#self._btnList + 1] = self._btnMap["EMERGENCY_STOP"]
    emrgBtn:setOnClick(function() self:_onClick("EMERGENCY_STOP") end)
end

function PanelUI:_buildStatusFrame()
    local a, r = self._app, self._root
    local W = self._termW
    local L = self._L

    self._statusFrame = a:createFrame({
        x = 1, y = L.STATUS,
        width = W - 1,
        height = 2,
        bg = C.bgPanel,
        border = { color = C.border },
    })
    r:addChild(self._statusFrame)

    -- Title tab in the frame (we approximate with a label at top-left)
    self._statusTitle = a:createLabel({
        x = 2, y = L.STATUS,
        width = 8,
        height = 1,
        text = " STATUS ",
        bg = C.bgPanel,
        fg = C.fgYellow,
    })
    r:addChild(self._statusTitle)

    -- Status line inside frame
    self._statusDot = a:createLabel({
        x = 2, y = L.STATUS + 1,
        width = 2,
        height = 1,
        text = "@",
        bg = C.bgPanel,
        fg = C.ok,
    })
    r:addChild(self._statusDot)

    self._statusLabel = a:createLabel({
        x = 4, y = L.STATUS + 1,
        width = W - 8,
        height = 1,
        text = "IDLE",
        bg = C.bgPanel,
        fg = C.fgWhite,
    })
    r:addChild(self._statusLabel)
end

function PanelUI:_buildLogArea()
    local a, r = self._app, self._root
    local W = self._termW
    local L = self._L

    self._logFrame = a:createFrame({
        x = 1, y = L.LOG_START,
        width = W - 1,
        height = self._logRows + 1,
        bg = C.bgDark,
        border = { color = C.border },
    })
    r:addChild(self._logFrame)

    self._logTitle = a:createLabel({
        x = 2, y = L.LOG_START,
        width = 20,
        height = 1,
        text = " OPERATION LOG ",
        bg = C.bgDark,
        fg = C.fgYellow,
    })
    r:addChild(self._logTitle)

    -- Pre-allocated log line widgets (inside frame area)
    self._logWidgets = {}
    for row = 0, self._logRows - 1 do
        local lw = a:createLabel({
            x = 2,
            y = L.LOG_START + 1 + row,
            width = W - 4,
            height = 1,
            text = "",
            bg = C.bgDark,
            fg = C.bgDark,
        })
        r:addChild(lw)
        self._logWidgets[row + 1] = lw
    end
end

-- ── Tab Key Patch ─────────────────────────────────────────────────

function PanelUI:_patchTextBoxTab()
    for _, meta in pairs(self._fields) do
        local tb = meta.tb
        local orig = tb.handleEvent
        local self_ = self
        function tb:handleEvent(event, ...)
            if event == "key" then
                local kc = ...
                if kc == keys.tab then return self_:_cycleFocus() end
            end
            return orig(self, event, ...)
        end
    end
end

function PanelUI:_cycleFocus()
    local app = self._app
    local focus = app:getFocus()
    for i, key in ipairs(FIELDS) do
        local m = self._fields[key]
        if m and m.tb == focus then
            local nk = FIELDS[i % #FIELDS + 1]
            local nm = self._fields[nk]
            if nm then app:setFocus(nm.tb) end
            return true
        end
    end
    local first = self._fields[FIELDS[1]]
    if first then app:setFocus(first.tb) end
    return true
end

-- ── Root Event Patch ──────────────────────────────────────────────

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
        end
        return orig and orig(self, event, ...) or false
    end
end

-- ── Resize ────────────────────────────────────────────────────────

function PanelUI:_onResize()
    local W, H = term.getSize()
    self._termW = W
    self._termH = H

    self:_calcLayout()
    local L = self._L

    if self._headerId then
        self._headerId:setPosition(W - 14, L.HEADER)
    end

    local emrg = self._btnMap and self._btnMap["EMERGENCY_STOP"]
    if emrg then
        emrg.widget:setPosition(W - 12, L.BUTTONS)
    end

    if self._progressBar then
        self._progressBar:setSize(W - 1, 1)
    end

    -- Resize log frame (6 lines + 1 for title = 7)
    if self._logFrame then
        self._logFrame:setSize(W - 1, self._logRows + 1)
    end
    -- Rebuild log widgets if needed
    if #self._logWidgets ~= self._logRows then
        for _, w in ipairs(self._logWidgets) do w.visible = false end
        self._logWidgets = {}
        for row = 0, self._logRows - 1 do
            local lw = self._app:createLabel({
                x = 2,
                y = L.LOG_START + 1 + row,
                width = W - 4,
                height = 1,
                text = "",
                bg = C.bgDark,
                fg = C.bgDark,
            })
            self._root:addChild(lw)
            self._logWidgets[row + 1] = lw
        end
        self:_refreshLog()
    end
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

function PanelUI:getApp()
    return self._app
end

---@param connected boolean
---@param craneId string|nil
function PanelUI:setConnected(connected, craneId)
    self._state.connected = connected
    if connected and craneId then self._state.craneId = craneId end
    self:_redrawHeader()
    self:_updateButtons()
end

function PanelUI:setRegistered(registered)
    self._state.registered = registered
    self:_redrawHeader()
    self:_updateButtons()
end

function PanelUI:setPending(pending)
    self._state.pending = pending
    self:showLoading(pending)
    self:_updateButtons()
    self:_updateStatus()
end

---@param opts {pos?:number[], sticker?:boolean, busy?:boolean, error?:boolean, errorMsg?:string}
function PanelUI:setCraneStatus(opts)
    opts = opts or {}
    if opts.pos       then self._state.cranePos   = opts.pos    end
    if opts.sticker   ~= nil then self._state.craneSticker = opts.sticker end
    if opts.busy      ~= nil then
        self._state.craneBusy = opts.busy
        self._state.severity = opts.busy and "busy" or self._state.craneError and "error" or "idle"
    end
    if opts.error     ~= nil then
        self._state.craneError = opts.error
        if opts.error then self._state.severity = "error" end
    end
    if opts.errorMsg  ~= nil then self._state.craneErrorMsg = opts.errorMsg end
    self:_updateStatus()
    self:_updatePreview()
    self:_updateProgress()
end

function PanelUI:setGridSize(maxX, maxY)
    self._state.gridMaxX = maxX or 100
    self._state.gridMaxY = maxY or 100
    if self._progressBar then
        self._progressBar:setRange(0, self._state.gridMaxX)
    end
    self:_updateProgress()
end

--- Show or hide the pending loading indicator.
--- Visual feedback is handled by the status dot in the status frame.
---@param visible boolean
function PanelUI:showLoading(visible)
    -- Visual loading state is shown via the status dot/status text
    -- (updated automatically by setPending/setCraneStatus)
end

---@param key "src_x"|"src_y"|"dst_x"|"dst_y"
---@return string
function PanelUI:getField(key)
    local m = self._fields[key]
    return m and m.tb:getText() or ""
end

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
    table.insert(lines, { text = text, color = color or C.fgLight })
    if #lines > MAX_LOG then table.remove(lines, 1) end
    self:_refreshLog()
end

function PanelUI:clearFields()
    for _, key in ipairs(FIELDS) do
        local m = self._fields[key]
        if m then m.tb:setText("") end
    end
end

-- ── Internal Render Updates ───────────────────────────────────────

function PanelUI:_redrawHeader()
    local connected = self._state.connected and self._state.registered
    self._headerDot.fg = connected and C.ok or C.fgRed
    self._headerDot:setText("  @")
    self._headerStatus:setText(connected and "CONNECTED" or "DISCONNECTED")
    self._headerStatus.fg = connected and C.ok or C.fgGray
    self._headerId:setText(connected and ("[" .. self._state.craneId .. "]") or "")
    self._headerId.fg = connected and C.fgCyan or C.bgDark
end

function PanelUI:_updateButtons()
    local enabled = self._state.connected and self._state.registered
    local blocked = self._state.pending
    for _, m in ipairs(self._btnList) do
        local btn = m.widget
        if m.action == "EMERGENCY_STOP" then
            btn.bg = enabled and C.bgEmrg or C.bgPanel
            btn.fg = C.fgWhite
        elseif not enabled or blocked then
            btn.bg = C.bgPanel
            btn.fg = C.fgGray
        else
            btn.bg = C.bgBtn
            btn.fg = C.fgWhite
        end
    end
end

function PanelUI:_updateStatus()
    local s = self._state
    local sl = self._statusLabel
    if not sl then return end

    local sev = s.severity
    local status, dotColor

    if not s.connected then
        status = "DISCONNECTED"
        dotColor = C.fgRed
        sev = "disconnected"
    elseif s.craneError then
        status = "ERROR"
        dotColor = C.fgRed
        -- Append error message if space allows
        if s.craneErrorMsg and #s.craneErrorMsg > 0 then
            status = "ERROR: " .. s.craneErrorMsg
        end
        sev = "error"
    elseif s.pending then
        status = "PENDING"
        dotColor = C.fgOrange
        sev = "pending"
    elseif s.craneBusy then
        status = "BUSY"
        dotColor = C.fgOrange
        sev = "busy"
    else
        status = "IDLE"
        dotColor = C.ok
        sev = "idle"
    end

    -- Update severity for later
    self._state.severity = sev
    self._statusDot.fg = dotColor

    -- Build compact status line
    local pos = string.format("Pos: (%d,%d)", s.cranePos[1], s.cranePos[2])
    local sticker = s.craneSticker and "Sticker:ON" or "Sticker:OFF"
    local grid = string.format("%dx%d", s.gridMaxX, s.gridMaxY)
    local line = status .. "  |  " .. pos .. "  |  " .. sticker .. "  |  " .. grid
    sl:setText(line)
end

function PanelUI:_updatePreview()
    local x, y = self._state.cranePos[1], self._state.cranePos[2]
    local text = string.format("crn: (%d,%d)", x, y)
    if self._srcPreview then self._srcPreview:setText(text) end
    if self._dstPreview then self._dstPreview:setText(text) end
end

function PanelUI:_updateProgress()
    local pb = self._progressBar
    if not pb then return end
    local x = self._state.cranePos[1]
    local maxX = self._state.gridMaxX
    pb:setValue(x)
    pb:setLabel(string.format("(%d, %d)", self._state.cranePos[1], self._state.cranePos[2]))
    -- Color based on position
    local pct = maxX > 0 and (x / maxX) or 0
    if pct > 0.9 then
        pb:setColors(C.bgPanel, C.fgRed, C.fgWhite)
    elseif pct > 0.7 then
        pb:setColors(C.bgPanel, C.fgOrange, C.fgWhite)
    else
        pb:setColors(C.bgPanel, C.ok, C.fgWhite)
    end
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
            w.fg = C.bgDark
        end
    end
    -- Update log title with count
    if self._logTitle then
        self._logTitle:setText(" OPERATION LOG (" .. #lines .. ") ")
    end
end

return PanelUI
