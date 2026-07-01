-- crane.lua v1.5.6 — CC: Create crane controller library
-- Extracted from crane.lua for use as a reusable module.
-- Loads configuration from src/config.lua.
--
-- Usage:
--   local crane = dofile("cccrane/src/lib/crane.lua")
--   crane.init()
--   crane.gotoXY(10, 5)
--   crane.pickup()
--   crane.done()
--
-- State persistence:
--   The crane tracks its position, sticker state, and whether an operation
--   is in progress in a file (/.crane-state). This survives chunk unloads so
--   that homing can be skipped when the crane shut down cleanly. If the crane
--   was interrupted mid-operation (chunk unload / Ctrl+T), the next run will
--   detect craneRunning=true and perform a full homing cycle.

local cfg = dofile("cccrane/src/config.lua")

local STATE_FILE = ".crane-state"
local STATE_FILE_TMP = ".crane-state.tmp"
local STATE_VERSION = 1

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local state = {
    version = STATE_VERSION,
    currentX = 0,
    currentY = 0,
    stickerOn = false,
    craneRunning = false,
}

local EMERGENCY_STOP = false

local function saveState()
    local f = fs.open(STATE_FILE_TMP, "w")
    if not f then
        print("WARNING: could not write state (tmp)")
        return
    end
    f.write(textutils.serialize(state, { compact = true }))
    f.close()
    fs.delete(STATE_FILE)
    fs.move(STATE_FILE_TMP, STATE_FILE)
end

local function loadState()
    if not fs.exists(STATE_FILE) then
        return false
    end
    local f = fs.open(STATE_FILE, "r")
    if not f then
        return false
    end
    local content = f.readAll()
    f.close()

    local ok, result = pcall(textutils.unserialize, content)
    if not ok or type(result) ~= "table" then
        return false
    end

    -- Merge loaded data with known defaults (forward compat)
    if type(result.currentX) == "number" then state.currentX = result.currentX end
    if type(result.currentY) == "number" then state.currentY = result.currentY end
    if type(result.stickerOn) == "boolean" then state.stickerOn = result.stickerOn end
    if type(result.craneRunning) == "boolean" then state.craneRunning = result.craneRunning end

    return true
end

------------------------------------------------------------
-- HELPERS
------------------------------------------------------------

local function relayTick()
    sleep(cfg.RELAY_DELAY)
end

local function shortTick()
    sleep(cfg.STICKER_TOGGLE_DELAY)
end

local function axisTick()
    sleep(cfg.AXIS_SWITCH_DELAY)
end

------------------------------------------------------------
-- PERIPHERALS
------------------------------------------------------------

local gear = peripheral.wrap(cfg.GEAR_PERIPHERAL)
local relay = peripheral.wrap(cfg.RELAY_PERIPHERAL)

------------------------------------------------------------
-- WAIT
------------------------------------------------------------

local function waitUntilStopped()
    while gear.isRunning() and not EMERGENCY_STOP do
        sleep(0.1)
    end
    -- Still wait for physical stop even after emergency stop
    while gear.isRunning() do
        sleep(0.1)
    end
    sleep(cfg.MOVE_SETTLE_DELAY)
end

------------------------------------------------------------
-- RELAYS
------------------------------------------------------------

local function resetRelays()
    relay.setOutput(cfg.AXIS_SIDE, false)
    relay.setOutput(cfg.LIFT_SIDE, false)
    relay.setOutput(cfg.STICKER_SIDE, false)
    relayTick()
end

local function enableLift()
    if EMERGENCY_STOP then return end
    relay.setOutput(cfg.LIFT_SIDE, true)
    relayTick()
end

------------------------------------------------------------
-- PULSE SYSTEM (STICKER)
------------------------------------------------------------

local function pulse(side)
    relay.setOutput(side, true)
    shortTick()
    relay.setOutput(side, false)
    shortTick()
end

------------------------------------------------------------
-- STICKER (TOGGLE LATCH)
------------------------------------------------------------

local function stickerGrab()
    if EMERGENCY_STOP then return end
    pulse(cfg.STICKER_SIDE) -- OFF -> ON (toggle latch)
    state.stickerOn = true
    saveState()
end

local function stickerRelease()
    if EMERGENCY_STOP then return end
    pulse(cfg.STICKER_SIDE) -- ON -> OFF (toggle latch)
    state.stickerOn = false
    saveState()
end

local function ensureStickerOff()
    if state.stickerOn then
        print("Sticker was ON, toggling OFF")
        pulse(cfg.STICKER_SIDE)
        state.stickerOn = false
        saveState()
    end
end

------------------------------------------------------------
-- AXES
------------------------------------------------------------

local function selectX()
    waitUntilStopped()
    if EMERGENCY_STOP then return end
    relay.setOutput(cfg.AXIS_SIDE, false)
    relay.setOutput(cfg.LIFT_SIDE, false)
    axisTick()
end

local function selectY()
    waitUntilStopped()
    if EMERGENCY_STOP then return end
    relay.setOutput(cfg.AXIS_SIDE, true)
    relay.setOutput(cfg.LIFT_SIDE, false)
    axisTick()
end

------------------------------------------------------------
-- GEARS
------------------------------------------------------------

local function runMove(distance, modifier)
    if distance <= 0 then return end
    if EMERGENCY_STOP then return end
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
-- AXIS MOVE (relative to tracked position)
------------------------------------------------------------

local function moveX(target)
    if target == state.currentX then return end
    local dx = target - state.currentX
    selectX()
    if EMERGENCY_STOP then return end
    if cfg.INVERSE_X then
        dx = -dx
    end
    if dx > 0 then
        moveForward(dx)
    else
        moveBackward(-dx)
    end
    if not EMERGENCY_STOP then
        state.currentX = target
        saveState()
    end
end

local function moveY(target)
    if target == state.currentY then return end
    local dy = target - state.currentY
    selectY()
    if EMERGENCY_STOP then return end
    if cfg.INVERSE_Y then
        dy = -dy
    end
    if dy > 0 then
        moveForward(dy)
    else
        moveBackward(-dy)
    end
    if not EMERGENCY_STOP then
        state.currentY = target
        saveState()
    end
end

------------------------------------------------------------
-- LIFT
------------------------------------------------------------

local TRANSPORT_HEIGHT = cfg.LIFT_HEIGHT - cfg.TRANSPORT_LOWER

local function lower()
    print("lower " .. cfg.LIFT_HEIGHT)
    enableLift()
    runMove(cfg.LIFT_HEIGHT, 1)
end

local function lowerTo(amount)
    if amount <= 0 then return end
    print("lower " .. amount)
    enableLift()
    runMove(amount, 1)
end

local function raise()
    print("raise " .. cfg.LIFT_HEIGHT + 3)
    enableLift()
    runMove(cfg.LIFT_HEIGHT + 3, -1)
end

local function raiseTo(amount)
    if amount <= 0 then return end
    print("raise " .. amount)
    enableLift()
    runMove(amount, -1)
end

------------------------------------------------------------
-- HOMING
------------------------------------------------------------

local function home()
    print("Homing...")
    resetRelays()
    raise()

    selectY()
    if cfg.INVERSE_Y then
        moveForward(cfg.MAX_Y)
    else
        moveBackward(cfg.MAX_Y)
    end

    selectX()
    if cfg.INVERSE_X then
        moveForward(cfg.MAX_X)
    else
        moveBackward(cfg.MAX_X)
    end

    waitUntilStopped()

    state.currentX = cfg.HOME_OFFSET_X
    state.currentY = cfg.HOME_OFFSET_Y
    state.stickerOn = false
    state.craneRunning = false

    saveState()
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

    print("Raise for transport")
    raiseTo(TRANSPORT_HEIGHT)
end

local function drop()
    print("Lower for drop")

    lowerTo(cfg.LIFT_HEIGHT)

    print("Sticker RELEASE")
    stickerRelease()

    print("Raise")
    raise()
end

------------------------------------------------------------
-- PUBLIC INIT / DONE
------------------------------------------------------------

--- Initialise the crane: load saved state, home if needed, mark as running.
function craneInit()
    resetRelays()

    local loaded = loadState()

    if loaded and not state.craneRunning then
        -- Clean shutdown from previous run -- reuse position, no homing needed.
        print("State loaded, crane idle at (" .. state.currentX .. ", " .. state.currentY .. ")")
        ensureStickerOff()
    else
        -- No state, corrupted state, or interrupted mid-operation -- full homing.
        if loaded and state.craneRunning then
            print("Previous operation was interrupted, homing...")
        else
            print("No saved state found, homing...")
        end
        home()
    end

    -- Mark operation as in-flight so a crash triggers homing on next start
    state.craneRunning = true
    saveState()
end

--- Finish crane operations: reset relays, mark crane as idle.
function craneDone()
    resetRelays()
    state.craneRunning = false
    saveState()
    print("Done.")
end

--- Explicitly mark the crane as running (protects against crash during command).
function craneMarkRunning()
    state.craneRunning = true
    saveState()
end

--- Explicitly mark the crane as idle (clean shutdown between commands).
function craneMarkIdle()
    state.craneRunning = false
    saveState()
end

--- Reset the emergency-stop flag (called after a new command is issued).
function craneClearStop()
    EMERGENCY_STOP = false
end

--- Trigger an emergency stop. Stops the motor immediately.
function craneEmergencyStop()
    EMERGENCY_STOP = true
    if gear then
        gear.setSpeed(0)
    end
end

--- Return the current stop-flag state.
function craneIsStopped()
    return EMERGENCY_STOP
end

--- Return the current internal state table (read-only snapshot).
function craneGetState()
    return {
        currentX = state.currentX,
        currentY = state.currentY,
        stickerOn = state.stickerOn,
        craneRunning = state.craneRunning,
    }
end

------------------------------------------------------------
-- EXPORT
------------------------------------------------------------

return {
    init = craneInit,
    done = craneDone,
    clearStop = craneClearStop,
    emergencyStop = craneEmergencyStop,
    isStopped = craneIsStopped,
    getState = craneGetState,

    markRunning = craneMarkRunning,
    markIdle = craneMarkIdle,

    -- Movement
    gotoXY = gotoXY,
    moveX = moveX,
    moveY = moveY,
    home = home,

    -- Pick / Drop
    pickup = pickup,
    drop = drop,

    -- Individual steps (for advanced use)
    lower = lower,
    lowerTo = lowerTo,
    raise = raise,
    raiseTo = raiseTo,
    stickerGrab = stickerGrab,
    stickerRelease = stickerRelease,
    selectX = selectX,
    selectY = selectY,
    resetRelays = resetRelays,
    enableLift = enableLift,
    waitUntilStopped = waitUntilStopped,

    -- Configuration
    config = cfg,
}
