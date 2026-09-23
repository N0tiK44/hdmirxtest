# hdmirxtest

Minimal RK3588 / Orange Pi 5 Plus HDMI-RX to HDMI-TX low-latency video
passthrough.

Current release: **v1.0**

## Repository layout

```text
hdmirxtest/
├── README.md
└── hdmirxtest-v1.0/
```

The README stays at the repository root. All runnable product files live inside
the single versioned directory.

## Purpose

The project receives video through the Orange Pi HDMI-RX interface and presents
the captured frames directly on HDMI-TX through DRM/KMS. It also hosts a safe,
monitor-derived EDID toward the source computer.

The setup process:

1. Reads the real EDID from the display connected to HDMI-TX.
2. Preserves the downstream monitor identity.
3. Keeps only compatible timings within the configured bridge ceiling.
4. Writes and verifies the generated EDID on HDMI-RX.
5. Saves that verified EDID for automatic loading during boot.

The advertised ceiling is:

- 1920×1080 maximum resolution
- 240 Hz maximum refresh rate
- 600 MHz maximum pixel clock
- Fixed-rate RGB 8-bit SDR

DSC, FRL, HDR, VRR/FreeSync, YCbCr, deep colour, 4K modes and refresh rates
above 240 Hz are not advertised.

## Wiring

```text
Windows PC HDMI output -> Orange Pi HDMI-RX
Orange Pi HDMI-TX      -> target monitor
```

During EDID setup, keep the target monitor connected to HDMI-TX and physically
unplug the Windows cable from HDMI-RX. The scripts refuse to rewrite EDID while
an active HDMI-RX source is detected.

## Clean installation

Run these commands as the normal `visionseek` user:

```bash
cd /
sudo systemctl disable --now hdmirxtest-passthrough.service 2>/dev/null || true

mkdir -p /home/visionseek/src
rm -rf -- /home/visionseek/src/hdmirxtest

cd /home/visionseek/src
git clone https://github.com/N0tiK44/hdmirxtest.git
cd /home/visionseek/src/hdmirxtest/hdmirxtest-v1.0
cat VERSION
```

The version command must print:

```text
1.0
```

## First setup

Before continuing:

```text
HDMI-TX -> target monitor: connected
Windows -> HDMI-RX:       physically unplugged
```

Run:

```bash
bash setup.sh
```

This installs dependencies, validates the package, builds the passthrough
program, generates the monitor-derived EDID, verifies exact HDMI-RX read-back
and installs the boot-time EDID loader.

Reconnect Windows to HDMI-RX only after setup succeeds.

## Normal use

Start video:

```bash
bash PiCycle.sh
```

Stop video and return to the terminal:

```text
Ctrl+C
```

Video runs only in the foreground. It is not started as a background service.
Only the verified EDID loader is enabled during boot.

## Changing monitors

1. Press `Ctrl+C` if video is running.
2. Physically unplug Windows from HDMI-RX.
3. Connect the replacement monitor to HDMI-TX.
4. Run `bash PiCycle.sh setup`.
5. Reconnect Windows after setup succeeds.
6. Run `bash PiCycle.sh`.

The start command checks the HDMI-TX identity and refuses to silently rewrite
the Windows-facing EDID underneath an active source connection.

## Debugging

Collect a hardware and EDID snapshot without starting video:

```bash
bash PiCycle.sh debug
```

The archive is written to:

```text
/home/visionseek/hdmirxtest-debug-latest.tar.gz
```

## Safe recovery

Physically unplug Windows from HDMI-RX, then run:

```bash
bash PiCycle.sh restoreedid
```

Recovery installs the bundled audited RGB 8-bit 1080p60 profile. It does not
load an unknown or unfiltered EDID backup.

## Technical boundary

The Orange Pi is a captured-frame HDMI-RX to DRM/KMS HDMI-TX system, not a
transparent electrical HDMI repeater. The source-facing identity and supported
timings can be derived from the downstream monitor, but transport features the
hardware pipeline cannot carry are deliberately excluded instead of being
falsely advertised.
