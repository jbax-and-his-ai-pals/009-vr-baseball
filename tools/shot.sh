#!/usr/bin/env bash
# Render a few frames of the scene to PNGs so a change can be looked at without a headset.
#   tools/shot.sh overview            (also: behind-plate, batter, hit, or "default" = mound view)
#   tools/shot.sh hit --demo --profile=MVP
# Frames land in tools/shots/<view>/.
cd "$(dirname "$0")/.."
view="${1:-default}"; shift || true
out="tools/shots/$view"; rm -rf "$out"; mkdir -p "$out"
flag=(); [[ "$view" != default ]] && flag=("--$view")
exec tools/godot.sh --position -3000,0 --resolution 1280x720 --write-movie "$out/f.png" --fixed-fps 30 \
  --quit-after 90 --no-log -- "${flag[@]}" "$@"
