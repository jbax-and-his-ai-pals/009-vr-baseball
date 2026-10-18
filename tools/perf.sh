#!/usr/bin/env bash
# Real render stats (draw calls, triangles) for the game scene. Needs a window, not a headset:
# the window is parked off-screen and the headset is never started.
#   tools/perf.sh                  idle scene
#   tools/perf.sh --demo           with pitches, swings and batted balls
#   tools/perf.sh --demo --budget  also exit non-zero if over the Quest budget
cd "$(dirname "$0")/.."
exec tools/godot.sh --position -3000,0 --resolution 1280x720 --fixed-fps 60 --no-log \
  -s res://tools/perf_probe.gd -- --frames=900 --profile=MVP "$@"
