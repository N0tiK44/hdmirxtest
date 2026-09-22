# Roadmap after V1.1

## 1. Keep V1.0 behavior as the baseline

The zero-copy V4L2 DMA-BUF -> DRM/KMS path and buffer-ownership rule remain the rollback point. Do not reintroduce deliberate frame dropping, unsafe early QBUF, GStreamer conversion, or framebuffer copies.

## 2. Prove 1080p240 on the exact HDMI-RX stack

Use the V1.1 sequence:

1. forward the downstream Zowie EDID to HDMI-RX
2. make Windows source 1920×1080 at ~240 Hz
3. run `probe240`
4. only after the gate passes, run the full `240` diagnostic

Classify the first failure precisely: source/EDID negotiation, HDMI-RX PHY/controller lock, V4L2 driver, DMA cadence, DRM mode availability, or KMS scanout.

## 3. Re-measure the frame boundary at 240 Hz

If the same one-refresh completion behavior remains, the expected dominant interval becomes roughly 4.17 ms instead of 16.68 ms. Confirm with CSV statistics rather than visual assumption.

## 4. Then investigate VOP2 late-latch / async behavior

Only after 240-Hz capture/scanout is stable should kernel work continue:

- where Rockchip serializes a pending atomic update
- whether a pending framebuffer address can be replaced before latch
- whether VOP2 supports a safe async update path
- whether an `atomic_async_check` / `atomic_async_update` implementation is feasible

## 5. Clean glass-to-glass control

For final visual latency validation, drive reference and passthrough-source outputs from the same GPU if possible. The current discrete-GPU versus CPU/iGPU comparison is not guaranteed to be genlocked.
