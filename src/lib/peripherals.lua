-- src/lib/peripherals.lua — Peripheral wait utilities
--
-- Blocks until a peripheral is available, handling chunk loading delays.
-- Uses the same pattern as ccloader's waitForPeripheral().
--
-- Usage:
--   local periph = dofile("cccrane/src/lib/peripherals.lua")
--   local gear = periph.waitForPeripheral(cfg.GEAR_PERIPHERAL, "Gear: " .. cfg.GEAR_PERIPHERAL)

local SCAN_INTERVAL = 1  -- seconds between peripheral scan retries

local M = {}

--- Wait for a peripheral to become available by name.
--- Retries indefinitely with pcall(peripheral.wrap) and informative messages.
---@param name string   The peripheral name (as seen by peripheral.wrap)
---@param label string? Optional human-readable label for log messages
---@return table         The wrapped peripheral object
function M.waitForPeripheral(name, label)
    label = label or tostring(name)
    local attempts = 0
    while true do
        local ok, periph = pcall(peripheral.wrap, name)
        if ok and periph then
            if attempts > 0 then
                term.setTextColor(colors.green)
                print("OK  " .. label)
                term.setTextColor(colors.white)
            end
            return periph
        end
        attempts = attempts + 1
        if attempts == 1 then
            term.setTextColor(colors.yellow)
            print("Waiting for: " .. label)
            term.setTextColor(colors.gray)
            print("  peripheral: " .. tostring(name))
            print("  (chunk may not be loaded)")
            term.setTextColor(colors.white)
        end
        os.sleep(SCAN_INTERVAL)
    end
end

return M
