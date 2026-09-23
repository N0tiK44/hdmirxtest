#!/usr/bin/env bash
set -euo pipefail

# V1.2.2 deliberately does NOT restore rx-edid-original.bin.  Historical
# backups may advertise 4K, deep colour, or stale identities and were the cause
# of the Windows display-stack regression.  "restoreedid" now means recover to
# a generated, audited, known-safe bridge profile.

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VIDEO=${VIDEO:-/dev/video0}
STATE_DIR=${STATE_DIR:-/var/lib/hdmirxtest}
FORENSIC_DIR=${FORENSIC_DIR:-/var/tmp/hdmirxtest-edid-history}
RX_DISCONNECTED=${RX_DISCONNECTED:-0}

if (( EUID != 0 )); then
  echo "Run with sudo." >&2
  exit 2
fi
if ! command -v v4l2-ctl >/dev/null 2>&1; then
  echo "v4l2-ctl is required." >&2
  exit 2
fi
if (( RX_DISCONNECTED != 1 )) && v4l2-ctl -d "$VIDEO" --query-dv-timings >/dev/null 2>&1; then
  echo "SAFETY STOP: unplug the Windows HDMI source from HDMI-RX before recovery." >&2
  echo "Changing EDID underneath an active Windows display is prohibited." >&2
  exit 4
fi

install -d -m 0755 "$STATE_DIR" "$FORENSIC_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RECOVERY="$FORENSIC_DIR/recovery-$STAMP.bin"
READBACK="$FORENSIC_DIR/recovery-readback-$STAMP.bin"

python3 "$ROOT/tools/clone-monitor-edid.py" \
  --input "$ROOT/edid/zowie-xl2546x-captured.bin" \
  --output "$RECOVERY" \
  --identity-mode isolated \
  --max-width 1920 \
  --max-height 1080 \
  --max-refresh 60 \
  --max-pixel-clock 600000000
python3 "$ROOT/tools/clone-monitor-edid.py" --check "$RECOVERY" --identity-mode isolated

v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$RECOVERY",format=raw
v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$READBACK" >/dev/null

if ! cmp -s "$RECOVERY" "$READBACK" ||
   ! python3 "$ROOT/tools/clone-monitor-edid.py" --check "$READBACK" --identity-mode isolated >/dev/null; then
  echo "Recovery EDID did not verify. Keep HDMI-RX disconnected." >&2
  exit 5
fi

install -m 0644 "$RECOVERY" "$STATE_DIR/recovery-edid.bin"
install -m 0644 "$RECOVERY" "$STATE_DIR/bridge-edid.bin"
rm -f "$STATE_DIR/downstream-monitor.bin" "$STATE_DIR/downstream-monitor.sha256" \
  "$STATE_DIR/bridge-manifest.json"
sha256sum "$RECOVERY" | awk '{print $1}' >"$STATE_DIR/bridge-edid.sha256"

echo
echo "Audited safe recovery EDID installed and verified."
echo "The old stock/original EDID backup was intentionally NOT restored."
echo "You may now reconnect the Windows HDMI source."
