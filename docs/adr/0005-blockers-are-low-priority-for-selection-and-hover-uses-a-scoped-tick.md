# Blockers take LOW selection priority; hover feedback uses a scoped `on_nth_tick`

Blocker entities are given `selection_priority = 5` — deliberately near the bottom of the 0–255 range, well below the default 50 — so that a blocker's 32×32 selection box never steals the cursor from the entities the player has actually built. Per-cell hover feedback instead comes from an `on_nth_tick` handler registered only while at least one player holds the survey tool, resolving the hovered cell by arithmetic on the cursor position.

This is the opposite of what a reader might assume, so it is worth stating why.

Under a binary claimed/unclaimed model, blocker priority barely matters: a blocker exists only on unclaimed land, where nothing is built and there is nothing to steal selection from. The tiered ladder changes that. Land Title Registry keeps a blocker on Trail and Rampart cells, which are full of the owner's belts, rails, turrets, and poles. A high-priority full-cell selection box over those would hijack hover, tooltips, and pipette from every one of them, permanently, whether or not the survey tool is in hand.

The high-priority idea originally came from wanting `on_selected_entity_changed` to drive hover feedback. It buys nothing for the drag path — `selection_priority` governs cursor selection, not area selection, and the selection handlers derive their cells from `event.area` and ignore `event.entities` entirely. And it could never have covered Deed cells, which have no blocker to hover.

## Consequences

- The scoped `on_nth_tick` is a **sanctioned exception** to the no-unconditional-`on_tick` rule, not a violation of it. It registers when a player picks up the survey tool and unregisters when the last holder puts it down, so an idle game pays nothing. Do not "clean this up" by moving it to an unconditional handler, and do not remove it in favour of `on_selected_entity_changed`.
- Hover feedback works uniformly across all four states, Deed included.
- Do not raise `selection_priority` later "so the survey tool picks blockers up reliably" — area selection already does, and raising it re-breaks entity selection inside owned cells.
