# hdmirxtest

RK3588 / Orange Pi 5 Plus HDMI-RX to HDMI-TX low-latency bridge.

Current release: **v1.2**

## Repository layout

```text
hdmirxtest/
├── README.md
└── hdmirxtest-v1.2/
```

The release folder contains the program and scripts. The README stays beside
that folder so a release can be replaced without mixing documentation into its
source tree.

## Current priority: HDMI-TX only

Version 1.2 first proves that Orange Pi HDMI-TX can drive each display without
HDMI-RX, EDID injection, a network connection or a keyboard. It fixes the old
Zowie-specific assumption by discovering the following at run time:

- connected HDMI connector and its current EDID modes;
- compatible CRTC;
- compatible primary plane supporting XRGB8888;
- a conservative progressive mode advertised by that exact display.

The mode preference is 1080p60, 1080p50, 720p60, 720p50, then the display's
preferred valid mode. Nothing is invented for this diagnostic. The test draws
animated colour bars directly with DRM/KMS and saves its connector decision,
mode, EDID and result to persistent storage.

This separates a basic HDMI-TX compatibility failure from every HDMI-RX,
Windows, Foxtel, capture-format, HDCP and bridge problem.

## Clean installation

Run these commands as the normal `visionseek` user while connected to the
working Zowie display:

```bash
mkdir -p /home/visionseek/src
rm -rf -- /home/visionseek/src/hdmirxtest
cd /home/visionseek/src
git clone https://github.com/N0tiK44/hdmirxtest.git
cd /home/visionseek/src/hdmirxtest/hdmirxtest-v1.2
cat VERSION
bash TxTest.sh install
```

`cat VERSION` must print `1.2`. Installation builds the TX-only test, enables
it at boot and immediately starts one two-minute colour-bar run.

## Offline television test

For each LG, Samsung or other display:

1. Power off the Orange Pi.
2. Disconnect HDMI-RX completely.
3. Connect Orange Pi HDMI-TX directly to the display's HDMI input.
4. Select that input and power on the Orange Pi.
5. Wait up to 60 seconds for boot. Animated colour bars should appear and move
   for two minutes.
6. Power off and repeat on the next display.

No SSH, Ethernet, Wi-Fi or keyboard is needed during these tests. A static
boot logo is not the pass condition; the moving box and border prove the v1.2
test program took control of the discovered output.

## Retrieve the offline result

After reconnecting the Pi to the Zowie:

```bash
cd /home/visionseek/src/hdmirxtest/hdmirxtest-v1.2
bash TxTest.sh status
bash TxTest.sh results
```

The archive is:

```text
/home/visionseek/hdmirxtest-tx-latest.tar.gz
```

It contains the saved downstream EDID, selected connector/mode log and current
DRM connector status. To copy it into Windows Downloads from PowerShell:

```powershell
scp visionseek@192.168.20.35:/home/visionseek/hdmirxtest-tx-latest.tar.gz "$env:USERPROFILE\Downloads\"
```

## Manual controls

```bash
bash TxTest.sh run       # run until Ctrl+C
bash TxTest.sh status    # show last boot result
bash TxTest.sh results   # create result archive
bash TxTest.sh enable    # enable automatic test next boot
bash TxTest.sh disable   # stop and disable automatic test
```

Disable the TX test after all displays pass:

```bash
bash TxTest.sh disable
```

## HDMI-RX bridge — only after TX passes

Do not connect a source to HDMI-RX or run EDID setup while diagnosing direct
HDMI-TX. Once Zowie, LG and Samsung all show the v1.2 colour bars, the existing
bridge workflow remains:

```bash
# HDMI-TX connected; HDMI-RX physically empty
bash setup.sh

# reconnect the source to HDMI-RX
bash PiCycle.sh
```

Press `Ctrl+C` to stop video and return to the terminal. Normal bridge startup
now defaults connector and plane IDs to `0`, meaning automatic selection. A
manual numeric override remains available only for debugging.

## Bridge capability boundary

EDID setup builds a source-facing intersection from modes explicitly advertised
by the HDMI-TX display, limited to 3840×2160, 240 Hz and a 600 MHz pixel clock,
under the current RGB 8-bit SDR fixed-refresh policy. Examples can include
4K60, 1440p modes and 1080p240 when the connected display advertises them.

The bridge performs no scaling or frame-rate conversion. It does not advertise
DSC, FRL, HDR, VRR/FreeSync, deep colour or YCbCr-only modes, and it does not
forward HDMI audio. EDID negotiation is separate from HDCP; this project does
not implement or bypass an HDCP repeater, so protected Foxtel content can still
remain blank even when a timing is valid.

Fullscreen-exclusive games can temporarily remove the source signal while
changing resolution or refresh. The foreground runner waits for the source and
relocks to the new compatible timing. Borderless-windowed mode remains the
compatibility fallback for unsupported transitions.
