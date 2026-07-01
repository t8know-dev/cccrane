# CC: Crane — ComputerCraft Gantry Crane Controller

A [ComputerCraft: Create](https://mods.twitch.tv/cccreate) program that controls a 2-axis gantry crane with a deployable hoist and sticker (toggle latch) grabber. Supports local CLI operation and remote control via ECNet2 encrypted networking.

## Features

- **2-axis movement** (X/Y) via sequenced gearshift drives
- **Automatic homing** — drives to the grid origin on startup (or on crash recovery)
- **Pick & place** — grabs blocks with a deployable sticker, transports them, and releases
- **Transport-safe height** — raises the load to a configurable intermediate height during transit
- **Persistent state tracking** — position, sticker, and operation state survive chunk unloads
- **Crash recovery** — detects interrupted operations (chunk unload / Ctrl+T) and re-homes automatically
- **Remote control via ECNet2** — encrypted wireless communication between a control panel computer and the crane computer
- **Monitor-based wizard UI** — load/unload panel for small monitors with point selection
- **Dual panel UIs** — full terminal GUI (`crane-panel`) or monitor wizard (`crane-load-unload`)
- **Saveable points** — named pickup/drop-off locations persisted to disk

## Project structure

```
cccrane/                          ← deploy root
├── crane.lua                     # CLI entry: crane <srcX> <srcY> <dstX> <dstY>
├── crane-client.lua              # Remote-control daemon (runs on the crane computer)
├── crane-panel.lua               # Full terminal GUI control panel (ECNet2 server)
├── crane-load-unload.lua         # Monitor-based load/unload wizard UI
│
├── src/                          # Application source
│   ├── config.lua                # Hardware config (dimensions, timing, peripherals)
│   ├── remote_config.lua         # Remote-control config (panel address, heartbeat)
│   └── lib/
│       ├── crane.lua             # Crane hardware control library
│       └── panel_ui.lua          # PixelUI-based terminal panel UI
│
├── lib/                          # Third-party libraries
│   ├── pixelui.lua               # PixelUI widget framework
│   └── shrekbox.lua              # PixelUI rendering engine
│
├── data/                         # Saved data
│   ├── pickup_points.lua         # Named pickup points
│   └── drop_points.lua           # Named drop-off points
│
├── modules/                      # Monitor wizard submodules
│   ├── load_unload_state.lua     # State management for load/unload UI
│   └── monitor_ui.lua            # Monitor rendering for load/unload UI
│
├── examples/                     # Example scripts
│   ├── ecnet_client.lua          # Minimal ECNet2 client example
│   ├── ecnet_server.lua          # Minimal ECNet2 server example
│   └── pixelui_example.lua       # PixelUI widget showcase
│
├── ecnet2/                       # ECNet2 networking library (third-party)
├── ccryptolib/                   # Crypto library: Chacha20, Ed25519, etc.
│
└── .crane-state                  # (auto) Persistent state file
```

## Requirements

- **ComputerCraft: Create** (or CC:Tweaked with Create addon)
- A **crane computer** with:
  - A **precision mechanism** (gear) — `gear.move(distance, modifier)`
  - A **redstone relay** — controls axis selection, lift, and sticker
  - A **wireless modem** on `top` (required for remote control)
- A **panel computer** (optional, for remote control) with a wireless modem on `top`

### Mechanical setup

| Component | Connection | Description |
|---|---|---|
| **Gantry** | — | Two orthogonal axes of movement (X, Y) |
| **Hoist** | Lift motor | Deployable vertical motion |
| **Sticker** | Toggle latch | Grips blocks (Create sticky piston) |
| Precision mechanism | `GEAR_PERIPHERAL` (right) | Drives selected axis or lift |
| Redstone relay | `RELAY_PERIPHERAL` (left) | Controls all three subsystems |

### Relay wiring

| Relay output | Signal | Function |
|---|---|---|
| `AXIS_SIDE` (front) | LOW = X, HIGH = Y | Axis selection gearshift |
| `LIFT_SIDE` (top) | HIGH = enable | Lift motor power |
| `STICKER_SIDE` (bottom) | Pulse = toggle | Sticker grab/release |

## Installation

Copy the repository to your ComputerCraft computer using `gitclone`:

```
gitclone cccrane jigga2
```

All files land in `/cccrane/`.

> If `gitclone` is unavailable, use `wget` for individual files:
> ```
> wget https://raw.githubusercontent.com/jigga2/cccrane/main/crane.lua
> mv crane.lua /cccrane/
> ```

## Usage

### Local CLI (single-computer)

Run a full pick-and-place cycle from the terminal:

```
cccrane/crane <srcX> <srcY> <dstX> <dstY>
```

Example — pick up at grid position (10, 5), move to (42, 30), and drop:

```
cccrane/crane 10 5 42 30
```

### Remote control (two computers)

**1. Start the control panel** (panel computer):

```
cccrane/crane-panel
```

The panel prints its ECNet2 address on startup:

```
=== Crane Control Panel ===
ECNet2 address: <public_key>
Copy this address to crane-remote-config.lua on the crane.
Waiting for connection...
```

**2. Configure the connection** (crane computer):

Edit `/cccrane/src/remote_config.lua` and set `PANEL_ADDRESS` to the panel's address:

```lua
return {
    PANEL_ADDRESS = "<paste_panel_address_here>",
    HEARTBEAT_INTERVAL = 3,
    CONNECTION_TIMEOUT = 15,
    RECONNECT_BACKOFF_INITIAL = 1,
    RECONNECT_BACKOFF_MULT = 1.5,
    RECONNECT_BACKOFF_MAX = 30,
    MAX_LOG_LINES = 50,
}
```

**3. Start the crane daemon** (crane computer):

```
cccrane/crane-client
```

The daemon connects to the panel, registers itself, and waits for commands.

### Monitor wizard (load/unload UI)

For a small monitor (2×1 block, 30 lines), run the wizard-style panel:

```
cccrane/crane-load-unload
```

This provides a touch-friendly picker for pickup/drop-off points and executes a full pick-and-drop cycle.

## Configuration

All tunable parameters are in `src/config.lua`:

| Parameter | Default | Description |
|---|---|---|
| `MAX_X` | 97 | Maximum X coordinate (grid width, blocks) |
| `MAX_Y` | 56 | Maximum Y coordinate (grid height, blocks) |
| `LIFT_HEIGHT` | 23 | Full hoist travel distance (blocks) |
| `TRANSPORT_LOWER` | 10 | How far below `LIFT_HEIGHT` to keep load during transit |
| `HOME_OFFSET_X` | 0 | Home position X offset |
| `HOME_OFFSET_Y` | 0 | Home position Y offset |
| `RELAY_DELAY` | 0.1 | Settling delay after relay state changes |
| `STICKER_TOGGLE_DELAY` | 0.1 | Settling delay for sticker pulsing |
| `AXIS_SWITCH_DELAY` | 0.1 | Settling delay after axis gearshift |
| `MOVE_SETTLE_DELAY` | 0.2 | Extra settling after gear movement stops |
| `GEAR_PERIPHERAL` | `"right"` | Side of the precision mechanism |
| `RELAY_PERIPHERAL` | `"left"` | Side of the redstone relay |
| `AXIS_SIDE` | `"front"` | Relay output for axis selection |
| `LIFT_SIDE` | `"top"` | Relay output for lift |
| `STICKER_SIDE` | `"bottom"` | Relay output for sticker |
| `INVERSE_X` | `false` | Invert X-axis movement direction |
| `INVERSE_Y` | `false` | Invert Y-axis movement direction |
| `MONITOR_PERIPHERAL` | `"monitor_15"` | Monitor peripheral name (load/unload UI) |

### Transport height

During transit the load is raised to `LIFT_HEIGHT - TRANSPORT_LOWER` instead of all the way up. Default: full lift = 23, transport height = 13.

- On pickup: lower 23 blocks → grab → raise to 13
- On drop: lower from 13 to 23 → release → raise 26 (23 + 3 clearance)

## Architecture

### Communication protocol (ECNet2)

The control panel acts as an ECNet2 **server** (Listener). The crane acts as a **client** (Connector). They communicate over the `"crane_control"` protocol with `textutils.serialize`/`textutils.unserialize`.

Message format:

```lua
{
    type = "request" | "response" | "event",
    body = { message_type = "...", ... }
}
```

| Message | Direction | Description |
|---|---|---|
| `REGISTER` | Crane → Panel | Identify after connect (crane_id, version) |
| `STATUS` | Crane → Panel | Position, sticker state, busy flag |
| `ACK` | Crane → Panel | Command acknowledgement (ok/error) |
| `COMMAND` | Panel → Crane | Command: GOTO, PICKUP, DROP, HOME, EMERGENCY_STOP, STATUS_QUERY |
| `CONFIG_QUERY` | Panel → Crane | Request crane config (dimensions, limits) |
| `CONFIG_RESPONSE` | Crane → Panel | Config data response |

Commands:

| Command | Params | Description |
|---|---|---|
| `GOTO` | `{ x, y }` | Move to absolute position |
| `PICKUP` | `{}` | Execute pick-up sequence |
| `DROP` | `{}` | Execute drop sequence |
| `HOME` | `{}` | Execute homing cycle |
| `EMERGENCY_STOP` | `{}` | Immediate stop |
| `STATUS_QUERY` | `{}` | Force status report |

### Connection lifecycle

```
Panel (Listener)                    Crane (Connector)
      |                                    |
      |   <-- ecnet2_request --             |
      |   -- accept("crane_panel") -->      |
      |   <-- REGISTER {crane_id} --        |
      |   -- CONFIG_QUERY -->               |
      |   <-- CONFIG_RESPONSE --            |
      |   <-- STATUS {idle} --              |
      |   -- COMMAND {GOTO} -->            |
      |   <-- ACK {ok} --                   |
      |   <-- STATUS {busy} --              |
      |   <-- STATUS {idle} --              |
```

### Resilience

| Scenario | Behaviour |
|---|---|
| **Panel address unknown to crane** | Configure once in `src/remote_config.lua` |
| **Wireless range / connection loss** | Crane heartbeats every 3s; panel timeout 15s → DISCONNECTED |
| **Crane busy, new command arrives** | Rejected with `ACK {status="error", message="Crane is busy"}` |
| **Panel restarts** | Crane detects send failure, reconnects with exponential backoff |
| **Crane restarts** | Panel detects disconnect; crane re-connects and re-registers |
| **Unexpected chunk unload** | `.crane-state` with `craneRunning=true` triggers homing on next start |

### State persistence

The crane saves its position and sticker state to `/.crane-state` after every physical change. On startup:

- **No file / corrupted** → full homing cycle
- **`craneRunning=false`** → skip homing, restore saved position
- **`craneRunning=true`** → previous run was interrupted → full homing

State is written atomically (temp file + rename) to prevent corruption from abrupt chunk unloads.

### Signal flow (local mode)

```
Computer
  ├── gear (precision mechanism) → drives the selected axis/lift
  └── relay (redstone relay)
        ├── AXIS_SIDE → axis selector (LOW=X, HIGH=Y)
        ├── LIFT_SIDE → lift enable
        └── STICKER_SIDE → sticker grab/release pulse
```

### Movement sequence

1. **Home** — raise hoist fully, drive to `(HOME_OFFSET_X, HOME_OFFSET_Y)`
2. **Move to source** — X-axis first, then Y-axis
3. **Pick up** — lower hoist → sticker grab → raise to transport height
4. **Move to destination** — Y-axis first, then X-axis
5. **Drop** — lower to transport height → sticker release → raise fully
6. **Done**

### Delay overview

| Delay | Value | Purpose |
|---|---|---|
| `RELAY_DELAY` | 0.1s | Between relay output changes |
| `STICKER_TOGGLE_DELAY` | 0.1s | While pulsing the sticker |
| `AXIS_SWITCH_DELAY` | 0.1s | After switching axes (gearshift) |
| `MOVE_SETTLE_DELAY` | 0.2s | After `gear.move()` reports stopped |
| Poll interval | 0.1s | In `sleep(0.1)` loop while gear is running |

## Troubleshooting

| Problem | Solution |
|---|---|
| `No saved state found, homing...` on every start | Check `/.crane-state` file permissions |
| Crane won't move | Check peripheral sides in `src/config.lua` |
| ECNet2 connection failure | Verify both computers have a modem on `top` and panel address is correct |
| Panel doesn't see crane | Check wireless range (use Ender modem / range extender) |
| Sticker doesn't grab | Check `STICKER_SIDE` output in config and toggle delay |
| Crane moves in wrong direction | Set `INVERSE_X` or `INVERSE_Y` to `true` in `src/config.lua` |
| `ecnet2_message` not handled | Ensure `ecnet2/` and `ccryptolib/` are fully downloaded |

## License

MIT
