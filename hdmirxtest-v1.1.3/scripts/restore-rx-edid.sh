#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VIDEO=${VIDEO:-/dev/video0}
BACKUP_DIR=${BACKUP_DIR:-/var/tmp/hdmirx-edid-backups}
FILE=${1:-}

if (( EUID != 0 )); then
  echo "Run with sudo." >&2
  exit 2
fi
if [[ -z "$FILE" ]]; then
  if [[ -s "$BACKUP_DIR/rx-edid-original.bin" ]]; then
    FILE="$BACKUP_DIR/rx-edid-original.bin"
  else
    FILE=$(ls -1t "$BACKUP_DIR"/rx-edid-current-*.bin 2>/dev/null | head -n1 || true)
    if [[ -z "$FILE" && -s "$ROOT/edid/rk-uhd-stock.bin" ]]; then
      FILE="$ROOT/edid/rk-uhd-stock.bin"
    fi
  fi
fi
if [[ -z "$FILE" || ! -s "$FILE" ]]; then
  echo "No saved HDMI-RX EDID backup found in $BACKUP_DIR" >&2
  exit 2
fi

v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$FILE",format=raw
READBACK="$BACKUP_DIR/restore-readback-$(date -u +%Y%m%dT%H%M%SZ).bin"
v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$READBACK" >/dev/null
if ! cmp -s "$FILE" "$READBACK"; then
  echo "Restore command returned, but byte-for-byte EDID verification failed." >&2
  exit 3
fi
echo "Restored and verified HDMI-RX EDID from: $FILE"
echo "Replug or disable/re-enable the Windows CPU/iGPU HDMI display."
