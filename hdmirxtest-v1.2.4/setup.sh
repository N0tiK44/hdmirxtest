#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if (( EUID == 0 )); then
  echo "Run setup.sh as your normal user, not as root." >&2
  exit 2
fi

cat <<'EOF'
HDMIRXTEST V1.2.4 SETUP

Required wiring right now:
  HDMI-TX -> target monitor: CONNECTED
  Windows -> HDMI-RX:       PHYSICALLY UNPLUGGED

The setup has a safety check and will refuse to rewrite EDID if an active
Windows HDMI source is detected.
EOF

bash "$ROOT/scripts/install-deps.sh"
make -C "$ROOT" check
make -C "$ROOT" -j"$(nproc)"
bash "$ROOT/scripts/pi-cycle.sh" setup

cat <<'EOF'

INSTALLATION COMPLETE
1. Reconnect the Windows HDMI cable to HDMI-RX.
2. Wait for Windows to detect the display.
3. Start video with: bash PiCycle.sh
4. Stop video with:  Ctrl+C
EOF
