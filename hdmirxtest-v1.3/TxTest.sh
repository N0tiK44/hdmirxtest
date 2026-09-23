#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
COMMAND=${1:-help}
CARD=${CARD:-auto}
SECONDS_TO_RUN=${SECONDS_TO_RUN:-120}
WAIT_SECONDS=${WAIT_SECONDS:-90}
STATE_DIR=/var/lib/hdmirxtest
SERVICE=hdmirxtest-tx-selftest.service

as_root() {
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else
    echo "sudo or doas is required." >&2
    return 127
  fi
}

latest_log() {
  as_root sh -c 'latest=/var/lib/hdmirxtest/tx-latest/tx-selftest.log; if [ -r "$latest" ]; then sed -n "1,260p" "$latest"; else echo "No TX history exists yet."; fi'
}

usage() {
  cat <<'EOF'
HDMIRXTEST V1.3 — HDMI-TX ONLY TEST

  bash TxTest.sh install   Install and start the automatic offline test
  bash TxTest.sh run       Run manually until Ctrl+C
  bash TxTest.sh status    Show the latest permanent boot record
  bash TxTest.sh history   List every saved display-test boot
  bash TxTest.sh results   Create ~/hdmirxtest-tx-history-latest.tar.gz
  bash TxTest.sh enable    Enable the test for the next boot
  bash TxTest.sh disable   Stop and disable the boot test

Every boot has a separate directory under /var/lib/hdmirxtest/tx-history.
Returning to the Zowie cannot overwrite a previous LG or Samsung record.
EOF
}

if (( EUID == 0 )); then
  echo "Run TxTest.sh as your normal user. It uses sudo only when needed." >&2
  exit 2
fi

case "$COMMAND" in
  install)
    bash "$ROOT/scripts/install-deps.sh"
    make -C "$ROOT" hdmirxtest-tx-selftest
    as_root systemctl disable --now hdmirxtest-passthrough.service \
      hdmirxtest-edid.service "$SERVICE" 2>/dev/null || true
    as_root install -d -m 0755 /usr/local/libexec "$STATE_DIR/tx-history"
    as_root install -m 0755 "$ROOT/hdmirxtest-tx-selftest" \
      /usr/local/bin/hdmirxtest-tx-selftest
    as_root install -m 0755 "$ROOT/scripts/collect-tx-state.sh" \
      /usr/local/libexec/hdmirxtest-collect-tx-state
    as_root install -m 0755 "$ROOT/scripts/tx-selftest-service.sh" \
      /usr/local/libexec/hdmirxtest-tx-selftest-service
    as_root install -m 0644 "$ROOT/packaging/systemd/$SERVICE" \
      "/etc/systemd/system/$SERVICE"
    printf 'CARD=%q\nSECONDS_TO_RUN=%q\nWAIT_SECONDS=%q\n' \
      "$CARD" "$SECONDS_TO_RUN" "$WAIT_SECONDS" | \
      as_root tee /etc/default/hdmirxtest-tx-selftest >/dev/null
    as_root systemctl daemon-reload
    as_root systemctl enable "$SERVICE"
    as_root systemctl start --no-block "$SERVICE"
    cat <<'EOF'

V1.3 TX TEST INSTALLED.
After the Zowie colour-bar test finishes, power off and test the TV with only
HDMI-TX connected. Every boot is now preserved permanently.
EOF
    ;;

  run)
    make -C "$ROOT" hdmirxtest-tx-selftest
    as_root systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    selected_card=$CARD
    if [[ "$selected_card" == auto ]]; then
      selected_card=$(for status in /sys/class/drm/card*-HDMI-*/status; do
        [[ -r "$status" && "$(cat "$status")" == connected ]] || continue
        connector=$(basename "$(dirname "$status")")
        printf '/dev/dri/%s\n' "${connector%%-*}"
        break
      done)
      selected_card=${selected_card:-/dev/dri/card0}
    fi
    echo "Colour bars are starting on $selected_card. Press Ctrl+C to stop."
    as_root "$ROOT/hdmirxtest-tx-selftest" --card "$selected_card" --seconds 0 \
      --edid-output /tmp/hdmirxtest-tx-edid.bin
    ;;

  status)
    as_root systemctl --no-pager --full status "$SERVICE" || true
    echo
    latest_log
    ;;

  history)
    as_root find "$STATE_DIR/tx-history" -mindepth 1 -maxdepth 1 -type d \
      -printf '%f\n' 2>/dev/null | sort || true
    ;;

  results)
    destination="$HOME/hdmirxtest-tx-history-latest.tar.gz"
    staging=$(mktemp -d)
    trap 'rm -rf -- "$staging"' EXIT
    as_root mkdir -p "$staging/history" "$staging/current-state"
    as_root cp -a "$STATE_DIR/tx-history/." "$staging/history/" 2>/dev/null || true
    if [[ -x /usr/local/libexec/hdmirxtest-collect-tx-state ]]; then
      as_root /usr/local/libexec/hdmirxtest-collect-tx-state \
        "$staging/current-state" || true
    fi
    as_root systemctl --no-pager --full status "$SERVICE" \
      >"$staging/service-status.txt" 2>&1 || true
    as_root chown -R "$(id -u):$(id -g)" "$staging"
    tar -czf "$destination" -C "$staging" .
    echo "Result archive: $destination"
    ;;

  enable)
    as_root systemctl enable "$SERVICE"
    echo "TX self-test enabled for the next boot."
    ;;

  disable)
    as_root systemctl disable --now "$SERVICE"
    echo "TX self-test stopped and disabled. Existing history was preserved."
    ;;

  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
