#!/usr/bin/env bash
set -u

OUT=${1:?Usage: collect-tx-state.sh OUTPUT_DIRECTORY}
mkdir -p "$OUT/connectors" "$OUT/cards" "$OUT/debugfs"

{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unavailable)"
  echo "uptime=$(cat /proc/uptime 2>/dev/null || echo unavailable)"
  echo "kernel=$(uname -a)"
  echo "cmdline=$(cat /proc/cmdline 2>/dev/null || echo unavailable)"
} >"$OUT/system.txt"

ls -la /dev/dri >"$OUT/dev-dri.txt" 2>&1 || true
ls -la /sys/class/drm >"$OUT/sys-class-drm.txt" 2>&1 || true

shopt -s nullglob
for card in /sys/class/drm/card[0-9]*; do
  name=$(basename "$card")
  [[ "$name" =~ ^card[0-9]+$ ]] || continue
  [[ -e "$card/device" ]] || continue
  {
    echo "path=$card"
    echo "device=$(readlink -f "$card/device" 2>/dev/null || true)"
    echo "driver=$(readlink -f "$card/device/driver" 2>/dev/null || true)"
    [[ -r "$card/device/uevent" ]] && cat "$card/device/uevent"
  } >"$OUT/cards/$name.txt"
done

for connector in /sys/class/drm/card*-*; do
  [[ -r "$connector/status" ]] || continue
  name=$(basename "$connector")
  target="$OUT/connectors/$name"
  mkdir -p "$target"
  for property in status enabled dpms modes link_status; do
    if [[ -r "$connector/$property" ]]; then
      cat "$connector/$property" >"$target/$property.txt" 2>&1 || true
    fi
  done
  if [[ -r "$connector/edid" ]]; then
    cp "$connector/edid" "$target/edid.bin" 2>/dev/null || true
    wc -c <"$target/edid.bin" >"$target/edid-size.txt" 2>/dev/null || true
    if command -v edid-decode >/dev/null 2>&1; then
      edid-decode "$target/edid.bin" >"$target/edid-decode.txt" 2>&1 || true
    fi
  fi
done

if [[ -d /sys/kernel/debug/dri ]]; then
  for debug_file in /sys/kernel/debug/dri/*/state \
    /sys/kernel/debug/dri/*/summary \
    /sys/kernel/debug/dri/*/clients \
    /sys/kernel/debug/dri/*/name; do
    [[ -r "$debug_file" ]] || continue
    safe_name=${debug_file#/sys/kernel/debug/dri/}
    safe_name=${safe_name//\//-}
    cat "$debug_file" >"$OUT/debugfs/$safe_name.txt" 2>&1 || true
  done
fi

dmesg --color=never >"$OUT/dmesg-full.txt" 2>&1 || true
grep -Ei 'drm|hdmi|dw-hdmi|rockchip|vop|edid|hpd|phy|cec' \
  "$OUT/dmesg-full.txt" >"$OUT/dmesg-hdmi.txt" 2>/dev/null || true

grep -Ei 'hdmi|vop|drm' /proc/interrupts >"$OUT/interrupts-display.txt" 2>/dev/null || true

if command -v modetest >/dev/null 2>&1; then
  for device in /dev/dri/card[0-9]*; do
    [[ -e "$device" ]] || continue
    name=$(basename "$device")
    timeout 15 modetest -D "$device" -c -e -p \
      >"$OUT/modetest-$name.txt" 2>&1 || true
  done
fi

exit 0
