#!/usr/bin/env bash
# Upload a built mod zip to the Factorio mod portal.
# Idempotent: skips upload (exit 0) if the version is already published.
# First release: when the mod has no portal page yet, the PUBLISH flow is
# used instead — it creates the page and the first release in one pass,
# seeded with the repo README as the page description, MIT, and the
# source link.
#
# Usage: tools/upload_mod_portal.sh <mod_name> <version> <zip_path>
# Env:   FACTORIO_API_KEY (required) — token with "ModPortal: Upload Mods"
#        scope ("ModPortal: Publish Mods" additionally for the first release)
#
# APIs: https://wiki.factorio.com/Mod_upload_API
#       https://wiki.factorio.com/Mod_publish_API
set -euo pipefail

MOD="${1:?mod name required}"
VERSION="${2:?version required}"
ZIP="${3:?zip path required}"

: "${FACTORIO_API_KEY:?FACTORIO_API_KEY env var not set}"
[[ -f "$ZIP" ]] || { echo "zip not found: $ZIP" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

echo "::group::Idempotency check"
# Public endpoint — no auth needed. /full includes the releases array with
# every published version. If our version is already there, this is a re-run
# and we should noop.
MOD_EXISTS=1
PORTAL_INFO=$(curl -fsSL "https://mods.factorio.com/api/mods/${MOD}/full" || echo "")
if [[ -z "$PORTAL_INFO" ]]; then
    echo "mod '${MOD}' has no portal page yet — publishing (creates the page)"
    MOD_EXISTS=0
else
    EXISTING=$(echo "$PORTAL_INFO" \
        | jq -r --arg v "$VERSION" '.releases[]? | select(.version == $v) | .version')
    if [[ "$EXISTING" == "$VERSION" ]]; then
        echo "version ${VERSION} already published to mod portal — skipping upload"
        echo "::endgroup::"
        exit 0
    fi
fi
echo "::endgroup::"

if [[ "$MOD_EXISTS" -eq 1 ]]; then
    INIT_URL="https://mods.factorio.com/api/v2/mods/releases/init_upload"
    INIT_KIND="init_upload"
else
    INIT_URL="https://mods.factorio.com/api/v2/mods/init_publish"
    INIT_KIND="init_publish"
fi

echo "::group::Step 1 — ${INIT_KIND}"
INIT_RESPONSE=$(curl -sS \
    -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer ${FACTORIO_API_KEY}" \
    -F "mod=${MOD}" \
    "$INIT_URL")

INIT_HTTP=$(echo "$INIT_RESPONSE" | tail -n1 | cut -d: -f2)
INIT_BODY=$(echo "$INIT_RESPONSE" | sed '$d')

# Don't echo the body unredacted — it contains a one-shot upload URL with
# embedded auth that we still need to use in step 2. Show structure only.
echo "${INIT_KIND} HTTP ${INIT_HTTP}"

if [[ "$INIT_HTTP" -lt 200 ]] || [[ "$INIT_HTTP" -ge 300 ]]; then
    echo "${INIT_KIND} failed:" >&2
    echo "$INIT_BODY" >&2
    exit 1
fi

UPLOAD_URL=$(echo "$INIT_BODY" | jq -r '.upload_url // empty')
if [[ -z "$UPLOAD_URL" ]]; then
    echo "init_upload returned no upload_url:" >&2
    echo "$INIT_BODY" >&2
    exit 1
fi
echo "got upload_url"
echo "::endgroup::"

echo "::group::Step 2 — upload zip"
# Publish additionally seeds the new page: license and source link, plus
# the repo README as the long description (the portal renders markdown)
# when the script runs from a checkout that has one.
PUBLISH_FIELDS=()
if [[ "$MOD_EXISTS" -eq 0 ]]; then
    PUBLISH_FIELDS+=(-F "license=default_mit" -F "category=content")
    if [[ -f info.json ]]; then
        HOMEPAGE=$(jq -r '.homepage // empty' info.json)
        [[ -n "$HOMEPAGE" ]] && PUBLISH_FIELDS+=(-F "source_url=${HOMEPAGE}")
    fi
    if [[ -f README.md && -f tools/portal_description.py ]]; then
        # Portal-ready render: relative links rewritten absolute.
        DESC_FILE=$(mktemp)
        python3 tools/portal_description.py > "$DESC_FILE"
        PUBLISH_FIELDS+=(-F "description=<${DESC_FILE}")
    fi
fi

UPLOAD_RESPONSE=$(curl -sS \
    -w "\nHTTP_CODE:%{http_code}" \
    -F "file=@${ZIP}" \
    "${PUBLISH_FIELDS[@]}" \
    "$UPLOAD_URL")

UPLOAD_HTTP=$(echo "$UPLOAD_RESPONSE" | tail -n1 | cut -d: -f2)
UPLOAD_BODY=$(echo "$UPLOAD_RESPONSE" | sed '$d')

echo "upload HTTP ${UPLOAD_HTTP}"
echo "$UPLOAD_BODY"

if [[ "$UPLOAD_HTTP" -lt 200 ]] || [[ "$UPLOAD_HTTP" -ge 300 ]]; then
    echo "upload failed" >&2
    exit 1
fi

SUCCESS=$(echo "$UPLOAD_BODY" | jq -r '.success // false')
if [[ "$SUCCESS" != "true" ]]; then
    echo "upload returned non-success body" >&2
    exit 1
fi

echo "uploaded ${MOD} ${VERSION} to mod portal"
echo "::endgroup::"
