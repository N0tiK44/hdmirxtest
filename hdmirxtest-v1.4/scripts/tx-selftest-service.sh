#!/usr/bin/env bash
set -uo pipefail

CARD=${CARD:-auto}
CONNECTOR_NAME=${CONNECTOR_NAME:-auto}
SECONDS_TO_RUN=${SECONDS_TO_RUN:-165}
WAIT_SECONDS=${WAIT_SECONDS:-90}
STATE_DIR=/var/lib/hdmirxtest
HISTORY_DIR="$STATE_DIR/tx-history"
RUNTIME_DIR=/run/hdmirxtest
HEARTBEAT="$RUNTIME_DIR/tx-heartbeat"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown)
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
RUN_ID="${STAMP}-${BOOT_ID:0:8}"
RUN_DIR="$HISTORY_DIR/$RUN_ID"
LOG="$RUN_DIR/tx-selftest.log"
EDID_DIR="$RUN_DIR/edid"
BIN=/usr/local/bin/hdmirxtest-tx-selftest
COLLECT=/usr/local/libexec/hdmirxtest-collect-tx-state
COLLECT_ATTEMPT=/usr/local/libexec/hdmirxtest-collect-tx-attempt

mkdir -p "$RUN_DIR" "$EDID_DIR" "$RUNTIME_DIR"
ln -sfn "$RUN_DIR" "$STATE_DIR/tx-latest"
exec > >(tee -a "$LOG") 2>&1

heartbeat() {
  local state=${1:-unknown}
  shift || true
  local tmp="$HEARTBEAT.tmp.$$"
  {
    echo "version=1.4"
    echo "state=$state"
    echo "run_id=$RUN_ID"
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'detail='
    printf '%s ' "$@"
    printf '\n'
  } >"$tmp"
  mv -f "$tmp" "$HEARTBEAT"
}

sanitize() {
  printf '%s' "$1" | tr -cs 'A-Za-z0-9._-' '_'
}

connected_targets() {
  local status base card connector seen=" "
  shopt -s nullglob
  for status in /sys/class/drm/card*-HDMI-*/status; do
    [[ -r "$status" ]] || continue
    [[ "$(cat "$status" 2>/dev/null)" == connected ]] || continue
    base=$(basename "$(dirname "$status")")
    card=${base%%-*}
    connector=${base#*-}
    [[ -e "/dev/dri/$card" ]] || continue
    if [[ "$CARD" != auto && "/dev/dri/$card" != "$CARD" ]]; then
      continue
    fi
    if [[ "$CONNECTOR_NAME" != auto && "$connector" != "$CONNECTOR_NAME" ]]; then
      continue
    fi
    if [[ "$seen" != *" $card/$connector "* ]]; then
      printf '/dev/dri/%s\t%s\n' "$card" "$connector"
      seen+="$card/$connector "
    fi
  done
}

all_cards() {
  local device
  shopt -s nullglob
  for device in /dev/dri/card[0-9]*; do
    [[ -e "$device" ]] || continue
    if [[ "$CARD" == auto || "$device" == "$CARD" ]]; then
      printf '%s\n' "$device"
    fi
  done
}

collect_attempt() {
  local label=$1
  if [[ -x "$COLLECT_ATTEMPT" ]]; then
    "$COLLECT_ATTEMPT" "$RUN_DIR/$label" || true
  fi
}

echo "HDMIRXTEST V1.4 HDMI-TX UNIVERSAL PROBE"
echo "run_id=$RUN_ID"
echo "run_directory=$RUN_DIR"
echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "configured_card=$CARD"
echo "configured_connector=$CONNECTOR_NAME"
echo "HDMI-RX is not opened, queried, configured or used by this test."
echo "Each EDID-advertised safe timing is tested separately; 59.94 and 60.00 are no longer collapsed together."

heartbeat boot "waiting-for-tx"
"$COLLECT" "$RUN_DIR/01-before-wait" || true

# Each profile is deliberately narrow. v1.3 grouped 59.94 and 60.00 into the
# same profile and therefore only tried whichever matching EDID mode appeared
# first. TVs often advertise both. v1.4 proves them independently.
profiles=(
  1080p5994
  1080p6000
  720p5994
  720p6000
  1080p50
  720p50
  576p50
  480p5994
  480p6000
  vga60
  preferred
)

# Keep the complete matrix under the requested test budget, while ensuring
# each visible mode remains up long enough to see a stable picture.
profile_seconds=$((SECONDS_TO_RUN / ${#profiles[@]}))
(( profile_seconds < 12 )) && profile_seconds=12

deadline=$((SECONDS + WAIT_SECONDS))
attempt=0
final_result=75
saw_target=0

while (( SECONDS < deadline )); do
  mapfile -t targets < <(connected_targets)

  if (( ${#targets[@]} == 0 )); then
    heartbeat wait "no-connected-hdmi" "remaining=$((deadline-SECONDS))s"
    sleep 2
    continue
  fi

  saw_target=1
  echo "connected_targets=${#targets[@]} timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  for target in "${targets[@]}"; do
    card=${target%%$'\t'*}
    connector=${target#*$'\t'}
    safe_connector=$(sanitize "$connector")

    echo "target_card=$card target_connector=$connector"
    heartbeat probe "card=$card" "connector=$connector"

    for profile in "${profiles[@]}"; do
      attempt=$((attempt + 1))
      attempt_tag=$(printf 'attempt-%02d-%s-%s' "$attempt" "$safe_connector" "$profile")
      edid="$EDID_DIR/${safe_connector}.bin"

      echo "trying_profile=$profile duration_seconds=$profile_seconds card=$card connector=$connector"
      heartbeat modeset "card=$card" "connector=$connector" "profile=$profile" "attempt=$attempt"
      collect_attempt "${attempt_tag}-before"

      "$BIN" --card "$card" --connector-name "$connector" --profile "$profile" \
        --seconds "$profile_seconds" --edid-output "$edid"
      profile_result=$?

      echo "profile_result=$profile_result card=$card connector=$connector profile=$profile"
      {
        echo "attempt=$attempt"
        echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "card=$card"
        echo "connector=$connector"
        echo "profile=$profile"
        echo "duration_seconds=$profile_seconds"
        echo "result=$profile_result"
      } >"$RUN_DIR/${attempt_tag}.txt"
      collect_attempt "${attempt_tag}-after"

      if (( profile_result == 0 )); then
        final_result=0
      elif (( profile_result == 75 )); then
        # Sink disappeared or connector stopped being usable. Return to the
        # outer wait loop instead of wasting the rest of this mode matrix.
        echo "connector_lost=$connector"
        break
      fi
    done
  done

  # One complete matrix is enough. The permanent boot record survives later
  # Zowie boots, so do not continuously retest and overwrite evidence.
  break
done

if (( saw_target == 0 )); then
  echo "No connected HDMI output with a readable sysfs status was found before timeout."
fi

"$COLLECT" "$RUN_DIR/99-after-test" || true
echo "result=$final_result"
echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "$final_result" >"$RUN_DIR/result.txt"
heartbeat done "result=$final_result" "history=$RUN_DIR"
exit "$final_result"
