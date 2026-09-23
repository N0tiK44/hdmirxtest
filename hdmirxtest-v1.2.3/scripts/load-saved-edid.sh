#!/usr/bin/env bash
set -euo pipefail

VIDEO=${VIDEO:-/dev/video0}
STATE_DIR=${STATE_DIR:-/var/lib/hdmirxtest}
EDID=${EDID:-$STATE_DIR/bridge-edid.bin}
READBACK=${READBACK:-/run/hdmirxtest-edid-readback.bin}
WAIT_SECONDS=${WAIT_SECONDS:-15}

if (( EUID != 0 )); then
  echo "Run with sudo." >&2
  exit 2
fi
if [[ ! -s "$EDID" ]]; then
  echo "Saved bridge EDID is missing: $EDID" >&2
  exit 3
fi

deadline=$((SECONDS + WAIT_SECONDS))
while [[ ! -e "$VIDEO" ]] && (( SECONDS < deadline )); do
  sleep 0.1
done
if [[ ! -e "$VIDEO" ]]; then
  echo "HDMI-RX device did not appear: $VIDEO" >&2
  exit 3
fi

v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$EDID",format=raw >/dev/null
v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$READBACK" >/dev/null
if ! cmp -s "$EDID" "$READBACK"; then
  echo "HDMI-RX EDID boot-time write/read-back mismatch." >&2
  exit 5
fi

echo "HDMI-RX saved bridge EDID loaded and verified."
