# Operations — hdmirxtest V1.2.3

Repository: `https://github.com/N0tiK44/hdmirxtest`

## First clone on the Orange Pi

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/N0tiK44/hdmirxtest.git
cd hdmirxtest
bash scripts/install-deps.sh
```

## Safely build the connected-monitor bridge EDID

First physically unplug the Windows/GPU cable from HDMI-RX. Leave the target
monitor connected to HDMI-TX.

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh setup
```

Reconnect the Windows HDMI source once. The clone is capped at 1920x1080 240
Hz and advertises RGB 8-bit SDR.

## Persistent Ubuntu/systemd path

```bash
bash scripts/pi-cycle.sh service-start
bash scripts/pi-cycle.sh service-status
```

The service is enabled by `setup`, survives SSH logout, automatically starts
at boot and waits/retries while HDMI-RX has no source. Stop it with:

```bash
bash scripts/pi-cycle.sh service-stop
```

## Continuous foreground path

```bash
bash scripts/pi-cycle.sh 240
```

The live path skips network sync, clean rebuild, the separate probe, and the
pre-run debug snapshot. It incrementally builds only when required, reads the
live HDMI-RX timing internally, and matches the HDMI-TX mode automatically. It
runs until Ctrl-C. Prefix it with `DURATION=120` only for a timed test.

## Explicit repository update

```bash
bash scripts/pi-cycle.sh sync
```

Use `SYNC=1 bash scripts/pi-cycle.sh 240` to update and run in one command.

## Debug only

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh debug
```

Only `sync` or `SYNC=1` contacts Git. Every operational mode still packages a
mode-specific result, and a compatibility copy remains at
`~/hdmirxtest-latest.tar.gz`.

## Windows-controlled workflow

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\host-cycle.ps1 -Mode baseline
```

Or double-click `RUN-BASELINE.cmd`. Use `RUN-DEBUG.cmd` for debug-only collection and `FETCH-RESULTS.cmd` to copy an existing result archive.

Manual PowerShell copy:

```powershell
scp visionseek@192.168.20.35:~/hdmirxtest-baseline-latest.tar.gz "$env:USERPROFILE\Downloads\hdmirxtest-baseline-latest.tar.gz"
```

## 240 Hz

After the baseline passes, use `RUN-240-WIZARD.cmd` in Windows extended-display mode. Manual modes are `prepare240`, `probe240`, and `240`. Use `restoreedid` or `RUN-RESTORE-EDID.cmd` to roll back.

## Safe EDID recovery

Physically unplug Windows from HDMI-RX first.

```bash
cd ~/src/hdmirxtest
sudo bash scripts/restore-rx-edid.sh
```

This loads an audited RGB 8-bit 1080p60 recovery profile. It intentionally
does not restore `rx-edid-original.bin`, `RK-UHD`, or any historical backup.

On systems using `doas`, replace `sudo` with `doas`.
