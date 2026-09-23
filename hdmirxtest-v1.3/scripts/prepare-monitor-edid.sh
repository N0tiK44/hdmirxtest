#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
DOWNSTREAM_CONNECTOR=${DOWNSTREAM_CONNECTOR:-}
DOWNSTREAM_EDID=${DOWNSTREAM_EDID:-}
STATE_DIR=${STATE_DIR:-/var/lib/hdmirxtest}
FORENSIC_DIR=${FORENSIC_DIR:-/var/tmp/hdmirxtest-edid-history}
MAX_WIDTH=${MAX_WIDTH:-3840}
MAX_HEIGHT=${MAX_HEIGHT:-2160}
MAX_REFRESH=${MAX_REFRESH:-240}
MAX_PIXEL_CLOCK=${MAX_PIXEL_CLOCK:-600000000}
RX_DISCONNECTED=${RX_DISCONNECTED:-0}

if (( EUID != 0 )); then
  echo "Run this with sudo." >&2
  exit 2
fi
if ! command -v v4l2-ctl >/dev/null 2>&1; then
  echo "v4l2-ctl is required. Run scripts/install-deps.sh first." >&2
  exit 2
fi

# Foreground video must exclusively own V4L2 and DRM. Remove any installed
# background passthrough before touching EDID.
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  systemctl disable --now hdmirxtest-passthrough.service >/dev/null 2>&1 || true
fi

# Never change the identity/capabilities of a display while Windows is using
# that link.  Live EDID replacement caused the host display-stack failure this
# release is designed to prevent.
if (( RX_DISCONNECTED != 1 )) && v4l2-ctl -d "$VIDEO" --query-dv-timings >/dev/null 2>&1; then
  echo "SAFETY STOP: an active HDMI source is detected on HDMI-RX." >&2
  echo "Physically unplug the Windows/motherboard HDMI cable from HDMI-RX, then rerun setup." >&2
  echo "Leave the monitor connected to HDMI-TX." >&2
  exit 4
fi

install -d -m 0755 "$STATE_DIR" "$FORENSIC_DIR"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
MONITOR_RAW="$FORENSIC_DIR/downstream-monitor-$STAMP.bin"
CANDIDATE="$FORENSIC_DIR/bridge-candidate-$STAMP.bin"
MANIFEST="$FORENSIC_DIR/bridge-manifest-$STAMP.json"
CURRENT="$FORENSIC_DIR/rx-before-setup-$STAMP.bin"
READBACK="$FORENSIC_DIR/rx-readback-$STAMP.bin"
RECOVERY="$FORENSIC_DIR/recovery-$STAMP.bin"

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
    [[ -d "$connector_path" ]] || {
      echo "Downstream DRM connector was not found: $DOWNSTREAM_CONNECTOR" >&2
      exit 2
    }
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
    echo "Expected one connected HDMI-TX monitor; found ${#candidates[@]}." >&2
    echo "Only the output monitor belongs on HDMI-TX during setup." >&2
    echo "If needed, set DOWNSTREAM_CONNECTOR=card0-HDMI-A-1." >&2
    exit 3
  fi

  SOURCE_LABEL=${candidates[0]}
  if ! dd if="${candidates[0]}/edid" of="$MONITOR_RAW" status=none || [[ ! -s "$MONITOR_RAW" ]]; then
    echo "Could not read the downstream EDID from ${candidates[0]}." >&2
    exit 3
  fi
fi

# Build the candidate from the real sink and a separate, isolated recovery
# profile. The recovery source is used only for its conservative timings.
python3 "$ROOT/tools/clone-monitor-edid.py" \
  --input "$MONITOR_RAW" \
  --output "$CANDIDATE" \
  --manifest "$MANIFEST" \
  --identity-mode clone \
  --max-width "$MAX_WIDTH" \
  --max-height "$MAX_HEIGHT" \
  --max-refresh "$MAX_REFRESH" \
  --max-pixel-clock "$MAX_PIXEL_CLOCK"

python3 "$ROOT/tools/clone-monitor-edid.py" \
  --input "$ROOT/edid/recovery-source.bin" \
  --output "$RECOVERY" \
  --identity-mode isolated \
  --max-width 1920 \
  --max-height 1080 \
  --max-refresh 60 \
  --max-pixel-clock 600000000 >/dev/null

python3 "$ROOT/tools/clone-monitor-edid.py" --check "$CANDIDATE" \
  --source "$MONITOR_RAW" --identity-mode clone
python3 "$ROOT/tools/clone-monitor-edid.py" --check "$RECOVERY" \
  --identity-mode isolated >/dev/null

if ! v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$CURRENT" >/dev/null 2>&1; then
  echo "Could not read the current HDMI-RX EDID; no write was attempted." >&2
  exit 3
fi

rollback() {
  echo "Candidate verification failed; loading the audited recovery EDID." >&2
  v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$RECOVERY",format=raw || return 1
  v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$READBACK" >/dev/null || return 1
  cmp -s "$RECOVERY" "$READBACK"
}

if ! v4l2-ctl -d "$VIDEO" --set-edid=pad=0,file="$CANDIDATE",format=raw ||
   ! v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$READBACK" >/dev/null ||
   ! cmp -s "$CANDIDATE" "$READBACK" ||
   ! python3 "$ROOT/tools/clone-monitor-edid.py" --check "$READBACK" \
     --source "$MONITOR_RAW" --identity-mode clone >/dev/null; then
  if rollback; then
    echo "Audited recovery EDID installed and verified." >&2
  else
    echo "CRITICAL: recovery EDID could not be verified. Keep HDMI-RX disconnected." >&2
  fi
  exit 5
fi

install -m 0644 "$MONITOR_RAW" "$STATE_DIR/downstream-monitor.bin"
install -m 0644 "$CANDIDATE" "$STATE_DIR/bridge-edid.bin"
install -m 0644 "$MANIFEST" "$STATE_DIR/bridge-manifest.json"
install -m 0644 "$RECOVERY" "$STATE_DIR/recovery-edid.bin"
sha256sum "$CANDIDATE" | awk '{print $1}' >"$STATE_DIR/bridge-edid.sha256"
sha256sum "$MONITOR_RAW" | awk '{print $1}' >"$STATE_DIR/downstream-monitor.sha256"

if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  install -d -m 0755 /usr/local/libexec /etc/default
  install -m 0755 "$ROOT/scripts/load-saved-edid.sh" \
    /usr/local/libexec/hdmirxtest-load-edid
  install -m 0644 "$ROOT/packaging/systemd/hdmirxtest-edid.service" \
    /etc/systemd/system/hdmirxtest-edid.service
  rm -f /usr/local/libexec/hdmirxtest-service-run \
    /etc/systemd/system/hdmirxtest-passthrough.service
  {
    printf 'HDMIRXTEST_ROOT=%s\n' "$ROOT"
    printf 'VIDEO=%s\n' "$VIDEO"
  } >/etc/default/hdmirxtest
  systemctl daemon-reload
  systemctl enable hdmirxtest-edid.service >/dev/null
  systemctl restart hdmirxtest-edid.service
  BOOT_SERVICE="systemd EDID loader installed/enabled; video remains foreground-only"
elif command -v rc-update >/dev/null 2>&1 && [[ -x /sbin/openrc-run ]]; then
  install -m 0755 "$ROOT/packaging/openrc/hdmirxtest-edid" /etc/init.d/hdmirxtest-edid
  rc-update add hdmirxtest-edid boot >/dev/null 2>&1 || true
  BOOT_SERVICE="OpenRC EDID loader installed and enabled"
else
  BOOT_SERVICE="not installed (neither systemd nor OpenRC was detected)"
fi

echo
echo "SAFE BRIDGE SETUP COMPLETE"
echo "Downstream monitor: $SOURCE_LABEL"
python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1], encoding="utf-8"))
i = m["bridge_identity"]
print(f"Windows identity: {i['manufacturer']} product={i['product_code']} name={i['monitor_name']!r}")
print(f"Audit manifest: {sys.argv[1]}")
PY
echo "Mode policy: sink intersection, maximum ${MAX_WIDTH}x${MAX_HEIGHT}@${MAX_REFRESH}, maximum ${MAX_PIXEL_CLOCK} Hz pixel clock"
echo "Signal policy: fixed-rate RGB 8-bit SDR; no DSC, FRL, HDR, VRR or YCbCr advertisement"
echo "HDMI-RX exact read-back: verified"
echo "Boot-time safe EDID loader: $BOOT_SERVICE"
echo
echo "You may now connect the Windows HDMI cable to HDMI-RX."
echo "Then start video with: bash PiCycle.sh"
echo "Press Ctrl+C whenever you want to stop video and use the terminal."
