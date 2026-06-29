# CC: Crane — ComputerCraft Gantry Crane Controller

A [ComputerCraft: Create](https://mods.twitch.tv/cccreate) program that controls a 2-axis gantry crane with a deployable hoist and sticker (toggle latch) grabber. Designed for the Create mod.

## Features

- **2-axis movement** (X/Y) via sequenced gearshift drives
- **Automatic homing** — drives to the grid origin on startup (or on crash recovery)
- **Pick & place** — grabs blocks with a deployable sticker, transports them, and releases
- **Transport-safe height** — raises the load to a configurable intermediate height during transit
- **Persistent state tracking** — position, sticker, and operation state survive chunk unloads
- **Crash recovery** — detects interrupted operations (chunk unload / Ctrl+T) and re-homes automatically
- **Status feedback** — prints every step to the terminal

## Requirements

- **ComputerCraft: Create** (or CC:Tweaked with Create addon)
- A **computer** with:
  - A **precision mechanism** (gear) on the right side — `gear.move(distance, modifier)`
  - A **redstone relay** on the bottom — controls the three subsystems
- **Mechanical setup**:
  - **Gantry** with two orthogonal axes of movement (X, Y)
  - **Deployable hoist** (lift) for vertical motion
  - **Sticker** (Create sticky piston / toggle latch) for gripping blocks
  - Axis selector: relay output on `back` side selects X (LOW) or Y (HIGH)
  - Lift motor: relay output on `left` side enables lift movement
  - Sticker toggle: relay output on `bottom` side pulses the sticker

## Installation

Copy both files to your ComputerCraft computer:

```
wget https://raw.githubusercontent.com/your-org/cccrane/main/crane.lua
wget https://raw.githubusercontent.com/your-org/cccrane/main/config.lua
```

## Usage

```
crane <srcX> <srcY> <dstX> <dstY>
```

Picks up a block at `(srcX, srcY)` and drops it at `(dstX, dstY)`. Coordinates are in the crane's internal block grid, where `(0, 0)` is the home position after homing (with offset applied).

### Example

```
crane 10 5 42 30
```

Pick up at grid position (10, 5), move to (42, 30), and drop.

## Configuration

All tunable parameters are in `config.lua`:

| Parameter | Default | Description |
|---|---|---|
| `MAX_X` | 97 | Maximum X coordinate (grid width) |
| `MAX_Y` | 56 | Maximum Y coordinate (grid height) |
| `LIFT_HEIGHT` | 23 | Full hoist travel distance in blocks |
| `TRANSPORT_LOWER` | 10 | How many blocks below `LIFT_HEIGHT` to keep the load during transit |
| `HOME_OFFSET_X` | 0 | Home position X offset (in world coordinates) |
| `HOME_OFFSET_Y` | 0 | Home position Y offset (in world coordinates) |
| `RELAY_DELAY` | 0.1 | Settling delay after relay state changes |
| `STICKER_TOGGLE_DELAY` | 0.1 | Settling delay for sticker toggling |
| `AXIS_SWITCH_DELAY` | 0.1 | Settling delay after axis gear change |
| `MOVE_SETTLE_DELAY` | 0.2 | Extra settling delay after a gear movement stops |
| `GEAR_PERIPHERAL` | `"right"` | Side of the precision mechanism (gear) |
| `RELAY_PERIPHERAL` | `"bottom"` | Side of the redstone relay |
| `AXIS_SIDE` | `"back"` | Relay output for axis selection |
| `LIFT_SIDE` | `"left"` | Relay output for lift |
| `STICKER_SIDE` | `"bottom"` | Relay output for sticker |
| `INVERSE_X` | `false` | Invert X-axis movement direction |
| `INVERSE_Y` | `true` | Invert Y-axis movement direction |

### Transport height

During transit the load is raised to `LIFT_HEIGHT - TRANSPORT_LOWER` instead of all the way up. This saves time while still giving enough clearance. The default values mean:

- Full lift: 23 blocks
- Transport height: 23 - 10 = **13 blocks**
- On pickup: lowers 23 blocks, grabs, raises to 13 blocks
- On drop: lowers from 13 to 23, releases, raises 23 blocks

## Architecture

```
crane.lua        — Main program: arguments, movement logic, and sequencing
config.lua       — Configuration constants (dimensions, timing, peripherals)
.crane-state     — (auto) Persistent state: position, sticker, operation flag
```

### State persistence

The crane saves its position and sticker state to `.crane-state` after every physical change. On startup it checks this file:

- **No file / corrupted file** → full homing cycle
- **File present, `craneRunning=false`** → skip homing, restore saved position
- **File present, `craneRunning=true`** → previous run was interrupted (chunk unload / Ctrl+T) → full homing

State is written using an atomic write pattern (temp file + rename) to prevent corruption from abrupt chunk unloads.

### Signal flow

```
Computer
  ├── gear (precision mechanism) → drives the selected axis/lift
  └── relay (redstone relay)
        ├── AXIS_SIDE → axis selector (LOW=X, HIGH=Y)
        ├── LIFT_SIDE → lift enable
        └── STICKER_SIDE → sticker grab/release pulse
```

### Movement sequence

1. **Home** — raise hoist fully, then drive to grid corner `(HOME_OFFSET_X, HOME_OFFSET_Y)`
2. **Move to source** — X-axis first, then Y-axis
3. **Pick up** — lower hoist → sticker grab → raise to transport height
4. **Move to destination** — Y-axis first (the load is already), then X-axis
5. **Drop** — lower to transport height → sticker release → raise fully
6. **Done**

### Delay overview

| Delay | Purpose |
|---|---|
| `RELAY_DELAY` 0.1s | Between relay output changes |
| `STICKER_TOGGLE_DELAY` 0.1s | While pulsing the sticker |
| `AXIS_SWITCH_DELAY` 0.1s | After switching axes (gearshift) |
| `MOVE_SETTLE_DELAY` 0.2s | After `gear.move()` reports stopped |
| `sleep(0.1)` in loop | Polling interval while gear is running |

## License

MIT
