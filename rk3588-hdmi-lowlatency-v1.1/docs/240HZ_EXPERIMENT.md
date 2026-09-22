# V1.1 1080p240 feasibility experiment

V1.1 keeps the V1.0 zero-copy/fence/ownership datapath intact. The new work is deliberately outside the critical frame loop except for a small high-refresh mode-selection tolerance change.

## Why 240 Hz

1920×1080×240 and 3840×2160×60 have the same active-pixel rate. A 240-Hz refresh is roughly 4.17 ms, so an architecture that remains one refresh behind becomes much more useful than the same architecture at 59.94 Hz (~16.68 ms).

This is a feasibility target, not a claim of support. RK3588 documentation commonly states HDMI-RX up to 4K60, and 1080p240 must be proven on the exact board/kernel/driver.

## EDID preparation

`scripts/prepare-240.sh` first backs up the HDMI-RX EDID. It then looks for a connected DRM output EDID and forwards that raw EDID to HDMI-RX. In the normal lab topology that downstream display is the Zowie, so Windows sees the Zowie's real advertised timings instead of a generic receiver identity.

If forwarding fails, the script falls back to v4l2-ctl's standard `hdmi-4k-600mhz` EDID. That fallback advertises HDMI 2.0-class link capability but does not itself promise a 1080p240 detailed timing.

Never select a source timing above 240 Hz during this experiment even if the downstream monitor advertises one.

## 240-Hz gate

`scripts/probe-240.sh` queries the actual incoming HDMI timing. It requires:

- 1920×1080 active resolution
- a reported frame rate between 230 and 250 fps

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
