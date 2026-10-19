#!/usr/bin/env bash
# Run every headless test (no window, no headset). Exit code is non-zero if any fail.
#   tools/test.sh            all tests
#   tools/test.sh batter     just tests whose name contains "batter"
cd "$(dirname "$0")/.."
filter="${1:-}"
fail=0
for t in tests/*_test.gd; do
  name="$(basename "$t" .gd)"
  [[ -n "$filter" && "$name" != *"$filter"* ]] && continue
  out="$(timeout 150 tools/godot.sh --headless -s "res://$t" 2>&1)" || { echo "FAIL  $name (exit code $?, timed out or crashed)"; grep -E "^FAIL  |SCRIPT ERROR|Parse Error" <<<"$out" | head -5; tail -5 <<<"$out"; fail=1; continue; }
  if grep -qE "^FAIL  |SCRIPT ERROR|Parse Error" <<<"$out" || ! grep -qE "FAILURES: 0|^PASS$" <<<"$out"; then
    echo "FAIL  $name"; grep -E "^FAIL  |SCRIPT ERROR|Parse Error" <<<"$out" | head -5
    fail=1
  else
    echo "ok    $name"
  fi
done
exit $fail
