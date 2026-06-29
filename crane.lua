-- crane.lua v1.4.2

------------------------------------------------------------
-- KONFIGURACJA CZASÓW
------------------------------------------------------------

local MAX_X = 15
local MAX_Y = 15
local LIFT_HEIGHT = 4    -- FIXED: was 5 (spec says 4 blocks)

-- Przesuniecie home: po homingu dzwig jest fizycznie na pozycji
-- (HOME_OFFSET_X, HOME_OFFSET_Y) w ukladzie wspolrzednych swiata.
-- W Create bloki sa 1-indeksowane, wiec domyslnie offset = 1.
local HOME_OFFSET_X = 1
local HOME_OFFSET_Y = 1

local RELAY_DELAY = 0.1
local STICKER_TOGGLE_DELAY = 0.1
local AXIS_SWITCH_DELAY = 0.1
local MOVE_SETTLE_DELAY = 0.2

local gear = peripheral.wrap("Create_SequencedGearshift_0")

local axisRelay = peripheral.wrap("redstone_relay_13")
local liftRelay = peripheral.wrap("redstone_relay_14")
local stickerRelay = peripheral.wrap("redstone_relay_15")

local SIDE = "front"

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function relayTick()
    sleep(RELAY_DELAY)
end

local function shortTick()
    sleep(STICKER_TOGGLE_DELAY)
end

local function axisTick()
    sleep(AXIS_SWITCH_DELAY)
end

------------------------------------------------------------
-- ARGUMENTY
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

check(srcX, "srcX", MAX_X)
check(srcY, "srcY", MAX_Y)
check(dstX, "dstX", MAX_X)
check(dstY, "dstY", MAX_Y)

------------------------------------------------------------
-- WAIT
------------------------------------------------------------

local function waitUntilStopped()
    while gear.isRunning() do
        sleep(0.1)
    end
    -- dodatkowy delay po zatrzymaniu (domyslnie 8 tick)
    sleep(MOVE_SETTLE_DELAY)
end

------------------------------------------------------------
-- RELAYS
------------------------------------------------------------

local function resetRelays()
    axisRelay.setOutput(SIDE, false)
    liftRelay.setOutput(SIDE, false)
    stickerRelay.setOutput(SIDE, false)
    relayTick()
end

local function enableLift()
    liftRelay.setOutput(SIDE, true)
    relayTick()
end

------------------------------------------------------------
-- PULSE SYSTEM (STICKER)
------------------------------------------------------------

local function pulse(relay)
    relay.setOutput(SIDE, true)
    shortTick()
    relay.setOutput(SIDE, false)
    shortTick()
end

------------------------------------------------------------
-- STICKER (TOGGLE LATCH)
------------------------------------------------------------

local function stickerGrab()
    pulse(stickerRelay) -- OFF -> ON (toggle latch)
end

local function stickerRelease()
    pulse(stickerRelay) -- ON -> OFF (toggle latch)
end

------------------------------------------------------------
-- OSIE
------------------------------------------------------------

local function selectX()
    waitUntilStopped()
    axisRelay.setOutput(SIDE, false)
    liftRelay.setOutput(SIDE, false)
    axisTick()
end

local function selectY()
    waitUntilStopped()
    axisRelay.setOutput(SIDE, true)
    liftRelay.setOutput(SIDE, false)
    axisTick()
end

------------------------------------------------------------
-- GEARS
------------------------------------------------------------

local function runMove(distance, modifier)
    if distance <= 0 then return end
    gear.move(distance, modifier)
    waitUntilStopped()
end

local function moveForward(distance)
    if distance <= 0 then return end
    runMove(distance, -1)
end

local function moveBackward(distance)
    if distance <= 0 then return end
    runMove(distance, 1)
end

------------------------------------------------------------
-- POZYCJA (sledzenie bezwzgledne)
------------------------------------------------------------

local currentX = 0
local currentY = 0

------------------------------------------------------------
-- OSIE MOVE (relatywnie wzgledem sledzonej pozycji)
------------------------------------------------------------

local function moveX(target)
    if target == currentX then return end
    local dx = target - currentX
    selectX()
    if dx > 0 then
        moveForward(dx)
    else
        moveBackward(-dx)
    end
    currentX = target
end

local function moveY(target)
    if target == currentY then return end
    local dy = target - currentY
    selectY()
    if dy > 0 then
        moveForward(dy)
    else
        moveBackward(-dy)
    end
    currentY = target
end

------------------------------------------------------------
-- LINA
------------------------------------------------------------

local function lower()
    print("lower " .. LIFT_HEIGHT)

    enableLift()
    runMove(LIFT_HEIGHT, 1)
end

local function raise()
    print("raise " .. LIFT_HEIGHT)

    enableLift()
    runMove(LIFT_HEIGHT, -1)
end

------------------------------------------------------------
-- HOMING
------------------------------------------------------------

local function home()
    print("Homing...")

    resetRelays()

    raise()

    selectY()
    moveBackward(MAX_Y)

    selectX()
    moveBackward(MAX_X)

    waitUntilStopped()

    currentX = HOME_OFFSET_X
    currentY = HOME_OFFSET_Y

    resetRelays()
end

------------------------------------------------------------
-- MOVE LOGIC
------------------------------------------------------------

local function gotoXY(x, y)
    print("Move X -> " .. x)
    moveX(x)

    print("Move Y -> " .. y)
    moveY(y)
end

------------------------------------------------------------
-- PICKUP / DROP
------------------------------------------------------------

local function pickup()
    print("Lower")
    lower()

    print("Sticker GRAB")
    stickerGrab()

    print("Raise")
    raise()
end

local function drop()
    print("Lower")
    lower()

    print("Sticker RELEASE")
    stickerRelease()    -- FIXED: bylo stickerGrab() - zwalniamy blok, nie chwytamy

    print("Raise")
    raise()
end

------------------------------------------------------------
-- START
------------------------------------------------------------

resetRelays()

home()

gotoXY(srcX, srcY)

pickup()

print("Switch X -> Y")

moveY(dstY)

print("Switch Y -> X")

moveX(dstX)

drop()

resetRelays()

print("Done.")