#!/usr/bin/env bash
set -euo pipefail

as_root() {
  if (( EUID == 0 )); then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v doas >/dev/null 2>&1; then
    doas "$@"
  else
    echo "Need root privileges (sudo/doas not found)." >&2
    exit 2
  fi
}

if command -v apt-get >/dev/null 2>&1; then
  as_root apt-get update
  as_root apt-get install -y build-essential pkg-config libdrm-dev python3 git bash v4l-utils openssh-client
  as_root apt-get install -y libdrm-tests edid-decode || true
elif command -v apk >/dev/null 2>&1; then
  as_root apk add bash build-base pkgconf libdrm-dev python3 git v4l-utils openssh-client
  as_root apk add libdrm-tests edid-decode || true
else
  echo "Unsupported package manager. Install: C compiler/build tools, pkg-config, libdrm development headers, Python 3, Git, bash, v4l-utils and OpenSSH client." >&2
  exit 2
fi

echo "Dependencies installed."
