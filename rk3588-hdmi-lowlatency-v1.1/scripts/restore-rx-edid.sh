#!/usr/bin/env bash
set -euo pipefail

VIDEO=${VIDEO:-/dev/video0}
BACKUP_DIR=${BACKUP_DIR:-/var/tmp/hdmirx-edid-backups}
FILE=${1:-}

if (( EUID != 0 )); then
  echo "Run with sudo." >&2
  exit 2
fi
if [[ -z "$FILE" ]]; then
  FILE=$(ls -1t "$BACKUP_DIR"/rx-edid-*.bin 2>/dev/null | head -n1 || true)
fi
if [[ -z "$FILE" || ! -s "$FILE" ]]; then
  echo "No saved HDMI-RX EDID backup found in $BACKUP_DIR" >&2
  exit 2
fi

v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$FILE",format=raw
echo "Restored HDMI-RX EDID from: $FILE"
