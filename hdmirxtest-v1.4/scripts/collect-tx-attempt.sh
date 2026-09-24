#!/usr/bin/env bash
set -u

OUT=${1:?Usage: collect-tx-attempt.sh OUTPUT_DIRECTORY}
mkdir -p "$OUT/connectors" "$OUT/debugfs"

{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unavailable)"
  echo "uptime=$(cat /proc/uptime 2>/dev/null || echo unavailable)"
} >"$OUT/time.txt"

ls -l /sys/class/drm >"$OUT/sys-class-drm.txt" 2>&1 || true

shopt -s nullglob
for connector in /sys/class/drm/card*-*; do
  [[ -r "$connector/status" ]] || continue
  name=$(basename "$connector")
  target="$OUT/connectors/$name"
  mkdir -p "$target"
  for property in status enabled dpms modes link_status; do
    [[ -r "$connector/$property" ]] || continue
    cat "$connector/$property" >"$target/$property.txt" 2>&1 || true
  done
  if [[ -r "$connector/edid" ]]; then
    wc -c <"$connector/edid" >"$target/edid-size.txt" 2>/dev/null || true
    sha256sum "$connector/edid" >"$target/edid-sha256.txt" 2>/dev/null || true
  fi
done

if [[ -d /sys/kernel/debug/dri ]]; then
  for debug_file in /sys/kernel/debug/dri/*/state /sys/kernel/debug/dri/*/summary; do
    [[ -r "$debug_file" ]] || continue
    safe_name=${debug_file#/sys/kernel/debug/dri/}
    safe_name=${safe_name//\//-}
    cat "$debug_file" >"$OUT/debugfs/$safe_name.txt" 2>&1 || true
  done
fi

dmesg --color=never 2>/dev/null | tail -n 500 >"$OUT/dmesg-tail.txt" || true
grep -Ei 'drm|hdmi|dw-hdmi|rockchip|vop|edid|hpd|phy|cec' \
  "$OUT/dmesg-tail.txt" >"$OUT/dmesg-hdmi-tail.txt" 2>/dev/null || true

grep -Ei 'hdmi|vop|drm' /proc/interrupts >"$OUT/interrupts-display.txt" 2>/dev/null || true

exit 0
