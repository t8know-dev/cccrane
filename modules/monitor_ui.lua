-- modules/monitor_ui.lua — PixelUI-based monitor UI for crane load/unload
-- Exports: init(pixelui), createUI(monitor, stateModule), updateScreen(state), updateProgress(state)
--
-- Designed for a 15-char wide monitor (2×1 block at scale 0.5 ~15×30).
-- Five screens: main (load/unload), select_source, select_dest, confirm, executing
-- Info screens: success, error, connection_lost
-- Uses PixelUI. Follows ccunloader patterns: all widgets created once, visibility toggling,
-- click guard, screen-specific rendering dispatch.

local M = {}
local pixelui
local st                 -- state module reference

local app
local root
local w, h               -- monitor dimensions

-- Widget references (shared across screens)
local headerLabel
local statusLabel
local copyrightLabel

-- Main screen
local mainLoadBtn, mainUnloadBtn

-- List screens (select_source / select_dest)
local listTitle
local itemRows = {}       -- array of label widgets
local upBtn, downBtn
local selectBtn, listAbortBtn

-- Confirm screen
local confirmLine1, confirmLine2, confirmLine3, confirmLine4, confirmLine5, confirmLine6, confirmLine7, confirmLine8
local confirmRunBtn, confirmAbortBtn

-- Executing screen
local execTitle
local execStatusLines = {}       -- multiple lines for wrapped status text

-- Success screen
local successLine1, successLine2, successSep, successSourceLine, successDestLine

-- Error screen
local errorLine1, errorLine2

-- Connection lost screen
local connLostLine1, connLostLine2

-- Layout info
local VISIBLE_ITEMS = 3

-- Colors
local C = {
    headerBg   = colors.red,
    headerFg   = colors.white,
    bg         = colors.black,
    fgWhite    = colors.white,
    fgLight    = colors.lightGray,
    fgGray     = colors.gray,
    fgGreen    = colors.green,
    fgRed      = colors.red,
    fgYellow   = colors.yellow,
    fgCyan     = colors.cyan,
    fgOrange   = colors.orange,
    btnBlue    = colors.blue,
    btnRed     = colors.red,
    btnGray    = colors.gray,
    selectBg   = colors.blue,
    sep        = colors.gray,
}

local clickGuardTime = 0

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function truncate(text, maxLen)
    if #text <= maxLen then return text end
    return text:sub(1, maxLen - 2) .. ".."
end

local function centerText(text, width)
    width = width or w
    local pad = math.max(0, math.floor((width - #text) / 2))
    local rightPad = math.max(0, width - #text - pad)
    return string.rep(" ", pad) .. text .. string.rep(" ", rightPad)
end

-- Center text helper

--- Word-wrap text to fit within a given width.
--- Returns up to `maxLines` lines, each truncated if needed.
local function wrapText(text, width, maxLines)
    width = width or w
    maxLines = maxLines or 5
    text = tostring(text or "")
    if #text == 0 then return { "" } end

    local lines = {}
    while #text > 0 and #lines < maxLines do
        if #text <= width then
            lines[#lines + 1] = text
            break
        end
        -- Try to break at a space within width
        local breakAt = width
        for i = width, 1, -1 do
            if text:sub(i, i) == " " then
                breakAt = i - 1
                break
            end
        end
        -- If no space found, hard-break
        lines[#lines + 1] = text:sub(1, breakAt)
        text = text:sub(breakAt + 2)  -- skip the space if we broke at one
    end
    return lines
end

local function computeLayout(h_)
    local contentStart = 3
    local contentEnd = h_ - 4
    local contentHeight = contentEnd - contentStart + 1

    local reserved = 2  -- title + nav row
    local maxItems = math.max(1, contentHeight - reserved)
    local nItems = math.min(maxItems, 14)

    return {
        headerY       = 1,
        contentStart  = contentStart,
        contentEnd    = contentEnd,
        contentHeight = contentHeight,
        sep2Y         = h_ - 1,
        statusY       = h_,
        nItems        = nItems,
        listStartY    = contentStart + 1,
        navY          = h_ - 5,
        actionSelectY = h_ - 3,
        actionAbortY  = h_ - 2,
        mainBtnY1     = contentStart + math.max(0, math.floor((contentHeight - 9) / 2)),
        mainBtnY2     = contentStart + math.max(0, math.floor((contentHeight - 9) / 2)) + 4,
    }
end

-------------------------------------------------------------------------------
-- Initialisation
-------------------------------------------------------------------------------

function M.init(pixeluiRef)
    pixelui = pixeluiRef
end

--- Get list info based on screen and operation mode.
--- For LOAD mode: first screen (select_source) = destPoints, second (select_dest) = sourcePoints.
--- For UNLOAD mode: first screen (select_source) = sourcePoints, second (select_dest) = destPoints.
--- Returns: items, currentIndex, indexKey, selectedKey
local function getListInfo(state)
    local isSource = (state.screen == "select_source")
    if state.mode == "load" then
        if isSource then
            return state.destPoints, state.destIndex, "destIndex", "selectedDest"
        else
            return state.sourcePoints, state.sourceIndex, "sourceIndex", "selectedSource"
        end
    else
        if isSource then
            return state.sourcePoints, state.sourceIndex, "sourceIndex", "selectedSource"
        else
            return state.destPoints, state.destIndex, "destIndex", "selectedDest"
        end
    end
end

-------------------------------------------------------------------------------
-- UI Creation
-------------------------------------------------------------------------------

function M.createUI(monitor, stateModule)
    if not pixelui then error("ui.init() not called before createUI") end
    st = stateModule

    monitor.setTextScale(0.5)
    w, h = monitor.getSize()

    if h < 14 then
        error("Monitor too small: need at least 14 lines (h=" .. tostring(h) .. ")")
    end

    local viewport = window.create(monitor, 1, 1, w, h, true)

    app = pixelui.create({
        window = viewport,
        background = C.bg,
        animationInterval = 0.05,
    })
    root = app:getRoot()

    local ly = computeLayout(h)
    VISIBLE_ITEMS = ly.nItems

    print("[monitor] size: " .. w .. "x" .. h .. ", visible items: " .. VISIBLE_ITEMS)

    ---------------------------------------------------------------------------
    -- Shared
    ---------------------------------------------------------------------------

    headerLabel = app:createLabel({
        x = 1, y = ly.headerY,
        width = w, height = 1,
        text = centerText("CCRANE", w),
        align = "center",
        bg = C.headerBg,
        fg = C.headerFg,
    })
    root:addChild(headerLabel)

    statusLabel = app:createLabel({
        x = 1, y = ly.statusY,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg,
        fg = C.fgGray,
    })
    root:addChild(statusLabel)

    copyrightLabel = app:createLabel({
        x = 1, y = ly.statusY,
        width = w, height = 1,
        text = "",
        align = "right",
        bg = C.bg,
        fg = C.fgGray,
    })
    root:addChild(copyrightLabel)

    ---------------------------------------------------------------------------
    -- Main screen  (width=13, centered buttons, height=3)
    ---------------------------------------------------------------------------

    local btnW = 13
    local btnX = math.floor((w - btnW) / 2) + 1

    mainLoadBtn = app:createButton({
        x = btnX, y = ly.mainBtnY1,
        width = btnW, height = 3,
        border = true,
        label = "LOAD",
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "main" then return end
            if not st.getState("connected") or not st.getState("registered") then
                st.updateState({ screen = "connection_lost" })
                return
            end
            st.updateState({
                mode = "load",
                sourceIndex = 1,
                destIndex = 1,
                selectedSource = st.getState("sourcePoints")[1],
                selectedDest = st.getState("destPoints")[1],
                screen = "select_source",
            })
        end,
    })
    root:addChild(mainLoadBtn)

    mainUnloadBtn = app:createButton({
        x = btnX, y = ly.mainBtnY2,
        width = btnW, height = 3,
        border = true,
        label = "UNLOAD",
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "main" then return end
            if not st.getState("connected") or not st.getState("registered") then
                st.updateState({ screen = "connection_lost" })
                return
            end
            st.updateState({
                mode = "unload",
                sourceIndex = 1,
                destIndex = 1,
                selectedSource = st.getState("sourcePoints")[1],
                selectedDest = st.getState("destPoints")[1],
                screen = "select_source",
            })
        end,
    })
    root:addChild(mainUnloadBtn)

    ---------------------------------------------------------------------------
    -- List screen
    ---------------------------------------------------------------------------

    listTitle = app:createLabel({
        x = 1, y = ly.contentStart,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg,
        fg = C.fgWhite,
    })
    root:addChild(listTitle)

    itemRows = {}
    for i = 1, ly.nItems do
        local row = app:createLabel({
            x = 2, y = ly.listStartY + i - 1,
            width = w - 2, height = 1,
            text = "",
            align = "left",
            bg = C.bg,
            fg = C.fgWhite,
        })
        root:addChild(row)
        itemRows[i] = row
    end

    -- Up/down buttons: width=3, gap=5 between them
    -- Total width = 3 + 5(gap) + 3 = 11. Margin each side = (15-11)/2 = 2
    local navBtnW = 3
    local navGap = 5
    local navX = math.floor((w - navBtnW * 2 - navGap) / 2) + 1
    upBtn = app:createButton({
        x = navX, y = ly.navY,
        width = navBtnW, height = 1,
        label = " \30 ",
        bg = C.btnGray, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            local screen = st.getState("screen")
            if screen ~= "select_source" and screen ~= "select_dest" then return end
            local items, idx, idxKey, selKey = getListInfo(st.getState())
            if idx > 1 then
                idx = idx - 1
                st.updateState({
                    [idxKey] = idx,
                    [selKey] = items[idx],
                })
            end
        end,
    })
    root:addChild(upBtn)

    downBtn = app:createButton({
        x = navX + navBtnW + navGap, y = ly.navY,
        width = navBtnW, height = 1,
        label = " \31 ",
        bg = C.btnGray, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            local screen = st.getState("screen")
            if screen ~= "select_source" and screen ~= "select_dest" then return end
            local items, idx, idxKey, selKey = getListInfo(st.getState())
            if idx < #items then
                idx = idx + 1
                st.updateState({
                    [idxKey] = idx,
                    [selKey] = items[idx],
                })
            end
        end,
    })
    root:addChild(downBtn)

    -- SELECT/ABORT at fixed bottom rows
    selectBtn = app:createButton({
        x = 2, y = ly.actionSelectY,
        width = 13, height = 1,
        label = centerText("SELECT", 13),
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            local screen = st.getState("screen")
            if screen == "select_source" then
                st.updateState({ screen = "select_dest" })
            elseif screen == "select_dest" then
                st.updateState({ screen = "confirm" })
            end
        end,
    })
    root:addChild(selectBtn)

    listAbortBtn = app:createButton({
        x = 2, y = ly.actionAbortY,
        width = 13, height = 1,
        label = centerText("ABORT", 13),
        bg = C.btnRed, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            local screen = st.getState("screen")
            if screen ~= "select_source" and screen ~= "select_dest" then return end
            st.updateState({ screen = "main" })
        end,
    })
    root:addChild(listAbortBtn)

    ---------------------------------------------------------------------------
    -- Confirm screen
    -- Layout:
    --   Source:        (yellow)
    --   Depot          (white, point name)
    --   (80, 30)       (white, coords)
    --   (empty)
    --   Destination:   (yellow)
    --   Train st...    (white, point name)
    --   (10, 40)       (white, coords)
    --   (empty)
    --   LOAD           (cyan, centered)
    ---------------------------------------------------------------------------

    confirmLine1 = app:createLabel({
        x = 1, y = ly.contentStart,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgYellow,
    })
    root:addChild(confirmLine1)

    confirmLine2 = app:createLabel({
        x = 1, y = ly.contentStart + 1,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(confirmLine2)

    confirmLine3 = app:createLabel({
        x = 1, y = ly.contentStart + 2,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(confirmLine3)

    confirmLine4 = app:createLabel({
        x = 1, y = ly.contentStart + 4,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgYellow,
    })
    root:addChild(confirmLine4)

    confirmLine5 = app:createLabel({
        x = 1, y = ly.contentStart + 5,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(confirmLine5)

    confirmLine6 = app:createLabel({
        x = 1, y = ly.contentStart + 6,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(confirmLine6)

    confirmLine7 = app:createLabel({
        x = 1, y = ly.contentStart + 8,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgCyan,
    })
    root:addChild(confirmLine7)

    confirmLine8 = app:createLabel({
        x = 1, y = ly.contentStart + 9,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgCyan,
    })
    root:addChild(confirmLine8)

    confirmRunBtn = app:createButton({
        x = 2, y = ly.actionSelectY,
        width = 13, height = 1,
        label = centerText("RUN", 13),
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "confirm" then return end
            if not st.getState("connected") or not st.getState("registered") then
                st.updateState({ screen = "connection_lost" })
                return
            end
            st.resetOperation()
            st.updateState({ screen = "executing", operationStatus = "Starting..." })
        end,
    })
    root:addChild(confirmRunBtn)

    confirmAbortBtn = app:createButton({
        x = 2, y = ly.actionAbortY,
        width = 13, height = 1,
        label = centerText("ABORT", 13),
        bg = C.btnRed, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "confirm" then return end
            st.updateState({ screen = "main" })
        end,
    })
    root:addChild(confirmAbortBtn)

    ---------------------------------------------------------------------------
    -- Executing screen
    ---------------------------------------------------------------------------

    execTitle = app:createLabel({
        x = 1, y = ly.contentStart + 1,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(execTitle)

    -- Multi-line status with word wrap (5 lines should cover most messages)
    for i = 1, 5 do
        execStatusLines[i] = app:createLabel({
            x = 1, y = ly.contentStart + 3 + (i - 1),
            width = w, height = 1,
            text = "",
            align = "left",
            bg = C.bg, fg = C.fgLight,
        })
        root:addChild(execStatusLines[i])
    end

    ---------------------------------------------------------------------------
    -- Success / Error / Connection lost
    ---------------------------------------------------------------------------

    successLine1 = app:createLabel({
        x = 1, y = ly.contentStart + 2,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgGreen,
    })
    root:addChild(successLine1)

    successLine2 = app:createLabel({
        x = 1, y = ly.contentStart + 4,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgLight,
    })
    root:addChild(successLine2)

    successSep = app:createLabel({
        x = 1, y = ly.contentStart + 6,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.sep,
    })
    root:addChild(successSep)

    successSourceLine = app:createLabel({
        x = 1, y = ly.contentStart + 7,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgYellow,
    })
    root:addChild(successSourceLine)

    successDestLine = app:createLabel({
        x = 1, y = ly.contentStart + 8,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgCyan,
    })
    root:addChild(successDestLine)

    errorLine1 = app:createLabel({
        x = 1, y = ly.contentStart + 2,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgRed,
    })
    root:addChild(errorLine1)

    errorLine2 = app:createLabel({
        x = 1, y = ly.contentStart + 4,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgLight,
    })
    root:addChild(errorLine2)

    connLostLine1 = app:createLabel({
        x = 1, y = ly.contentStart + 2,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgRed,
    })
    root:addChild(connLostLine1)

    connLostLine2 = app:createLabel({
        x = 1, y = ly.contentStart + 4,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgLight,
    })
    root:addChild(connLostLine2)

    return app
end

-------------------------------------------------------------------------------
-- Visibility helpers
-------------------------------------------------------------------------------

local function hideAllDynamic()
    if mainLoadBtn then mainLoadBtn.visible = false end
    if mainUnloadBtn then mainUnloadBtn.visible = false end
    if listTitle then listTitle.visible = false end
    for _, r in ipairs(itemRows) do r.visible = false end
    if upBtn then upBtn.visible = false end
    if downBtn then downBtn.visible = false end
    if selectBtn then selectBtn.visible = false end
    if listAbortBtn then listAbortBtn.visible = false end
    if confirmLine1 then confirmLine1.visible = false end
    if confirmLine2 then confirmLine2.visible = false end
    if confirmLine3 then confirmLine3.visible = false end
    if confirmLine4 then confirmLine4.visible = false end
    if confirmLine5 then confirmLine5.visible = false end
    if confirmLine6 then confirmLine6.visible = false end
    if confirmLine7 then confirmLine7.visible = false end
    if confirmLine8 then confirmLine8.visible = false end
    if confirmRunBtn then confirmRunBtn.visible = false end
    if confirmAbortBtn then confirmAbortBtn.visible = false end
    if execTitle then execTitle.visible = false end
    for _, l in ipairs(execStatusLines) do l.visible = false end
    if successLine1 then successLine1.visible = false end
    if successLine2 then successLine2.visible = false end
    if successSep then successSep.visible = false end
    if successSourceLine then successSourceLine.visible = false end
    if successDestLine then successDestLine.visible = false end
    if errorLine1 then errorLine1.visible = false end
    if errorLine2 then errorLine2.visible = false end
    if connLostLine1 then connLostLine1.visible = false end
    if connLostLine2 then connLostLine2.visible = false end
end

local function buildItemLabels(points)
    local labels = {}
    for i, p in ipairs(points) do
        local name = p.name or "Pt" .. tostring(i)
        table.insert(labels, truncate(name, 12))
    end
    return labels
end

-------------------------------------------------------------------------------
-- Screen renderer
-------------------------------------------------------------------------------

function M.updateScreen(state)
    if not app then return end
    hideAllDynamic()

    if headerLabel then headerLabel.visible = true end

    if statusLabel then
        local connected = state.connected and state.registered
        if connected then
            statusLabel:setText(truncate(state.craneId or "ONLINE", w))
            statusLabel.fg = C.fgGreen
        else
            statusLabel:setText("DISCONNECTED")
            statusLabel.fg = C.fgRed
        end
        statusLabel.visible = true
    end

    if copyrightLabel then
        copyrightLabel:setText("(c) jigga " .. (state.version or ""))
        copyrightLabel.visible = true
    end

    if state.screen == "main" then
        local enabled = state.connected and state.registered
        if mainLoadBtn then
            mainLoadBtn.bg = enabled and C.btnBlue or C.btnGray
            mainLoadBtn.fg = enabled and C.fgWhite or C.fgGray
            mainLoadBtn.visible = true
        end
        if mainUnloadBtn then
            mainUnloadBtn.bg = enabled and C.btnBlue or C.btnGray
            mainUnloadBtn.fg = enabled and C.fgWhite or C.fgGray
            mainUnloadBtn.visible = true
        end

    elseif state.screen == "select_source" or state.screen == "select_dest" then
        local isSource = (state.screen == "select_source")
        local items, selIdx = getListInfo(state)

        if listTitle then
            listTitle:setText(isSource and "PICKUP" or "DROP")
            listTitle.visible = true
        end

        local labels = buildItemLabels(items)
        local nItems = #items

        local scrollOffset = 1
        if nItems > VISIBLE_ITEMS then
            if selIdx <= 2 then
                scrollOffset = 1
            elseif selIdx >= nItems - (VISIBLE_ITEMS - 2) then
                scrollOffset = nItems - VISIBLE_ITEMS + 1
            else
                scrollOffset = selIdx - 1
            end
        end

        for ri = 1, VISIBLE_ITEMS do
            local row = itemRows[ri]
            if row then
                local itemIdx = scrollOffset + ri - 1
                if itemIdx <= nItems then
                    local isSel = (itemIdx == selIdx)
                    local prefix = isSel and ">" or " "
                    row:setText(prefix .. labels[itemIdx])
                    row.bg = isSel and C.selectBg or C.bg
                    row.fg = C.fgWhite
                    row.visible = true
                else
                    row.visible = false
                end
            end
        end

        local showScroll = nItems > 1
        if upBtn then upBtn.visible = showScroll end
        if downBtn then downBtn.visible = showScroll end

        if selectBtn then selectBtn.visible = true end
        if listAbortBtn then listAbortBtn.visible = true end

    elseif state.screen == "confirm" then
        local src, dst
        if state.mode == "load" then
            -- LOAD: pick up from dest, drop at source
            src = state.selectedDest or { name = "?", x = 0, y = 0 }
            dst = state.selectedSource or { name = "?", x = 0, y = 0 }
        else
            -- UNLOAD: pick up from source, drop at dest
            src = state.selectedSource or { name = "?", x = 0, y = 0 }
            dst = state.selectedDest or { name = "?", x = 0, y = 0 }
        end
        local mode = (state.mode or "load"):upper()

        if confirmLine1 then
            confirmLine1:setText("Source:")
            confirmLine1.visible = true
        end
        if confirmLine2 then
            confirmLine2:setText(truncate(src.name, w))
            confirmLine2.visible = true
        end
        if confirmLine3 then
            confirmLine3:setText("(" .. src.x .. "," .. src.y .. ")")
            confirmLine3.visible = true
        end
        if confirmLine4 then
            confirmLine4:setText("Destination:")
            confirmLine4.visible = true
        end
        if confirmLine5 then
            confirmLine5:setText(truncate(dst.name, w))
            confirmLine5.visible = true
        end
        if confirmLine6 then
            confirmLine6:setText("(" .. dst.x .. "," .. dst.y .. ")")
            confirmLine6.visible = true
        end
        if confirmLine7 then
            confirmLine7:setText("Operation:")
            confirmLine7.visible = true
        end
        if confirmLine8 then
            confirmLine8:setText(mode)
            confirmLine8.visible = true
        end
        if confirmRunBtn then confirmRunBtn.visible = true end
        if confirmAbortBtn then confirmAbortBtn.visible = true end

    elseif state.screen == "executing" then
        local mode = (state.mode or "load"):upper()
        if execTitle then
            execTitle:setText(centerText(mode, w))
            execTitle.visible = true
        end
        local lines = wrapText(state.operationStatus or "", w, #execStatusLines)
        for i, l in ipairs(execStatusLines) do
            l:setText(lines[i] or "")
            l.visible = true
        end

    elseif state.screen == "success" then
        if successLine1 then
            successLine1:setText(centerText(state.operationStatus or "Done!", w))
            successLine1.visible = true
        end
        if successSep then
            successSep:setText(string.rep("-", w))
            successSep.visible = true
        end
        local src, dst
        if state.mode == "load" then
            src = state.selectedDest or { name = "?", x = 0, y = 0 }
            dst = state.selectedSource or { name = "?", x = 0, y = 0 }
        else
            src = state.selectedSource or { name = "?", x = 0, y = 0 }
            dst = state.selectedDest or { name = "?", x = 0, y = 0 }
        end
        if successSourceLine then
            successSourceLine:setText("> " .. truncate(src.name, w - 2))
            successSourceLine.visible = true
        end
        if successDestLine then
            successDestLine:setText("> " .. truncate(dst.name, w - 2))
            successDestLine.visible = true
        end
    elseif state.screen == "error" then
        if errorLine1 then
            errorLine1:setText(truncate("ERR:" .. (state.operationError or "?"), w))
            errorLine1.visible = true
        end
        if errorLine2 then
            errorLine2:setText(centerText("Returning...", w))
            errorLine2.visible = true
        end

    elseif state.screen == "connection_lost" then
        if connLostLine1 then
            connLostLine1:setText(centerText("CONN LOST", w))
            connLostLine1.visible = true
        end
        if connLostLine2 then
            connLostLine2:setText(centerText("Waiting...", w))
            connLostLine2.visible = true
        end
    end

    app:render()
end

-------------------------------------------------------------------------------
-- Live status update
-------------------------------------------------------------------------------

function M.updateProgress(state)
    if not app then return end
    if state.screen == "executing" then
        local lines = wrapText(state.operationStatus or "", w, #execStatusLines)
        for i, l in ipairs(execStatusLines) do
            l:setText(lines[i] or "")
        end
        app:render()
    end
end

return M
