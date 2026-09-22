#!/usr/bin/env bash
set -u

OUTDIR=${OUTDIR:-/tmp/hdmirx-v11-240}
VIDEO=${VIDEO:-/dev/video0}
mkdir -p "$OUTDIR"
OUT="$OUTDIR/probe-240.txt"

if (( EUID != 0 )); then
  echo "Run probe-240.sh with sudo." >&2
  exit 2
fi

if ! command -v v4l2-ctl >/dev/null 2>&1; then
  echo "v4l2-ctl is required. Run scripts/install-deps.sh first." | tee "$OUT" >&2
  exit 2
fi

set +e
TIMING=$(v4l2-ctl -d "$VIDEO" --query-dv-timings 2>&1)
RC=$?
set -e

{
  echo "=== RK3588 HDMI-RX 1080p240 feasibility gate ==="
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "video=$VIDEO"
  echo
  echo "$TIMING"
} >"$OUT"

if (( RC != 0 )); then
  echo "RESULT=NO_SIGNAL_OR_TIMING_QUERY_FAILED" | tee -a "$OUT"
  exit 3
fi

FPS=$(printf '%s\n' "$TIMING" | sed -nE 's/.*\(([0-9]+([.][0-9]+)?) frames per second\).*/\1/p' | head -n1)
WIDTH=$(printf '%s\n' "$TIMING" | sed -nE 's/^[[:space:]]*Active width:[[:space:]]*([0-9]+).*/\1/p' | head -n1)
HEIGHT=$(printf '%s\n' "$TIMING" | sed -nE 's/^[[:space:]]*Active height:[[:space:]]*([0-9]+).*/\1/p' | head -n1)

# Some v4l2-ctl versions print "Active WxH" differently. Fall back to common labels.
[[ -n "$WIDTH" ]] || WIDTH=$(printf '%s\n' "$TIMING" | sed -nE 's/^[[:space:]]*Width:[[:space:]]*([0-9]+).*/\1/p' | head -n1)
[[ -n "$HEIGHT" ]] || HEIGHT=$(printf '%s\n' "$TIMING" | sed -nE 's/^[[:space:]]*Height:[[:space:]]*([0-9]+).*/\1/p' | head -n1)

printf 'parsed_width=%s\nparsed_height=%s\nparsed_fps=%s\n' "${WIDTH:-unknown}" "${HEIGHT:-unknown}" "${FPS:-unknown}" >>"$OUT"

if [[ "$WIDTH" != "1920" || "$HEIGHT" != "1080" || -z "$FPS" ]]; then
  echo "RESULT=NOT_CONFIRMED_1080P240" | tee -a "$OUT"
  echo "Set the Windows HDMI source to 1920x1080 at ~240 Hz, then rerun." | tee -a "$OUT"
  exit 3
fi

set +e
python3 - "$FPS" >>"$OUT" <<'PY'
import sys
fps=float(sys.argv[1])
if 230.0 <= fps <= 250.0:
    print("RESULT=INPUT_1080P240_CONFIRMED")
    raise SystemExit(0)
print("RESULT=NOT_CONFIRMED_1080P240")
print(f"Observed {fps:.3f} fps; expected roughly 230-250 fps.")
raise SystemExit(3)
PY
RC=$?
set -e

if (( RC == 0 )); then
  echo >>"$OUT"
  echo "Locking V4L2 to the detected DV timing and requesting NV24..." >>"$OUT"
  v4l2-ctl -d "$VIDEO" --set-dv-bt-timings query >>"$OUT" 2>&1 || true
  v4l2-ctl -d "$VIDEO" --set-fmt-video=width=1920,height=1080,pixelformat=NV24 >>"$OUT" 2>&1 || true
  v4l2-ctl -d "$VIDEO" --get-dv-timings >>"$OUT" 2>&1 || true
  v4l2-ctl -d "$VIDEO" --get-fmt-video >>"$OUT" 2>&1 || true
  echo "Input timing is suitable for the experimental 240-Hz passthrough run." >>"$OUT"
fi
exit "$RC"
