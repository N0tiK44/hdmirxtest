#!/usr/bin/env bash
set -u

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUTDIR=${OUTDIR:-/tmp/hdmirxtest-v11-debug}
VIDEO=${VIDEO:-/dev/video0}
CARD=${CARD:-/dev/dri/card0}
PHASE=${1:-snapshot}

if (( EUID != 0 )); then
  echo "Run collect-debug.sh with sudo." >&2
  exit 2
fi

mkdir -p "$OUTDIR"
OUT="$OUTDIR/debug-${PHASE}.txt"

section() {
  printf '\n===== %s =====\n' "$1" >>"$OUT"
}

run() {
  printf '\n$ %s\n' "$*" >>"$OUT"
  "$@" >>"$OUT" 2>&1 || true
}

{
  echo "hdmirxtest V1.2.3 debug snapshot"
  echo "phase=$PHASE"
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "repo=$ROOT"
  echo "video=$VIDEO"
  echo "card=$CARD"
} >"$OUT"

section "SYSTEM"
run uname -a
run cat /proc/cmdline
run sh -c 'cat /etc/os-release 2>/dev/null || true'
run sh -c 'uptime || true'
run sh -c 'cat /sys/module/rockchip_hdmirx/parameters/low_latency 2>/dev/null || true'

section "GIT"
run git -C "$ROOT" rev-parse HEAD
run git -C "$ROOT" status --short
run git -C "$ROOT" log -1 --oneline --decorate

section "V4L2 / HDMI RX"
if command -v v4l2-ctl >/dev/null 2>&1; then
  run v4l2-ctl -d "$VIDEO" --info
  run v4l2-ctl -d "$VIDEO" --all
  run v4l2-ctl -d "$VIDEO" --query-dv-timings
  run v4l2-ctl -d "$VIDEO" --get-dv-timings
  run v4l2-ctl -d "$VIDEO" --list-formats-ext
  run v4l2-ctl -d "$VIDEO" --list-dv-timings

  RX_EDID="$OUTDIR/rx-edid-${PHASE}.bin"
  if ! v4l2-ctl -d "$VIDEO" --get-edid=pad=0,format=raw,file="$RX_EDID" >>"$OUT" 2>&1; then
    rm -f "$RX_EDID"
    v4l2-ctl -d "$VIDEO" --get-edid=pad=0,file="$RX_EDID" >>"$OUT" 2>&1 || true
  fi
  if [[ -s "$RX_EDID" ]] && command -v edid-decode >/dev/null 2>&1; then
    section "HDMI RX EDID DECODE"
    run edid-decode "$RX_EDID"
  fi
else
  echo "v4l2-ctl not installed" >>"$OUT"
fi

section "DRM / KMS"
run sh -c 'for s in /sys/class/drm/card*-*/status; do [ -f "$s" ] || continue; echo "--- $s"; cat "$s"; done'
run sh -c 'for m in /sys/class/drm/card*-*/modes; do [ -f "$m" ] || continue; echo "--- $m"; cat "$m"; done'
run sh -c 'for e in /sys/class/drm/card*-*/edid; do [ -e "$e" ] || continue; bytes=$(cat "$e" 2>/dev/null | wc -c); [ "$bytes" -gt 0 ] || continue; echo "--- $e ($bytes bytes)"; done'

n=0
for e in /sys/class/drm/card*-*/edid; do
  [[ -e "$e" ]] || continue
  candidate="$OUTDIR/.downstream-edid-${PHASE}-candidate.bin"
  if ! cat "$e" >"$candidate" 2>/dev/null || [[ ! -s "$candidate" ]]; then
    rm -f "$candidate"
    continue
  fi
  n=$((n+1))
  mv "$candidate" "$OUTDIR/downstream-edid-${PHASE}-${n}.bin"
done

if command -v modetest >/dev/null 2>&1; then
  run modetest -M rockchip -c
  run modetest -M rockchip -p
else
  echo "modetest not installed (optional libdrm-tests package)" >>"$OUT"
fi

if command -v drm_info >/dev/null 2>&1; then
  run drm_info "$CARD"
fi

section "DRM DEBUGFS"
run sh -c 'cat /sys/kernel/debug/dri/0/state 2>/dev/null || true'
run sh -c 'cat /sys/kernel/debug/dri/0/summary 2>/dev/null || true'

section "KERNEL MESSAGES"
run sh -c "dmesg | grep -iE 'hdmirx|hdmi|vop2|drm|fence|sync_file|dma' | tail -n 500"

section "DEVICES"
run ls -l "$VIDEO" "$CARD"
run sh -c 'ls -l /dev/video* /dev/dri/* 2>/dev/null || true'

chmod a+r "$OUT" "$OUTDIR"/*.bin 2>/dev/null || true

echo "$OUT"
