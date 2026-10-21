#!/bin/sh
# Runs the M2 accuracy benchmark on a connected iPhone (Debug build installed):
#   1. copies Benchmarks/photos/* and Benchmarks/photos/labels.csv into the
#      app's Documents/Benchmarks/<set>/ on the phone,
#   2. launches the app with -MSRunBenchmark <set>,
#   3. copies the summary and CSV back into Benchmarks/private/ (git-ignored:
#      the readings describe real people).
# Usage: scripts/run-benchmark.sh [set-name]   (DEVICE=<udid> picks a phone, PHOTOS=<dir> another folder)
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="com.williammcintyre.MonsterScanner"
SET="${1:-run-$(date +%Y%m%d-%H%M%S)}"
SRC="${PHOTOS:-$ROOT/Benchmarks/photos}"
OUT="$ROOT/Benchmarks/private"
mkdir -p "$OUT"

if [ -z "${DEVICE:-}" ]; then
  JSON="$(mktemp)"
  xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1
  DEVICE="$(python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, cp = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("deviceType") == "iPhone" and hw.get("reality") == "physical" and cp.get("tunnelState") == "connected":
        print(hw["udid"]); break
' "$JSON")"
  rm -f "$JSON"
fi
[ -n "$DEVICE" ] || { echo "No connected, unlocked iPhone found." >&2; exit 1; }
[ -f "$SRC/labels.csv" ] || { echo "Missing $SRC/labels.csv" >&2; exit 1; }

copy_to() {
  xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "$1" --destination "$2" >/dev/null
}
COUNT=0
for photo in "$SRC"/*; do
  case "$(echo "$photo" | tr '[:upper:]' '[:lower:]')" in
    *.jpg|*.jpeg|*.png|*.heic) copy_to "$photo" "Documents/Benchmarks/$SET/photos/$(basename "$photo")"; COUNT=$((COUNT + 1)) ;;
  esac
done
copy_to "$SRC/labels.csv" "Documents/Benchmarks/$SET/labels.csv"
echo "Copied $COUNT photos to set '$SET'. Launching benchmark…"

if ! LAUNCH="$(xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" -MSRunBenchmark "$SET" 2>&1)"; then
  if echo "$LAUNCH" | grep -q "Locked"; then
    echo "The iPhone is locked. Unlock it (keep it unlocked for about a minute) and run this again." >&2
  else
    echo "$LAUNCH" >&2
  fi
  exit 1
fi
for _ in $(seq 1 60); do
  if xcrun devicectl device info files --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
       --subdirectory "Documents/Benchmarks/$SET" 2>/dev/null | grep -q "summary-latest.txt"; then
    break
  fi
  sleep 5
done
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "Documents/Benchmarks/$SET/summary-latest.txt" --destination "$OUT/summary-$SET.txt" >/dev/null
CSV="$(grep -o 'results-[^ ]*\.csv' "$OUT/summary-$SET.txt" || true)"
if [ -n "$CSV" ]; then
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "Documents/Benchmarks/$SET/$CSV" --destination "$OUT/results-$SET.csv" >/dev/null
fi
cat "$OUT/summary-$SET.txt"
echo "\nSaved to $OUT/ (git-ignored)."
