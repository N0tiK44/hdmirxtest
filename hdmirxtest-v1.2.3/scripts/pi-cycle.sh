#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:-live}
BRANCH=${BRANCH:-main}
DURATION=${DURATION:-}
BUFFERS=${BUFFERS:-4}
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
CONNECTOR=${CONNECTOR:-217}
PLANE=${PLANE:-114}
SYNC=${SYNC:-0}
DIAGNOSTICS=${DIAGNOSTICS:-0}
RX_DISCONNECTED=${RX_DISCONNECTED:-0}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RESULT_DIR=${RESULT_DIR:-/tmp/hdmirxtest-v123-${MODE}-${STAMP}}
ARCHIVE=${ARCHIVE:-$HOME/hdmirxtest-${MODE}-latest.tar.gz}
LEGACY_ARCHIVE=${LEGACY_ARCHIVE:-$HOME/hdmirxtest-latest.tar.gz}

if (( EUID == 0 )); then
  echo "Run pi-cycle.sh as your normal user. It elevates only hardware commands." >&2
  exit 2
fi

as_root() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else
    echo "Need sudo or doas for hardware access." >&2
    return 127
  fi
}

usage() {
  cat >&2 <<'EOF'
Usage: bash scripts/pi-cycle.sh MODE

Fast paths (no network fetch, clean rebuild, or pre-run debug dump):
  live | 240       Auto-match the current HDMI-RX timing and start immediately
  setup             Clone HDMI-TX identity and install its safe mode intersection
  preparemonitor    Alias for setup
  prepare240        Legacy alias for setup

Maintenance / diagnostics:
  sync             Update the checkout from origin/main, then build
  diagnostic       120-second auto-refresh diagnostic with full profiling
  baseline         Legacy fixed 59.940-Hz diagnostic
  probe240          Query HDMI-RX without starting passthrough
  restoreedid       Install the audited safe recovery EDID (never old stock)
  debug             Collect a hardware snapshot only
  service-start     Start/restart persistent Ubuntu/systemd passthrough
  service-stop      Stop persistent Ubuntu/systemd passthrough
  service-status    Show persistent passthrough status and recent log

Set SYNC=1 before another mode when an update must be fetched first.
Set DIAGNOSTICS=1 to collect post-run hardware diagnostics on a fast live run.
Live/240 runs continuously by default. Set DURATION=120 only for a timed test.
EOF
}

case "$MODE" in
  live|240|setup|preparemonitor|prepare240|sync|diagnostic|baseline|probe240|restoreedid|debug|service-start|service-stop|service-status) ;;
  *) usage; exit 2 ;;
esac

if [[ -z "$DURATION" ]]; then
  case "$MODE" in
    live|240|service-start) DURATION=0 ;;
    *) DURATION=120 ;;
  esac
fi

cd "$ROOT"

sync_checkout() {
  if [[ -n $(git status --porcelain) ]]; then
    echo "Local changes detected; saving them before sync."
    git stash push -u -m "pi-cycle auto-backup $STAMP" >/dev/null
    echo "Saved as: $(git stash list -1)"
  fi

  git fetch origin "$BRANCH"
  CURRENT=$(git rev-parse HEAD 2>/dev/null || true)
  REMOTE=$(git rev-parse "origin/$BRANCH")
  if [[ -n "$CURRENT" && "$CURRENT" != "$REMOTE" ]] &&
     ! git merge-base --is-ancestor "$CURRENT" "$REMOTE" 2>/dev/null; then
    BACKUP_BRANCH="backup/pi-before-sync-$STAMP"
    git branch "$BACKUP_BRANCH" "$CURRENT" 2>/dev/null || true
    echo "Divergent committed state preserved as $BACKUP_BRANCH"
  fi
  git switch -C "$BRANCH" "origin/$BRANCH"
  echo "Checkout synced to $(git rev-parse --short HEAD) on $BRANCH"
}

if [[ "$MODE" == sync || "$SYNC" == 1 ]]; then
  sync_checkout
fi

build_if_needed() {
  if [[ ! -x "$ROOT/rk3588-hdmi-passthrough" ]] ||
     ! make -q rk3588-hdmi-passthrough >/dev/null 2>&1; then
    echo "Building changed sources..."
    make check
    make
  fi
}

if [[ "$MODE" == sync ]]; then
  build_if_needed
  echo "Update complete. Start video with: bash scripts/pi-cycle.sh 240"
  exit 0
fi

mkdir -p "$RESULT_DIR"
RUN_RC=0

case "$MODE" in
  setup|preparemonitor|prepare240)
    set +e
    as_root env VIDEO="$VIDEO" CARD="$CARD" CONNECTOR="$CONNECTOR" PLANE="$PLANE" \
      BUFFERS="$BUFFERS" RX_DISCONNECTED="$RX_DISCONNECTED" \
      bash "$ROOT/scripts/prepare-monitor-edid.sh" 2>&1 | tee "$RESULT_DIR/prepare-monitor-edid.log"
    RUN_RC=${PIPESTATUS[0]}
    set -e
    if (( RUN_RC == 0 )); then
      for state_file in \
        bridge-manifest.json bridge-edid.bin bridge-edid.sha256 \
        downstream-monitor.bin downstream-monitor.sha256 recovery-edid.bin; do
        if [[ -r "/var/lib/hdmirxtest/$state_file" ]]; then
          cp "/var/lib/hdmirxtest/$state_file" "$RESULT_DIR/$state_file"
        else
          as_root cp "/var/lib/hdmirxtest/$state_file" "$RESULT_DIR/$state_file" 2>/dev/null || true
        fi
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

  service-start)
    build_if_needed
    as_root env VIDEO="$VIDEO" bash "$ROOT/scripts/verify-bridge-edid.sh"
    as_root systemctl restart hdmirxtest-passthrough.service
    as_root systemctl --no-pager --full status hdmirxtest-passthrough.service || RUN_RC=$?
    ;;

  service-stop)
    as_root systemctl stop hdmirxtest-passthrough.service || RUN_RC=$?
    ;;

  service-status)
    as_root systemctl --no-pager --full status hdmirxtest-passthrough.service || RUN_RC=$?
    as_root journalctl -u hdmirxtest-passthrough.service -n 80 --no-pager || true
    ;;

  probe240)
    as_root env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" \
      bash "$ROOT/scripts/probe-240.sh" || RUN_RC=$?
    ;;

  live|240)
    if command -v systemctl >/dev/null 2>&1 &&
       as_root systemctl is-active --quiet hdmirxtest-passthrough.service; then
      echo "Stopping the persistent service so this foreground run can own HDMI-RX/DRM."
      as_root systemctl stop hdmirxtest-passthrough.service
    fi
    set +e
    as_root env VIDEO="$VIDEO" CARD="$CARD" \
      bash "$ROOT/scripts/check-monitor-identity.sh"
    MONITOR_RC=$?
    set -e
    if (( MONITOR_RC != 0 )); then
      RUN_RC=$MONITOR_RC
    else
      build_if_needed
      set +e
      as_root env VIDEO="$VIDEO" bash "$ROOT/scripts/verify-bridge-edid.sh"
      VERIFY_RC=$?
      set -e
      if (( VERIFY_RC != 0 )); then
        RUN_RC=$VERIFY_RC
      else
        echo "Starting zero-copy video now (automatic input refresh; hard limit 1080p240)..."
        set +e
        as_root env \
          DURATION="$DURATION" \
          BUFFERS="$BUFFERS" \
          VIDEO="$VIDEO" \
          CARD="$CARD" \
          CONNECTOR="$CONNECTOR" \
          PLANE="$PLANE" \
          TARGET_REFRESH_MILLIHZ=auto \
          CSV="$RESULT_DIR/trace.csv" \
          bash "$ROOT/scripts/run.sh" 2>&1 | tee "$RESULT_DIR/run.log"
        RUN_RC=${PIPESTATUS[0]}
        set -e
        if (( DIAGNOSTICS == 1 )); then
          as_root env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" \
            bash "$ROOT/scripts/collect-debug.sh" post || true
        fi
      fi
    fi
    ;;

  diagnostic|baseline)
    build_if_needed
    if as_root env VIDEO="$VIDEO" bash "$ROOT/scripts/verify-bridge-edid.sh"; then
      as_root env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" \
        bash "$ROOT/scripts/collect-debug.sh" pre || true
      TARGET=auto
      [[ "$MODE" == baseline ]] && TARGET=59940
      as_root env \
        OUTDIR="$RESULT_DIR" \
        DURATION="$DURATION" \
        BUFFERS="$BUFFERS" \
        VIDEO="$VIDEO" \
        CARD="$CARD" \
        CONNECTOR="$CONNECTOR" \
        PLANE="$PLANE" \
        TARGET_REFRESH_MILLIHZ="$TARGET" \
        bash "$ROOT/scripts/diagnose.sh" || RUN_RC=$?
      as_root env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" \
        bash "$ROOT/scripts/collect-debug.sh" post || true
    else
      RUN_RC=4
    fi
    ;;
esac

{
  echo "version=1.2.3"
  echo "mode=$MODE"
  echo "branch=$BRANCH"
  echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "run_exit=$RUN_RC"
  echo "duration_seconds=$DURATION"
  echo "buffers=$BUFFERS"
  echo "sync=$SYNC"
  echo "diagnostics=$DIAGNOSTICS"
} >"$RESULT_DIR/pi-cycle.txt"

git status --short >"$RESULT_DIR/git-status-after.txt" 2>/dev/null || true
git log -1 --oneline --decorate >"$RESULT_DIR/git-head.txt" 2>/dev/null || true

as_root chown -R "$(id -u):$(id -g)" "$RESULT_DIR" 2>/dev/null || true
rm -f "$ARCHIVE"
tar -czf "$ARCHIVE" -C "$RESULT_DIR" .
if [[ "$LEGACY_ARCHIVE" != "$ARCHIVE" ]]; then
  cp "$ARCHIVE" "$LEGACY_ARCHIVE"
fi

echo
echo "============================================================"
echo "Pi cycle complete: mode=$MODE exit=$RUN_RC"
echo "Result archive: $ARCHIVE"
echo "============================================================"
exit "$RUN_RC"
