# V1.1.3 native-RGB 1080p240 experiment

V1.1 keeps the V1.0 zero-copy/fence/ownership datapath intact. The new work is deliberately outside the critical frame loop except for a small high-refresh mode-selection tolerance change.

## Why 240 Hz

1920×1080×240 and 3840×2160×60 have the same active-pixel rate. A 240-Hz refresh is roughly 4.17 ms, so an architecture that remains one refresh behind becomes much more useful than the same architecture at 59.94 Hz (~16.68 ms).

The first hardware run proved HDMI-RX lock at 1920×1080 239.96 Hz with a 570.988-MHz pixel clock on this exact board/kernel/driver.

## EDID preparation

`scripts/prepare-240.sh` first backs up the HDMI-RX EDID. It then loads the bundled `edid/rk1080p240.bin` bridge profile.

The bridge profile is derived from the exact Zowie XL2546X EDID captured on the RK3588 HDMI-TX connector. It preserves the Zowie HDMI Forum 600-MHz capability block and uses the Zowie's real timing:

- 1920×1080 active
- 2080×1144 total
- 571.000 MHz pixel clock
- 239.964 Hz
- 8-bit SDR

It makes that timing preferred and keeps 1920×1080 at 60 Hz as the first fallback. The script validates every 128-byte checksum and verifies exact read-back from HDMI-RX.

Use Windows extended-display mode. Duplicate mode can inherit the MSI's modes and is not evidence that RK-UHD advertised or accepted 240 Hz.

Never select a source timing above 240 Hz during this experiment even if the downstream monitor advertises one.

Rollback is always available with `bash scripts/pi-cycle.sh restoreedid` or `RUN-RESTORE-EDID.cmd`.

## 240-Hz gate

`scripts/probe-240.sh` queries the actual incoming HDMI timing and native capture format. It requires:

- 1920×1080 active resolution
- a reported frame rate between 230 and 250 fps
- a native one-plane capture format supported by the zero-copy program: `BGR3` or `NV24`

The probe deliberately does not request a different pixel format. The Rockchip vendor driver binds V4L2 capture format to the HDMI source encoding: RGB888 is exposed as `BGR3`, while YUV444 is exposed as `NV24`.

## Native RGB fix

The first 240-Hz run reached the target timing but exited because the older program required `NV24` while Windows transmitted RGB888. V1.1.3 accepts that native `BGR3` memory directly and describes the same byte layout to DRM as `RGB888` (`RG24`). Plane 114 advertises the required linear `RG24` format. No pixel conversion, CPU copy, GStreamer stage, or additional queue is introduced.

If the gate fails, the full passthrough run is skipped. The debug bundle is still packaged so the failure can be classified as EDID/source negotiation, RX timing lock, driver rejection, or something later in the path.

## Output timing

The V1.0 C program required a target mode within 0.005 Hz. That strict rule is retained below 120 Hz so a 59.940-Hz request cannot silently become 60.000 Hz.

For targets at or above 120 Hz, V1.1 allows up to 1.000 Hz of delta. This lets a `240000` mHz request select EDID timings such as 239.760 Hz without synthesizing an unadvertised mode.

## Success criteria

A useful first 240-Hz result has all of the following:

- HDMI-RX query reports 1920×1080 at ~240 fps
- DRM/KMS advertises a matching ~240-Hz 1080p mode
- diagnostic runs to completion
- zero missing Rockchip acquire fences
- zero V4L2 sequence gaps after warm-up
- DQ cadence near 4.17 ms
- commit-return-to-completion near one 240-Hz refresh if the existing KMS boundary remains

Only after this is stable should VOP2 late-latch / pending-update replacement work resume.
