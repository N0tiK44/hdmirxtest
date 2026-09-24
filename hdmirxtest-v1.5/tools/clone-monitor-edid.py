#!/usr/bin/env python3
"""Create a conservative HDMI-RX EDID from the monitor on HDMI-TX.

The generated EDID keeps the downstream display identity and every explicit
timing that can be proved to fit the configured geometry, refresh and HDMI 2.0
pixel-clock ceilings. Unknown timing-bearing extensions are deliberately
omitted: the bridge fails closed instead of advertising an unverified mode.

The output is EDID 1.4 plus one CTA-861 extension (256 bytes), which matches the
format accepted by the Rockchip HDMI-RX EDID ioctl on the tested 6.1 kernel.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import zlib
from dataclasses import dataclass
from pathlib import Path


HEADER = bytes.fromhex("00ffffffffffff00")


def encode_manufacturer(name: str) -> bytes:
    if len(name) != 3 or not name.isalpha():
        raise ValueError("manufacturer must contain exactly three letters")
    a, b, c = (ord(ch.upper()) - 64 for ch in name)
    return ((a << 10) | (b << 5) | c).to_bytes(2, "big")


def descriptor_name(name: str) -> bytes:
    payload = (name[:12] + "\n").encode("ascii")[:13].ljust(13, b" ")
    return b"\x00\x00\x00\xfc\x00" + payload

# Established CTA modes no larger than 1920x1080 (plus the 1680-wide cinema
# modes). Their pixel clocks are safely below 600 MHz. Higher-resolution CTA
# modes are described explicitly below; unknown/new VICs are rejected.
LEGACY_CTA_VICS = (
    set(range(1, 35))
    | set(range(39, 86))
    | {108, 109, 110, 111, 112}
) - {10, 11, 12, 13, 25, 26, 27, 28}

# Rates for the safe CTA VIC ranges.  The only purpose of this table is the
# hard >240-Hz check; all currently safe CTA VICs are <=240 Hz.
CTA_VIC_RATE = {
    **{vic: 60.0 for vic in range(1, 17)},
    **{vic: 50.0 for vic in range(17, 32)},
    32: 24.0,
    33: 25.0,
    34: 30.0,
    39: 50.0,
    40: 100.0,
    41: 100.0,
    42: 100.0,
    43: 100.0,
    44: 100.0,
    45: 100.0,
    46: 120.0,
    47: 120.0,
    48: 120.0,
    49: 120.0,
    50: 120.0,
    51: 120.0,
    52: 200.0,
    53: 200.0,
    54: 200.0,
    55: 240.0,
    56: 240.0,
    57: 200.0,
    58: 200.0,
    59: 24.0,
    60: 25.0,
    61: 30.0,
    62: 120.0,
    63: 100.0,
    64: 100.0,
    **{vic: rate for vic, rate in zip(range(65, 72), (24, 25, 30, 50, 60, 100, 120))},
    **{vic: rate for vic, rate in zip(range(72, 79), (24, 25, 30, 50, 60, 100, 120))},
    **{vic: rate for vic, rate in zip(range(79, 86), (24, 25, 30, 50, 60, 100, 120))},
    108: 48.0,
    109: 48.0,
    110: 48.0,
    111: 48.0,
    112: 48.0,
}

# width, height, nominal refresh, pixel clock. This is the subset of CTA UHD
# and ultrawide timings that can fit an RGB 8-bit HDMI 2.0 link at <=600 MHz.
# 4096-wide DCI, 5K/8K and 4K100/120 modes remain excluded by policy.
CTA_HIGH_VIC_INFO = {
    10: (2880, 480, 60.0, 54_000_000),
    11: (2880, 480, 60.0, 54_000_000),
    12: (2880, 240, 60.0, 54_000_000),
    13: (2880, 240, 60.0, 54_000_000),
    25: (2880, 576, 50.0, 54_000_000),
    26: (2880, 576, 50.0, 54_000_000),
    27: (2880, 288, 50.0, 54_000_000),
    28: (2880, 288, 50.0, 54_000_000),
    35: (2880, 480, 60.0, 108_000_000),
    36: (2880, 480, 60.0, 108_000_000),
    37: (2880, 576, 50.0, 108_000_000),
    38: (2880, 576, 50.0, 108_000_000),
    86: (2560, 1080, 24.0, 99_000_000),
    87: (2560, 1080, 25.0, 90_000_000),
    88: (2560, 1080, 30.0, 118_800_000),
    89: (2560, 1080, 50.0, 185_625_000),
    90: (2560, 1080, 60.0, 198_000_000),
    91: (2560, 1080, 100.0, 371_250_000),
    92: (2560, 1080, 120.0, 495_000_000),
    93: (3840, 2160, 24.0, 297_000_000),
    94: (3840, 2160, 25.0, 297_000_000),
    95: (3840, 2160, 30.0, 297_000_000),
    96: (3840, 2160, 50.0, 594_000_000),
    97: (3840, 2160, 60.0, 594_000_000),
    103: (3840, 2160, 24.0, 297_000_000),
    104: (3840, 2160, 25.0, 297_000_000),
    105: (3840, 2160, 30.0, 297_000_000),
    106: (3840, 2160, 50.0, 594_000_000),
    107: (3840, 2160, 60.0, 594_000_000),
    113: (2560, 1080, 48.0, 198_000_000),
    114: (3840, 2160, 48.0, 594_000_000),
    116: (3840, 2160, 48.0, 594_000_000),
}


@dataclass(frozen=True)
class Limits:
    width: int = 3840
    height: int = 2160
    refresh: float = 240.0
    pixel_clock_hz: int = 600_000_000


def checksum_ok(block: bytes) -> bool:
    return len(block) == 128 and sum(block) % 256 == 0


def fix_checksum(block: bytearray) -> None:
    if len(block) != 128:
        raise ValueError("EDID block must contain exactly 128 bytes")
    block[127] = (-sum(block[:127])) & 0xFF


def dtd_values(dtd: bytes) -> tuple[int, int, float, int] | None:
    if len(dtd) != 18:
        raise ValueError("DTD must contain 18 bytes")
    clock_hz = int.from_bytes(dtd[0:2], "little") * 10_000
    if not clock_hz:
        return None
    width = dtd[2] | ((dtd[4] & 0xF0) << 4)
    hblank = dtd[3] | ((dtd[4] & 0x0F) << 8)
    height = dtd[5] | ((dtd[7] & 0xF0) << 4)
    vblank = dtd[6] | ((dtd[7] & 0x0F) << 8)
    htotal = width + hblank
    vtotal = height + vblank
    if not htotal or not vtotal:
        return width, height, 0.0, clock_hz
    refresh = clock_hz / (htotal * vtotal)
    if dtd[17] & 0x80:
        refresh *= 2.0
    return width, height, refresh, clock_hz


def dtd_allowed(dtd: bytes, limits: Limits) -> bool:
    values = dtd_values(dtd)
    if values is None:
        return False
    width, height, refresh, clock_hz = values
    return (
        0 < width <= limits.width
        and 0 < height <= limits.height
        and 0 < refresh <= limits.refresh + 0.25
        and clock_hz <= limits.pixel_clock_hz
    )


def standard_timing_values(pair: bytes, revision: int) -> tuple[int, int, int] | None:
    if pair in (b"\x01\x01", b"\x00\x00"):
        return None
    width = (pair[0] + 31) * 8
    ratio = pair[1] >> 6
    if ratio == 0:
        height = width if revision < 3 else round(width * 10 / 16)
    elif ratio == 1:
        height = round(width * 3 / 4)
    elif ratio == 2:
        height = round(width * 4 / 5)
    else:
        height = round(width * 9 / 16)
    refresh = (pair[1] & 0x3F) + 60
    return width, height, refresh


def sanitize_standard_timings(base: bytearray, limits: Limits) -> None:
    for offset in range(38, 54, 2):
        pair = bytes(base[offset:offset + 2])
        values = standard_timing_values(pair, base[19])
        if values is None:
            continue
        width, height, refresh = values
        if width > limits.width or height > limits.height or refresh > limits.refresh:
            base[offset:offset + 2] = b"\x01\x01"


def dummy_descriptor() -> bytes:
    return b"\x00\x00\x00\x10\x00" + bytes(13)


def descriptor_text(descriptor: bytes) -> str | None:
    if len(descriptor) != 18 or descriptor[:3] != b"\x00\x00\x00":
        return None
    if descriptor[3] not in (0xFC, 0xFF):
        return None
    return descriptor[5:18].split(b"\n", 1)[0].decode("ascii", "replace").strip()


def manufacturer_name(raw: bytes) -> str:
    value = int.from_bytes(raw, "big")
    chars = [(value >> 10) & 31, (value >> 5) & 31, value & 31]
    if any(value < 1 or value > 26 for value in chars):
        return "???"
    return "".join(chr(value + 64) for value in chars)


def identity(data: bytes) -> dict[str, object]:
    descriptors = [data[o:o + 18] for o in range(54, 126, 18)]
    texts = {
        d[3]: descriptor_text(d)
        for d in descriptors
        if len(d) == 18 and d[:3] == b"\x00\x00\x00" and d[3] in (0xFC, 0xFF)
    }
    return {
        "manufacturer": manufacturer_name(data[8:10]),
        "product_code": int.from_bytes(data[10:12], "little"),
        "serial_number": int.from_bytes(data[12:16], "little"),
        "monitor_name": texts.get(0xFC),
        "serial_text": texts.get(0xFF),
        "week": data[16],
        "year": 1990 + data[17],
    }


def sanitize_base(
    source: bytes, limits: Limits, identity_mode: str
) -> tuple[bytearray, list[bytes]]:
    base = bytearray(source[:128])
    sanitize_standard_timings(base, limits)

    if identity_mode == "isolated":
        # Recovery/troubleshooting identity.  Normal setup uses clone mode and
        # keeps the downstream manufacturer, product and serial bytes exactly.
        source_crc = zlib.crc32(source) & 0xFFFFFFFF
        base[8:10] = encode_manufacturer("RKP")
        base[10:12] = (0x1202).to_bytes(2, "little")
        base[12:16] = source_crc.to_bytes(4, "little")

    # EDID 1.4 digital-input bit depth 010 means 8 bits per primary colour.
    if base[20] & 0x80:
        base[20] = (base[20] & 0x8F) | 0x20

    descriptors = [bytes(base[o:o + 18]) for o in range(54, 126, 18)]
    allowed_dtds = [d for d in descriptors if dtd_allowed(d, limits)]
    # Do not carry range-limit, CVT/GTF, extra-standard-timing or arbitrary
    # monitor descriptors into the bridge: Windows could use them to infer a
    # mode that was not explicitly accepted by the cap audit.
    if identity_mode == "clone":
        # Preserve the monitor name and textual serial.  Range-limit, CVT/GTF
        # and extra-timing descriptors are deliberately excluded because they
        # let a source synthesize modes outside the audited set.
        monitor_descriptors = [
            d for d in descriptors
            if d[:3] == b"\x00\x00\x00" and d[3] in (0xFC, 0xFF)
        ]
    else:
        monitor_descriptors = [descriptor_name("RK-BRIDGE")]
    # Identity text has priority over secondary timings.  Keep at least the
    # real monitor name/serial when present; the preferred safe DTD remains in
    # the first slot and CTA can carry additional accepted timings.
    monitor_descriptors = monitor_descriptors[:2]
    packed = allowed_dtds[:4 - len(monitor_descriptors)] + monitor_descriptors
    packed += [dummy_descriptor()] * (4 - len(packed))
    for slot, descriptor in enumerate(packed):
        offset = 54 + slot * 18
        base[offset:offset + 18] = descriptor

    # Exactly one sanitized CTA extension is emitted below.
    base[126] = 1
    fix_checksum(base)
    return base, [d for d in packed if dtd_values(d) is not None]


def parse_cta_blocks(extension: bytes) -> tuple[list[bytes], list[bytes]]:
    if len(extension) != 128 or extension[0] != 0x02:
        return [], []
    end = extension[2]
    if end == 0:
        end = 127
    if end < 4 or end > 127:
        return [], []

    blocks: list[bytes] = []
    index = 4
    while index < end:
        length = extension[index] & 0x1F
        block_end = index + 1 + length
        if block_end > end:
            break
        blocks.append(bytes(extension[index:block_end]))
        index = block_end

    dtds: list[bytes] = []
    for offset in range(end, 127, 18):
        if offset + 18 > 127:
            break
        descriptor = bytes(extension[offset:offset + 18])
        if dtd_values(descriptor) is not None:
            dtds.append(descriptor)
    return blocks, dtds


def sanitize_video_block(block: bytes, limits: Limits) -> bytes | None:
    payload = block[1:]
    kept: list[int] = []
    for svd in payload:
        vic = svd & 0x7F
        if cta_vic_allowed(vic, limits):
            kept.append(svd)
    if not kept:
        return None
    return bytes([(2 << 5) | len(kept), *kept])


def cta_vic_allowed(vic: int, limits: Limits) -> bool:
    if vic in LEGACY_CTA_VICS:
        rate = CTA_VIC_RATE.get(vic)
        return rate is not None and rate <= limits.refresh + 0.25

    info = CTA_HIGH_VIC_INFO.get(vic)
    if info is None:
        return False
    width, height, refresh, pixel_clock_hz = info
    return (
        width <= limits.width
        and height <= limits.height
        and refresh <= limits.refresh + 0.25
        and pixel_clock_hz <= limits.pixel_clock_hz
    )


def sanitize_hdmi_vsdb(payload: bytes) -> bytes:
    # OUI + physical address are sufficient to identify an HDMI sink.  Keep a
    # capped Max TMDS clock, clear all deep-colour bits, and omit HDMI-VIC/3D
    # fields that could reintroduce hidden UHD modes.
    physical = payload[3:5].ljust(2, b"\x00")
    max_tmds = payload[6] if len(payload) >= 7 else 0
    max_tmds = min(max_tmds or 120, 120)
    return b"\x03\x0c\x00" + physical + b"\x00" + bytes([max_tmds])


def sanitize_hf_vsdb(payload: bytes) -> bytes:
    # HDMI Forum OUI, version 1, max 600 MHz, SCDC-present only.  This retains
    # the proven 571-MHz 1080p240 link while removing FRL, DSC, VRR and 4:2:0
    # deep-colour advertisement from newer monitor EDIDs.
    max_rate = payload[4] if len(payload) >= 5 else 120
    max_rate = min(max_rate or 120, 120)
    scdc = 0x80 if len(payload) >= 6 and payload[5] & 0x80 else 0x80
    return b"\xd8\x5d\xc4\x01" + bytes([max_rate, scdc, 0x00])


def sanitize_data_block(block: bytes, limits: Limits) -> bytes | None:
    tag = block[0] >> 5
    payload = block[1:]
    if tag == 2:
        return sanitize_video_block(block, limits)
    if tag in (1, 4):
        # The current zero-copy program forwards video only.  Do not advertise
        # an HDMI audio endpoint that the bridge does not reproduce.
        return None
    if tag == 3 and len(payload) >= 3:
        oui = payload[:3]
        if oui == b"\x03\x0c\x00":
            new_payload = sanitize_hdmi_vsdb(payload)
        elif oui == b"\xd8\x5d\xc4":
            new_payload = sanitize_hf_vsdb(payload)
        else:
            return None
        return bytes([(3 << 5) | len(new_payload)]) + new_payload
    if tag == 7:
        # Extended video, YCbCr 4:2:0, HDR, colourimetry, adaptive-sync and
        # vendor-video blocks are intentionally omitted for RGB 8-bit SDR.
        return None
    return None


def unique(items: list[bytes]) -> list[bytes]:
    result: list[bytes] = []
    seen: set[bytes] = set()
    for item in items:
        if item not in seen:
            result.append(item)
            seen.add(item)
    return result


def build_cta(source: bytes, limits: Limits, base_dtds: list[bytes]) -> tuple[bytearray, list[bytes]]:
    all_blocks: list[bytes] = []
    all_dtds: list[bytes] = []
    declared = min(source[126], (len(source) // 128) - 1)
    revision = 3
    basic_audio = False
    underscan = False

    for index in range(1, declared + 1):
        extension = source[index * 128:(index + 1) * 128]
        if not checksum_ok(extension) or extension[0] != 0x02:
            continue
        revision = max(revision, extension[1])
        underscan |= bool(extension[3] & 0x80)
        # Audio is intentionally not advertised by this video-only bridge.
        blocks, dtds = parse_cta_blocks(extension)
        for block in blocks:
            cleaned = sanitize_data_block(block, limits)
            if cleaned:
                all_blocks.append(cleaned)
        all_dtds.extend(d for d in dtds if dtd_allowed(d, limits))

    all_blocks = unique(all_blocks)
    all_dtds = unique([d for d in all_dtds if d not in base_dtds])

    # The collection must end at byte 123 or earlier so at least one full DTD
    # can still fit whenever a CTA-only timing exists.
    collection = bytearray()
    for block in all_blocks:
        if 4 + len(collection) + len(block) <= 123:
            collection.extend(block)

    cta = bytearray(128)
    cta[0] = 0x02
    cta[1] = min(revision, 3)
    cta[2] = 4 + len(collection)
    cta[3] = (0x80 if underscan else 0) | (0x40 if basic_audio else 0)
    cta[4:4 + len(collection)] = collection

    offset = cta[2]
    written_dtds: list[bytes] = []
    for descriptor in all_dtds:
        if offset + 18 > 127:
            break
        cta[offset:offset + 18] = descriptor
        written_dtds.append(descriptor)
        offset += 18

    cta[3] |= min(len(written_dtds), 0x0F)
    fix_checksum(cta)
    return cta, written_dtds


def validate_source(data: bytes) -> None:
    if len(data) < 128 or len(data) % 128:
        raise ValueError(f"invalid EDID size: {len(data)} bytes")
    if data[:8] != HEADER:
        raise ValueError("invalid EDID header")
    declared = data[126] + 1
    if declared > len(data) // 128:
        raise ValueError("EDID extension count exceeds file size")
    for index in range(declared):
        block = data[index * 128:(index + 1) * 128]
        if not checksum_ok(block):
            raise ValueError(f"EDID block {index} checksum is invalid")


def build_clone(source: bytes, limits: Limits, identity_mode: str) -> tuple[bytes, int, int]:
    validate_source(source)
    base, base_dtds = sanitize_base(source, limits, identity_mode)
    cta, cta_dtds = build_cta(source, limits, base_dtds)

    candidates = unique(base_dtds + cta_dtds)
    if candidates:
        preferred = max(
            candidates,
            key=lambda d: (
                dtd_values(d)[0] * dtd_values(d)[1],
                dtd_values(d)[2],
            ),
        )
        descriptors = [bytes(base[o:o + 18]) for o in range(54, 126, 18)]
        monitor_descriptors = [d for d in descriptors if dtd_values(d) is None]
        priority = {0xFC: 0, 0xFF: 1, 0xFD: 2}
        monitor_descriptors.sort(
            key=lambda d: priority.get(d[3] if len(d) >= 4 else 0, 9)
        )
        packed = [preferred]
        packed.extend(d for d in base_dtds if d != preferred)
        packed.extend(monitor_descriptors)
        packed = packed[:4] + [dummy_descriptor()] * max(0, 4 - len(packed))
        for slot, descriptor in enumerate(packed):
            offset = 54 + slot * 18
            base[offset:offset + 18] = descriptor
        fix_checksum(base)

    output = bytes(base + cta)
    validate_source(output)
    if not base_dtds and not cta_dtds:
        raise ValueError("monitor EDID contains no safe detailed timing at or below the ceiling")
    return output, len(base_dtds), len(cta_dtds)


def audit_clone(
    data: bytes, limits: Limits, source: bytes | None = None, identity_mode: str = "clone"
) -> None:
    validate_source(data)
    if len(data) != 256 or data[126] != 1 or data[128] != 0x02:
        raise ValueError("bridge EDID must be exactly two blocks with one CTA extension")
    if identity_mode == "isolated" and data[8:10] != encode_manufacturer("RKP"):
        raise ValueError("recovery EDID does not have the isolated RKP identity")
    if source is not None and identity_mode == "clone":
        if data[8:16] != source[8:16]:
            raise ValueError("bridge manufacturer/product/serial identity differs from sink")
        source_identity = identity(source)
        bridge_identity = identity(data)
        for key in ("monitor_name", "serial_text"):
            if source_identity[key] and bridge_identity[key] != source_identity[key]:
                raise ValueError(f"bridge {key} differs from sink")
    if data[20] & 0x70 != 0x20:
        raise ValueError("bridge EDID is not explicitly limited to 8 bpc")
    if data[131] & 0x30:
        raise ValueError("bridge CTA block still advertises YCbCr")
    if data[131] & 0x40:
        raise ValueError("video-only bridge still advertises basic audio")

    for offset in range(38, 54, 2):
        values = standard_timing_values(data[offset:offset + 2], data[19])
        if values and (
            values[0] > limits.width
            or values[1] > limits.height
            or values[2] > limits.refresh
        ):
            raise ValueError(f"unsafe standard timing remains: {values}")

    for offset in range(54, 126, 18):
        descriptor = data[offset:offset + 18]
        values = dtd_values(descriptor)
        if values is not None and not dtd_allowed(descriptor, limits):
            raise ValueError(f"unsafe base detailed timing remains at byte {offset}")
        if values is None and descriptor[:3] == b"\x00\x00\x00" and descriptor[3] not in (0x10, 0xFC, 0xFF):
            raise ValueError(f"unapproved base monitor descriptor remains at byte {offset}")

    blocks, dtds = parse_cta_blocks(data[128:256])
    for block in blocks:
        tag = block[0] >> 5
        if tag == 2:
            for svd in block[1:]:
                vic = svd & 0x7F
                if not cta_vic_allowed(vic, limits):
                    raise ValueError(f"unsafe or unknown CTA VIC remains: {vic}")
        elif tag == 7:
            raise ValueError("extended CTA capability block remains")
        elif tag in (1, 4):
            raise ValueError("video-only bridge still contains audio capability data")
    for descriptor in dtds:
        if not dtd_allowed(descriptor, limits):
            raise ValueError("unsafe CTA detailed timing remains")


def describe_timing(dtd: bytes) -> str:
    values = dtd_values(dtd)
    if values is None:
        return "descriptor"
    width, height, refresh, clock_hz = values
    return f"{width}x{height}@{refresh:.3f} ({clock_hz / 1_000_000:.3f} MHz)"


def advertised_detailed_timings(data: bytes) -> list[str]:
    descriptors = [data[o:o + 18] for o in range(54, 126, 18)]
    _, cta_dtds = parse_cta_blocks(data[128:256])
    return [describe_timing(dtd) for dtd in unique(
        [d for d in descriptors if dtd_values(d) is not None] + cta_dtds
    )]


def advertised_cta_vics(data: bytes) -> list[int]:
    blocks, _ = parse_cta_blocks(data[128:256])
    return [
        svd & 0x7F
        for block in blocks if block[0] >> 5 == 2
        for svd in block[1:]
    ]


def write_manifest(
    path: Path, source: bytes, output: bytes, limits: Limits, identity_mode: str
) -> None:
    source_identity = identity(source)
    bridge_identity = identity(output)
    manifest = {
        "schema": "hdmirxtest-edid-audit-v1",
        "identity_mode": identity_mode,
        "source_sha256": hashlib.sha256(source).hexdigest(),
        "bridge_sha256": hashlib.sha256(output).hexdigest(),
        "source_size": len(source),
        "bridge_size": len(output),
        "source_identity": source_identity,
        "bridge_identity": bridge_identity,
        "identity_bytes_preserved": output[8:16] == source[8:16],
        "ceiling": {
            "width": limits.width,
            "height": limits.height,
            "refresh_hz": limits.refresh,
            "pixel_clock_hz": limits.pixel_clock_hz,
        },
        "signal_policy": "RGB 8-bit SDR, fixed refresh",
        "not_advertised": [
            "audio", "DSC", "FRL", "HDR", "VRR/FreeSync",
            "YCbCr", "deep colour", "unknown timing extensions"
        ],
        "preferred_timing": describe_timing(output[54:72]),
        "advertised_detailed_timings": advertised_detailed_timings(output),
        "advertised_cta_vics": advertised_cta_vics(output),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", type=Path)
    parser.add_argument("--source", type=Path, help="source EDID for clone-identity audit")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--identity-mode", choices=("clone", "isolated"), default="clone")
    parser.add_argument("--max-width", type=int, default=3840)
    parser.add_argument("--max-height", type=int, default=2160)
    parser.add_argument("--max-refresh", type=float, default=240.0)
    parser.add_argument("--max-pixel-clock", type=int, default=600_000_000)
    args = parser.parse_args()

    limits = Limits(args.max_width, args.max_height, args.max_refresh, args.max_pixel_clock)

    if args.check:
        if args.input or args.output or args.manifest:
            parser.error("--check cannot be combined with --input, --output or --manifest")
        data = args.check.read_bytes()
        source = args.source.read_bytes() if args.source else None
        if source is not None:
            validate_source(source)
        audit_clone(data, limits, source, args.identity_mode)
        print(f"safe_bridge={args.check}")
        print(f"preferred={describe_timing(data[54:72])}")
        ident = identity(data)
        print(f"identity={ident['manufacturer']} product={ident['product_code']} name={ident['monitor_name']}")
        print("colour=RGB-8-bit checksums=valid")
        return 0

    if not args.input or not args.output:
        parser.error("--input and --output are required when not using --check")

    source = args.input.read_bytes()
    output, base_count, cta_count = build_clone(source, limits, args.identity_mode)
    audit_clone(output, limits, source if args.identity_mode == "clone" else None, args.identity_mode)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(output)
    if args.manifest:
        write_manifest(args.manifest, source, output, limits, args.identity_mode)

    preferred = describe_timing(output[54:72])
    print(f"source={args.input}")
    print(f"output={args.output}")
    print(f"ceiling={limits.width}x{limits.height}@{limits.refresh:g} RGB 8-bit SDR")
    print(f"preferred={preferred}")
    print(f"safe_detailed_timings={base_count + cta_count}")
    ident = identity(output)
    print(f"identity={ident['manufacturer']} product={ident['product_code']} name={ident['monitor_name']}")
    print("checksums=valid size=256")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
