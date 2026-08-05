# The cell registry is the single source of truth; blockers and renders are derived

`storage.cells[surface_index][cell_key]` is the authoritative record of every claimed cell. Blocker entities and render objects are derived state: they must always be reconstructible from the registry alone, and no code path may treat their presence or absence as authoritative. When registry and world disagree, the registry wins and the world is rebuilt to match — that is what `/fh-rebuild` is for.

Supporting choices:

- **Wilderness cells are not stored.** Absence of a key means Wilderness, which keeps the registry proportional to claimed land rather than to explored land. `"wilderness"` is never a stored state value.
- **No `LuaEntity` references in `storage`.** Blockers are found with `surface.find_entity(name, cell_center)` when a cell is operated on. Only `script.register_on_object_destroyed` registration ids are persisted, so `on_object_destroyed` can clean up.
- **`storage.meta.version` from day one**, with a `migrations/` folder that exists even while empty. Any change to the storage schema, the blocker prototypes, or the render scheme ships with a migration in the same release.

The alternative — inferring ownership by querying the world for blocker entities — was rejected because it makes every other mod that can destroy an entity a source of silent state loss, and because it offers no recovery path when the two drift.
