#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VIDEO=${VIDEO:-/dev/video0}
BACKUP_DIR=${BACKUP_DIR:-/var/tmp/hdmirx-edid-backups}
CUSTOM_EDID=${CUSTOM_EDID:-$ROOT/edid/rk1080p240.bin}

if (( EUID != 0 )); then
  echo "Run this with sudo: sudo bash scripts/prepare-240.sh" >&2
  exit 2
fi
if ! command -v v4l2-ctl >/dev/null 2>&1; then
  echo "v4l2-ctl is required. Run scripts/install-deps.sh first." >&2
  exit 2
fi
if [[ ! -f "$CUSTOM_EDID" ]]; then
  echo "Bundled 1080p240 EDID is missing: $CUSTOM_EDID" >&2
  exit 2
fi
if ! python3 "$ROOT/tools/build-240-edid.py" --check "$CUSTOM_EDID"; then
  echo "Bundled 1080p240 EDID failed validation; refusing to load it." >&2
  exit 2
fi

mkdir -p "$BACKUP_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
CURRENT="$BACKUP_DIR/rx-edid-current-$STAMP.bin"
ORIGINAL="$BACKUP_DIR/rx-edid-original.bin"
READBACK="$BACKUP_DIR/rx-edid-readback-$STAMP.bin"

if v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$CURRENT" >/dev/null 2>&1; then
  SIZE=$(wc -c <"$CURRENT")
  if (( SIZE < 128 || SIZE % 128 != 0 )); then
    echo "Current RX EDID has an invalid size ($SIZE bytes); refusing to overwrite it." >&2
    exit 3
  fi
  echo "Backed up current HDMI-RX EDID: $CURRENT"
  if ! cmp -s "$CURRENT" "$CUSTOM_EDID" && [[ ! -f "$ORIGINAL" ]]; then
    cp "$CURRENT" "$ORIGINAL"
    echo "Saved permanent restore point: $ORIGINAL"
  fi
else
  echo "Could not back up the current HDMI-RX EDID; refusing to continue." >&2
  exit 3
fi

echo
echo "Loading the Zowie-derived 1080p240 bridge EDID into HDMI-RX..."
v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$CUSTOM_EDID",format=raw

if ! v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$READBACK" >/dev/null 2>&1; then
  echo "The driver accepted the EDID command but read-back failed." >&2
  exit 3
fi
if ! cmp -s "$CUSTOM_EDID" "$READBACK"; then
  echo "EDID read-back differs from the requested bridge EDID; refusing to claim success." >&2
  echo "Restore with: sudo bash scripts/restore-rx-edid.sh" >&2
  exit 3
fi

echo "EDID write and exact byte-for-byte read-back succeeded."
echo "Profile: RK-1080P240"
echo "Preferred: 1920x1080 @ 239.964 Hz, 571.000 MHz, 8-bit"
echo "Fallback:  1920x1080 @ 60.000 Hz"
echo
echo "NEXT ON WINDOWS 11:"
echo "  1. Use EXTEND THESE DISPLAYS, not Duplicate."
echo "  2. Replug or disable/re-enable the CPU/iGPU HDMI display so Windows rereads EDID."
echo "  3. Select the new RK-1080P240 display."
echo "  4. Select 1920x1080 at 240 Hz. Keep 8-bit SDR; do not enable HDR or VRR."
echo "  5. Run the 240-Hz probe."
echo
echo "Emergency restore: sudo bash scripts/restore-rx-edid.sh"
