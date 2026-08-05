-- Single source of truth for the per-state palette, shared between runtime
-- rendering (scripts/render.lua requires this) and the overlay generator
-- (tools/gen_overlays.py PARSES this file — keep the literal `name = { r =
-- N, g = N, b = N }` shape). Components are 0-255.
--
-- The gradient reads busy-to-calm as land rises: red -> orange -> yellow ->
-- green/clear.
return {
  wilderness = { r = 214, g = 48, b = 38 },
  trail = { r = 222, g = 126, b = 38 },
  rampart = { r = 224, g = 186, b = 48 },
  deed = { r = 90, g = 170, b = 82 },
}
