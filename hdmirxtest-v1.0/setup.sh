#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if (( EUID == 0 )); then
  echo "Run setup.sh as your normal user, not as root." >&2
  exit 2
fi

cat <<'EOF'
HDMIRXTEST V1.0 SETUP

Required wiring:
  HDMI-TX -> target monitor: CONNECTED
  Windows -> HDMI-RX:       PHYSICALLY UNPLUGGED

Setup will refuse to rewrite EDID if an active HDMI-RX source is detected.
EOF

bash "$ROOT/scripts/install-deps.sh"
make -C "$ROOT" check
make -C "$ROOT" -j"$(nproc)"
bash "$ROOT/scripts/pi-cycle.sh" setup

cat <<'EOF'

SETUP COMPLETE
1. Reconnect Windows to HDMI-RX.
2. Wait for Windows to detect the display.
3. Start video: bash PiCycle.sh
4. Stop video:  Ctrl+C
EOF
