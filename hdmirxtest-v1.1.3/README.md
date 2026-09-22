# hdmirxtest — RK3588 HDMI ultra-low-latency passthrough — V1.1.3

V1.1.3 preserves the V1.0 zero-copy Orange Pi 5 Plus datapath, keeps the verified reversible 1080p240 bridge EDID, and adds the native RGB capture path proven necessary by the first real 240-Hz run.

The critical path is still:

`RK3588 HDMI-RX -> native V4L2 NV24 or BGR3 -> DMA-BUF -> DRM PRIME -> matching native DRM framebuffer -> atomic KMS plane`

There is no GStreamer pipeline, CPU colour conversion, framebuffer copy, or deliberate userspace frame queue.

## What changed in V1.1.3

- the real source was proven locked at 1920×1080 239.96 Hz / 570.988 MHz
- Windows RGB888 arrives from HDMI-RX as V4L2 `BGR3`
- `BGR3` now maps directly to DRM `RGB888` (`RG24`) with the same byte layout
- the existing `NV24` path remains unchanged for YUV444 sources
- the probe no longer tries to force an HDMI source format through `VIDIOC_S_FMT`
- both paths remain DMA-BUF zero-copy with no CPU colour conversion or framebuffer copy

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

The RX controller and EDID negotiation are now proven at 1080p240. The next experiment is sustained BGR3 DMA capture and native RGB888 KMS scanout at the matching 239.96-Hz output mode.

## Known-good baseline configuration

- Orange Pi 5 Plus / RK3588
- vendor Rockchip 6.1-class HDMI-RX stack used by the V1.0 project
- HDMI-RX `/dev/video0`
- DRM `/dev/dri/card0`
- connector `217`, plane `114` on the verified installation
- native NV24/YUV444 or BGR3/RGB888 at 1920×1080
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

## Simplest Pi-only 240-Hz workflow

Run `prepare240` on the Orange Pi, physically reconnect the Windows-source HDMI cable so it rereads the EDID, select 240 Hz in the ordinary Windows display GUI, then run `240` on the Orange Pi. No Windows repository, PowerShell controller, or `.cmd` file is required.

## Why the 240-Hz experiment matters

A 59.94-Hz refresh is about 16.68 ms. A 240-Hz refresh is about 4.17 ms. The current project measurements show that the dominant remaining delay is around one display refresh rather than userspace execution. If the RK3588 can sustain the same architecture at 1080p240, the same one-refresh boundary should become roughly four times smaller before deeper VOP2 work.

## 240-Hz EDID strategy

Windows duplicate mode merges/intersects display behavior and can misleadingly expose 240 Hz from the MSI. In extended mode the stock `RK-UHD` EDID exposes only 60 Hz. The custom bridge EDID fixes the receiver side directly.

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
