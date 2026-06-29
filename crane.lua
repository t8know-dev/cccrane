-- crane.lua v1.4.0

------------------------------------------------------------
-- KONFIGURACJA CZASÓW
------------------------------------------------------------

local MAX_X = 15
local MAX_Y = 15
local LIFT_HEIGHT = 4    -- FIXED: was 5 (spec says 4 blocks)

local RELAY_DELAY = 0.4            -- 8 tick
local STICKER_TOGGLE_DELAY = 0.1   -- 2 tick
local AXIS_SWITCH_DELAY = 0.4      -- 8 tick

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
        sleep(1)
    end
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

-- resetSticker: dwa pulse'y = netto brak zmiany stanu.
-- To pozwala "odswiezyc" zatrzask stickera bez puszczania bloku,
-- co jest wymagane po kazdym zatrzymaniu osi podczas transportu.
-- Gdyby byl tu pojedynczy pulse, sticker przelaczylby sie w OFF
-- i blok spadlby podczas jazdy.
local function resetSticker()
    pulse(stickerRelay) -- OFF
    shortTick()
    pulse(stickerRelay) -- ON  (netto: stan niezmieniony)
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

local function moveForward(distance)
    if distance <= 0 then return end
    waitUntilStopped()
    gear.move(distance, -1)
end

local function moveBackward(distance)
    if distance <= 0 then return end
    waitUntilStopped()
    gear.move(distance, 1)
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
    waitUntilStopped()

    gear.move(LIFT_HEIGHT, 1)
end

local function raise()
    print("raise " .. LIFT_HEIGHT)

    enableLift()
    waitUntilStopped()

    gear.move(LIFT_HEIGHT, -1)
end

------------------------------------------------------------
-- HOMING
------------------------------------------------------------

local function home()
    print("Homing...")

    stickerRelease()    -- FIXED: wylaczenie stickera (było resetSticker ktory nie zmienial stanu)
    resetRelays()

    raise()

    selectY()
    moveBackward(MAX_Y)

    selectX()
    moveBackward(MAX_X)

    waitUntilStopped()

    currentX = 0
    currentY = 0

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
resetSticker()

moveY(dstY)

print("Switch Y -> X")
resetSticker()

moveX(dstX)

drop()

resetRelays()

print("Done.")