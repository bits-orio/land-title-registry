-- The key the driver (dev/run-drag.sh) presses between drags. It arrives as
-- synced input, so the server and the client log the same line at the same
-- tick.
data:extend({
  { type = "custom-input", name = "ltr-drag-probe-mark", key_sequence = "CONTROL + ALT + M", action = "lua" },
})
