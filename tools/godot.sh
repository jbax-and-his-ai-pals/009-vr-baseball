#!/usr/bin/env bash
# Run Godot for this project WITHOUT touching the headset.
#
# Everything here passes --xr-mode off, so OpenXR / Virtual Desktop is never started: no headset
# needs to be connected, worn, or even streaming, and a run cannot grab your VR session.
#
#   tools/godot.sh [godot args...]        e.g. tools/godot.sh --headless -s res://tests/perf_test.gd
#
# To deliberately run with the headset, call Godot yourself (or pass --xr-mode on).
set -euo pipefail
GODOT="${GODOT:-/c/Users/baxte/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
cd "$(dirname "$0")/.."
if [[ " $* " != *" --xr-mode "* ]]; then
  set -- --xr-mode off "$@"
fi
exec "$GODOT" --path . "$@"
