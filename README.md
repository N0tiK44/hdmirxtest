# hdmirxtest — RK3588 HDMI ultra-low-latency passthrough — V1.2.0

V1.2.0 adds a monitor-cloning bridge EDID, automatic input/output refresh
matching, source-change restart, a hard 1920x1080/240-Hz ceiling, and a fast
live start that does not fetch Git, clean-build, or collect a pre-run dump.

## V1.2.0 quick workflow

Connect the real monitor to Orange Pi HDMI-TX, then run once whenever that
monitor changes:

```bash
bash scripts/pi-cycle.sh preparemonitor
```

Reconnect or disable/re-enable the Windows-to-HDMI-RX source so Windows reads
the new EDID. Start passthrough with:

```bash
bash scripts/pi-cycle.sh 240
```

Despite the legacy command name, `240` is now an alias for the automatic live
path. It reads the current HDMI-RX timing and selects the matching downstream
mode at any advertised rate up to the hard ceiling. If Windows changes timing,
the wrapper tears down safely and rematches automatically.

The fast path performs only an incremental build when source code changed. It
does not contact Git or collect large diagnostics before video. Use this when
an update is wanted:

```bash
bash scripts/pi-cycle.sh sync
```

Or update and then run in one invocation:

```bash
SYNC=1 bash scripts/pi-cycle.sh 240
```

The generated EDID preserves only timings that can be proved to be no greater
than 1920x1080 at 240 Hz, promotes the highest safe detailed timing, advertises
RGB 8-bit SDR, and removes YCbCr/deep-colour/HDR/VRR and unknown timing-bearing
blocks. Unsupported or unknown timings fail closed instead of being guessed.

V1.2.0 preserves the V1.0 zero-copy Orange Pi 5 Plus datapath, keeps the verified reversible 1080p240 bridge EDID, and retains the native RGB capture path proven by the first real 240-Hz run.

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
bash scripts/pi-cycle.sh preparemonitor
```

Reconnect the Windows HDMI source once. For later runs, you only need:

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh 240
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

Fast automatic live video:

```bash
bash scripts/pi-cycle.sh 240
```

Automatically clone the connected monitor EDID with the bridge ceiling:

```bash
bash scripts/pi-cycle.sh preparemonitor
```

Restore the original RX EDID:

```bash
bash scripts/pi-cycle.sh restoreedid
```

Probe only:

```bash
bash scripts/pi-cycle.sh probe240
```

Full automatic diagnostic:

```bash
bash scripts/pi-cycle.sh diagnostic
```

The old command remains compatible:

```bash
bash scripts/pi-update-and-diagnose.sh
```

It now delegates to `pi-cycle.sh baseline`.

## Simplest Pi-only automatic workflow

Run `preparemonitor` on the Orange Pi, physically reconnect the Windows-source
HDMI cable so it rereads the EDID, select any offered refresh rate, then run
`240` on the Orange Pi. No Windows repository, PowerShell controller, or `.cmd`
file is required.

## Why the 240-Hz experiment matters

A 59.94-Hz refresh is about 16.68 ms. A 240-Hz refresh is about 4.17 ms. The current project measurements show that the dominant remaining delay is around one display refresh rather than userspace execution. If the RK3588 can sustain the same architecture at 1080p240, the same one-refresh boundary should become roughly four times smaller before deeper VOP2 work.

## 240-Hz EDID strategy

Windows duplicate mode merges/intersects display behavior and can misleadingly expose 240 Hz from the MSI. In extended mode the stock `RK-UHD` EDID exposes only 60 Hz. The custom bridge EDID fixes the receiver side directly.

`scripts/prepare-240.sh` backs up the stock receiver EDID and loads `edid/rk1080p240.bin`. The profile is based on the exact 256-byte Zowie XL2546X EDID captured by DRM, including its HDMI Forum 600-MHz capability block. The monitor's own 571-MHz 1080p239.964 timing is made preferred, with 1080p60 retained as a safe fallback.

The script refuses to proceed without a backup, validates the EDID checksums/timings, and verifies exact read-back after programming. It does not fall back to the generic `hdmi-4k-600mhz` preset because that preset does not advertise the required 1080p240 detailed timing.

`preparemonitor` supersedes the fixed profile for ordinary use. The fixed
`prepare240` mode remains available as a known Zowie recovery/diagnostic profile.

## Safety rules

- four buffers remain the stable minimum from V1.0 testing
- never requeue the currently displayed capture buffer
- only the previously displayed buffer is returned after the next KMS completion
- do not add GStreamer, CPU conversion, framebuffer copies, or a deliberate extra queue
- do not reintroduce the retired frame-dropping experiment
- each newly cloned monitor and timing remains hardware-dependent and must be
  verified; the known Zowie 1080p239.96 BGR3 path is already proven

## Documentation

- [Simple tutorial](TUTORIAL.txt)
- [Start here / detailed notes](START-HERE.txt)
- [Architecture](docs/ARCHITECTURE.md)
- [Operations](docs/OPERATIONS.md)
- [1080p240 experiment](docs/240HZ_EXPERIMENT.md)
- [Research findings](docs/RESEARCH_FINDINGS.md)
- [Roadmap](docs/ROADMAP.md)
- [V1.2.0 changelog](docs/V1.2_CHANGELOG.md)
