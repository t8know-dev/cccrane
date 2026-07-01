-- crane-remote-config.lua — Remote control configuration
-- Place this file on the crane computer.
--
-- Set PANEL_ADDRESS to the ECNet2 identity key of the control panel.
-- You can obtain it by running crane-panel.lua — it prints its address on startup.

return {
    -- The ECNet2 public key (address) of the control panel
    PANEL_ADDRESS = "PASTE_PANEL_ADDRESS_HERE",

    -- Timing (seconds)
    HEARTBEAT_INTERVAL = 3,       -- how often to send STATUS while idle
    CONNECTION_TIMEOUT = 15,      -- panel marks crane as disconnected after this

    -- Reconnect exponential backoff
    RECONNECT_BACKOFF_INITIAL = 1,   -- first retry after 1s
    RECONNECT_BACKOFF_MULT = 1.5,    -- multiply by 1.5 each attempt
    RECONNECT_BACKOFF_MAX = 30,      -- cap at 30s

    -- Logging
    MAX_LOG_LINES = 50,
}
