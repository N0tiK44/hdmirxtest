# Operations and repository workflow — V1.1

The preferred workflow treats the SBC checkout as a deployment target, not a place to hand-edit source.

## First clone on the Orange Pi

```bash
mkdir -p ~/src
cd ~/src
git clone YOUR_NEW_REPOSITORY_URL rk3588-hdmi-lowlatency
cd rk3588-hdmi-lowlatency
bash scripts/install-deps.sh
bash scripts/pi-cycle.sh baseline
```

## Routine board command

```bash
cd ~/src/rk3588-hdmi-lowlatency
bash scripts/pi-cycle.sh baseline
```

`pi-cycle.sh` replaces the older fragile update workflow. If the SBC has uncommitted changes, it stashes them automatically before syncing. If its committed history diverged from GitHub, it preserves the old HEAD on a `backup/pi-before-sync-*` branch before resetting the working branch to `origin/main`.

This means routine test deployment no longer stops at `Refusing to overwrite local repository changes`.

## Preferred Windows-controlled workflow

Clone the repo once on Windows, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\host-cycle.ps1 -Mode baseline
```

The helper remotely updates/builds/tests the Pi and then downloads `~/hdmirx-latest.tar.gz` to Windows Downloads. The root-level `RUN-*.cmd` wrappers provide the same flow by double-click.

Available modes are `baseline`, `prepare240`, `probe240`, and `240`.

## Debug bundle

Every cycle attempts to preserve:

- timing CSV and analyzer report when applicable
- V4L2 HDMI-RX timing and capabilities
- current receiver EDID
- downstream display EDID
- DRM connector/plane data and debugfs state
- HDMI/VOP2/fence-related kernel messages
- Git revision and status

Even a failed 240-Hz gate should produce an archive worth sending back for review.

## EDID restore

```bash
sudo bash scripts/restore-rx-edid.sh
```

This restores the newest receiver EDID backup from `/var/tmp/hdmirx-edid-backups`.
