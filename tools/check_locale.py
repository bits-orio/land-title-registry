#!/usr/bin/env python3
"""Verify every locale key the Lua references exists in the right section.

Catches the two failure modes that have actually bitten this repo:
  1. A key referenced in Lua but never defined (renders as "Unknown key").
  2. A key defined in the WRONG section — blind `cat >>` appends land at the
     end of the file, which is some other [section], so the runtime lookup
     under [freehold] misses even though the text is present.

Dynamic keys built by concatenation ("freehold.hover-" .. state) are checked
by prefix: at least one key with that prefix must exist in [freehold].

Run from the repo root:  python3 tools/check_locale.py
Exit status is non-zero when something is missing, so it can gate a release.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "locale/en/freehold.cfg"
RUNTIME_SECTION = "freehold"


def parse_sections(text):
    sections, current = {}, None
    for line in text.split("\n"):
        header = re.match(r"^\[(.+)\]$", line.strip())
        if header:
            current = header.group(1)
            sections.setdefault(current, set())
            continue
        if current and "=" in line and not line.strip().startswith("#"):
            sections[current].add(line.split("=", 1)[0].strip())
    return sections


def lua_sources():
    for folder in ("scripts", "compat", "prototypes"):
        yield from (ROOT / folder).glob("*.lua")
    yield ROOT / "control.lua"


def main():
    sections = parse_sections(CFG.read_text())
    runtime = sections.get(RUNTIME_SECTION, set())

    exact, prefixes = set(), set()
    for path in lua_sources():
        text = path.read_text()
        # Dynamic first, so its prefix is not also counted as an exact key.
        for prefix in re.findall(r'"freehold\.([a-z0-9-]*-)"\s*\.\.', text):
            prefixes.add(prefix)
        for key in re.findall(r'"freehold\.([a-z0-9-]+)"', text):
            if not key.endswith("-"):
                exact.add(key)

    problems = []
    for key in sorted(exact):
        if key in runtime:
            continue
        elsewhere = [s for s, keys in sections.items() if key in keys]
        if elsewhere:
            problems.append(f"WRONG SECTION: {key} is in [{elsewhere[0]}], must be in [{RUNTIME_SECTION}]")
        else:
            problems.append(f"MISSING: {key}")

    for prefix in sorted(prefixes):
        if not any(k.startswith(prefix) for k in runtime):
            problems.append(f"MISSING (dynamic): no [{RUNTIME_SECTION}] key starts with {prefix!r}")

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} locale problem(s).")
        return 1
    print(f"locale OK — {len(exact)} exact keys, {len(prefixes)} dynamic prefixes, all in [{RUNTIME_SECTION}].")
    return 0


if __name__ == "__main__":
    sys.exit(main())
