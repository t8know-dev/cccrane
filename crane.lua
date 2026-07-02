-- crane.lua — CC: Create crane controller
-- Thin CLI wrapper around src/lib/crane.lua.
--
-- Usage: crane <srcX> <srcY> <dstX> <dstY>

local crane = dofile("cccrane/src/lib/crane.lua")
local cfg = crane.config

------------------------------------------------------------
-- ARGUMENTS
------------------------------------------------------------

local args = {...}

if #args ~= 4 then
    print("Usage: crane <srcX> <srcY> <dstX> <dstY>")
    return
end

local srcX = tonumber(args[1])
local srcY = tonumber(args[2])
local dstX = tonumber(args[3])
local dstY = tonumber(args[4])

local function check(v, name, max)
    if not v then error(name .. " is not a number") end
    if v < 0 or v > max then
        error(name .. " must be in range 0.." .. max)
    end
end

check(srcX, "srcX", cfg.MAX_X)
check(srcY, "srcY", cfg.MAX_Y)
check(dstX, "dstX", cfg.MAX_X)
check(dstY, "dstY", cfg.MAX_Y)

------------------------------------------------------------
-- EXECUTE
------------------------------------------------------------

crane.init()

crane.gotoXY(srcX, srcY)
crane.pickup()

print("Switch X -> Y")
crane.moveY(dstY)

print("Switch Y -> X")
crane.moveX(dstX)

crane.drop()
crane.done()
