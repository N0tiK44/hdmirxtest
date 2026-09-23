#!/usr/bin/env bash
set -euo pipefail

CARD=${CARD:-/dev/dri/card0}
SECONDS_TO_RUN=${SECONDS_TO_RUN:-120}
STATE_DIR=/var/lib/hdmirxtest
LOG="$STATE_DIR/tx-selftest.log"
EDID="$STATE_DIR/tx-selftest-edid.bin"
BIN=/usr/local/bin/hdmirxtest-tx-selftest

mkdir -p "$STATE_DIR"
if [[ -f "$LOG" ]]; then
  mv -f "$LOG" "$LOG.previous"
fi
exec > >(tee -a "$LOG") 2>&1

echo "HDMIRXTEST V1.2 HDMI-TX SELF-TEST"
echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "card=$CARD"
echo "HDMI-RX is not used by this test."

for attempt in $(seq 1 30); do
  set +e
  "$BIN" --card "$CARD" --seconds "$SECONDS_TO_RUN" --edid-output "$EDID"
  result=$?
  set -e
  if (( result != 75 )); then
    echo "result=$result"
    echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    exit "$result"
  fi
  echo "No connected HDMI display yet (attempt $attempt/30); retrying..."
  sleep 1
done

echo "result=75"
echo "No HDMI-TX display became ready within 30 seconds."
exit 75
