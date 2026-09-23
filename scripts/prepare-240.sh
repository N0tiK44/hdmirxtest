#!/usr/bin/env bash
set -euo pipefail

# Compatibility entry point.  The old fixed-profile writer is intentionally
# retired; all preparation now uses the connected HDMI-TX monitor and the
# audited intersection/cap pipeline.
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
exec bash "$ROOT/scripts/prepare-monitor-edid.sh"
