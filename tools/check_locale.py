#!/usr/bin/env python3
"""Verify every locale key the Lua references exists in the right section.

Catches the three failure modes that have actually bitten this repo:
  1. A key referenced in Lua but never defined (renders as "Unknown key").
  2. A key defined in the WRONG section — blind `cat >>` appends land at the
     end of the file, which is some other [section], so the runtime lookup
     under [land-title-registry] misses even though the text is present.
  3. A setting declared in settings.lua with no [mod-setting-name] entry —
     the settings GUI shows raw "Unknown key" names (playtest report: the
     four layer-override settings shipped nameless).

Dynamic keys built by concatenation ("land-title-registry.hover-" .. state) are checked
by prefix: at least one key with that prefix must exist in [land-title-registry].
Settings with allowed_values additionally need a [string-mod-setting]
<setting>-<value> label per value.

Run from the repo root:  python3 tools/check_locale.py
Exit status is non-zero when something is missing, so it can gate a release.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "locale/en/land-title-registry.cfg"
RUNTIME_SECTION = "land-title-registry"


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
        for prefix in re.findall(r'"land-title-registry\.([a-z0-9-]*-)"\s*\.\.', text):
            prefixes.add(prefix)
        for key in re.findall(r'"land-title-registry\.([a-z0-9-]+)"', text):
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

    # Settings coverage: every `name = "ltr-..."` in settings.lua needs a
    # [mod-setting-name] entry, and every allowed_values string setting a
    # [string-mod-setting] label per value. Name construction in settings.lua
    # is either a literal or a literal prefix concatenation ("ltr-x-" .. v);
    # the regexes below cover both shapes used there.
    settings_text = (ROOT / "settings.lua").read_text()
    # A literal ending in "-" is a concatenation prefix, handled below.
    setting_names = set(
        n for n in re.findall(r'name\s*=\s*"(ltr-[a-z0-9-]+)"', settings_text)
        if not n.endswith("-"))
    for prefix, var in re.findall(r'name\s*=\s*"(ltr-[a-z0-9-]+-)"\s*\.\.\s*([a-zA-Z_.\[\]]+)', settings_text):
        # Concatenated names (e.g. "ltr-border-color-" .. entry.state): every
        # [mod-setting-name] key with that prefix counts as declared; require
        # at least one so a renamed prefix cannot silently orphan the labels.
        if not any(k.startswith(prefix) for k in sections.get("mod-setting-name", set())):
            problems.append(f"MISSING: no [mod-setting-name] key starts with {prefix!r}")
    names = sections.get("mod-setting-name", set())
    for name in sorted(setting_names):
        if name not in names:
            problems.append(f"MISSING: [mod-setting-name] {name}")
    # allowed_values labels, two shapes as written in settings.lua:
    labels = sections.get("string-mod-setting", set())

    def check_labels(name, values):
        for value in values:
            if f"{name}-{value}" not in labels:
                problems.append(f"MISSING: [string-mod-setting] {name}-{value}")

    # Shape 1 — an entry literal carrying both name and inline values
    # (ltr-cell-size).
    for name, lst in re.findall(
            r'name\s*=\s*"(ltr-[a-z0-9-]+)"[^{}]*?allowed_values\s*=\s*\{([^{}]*)\}',
            settings_text, re.S):
        check_labels(name, re.findall(r'"([^"]+)"', lst))

    # Shape 2 — loop-built dropdowns referencing a shared UPPERCASE list
    # (the gesture settings): apply that list to every name declared in an
    # adjacent `{ name = "ltr-..." , ... }` source-table entry.
    named_lists = dict(re.findall(r'local\s+([A-Z_]+)\s*=\s*\{([^{}]*)\}', settings_text))
    for const_name in set(re.findall(r'allowed_values\s*=\s*([A-Z_]+)', settings_text)):
        values = re.findall(r'"([^"]+)"', named_lists.get(const_name, ""))
        if not values:
            continue
        for name in re.findall(r'\{\s*name\s*=\s*"(ltr-[a-z0-9-]+)"\s*,\s*default', settings_text):
            check_labels(name, values)

    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} locale problem(s).")
        return 1
    print(f"locale OK — {len(exact)} exact keys, {len(prefixes)} dynamic prefixes, all in [{RUNTIME_SECTION}].")
    return 0


if __name__ == "__main__":
    sys.exit(main())
