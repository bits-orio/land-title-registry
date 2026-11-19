"""Groups the probe's "SP" log lines into drags, one line a drag.

    python3 analyze.py <factorio log>

A drag runs from on_player_start_selected_area to the final or cancel event.
Per drag: its ticks, how many change events it had and how fast they came,
whether two ever shared a tick (sameTickDup), the smallest and largest gap
in ticks between two change events, the largest tiles and entities tables
seen, the selection modes, and the event that ended it (name, mode, tiles,
entities).
"""
import re
import sys

START = "on_player_start_selected_area"
CHANGE = "on_player_change_selected_area"
EVENT = re.compile(r"^ *([\d.]+) Script @\S+ SP t=(\d+) ev=(\S+) (.*)")


def read_events(path):
    events = []
    for line in open(path):
        m = EVENT.search(line)
        if not m:
            continue
        if "iterate-cost" in line:
            events.append((int(m.group(2)), "COST", {}))
        else:
            fields = dict(re.findall(r"(\w+)=(\S+)", m.group(4)))
            events.append((int(m.group(2)), m.group(3), fields))
    return events


def drags(events):
    out, current = [], None
    for event in events:
        name = event[1]
        if name == START:
            current = [event]
            out.append(current)
        elif current is not None:
            current.append(event)
            if name not in (CHANGE, "COST"):
                current = None
    return out


def largest(drag, field):
    return max([int(e[2][field]) for e in drag if e[2].get(field, "x").isdigit()] or [0])


def main():
    for i, drag in enumerate(drags(read_events(sys.argv[1]))):
        changes = [e for e in drag if e[1] == CHANGE]
        ends = [e for e in drag if e[1] not in (START, CHANGE, "COST")]
        first, last = drag[0][0], drag[-1][0]
        ticks = [e[0] for e in changes]
        gaps = [b - a for a, b in zip(ticks, ticks[1:])]
        seconds = (last - first) / 60
        rate = len(changes) / seconds if seconds else 0
        modes = sorted(set(e[2].get("mode", "") for e in drag if e[2]))
        end = [(e[1], e[2].get("mode"), e[2].get("tiles"), e[2].get("ents")) for e in ends]
        print(f"#{i} t={first}..{last} ({seconds:.2f}s) changes={len(changes)} rate={rate:.1f}/s "
              f"sameTickDup={len(ticks) - len(set(ticks))} "
              f"gap(min/max)={min(gaps) if gaps else '-'}/{max(gaps) if gaps else '-'} "
              f"maxtiles={largest(drag, 'tiles')} maxents={largest(drag, 'ents')} modes={modes} end={end}")


if __name__ == "__main__":
    main()
