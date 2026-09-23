#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:-start}
DURATION=${DURATION:-0}
BUFFERS=${BUFFERS:-4}
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
CONNECTOR=${CONNECTOR:-0}
PLANE=${PLANE:-0}
RX_DISCONNECTED=${RX_DISCONNECTED:-0}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RESULT_DIR=${RESULT_DIR:-/tmp/hdmirxtest-v13-${MODE}-${STAMP}}
ARCHIVE=${ARCHIVE:-$HOME/hdmirxtest-${MODE}-latest.tar.gz}

as_root() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else
    echo "sudo or doas is required for HDMI hardware access." >&2
    return 127
  fi
}

usage() {
  cat <<'EOF'
HDMIRXTEST V1.3

  bash PiCycle.sh              Start foreground video
  Ctrl+C                       Stop video and return to the terminal
  bash PiCycle.sh setup        Read and install the HDMI-TX monitor EDID
  bash PiCycle.sh debug        Collect a hardware snapshot
  bash PiCycle.sh restoreedid  Install the safe recovery EDID

Physically unplug Windows from HDMI-RX before setup or restoreedid.
Keep the target monitor connected to HDMI-TX.
EOF
}

case "$MODE" in
  start|setup|debug|restoreedid|help|-h|--help) ;;
  *) usage; exit 2 ;;
esac

if [[ "$MODE" == help || "$MODE" == -h || "$MODE" == --help ]]; then
  usage
  exit 0
fi

if (( EUID == 0 )); then
  echo "Run PiCycle.sh as your normal user. It uses sudo only when required." >&2
  exit 2
fi

cd "$ROOT"

build_if_needed() {
  if [[ ! -x "$ROOT/rk3588-hdmi-passthrough" ]] ||
     ! make -q rk3588-hdmi-passthrough >/dev/null 2>&1; then
    echo "Building the passthrough program..."
    make check
    make -j"$(nproc)"
  fi
}

mkdir -p "$RESULT_DIR"
RUN_RC=0

case "$MODE" in
  setup)
    set +e
    as_root env VIDEO="$VIDEO" CARD="$CARD" CONNECTOR="$CONNECTOR" PLANE="$PLANE" \
      BUFFERS="$BUFFERS" RX_DISCONNECTED="$RX_DISCONNECTED" \
      bash "$ROOT/scripts/prepare-monitor-edid.sh" 2>&1 | tee "$RESULT_DIR/setup.log"
    RUN_RC=${PIPESTATUS[0]}
    set -e
    if (( RUN_RC == 0 )); then
      for state_file in bridge-manifest.json bridge-edid.bin bridge-edid.sha256 \
        downstream-monitor.bin downstream-monitor.sha256 recovery-edid.bin; do
        as_root cp "/var/lib/hdmirxtest/$state_file" "$RESULT_DIR/$state_file" 2>/dev/null || true
      done
    fi
    ;;

  restoreedid)
    set +e
    as_root env VIDEO="$VIDEO" RX_DISCONNECTED="$RX_DISCONNECTED" \
      bash "$ROOT/scripts/restore-rx-edid.sh" 2>&1 | tee "$RESULT_DIR/restore-edid.log"
    RUN_RC=${PIPESTATUS[0]}
    set -e
    ;;

  debug)
    as_root env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" \
      bash "$ROOT/scripts/collect-debug.sh" debug || RUN_RC=$?
    ;;

  start)
    if command -v systemctl >/dev/null 2>&1; then
      as_root systemctl stop hdmirxtest-tx-selftest.service >/dev/null 2>&1 || true
    fi
    if command -v systemctl >/dev/null 2>&1 &&
       as_root systemctl is-active --quiet hdmirxtest-passthrough.service 2>/dev/null; then
      echo "Stopping the background video service..."
      as_root systemctl disable --now hdmirxtest-passthrough.service >/dev/null 2>&1 || true
    fi

    set +e
    as_root env VIDEO="$VIDEO" CARD="$CARD" bash "$ROOT/scripts/check-monitor-identity.sh"
    MONITOR_RC=$?
    set -e
    if (( MONITOR_RC != 0 )); then
      RUN_RC=$MONITOR_RC
    else
      build_if_needed
      if as_root env VIDEO="$VIDEO" bash "$ROOT/scripts/verify-bridge-edid.sh"; then
        echo
        echo "VIDEO IS RUNNING — press Ctrl+C to stop and return to the terminal."
        echo
        set +e
        as_root env DURATION="$DURATION" BUFFERS="$BUFFERS" VIDEO="$VIDEO" \
          CARD="$CARD" CONNECTOR="$CONNECTOR" PLANE="$PLANE" \
          TARGET_REFRESH_MILLIHZ=auto AUTO_RESTART=1 WAIT_FOR_SOURCE=1 \
          CSV="$RESULT_DIR/trace.csv" \
          bash "$ROOT/scripts/run.sh" 2>&1 | tee "$RESULT_DIR/run.log"
        RUN_RC=${PIPESTATUS[0]}
        set -e
        if (( RUN_RC == 130 || RUN_RC == 143 )); then
          RUN_RC=0
        fi
        echo
        echo "Video stopped. The terminal is ready."
      else
        RUN_RC=$?
      fi
    fi
    ;;
esac

{
  echo "version=1.3"
  echo "mode=$MODE"
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "run_exit=$RUN_RC"
  echo "duration_seconds=$DURATION"
  echo "buffers=$BUFFERS"
} >"$RESULT_DIR/pi-cycle.txt"

as_root chown -R "$(id -u):$(id -g)" "$RESULT_DIR" 2>/dev/null || true
tar -czf "$ARCHIVE" -C "$RESULT_DIR" .
echo "Result archive: $ARCHIVE"
exit "$RUN_RC"
