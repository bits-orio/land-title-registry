#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFO="$SCRIPT_DIR/info.json"

NAME=$(grep -o '"name": *"[^"]*"' "$INFO" | head -1 | sed 's/.*"\([^"]*\)"/\1/')
VERSION=$(grep -o '"version": *"[^"]*"' "$INFO" | head -1 | sed 's/.*"\([^"]*\)"/\1/')
LINK_NAME="${NAME}_${VERSION}"

# A running Factorio holds the mod directory by its versioned path. Renaming
# it mid-session (which a version bump does) breaks every later file read:
# sprites and locale vanish, and starting a NEW game inside that process
# fails to load control.lua at all - the mod simply disappears. Warn loudly;
# the fix is always "restart Factorio".
if pgrep -x factorio >/dev/null 2>&1; then
    echo "WARNING: Factorio is running." >&2
    echo "         Relinking renames ${NAME}_<version>; the running process will" >&2
    echo "         lose this mod's files (missing graphics/locale, and a new game" >&2
    echo "         started in that process will not load the mod at all)." >&2
    echo "         Restart Factorio after this finishes." >&2
    echo "" >&2
fi

MOD_DIRS=(
    "$HOME/factorio/mods"
    "$HOME/.factorio/mods"
    "$HOME/factorio2/mods"
    "$HOME/factorio-2.1/mods"
)

for dir in "${MOD_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        echo "Skipping $dir (not found)"
        continue
    fi

    # Remove old symlinks pointing to this mod
    for link in "$dir/${NAME}_"*; do
        if [[ -L "$link" ]]; then
            echo "Removing old link: $link"
            rm "$link"
        fi
    done

    # Remove old packaged zips of this mod
    for zip in "$dir/${NAME}_"*.zip; do
        if [[ -f "$zip" ]]; then
            echo "Removing old zip: $zip"
            rm "$zip"
        fi
    done

    ln -s "$SCRIPT_DIR" "$dir/$LINK_NAME"
    echo "Created: $dir/$LINK_NAME -> $SCRIPT_DIR"
done
