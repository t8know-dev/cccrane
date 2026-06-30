--[[
config.lua — Crane configuration file
All tunable parameters are defined here. The main script (crane.lua) reads from this
file so you can adjust dimensions, timing, peripheral names, and polarity without
touching the logic.
--]]

return {
    -- Grid dimensions (in blocks). The crane can move within [0, MAX_X] × [0, MAX_Y].
    MAX_X = 97,
    MAX_Y = 56,

    -- Lift travel distance (in blocks). How far the hook lowers/raises.
    LIFT_HEIGHT = 23,

    -- Transport offset: during transit the load is raised to
    -- (LIFT_HEIGHT - TRANSPORT_LOWER) instead of all the way up.
    -- A higher value = lower transport position (more clearance from top stops).
    TRANSPORT_LOWER = 10,

    -- Home offset: after homing the crane is physically at (HOME_OFFSET_X, HOME_OFFSET_Y)
    -- in world coordinates. In CC: Create blocks are 1-indexed, so offset defaults to 1.
    HOME_OFFSET_X = 0,
    HOME_OFFSET_Y = 0,

    -- Timing delays (seconds). Tune these if the crane behaves erratically.
    RELAY_DELAY = 0.1,
    STICKER_TOGGLE_DELAY = 0.1,
    AXIS_SWITCH_DELAY = 0.1,
    MOVE_SETTLE_DELAY = 0.2,

    -- Peripheral names (as seen by peripheral.wrap)
    GEAR_PERIPHERAL = "right",
    RELAY_PERIPHERAL = "left",

    -- Redstone relay output sides (on the relay block)
    AXIS_SIDE = "top",
    LIFT_SIDE = "front",
    STICKER_SIDE = "bottom",

    -- Axis polarity: set INVERSE_X or INVERSE_Y to true if the respective
    -- motor moves in the opposite direction from what the coordinate system expects.
    INVERSE_X = false,
    INVERSE_Y = false,
}
