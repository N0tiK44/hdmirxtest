#!/usr/bin/env bash
set -euo pipefail

ROOT=${HDMIRXTEST_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}

if (( EUID != 0 )); then
  echo "The persistent passthrough service must run as root." >&2
  exit 2
fi

# Fail closed before claiming the DRM device. systemd retries if HDMI-TX or the
# source is not ready yet. A changed TX monitor is staged safely by the same
# identity preflight used by the manual live path.
NO_AUTO_APPLY=1 bash "$ROOT/scripts/check-monitor-identity.sh"
bash "$ROOT/scripts/verify-bridge-edid.sh"

exec env \
  DURATION=0 \
  WAIT_FOR_SOURCE=1 \
  VIDEO="$VIDEO" \
  CARD="$CARD" \
  bash "$ROOT/scripts/run.sh"
