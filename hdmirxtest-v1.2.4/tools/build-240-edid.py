#!/usr/bin/env python3
"""Build and validate the hdmirxtest 1080p240 bridge EDID.

The source bytes are the genuine 256-byte EDID captured from the connected
ZOWIE XL2546X by `modetest -M rockchip -c`.  The bridge variant makes the
monitor's own 571.000 MHz 1920x1080@239.96 detailed timing the preferred mode,
keeps 1920x1080@60 as the first fallback, and gives the receiver a unique name
so Windows does not confuse it with the stock RK-UHD profile.
"""

from __future__ import annotations

import argparse
from pathlib import Path


# Keep the constant visually aligned with the 16-byte modetest rows while
# avoiding a transcription trap in the final three detailed timings.
ORIGINAL_HEX = (
    "00ffffffffffff0009d1c87f01010101"
    "1d22010380361e782a6fb5a755529e27"
    "125054a56b80d1c081c081008180a9c0"
    "b30081bc0101023a801871382d40582c"
    "4500202f2100001e000000ff00454247"
    "37523031303531534c30000000fd0018"
    "f01eff3c000a202020202020000000fc"
    "005a4f57494520584c323534365801ff"
    "02033df14f9005040302011211133f07"
    "061f2040e200cf230907078301000067"
    "030c001000004467d85dc4017880006d"
    "1a0000020130f0e60000000000b49100"
    "a050c0783030203400202f2100001a5a"
    "8780a070384d4030203500202f210000"
    "1a0cdf80a07038404030403500202f21"
    "00001a0000000000000000000000006a"
)


def encode_manufacturer(name: str) -> bytes:
    if len(name) != 3 or not name.isalpha():
        raise ValueError("manufacturer must contain exactly three letters")
    a, b, c = (ord(ch.upper()) - 64 for ch in name)
    value = (a << 10) | (b << 5) | c
    return value.to_bytes(2, "big")


def descriptor_name(name: str) -> bytes:
    payload = (name[:12] + "\n").encode("ascii")[:13].ljust(13, b" ")
    return b"\x00\x00\x00\xfc\x00" + payload


def dtd_values(dtd: bytes) -> dict[str, float | int]:
    if len(dtd) != 18:
        raise ValueError("DTD must be 18 bytes")
    pixel_clock_hz = int.from_bytes(dtd[0:2], "little") * 10_000
    hactive = dtd[2] | ((dtd[4] & 0xF0) << 4)
    hblank = dtd[3] | ((dtd[4] & 0x0F) << 8)
    vactive = dtd[5] | ((dtd[7] & 0xF0) << 4)
    vblank = dtd[6] | ((dtd[7] & 0x0F) << 8)
    htotal = hactive + hblank
    vtotal = vactive + vblank
    refresh_hz = pixel_clock_hz / (htotal * vtotal)
    return {
        "pixel_clock_hz": pixel_clock_hz,
        "hactive": hactive,
        "vactive": vactive,
        "htotal": htotal,
        "vtotal": vtotal,
        "refresh_hz": refresh_hz,
    }


def fix_checksum(block: bytearray) -> None:
    if len(block) != 128:
        raise ValueError("EDID block must be 128 bytes")
    block[127] = (-sum(block[:127])) & 0xFF


def build_bridge(original: bytes) -> bytes:
    if len(original) != 256:
        raise ValueError("captured Zowie EDID must be exactly 256 bytes")
    edid = bytearray(original)

    dtd_60 = bytes(edid[54:72])
    dtd_1280_240 = bytes(edid[189:207])
    dtd_144 = bytes(edid[207:225])
    dtd_240 = bytes(edid[225:243])

    # Unique receiver identity prevents Windows from reusing the stock RK-UHD
    # mode cache. Product code and serial are intentionally little-endian.
    edid[8:10] = encode_manufacturer("RKP")
    edid[10:12] = (0x2401).to_bytes(2, "little")
    edid[12:16] = (240).to_bytes(4, "little")

    # Base block: preferred 1080p240, then known-safe 1080p60 fallback.
    edid[54:72] = dtd_240
    edid[72:90] = dtd_60
    edid[108:126] = descriptor_name("RK-1080P240")

    # CTA says one native detailed timing. Put 1080p240 first there as well.
    edid[189:207] = dtd_240
    edid[207:225] = dtd_144
    edid[225:243] = dtd_1280_240

    base = bytearray(edid[:128])
    extension = bytearray(edid[128:256])
    fix_checksum(base)
    fix_checksum(extension)
    edid[:128] = base
    edid[128:256] = extension
    return bytes(edid)


def validate(edid: bytes, *, require_bridge: bool) -> list[str]:
    errors: list[str] = []
    if len(edid) < 128 or len(edid) % 128:
        return [f"invalid EDID size: {len(edid)} bytes"]
    if edid[:8] != bytes.fromhex("00ffffffffffff00"):
        errors.append("invalid EDID header")
    for index in range(0, len(edid), 128):
        if sum(edid[index:index + 128]) & 0xFF:
            errors.append(f"block {index // 128} checksum is invalid")
    if edid[126] != len(edid) // 128 - 1:
        errors.append("extension count does not match file size")

    preferred = dtd_values(edid[54:72])
    if require_bridge:
        if preferred["hactive"] != 1920 or preferred["vactive"] != 1080:
            errors.append("preferred timing is not 1920x1080")
        if not 239.0 <= preferred["refresh_hz"] <= 241.0:
            errors.append("preferred timing is not approximately 240 Hz")
        if preferred["pixel_clock_hz"] != 571_000_000:
            errors.append("preferred timing is not the captured 571 MHz Zowie timing")
        fallback = dtd_values(edid[72:90])
        if fallback["hactive"] != 1920 or fallback["vactive"] != 1080:
            errors.append("first fallback timing is not 1920x1080")
        if not 59.9 <= fallback["refresh_hz"] <= 60.1:
            errors.append("first fallback timing is not approximately 60 Hz")
        if b"\xd8\x5d\xc4\x01\x78" not in edid[128:]:
            errors.append("HDMI Forum 600 MHz capability block is missing")
    return errors


def describe(edid: bytes) -> str:
    preferred = dtd_values(edid[54:72])
    fallback = dtd_values(edid[72:90])
    return (
        f"size={len(edid)} bytes; checksums=valid; "
        f"preferred={preferred['hactive']}x{preferred['vactive']} "
        f"{preferred['refresh_hz']:.3f} Hz "
        f"({preferred['pixel_clock_hz'] / 1_000_000:.3f} MHz); "
        f"fallback={fallback['hactive']}x{fallback['vactive']} "
        f"{fallback['refresh_hz']:.3f} Hz"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", type=Path, help="validate an existing bridge EDID")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "edid")
    args = parser.parse_args()

    if args.check:
        data = args.check.read_bytes()
        errors = validate(data, require_bridge=True)
        if errors:
            for error in errors:
                print(f"ERROR: {error}")
            return 1
        print(describe(data))
        return 0

    original = bytes.fromhex(ORIGINAL_HEX)
    original_errors = validate(original, require_bridge=False)
    if original_errors:
        raise SystemExit("captured source EDID failed validation: " + "; ".join(original_errors))
    bridge = build_bridge(original)
    bridge_errors = validate(bridge, require_bridge=True)
    if bridge_errors:
        raise SystemExit("generated bridge EDID failed validation: " + "; ".join(bridge_errors))

    args.output_dir.mkdir(parents=True, exist_ok=True)
    original_path = args.output_dir / "zowie-xl2546x-captured.bin"
    bridge_path = args.output_dir / "rk1080p240.bin"
    original_path.write_bytes(original)
    bridge_path.write_bytes(bridge)
    print(original_path)
    print(bridge_path)
    print(describe(bridge))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
