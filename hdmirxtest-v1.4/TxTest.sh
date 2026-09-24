#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
COMMAND=${1:-help}
CARD=${CARD:-auto}
CONNECTOR_NAME=${CONNECTOR_NAME:-auto}
SECONDS_TO_RUN=${SECONDS_TO_RUN:-165}
WAIT_SECONDS=${WAIT_SECONDS:-90}
STATE_DIR=/var/lib/hdmirxtest
SYSTEMD_SERVICE=hdmirxtest-tx-selftest.service
OPENRC_SERVICE=hdmirxtest-tx-selftest

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

init_kind() {
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    echo systemd
  elif command -v rc-service >/dev/null 2>&1; then
    echo openrc
  else
    echo none
  fi
}

stop_service() {
  case "$(init_kind)" in
    systemd) as_root systemctl stop "$SYSTEMD_SERVICE" >/dev/null 2>&1 || true ;;
    openrc) as_root rc-service "$OPENRC_SERVICE" stop >/dev/null 2>&1 || true ;;
  esac
}

disable_service() {
  case "$(init_kind)" in
    systemd) as_root systemctl disable --now "$SYSTEMD_SERVICE" >/dev/null 2>&1 || true ;;
    openrc)
      as_root rc-service "$OPENRC_SERVICE" stop >/dev/null 2>&1 || true
      as_root rc-update del "$OPENRC_SERVICE" default >/dev/null 2>&1 || true
      ;;
  esac
}

enable_service() {
  case "$(init_kind)" in
    systemd)
      as_root systemctl daemon-reload
      as_root systemctl enable "$SYSTEMD_SERVICE"
      ;;
    openrc)
      as_root rc-update add "$OPENRC_SERVICE" default
      ;;
    none)
      echo "Neither systemd nor OpenRC was detected." >&2
      return 1
      ;;
  esac
}

start_service() {
  case "$(init_kind)" in
    systemd) as_root systemctl start --no-block "$SYSTEMD_SERVICE" ;;
    openrc) as_root rc-service "$OPENRC_SERVICE" start ;;
    none) return 1 ;;
  esac
}

service_status() {
  case "$(init_kind)" in
    systemd) as_root systemctl --no-pager --full status "$SYSTEMD_SERVICE" || true ;;
    openrc) as_root rc-service "$OPENRC_SERVICE" status || true ;;
    none) echo "No supported init system detected." ;;
  esac
}

latest_log() {
  as_root sh -c 'latest=/var/lib/hdmirxtest/tx-latest/tx-selftest.log; if [ -r "$latest" ]; then sed -n "1,320p" "$latest"; else echo "No TX history exists yet."; fi'
}

find_first_target() {
  local status base card connector
  shopt -s nullglob
  for status in /sys/class/drm/card*-HDMI-*/status; do
    [[ -r "$status" && "$(cat "$status")" == connected ]] || continue
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
    printf '/dev/dri/%s\t%s\n' "$card" "$connector"
    return 0
  done
  return 1
}

usage() {
  cat <<'USAGE'
HDMIRXTEST V1.4 — UNIVERSAL HDMI-TX FOUNDATION

  bash TxTest.sh install   Install/start the offline TX probe at boot
  bash TxTest.sh run       Hold a safe auto-selected TX mode until Ctrl+C
  bash TxTest.sh status    Show service state, heartbeat and latest boot log
  bash TxTest.sh history   List every retained display-test boot
  bash TxTest.sh results   Create ~/hdmirxtest-tx-history-latest.tar.gz
  bash TxTest.sh enable    Enable the boot probe
  bash TxTest.sh disable   Stop/disable it without deleting history

Optional environment overrides:
  CARD=/dev/dri/card0
  CONNECTOR_NAME=HDMI-A-1
  SECONDS_TO_RUN=165
  WAIT_SECONDS=90

V1.4 does not touch HDMI-RX. It identifies the connected HDMI output by
capability/name instead of relying on one hard-coded connector number.
USAGE
}

if (( EUID == 0 )); then
  echo "Run TxTest.sh as your normal user. It uses sudo/doas only when needed." >&2
  exit 2
fi

case "$COMMAND" in
  install)
    bash "$ROOT/scripts/install-deps.sh"
    make -C "$ROOT" hdmirxtest-tx-selftest

    # The TX-first milestone is intentionally isolated from all HDMI-RX work.
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
      as_root systemctl disable --now hdmirxtest-passthrough.service \
        hdmirxtest-edid.service "$SYSTEMD_SERVICE" 2>/dev/null || true
    elif command -v rc-service >/dev/null 2>&1; then
      as_root rc-service hdmirxtest-edid stop >/dev/null 2>&1 || true
      as_root rc-update del hdmirxtest-edid default >/dev/null 2>&1 || true
      as_root rc-service "$OPENRC_SERVICE" stop >/dev/null 2>&1 || true
    fi

    as_root install -d -m 0755 /usr/local/libexec "$STATE_DIR/tx-history" /run/hdmirxtest
    as_root install -m 0755 "$ROOT/hdmirxtest-tx-selftest" \
      /usr/local/bin/hdmirxtest-tx-selftest
    as_root install -m 0755 "$ROOT/scripts/collect-tx-state.sh" \
      /usr/local/libexec/hdmirxtest-collect-tx-state
    as_root install -m 0755 "$ROOT/scripts/collect-tx-attempt.sh" \
      /usr/local/libexec/hdmirxtest-collect-tx-attempt
    as_root install -m 0755 "$ROOT/scripts/tx-selftest-service.sh" \
      /usr/local/libexec/hdmirxtest-tx-selftest-service

    case "$(init_kind)" in
      systemd)
        as_root install -m 0644 "$ROOT/packaging/systemd/$SYSTEMD_SERVICE" \
          "/etc/systemd/system/$SYSTEMD_SERVICE"
        printf 'CARD=%q\nCONNECTOR_NAME=%q\nSECONDS_TO_RUN=%q\nWAIT_SECONDS=%q\n' \
          "$CARD" "$CONNECTOR_NAME" "$SECONDS_TO_RUN" "$WAIT_SECONDS" | \
          as_root tee /etc/default/hdmirxtest-tx-selftest >/dev/null
        ;;
      openrc)
        as_root install -m 0755 "$ROOT/packaging/openrc/$OPENRC_SERVICE" \
          "/etc/init.d/$OPENRC_SERVICE"
        printf 'CARD=%q\nCONNECTOR_NAME=%q\nSECONDS_TO_RUN=%q\nWAIT_SECONDS=%q\n' \
          "$CARD" "$CONNECTOR_NAME" "$SECONDS_TO_RUN" "$WAIT_SECONDS" | \
          as_root tee "/etc/conf.d/$OPENRC_SERVICE" >/dev/null
        ;;
      none)
        echo "No supported init system found after installing files." >&2
        exit 1
        ;;
    esac

    enable_service
    start_service
    cat <<'MSG'

V1.4 TX PROBE INSTALLED.
HDMI-RX is still deliberately unused. After the current display test finishes,
power off and test each TV/monitor directly from one HDMI-TX port at a time.
Every boot is stored permanently under /var/lib/hdmirxtest/tx-history.
MSG
    ;;

  run)
    make -C "$ROOT" hdmirxtest-tx-selftest
    stop_service
    if ! target=$(find_first_target); then
      echo "No connected HDMI output was found." >&2
      exit 75
    fi
    selected_card=${target%%$'\t'*}
    selected_connector=${target#*$'\t'}
    echo "Colour bars are starting on $selected_card / $selected_connector. Press Ctrl+C to stop."
    as_root "$ROOT/hdmirxtest-tx-selftest" \
      --card "$selected_card" --connector-name "$selected_connector" \
      --profile auto --seconds 0 --edid-output /tmp/hdmirxtest-tx-edid.bin
    ;;

  status)
    service_status
    echo
    if as_root test -r /run/hdmirxtest/tx-heartbeat; then
      echo "--- TX heartbeat ---"
      as_root cat /run/hdmirxtest/tx-heartbeat
      echo
    fi
    echo "--- latest boot log ---"
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
    service_status >"$staging/service-status.txt" 2>&1 || true
    as_root cp /run/hdmirxtest/tx-heartbeat "$staging/tx-heartbeat.txt" 2>/dev/null || true
    as_root chown -R "$(id -u):$(id -g)" "$staging"
    tar -czf "$destination" -C "$staging" .
    echo "Result archive: $destination"
    ;;

  enable)
    enable_service
    echo "TX self-test enabled for the next boot."
    ;;

  disable)
    disable_service
    echo "TX self-test stopped and disabled. Existing history was preserved."
    ;;

  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
