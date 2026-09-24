# Offline field-test workflow

V1.5 is designed for a Pi that must be physically moved to a TV with no Ethernet or terminal access.

1. Install once in the office with `bash TxTest.sh install`.
2. Immediately before moving the board, run `bash TxTest.sh field`. This creates a persistent one-shot arm marker and powers the Pi off cleanly.
3. At the remote display, connect only one HDMI-TX cable and power the Pi. No keyboard or network is required.
4. The boot service consumes the arm marker before testing, so even a reboot cannot create a repeated test/poweroff loop.
5. The TX matrix is saved under `/var/lib/hdmirxtest/tx-history`, filesystems are synchronized, and the OS powers off automatically.
6. Back in the office, ordinary boots are idle because the marker has been consumed. Run `bash TxTest.sh results` to package the accumulated evidence.

HDMI-RX remains intentionally unused in this milestone.
