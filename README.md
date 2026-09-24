# hdmirxtest

RK3588 / Orange Pi 5 Plus HDMI appliance project.

Current release: **v1.4**

The final product has two modes:

1. **Standalone HDMI-TX mode** — the Orange Pi generates/output its own image with HDMI-RX unused.
2. **Low-latency pass-through mode** — HDMI-RX frames are forwarded to HDMI-TX through the shortest practical V4L2 DMA-BUF -> DRM/KMS path, with AI/recording kept off the display-critical path.

## Why v1.4 exists

The immediate blocker is HDMI-TX universality. The previous v1.3 test produced a stable image on the Zowie monitor while some televisions reported **No Signal**. Before changing HDMI-RX again, v1.4 isolates the transmitter and makes the TX test substantially more deterministic.

V1.5 keeps HDMI-RX completely unused during the TX milestone.

## What changed in v1.4

- Selects a connected HDMI output by **DRM card + connector name** (`HDMI-A-1`, `HDMI-A-2`) instead of one machine-specific numeric connector ID.
- Tests both physical HDMI outputs when they are connected.
- Separates **59.94 Hz** and **60.00 Hz** timings instead of treating them as one profile.
- Adds additional conservative EDID-advertised fallbacks: 1080p, 720p, 576p, 480p and VGA-class 60 Hz where the sink actually advertises them.
- Adds a runtime heartbeat at `/run/hdmirxtest/tx-heartbeat`.
- Saves lightweight DRM/HDMI state both **before and after every mode attempt**.
- Retains complete per-boot history under `/var/lib/hdmirxtest/tx-history/`.
- Adds both **systemd and OpenRC** installation support.
- Does not use HDMI-RX, EDID cloning, GStreamer, encoding, or the pass-through binary during the TX-only test.

## Repository layout

```text
hdmirxtest/
├── README.md
├── hdmirxtest-v1.3/       # previous release retained for comparison
└── hdmirxtest-v1.5/       # current TX-first release
```

## Install v1.4 on the Orange Pi

```bash
cd /home/visionseek/src
rm -rf -- hdmirxtest
git clone https://github.com/N0tiK44/hdmirxtest.git
cd hdmirxtest/hdmirxtest-v1.5
cat VERSION
bash TxTest.sh install
```

`cat VERSION` must print `1.4`.

## TX-only television test

1. Keep **HDMI-RX physically disconnected**.
2. Connect one Orange Pi HDMI-TX port directly to the display.
3. Boot the Pi and let the v1.4 mode matrix finish.
4. Record whether **any** colour-bar interval appears, even briefly.
5. Power down and repeat with the other physical HDMI-TX port if required.
6. Return to the known-good Zowie once and collect the retained history.

```bash
cd /home/visionseek/src/hdmirxtest/hdmirxtest-v1.5
bash TxTest.sh status
bash TxTest.sh history
bash TxTest.sh results
```

The resulting archive is:

```text
~/hdmirxtest-tx-history-latest.tar.gz
```

Upload that archive for the next diagnosis.

## Manual standalone output

With a display connected:

```bash
bash TxTest.sh run
```

This selects the connected HDMI connector automatically and holds an animated test image until `Ctrl+C`.

## Important boundary

Do **not** run `setup.sh`, `PiCycle.sh`, EDID cloning, or HDMI-RX tests until direct HDMI-TX output works reliably on the target televisions/monitors. The pass-through code remains in the release, but it is deliberately not part of this milestone.

See `docs/ARCHITECTURE.md` for the final two-mode design and `docs/TX-FIRST-TEST-PLAN.md` for the current acceptance gates.
