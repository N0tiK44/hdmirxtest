#!/usr/bin/env bash
set -euo pipefail

# Fast preflight for the live path.  It reads the HDMI-TX EDID and compares it
# with the sink used to build the installed RX profile.  A changed sink is
# staged immediately, but an active Windows link is never rewritten in place.

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
DOWNSTREAM_CONNECTOR=${DOWNSTREAM_CONNECTOR:-}
STATE_DIR=${STATE_DIR:-/var/lib/hdmirxtest}
MAX_WIDTH=${MAX_WIDTH:-1920}
MAX_HEIGHT=${MAX_HEIGHT:-1080}
MAX_REFRESH=${MAX_REFRESH:-240}
MAX_PIXEL_CLOCK=${MAX_PIXEL_CLOCK:-600000000}
NO_AUTO_APPLY=${NO_AUTO_APPLY:-0}

if (( EUID != 0 )); then
  echo "Run with sudo." >&2
  exit 2
fi

CARD_NAME=$(basename "$CARD")
candidates=()
if [[ -n "$DOWNSTREAM_CONNECTOR" ]]; then
  connector_path="/sys/class/drm/$DOWNSTREAM_CONNECTOR"
  [[ -d "$connector_path" ]] || connector_path="/sys/class/drm/${CARD_NAME}-${DOWNSTREAM_CONNECTOR}"
  [[ -d "$connector_path" ]] && candidates+=("$connector_path")
else
  for connector_path in /sys/class/drm/"$CARD_NAME"-HDMI-A-*; do
    [[ -d "$connector_path" ]] || continue
    [[ $(<"$connector_path/status") == connected ]] || continue
    [[ -r "$connector_path/edid" ]] || continue
    candidates+=("$connector_path")
  done
fi

if (( ${#candidates[@]} != 1 )); then
  echo "SAFETY STOP: expected one connected HDMI-TX monitor; found ${#candidates[@]}." >&2
  exit 3
fi

CURRENT=$(mktemp /tmp/hdmirxtest-tx-edid.XXXXXX.bin)
trap 'rm -f -- "$CURRENT"' EXIT
dd if="${candidates[0]}/edid" of="$CURRENT" status=none
[[ -s "$CURRENT" ]] || { echo "Could not read HDMI-TX monitor EDID." >&2; exit 3; }

if [[ -s "$STATE_DIR/downstream-monitor.bin" ]] &&
   cmp -s "$CURRENT" "$STATE_DIR/downstream-monitor.bin"; then
  echo "HDMI-TX monitor identity: unchanged"
  exit 0
fi

install -d -m 0755 "$STATE_DIR"
python3 "$ROOT/tools/clone-monitor-edid.py" \
  --input "$CURRENT" \
  --output "$STATE_DIR/pending-bridge-edid.bin" \
  --manifest "$STATE_DIR/pending-bridge-manifest.json" \
  --identity-mode clone \
  --max-width "$MAX_WIDTH" \
  --max-height "$MAX_HEIGHT" \
  --max-refresh "$MAX_REFRESH" \
  --max-pixel-clock "$MAX_PIXEL_CLOCK" >/dev/null
install -m 0644 "$CURRENT" "$STATE_DIR/pending-downstream-monitor.bin"

echo "A new HDMI-TX monitor was detected and its safe profile was staged." >&2
if v4l2-ctl -d "$VIDEO" --query-dv-timings >/dev/null 2>&1; then
  echo "SAFETY STOP: Windows is active on HDMI-RX, so its EDID was not changed." >&2
  echo "Unplug HDMI-RX, run: bash PiCycle.sh setup, then reconnect." >&2
  exit 10
fi

if (( NO_AUTO_APPLY == 1 )); then
  echo "Run setup with HDMI-RX unplugged, then reconnect and run bash PiCycle.sh." >&2
  exit 10
fi

echo "HDMI-RX is inactive; installing the new monitor profile now." >&2
DOWNSTREAM_CONNECTOR=$(basename "${candidates[0]}") RX_DISCONNECTED=1 \
  bash "$ROOT/scripts/prepare-monitor-edid.sh"
echo "Reconnect HDMI-RX, then rerun: bash PiCycle.sh" >&2
exit 11
