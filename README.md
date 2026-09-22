# hdmirxtest — RK3588 HDMI ultra-low-latency passthrough — V1.1.1

V1.1.1 preserves the V1.0 zero-copy Orange Pi 5 Plus datapath and adds a safer 1080p240 feasibility workflow plus one-command lab automation.

The critical path is still:

`RK3588 HDMI-RX -> V4L2 NV24 -> DMA-BUF -> DRM PRIME -> native NV24 framebuffer -> atomic KMS plane`

There is no GStreamer pipeline, CPU colour conversion, framebuffer copy, or deliberate userspace frame queue.

## What changed in V1.1.1

- the proven V1.0 ownership/fence path is retained
- high-refresh EDID mode matching can accept fractional rates such as 239.760 Hz without relaxing the strict 59.940-vs-60.000 rule
- `prepare240` can forward the connected downstream monitor EDID (normally the Zowie) to HDMI-RX
- `probe240` refuses to run the full 240-Hz test unless HDMI-RX is actually reporting 1920×1080 at roughly 240 fps
- every test gathers a larger EDID/V4L2/DRM/kernel debug bundle
- the SBC update workflow automatically backs up local changes instead of stopping on a dirty worktree
- the Windows helper can remotely update/build/test the SBC and SCP the result archive back in one command

V1.1.1 does **not** claim that RK3588 HDMI-RX has already been proven at 1080p240. That is the experiment this build is designed to answer.

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

The test creates:

```text
~/hdmirxtest-latest.tar.gz
```

## Routine commands on the Pi

Known-good baseline:

```bash
bash scripts/pi-cycle.sh baseline
```

Prepare EDID for 240-Hz negotiation:

```bash
bash scripts/pi-cycle.sh prepare240
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
- `RUN-PREPARE-240.cmd`
- `RUN-PROBE-240.cmd`
- `RUN-240-TEST.cmd`

The helper SSHes into the Pi, clones the repo there if needed, installs missing dependencies on first use, syncs it, builds/tests it, packages results, then SCPs `hdmirxtest-latest.tar.gz` into Windows Downloads.

Default lab values are `visionseek@192.168.20.35`; override them with `-PiUser` and `-PiHost` if needed.

## Why the 240-Hz experiment matters

A 59.94-Hz refresh is about 16.68 ms. A 240-Hz refresh is about 4.17 ms. The current project measurements show that the dominant remaining delay is around one display refresh rather than userspace execution. If the RK3588 can sustain the same architecture at 1080p240, the same one-refresh boundary should become roughly four times smaller before deeper VOP2 work.

## 240-Hz EDID strategy

`scripts/prepare-240.sh` first backs up the current HDMI-RX EDID, then prefers forwarding the real EDID of the connected downstream monitor into HDMI-RX. With the Zowie connected to Pi HDMI-TX, Windows can therefore see the Zowie's actual advertised modes.

If direct forwarding fails, the script falls back to the standard `v4l2-ctl` HDMI 2.0 / 600-MHz EDID.

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
