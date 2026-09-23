# hdmirxtest

RK3588 / Orange Pi 5 Plus HDMI-RX to HDMI-TX low-latency bridge.

Current release: **v1.3**

## Repository layout

```text
hdmirxtest/
├── README.md
└── hdmirxtest-v1.3/
```

The README remains separate from the replaceable release folder.

## Why v1.3 exists

The v1.2 HDMI-TX test worked on the Zowie but the LG and Samsung reported no
signal. Its rotating log retained only Zowie boots and overwrote the television
EDID, so it could not identify where the TV handshake failed.

Version 1.3 gives every boot a permanent directory under:

```text
/var/lib/hdmirxtest/tx-history/
```

Each directory is named using the UTC timestamp and kernel boot ID. Later Zowie
boots cannot overwrite LG or Samsung evidence.

## What every boot records

- every `/dev/dri/card*` device and its kernel driver;
- every DRM connector, connection state and advertised mode;
- raw EDID and decoded EDID for every readable connector;
- DRM debug state, clients and summary when debugfs exposes them;
- complete and HDMI-filtered kernel messages;
- `modetest` connectors and planes when available;
- automatically selected DRM card, HDMI connector, CRTC and primary plane;
- each attempted timing and the exact modeset result.

HDMI-RX remains completely unused during this test.

## Compatibility mode sequence

For each connected HDMI display, v1.3 tries only modes explicitly advertised
by that display, in this order:

1. 1920×1080 at 60/59.94 Hz
2. 1280×720 at 60/59.94 Hz
3. 1920×1080 at 50 Hz
4. 1280×720 at 50 Hz
5. the display's preferred valid mode

Each mode gets an animated colour-bar interval. This both tests the normal
1080p path and provides conservative CEA television fallbacks. The test also
discovers the connected DRM card automatically instead of assuming `card0`.

## Clean installation

Upload this README and the `hdmirxtest-v1.3` folder to the existing repository.
Then run on the Orange Pi as `visionseek` while connected to the Zowie:

```bash
mkdir -p /home/visionseek/src
rm -rf -- /home/visionseek/src/hdmirxtest
cd /home/visionseek/src
git clone https://github.com/N0tiK44/hdmirxtest.git
cd /home/visionseek/src/hdmirxtest/hdmirxtest-v1.3
cat VERSION
bash TxTest.sh install
```

`cat VERSION` must print `1.3`. Installation preserves any existing diagnostic
history in `/var/lib/hdmirxtest`.

## Test the television offline

1. Let the initial Zowie colour-bar sequence finish.
2. Run `sudo poweroff`.
3. Leave HDMI-RX completely disconnected.
4. Connect Orange Pi HDMI-TX directly to the television.
5. Select that HDMI input and power on the Orange Pi.
6. Watch for any colour-bar interval for at least three minutes.
7. Power off, reconnect the Zowie and boot exactly once.

No network, keyboard or SSH connection is needed at the television.

## Retrieve all boot evidence

After returning to the Zowie:

```bash
cd /home/visionseek/src/hdmirxtest/hdmirxtest-v1.3
bash TxTest.sh history
bash TxTest.sh status
bash TxTest.sh results
```

The archive is:

```text
/home/visionseek/hdmirxtest-tx-history-latest.tar.gz
```

Copy it from Windows PowerShell:

```powershell
scp visionseek@192.168.20.35:/home/visionseek/hdmirxtest-tx-history-latest.tar.gz "$env:USERPROFILE\Downloads\"
```

Upload that archive for diagnosis. It contains every retained boot, including
the television boot even after reconnecting the Zowie.

## Controls

```bash
bash TxTest.sh status
bash TxTest.sh history
bash TxTest.sh results
bash TxTest.sh run
bash TxTest.sh enable
bash TxTest.sh disable
```

`disable` stops future automatic tests but deliberately preserves all history.

## HDMI-RX boundary

Do not run `setup.sh`, `restoreedid`, connect Windows, or connect Foxtel to
HDMI-RX until direct HDMI-TX works on the televisions. Once that succeeds, the
bridge workflow remains:

```bash
# HDMI-TX connected and HDMI-RX physically empty
bash setup.sh

# reconnect the source to HDMI-RX
bash PiCycle.sh
```

Normal bridge startup dynamically selects the output connector and compatible
plane by default. Manual numeric IDs remain optional diagnostic overrides.

The bridge still performs no scaling or frame-rate conversion. Its current
policy is RGB 8-bit SDR, fixed refresh, maximum 3840×2160, maximum 240 Hz and a
maximum 600 MHz pixel clock. It does not advertise DSC, FRL, HDR, VRR, deep
colour or YCbCr-only modes and does not implement an HDCP repeater.
