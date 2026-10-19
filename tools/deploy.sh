#!/usr/bin/env bash
# Build the Android (Quest) APK and install it on a connected headset. NOT YET RUN: it was written without a
# device or the Android toolchain, so expect to adjust it (see docs/QUEST.md for the one-time setup).
#
#   tools/deploy.sh            export a debug APK to build/vr-baseball.apk and `adb install -r` it
#   tools/deploy.sh --export   only export
#   tools/deploy.sh --launch   install, then start the game (adb shell am start)
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/c/Users/baxte/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
PRESET="${PRESET:-Quest}"
APK="build/vr-baseball.apk"
PACKAGE="${PACKAGE:-com.jbax.vrbaseball}"

if [[ ! -f export_presets.cfg ]]; then
  echo "No export_presets.cfg: create the '$PRESET' Android preset first (docs/QUEST.md, step 2)." >&2
  exit 2
fi
mkdir -p build
echo "Exporting the '$PRESET' preset to $APK ..."
"$GODOT" --path . --headless --export-debug "$PRESET" "$APK" || { echo "Export failed (templates? keystore? see docs/QUEST.md)" >&2; exit 1; }
[[ "${1:-}" == "--export" ]] && exit 0
if ! command -v adb >/dev/null 2>&1; then
  echo "adb not found: install the Android platform tools and enable developer mode on the headset." >&2
  exit 3
fi
adb devices | grep -q "device$" || { echo "No headset connected over adb (USB, or 'adb connect <ip>:5555')." >&2; exit 4; }
adb install -r "$APK"
[[ "${1:-}" == "--launch" ]] && adb shell am start -n "$PACKAGE/com.godot.game.GodotApp"
echo "Installed."
