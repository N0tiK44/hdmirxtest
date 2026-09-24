# Passive TV HDMI diagnostic add-on (V1.5)

This add-on exists to answer one question before any active HDMI-TX testing:

> When an Orange Pi 5 Plus is connected to a TV that shows **No Signal**, what does the stock Linux DRM/HDMI stack actually see?

It deliberately does **not** perform a DRM modeset, does **not** display colour bars, and does **not** open HDMI-RX. It passively records both HDMI connector states every two seconds for about 90 seconds, including status, advertised modes, EDID presence/hash, DRM debug state, and HDMI/PHY-related kernel logs.

## Office setup

```bash
bash TvDiag.sh install
bash TvDiag.sh field
```

`field` arms one diagnostic for the next boot and powers the Pi off cleanly.

## Living-room test

Connect only the HDMI-TX cable to the TV, leave HDMI-RX disconnected, and power the Pi on. No keyboard, Ethernet, Wi-Fi, or terminal is required. After roughly two minutes the Pi saves the evidence and powers itself off.

## Back in the office

Boot normally and run:

```bash
bash TvDiag.sh status
bash TvDiag.sh results
```

Upload `~/hdmirxtest-tv-diag-latest.tar.gz` for analysis.

Normal boots remain idle because the arm marker is consumed before the diagnostic begins.
