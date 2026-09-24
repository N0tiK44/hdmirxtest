#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
COMMAND=${1:-help}
STATE_DIR=/var/lib/hdmirxtest/tv-diag
ARM_FILE="$STATE_DIR/armed"
SYSTEMD_SERVICE=hdmirxtest-tv-diag.service
OPENRC_SERVICE=hdmirxtest-tv-diag

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

enable_service() {
  case "$(init_kind)" in
    systemd)
      as_root systemctl daemon-reload
      as_root systemctl enable "$SYSTEMD_SERVICE" >/dev/null
      ;;
    openrc)
      as_root rc-update add "$OPENRC_SERVICE" default >/dev/null 2>&1 || true
      ;;
    *) echo "Neither systemd nor OpenRC was detected." >&2; return 1 ;;
  esac
}

service_status() {
  case "$(init_kind)" in
    systemd) as_root systemctl --no-pager --full status "$SYSTEMD_SERVICE" || true ;;
    openrc) as_root rc-service "$OPENRC_SERVICE" status || true ;;
    *) echo "No supported init system detected." ;;
  esac
}

usage() {
  cat <<'USAGE'
HDMIRXTEST V1.5 — PASSIVE TV HDMI DIAGNOSTIC ADD-ON

This does NOT modeset the display and does NOT use HDMI-RX. It only records what
stock Linux/DRM sees when the Pi is connected to a TV.

  bash TvDiag.sh install   Install the passive diagnostic boot service
  bash TvDiag.sh arm       Arm ONE passive diagnostic for the next boot
  bash TvDiag.sh field     Arm it, sync disks, and power off now
  bash TvDiag.sh disarm    Cancel the armed passive diagnostic
  bash TvDiag.sh status    Show service/arm state and latest run summary
  bash TvDiag.sh history   List saved passive TV diagnostic runs
  bash TvDiag.sh results   Create ~/hdmirxtest-tv-diag-latest.tar.gz

Recommended living-room workflow:
  1. bash TvDiag.sh install
  2. bash TvDiag.sh field
  3. Move Pi to TV, connect HDMI-A-1, power on, wait for automatic shutdown.
  4. Return to office, boot normally, run: bash TvDiag.sh results
USAGE
}

if (( EUID == 0 )); then
  echo "Run TvDiag.sh as your normal user. It uses sudo/doas only when needed." >&2
  exit 2
fi

case "$COMMAND" in
  install)
    as_root install -d -m 0755 /usr/local/libexec "$STATE_DIR/history" /run/hdmirxtest
    as_root install -m 0755 "$ROOT/scripts/tv-diag-service.sh" \
      /usr/local/libexec/hdmirxtest-tv-diag-service

    case "$(init_kind)" in
      systemd)
        as_root install -m 0644 "$ROOT/packaging/systemd/$SYSTEMD_SERVICE" \
          "/etc/systemd/system/$SYSTEMD_SERVICE"
        ;;
      openrc)
        as_root install -m 0755 "$ROOT/packaging/openrc/$OPENRC_SERVICE" \
          "/etc/init.d/$OPENRC_SERVICE"
        ;;
      *) echo "No supported init system found." >&2; exit 1 ;;
    esac

    # Helpful but optional. The collector works even if the package is absent.
    if ! command -v edid-decode >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1; then
        echo "Installing optional edid-decode helper..."
        as_root apt-get update || true
        as_root apt-get install -y edid-decode || true
      elif command -v apk >/dev/null 2>&1; then
        echo "Attempting to install optional edid-decode helper..."
        as_root apk add edid-decode || true
      fi
    fi

    enable_service
    cat <<'MSG'

Passive TV diagnostic installed.
It remains IDLE on normal boots unless explicitly armed.
It does not alter HDMI modes, does not open HDMI-RX, and does not run the V1.5
TX mode matrix.

When ready to move the Pi to the TV:
    bash TvDiag.sh field
MSG
    ;;

  arm)
    as_root install -d -m 0755 "$STATE_DIR"
    # Prevent the active V1.5 TX mode-matrix field test from running at the same
    # time if it had previously been armed.
    as_root rm -f /var/lib/hdmirxtest/field-test-armed
    printf 'armed_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | \
      as_root tee "$ARM_FILE" >/dev/null
    enable_service
    echo "ONE passive TV diagnostic is armed for the next boot."
    ;;

  field)
    as_root install -d -m 0755 "$STATE_DIR"
    as_root rm -f /var/lib/hdmirxtest/field-test-armed
    printf 'armed_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | \
      as_root tee "$ARM_FILE" >/dev/null
    enable_service
    echo "Passive TV diagnostic armed. Syncing disks and powering off now..."
    sync
    sleep 1
    case "$(init_kind)" in
      systemd) as_root systemctl poweroff ;;
      openrc) as_root poweroff ;;
      *) as_root poweroff ;;
    esac
    ;;

  disarm)
    as_root rm -f "$ARM_FILE"
    echo "Passive TV diagnostic disarmed."
    ;;

  status)
    service_status
    echo
    if as_root test -e "$ARM_FILE"; then
      echo "TV DIAGNOSTIC: ARMED for next boot"
      as_root cat "$ARM_FILE" || true
    else
      echo "TV DIAGNOSTIC: not armed"
    fi
    echo
    echo "--- latest summary ---"
    as_root sh -c 'latest=/var/lib/hdmirxtest/tv-diag/latest/summary.txt; if [ -r "$latest" ]; then cat "$latest"; else echo "No passive TV diagnostic has run yet."; fi'
    ;;

  history)
    as_root find "$STATE_DIR/history" -mindepth 1 -maxdepth 1 -type d \
      -printf '%f\n' 2>/dev/null | sort || true
    ;;

  results)
    destination="$HOME/hdmirxtest-tv-diag-latest.tar.gz"
    staging=$(mktemp -d)
    trap 'rm -rf -- "$staging"' EXIT
    as_root mkdir -p "$staging/history"
    as_root cp -a "$STATE_DIR/history/." "$staging/history/" 2>/dev/null || true
    service_status >"$staging/service-status.txt" 2>&1 || true
    as_root cp "$STATE_DIR/latest-tv-diag.tar.gz" "$staging/on-device-latest-tv-diag.tar.gz" 2>/dev/null || true
    as_root chown -R "$(id -u):$(id -g)" "$staging"
    tar -czf "$destination" -C "$staging" .
    echo "Result archive: $destination"
    ;;

  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
