#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BIN="$ROOT/rk3588-hdmi-passthrough"
DURATION=${DURATION:-0}
BUFFERS=${BUFFERS:-4}
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
CONNECTOR=${CONNECTOR:-0}
PLANE=${PLANE:-0}
TARGET_REFRESH_MILLIHZ=${TARGET_REFRESH_MILLIHZ:-auto}
CSV=${CSV:-/tmp/hdmirx-live.csv}
AUTO_RESTART=${AUTO_RESTART:-1}
WAIT_FOR_SOURCE=${WAIT_FOR_SOURCE:-0}

if (( EUID != 0 )); then
  echo "Run this script with sudo." >&2
  exit 2
fi

if [[ ! -x "$BIN" ]]; then
  echo "Binary missing. Run: make clean && make check && make" >&2
  exit 2
fi

if [[ "$DURATION" == 0 ]]; then
  DURATION=2147483647
fi

ARGS=(
  --video "$VIDEO"
  --card "$CARD"
  --connector "$CONNECTOR"
  --plane "$PLANE"
  --seconds "$DURATION"
  --buffers "$BUFFERS"
  --csv "$CSV"
)

if [[ "$TARGET_REFRESH_MILLIHZ" == auto ]]; then
  ARGS+=(--auto-refresh)
else
  ARGS+=(--target-refresh-millihz "$TARGET_REFRESH_MILLIHZ")
fi

RELOCK_TRIES=0
while :; do
  set +e
  "$BIN" "${ARGS[@]}"
  RC=$?
  set -e

  if (( AUTO_RESTART == 1 && RC == 75 )); then
    echo "Input timing changed; rematching HDMI output..." >&2
    RELOCK_TRIES=40
    sleep 0.05
    continue
  fi

  if (( AUTO_RESTART == 1 && RELOCK_TRIES > 0 && RC == 1 )); then
    RELOCK_TRIES=$((RELOCK_TRIES - 1))
    sleep 0.05
    continue
  fi

  if (( AUTO_RESTART == 1 && WAIT_FOR_SOURCE == 1 && RC == 1 )); then
    sleep 0.10
    continue
  fi

  exit "$RC"
done
