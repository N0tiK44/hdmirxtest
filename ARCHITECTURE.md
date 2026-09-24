# HDMIRXTEST architecture

## Product goal

The Orange Pi 5 Plus is treated as one HDMI appliance with two operating modes that share the same transmitter subsystem.

### Mode A — standalone output

```text
Orange Pi application / generated surface
                |
                v
           DRM/KMS TX core
                |
        +-------+-------+
        |               |
      TX port 1       TX port 2
        |               |
     display          display
```

HDMI-RX is not required. This mode is also the bring-up and recovery mode because it proves the transmitter independently of capture.

### Mode B — low-latency pass-through

```text
HDMI source
    |
    v
 HDMI-RX / V4L2
    |
 DMA-BUF + acquire fence
    |
    +---------------------------> AI / recording / analysis (secondary consumer)
    |
    v
 DRM/KMS plane + release fence
    |
 HDMI-TX
    |
 display
```

The display path must never wait for AI, recording, encoding, networking, or CPU colour conversion.

## Shared state machine

The intended final controller is a small daemon with explicit states:

```text
BOOT
  -> DISCOVER_DRM
  -> WAIT_TX
  -> TX_READY
       -> STANDALONE              (no usable RX signal)
       -> RX_LOCKING
       -> PASSTHROUGH             (RX locked and compatible)
       -> REMATCH                 (source timing changes)
       -> STANDALONE / WAIT_TX    (source or sink removed)
```

The daemon should expose a heartbeat containing at least:

- DRM card and kernel driver
- connector name and connection state
- EDID validity and selected mode
- CRTC/plane selected by capability
- RX device and lock state (when RX work resumes)
- current operating mode
- frame/queue/drop counters
- last successful presentation timestamp

V1.4 implements only the TX-side heartbeat because TX universality is the current gate.

## Non-negotiable latency rules for pass-through

- no GStreamer in the production display-critical path;
- no software encode/decode round-trip;
- no userspace framebuffer copy;
- no CPU colour conversion merely for convenience;
- V4L2 capture buffers should be exported/imported through DMA-BUF;
- explicit acquire/release fences should be used where the Rockchip driver exposes them;
- the AI path is a tap/secondary consumer and may drop work rather than delaying the display path;
- scaling or frame-rate conversion is not silently introduced.

## Discovery policy

Product code must not assume that `/dev/dri/card0`, `/dev/video0`, a numeric connector ID, or a plane ID is stable across kernels, displays, or boots.

Discovery should be capability based:

1. enumerate DRM cards;
2. enumerate connected physical HDMI connectors;
3. read EDID and advertised modes;
4. enumerate compatible encoders/CRTCs;
5. enumerate planes and required formats;
6. select a valid route;
7. only then modeset/scan out.

The same principle will later be applied to HDMI-RX V4L2/media discovery.

## Development gates

1. Universal HDMI-TX direct output.
2. TX hotplug/recovery.
3. Both physical TX ports mapped and proven.
4. Standalone output kept active indefinitely.
5. RX discovery and lock heartbeat.
6. Raw RX capture.
7. DMA-BUF import into DRM.
8. Direct zero-copy scanout with explicit fencing.
9. Dynamic resolution/refresh rematching.
10. Secondary AI consumer without display back-pressure.

No later gate should be used to work around a failure in an earlier one.
