#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
VIDEO=${VIDEO:-/dev/video0}
STATE_DIR=${STATE_DIR:-/var/lib/hdmirxtest}
EXPECTED="$STATE_DIR/bridge-edid.bin"
SOURCE="$STATE_DIR/downstream-monitor.bin"
CHECK_FILE=$(mktemp /tmp/hdmirxtest-current-edid.XXXXXX.bin)
trap 'rm -f -- "$CHECK_FILE"' EXIT

if (( EUID != 0 )); then
  echo "Run with sudo." >&2
  exit 2
fi

if ! v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$CHECK_FILE" >/dev/null 2>&1; then
  echo "Could not read the HDMI-RX EDID. Passthrough was not started." >&2
  exit 3
fi

if [[ ! -s "$EXPECTED" ]] || ! cmp -s "$EXPECTED" "$CHECK_FILE"; then
  echo "SAFETY STOP: HDMI-RX does not exactly match the installed bridge EDID." >&2
  echo "Unplug the Windows HDMI source and run: bash PiCycle.sh setup" >&2
  exit 4
fi

AUDIT_ARGS=(--check "$CHECK_FILE")
if [[ -s "$SOURCE" ]]; then
  AUDIT_ARGS+=(--source "$SOURCE" --identity-mode clone)
fi
if ! python3 "$ROOT/tools/clone-monitor-edid.py" "${AUDIT_ARGS[@]}" >/dev/null 2>&1; then
  echo "SAFETY STOP: installed bridge EDID failed the capability/identity audit." >&2
  exit 4
fi

echo "HDMI-RX exact-state, capability and identity checks: passed"
