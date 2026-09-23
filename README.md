# hdmirxtest

RK3588 / Orange Pi 5 Plus HDMI-RX to HDMI-TX low-latency video bridge.

Current release: **v1.1**

## Repository layout

```text
hdmirxtest/
├── README.md
└── hdmirxtest-v1.1/
```

## Capability negotiation

The device builds a source-facing EDID from the intersection of:

1. Explicit modes advertised by the display connected to HDMI-TX.
2. The bridge geometry limit of 3840×2160.
3. The bridge refresh limit of 240 Hz.
4. The HDMI 2.0 pixel-clock limit of 600 MHz.
5. The current fixed RGB 8-bit SDR signal policy.

The HDMI source reads that generated EDID and chooses one of the advertised
modes. The bridge then reads the actual HDMI-RX timing and configures HDMI-TX
to the same resolution and refresh rate.

The source does not provide an EDID. It declares its choice by transmitting a
video timing after reading the bridge EDID.

## Mode flexibility

Modes can coexist in the generated EDID when the connected display explicitly
advertises them and each mode fits the bridge limits. Examples include:

| Use case | Example timing | Pixel clock |
|---|---:|---:|
| Maximum quality | 3840×2160 at 60 Hz | 594 MHz |
| Australian television | 3840×2160 at 50 Hz | 594 MHz |
| Intermediate resolution | 2560×1440 at display-supported rates | Must be ≤600 MHz |
| Maximum tested refresh | 1920×1080 at 239.964 Hz | 571 MHz |
| Compatibility | 1920×1080 at 50/59.94/60 Hz | ≤148.5 MHz |

This is an intersection, not a universal mode injection system. A 4K60
television that does not advertise 1080p240 will not be told to accept
1080p240. A 1080p60 display will expose only its compatible modes, causing a
well-behaved 4K/8K-capable source to select 1080p instead.

The bridge performs no scaling or frame-rate conversion. Input and output must
use the same resolution and refresh rate.

## Signal policy

The current video path accepts native HDMI-RX NV24/YUV444 or BGR3/RGB888 and
imports its DMA-BUF directly into DRM/KMS. It uses:

- RGB 8-bit SDR advertisement
- Fixed refresh rates
- No deliberate userspace frame queue
- No GStreamer
- No CPU colour conversion
- No framebuffer copy

The EDID deliberately excludes audio, DSC, FRL, HDR, VRR/FreeSync, YCbCr-only
modes and deep colour. RGB 10-bit is not advertised because high-bandwidth
modes such as 4K60 and 1080p240 would exceed the 600 MHz HDMI 2.0 transport
ceiling at 10-bit depth.

## Important protected-content boundary

EDID negotiation and HDCP authentication are different systems. This project
does not implement or bypass an HDCP repeater. A protected source may show a
blank image or compatibility error even when resolution negotiation succeeds.
Foxtel 4K content normally expects an HDCP 2.2-capable chain.

The current bridge is also video-only; HDMI audio is not forwarded.

## Wiring

```text
HDMI source output -> Orange Pi HDMI-RX
Orange Pi HDMI-TX  -> television or monitor
```

During EDID setup, keep the display connected to HDMI-TX and physically unplug
the source from HDMI-RX. Setup refuses to rewrite EDID while an active source
signal is detected.

## Clean installation

Run as the normal `visionseek` user:

```bash
cd /
sudo systemctl disable --now hdmirxtest-passthrough.service 2>/dev/null || true

mkdir -p /home/visionseek/src
rm -rf -- /home/visionseek/src/hdmirxtest

cd /home/visionseek/src
git clone https://github.com/N0tiK44/hdmirxtest.git
cd /home/visionseek/src/hdmirxtest/hdmirxtest-v1.1
cat VERSION
```

The version command must print:

```text
1.1
```

## Display setup

Before setup:

```text
HDMI-TX -> television/monitor: connected
Source  -> HDMI-RX:           physically unplugged
```

Run:

```bash
bash setup.sh
```

Setup reads the HDMI-TX EDID, generates the filtered intersection, verifies
exact HDMI-RX read-back and installs the boot-time EDID loader.

Reconnect the source only after setup succeeds.

## Start and stop video

Start:

```bash
bash PiCycle.sh
```

Stop and return to the terminal:

```text
Ctrl+C
```

Video runs in the foreground. Only the verified EDID loader runs during boot.

## Fullscreen-exclusive games

Fullscreen-exclusive mode can make Windows temporarily remove the HDMI signal
while the game changes resolution, refresh rate or display state. Version 1.1
keeps the foreground runner alive while the source is absent and automatically
restarts the zero-copy path when a new HDMI-RX timing locks.

A brief black screen during HDMI link retraining is normal. The bridge should
then select the identical HDMI-TX resolution and refresh rate and resume video.

If a game requests a mode that is not present in the generated EDID, or it
repeatedly changes into HDR, VRR or another excluded signal state, the bridge
will fail closed. Use borderless-windowed mode as the compatibility fallback,
then run `bash PiCycle.sh debug` after reproducing the problem.

## Testing a Foxtel box and television

1. Connect Orange Pi HDMI-TX to the television.
2. Leave Foxtel physically disconnected from HDMI-RX.
3. Run `bash setup.sh`.
4. Connect Foxtel to HDMI-RX.
5. Run `bash PiCycle.sh`.
6. If video fails, press `Ctrl+C` and run `bash PiCycle.sh debug`.

The test determines whether Foxtel selects an advertised timing and whether the
RK3588 HDMI-RX and DRM plane accept the resulting native format. It cannot make
protected content pass an unsupported HDCP chain.

## Changing displays

1. Press `Ctrl+C`.
2. Physically unplug the HDMI source from HDMI-RX.
3. Connect the replacement display to HDMI-TX.
4. Run `bash PiCycle.sh setup`.
5. Reconnect the source.
6. Run `bash PiCycle.sh`.

## Debugging

```bash
bash PiCycle.sh debug
```

The result archive is written to:

```text
/home/visionseek/hdmirxtest-debug-latest.tar.gz
```

The saved bridge manifest includes the downstream identity, filtering limits,
explicit detailed timings and CTA video identification codes retained in the
generated EDID.

## Recovery

Physically unplug the HDMI source from HDMI-RX, then run:

```bash
bash PiCycle.sh restoreedid
```

Recovery installs an audited RGB 8-bit 1080p60 profile.

## Current validation status

The EDID policy is validated for explicit 4K24/25/30/48/50/60 CTA modes,
2560-wide ultrawide CTA modes, explicit 2560×1440 detailed timings and the
existing 1080p240 path. The 4K60 hardware datapath remains experimental until
captured and tested on the Orange Pi with a real 4K display and unprotected
source.
