---
name: bump-version
description: Bump Freehold's version in info.json, refresh user-facing docs, write the changelog entry, relink the mod, and cut a release.
---

# Bump Version

## When to use
When the user asks to bump the version, release a new version, or after the version in `info.json` has been changed.

## Steps

1. **Bump the version in `info.json`** if not already done. **Default to a patch bump** (e.g. `0.1.0` → `0.1.1`). Only do a minor or major bump if the user explicitly asks for one — do not infer from the diff.

   Semver components (https://semver.org/), given a version `MAJOR.MINOR.PATCH`:
   - **PATCH** — backwards-compatible bug fixes. Default. Increment the third number; reset nothing. `0.1.0` → `0.1.1`.
   - **MINOR** — backwards-compatible new functionality. Only when the user requests it. Increment the second number; reset patch to 0. `0.1.1` → `0.2.0`.
   - **MAJOR** — incompatible / breaking changes. Only when the user requests it. Increment the first number; reset minor and patch to 0. `0.2.0` → `1.0.0`.

   For Freehold, treat these as MAJOR-worthy breakage: a change to the `freehold` remote interface's function signatures, a removed or renamed custom event, a removed console command, or a storage-schema change that ships without a migration.

2. **Verify user-facing docs** are still accurate for the changes since the last release:
   - `README.md` — the canonical, external-facing description (mod portal viewers, GitHub readers). Must carry the Gridlocked credit line verbatim and state the shared-surface limitation honestly.
   - `docs/API.md` — the `freehold` remote interface and custom-event payloads. This is a **compatibility contract**: any signature or payload change since the last release must be reflected here, and a breaking one belongs in the changelog's Changes section, spelled out.
   - `CONTEXT.md` — the domain glossary. If a release introduced or renamed a domain term, update it. Never let code and glossary drift.

   All must be **correct**: no claim that contradicts current behavior. Do not invent or expand claims to features that have not been tested. Show any doc edits to the user for approval before committing.

3. **Verify locale integrity**: run `python3 tools/check_locale.py`. It fails the release if any key the Lua references is missing *or defined in the wrong section* — blind `cat >>` appends land at the end of the file, which is some other `[section]`, and the runtime lookup under `[freehold]` then misses silently ("Unknown key" in game).

4. **Check for a storage migration.** If the release changes `storage`'s schema, the blocker prototypes, or the render scheme, it must ship a file in `migrations/` and a bump of `storage.meta.version` in the same release. A schema change without a migration is a release blocker, not a follow-up.

5. **Generate a changelog entry** at the top of `changelog.txt`:
   - Determine the previous version's git tag (format: `v<old_version>`). If no tag exists, use `git log` to find commits since the last changelog entry.
   - Collect the diff: `git log --pretty=format:"- %s" v<old_version>..HEAD` (exclude "Bump version" commits).
   - Write a new entry at the **top** of `changelog.txt` following the existing format exactly:
     ```
     ---------------------------------------------------------------------------------------------------
     Version: <new_version>
     Date: <YYYY-MM-DD>
       Features:
         - ...
       Changes:
         - ...
       Bugfixes:
         - ...
     ```
   - Only include sections (Features, Changes, Bugfixes) that have entries. Categorize each commit appropriately. Reword commit messages into clear, user-facing descriptions — don't just paste raw commit subjects. Use the domain vocabulary from `CONTEXT.md`: **cell**, never "chunk"; **Land points**, not "currency".
   - Show the draft entry to the user for approval before writing it.

6. **Recreate mod symlinks** by running:
   ```bash
   ./link-mod.sh
   ```
   This removes old `freehold_*` symlinks and creates new ones with the current version in every Factorio mods directory that exists on this machine.

   **Tell the user to restart Factorio afterwards.** The rename breaks the mod directory path a running process holds: sprites and locale stop resolving mid-session, and starting a new game inside that same process fails to load `control.lua` entirely — the mod appears to vanish. `link-mod.sh` warns when it detects a running Factorio, but the warning is only useful if it is passed on.

7. **Commit the version bump**: stage `info.json`, `changelog.txt`, any `migrations/` file, and any doc edits from step 2. Commit with message: `Bump version to <new_version>` (or `Release <new_version>: <one-line summary>` if substantial doc/feature work shipped — match the recent commit history's style).

8. **Release** (when the user asks): push the bump commit, then run `./tools/release.sh`. The script verifies the changelog entry, creates and pushes `v<new_version>`, and the GitHub Actions workflow takes over (build zip → GitHub release → Discord → mod portal upload).
   - The workflow fails fast if the tag and `info.json` version disagree.
   - If the mod-portal upload step fails (portal outage, etc.), the GH release and tag remain. Re-run the upload via the **Upload to Mod Portal** workflow (Actions tab → workflow_dispatch). The upload script is idempotent — it noops if the version is already published.
   - Discord and mod-portal steps are skipped when their secrets are unset, so the GitHub release always publishes.
   - Required secrets on the GitHub repo: `FACTORIO_API_KEY` (scope: ModPortal: Upload Mods), and optionally `DISCORD_WEBHOOK` and `DISCORD_ANNOUNCEMENTS_WEBHOOK`.
   - **First mod-portal release only:** the Factorio upload API adds a *release* to an *existing* mod page. Create the `freehold` mod page once on mods.factorio.com by hand before the first portal upload can succeed.
