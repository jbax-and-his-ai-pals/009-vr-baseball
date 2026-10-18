#!/usr/bin/env python3
"""Summarize a playtest event log.

    python tools/log_summary.py                 # the newest events_*.jsonl in the game's user folder
    python tools/log_summary.py path/to/file.jsonl

Prints the session header, what happened (pitches, plays, steals...), performance over time,
the slow frames, and every mark (player flags and the game's own watchdog) with the entries just
before it, so a note like "mark 3" can be found fast.
"""
import glob
import json
import os
import sys
from collections import Counter


def newest_log() -> str:
    base = os.path.join(os.environ.get("APPDATA", ""), "Godot", "app_userdata", "VR Baseball")
    files = sorted(glob.glob(os.path.join(base, "events_*.jsonl")), key=os.path.getmtime)
    if not files:
        sys.exit("no events_*.jsonl found in " + base)
    return files[-1]


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else newest_log()
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    print("  (unreadable line skipped)")
    print("file:", path)
    print("entries:", len(rows))
    if not rows:
        return
    head = rows[0] if rows[0].get("kind") == "session" else {}
    if head:
        print("session: mode=%s activity=%s xr=%s assist=%s hand=%s engine=%s" % (
            head.get("mode"), head.get("activity"), head.get("xr"), head.get("assist"), head.get("hand"), head.get("engine")))
    kinds = Counter(r.get("kind") for r in rows)
    print("\nentries by kind:", dict(kinds))
    span = rows[-1].get("t", 0.0)
    print("session length: %.0f s" % span)

    pitches = [r for r in rows if r.get("kind") == "pitch"]
    if pitches:
        out = Counter(p.get("outcome") for p in pitches)
        strikes = sum(1 for p in pitches if p.get("outcome") in ("called_strike", "swinging_strike") or p.get("bat") in ("hit", "foul tip"))
        print("\npitches: %d  outcomes: %s" % (len(pitches), dict(out)))
        locs = Counter(p.get("loc") for p in pitches)
        print("locations:", dict(locs))
        types = Counter(p.get("label") for p in pitches)
        print("types:", dict(types))
        deliveries = [p["delivery"] for p in pitches if p.get("delivery")]
        if deliveries:
            print("delivery with runners on: n=%d mean %.2f s min %.2f max %.2f" % (
                len(deliveries), sum(deliveries) / len(deliveries), min(deliveries), max(deliveries)))
    plays = [r for r in rows if r.get("kind") == "contact"]
    if plays:
        res = Counter(p.get("play") for p in plays)
        evs = [p["ev"] for p in plays if p.get("ev")]
        print("\nballs in play: %d  results: %s" % (len(plays), dict(res)))
        if evs:
            print("exit velocity mean %.0f mph, max %.0f" % (sum(evs) / len(evs), max(evs)))
    for kind in ("steal_resolve", "pickoff", "balk", "pitcher_change", "intentional_walk", "half_over", "game_over"):
        items = [r for r in rows if r.get("kind") == kind]
        if items:
            print("\n%s: %d" % (kind, len(items)))
            for r in items[:8]:
                short = {k: v for k, v in r.items() if k not in ("s", "kind", "stats")}
                print("   t=%7.1f %s" % (r.get("t", 0), json.dumps(short)[:170]))

    perf = [r for r in rows if r.get("kind") == "perf"]
    if perf:
        print("\nperformance windows (5 s each): %d" % len(perf))
        third = max(len(perf) // 3, 1)
        for name, chunk in (("first third", perf[:third]), ("middle", perf[third:2 * third]), ("last third", perf[2 * third:])):
            if not chunk:
                continue
            avg = sum(c["ms_avg"] for c in chunk) / len(chunk)
            worst = max(c["ms_max"] for c in chunk)
            calls = sum(c.get("draw_calls", 0) for c in chunk) / len(chunk)
            print("  %-11s avg frame %.1f ms, worst %.0f ms, draw calls ~%.0f, quality level max %d" % (
                name, avg, worst, calls, max(c.get("level", 0) for c in chunk)))
    spikes = [r for r in rows if r.get("kind") == "spike"]
    if spikes:
        print("\nslow frames (over 60 ms): %d" % len(spikes))
        for r in spikes[:12]:
            print("   t=%7.1f %5.0f ms  inn %s outs %s count %s on %s ready=%s walk_on=%s aux=%s steal=%s hits=%s" % (
                r.get("t", 0), r.get("ms", 0), r.get("inn"), r.get("outs"), r.get("count"), r.get("on"),
                r.get("ready"), r.get("walk_on"), r.get("aux"), r.get("steal"), r.get("hits_alive")))

    marks = [r for r in rows if r.get("kind") == "mark"]
    print("\nmarks: %d" % len(marks))
    for i, m in enumerate(marks, 1):
        print("\n--- mark %d at t=%.1f: %s" % (i, m.get("t", 0), m.get("reason")))
        st = m.get("state", {})
        print("    state:", json.dumps({k: st[k] for k in st if k in (
            "inn", "outs", "count", "on", "score", "batter", "ready", "batter_visible", "walk_on", "aux", "steal",
            "hits_alive", "plays_open", "unready_for", "frame_ms")}))
        for r in (m.get("recent") or [])[-8:]:
            short = {k: v for k, v in r.items() if k not in ("s", "kind", "t")}
            print("    t=%7.1f %-14s %s" % (r.get("t", 0), r.get("kind"), json.dumps(short)[:150]))


if __name__ == "__main__":
    main()
