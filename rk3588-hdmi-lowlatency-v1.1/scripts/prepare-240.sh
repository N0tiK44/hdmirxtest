#!/usr/bin/env bash
set -euo pipefail

VIDEO=${VIDEO:-/dev/video0}
BACKUP_DIR=${BACKUP_DIR:-/var/tmp/hdmirx-edid-backups}
DOWNSTREAM_EDID=${DOWNSTREAM_EDID:-}

if (( EUID != 0 )); then
  echo "Run this with sudo: sudo bash scripts/prepare-240.sh" >&2
  exit 2
fi
if ! command -v v4l2-ctl >/dev/null 2>&1; then
  echo "v4l2-ctl is required. Run scripts/install-deps.sh first." >&2
  exit 2
fi

mkdir -p "$BACKUP_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="$BACKUP_DIR/rx-edid-$STAMP.bin"
FORWARDED="$BACKUP_DIR/downstream-edid-$STAMP.bin"

if v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$BACKUP" >/dev/null 2>&1; then
  echo "Backed up current HDMI-RX EDID: $BACKUP"
else
  rm -f "$BACKUP"
  echo "Could not save the current HDMI-RX EDID in raw form; continuing." >&2
fi

if [[ -z "$DOWNSTREAM_EDID" ]]; then
  # Prefer a physical HDMI output (normally the Zowie on HDMI-TX).  Fall back
  # to any connected DRM connector only if no HDMI-A EDID is available.
  for pattern in '/sys/class/drm/card*-HDMI-A-*/status' '/sys/class/drm/card*-*/status'; do
    for status in $pattern; do
      [[ -f "$status" ]] || continue
      [[ $(cat "$status" 2>/dev/null) == "connected" ]] || continue
      candidate="${status%/status}/edid"
      if [[ -s "$candidate" ]]; then
        DOWNSTREAM_EDID="$candidate"
        break 2
      fi
    done
  done
fi

if [[ -n "$DOWNSTREAM_EDID" && -s "$DOWNSTREAM_EDID" ]]; then
  cp "$DOWNSTREAM_EDID" "$FORWARDED"
  SIZE=$(wc -c <"$FORWARDED")
  echo "Found connected downstream display EDID: $DOWNSTREAM_EDID ($SIZE bytes)"
  if (( SIZE < 128 || SIZE % 128 != 0 )); then
    echo "Downstream EDID size is invalid; refusing to forward it." >&2
    rm -f "$FORWARDED"
  fi
fi

if [[ -s "$FORWARDED" ]]; then
  if command -v edid-decode >/dev/null 2>&1; then
    echo
    echo "Downstream EDID summary:"
    edid-decode "$FORWARDED" 2>/dev/null | grep -E 'Display Product Name|DTD|Detailed Timing|1920x1080|239|240|Maximum TMDS|Max TMDS|SCDC' | head -n 80 || true
    echo
  fi

  echo "Forwarding the downstream monitor EDID to HDMI-RX..."
  if v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$FORWARDED",format=raw; then
    echo "Downstream EDID forwarded successfully."
    echo "Windows should now see the downstream monitor's advertised modes."
  else
    echo "Direct downstream EDID forwarding failed; trying v4l2-ctl's HDMI 2.0 / 600-MHz fallback EDID." >&2
    if v4l2-ctl --help-edid 2>&1 | grep -q 'hdmi-4k-600mhz'; then
      v4l2-ctl -d "$VIDEO" --set-edid=pad=0,type=hdmi-4k-600mhz
    else
      echo "This v4l2-ctl build has no hdmi-4k-600mhz preset. Keep the saved debug output and report this result." >&2
      exit 3
    fi
  fi
else
  echo "No usable downstream EDID was found; trying v4l2-ctl's HDMI 2.0 / 600-MHz fallback EDID."
  if v4l2-ctl --help-edid 2>&1 | grep -q 'hdmi-4k-600mhz'; then
    v4l2-ctl -d "$VIDEO" --set-edid=pad=0,type=hdmi-4k-600mhz
  else
    echo "This v4l2-ctl build has no hdmi-4k-600mhz preset. Keep the saved debug output and report this result." >&2
    exit 3
  fi
fi

echo
echo "NEXT ON WINDOWS:"
echo "  1. Replug/disable-enable the HDMI source if Windows does not refresh the monitor modes."
echo "  2. Select exactly 1920x1080 at 240 Hz (or the closest ~239.7/239.8-Hz entry)."
echo "  3. Do NOT select a mode above 240 Hz even if the Zowie EDID advertises one."
echo "  4. Then run the 240 probe/test."
echo
echo "EDID forwarding only changes source/display negotiation; it does not alter the zero-copy capture/scanout path."
