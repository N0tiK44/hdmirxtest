# V1.2.4 operations

Normal operation is intentionally foreground-only:

```bash
bash PiCycle.sh
```

Press `Ctrl+C` to stop and return to the terminal. The video process is not a
systemd service, does not survive logout, and does not automatically occupy the
console after boot. Only the verified bridge EDID loader is enabled at boot.

To configure a new HDMI-TX monitor, stop video, physically unplug the Windows
HDMI-RX cable, and run:

```bash
bash PiCycle.sh setup
```

Reconnect Windows only after exact EDID read-back succeeds.

Diagnostics without video:

```bash
bash PiCycle.sh debug
```
