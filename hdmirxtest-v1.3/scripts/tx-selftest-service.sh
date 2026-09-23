#!/usr/bin/env bash
set -uo pipefail

CARD=${CARD:-auto}
SECONDS_TO_RUN=${SECONDS_TO_RUN:-120}
WAIT_SECONDS=${WAIT_SECONDS:-90}
STATE_DIR=/var/lib/hdmirxtest
HISTORY_DIR="$STATE_DIR/tx-history"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_ID="${STAMP}-${BOOT_ID:0:8}"
RUN_DIR="$HISTORY_DIR/$RUN_ID"
LOG="$RUN_DIR/tx-selftest.log"
EDID="$RUN_DIR/selected-display-edid.bin"
BIN=/usr/local/bin/hdmirxtest-tx-selftest
COLLECT=/usr/local/libexec/hdmirxtest-collect-tx-state

mkdir -p "$RUN_DIR"
ln -sfn "$RUN_DIR" "$STATE_DIR/tx-latest"
exec > >(tee -a "$LOG") 2>&1

echo "HDMIRXTEST V1.3 HDMI-TX SELF-TEST"
echo "run_id=$RUN_ID"
echo "run_directory=$RUN_DIR"
echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "configured_card=$CARD"
echo "HDMI-RX is not used by this test."

"$COLLECT" "$RUN_DIR/01-before-wait" || true

connected_cards() {
  local connector base candidate seen=" "
  shopt -s nullglob
  for connector in /sys/class/drm/card*-HDMI-*/status; do
    [[ "$(cat "$connector" 2>/dev/null)" == connected ]] || continue
    base=$(basename "$(dirname "$connector")")
    candidate=${base%%-*}
    [[ -e "/dev/dri/$candidate" ]] || continue
    if [[ "$seen" != *" $candidate "* ]]; then
      printf '/dev/dri/%s\n' "$candidate"
      seen+="$candidate "
    fi
  done
}

all_cards() {
  local device
  shopt -s nullglob
  for device in /dev/dri/card[0-9]*; do
    printf '%s\n' "$device"
  done
}

deadline=$((SECONDS + WAIT_SECONDS))
attempt=0
final_result=75
profile_seconds=$((SECONDS_TO_RUN / 5))
(( profile_seconds < 10 )) && profile_seconds=10
profiles=(1080p60 720p60 1080p50 720p50 preferred)
pre_modeset_captured=0

while (( SECONDS < deadline )); do
  attempt=$((attempt + 1))
  candidates=()
  if [[ "$CARD" != auto ]]; then
    candidates+=("$CARD")
    if (( pre_modeset_captured == 0 )); then
      "$COLLECT" "$RUN_DIR/02-before-modeset-attempt-$attempt" || true
      pre_modeset_captured=1
    fi
  else
    mapfile -t candidates < <(connected_cards)
    if (( ${#candidates[@]} > 0 && pre_modeset_captured == 0 )); then
      "$COLLECT" "$RUN_DIR/02-before-modeset-attempt-$attempt" || true
      pre_modeset_captured=1
    fi
    if (( ${#candidates[@]} == 0 )); then
      mapfile -t candidates < <(all_cards)
    fi
  fi

  echo "attempt=$attempt timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ) cards=${candidates[*]:-none}"
  for candidate in "${candidates[@]}"; do
    echo "trying_card=$candidate"
    card_success=0
    for profile in "${profiles[@]}"; do
      echo "trying_profile=$profile duration_seconds=$profile_seconds"
      "$BIN" --card "$candidate" --profile "$profile" \
        --seconds "$profile_seconds" --edid-output "$EDID"
      profile_result=$?
      echo "profile_result=$profile_result card=$candidate profile=$profile"
      (( profile_result == 0 )) && card_success=1
      if (( profile_result == 75 )); then
        break
      fi
    done
    if (( card_success == 1 )); then
      final_result=0
      break 2
    fi
  done
  sleep 3
done

"$COLLECT" "$RUN_DIR/03-after-test" || true
echo "result=$final_result"
echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "$final_result" >"$RUN_DIR/result.txt"
exit "$final_result"
