-- modules/monitor_ui.lua — PixelUI-based monitor UI for crane load/unload
-- Exports: init(pixelui), createUI(monitor, stateModule), updateScreen(state), updateProgress(state)
--
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

-- Main screen
local mainLoadBtn, mainUnloadBtn

-- List screens (select_source / select_dest)
local listTitle
local itemRows = {}       -- array of label widgets
local upBtn, downBtn
local selectBtn, listAbortBtn

-- Confirm screen
local confirmTitle
local confirmSourceLabel, confirmDestLabel
local confirmModeLabel
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
local MAX_ITEM_NAME_LEN = 18

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

local function centerText(text, width)
    width = width or w
    local pad = math.max(0, math.floor((width - #text) / 2))
    local rightPad = math.max(0, width - #text - pad)
    return string.rep(" ", pad) .. text .. string.rep(" ", rightPad)
end

--- Compute screen layout rows from monitor height.
--- Returns a table with y-coordinates for each section.
local function computeLayout(h_)
    -- Header at row 1, footer at row h_
    -- Content area: rows 3 to h_-2 (with separators at 2 and h_-1)
    local contentStart = 3
    local contentEnd = h_ - 2
    local contentHeight = contentEnd - contentStart + 1

    -- In list screens we need room for: title(1) + items(N) + nav(1) + select(1) + abort(1)
    -- Reserve 5 rows for controls (title + nav + select + abort) = 4 rows + 1 padding
    -- Actually: title(1), buttons (nav=1, select=1, abort=1)
    -- Items = contentHeight - 4 (title) - 1 (gap) = contentHeight - 5 for buttons area
    local reserved = 5  -- title row + nav row + select row + abort row + top gap
    local maxItems = math.max(1, contentHeight - reserved)
    -- But cap at reasonable limit
    local nItems = math.min(maxItems, 6)

    return {
        headerY       = 1,
        sep1Y         = 2,
        contentStart  = contentStart,
        contentEnd    = contentEnd,
        contentHeight = contentHeight,
        sep2Y         = h_ - 1,
        statusY       = h_,
        nItems        = nItems,
        -- Item list rows start at contentStart + 1 (after title)
        listStartY    = contentStart + 1,
        -- Nav buttons row: after items + 1 blank row
        navY          = contentStart + 1 + nItems + 1,
        -- Select button row
        selectY       = contentStart + 1 + nItems + 2,
        -- Abort button row (list screen)
        listAbortY    = contentStart + 1 + nItems + 3,
        -- Confirm screen
        confirmRunY   = h_ - 3,
        confirmAbortY = h_ - 2,
        -- Executing screen
        execAbortY    = h_ - 3,
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

    -- Minimum viable height: need at least 10 lines
    if h < 10 then
        error("Monitor too small: need at least 10 lines (h=" .. tostring(h) .. ")")
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

    -- Show monitor dimensions and layout info on terminal
    print("[monitor] size: " .. w .. "x" .. h .. ", visible items: " .. VISIBLE_ITEMS)

    ---------------------------------------------------------------------------
    -- Shared widgets
    ---------------------------------------------------------------------------

    -- Header: row 1, red background
    headerLabel = app:createLabel({
        x = 1, y = ly.headerY,
        width = w, height = 1,
        text = centerText("CCrane", w),
        align = "center",
        bg = C.headerBg,
        fg = C.headerFg,
    })
    root:addChild(headerLabel)

    -- Status footer: last row
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
    -- Main screen widgets
    ---------------------------------------------------------------------------

    -- Centered LOAD button
    local btnW = 12
    local btnX = math.floor((w - btnW) / 2)
    local mainBtnY1 = math.floor(ly.contentStart + ly.contentHeight * 0.3)
    local mainBtnY2 = math.floor(ly.contentStart + ly.contentHeight * 0.55)

    mainLoadBtn = app:createButton({
        x = btnX, y = mainBtnY1,
        width = btnW, height = 1,
        label = centerText("LOAD", btnW),
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

    mainUnloadBtn = app:createButton({
        x = btnX, y = mainBtnY2,
        width = btnW, height = 1,
        label = centerText("UNLOAD", btnW),
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

    ---------------------------------------------------------------------------
    -- List screen widgets (shared by select_source and select_dest)
    ---------------------------------------------------------------------------

    listTitle = app:createLabel({
        x = 2, y = ly.contentStart,
        width = w - 3, height = 1,
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
            x = 3, y = ly.listStartY + i - 1,
            width = w - 4, height = 1,
            text = "",
            align = "left",
            bg = C.bg,
            fg = C.fgWhite,
        })
        root:addChild(row)
        itemRows[i] = row
    end

    -- Navigation buttons side by side
    local navBtnW = 5
    local navGap = 2
    local navTotalW = navBtnW * 2 + navGap
    local navX = math.floor((w - navTotalW) / 2)

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

    -- Select button
    selectBtn = app:createButton({
        x = 2, y = ly.selectY,
        width = w - 3, height = 1,
        label = "SELECT",
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

    -- Abort button on list screens
    listAbortBtn = app:createButton({
        x = 2, y = ly.listAbortY,
        width = w - 3, height = 1,
        label = "ABORT",
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
    -- Confirm screen widgets
    ---------------------------------------------------------------------------

    confirmTitle = app:createLabel({
        x = 2, y = ly.contentStart,
        width = w - 3, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgYellow,
    })
    root:addChild(confirmTitle)

    confirmSourceLabel = app:createLabel({
        x = 2, y = ly.contentStart + 2,
        width = w - 3, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(confirmSourceLabel)

    confirmDestLabel = app:createLabel({
        x = 2, y = ly.contentStart + 3,
        width = w - 3, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(confirmDestLabel)

    confirmModeLabel = app:createLabel({
        x = 2, y = ly.contentStart + 5,
        width = w - 3, height = 1,
        text = "",
        align = "left",
        bg = C.bg, fg = C.fgCyan,
    })
    root:addChild(confirmModeLabel)

    confirmRunBtn = app:createButton({
        x = 2, y = ly.confirmRunY,
        width = w - 3, height = 1,
        label = "RUN",
        bg = C.btnBlue, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "confirm" then return end
            -- Transition to executing — the entry point handles sending the command
            st.resetOperation()
            st.updateState({ screen = "executing", operationStatus = "Starting..." })
        end,
    })
    root:addChild(confirmRunBtn)

    confirmAbortBtn = app:createButton({
        x = 2, y = ly.confirmAbortY,
        width = w - 3, height = 1,
        label = "ABORT",
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
    -- Executing screen widgets
    ---------------------------------------------------------------------------

    execTitle = app:createLabel({
        x = 2, y = ly.contentStart + 1,
        width = w - 3, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgWhite,
    })
    root:addChild(execTitle)

    execStatusLabel = app:createLabel({
        x = 2, y = ly.contentStart + 3,
        width = w - 3, height = 1,
        text = "",
        align = "center",
        bg = C.bg, fg = C.fgLight,
    })
    root:addChild(execStatusLabel)

    execAbortBtn = app:createButton({
        x = 2, y = ly.execAbortY,
        width = w - 3, height = 1,
        label = "EMERGENCY STOP",
        bg = C.btnRed, fg = C.fgWhite,
        onClick = function()
            local now = os.clock()
            if now - clickGuardTime < 0.15 then return end
            clickGuardTime = now
            if st.getState("screen") ~= "executing" then return end
            -- Signal emergency stop via state; entry point handles sending ECNet2 command
            st.updateState({ operationStatus = "EMERGENCY STOP requested..." })
            -- The entry point will call the emergency stop callback
            if app._callbacks and app._callbacks.onEmergencyStop then
                app._callbacks.onEmergencyStop()
            end
        end,
    })
    root:addChild(execAbortBtn)

    ---------------------------------------------------------------------------
    -- Success screen widgets
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
    -- Error screen widgets
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
    -- Connection lost screen widgets
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
    -- Main
    if mainLoadBtn then mainLoadBtn.visible = false end
    if mainUnloadBtn then mainUnloadBtn.visible = false end
    -- List
    if listTitle then listTitle.visible = false end
    for _, r in ipairs(itemRows) do r.visible = false end
    if upBtn then upBtn.visible = false end
    if downBtn then downBtn.visible = false end
    if selectBtn then selectBtn.visible = false end
    if listAbortBtn then listAbortBtn.visible = false end
    -- Confirm
    if confirmTitle then confirmTitle.visible = false end
    if confirmSourceLabel then confirmSourceLabel.visible = false end
    if confirmDestLabel then confirmDestLabel.visible = false end
    if confirmModeLabel then confirmModeLabel.visible = false end
    if confirmRunBtn then confirmRunBtn.visible = false end
    if confirmAbortBtn then confirmAbortBtn.visible = false end
    -- Executing
    if execTitle then execTitle.visible = false end
    if execStatusLabel then execStatusLabel.visible = false end
    if execAbortBtn then execAbortBtn.visible = false end
    -- Success
    if successLine1 then successLine1.visible = false end
    if successLine2 then successLine2.visible = false end
    -- Error
    if errorLine1 then errorLine1.visible = false end
    if errorLine2 then errorLine2.visible = false end
    -- Connection lost
    if connLostLine1 then connLostLine1.visible = false end
    if connLostLine2 then connLostLine2.visible = false end
end

local function updateMainButtons(state)
    state = state or st.getState()
    local connected = state.connected and state.registered
    if mainLoadBtn then
        mainLoadBtn.bg = connected and C.btnBlue or C.btnGray
        mainLoadBtn.fg = connected and C.fgWhite or C.fgGray
    end
    if mainUnloadBtn then
        mainUnloadBtn.bg = connected and C.btnBlue or C.btnGray
        mainUnloadBtn.fg = connected and C.fgWhite or C.fgGray
    end
end

local function buildItemLabels(points)
    local labels = {}
    for i, p in ipairs(points) do
        local name = p.name or "Point " .. tostring(i)
        if #name > MAX_ITEM_NAME_LEN then
            name = name:sub(1, MAX_ITEM_NAME_LEN - 2) .. ".."
        end
        table.insert(labels, name .. " (" .. tostring(p.x) .. "," .. tostring(p.y) .. ")")
    end
    return labels
end

-------------------------------------------------------------------------------
-- Screen renderer
-------------------------------------------------------------------------------

function M.updateScreen(state)
    if not app then return end
    hideAllDynamic()

    -- Always update header + status
    if headerLabel then
        headerLabel.visible = true
    end
    if statusLabel then
        local connected = state.connected and state.registered
        local text
        if connected then
            text = "Connected: " .. (state.craneId or "?")
        else
            text = "DISCONNECTED"
        end
        statusLabel:setText(text)
        statusLabel.fg = connected and C.fgGreen or C.fgRed
        statusLabel.visible = true
    end

    -- Update button colors based on connection
    updateMainButtons(state)

    if state.screen == "main" then
        if mainLoadBtn then mainLoadBtn.visible = true end
        if mainUnloadBtn then mainUnloadBtn.visible = true end

    elseif state.screen == "select_source" or state.screen == "select_dest" then
        if headerLabel then headerLabel.visible = true end

        local isSource = (state.screen == "select_source")
        local items = isSource and state.sourcePoints or state.destPoints
        local selIdx = isSource and state.sourceIndex or state.destIndex
        local selPoint = isSource and state.selectedSource or state.selectedDest

        -- Title
        if listTitle then
            listTitle:setText(isSource and "PICKUP POINTS:" or "DROP POINTS:")
            listTitle.visible = true
        end

        -- Render visible rows
        local labels = buildItemLabels(items)
        local nItems = #items

        -- Compute scroll offset to keep selected item visible
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
                    local prefix = isSel and "> " or "  "
                    row:setText(prefix .. labels[itemIdx])
                    row.bg = isSel and C.selectBg or C.bg
                    row.fg = C.fgWhite
                    row.visible = true
                else
                    row.visible = false
                end
            end
        end

        -- Navigation buttons (only when more items than visible rows)
        local showScroll = nItems > VISIBLE_ITEMS
        if upBtn then upBtn.visible = showScroll end
        if downBtn then downBtn.visible = showScroll end

        -- Select + Abort always visible on list screens
        if selectBtn then selectBtn.visible = true end
        if listAbortBtn then listAbortBtn.visible = true end

    elseif state.screen == "confirm" then
        if headerLabel then headerLabel.visible = true end

        local src = state.selectedSource or { name = "?", x = 0, y = 0 }
        local dst = state.selectedDest or { name = "?", x = 0, y = 0 }
        local mode = (state.mode or "load"):upper()

        if confirmTitle then
            confirmTitle:setText("CONFIRM OPERATION")
            confirmTitle.visible = true
        end
        if confirmModeLabel then
            confirmModeLabel:setText("Mode: " .. mode)
            confirmModeLabel.visible = true
        end
        if confirmSourceLabel then
            confirmSourceLabel:setText("Source: " .. src.name .. " (" .. src.x .. "," .. src.y .. ")")
            confirmSourceLabel.visible = true
        end
        if confirmDestLabel then
            confirmDestLabel:setText("Dest:   " .. dst.name .. " (" .. dst.x .. "," .. dst.y .. ")")
            confirmDestLabel.visible = true
        end
        if confirmRunBtn then confirmRunBtn.visible = true end
        if confirmAbortBtn then confirmAbortBtn.visible = true end

    elseif state.screen == "executing" then
        if headerLabel then headerLabel.visible = true end

        local mode = (state.mode or "load"):upper()
        if execTitle then
            execTitle:setText(mode .. "ING...")
            execTitle.visible = true
        end
        if execStatusLabel then
            local status = state.operationStatus or ""
            execStatusLabel:setText(status)
            execStatusLabel.visible = true
        end
        if execAbortBtn then execAbortBtn.visible = true end

    elseif state.screen == "success" then
        if headerLabel then headerLabel.visible = true end
        if successLine1 then
            successLine1:setText("Operation complete!")
            successLine1.visible = true
        end
        if successLine2 then
            successLine2:setText("Returning to main screen...")
            successLine2.visible = true
        end

    elseif state.screen == "error" then
        if headerLabel then headerLabel.visible = true end
        if errorLine1 then
            errorLine1:setText("ERROR: " .. (state.operationError or "Unknown error"))
            errorLine1.visible = true
        end
        if errorLine2 then
            errorLine2:setText("Returning to main screen...")
            errorLine2.visible = true
        end

    elseif state.screen == "connection_lost" then
        if headerLabel then headerLabel.visible = true end
        if connLostLine1 then
            connLostLine1:setText("CONNECTION LOST")
            connLostLine1.visible = true
        end
        if connLostLine2 then
            connLostLine2:setText("Waiting for reconnection...")
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
            execStatusLabel:setText(state.operationStatus or "")
        end
        app:render()
    end
end

return M
