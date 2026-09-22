# hdmirxtest — RK3588 HDMI ultra-low-latency passthrough — V1.1.2

V1.1.2 preserves the V1.0 zero-copy Orange Pi 5 Plus datapath and adds a verified, reversible 1080p240 bridge EDID for the Orange Pi HDMI-RX.

The critical path is still:

`RK3588 HDMI-RX -> V4L2 NV24 -> DMA-BUF -> DRM PRIME -> native NV24 framebuffer -> atomic KMS plane`

There is no GStreamer pipeline, CPU colour conversion, framebuffer copy, or deliberate userspace frame queue.

## What changed in V1.1.2

- the proven V1.0 ownership/fence path is retained
- high-refresh EDID mode matching can accept fractional rates such as 239.760 Hz without relaxing the strict 59.940-vs-60.000 rule
- `prepare240` loads `edid/rk1080p240.bin`, derived from the captured Zowie XL2546X EDID
- 1920×1080 at 239.964 Hz / 571 MHz is the preferred timing; 1080p60 is the first fallback
- the EDID is validated before use and read back byte-for-byte after programming
- `restoreedid` and `RUN-RESTORE-EDID.cmd` safely restore the pre-experiment RX EDID
- `probe240` refuses to run the full 240-Hz test unless HDMI-RX is actually reporting 1920×1080 at roughly 240 fps
- sysfs EDIDs are copied by reading their bytes instead of trusting their reported pseudo-file size
- each test mode keeps its own result archive so baseline and debug no longer overwrite each other
- every test gathers a larger EDID/V4L2/DRM/kernel debug bundle
- the SBC update workflow automatically backs up local changes instead of stopping on a dirty worktree
- the Windows helper can remotely update/build/test the SBC and SCP the result archive back in one command

V1.1.2 does **not** claim that RK3588 HDMI-RX has already been proven at 1080p240. The EDID negotiation problem is now addressed; the remaining experiment is whether the RX controller, DMA path, and driver can lock and sustain the timing.

## Known-good baseline configuration

- Orange Pi 5 Plus / RK3588
- vendor Rockchip 6.1-class HDMI-RX stack used by the V1.0 project
- HDMI-RX `/dev/video0`
- DRM `/dev/dri/card0`
- connector `217`, plane `114` on the verified installation
- NV24 1920×1080
- four V4L2 capture buffers
- Rockchip HDMI-RX `low_latency=1`
- acquire sync-file from V4L2 `timecode.userbits`
- plane `IN_FENCE_FD`; CRTC `OUT_FENCE_PTR`

DRM object IDs are installation-specific. The binary supports automatic discovery with ID `0`, but the scripts keep the last verified IDs as defaults.

## Easiest start

On the Orange Pi, as your normal user:

```bash
mkdir -p ~/src && cd ~/src
git clone https://github.com/N0tiK44/hdmirxtest.git
cd hdmirxtest
bash scripts/install-deps.sh
bash scripts/pi-cycle.sh baseline
```

For later runs, you only need:

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh baseline
```

For debug collection without running passthrough:

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh debug
```

The baseline test creates:

```text
~/hdmirxtest-baseline-latest.tar.gz
```

Each mode uses its own filename. A compatibility copy is also kept at `~/hdmirxtest-latest.tar.gz`.

## Routine commands on the Pi

Known-good baseline:

```bash
bash scripts/pi-cycle.sh baseline
```

Prepare EDID for 240-Hz negotiation:

```bash
bash scripts/pi-cycle.sh prepare240
```

Restore the original RX EDID:

```bash
bash scripts/pi-cycle.sh restoreedid
```

Probe only:

```bash
bash scripts/pi-cycle.sh probe240
```

Full 240-Hz diagnostic, but only after the input gate passes:

```bash
bash scripts/pi-cycle.sh 240
```

The old command remains compatible:

```bash
bash scripts/pi-update-and-diagnose.sh
```

It now delegates to `pi-cycle.sh baseline`.

## Preferred Windows-controlled workflow

Clone the repo once on the Windows host, then use:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\host-cycle.ps1 -Mode baseline
```

or double-click one of:

- `RUN-BASELINE.cmd`
- `RUN-DEBUG.cmd` — collect diagnostics without starting passthrough
- `FETCH-RESULTS.cmd` — copy an existing archive from the Pi
- `RUN-240-WIZARD.cmd` — recommended 240-Hz workflow
- `RUN-RESTORE-EDID.cmd` — emergency rollback to the original RK-UHD EDID
- `RUN-PREPARE-240.cmd`
- `RUN-PROBE-240.cmd`
- `RUN-240-TEST.cmd`

The helper SSHes into the Pi, clones the repo there if needed, installs missing dependencies on first use, syncs it, builds/tests it, packages results, then SCPs a mode-specific archive such as `hdmirxtest-probe240-latest.tar.gz` into Windows Downloads.

Default lab values are `visionseek@192.168.20.35`; override them with `-PiUser` and `-PiHost` if needed.

## Why the 240-Hz experiment matters

A 59.94-Hz refresh is about 16.68 ms. A 240-Hz refresh is about 4.17 ms. The current project measurements show that the dominant remaining delay is around one display refresh rather than userspace execution. If the RK3588 can sustain the same architecture at 1080p240, the same one-refresh boundary should become roughly four times smaller before deeper VOP2 work.

## 240-Hz EDID strategy

Windows duplicate mode merges/intersects display behavior and can misleadingly expose 240 Hz from the MSI. In extended mode the stock `RK-UHD` EDID exposes only 60 Hz. V1.1.2 fixes the receiver side directly.

`scripts/prepare-240.sh` backs up the stock receiver EDID and loads `edid/rk1080p240.bin`. The profile is based on the exact 256-byte Zowie XL2546X EDID captured by DRM, including its HDMI Forum 600-MHz capability block. The monitor's own 571-MHz 1080p239.964 timing is made preferred, with 1080p60 retained as a safe fallback.

The script refuses to proceed without a backup, validates the EDID checksums/timings, and verifies exact read-back after programming. It does not fall back to the generic `hdmi-4k-600mhz` preset because that preset does not advertise the required 1080p240 detailed timing.

Do not select a source refresh above 240 Hz even if the downstream EDID advertises one.

## Safety rules

- four buffers remain the stable minimum from V1.0 testing
- never requeue the currently displayed capture buffer
- only the previously displayed buffer is returned after the next KMS completion
- do not add GStreamer, CPU conversion, framebuffer copies, or a deliberate extra queue
- do not reintroduce the retired frame-dropping experiment
- the 240-Hz path is experimental until the debug data proves each stage

## Documentation

- [Simple tutorial](TUTORIAL.txt)
- [Start here / detailed notes](START-HERE.txt)
- [Architecture](docs/ARCHITECTURE.md)
- [Operations](docs/OPERATIONS.md)
- [1080p240 experiment](docs/240HZ_EXPERIMENT.md)
- [Research findings](docs/RESEARCH_FINDINGS.md)
- [Roadmap](docs/ROADMAP.md)
