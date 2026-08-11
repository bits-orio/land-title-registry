#!/usr/bin/env bash
# Sync the mod-portal page description from the repo README (rendered
# portal-ready by tools/portal_description.py — absolute links instead of
# GitHub-relative ones). Idempotent: the portal stores whatever is sent.
#
# Usage: tools/sync_portal_description.sh
# Env:   FACTORIO_API_KEY (required) — token with "ModPortal: Edit Mods" scope
#
# API: https://wiki.factorio.com/Mod_details_API
set -euo pipefail

: "${FACTORIO_API_KEY:?FACTORIO_API_KEY env var not set}"
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

MOD=$(jq -r .name info.json)
DESCRIPTION=$(python3 tools/portal_description.py)

RESPONSE=$(curl -sS \
    -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer ${FACTORIO_API_KEY}" \
    --form-string "mod=${MOD}" \
    --form-string "description=${DESCRIPTION}" \
    "https://mods.factorio.com/api/v2/mods/edit_details")

HTTP=$(echo "$RESPONSE" | tail -n1 | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '$d')
echo "edit_details HTTP ${HTTP}"
echo "$BODY"

if [[ "$HTTP" -lt 200 ]] || [[ "$HTTP" -ge 300 ]]; then
    echo "edit_details failed" >&2
    exit 1
fi
SUCCESS=$(echo "$BODY" | jq -r '.success // false')
[[ "$SUCCESS" == "true" ]] || { echo "edit_details returned non-success" >&2; exit 1; }
echo "portal description synced for ${MOD}"
