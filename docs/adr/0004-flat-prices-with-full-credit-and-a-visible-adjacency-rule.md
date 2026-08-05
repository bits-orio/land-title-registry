# Flat step prices with full credit, and adjacency as a separate visible rule

Prices are flat per step — Trail 1, Rampart 3, Deed 5 cumulative — with full credit for already-held rights, so the total invested to reach a state is path-independent. Trail → Deed costs 4 exactly because Trail → Rampart → Deed costs 2 + 2. A player never routes through Rampart "for the discount"; Rampart is bought for its defensive rights.

Connectivity is enforced separately, as a binary claim-time rule: a new claim on a Wilderness cell must touch a cell the acting force already owns in any state. It is checked **only** at claim time. There is no global-connectivity maintenance — downgrades may disconnect territory, disconnected islands stay owned, and those islands remain valid adjacency sources. No flood-fill, no revocation, no reconnection requirement, ever.

This splits two concerns that Gridlocked's adjacency-discount cost formula fused into one piece of opaque arithmetic. Prices become legible (a player can predict a batch's cost by counting cells), and connectivity becomes a rule a player can see on the map rather than infer from a number.

Refunds are symmetric with the credit principle: each downgrade step refunds `step price × fh-refund-percent / 100`, so fully unwinding a Deed returns exactly that percentage of the 5 invested regardless of the path taken up. The default rate is deliberately low (25%) — claim, strip-mine, and downgrade must never be a free roundtrip. Fractional refunds are applied exactly, which is why balances are plain Lua numbers and `get_points` returns a number rather than an integer.

Batches are all-or-nothing. Applying "as many cells as you can afford" would make the outcome depend on internal iteration order; predictability wins.
