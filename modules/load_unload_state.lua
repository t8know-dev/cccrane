-- modules/load_unload_state.lua — State management for crane load/unload monitor UI
-- Exports: getState(), updateState(changes), subscribe(callback), resetOperation()
--
-- Tracks screen flow, point selection, connection status, and operation state.
-- Uses a subscriber pattern so state changes trigger UI redraws.

local M = {}

local state = {
    -- Current screen in the wizard flow
    screen          = "main",  -- main | select_source | select_dest | confirm | executing | success | error | connection_lost

    -- Operation mode: "load" (pickup → drop) or "unload" (same, just labeled)
    mode            = nil,

    -- Point lists loaded from config files
    sourcePoints    = {},      -- array of {name, x, y}
    destPoints      = {},      -- array of {name, x, y}

    -- Current list scroll/selection state
    sourceIndex     = 1,       -- index into sourcePoints (1-based)
    destIndex       = 1,       -- index into destPoints (1-based)
    -- The resolved point records
    selectedSource  = nil,     -- {name=, x=, y=}
    selectedDest    = nil,     -- {name=, x=, y=}

    -- Operation execution
    operationStatus = "",      -- status/progress text during execution
    operationDone   = false,   -- true when operation completes (success or error)
    operationError  = nil,     -- error message string, or nil on success

    -- ECNet2 connection status (set by the entry point)
    connected       = false,
    craneId         = "?",
    registered      = false,
}

local subscribers = {}

function M.getState(key)
    if key then return state[key] end
    return state
end

function M.updateState(changes)
    local hasChanges = false
    for k, v in pairs(changes) do
        if state[k] ~= v then
            state[k] = v
            hasChanges = true
        end
    end
    if hasChanges then
        for _, cb in ipairs(subscribers) do
            pcall(cb, changes)
        end
    end
end

function M.subscribe(callback)
    table.insert(subscribers, callback)
end

--- Reset operation-specific fields before starting a new one.
function M.resetOperation()
    state.operationStatus = ""
    state.operationDone = false
    state.operationError = nil
end

return M
