# TX-first test plan — v1.4

## Acceptance criterion

Before HDMI-RX development resumes, the Orange Pi must be able to boot with HDMI-RX disconnected and generate a stable direct HDMI picture on the target displays.

## What v1.4 changes from v1.3

V1.3 proved that the dumb-buffer/KMS path can work on the Zowie, but its mode profiles grouped 59.94 and 60.00 Hz together. Because the program returned the first EDID mode matching a broad 59–61 Hz range, it did not prove both timings individually. V1.4 separates them and records state around every attempt.

V1.4 also targets a named HDMI connector (`HDMI-A-1`, `HDMI-A-2`) rather than relying on a numeric connector ID that can change across boots/topologies.

## Test matrix

For every connected HDMI sink, v1.4 attempts only modes that the sink itself advertises, in this order:

1. 1920x1080 around 59.94 Hz
2. 1920x1080 around 60.00 Hz
3. 1280x720 around 59.94 Hz
4. 1280x720 around 60.00 Hz
5. 1920x1080 at 50.00 Hz
6. 1280x720 at 50.00 Hz
7. 720x576 at 50.00 Hz
8. 720x480 around 59.94 Hz
9. 720x480 around 60.00 Hz
10. 640x480 around 60 Hz
11. the display's preferred valid mode

Unsupported/non-advertised entries are skipped by the binary; they are not synthesized.

## Physical test sequence

- RX cable removed.
- One TX port connected directly to the sink.
- No splitter, capture card, AVR or converter between Pi and sink.
- Observe the full mode sequence.
- Repeat on the second physical TX port if the first gives no image.
- Return to the Zowie and export `TxTest.sh results`.

## Evidence captured

The archive retains:

- DRM device/driver inventory;
- sysfs connector names, status, modes and EDID;
- decoded EDID when `edid-decode` exists;
- DRM debugfs state/summary;
- `modetest` connector/plane output when available;
- full and HDMI-filtered kernel logs;
- display-related interrupt counters;
- a before/after snapshot around each attempted mode;
- the exact card, connector, timing profile and return code;
- a runtime heartbeat in `/run/hdmirxtest/tx-heartbeat`.

## Interpretation

- **Picture appears on one mode only:** TX/PHY works; mode selection or timing compatibility is the next target.
- **All modes return success in logs but TV always says No Signal:** investigate the Rockchip HDMI transmitter/PHY/connector state rather than HDMI-RX.
- **Connector never becomes `connected` or has no EDID:** focus on HPD/DDC/EDID/physical-port/DT/kernel issues.
- **Modeset returns an error:** use the matching per-attempt snapshot and kernel log to identify the rejected CRTC/plane/mode route.
- **Zowie works on both ports but TVs fail on both:** the problem is sink-specific TX negotiation, not the RX pipeline.

Only after this gate passes do we resume V4L2 HDMI-RX work.
