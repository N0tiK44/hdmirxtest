#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:-baseline}
BRANCH=${BRANCH:-main}
DURATION=${DURATION:-120}
BUFFERS=${BUFFERS:-4}
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
CONNECTOR=${CONNECTOR:-217}
PLANE=${PLANE:-114}
ARCHIVE=${ARCHIVE:-$HOME/hdmirx-latest.tar.gz}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RESULT_DIR=${RESULT_DIR:-/tmp/hdmirx-v11-${MODE}-${STAMP}}

if (( EUID == 0 )); then
  echo "Run pi-cycle.sh as your normal user. It invokes sudo only for hardware access." >&2
  exit 2
fi

case "$MODE" in
  baseline|probe240|prepare240|240) ;;
  *) echo "Usage: bash scripts/pi-cycle.sh [baseline|probe240|prepare240|240]" >&2; exit 2 ;;
esac

cd "$ROOT"

# Holy-grail update behavior: preserve anything local, then make the SBC checkout
# exactly match origin/<branch>. This avoids the old 'refusing to overwrite local changes'
# dead-end while still keeping recovery points.
if [[ -n $(git status --porcelain) ]]; then
  echo "Local changes detected; saving them to a Git stash before sync."
  git stash push -u -m "pi-cycle auto-backup $STAMP" >/dev/null
  echo "Saved as: $(git stash list -1)"
fi

git fetch origin "$BRANCH"
CURRENT=$(git rev-parse HEAD 2>/dev/null || true)
REMOTE=$(git rev-parse "origin/$BRANCH")
if [[ -n "$CURRENT" && "$CURRENT" != "$REMOTE" ]] && ! git merge-base --is-ancestor "$CURRENT" "$REMOTE" 2>/dev/null; then
  BACKUP_BRANCH="backup/pi-before-sync-$STAMP"
  git branch "$BACKUP_BRANCH" "$CURRENT" 2>/dev/null || true
  echo "Divergent committed SBC state preserved as $BACKUP_BRANCH"
fi

git switch -C "$BRANCH" "origin/$BRANCH"

echo "SBC checkout synced to $(git rev-parse --short HEAD) on $BRANCH"

if [[ "$MODE" == "prepare240" ]]; then
  mkdir -p "$RESULT_DIR"
  sudo env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" bash "$ROOT/scripts/collect-debug.sh" before-prepare240 || true
  set +e
  sudo env VIDEO="$VIDEO" bash "$ROOT/scripts/prepare-240.sh" 2>&1 | tee "$RESULT_DIR/prepare-240.log"
  RUN_RC=${PIPESTATUS[0]}
  set -e
  sudo env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" bash "$ROOT/scripts/collect-debug.sh" after-prepare240 || true
else
  make clean
  if ! make check; then
    echo "Build prerequisites are missing or checks failed." >&2
    echo "Run once: bash scripts/install-deps.sh" >&2
    exit 2
  fi
  make

  mkdir -p "$RESULT_DIR"
  sudo env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" bash "$ROOT/scripts/collect-debug.sh" pre || true

  RUN_RC=0
  if [[ "$MODE" == "probe240" || "$MODE" == "240" ]]; then
    set +e
    sudo env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" bash "$ROOT/scripts/probe-240.sh"
    PROBE_RC=$?
    set -e
    if [[ "$MODE" == "probe240" ]]; then
      RUN_RC=$PROBE_RC
    elif (( PROBE_RC != 0 )); then
      echo "240-Hz passthrough was NOT started because the HDMI-RX input is not confirmed at 1080p240." | tee "$RESULT_DIR/240-gate.txt"
      RUN_RC=$PROBE_RC
    fi
  fi

  if [[ "$MODE" == "baseline" || ( "$MODE" == "240" && "$RUN_RC" == "0" ) ]]; then
    if [[ "$MODE" == "240" ]]; then
      TARGET=240000
    else
      TARGET=59940
    fi
    set +e
    sudo env \
      OUTDIR="$RESULT_DIR" \
      DURATION="$DURATION" \
      BUFFERS="$BUFFERS" \
      VIDEO="$VIDEO" \
      CARD="$CARD" \
      CONNECTOR="$CONNECTOR" \
      PLANE="$PLANE" \
      TARGET_REFRESH_MILLIHZ="$TARGET" \
      bash "$ROOT/scripts/diagnose.sh"
    RUN_RC=$?
    set -e
  fi

  sudo env OUTDIR="$RESULT_DIR" VIDEO="$VIDEO" CARD="$CARD" bash "$ROOT/scripts/collect-debug.sh" post || true
fi

{
  echo "mode=$MODE"
  echo "branch=$BRANCH"
  echo "commit=$(git rev-parse HEAD)"
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "run_exit=$RUN_RC"
  echo "duration_seconds=$DURATION"
  echo "buffers=$BUFFERS"
} >"$RESULT_DIR/pi-cycle.txt"

git status --short >"$RESULT_DIR/git-status-after.txt" || true
git log -1 --oneline --decorate >"$RESULT_DIR/git-head.txt" || true

sudo chown -R "$(id -u):$(id -g)" "$RESULT_DIR" 2>/dev/null || true
rm -f "$ARCHIVE"
tar -czf "$ARCHIVE" -C "$RESULT_DIR" .

echo
echo "============================================================"
echo "Pi cycle complete: mode=$MODE exit=$RUN_RC"
echo "Result archive: $ARCHIVE"
echo "============================================================"
echo "Send this .tar.gz back for review even if the 240-Hz gate failed."
exit "$RUN_RC"
