# hdmirxtest — RK3588 HDMI ultra-low-latency passthrough — V1.2.3

V1.2.3 is both a downstream-monitor impersonator and a capacity-limited HDMI
bridge. It copies the HDMI-TX sink's manufacturer, product, serial and monitor
name, then advertises only the timing/signal intersection supported by that
sink and the proven RK3588 path. It refuses to rewrite EDID while an HDMI-RX
source is active.

V1.2.3 also fixes the lifecycle faults demonstrated on Ubuntu 24.04: normal
live operation is continuous rather than a 120-second test, systemd reloads the
verified EDID at boot and can keep passthrough running persistently, and source
timing changes no longer restore the old DRM mode before rematching.

## V1.2.3 safe workflow

Physically unplug the Windows/motherboard HDMI cable from HDMI-RX. Leave the
real output monitor connected to HDMI-TX, then run:

```bash
bash scripts/pi-cycle.sh setup
```

Reconnect or disable/re-enable the Windows-to-HDMI-RX source so Windows reads
the new EDID. On Ubuntu/systemd, start the persistent service with:

```bash
bash scripts/pi-cycle.sh service-start
```

For a foreground run instead:

```bash
bash scripts/pi-cycle.sh 240
```

Despite the legacy command name, `240` is now an alias for the automatic live
path. It reads the current HDMI-RX timing and selects the matching downstream
mode at any advertised rate up to the hard ceiling. If Windows changes timing,
the wrapper tears down safely and rematches automatically.

`live` and `240` now run continuously until Ctrl-C. Set `DURATION=120` only
when a timed test archive is wanted. The fast path performs only an incremental build when source code changed. It
does not contact Git or collect large diagnostics before video. Use this when
an update is wanted:

```bash
bash scripts/pi-cycle.sh sync
```

Or update and then run in one invocation:

```bash
SYNC=1 bash scripts/pi-cycle.sh 240
```

The generated EDID preserves the sink identity and only those sink timings that can be proved to be no
greater than 1920x1080 at 240 Hz and 600 MHz pixel clock. It advertises fixed
RGB 8-bit SDR and removes DSC, FRL, YCbCr, deep-colour, HDR, VRR/FreeSync and
unknown timing-bearing blocks. Unsupported or unknown timings fail closed.

The main monitor may independently use DSC, HDR, or FreeSync. HDMI outputs
negotiate separately; those features are intentionally not advertised on the
Orange Pi bridge output.

`restoreedid` no longer restores `rx-edid-original.bin`, the stock `RK-UHD`
profile, or any historical backup. It installs an audited RGB 8-bit 1080p60
recovery EDID and also requires HDMI-RX to be physically disconnected.

V1.2.3 preserves the V1.0 zero-copy Orange Pi 5 Plus datapath and the native
RGB capture path proven by the first real 240-Hz run.

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
- historical note: older releases restored the pre-experiment RX EDID; V1.2.1
  intentionally replaces that behavior with an audited 1080p60 recovery EDID
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
bash scripts/pi-cycle.sh setup
```

Reconnect the Windows HDMI source once. On Ubuntu, start the persistent service:

```bash
cd ~/src/hdmirxtest
bash scripts/pi-cycle.sh service-start
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

Persistent automatic live video on Ubuntu/systemd:

```bash
bash scripts/pi-cycle.sh service-start
bash scripts/pi-cycle.sh service-status
```

Continuous foreground video:

```bash
bash scripts/pi-cycle.sh 240
```

Automatically clone the connected monitor EDID with the bridge ceiling:

```bash
bash scripts/pi-cycle.sh setup
```

Install the audited 1080p60 emergency recovery EDID:

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

Run `setup` on the Orange Pi with HDMI-RX physically disconnected, then
reconnect the Windows-source
HDMI cable so it rereads the EDID, select any offered refresh rate, then run
`service-start` on Ubuntu or `240` for a foreground session. No Windows
repository, PowerShell controller, or `.cmd` file is required.

## Why the 240-Hz experiment matters

A 59.94-Hz refresh is about 16.68 ms. A 240-Hz refresh is about 4.17 ms. The current project measurements show that the dominant remaining delay is around one display refresh rather than userspace execution. If the RK3588 can sustain the same architecture at 1080p240, the same one-refresh boundary should become roughly four times smaller before deeper VOP2 work.

## 240-Hz EDID strategy

Windows duplicate mode merges/intersects display behavior and can misleadingly expose 240 Hz from the MSI. In extended mode the stock `RK-UHD` EDID exposes only 60 Hz. The custom bridge EDID fixes the receiver side directly.

`scripts/prepare-240.sh` backs up the stock receiver EDID and loads `edid/rk1080p240.bin`. The profile is based on the exact 256-byte Zowie XL2546X EDID captured by DRM, including its HDMI Forum 600-MHz capability block. The monitor's own 571-MHz 1080p239.964 timing is made preferred, with 1080p60 retained as a safe fallback.

The script refuses to proceed without a backup, validates the EDID checksums/timings, and verifies exact read-back after programming. It does not fall back to the generic `hdmi-4k-600mhz` preset because that preset does not advertise the required 1080p240 detailed timing.

`setup`, `preparemonitor`, and the legacy `prepare240` spelling now all use the
same safe connected-monitor intersection pipeline.

Before every `live`/`240` start, the fast preflight compares the current
HDMI-TX EDID with the monitor used by `setup`. If a different monitor is
connected, its filtered profile is staged automatically. If Windows is still
active on HDMI-RX, the program stops and requests one controlled unplug, setup,
and reconnect cycle instead of changing EDID under a live source.

Setup writes `/var/lib/hdmirxtest/bridge-manifest.json` with SHA-256 hashes,
source/bridge identities, the hard ceiling and deliberately removed features.
The live path requires the HDMI-RX read-back to match the installed bridge EDID
byte-for-byte before video starts.

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
- [V1.2.1 safety changelog](docs/V1.2.1_CHANGELOG.md)
- [V1.2.2 identity bridge changelog](docs/V1.2.2_CHANGELOG.md)
- [V1.2.3 persistence/relock changelog](docs/V1.2.3_CHANGELOG.md)
