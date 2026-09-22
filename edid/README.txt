HDMIRXTEST EDID PROFILES
========================

rk1080p240.bin
---------------
Custom Orange Pi HDMI-RX bridge EDID derived from the Zowie XL2546X EDID
captured by `modetest -M rockchip -c` on the actual test hardware.

Preferred timing:
    1920 x 1080
    239.964 Hz
    571.000 MHz pixel clock
    H total 2080
    V total 1144

First fallback:
    1920 x 1080
    60.000 Hz
    148.500 MHz pixel clock

SHA-256:
    5ab4e8f07e38c6786e03f043905318601163f5fd29d2f441cc2adbc6c9d23ae6


zowie-xl2546x-captured.bin
---------------------------
Exact 256-byte EDID captured from the downstream Zowie XL2546X.

SHA-256:
    f00b7e502842f659e02a4ace00014cc00ea2e1b5e1b620cfd1a228c39de4beaf


rk-uhd-stock.bin
----------------
Verified 256-byte stock RK-UHD HDMI-RX EDID captured before the custom profile.
This is the final recovery fallback if the permanent pre-change backup is not
available.

SHA-256:
    abd553b14098d56dbf583ba86052216097157e36ea6fb5335ef9935ee1212cdc


Validation
----------
Run from the repository root:

    python3 tools/build-240-edid.py --check edid/rk1080p240.bin

Expected output includes:

    checksums=valid
    preferred=1920x1080 239.964 Hz (571.000 MHz)
    fallback=1920x1080 60.000 Hz
