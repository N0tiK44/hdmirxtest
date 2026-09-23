#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
COMMAND=${1:-help}
CARD=${CARD:-/dev/dri/card0}
SECONDS_TO_RUN=${SECONDS_TO_RUN:-120}
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

usage() {
  cat <<'EOF'
HDMIRXTEST V1.2 — HDMI-TX ONLY TEST

  bash TxTest.sh install   Build and enable the automatic boot test
  bash TxTest.sh run       Run colour bars until Ctrl+C
  bash TxTest.sh status    Show the most recent offline result
  bash TxTest.sh results   Create ~/hdmirxtest-tx-latest.tar.gz
  bash TxTest.sh enable    Enable the test for the next boot
  bash TxTest.sh disable   Stop and disable the boot test

This test needs only Orange Pi HDMI-TX -> display HDMI input.
Leave HDMI-RX empty. It automatically discovers connector, CRTC, primary plane
and a safe mode from the connected display on every run.
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
      hdmirxtest-edid.service 2>/dev/null || true
    as_root install -d -m 0755 /usr/local/libexec "$STATE_DIR"
    as_root install -m 0755 "$ROOT/hdmirxtest-tx-selftest" \
      /usr/local/bin/hdmirxtest-tx-selftest
    as_root install -m 0755 "$ROOT/scripts/tx-selftest-service.sh" \
      /usr/local/libexec/hdmirxtest-tx-selftest-service
    as_root install -m 0644 "$ROOT/packaging/systemd/$SERVICE" \
      "/etc/systemd/system/$SERVICE"
    as_root mkdir -p /etc/default
    printf 'CARD=%q\nSECONDS_TO_RUN=%q\n' "$CARD" "$SECONDS_TO_RUN" | \
      as_root tee /etc/default/hdmirxtest-tx-selftest >/dev/null
    as_root systemctl daemon-reload
    as_root systemctl enable "$SERVICE"
    as_root systemctl start --no-block "$SERVICE"
    cat <<'EOF'

TX TEST INSTALLED.
The animated colour bars should appear shortly and run for two minutes.
For the TV test: power off, connect only HDMI-TX to the TV, then power on.
No HDMI-RX, network or keyboard is required after installation.
EOF
    ;;

  run)
    make -C "$ROOT" hdmirxtest-tx-selftest
    as_root systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    echo "Colour bars are starting. Press Ctrl+C to stop and restore the console."
    as_root "$ROOT/hdmirxtest-tx-selftest" --card "$CARD" --seconds 0 \
      --edid-output /tmp/hdmirxtest-tx-edid.bin
    ;;

  status)
    as_root systemctl --no-pager --full status "$SERVICE" || true
    echo
    as_root tail -n 120 "$STATE_DIR/tx-selftest.log" 2>/dev/null || \
      echo "No TX test log exists yet."
    ;;

  results)
    destination="$HOME/hdmirxtest-tx-latest.tar.gz"
    temporary=$(mktemp -d)
    trap 'rm -rf -- "$temporary"' EXIT
    as_root cp -a "$STATE_DIR/tx-selftest.log" "$temporary/" 2>/dev/null || true
    as_root cp -a "$STATE_DIR/tx-selftest-edid.bin" "$temporary/" 2>/dev/null || true
    as_root sh -c 'for p in /sys/class/drm/card*-HDMI-*/status /sys/class/drm/card*-HDMI-*/modes; do [ -r "$p" ] && { echo "--- $p"; cat "$p"; }; done' \
      >"$temporary/drm-connectors.txt" 2>&1 || true
    as_root chown -R "$(id -u):$(id -g)" "$temporary"
    tar -czf "$destination" -C "$temporary" .
    echo "Result archive: $destination"
    ;;

  enable)
    as_root systemctl enable "$SERVICE"
    echo "TX self-test enabled for the next boot."
    ;;

  disable)
    as_root systemctl disable --now "$SERVICE"
    echo "TX self-test stopped and disabled."
    ;;

  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
