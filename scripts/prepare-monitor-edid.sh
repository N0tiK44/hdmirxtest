#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
DOWNSTREAM_CONNECTOR=${DOWNSTREAM_CONNECTOR:-}
DOWNSTREAM_EDID=${DOWNSTREAM_EDID:-}
BACKUP_DIR=${BACKUP_DIR:-/var/tmp/hdmirx-edid-backups}
MAX_WIDTH=${MAX_WIDTH:-1920}
MAX_HEIGHT=${MAX_HEIGHT:-1080}
MAX_REFRESH=${MAX_REFRESH:-240}
MAX_PIXEL_CLOCK=${MAX_PIXEL_CLOCK:-600000000}

if (( EUID != 0 )); then
  echo "Run this with sudo." >&2
  exit 2
fi
if ! command -v v4l2-ctl >/dev/null 2>&1; then
  echo "v4l2-ctl is required. Run scripts/install-deps.sh first." >&2
  exit 2
fi

mkdir -p "$BACKUP_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
MONITOR_RAW="$BACKUP_DIR/downstream-monitor-$STAMP.bin"
CLONE="$BACKUP_DIR/downstream-clone-1080p240-$STAMP.bin"
CURRENT="$BACKUP_DIR/rx-edid-current-$STAMP.bin"
ORIGINAL="$BACKUP_DIR/rx-edid-original.bin"
READBACK="$BACKUP_DIR/rx-edid-readback-$STAMP.bin"

if [[ -n "$DOWNSTREAM_EDID" ]]; then
  if [[ ! -s "$DOWNSTREAM_EDID" ]]; then
    echo "DOWNSTREAM_EDID does not name a readable EDID: $DOWNSTREAM_EDID" >&2
    exit 2
  fi
  cp "$DOWNSTREAM_EDID" "$MONITOR_RAW"
  SOURCE_LABEL="$DOWNSTREAM_EDID"
else
  CARD_NAME=$(basename "$CARD")
  candidates=()

  if [[ -n "$DOWNSTREAM_CONNECTOR" ]]; then
    connector_path="/sys/class/drm/$DOWNSTREAM_CONNECTOR"
    [[ -d "$connector_path" ]] || connector_path="/sys/class/drm/${CARD_NAME}-${DOWNSTREAM_CONNECTOR}"
    if [[ ! -d "$connector_path" ]]; then
      echo "Downstream DRM connector was not found: $DOWNSTREAM_CONNECTOR" >&2
      exit 2
    fi
    candidates+=("$connector_path")
  else
    for connector_path in /sys/class/drm/"$CARD_NAME"-HDMI-A-*; do
      [[ -d "$connector_path" ]] || continue
      [[ $(<"$connector_path/status") == connected ]] || continue
      [[ -r "$connector_path/edid" ]] || continue
      candidates+=("$connector_path")
    done
  fi

  if (( ${#candidates[@]} != 1 )); then
    echo "Expected exactly one connected downstream HDMI monitor; found ${#candidates[@]}." >&2
    echo "Set DOWNSTREAM_CONNECTOR=card0-HDMI-A-1 (adjust the name shown in /sys/class/drm)." >&2
    exit 3
  fi

  SOURCE_LABEL=${candidates[0]}
  if ! dd if="${candidates[0]}/edid" of="$MONITOR_RAW" status=none || [[ ! -s "$MONITOR_RAW" ]]; then
    echo "Could not read the downstream monitor EDID from ${candidates[0]}." >&2
    exit 3
  fi
fi

python3 "$ROOT/tools/clone-monitor-edid.py" \
  --input "$MONITOR_RAW" \
  --output "$CLONE" \
  --max-width "$MAX_WIDTH" \
  --max-height "$MAX_HEIGHT" \
  --max-refresh "$MAX_REFRESH" \
  --max-pixel-clock "$MAX_PIXEL_CLOCK"

if ! v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$CURRENT" >/dev/null 2>&1; then
  echo "Could not back up the active HDMI-RX EDID; refusing to overwrite it." >&2
  exit 3
fi

SIZE=$(wc -c <"$CURRENT")
if (( SIZE < 128 || SIZE % 128 != 0 )); then
  echo "The active HDMI-RX EDID has an invalid size ($SIZE bytes)." >&2
  exit 3
fi
if [[ ! -f "$ORIGINAL" ]]; then
  cp "$CURRENT" "$ORIGINAL"
  echo "Saved permanent HDMI-RX restore point: $ORIGINAL"
fi

v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$CLONE",format=raw
v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$READBACK" >/dev/null

if ! cmp -s "$CLONE" "$READBACK"; then
  echo "HDMI-RX EDID read-back differs from the generated monitor clone." >&2
  echo "Restore with: bash scripts/pi-cycle.sh restoreedid" >&2
  exit 3
fi

cp "$MONITOR_RAW" "$BACKUP_DIR/downstream-monitor-latest.bin"
cp "$CLONE" "$BACKUP_DIR/downstream-clone-1080p240-latest.bin"

echo
echo "Downstream monitor EDID cloned from: $SOURCE_LABEL"
echo "HDMI-RX now advertises only provably safe modes at or below ${MAX_WIDTH}x${MAX_HEIGHT}@${MAX_REFRESH}."
echo "Colour policy: RGB 8-bit SDR; YCbCr/deep-colour/HDR/VRR advertisement removed."
echo "Exact HDMI-RX read-back: verified"
echo
echo "Reconnect or disable/re-enable the Windows HDMI source once so it rereads the EDID."
