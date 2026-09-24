#!/usr/bin/env bash
set -uo pipefail

STATE_DIR=/var/lib/hdmirxtest/tv-diag
ARM_FILE="$STATE_DIR/armed"
HISTORY_DIR="$STATE_DIR/history"
RUNTIME_DIR=/run/hdmirxtest
HEARTBEAT="$RUNTIME_DIR/tv-diag-heartbeat"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_ID="${STAMP}-${BOOT_ID:0:8}"
RUN_DIR="$HISTORY_DIR/$RUN_ID"
EDID_DIR="$RUN_DIR/edid"
LOG="$RUN_DIR/diagnostic.txt"
SAMPLE_INTERVAL=2
SAMPLE_COUNT=45

mkdir -p "$RUNTIME_DIR"

heartbeat() {
  local state=${1:-unknown}
  shift || true
  local tmp="$HEARTBEAT.tmp.$$"
  {
    echo "version=1.5"
    echo "diagnostic=passive-tv"
    echo "state=$state"
    echo "run_id=${RUN_ID:-none}"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'detail='
    printf '%s ' "$@"
    printf '\n'
  } >"$tmp"
  mv -f "$tmp" "$HEARTBEAT"
}

# Normal boots are intentionally inert.
if [[ ! -f "$ARM_FILE" ]]; then
  heartbeat idle field-test-not-armed
  exit 0
fi

ARM_METADATA=$(cat "$ARM_FILE" 2>/dev/null || true)
# Consume before doing any work so a crash/reboot cannot loop forever.
rm -f "$ARM_FILE"

mkdir -p "$RUN_DIR" "$EDID_DIR"
ln -sfn "$RUN_DIR" "$STATE_DIR/latest"
exec > >(tee -a "$LOG") 2>&1

heartbeat boot collecting-passive-state

echo "HDMIRXTEST V1.5 PASSIVE TV HDMI DIAGNOSTIC"
echo "run_id=$RUN_ID"
echo "boot_id=$BOOT_ID"
echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf 'arm_metadata=%q\n' "$ARM_METADATA"
echo "sample_interval_seconds=$SAMPLE_INTERVAL"
echo "sample_count=$SAMPLE_COUNT"
echo "IMPORTANT: this diagnostic performs no DRM modesets and never opens HDMI-RX."
echo

echo "===== SYSTEM ====="
date || true
uname -a || true
cat /proc/device-tree/model 2>/dev/null || true
echo
printf 'cmdline='; cat /proc/cmdline 2>/dev/null || true
echo

echo "===== DRM CLASS ====="
ls -la /sys/class/drm/ 2>&1 || true

echo "===== DRM CONNECTOR SYMLINKS ====="
for x in /sys/class/drm/card*-HDMI-*; do
  [[ -e "$x" ]] || continue
  printf '%s -> ' "$x"
  readlink -f "$x" 2>/dev/null || true
  cat "$x/uevent" 2>/dev/null || true
  echo
 done

mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true

printf 'sample\tmonotonic_s\tconnector\tstatus\tedid_bytes\tedid_sha256\tmodes\n' >"$RUN_DIR/samples.tsv"

for n in $(seq 1 "$SAMPLE_COUNT"); do
  heartbeat sample "n=$n/$SAMPLE_COUNT"
  now_mono=$(cut -d' ' -f1 /proc/uptime 2>/dev/null || echo unknown)
  echo
  echo "===== SAMPLE $n/$SAMPLE_COUNT uptime=${now_mono}s utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) ====="

  found=0
  shopt -s nullglob
  for x in /sys/class/drm/card*-HDMI-*; do
    [[ -e "$x" ]] || continue
    found=1
    name=$(basename "$x")
    status=$(cat "$x/status" 2>/dev/null || echo unreadable)
    modes=$(tr '\n' ',' <"$x/modes" 2>/dev/null | sed 's/,$//' || true)
    edid_bytes=0
    edid_hash="-"
    if [[ -r "$x/edid" ]]; then
      edid_bytes=$(wc -c <"$x/edid" 2>/dev/null || echo 0)
      if [[ "$edid_bytes" =~ ^[0-9]+$ ]] && (( edid_bytes > 0 )); then
        edid_hash=$(sha256sum "$x/edid" 2>/dev/null | awk '{print $1}' || echo hash-error)
        # Save the first valid EDID seen for each connector plus the final one later.
        if [[ ! -s "$EDID_DIR/${name}-first.bin" ]]; then
          cp "$x/edid" "$EDID_DIR/${name}-first.bin" 2>/dev/null || true
        fi
      fi
    fi

    echo "--- $name ---"
    echo "status=$status"
    echo "edid_bytes=$edid_bytes"
    echo "edid_sha256=$edid_hash"
    echo "modes=${modes:-<none>}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$n" "$now_mono" "$name" "$status" "$edid_bytes" "$edid_hash" "${modes:-}" \
      >>"$RUN_DIR/samples.tsv"
  done
  if (( found == 0 )); then
    echo "No card*-HDMI-* connectors exist in sysfs at this sample."
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$n" "$now_mono" none absent 0 - '' >>"$RUN_DIR/samples.tsv"
  fi

  sleep "$SAMPLE_INTERVAL"
done

heartbeat final-snapshot
echo
echo "===== FINAL CONNECTOR SNAPSHOT ====="
for x in /sys/class/drm/card*-HDMI-*; do
  [[ -e "$x" ]] || continue
  name=$(basename "$x")
  echo "--- $name ---"
  echo -n "status="; cat "$x/status" 2>/dev/null || true
  echo "modes:"
  cat "$x/modes" 2>/dev/null || true
  if [[ -s "$x/edid" ]]; then
    cp "$x/edid" "$EDID_DIR/${name}-final.bin" 2>/dev/null || true
    if command -v edid-decode >/dev/null 2>&1; then
      edid-decode "$x/edid" >"$EDID_DIR/${name}-final.txt" 2>&1 || true
    fi
  fi
  echo
 done

echo "===== DRM DEBUG STATE ====="
shopt -s nullglob
for state in /sys/kernel/debug/dri/*/state; do
  echo "--- $state ---"
  cat "$state" 2>/dev/null || true
 done

echo "===== FILTERED DMESG ====="
dmesg | grep -Ei 'hdmi|drm|edid|hpd|hdptx|phy|tmds|vop|dclk|scdc|connector' || true

dmesg >"$RUN_DIR/dmesg-full.txt" 2>&1 || true
if command -v journalctl >/dev/null 2>&1; then
  journalctl -b -k --no-pager >"$RUN_DIR/journal-kernel.txt" 2>&1 || true
fi

# Produce a compact human-readable summary before packaging.
{
  echo "HDMIRXTEST V1.5 passive TV diagnostic summary"
  echo "run_id=$RUN_ID"
  echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "Final HDMI connector states:"
  for x in /sys/class/drm/card*-HDMI-*; do
    [[ -e "$x" ]] || continue
    name=$(basename "$x")
    status=$(cat "$x/status" 2>/dev/null || echo unreadable)
    bytes=$(wc -c <"$x/edid" 2>/dev/null || echo 0)
    echo "  $name status=$status edid_bytes=$bytes"
  done
  echo
  echo "See samples.tsv for the 90-second status/EDID timeline."
  echo "See diagnostic.txt and dmesg-full.txt for HDMI/PHY/kernel evidence."
} >"$RUN_DIR/summary.txt"

# Keep a self-contained archive on-device as well as the normal history tree.
tar -C "$HISTORY_DIR" -czf "$STATE_DIR/latest-tv-diag.tar.gz" "$(basename "$RUN_DIR")" 2>/dev/null || true

heartbeat done "history=$RUN_DIR"
echo
echo "===== DONE ====="
cat "$RUN_DIR/summary.txt"
echo "automatic_poweroff_in_seconds=10"
sync
sleep 10
heartbeat shutdown "history=$RUN_DIR"
sync
if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
  systemctl poweroff --no-block || true
elif command -v poweroff >/dev/null 2>&1; then
  poweroff || true
elif command -v shutdown >/dev/null 2>&1; then
  shutdown -h now || true
fi

heartbeat shutdown-failed "history=$RUN_DIR"
exit 0
