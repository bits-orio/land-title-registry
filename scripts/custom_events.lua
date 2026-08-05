-- Custom event ids, generated once per session at control.lua root scope.
-- Ids are regenerated every session and must NEVER be stored in storage —
-- consumers resolve them via the remote interface's get_event_id (M4).

return {
  on_cell_claimed = script.generate_event_name(),
  on_cell_downgraded = script.generate_event_name(),
  on_points_changed = script.generate_event_name(),
}
