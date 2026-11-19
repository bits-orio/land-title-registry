#!/usr/bin/env python3
"""Timing table for dev/run-drag.sh: how long after each mouse step the
client ran the event it caused, and how far the cursor had moved on by then.

usage: drag-lag.py <run dir> [scenario ...]

Reads <run dir>/steps.txt (wall-clock time of every xdotool step), the
client's and the server's logs (a log line's time counts from the start of
its process, which run-drag.sh recorded in client.start and server.start)
and matches every preselection event to the mouse step that put the cursor
on the event's pixel. Exits 1 when a named scenario logged no drag event.

The preview label is a render object: the client draws it when its own
simulation runs the event, so "lag" here is how long the label trails the
hand. Process start to first log line is not measured, so read the
absolute numbers as a few milliseconds late; differences between runs are
exact.
"""
import re
import statistics
import sys
from pathlib import Path

TICK_MS = 1000 / 60
LINE = re.compile(r"^\s*(\d+\.\d+) Script @__ltr-drag-probe__/control\.lua:\d+: LTR_MP (\w+) (.*)$")
ENDS = ("selected", "alt_selected", "reverse_selected", "alt_reverse_selected", "super_forced_selected", "cancel")


def read_steps(path):
    steps = []
    for line in path.read_text().splitlines():
        time, scenario, action, *args = line.split()
        steps.append({"time": float(time), "scenario": scenario, "action": action, "args": args})
    return steps


def read_log(run, peer):
    start = float((run / f"{peer}.start").read_text())
    events = []
    for line in (run / f"{peer}.log").read_text(errors="replace").splitlines():
        match = LINE.match(line)
        if not match:
            continue
        fields = dict(re.findall(r"(\w+)=(\S+)", match.group(3)))
        events.append({"time": start + float(match.group(1)), "kind": match.group(2), "fields": fields,
                       "text": match.group(3)})
    return events


def pixel(text):
    x, y = text.split(",")
    return int(x), int(y)


def cursor_at(moves, time):
    """Where the mouse was at a wall-clock time: the last step before it."""
    last = None
    for step in moves:
        if step["time"] > time:
            break
        last = step
    return last and (int(last["args"][0]), int(last["args"][1]))


def step_for(moves, presses, event):
    """The mouse step that caused this event: the button press for a start
    event, else the move that put the cursor on the event's pixel."""
    if event["fields"]["ev"] == "start":
        before = [s for s in presses if s["time"] <= event["time"]]
        return before[-1] if before else None
    x, y = pixel(event["fields"]["px"])
    best = None
    for step in moves:
        if step["time"] > event["time"]:
            break
        if abs(int(step["args"][0]) - x) <= 2 and abs(int(step["args"][1]) - y) <= 2:
            best = step
    return best


def spread(values, unit=""):
    if not values:
        return "-"
    return f"{statistics.median(values):.0f}{unit} ({min(values):.0f} to {max(values):.0f})"


def scenario_rows(steps, events, name, window):
    mine = [s for s in steps if s["scenario"] == name]
    # A click mid-drag changes the selection where the cursor stands, so it
    # counts as a step at that pixel. Escape is not an end: it opens the game
    # menu, and the cancel follows the button's release.
    moves = [s for s in mine if s["action"] in ("move", "click")]
    presses = [s for s in mine if s["action"] == "press"]
    enders = [s for s in mine if s["action"] == "release" or (s["action"] == "key" and s["args"][0] == "q")]
    seen = [e for e in events if e["kind"] == "EV" and window[0] <= e["time"] < window[1]]
    lags, trails, end_lags = [], [], []
    for event in seen:
        kind = event["fields"].get("ev")
        if kind in ("start", "change"):
            step = step_for(moves, presses, event)
            if step:
                lags.append((event["time"] - step["time"]) * 1000)
            here = cursor_at(moves, event["time"])
            if here:
                x, y = pixel(event["fields"]["px"])
                trails.append(((here[0] - x) ** 2 + (here[1] - y) ** 2) ** 0.5)
        elif kind in ENDS:
            before = [s for s in enders if s["time"] <= event["time"]]
            if before:
                end_lags.append((event["time"] - before[-1]["time"]) * 1000)
    return seen, lags, trails, end_lags


def main():
    run = Path(sys.argv[1])
    wanted = sys.argv[2:]
    steps = read_steps(run / "steps.txt")
    order = []
    for step in steps:
        if step["scenario"] not in order:
            order.append(step["scenario"])
    starts = {name: next(s["time"] for s in steps if s["scenario"] == name) for name in order}
    status = 0
    for peer in ("client", "server"):
        events = read_log(run, peer)
        marks = [e for e in events if e["kind"] == "MARK"]
        presses = [s for s in steps if s["action"] == "key" and s["args"][0] == "ctrl+alt+m"]
        mark_lags = [(m["time"] - p["time"]) * 1000 for m, p in zip(marks, presses)]
        print(f"---- {peer}: milliseconds from a mouse or key step to its event, median (min to max)")
        print(f"mark key to its event: {spread(mark_lags, ' ms')}, "
              f"{statistics.median(mark_lags) / TICK_MS:.1f} ticks" if mark_lags else "no marks")
        print(f"{'scenario':<14} {'events':>6}  {'cursor step to event':<24} {'cursor ahead of label, px':<26} "
              f"{'release or cancel to event':<24}")
        all_lags = []
        for index, name in enumerate(order):
            if name in ("start", "end"):
                continue
            end = starts[order[index + 1]] if index + 1 < len(order) else float("inf")
            seen, lags, trails, end_lags = scenario_rows(steps, events, name, (starts[name], end))
            all_lags += lags
            print(f"{name:<14} {len(seen):>6}  {spread(lags, ' ms'):<24} {spread(trails):<26} {spread(end_lags, ' ms'):<24}")
            if name in wanted and not seen:
                print(f"FAILED: scenario {name} logged no drag event on the {peer}")
                status = 1
        if all_lags:
            median = statistics.median(all_lags)
            print(f"all preselection events: {spread(all_lags, ' ms')}, median {median / TICK_MS:.1f} ticks")
    return status


if __name__ == "__main__":
    sys.exit(main())
