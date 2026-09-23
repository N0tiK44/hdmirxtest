#!/usr/bin/env python3
"""Regression test for the HDMI 2.0 EDID intersection policy."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "clone-monitor-edid.py"
spec = importlib.util.spec_from_file_location("clone_monitor_edid", TOOL)
assert spec and spec.loader
edid = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = edid
spec.loader.exec_module(edid)


def synthetic_sink() -> bytes:
    source = bytearray((ROOT / "edid" / "recovery-source.bin").read_bytes())

    # Explicit 2560x1440p60 DTD at 241.50 MHz.
    dtd = bytearray(18)
    dtd[0:2] = (24150).to_bytes(2, "little")
    dtd[2], dtd[3], dtd[4] = 0x00, 0xA0, 0xA0
    dtd[5], dtd[6], dtd[7] = 0xA0, 0x29, 0x50
    dtd[17] = 0x1A
    source[54:72] = dtd
    source[126] = 1
    base = bytearray(source[:128])
    edid.fix_checksum(base)
    source[:128] = base

    # Keep 4K60/50/30/48 and 1080p60. Reject 4096x2160p60 and 4K120.
    cta = bytearray(128)
    cta[0], cta[1] = 0x02, 0x03
    vics = [0x80 | 97, 96, 95, 114, 16, 102, 117]
    video = bytes([(2 << 5) | len(vics), *vics])
    forum_payload = bytes.fromhex("d85dc401788000")
    forum = bytes([(3 << 5) | len(forum_payload)]) + forum_payload
    blocks = video + forum
    cta[2] = 4 + len(blocks)
    cta[3] = 1
    cta[4:4 + len(blocks)] = blocks
    # Explicit 1920x1080p60 DTD used by the restricted recovery-policy test.
    dtd1080 = bytearray(18)
    dtd1080[0:2] = (14850).to_bytes(2, "little")
    dtd1080[2], dtd1080[3], dtd1080[4] = 0x80, 0x18, 0x71
    dtd1080[5], dtd1080[6], dtd1080[7] = 0x38, 0x2D, 0x40
    dtd1080[17] = 0x1A
    cta[cta[2]:cta[2] + 18] = dtd1080
    edid.fix_checksum(cta)
    source[128:256] = cta
    return bytes(source)


def cta_vics(data: bytes) -> list[int]:
    return edid.advertised_cta_vics(data)


def main() -> int:
    source = synthetic_sink()
    limits = edid.Limits()
    bridge, _, _ = edid.build_clone(source, limits, "clone")
    edid.audit_clone(bridge, limits, source, "clone")

    kept = set(cta_vics(bridge))
    assert {16, 95, 96, 97, 114}.issubset(kept)
    assert 102 not in kept
    assert 117 not in kept
    assert any(timing.startswith("2560x1440@") for timing in
               edid.advertised_detailed_timings(bridge))

    recovery_limits = edid.Limits(1920, 1080, 60.0, 600_000_000)
    recovery, _, _ = edid.build_clone(source, recovery_limits, "isolated")
    edid.audit_clone(recovery, recovery_limits, None, "isolated")
    assert cta_vics(recovery) == [16]
    assert all(not timing.startswith(("2560x", "3840x", "4096x"))
               for timing in edid.advertised_detailed_timings(recovery))

    print("EDID policy self-test passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
