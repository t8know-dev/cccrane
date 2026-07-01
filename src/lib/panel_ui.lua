-- panel_ui.lua — PixelUI-based crane control panel UI (v2)
--
-- Redesigned with visual hierarchy: bordered frames, status indicators,
-- loading indicator, and color-coded status elements.

local pixelui = require("lib.pixelui")

---@class PanelUI
local PanelUI = {}
PanelUI.__index = PanelUI

local FIELDS = { "src_x", "src_y", "dst_x", "dst_y" }

local MAX_LOG = 50

local PICKUP_POINTS_FILE = "/cccrane/data/pickup_points.lua"
local DROP_POINTS_FILE = "/cccrane/data/drop_points.lua"

-- ── Color palette ────────────────────────────────────────────────

local C = {
    bgDark    = colors.black,
    bgPanel   = colors.gray,
    bgBtn     = colors.blue,
    bgEmrg    = colors.red,
    bgSave    = colors.green,
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
    self:_buildButtons()
    self:_buildStatusFrame()
    self:_buildLogArea()
    -- Loading visual handled by status dot + text, no physical ring widget

    self:_patchTextBoxTab()
    self:_patchRootEvents()
    self:_updateButtons()
    self:_updateStatus()

    return self
end

-- ── Layout Calculator ────────────────────────────────────────────

function PanelUI:_calcLayout()
    -- 1=header, 2=sep, 3-5=source+dest(3 rows: title, fields, pad),
    -- 6=buttons(1 row), 7=gap, 8-9=status(2 rows),
    -- 10=gap, 12+=log(6 lines)
    self._L = {
        HEADER    = 1,
        SEP1      = 2,
        INPUTS    = 3,     -- Source/Dest frame start
        INPUT_END = 5,     -- frame end (3 rows)
        GAP_BTN   = 6,
        BUTTONS   = 7,     -- 1 row
        GAP_BTN2  = 8,
        STATUS    = 9,
        STATUS_END= 10,
        GAP_LOG   = 11,
        LOG_START = 12,
    }
    self._logRows = 7  -- fixed 7 log lines (frame = 9 rows)
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
    local height = 3                      -- title + fields + pad

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

    -- X field
    local lblX = a:createLabel({
        x = 2, y = L.INPUTS + 1,
        width = 2,
        height = 1,
        text = "X:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblX)

    local tbSrcX = a:createTextBox({
        x = 4, y = L.INPUTS + 1,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbSrcX)

    -- Y field
    local lblY = a:createLabel({
        x = 11, y = L.INPUTS + 1,
        width = 2,
        height = 1,
        text = "Y:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblY)

    local tbSrcY = a:createTextBox({
        x = 13, y = L.INPUTS + 1,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbSrcY)

    -- [+] clickable label
    self._srcSaveBtn = a:createButton({
        x = 19, y = L.INPUTS + 1,
        width = 3, height = 1,
        label = "[+]",
        bg = C.bgPanel, fg = C.fgYellow,
    })
    r:addChild(self._srcSaveBtn)
    self._srcSaveBtn:setOnClick(function() self:_onSaveClick("source") end)

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
    local height = 3                      -- title + fields + pad

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

    -- X field
    local lblX = a:createLabel({
        x = panX + 2, y = L.INPUTS + 1,
        width = 2,
        height = 1,
        text = "X:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblX)

    local tbDstX = a:createTextBox({
        x = panX + 4, y = L.INPUTS + 1,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbDstX)

    -- Y field
    local lblY = a:createLabel({
        x = panX + 11, y = L.INPUTS + 1,
        width = 2,
        height = 1,
        text = "Y:",
        bg = C.bgPanel,
        fg = C.fgLight,
    })
    r:addChild(lblY)

    local tbDstY = a:createTextBox({
        x = panX + 13, y = L.INPUTS + 1,
        width = 5, height = 1,
        numericOnly = true, maxLength = 5,
        placeholder = "     ", placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(tbDstY)

    -- [+] clickable label
    self._dstSaveBtn = a:createButton({
        x = panX + 19, y = L.INPUTS + 1,
        width = 3, height = 1,
        label = "[+]",
        bg = C.bgPanel, fg = C.fgYellow,
    })
    r:addChild(self._dstSaveBtn)
    self._dstSaveBtn:setOnClick(function() self:_onSaveClick("dest") end)

    self._fields.dst_x = { tb = tbDstX, label = lblX }
    self._fields.dst_y = { tb = tbDstY, label = lblY }
end

function PanelUI:_buildButtons()
    local a, r = self._app, self._root
    local L = self._L

    self._btnMap = {}
    self._btnList = {}

    -- RUN
    local runBtn = a:createButton({
        x = 2, y = L.BUTTONS,
        width = 7, height = 1,
        label = "RUN",
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
        width = 8, height = 1,
        label = "GOTO",
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
        width = 8, height = 1,
        label = "HOME",
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
        width = 10, height = 1,
        label = "EMRG",
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
        height = self._logRows + 2,
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
        if event == "key" then
            local kc = ...
            if kc == keys.escape and self_._popupFrame then
                self_:_closePopup()
                return true
            end
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

    -- Resize log frame (6 lines + 1 for title = 7)
    if self._logFrame then
        self._logFrame:setSize(W - 1, self._logRows + 2)
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

-- ── Save Point Methods ────────────────────────────────────────────

function PanelUI:_onSaveClick(pointType)
    local xStr, yStr
    if pointType == "source" then
        xStr = self:getField("src_x")
        yStr = self:getField("src_y")
    else
        xStr = self:getField("dst_x")
        yStr = self:getField("dst_y")
    end
    local x = tonumber(xStr)
    local y = tonumber(yStr)
    if not x or not y then
        self:addLogLine("Set " .. pointType .. " coordinates first", C.warn)
        return
    end
    self:_showSavePopup(pointType, x, y)
end

function PanelUI:_showSavePopup(pointType, x, y)
    if self._popupFrame then return end

    local W, H = self._termW, self._termH
    local pw, ph = 30, 9
    local px = math.floor((W - pw) / 2) + 1
    local py = math.floor((H - ph) / 2) + 1

    local a = self._app
    local r = self._root

    -- Main popup frame
    local frame = a:createFrame({
        x = px, y = py, width = pw, height = ph,
        bg = C.bgPanel,
        border = { color = C.border },
    })
    r:addChild(frame)

    -- Title
    local title = a:createLabel({
        x = px + 1, y = py,
        width = pw - 2, height = 1,
        text = (pointType == "source") and " Save source point " or " Save dest point ",
        bg = C.bgPanel, fg = C.fgYellow,
    })
    r:addChild(title)

    -- Coordinates display
    local coord = a:createLabel({
        x = px + 2, y = py + 2,
        width = pw - 4, height = 1,
        text = "X=" .. x .. "  Y=" .. y,
        bg = C.bgPanel, fg = C.fgLight,
    })
    r:addChild(coord)

    -- Name textbox
    local nameTb = a:createTextBox({
        x = px + 2, y = py + 4,
        width = pw - 4, height = 1,
        maxLength = 20,
        placeholder = "Enter point name...",
        placeholderColor = C.border,
        bg = C.bgDark, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(nameTb)
    a:setFocus(nameTb)

    -- Cancel button
    local cancel = a:createButton({
        x = px + 2, y = py + ph - 2,
        width = 9, height = 1,
        label = " Cancel ",
        bg = C.bgPanel, fg = C.fgLight,
        border = { color = C.border },
    })
    r:addChild(cancel)
    cancel:setOnClick(function() self:_closePopup() end)

    -- Save button
    local save = a:createButton({
        x = px + pw - 11, y = py + ph - 2,
        width = 9, height = 1,
        label = " Save ",
        bg = C.bgSave, fg = C.fgWhite,
        border = { color = C.border },
    })
    r:addChild(save)
    save:setOnClick(function()
        local name = nameTb:getText():gsub("^%s*(.-)%s*$", "%1")
        if name == "" then
            self:addLogLine("Enter a point name", C.warn)
            return
        end
        self:_savePoint(pointType, name, x, y)
    end)

    -- Store popup references
    self._popupFrame = frame
    self._popupTitle = title
    self._popupCoord = coord
    self._popupNameTb = nameTb
    self._popupCancel = cancel
    self._popupSave = save
end

function PanelUI:_closePopup()
    if not self._popupFrame then return end
    self._popupFrame.visible = false
    if self._popupTitle  then self._popupTitle.visible = false end
    if self._popupCoord  then self._popupCoord.visible = false end
    if self._popupNameTb then self._popupNameTb.visible = false end
    if self._popupCancel then self._popupCancel.visible = false end
    if self._popupSave   then self._popupSave.visible = false end
    self._popupFrame = nil
    self._popupTitle = nil
    self._popupCoord = nil
    self._popupNameTb = nil
    self._popupCancel = nil
    self._popupSave = nil
end

function PanelUI:_savePoint(pointType, name, x, y)
    local filePath = (pointType == "source") and PICKUP_POINTS_FILE or DROP_POINTS_FILE

    -- Load existing points
    local points = {}
    if fs.exists(filePath) then
        local ok, result = pcall(dofile, filePath)
        if ok and type(result) == "table" then
            points = result
        else
            self:addLogLine("Warning: corrupt " .. filePath .. ", starting fresh", C.warn)
        end
    end

    -- Normalize to array-of-tables format (file was previously saved in keyed-object format)
    local firstKey = next(points)
    if firstKey ~= nil and type(firstKey) == "string" then
        -- Keyed-object: { ["Name"] = { x=1, y=2 } } → { { name="Name", x=1, y=2 } }
        local array = {}
        for k, v in pairs(points) do
            if type(v) == "table" and v.x and v.y then
                table.insert(array, { name = k, x = v.x, y = v.y })
            end
        end
        points = array
    end

    -- Find existing entry by name and update, or append new
    local found = false
    for _, p in ipairs(points) do
        if p.name == name then
            p.x, p.y = x, y
            found = true
            break
        end
    end
    if not found then
        table.insert(points, { name = name, x = x, y = y })
    end

    -- Atomic write (temp file + rename)
    local tmpPath = filePath .. ".tmp"
    local f = fs.open(tmpPath, "w")
    if not f then
        self:addLogLine("Error: cannot write " .. filePath, C.err)
        return
    end
    f.write("return ")
    f.write(textutils.serialize(points, { compact = true }))
    f.close()
    fs.delete(filePath)
    fs.move(tmpPath, filePath)

    self:addLogLine("Saved " .. pointType .. " point: " .. name .. " (" .. x .. "," .. y .. ")", C.ok)
    self:_closePopup()
end

-- ── Public API ────────────────────────────────────────────────────

function PanelUI:run()
    self._app:run()
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
end

function PanelUI:setGridSize(maxX, maxY)
    self._state.gridMaxX = maxX or 100
    self._state.gridMaxY = maxY or 100
end

--- Show or hide the pending loading indicator.
--- Visual feedback is handled by the status dot in the status frame.
---@param visible boolean
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

-- ── Internal Render Updates ───────────────────────────────────────

function PanelUI:_redrawHeader()
    local connected = self._state.connected and self._state.registered
    self._headerDot.fg = connected and C.ok or C.fgRed
    self._headerDot:setText(" @ ")
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
