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

-- Main screen (height=3 buttons with label overlay)
local mainLoadBtn, mainUnloadBtn
local mainLoadLabel, mainUnloadLabel

-- List screens (select_source / select_dest)
local listTitle
local itemRows = {}       -- array of label widgets
local upBtn, downBtn
local selectBtn, listAbortBtn

-- Confirm screen
local confirmLine1, confirmLine2, confirmLine3, confirmLine4, confirmLine5, confirmLine6
local confirmRunBtn, confirmAbortBtn

-- Executing screen
local execTitle, execStatusLabel
local execAbortBtn

-- Success screen
local successLine1, successLine2

-- Error screen
local errorLine1, errorLine2

-- Connection lost screen
local connLostLine1, connLostLine2

-- Layout info
local VISIBLE_ITEMS = 3      -- max visible items in list (adjusted in createUI)

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

-- Guard against CC:Tweaked double-event dispatch (monitor_touch + mouse_click).
local clickGuardTime = 0

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

--- Truncate text to maxLen; if it exceeds maxLen, replace last two chars with "..".
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

--- Compute screen layout rows from monitor height.
--- Bottom 3 rows are reserved for action buttons (SELECT/ABORT/RUN/STOP):
---   h-3 = primary action (SELECT / RUN / STOP)
---   h-2 = secondary action (ABORT)
---   h-1 = separator
---   h   = status
--- Content area: rows 3 to h-4
local function computeLayout(h_)
    local contentStart = 3
    local contentEnd = h_ - 4
    local contentHeight = contentEnd - contentStart + 1

    -- Items: title(1) + items(N) + nav(1) fits within contentHeight
    local reserved = 2  -- title + nav row
    local maxItems = math.max(1, contentHeight - reserved)
    local nItems = math.min(maxItems, 8)

    -- Main buttons: center them in content area
    local mainBtnH = 3
    local mainAreaH = contentHeight - mainBtnH * 2
    local gap = math.floor(mainAreaH * 0.25)
    local mainBtnY1 = contentStart + gap
    local mainBtnY2 = contentStart + gap + mainBtnH + math.floor(mainAreaH * 0.5)

    return {
        headerY       = 1,
        sep1Y         = 2,
        contentStart  = contentStart,
        contentEnd    = contentEnd,
        contentHeight = contentHeight,
        sep2Y         = h_ - 1,
        statusY       = h_,
        nItems        = nItems,
        listStartY    = contentStart + 1,
        navY          = contentStart + 1 + nItems,
        -- Action buttons: always at fixed rows from bottom
        actionSelectY = h_ - 3,
        actionAbortY  = h_ - 2,
        mainBtnY1     = mainBtnY1,
        mainBtnY2     = mainBtnY2,
        mainBtnH      = mainBtnH,
    }
end

-------------------------------------------------------------------------------
-- Initialisation
-------------------------------------------------------------------------------

function M.init(pixeluiRef)
    pixelui = pixeluiRef
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
    -- Shared widgets
    ---------------------------------------------------------------------------

    headerLabel = app:createLabel({
        x = 1, y = ly.headerY,
        width = w, height = 1,
        text = centerText("CCrane", w),
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

    ---------------------------------------------------------------------------
    -- Main screen widgets — height=3 buttons with centered label overlay
    ---------------------------------------------------------------------------

    mainLoadBtn = app:createButton({
        x = 1, y = ly.mainBtnY1,
        width = w, height = ly.mainBtnH,
        label = "",
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "main" then return end
            if not st.getState("connected") or not st.getState("registered") then return end
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

    mainLoadLabel = app:createLabel({
        x = 1, y = ly.mainBtnY1 + math.floor(ly.mainBtnH / 2),
        width = w, height = 1,
        text = centerText("LOAD", w),
        align = "center",
        bg = C.btnBlue,
        fg = C.fgWhite,
    })
    root:addChild(mainLoadLabel)

    mainUnloadBtn = app:createButton({
        x = 1, y = ly.mainBtnY2,
        width = w, height = ly.mainBtnH,
        label = "",
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "main" then return end
            if not st.getState("connected") or not st.getState("registered") then return end
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

    mainUnloadLabel = app:createLabel({
        x = 1, y = ly.mainBtnY2 + math.floor(ly.mainBtnH / 2),
        width = w, height = 1,
        text = centerText("UNLOAD", w),
        align = "center",
        bg = C.btnBlue,
        fg = C.fgWhite,
    })
    root:addChild(mainUnloadLabel)

    ---------------------------------------------------------------------------
    -- List screen widgets  (w=15)
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

    -- Item rows
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

    -- Nav buttons: side by side
    local navBtnW = 6
    local navX = 1
    upBtn = app:createButton({
        x = navX, y = ly.navY,
        width = navBtnW, height = 1,
        label = truncate(" \30 " .. " UP", navBtnW),
        bg = C.btnGray, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            local screen = st.getState("screen")
            if screen ~= "select_source" and screen ~= "select_dest" then return end
            local idx = st.getState(screen == "select_source" and "sourceIndex" or "destIndex")
            if idx > 1 then
                idx = idx - 1
                local items = st.getState(screen == "select_source" and "sourcePoints" or "destPoints")
                local change = {
                    [screen == "select_source" and "sourceIndex" or "destIndex"] = idx,
                    [screen == "select_source" and "selectedSource" or "selectedDest"] = items[idx],
                }
                st.updateState(change)
            end
        end,
    })
    root:addChild(upBtn)

    downBtn = app:createButton({
        x = navX + navBtnW + 1, y = ly.navY,
        width = navBtnW, height = 1,
        label = truncate(" \31 " .. " DN", navBtnW),
        bg = C.btnGray, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            local screen = st.getState("screen")
            if screen ~= "select_source" and screen ~= "select_dest" then return end
            local items = st.getState(screen == "select_source" and "sourcePoints" or "destPoints")
            local idx = st.getState(screen == "select_source" and "sourceIndex" or "destIndex")
            if idx < #items then
                idx = idx + 1
                local change = {
                    [screen == "select_source" and "sourceIndex" or "destIndex"] = idx,
                    [screen == "select_source" and "selectedSource" or "selectedDest"] = items[idx],
                }
                st.updateState(change)
            end
        end,
    })
    root:addChild(downBtn)

    -- SELECT at bottom (h-3), ABORT at bottom (h-2) — same fixed rows across all screens
    selectBtn = app:createButton({
        x = 1, y = ly.actionSelectY,
        width = w, height = 1,
        label = centerText("SELECT", w),
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
        x = 1, y = ly.actionAbortY,
        width = w, height = 1,
        label = centerText("ABORT", w),
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
    -- Confirm screen widgets  (w=15)
    -- Line 1: "Source: name"
    -- Line 2: "(x,y)"
    -- Line 3: "Destination: name"
    -- Line 4: "(x,y)"
    -- Line 5: mode (LOAD/UNLOAD)
    -- Line 6: spacer or extra info
    -- RUN at h-3, ABORT at h-2
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
        bg = C.bg, fg = C.fgYellow,
    })
    root:addChild(confirmLine3)

    confirmLine4 = app:createLabel({
        x = 1, y = ly.contentStart + 3,
        width = w, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(confirmLine4)

    confirmLine5 = app:createLabel({
        x = 1, y = ly.contentStart + 5,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgCyan,
    })
    root:addChild(confirmLine5)

    confirmLine6 = app:createLabel({
        x = 1, y = ly.contentStart + 6,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgLight,
    })
    root:addChild(confirmLine6)

    confirmRunBtn = app:createButton({
        x = 1, y = ly.actionSelectY,
        width = w, height = 1,
        label = centerText("RUN", w),
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "confirm" then return end
            st.resetOperation()
            st.updateState({ screen = "executing", operationStatus = "Starting..." })
        end,
    })
    root:addChild(confirmRunBtn)

    confirmAbortBtn = app:createButton({
        x = 1, y = ly.actionAbortY,
        width = w, height = 1,
        label = centerText("ABORT", w),
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
    -- Executing screen widgets  (w=15)
    -- STOP button at h-3
    ---------------------------------------------------------------------------

    execTitle = app:createLabel({
        x = 1, y = ly.contentStart + 1,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(execTitle)

    execStatusLabel = app:createLabel({
        x = 1, y = ly.contentStart + 3,
        width = w, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgLight,
    })
    root:addChild(execStatusLabel)

    execAbortBtn = app:createButton({
        x = 1, y = ly.actionSelectY,
        width = w, height = 1,
        label = centerText("STOP", w),
        bg = C.btnRed, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "executing" then return end
            st.updateState({ operationStatus = "STOP requested..." })
            if app._callbacks and app._callbacks.onEmergencyStop then
                app._callbacks.onEmergencyStop()
            end
        end,
    })
    root:addChild(execAbortBtn)

    ---------------------------------------------------------------------------
    -- Success screen widgets  (w=15)
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

    ---------------------------------------------------------------------------
    -- Error screen widgets  (w=15)
    ---------------------------------------------------------------------------

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

    ---------------------------------------------------------------------------
    -- Connection lost screen widgets  (w=15)
    ---------------------------------------------------------------------------

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
    if mainLoadLabel then mainLoadLabel.visible = false end
    if mainUnloadBtn then mainUnloadBtn.visible = false end
    if mainUnloadLabel then mainUnloadLabel.visible = false end
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
    if confirmRunBtn then confirmRunBtn.visible = false end
    if confirmAbortBtn then confirmAbortBtn.visible = false end
    if execTitle then execTitle.visible = false end
    if execStatusLabel then execStatusLabel.visible = false end
    if execAbortBtn then execAbortBtn.visible = false end
    if successLine1 then successLine1.visible = false end
    if successLine2 then successLine2.visible = false end
    if errorLine1 then errorLine1.visible = false end
    if errorLine2 then errorLine2.visible = false end
    if connLostLine1 then connLostLine1.visible = false end
    if connLostLine2 then connLostLine2.visible = false end
end

local function updateMainButtons(state)
    state = state or st.getState()
    local connected = state.connected and state.registered
    local bg = connected and C.btnBlue or C.btnGray
    local fg = connected and C.fgWhite or C.fgGray
    if mainLoadBtn then mainLoadBtn.bg = bg; mainLoadBtn.fg = fg end
    if mainLoadLabel then mainLoadLabel.bg = bg; mainLoadLabel.fg = fg end
    if mainUnloadBtn then mainUnloadBtn.bg = bg; mainUnloadBtn.fg = fg end
    if mainUnloadLabel then mainUnloadLabel.bg = bg; mainUnloadLabel.fg = fg end
end

--- Build compact list labels (name only, no coords on 15-char screen).
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

    -- Header always visible
    if headerLabel then headerLabel.visible = true end

    -- Status footer
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

    updateMainButtons(state)

    if state.screen == "main" then
        if mainLoadBtn then mainLoadBtn.visible = true end
        if mainLoadLabel then mainLoadLabel.visible = true end
        if mainUnloadBtn then mainUnloadBtn.visible = true end
        if mainUnloadLabel then mainUnloadLabel.visible = true end

    elseif state.screen == "select_source" or state.screen == "select_dest" then
        if headerLabel then headerLabel.visible = true end

        local isSource = (state.screen == "select_source")
        local items = isSource and state.sourcePoints or state.destPoints
        local selIdx = isSource and state.sourceIndex or state.destIndex

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

        -- Navigation buttons visible when there are multiple items to choose from.
        local showScroll = nItems > 1
        if upBtn then upBtn.visible = showScroll end
        if downBtn then downBtn.visible = showScroll end

        -- SELECT/ABORT always at the bottom (fixed rows h-3 / h-2)
        if selectBtn then selectBtn.visible = true end
        if listAbortBtn then listAbortBtn.visible = true end

    elseif state.screen == "confirm" then
        if headerLabel then headerLabel.visible = true end

        local src = state.selectedSource or { name = "?", x = 0, y = 0 }
        local dst = state.selectedDest or { name = "?", x = 0, y = 0 }
        local mode = (state.mode or "load"):upper()

        if confirmLine1 then
            confirmLine1:setText("Source:")
            confirmLine1.visible = true
        end
        if confirmLine2 then
            local coordStr = "(" .. src.x .. "," .. src.y .. ")"
            local maxName = math.max(1, w - #coordStr)
            confirmLine2:setText(truncate(src.name, maxName) .. coordStr)
            confirmLine2.visible = true
        end
        if confirmLine3 then
            confirmLine3:setText("Destination:")
            confirmLine3.visible = true
        end
        if confirmLine4 then
            local coordStr = "(" .. dst.x .. "," .. dst.y .. ")"
            local maxName = math.max(1, w - #coordStr)
            confirmLine4:setText(truncate(dst.name, maxName) .. coordStr)
            confirmLine4.visible = true
        end
        if confirmLine5 then
            confirmLine5:setText(centerText(mode, w))
            confirmLine5.visible = true
        end
        if confirmLine6 then
            confirmLine6.visible = false
        end
        if confirmRunBtn then confirmRunBtn.visible = true end
        if confirmAbortBtn then confirmAbortBtn.visible = true end

    elseif state.screen == "executing" then
        if headerLabel then headerLabel.visible = true end

        local mode = (state.mode or "load"):upper()
        if execTitle then
            execTitle:setText(centerText(mode, w))
            execTitle.visible = true
        end
        if execStatusLabel then
            execStatusLabel:setText(truncate(state.operationStatus or "", w))
            execStatusLabel.visible = true
        end
        -- STOP button at the bottom (h-3)
        if execAbortBtn then execAbortBtn.visible = true end

    elseif state.screen == "success" then
        if headerLabel then headerLabel.visible = true end
        if successLine1 then
            successLine1:setText(centerText("Done!", w))
            successLine1.visible = true
        end
        if successLine2 then
            successLine2:setText(centerText("Returning...", w))
            successLine2.visible = true
        end

    elseif state.screen == "error" then
        if headerLabel then headerLabel.visible = true end
        if errorLine1 then
            errorLine1:setText(truncate("ERR:" .. (state.operationError or "?"), w))
            errorLine1.visible = true
        end
        if errorLine2 then
            errorLine2:setText(centerText("Returning...", w))
            errorLine2.visible = true
        end

    elseif state.screen == "connection_lost" then
        if headerLabel then headerLabel.visible = true end
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
-- Live status update during execution (no full screen transition)
-------------------------------------------------------------------------------

function M.updateProgress(state)
    if not app then return end
    if state.screen == "executing" then
        if execStatusLabel then
            execStatusLabel:setText(truncate(state.operationStatus or "", w))
        end
        app:render()
    end
end

return M
