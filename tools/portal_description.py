#!/usr/bin/env python3
"""Render README.md as the mod-portal page description.

The README is written for GitHub, where repo-relative links (docs/API.md,
LICENSE, docs/adr/) resolve; on the portal they 404 (playtest report:
"a lot of links are broken"). This rewrites every relative markdown link
target to an absolute GitHub URL under the homepage from info.json, and
prints the result to stdout. External links, anchors, and mailto are left
alone. Used by tools/sync_portal_description.sh and the first-publish
branch of tools/upload_mod_portal.sh.

Run from the repo root:  python3 tools/portal_description.py
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    homepage = json.loads((ROOT / "info.json").read_text())["homepage"].rstrip("/")
    base = homepage + "/blob/master/"
    text = (ROOT / "README.md").read_text()

    def rewrite(match):
        target = match.group(1)
        if re.match(r"^(https?://|#|mailto:)", target):
            return match.group(0)
        # Strip an explicit ./ prefix only — lstrip("./") eats the leading
        # dot of dotfile paths like .claude/skills/.
        if target.startswith("./"):
            target = target[2:]
        return "](" + base + target + ")"

    # ](target) with no closing-paren inside the target — covers links and
    # images alike; titles ("](x \"t\")") are not used in this README.
    sys.stdout.write(re.sub(r"\]\(([^)\s]+)\)", rewrite, text))


if __name__ == "__main__":
    main()
