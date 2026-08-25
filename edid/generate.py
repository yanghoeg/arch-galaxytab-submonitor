#!/usr/bin/env python3
"""Generate a synthetic EDID 1.4 blob for the virtual sub-monitor output.

Timings follow VESA CVT 1.2 reduced-blanking version 2 (CVT-RB2), which is what
a modern tablet-class panel expects and which keeps the pixel clock as low as
the standard allows.

The blob deliberately carries a neutral LNX vendor id and a generic monitor
name -- never a real panel's PnP id or product string (see SECURITY.md).
"""

from __future__ import annotations

import argparse
import math
import sys

# ── CVT 1.2 reduced-blanking v2 constants ─────────────────────────────────────
CELL_GRAN = 8       # horizontal addressable must be a multiple of this
RB_MIN_V_BLANK = 460  # microseconds
RB_H_BLANK = 80     # pixels: 8 front porch + 32 sync + 40 back porch
RB_H_FRONT_PORCH = 8
RB_H_SYNC = 32
RB_V_FRONT_PORCH_MIN = 1
RB_V_SYNC = 8
RB_V_BACK_PORCH = 6

# A detailed timing descriptor stores the pixel clock as a 16-bit count of
# 10 kHz units, so this is a hard ceiling of the EDID format itself.
DTD_MAX_PIXEL_CLOCK_HZ = 65535 * 10_000

# Remaining detailed-timing-descriptor field widths, in bits. Overflowing any of
# these silently wraps and produces a blob that decodes to the wrong timing.
DTD_ACTIVE_MAX = 0xFFF    # 12 bits: horizontal/vertical addressable and blanking
DTD_H_PORCH_MAX = 0x3FF   # 10 bits: horizontal front porch and sync width
DTD_V_PORCH_MAX = 0x3F    # 6 bits: vertical front porch and sync width

# CTA-861 extension block. Without a Vendor-Specific Data Block carrying the
# HDMI IEEE OUI the kernel classifies the sink as DVI and refuses anything above
# 165 MHz, which prunes every mode this project cares about. Above 340 MHz the
# HDMI Forum VSDB is additionally required to declare the character rate.
CTA_TAG = 0x02
CTA_REVISION = 0x03
CTA_VDB_TAG = 2                         # Video Data Block (short video descriptors)
CTA_VSDB_TAG = 3
CTA_EXTENDED_TAG = 7
CTA_VCDB_EXT_TAG = 0                    # Video Capabilities Data Block
CTA_VIC_640x480p60 = 1                  # CTA-861 requires this mode to be listed
HDMI_IEEE_OUI = (0x03, 0x0C, 0x00)      # 00-0C-03, stored little-endian
HDMI_FORUM_OUI = (0xD8, 0x5D, 0xC4)     # C4-5D-D8, stored little-endian
HDMI_14_MAX_TMDS_HZ = 340_000_000
SOURCE_PHYSICAL_ADDRESS = (0x10, 0x00)  # CEC 1.0.0.0

# sRGB primaries and D65 white point, as CIE 1931 xy.
SRGB_CHROMA = {
    "red": (0.6400, 0.3300),
    "green": (0.3000, 0.6000),
    "blue": (0.1500, 0.0600),
    "white": (0.3127, 0.3290),
}

# Which of these a given machine can actually drive is platform-dependent: the
# display PLL cannot synthesise every pixel clock, and the gaps are not
# advertised anywhere. On a Raptor Lake-P host, 88 Hz (515.24 MHz) and 90 Hz
# (527.50 MHz) are pruned while 85, 95 and 100 Hz are accepted -- so a profile
# missing from a connector's "modes" file is not necessarily a bad blob.
# The connector's own modes file is the oracle:
#   cat /sys/class/drm/card*-<connector>/modes
PROFILES = {
    # name: (width, height, refresh_hz, diagonal_inches)
    "tabs9_60hz": (2960, 1848, 60, 14.6),
    "tabs9_85hz": (2960, 1848, 85, 14.6),
    "tabs9_95hz": (2960, 1848, 95, 14.6),
    "tabs9_100hz": (2960, 1848, 100, 14.6),
}


class Timing:
    """A CVT-RB2 mode, already rounded to what a DTD can actually encode."""

    def __init__(self, width: int, height: int, refresh: float):
        if width % CELL_GRAN:
            raise ValueError(
                f"horizontal addressable {width} is not a multiple of {CELL_GRAN}"
            )
        if width <= 0 or height <= 0 or refresh <= 0:
            raise ValueError("width, height and refresh must all be positive")

        self.h_active = width
        self.v_active = height
        self.refresh_requested = float(refresh)

        # Estimate the line period left over once the fixed vertical blanking
        # interval is subtracted, then size the VBI in whole lines.
        h_period_est = (1_000_000.0 / refresh - RB_MIN_V_BLANK) / height
        if h_period_est <= 0:
            raise ValueError(
                f"{width}x{height}@{refresh} leaves no time for active video"
            )

        vbi_lines = math.floor(RB_MIN_V_BLANK / h_period_est) + 1
        min_vbi = RB_V_FRONT_PORCH_MIN + RB_V_SYNC + RB_V_BACK_PORCH
        vbi_lines = max(vbi_lines, min_vbi)

        self.h_total = width + RB_H_BLANK
        self.v_total = height + vbi_lines

        # CVT-RB2 pins the sync and back porch and lets the front porch absorb
        # whatever is left of the blanking interval.
        self.h_front_porch = RB_H_FRONT_PORCH
        self.h_sync = RB_H_SYNC
        self.v_sync = RB_V_SYNC
        self.v_front_porch = vbi_lines - RB_V_SYNC - RB_V_BACK_PORCH
        self.v_back_porch = RB_V_BACK_PORCH
        if self.v_front_porch > DTD_V_PORCH_MAX:
            # The descriptor only has 6 bits for the front porch. Park the
            # overflow in the back porch instead: the blanking interval, and so
            # the pixel clock and refresh rate, are unchanged -- only where the
            # sync pulse sits inside it moves.
            overflow = self.v_front_porch - DTD_V_PORCH_MAX
            self.v_front_porch = DTD_V_PORCH_MAX
            self.v_back_porch += overflow

        ideal_clock = self.h_total * self.v_total * refresh
        # Round to the DTD's 10 kHz grid so the blob describes exactly the clock
        # the driver will program -- no silent drift between the two.
        self.pixel_clock = int(round(ideal_clock / 10_000)) * 10_000
        if self.pixel_clock > DTD_MAX_PIXEL_CLOCK_HZ:
            raise ValueError(
                f"{width}x{height}@{refresh:g} needs a "
                f"{ideal_clock / 1e6:.3f} MHz pixel clock, but an EDID detailed "
                f"timing descriptor cannot encode more than "
                f"{DTD_MAX_PIXEL_CLOCK_HZ / 1e6:.2f} MHz.\n"
                f"Lower the refresh rate or the resolution."
            )

    @property
    def h_blank(self) -> int:
        return self.h_total - self.h_active

    @property
    def v_blank(self) -> int:
        return self.v_total - self.v_active

    @property
    def refresh_actual(self) -> float:
        return self.pixel_clock / (self.h_total * self.v_total)

    @property
    def h_rate_khz(self) -> float:
        return self.pixel_clock / self.h_total / 1000.0


def physical_size_mm(width: int, height: int, diagonal_in: float) -> tuple[int, int]:
    """Physical panel size in mm, derived from pixel aspect and diagonal."""
    diag_mm = diagonal_in * 25.4
    pixel_diag = math.hypot(width, height)
    return (
        round(diag_mm * width / pixel_diag),
        round(diag_mm * height / pixel_diag),
    )


def encode_manufacturer(pnp_id: str) -> bytes:
    """Pack a 3-letter PnP id into EDID's 5-bit-per-letter big-endian form."""
    if len(pnp_id) != 3 or not pnp_id.isalpha():
        raise ValueError(f"PnP id must be exactly 3 letters, got {pnp_id!r}")
    packed = 0
    for letter in pnp_id.upper():
        packed = (packed << 5) | (ord(letter) - ord("A") + 1)
    return packed.to_bytes(2, "big")


def encode_chromaticity() -> bytes:
    """Bytes 25..34: 10-bit CIE xy coordinates, low bits gathered up front."""
    coords = []
    for key in ("red", "green", "blue", "white"):
        x, y = SRGB_CHROMA[key]
        coords.append(min(1023, round(x * 1024)))
        coords.append(min(1023, round(y * 1024)))

    low_rg = (
        ((coords[0] & 0x3) << 6)
        | ((coords[1] & 0x3) << 4)
        | ((coords[2] & 0x3) << 2)
        | (coords[3] & 0x3)
    )
    low_bw = (
        ((coords[4] & 0x3) << 6)
        | ((coords[5] & 0x3) << 4)
        | ((coords[6] & 0x3) << 2)
        | (coords[7] & 0x3)
    )
    return bytes([low_rg, low_bw] + [c >> 2 for c in coords])


def _cta_data_block(tag: int, payload: bytes) -> bytes:
    if len(payload) > 31:
        raise ValueError("a CTA data block payload cannot exceed 31 bytes")
    return bytes([(tag << 5) | len(payload)]) + payload


def _hdmi_vsdb(t: Timing) -> bytes:
    """HDMI 1.4b VSDB. Its OUI is what makes the kernel treat this as HDMI."""
    max_tmds_mhz = min(t.pixel_clock, HDMI_14_MAX_TMDS_HZ) // 1_000_000
    payload = (
        bytes(HDMI_IEEE_OUI)
        + bytes(SOURCE_PHYSICAL_ADDRESS)
        + bytes([0x00])              # no deep colour, not DVI dual-link
        + bytes([max_tmds_mhz // 5])  # Max_TMDS_Clock, 5 MHz units
    )
    return _cta_data_block(CTA_VSDB_TAG, payload)


def _hdmi_forum_vsdb(t: Timing) -> bytes:
    """HDMI Forum VSDB, needed to declare a character rate above 340 MHz."""
    rate = -(-t.pixel_clock // 5_000_000)  # ceil to 5 MHz units
    if rate > 0xFF:
        raise ValueError(
            f"{t.pixel_clock / 1e6:.2f} MHz exceeds what an HDMI Forum VSDB "
            f"can declare ({0xFF * 5} MHz)"
        )
    payload = (
        bytes(HDMI_FORUM_OUI)
        + bytes([0x01])   # version
        + bytes([rate])   # Max_TMDS_Character_Rate, 5 MHz units
        + bytes([0x00])   # SCDC/scrambling flags, filled in by the caller
        + bytes([0x00])   # no YCbCr 4:2:0 deep colour
    )
    return _cta_data_block(CTA_VSDB_TAG, payload)


def _video_data_block() -> bytes:
    """CTA-861 requires 640x480p60 (VIC 1) to be advertised somewhere."""
    return _cta_data_block(CTA_VDB_TAG, bytes([CTA_VIC_640x480p60]))


def _video_capabilities_block() -> bytes:
    """VCDB: selectable RGB quantization range, everything always underscanned."""
    qs = 0x40                     # RGB Quantization Range is selectable
    scan = (0b10 << 4) | (0b10 << 2) | 0b10   # S_PT / S_IT / S_CE: underscanned
    return _cta_data_block(
        CTA_EXTENDED_TAG, bytes([CTA_VCDB_EXT_TAG, qs | scan])
    )


def cta_extension_block(t: Timing, *, scdc: bool) -> bytes:
    blocks = [_video_data_block(), _video_capabilities_block(), _hdmi_vsdb(t)]
    if t.pixel_clock > HDMI_14_MAX_TMDS_HZ:
        hf = bytearray(_hdmi_forum_vsdb(t))
        if scdc:
            # SCDC_Present | LTE_340Mcsc_Scramble. Spec-correct for >340 MHz,
            # but a forced connector has no sink to answer SCDC over I2C.
            hf[6] = 0x80 | 0x10
        blocks.append(bytes(hf))

    data = b"".join(blocks)
    blk = bytearray(128)
    blk[0] = CTA_TAG
    blk[1] = CTA_REVISION
    blk[3] = 0x80                 # underscan supported; no audio, no native DTDs
    blk[4:4 + len(data)] = data
    blk[2] = 4 + len(data)        # where DTDs would start
    blk[127] = (256 - sum(blk[:127]) % 256) % 256
    return bytes(blk)


def detailed_timing_descriptor(t: Timing, size_mm: tuple[int, int]) -> bytes:
    h_mm, v_mm = size_mm
    clock_10khz = t.pixel_clock // 10_000

    for label, value, limit in (
        ("horizontal addressable", t.h_active, DTD_ACTIVE_MAX),
        ("horizontal blanking", t.h_blank, DTD_ACTIVE_MAX),
        ("vertical addressable", t.v_active, DTD_ACTIVE_MAX),
        ("vertical blanking", t.v_blank, DTD_ACTIVE_MAX),
        ("horizontal front porch", t.h_front_porch, DTD_H_PORCH_MAX),
        ("horizontal sync width", t.h_sync, DTD_H_PORCH_MAX),
        ("vertical front porch", t.v_front_porch, DTD_V_PORCH_MAX),
        ("vertical sync width", t.v_sync, DTD_V_PORCH_MAX),
    ):
        if value > limit:
            raise ValueError(
                f"{label} is {value}, which does not fit the descriptor's "
                f"maximum of {limit}"
            )

    return bytes(
        [
            clock_10khz & 0xFF,
            (clock_10khz >> 8) & 0xFF,
            t.h_active & 0xFF,
            t.h_blank & 0xFF,
            ((t.h_active >> 8) << 4) | (t.h_blank >> 8),
            t.v_active & 0xFF,
            t.v_blank & 0xFF,
            ((t.v_active >> 8) << 4) | (t.v_blank >> 8),
            t.h_front_porch & 0xFF,
            t.h_sync & 0xFF,
            ((t.v_front_porch & 0xF) << 4) | (t.v_sync & 0xF),
            ((t.h_front_porch >> 8) << 6)
            | ((t.h_sync >> 8) << 4)
            | (((t.v_front_porch >> 4) & 0x3) << 2)
            | ((t.v_sync >> 4) & 0x3),
            h_mm & 0xFF,
            v_mm & 0xFF,
            ((h_mm >> 8) << 4) | (v_mm >> 8),
            0x00,  # horizontal border
            0x00,  # vertical border
            # Digital separate sync, H positive / V negative -- the CVT-RB
            # signature that tells the sink these are reduced-blanking timings.
            0x1A,
        ]
    )


def range_limits_descriptor(t: Timing) -> bytes:
    v_rate = t.refresh_actual
    return bytes(
        [0x00, 0x00, 0x00, 0xFD, 0x00]
        + [
            max(1, math.floor(v_rate) - 1),         # min vertical rate, Hz
            math.ceil(v_rate) + 1,                  # max vertical rate, Hz
            max(1, math.floor(t.h_rate_khz) - 1),   # min horizontal rate, kHz
            math.ceil(t.h_rate_khz) + 1,            # max horizontal rate, kHz
            math.ceil(t.pixel_clock / 10_000_000),  # max pixel clock, 10 MHz
            0x01,                                   # bare limits, no GTF/CVT formula
        ]
        + [0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20]
    )


def string_descriptor(tag: int, text: str) -> bytes:
    payload = text.encode("ascii")[:13]
    if len(payload) < 13:
        payload += b"\x0a" + b"\x20" * (12 - len(payload))
    return bytes([0x00, 0x00, 0x00, tag, 0x00]) + payload


def dummy_descriptor() -> bytes:
    return bytes([0x00, 0x00, 0x00, 0x10, 0x00]) + bytes(13)


def build_edid(t: Timing, *, pnp_id: str, product_code: int, name: str,
               year: int, size_mm: tuple[int, int],
               extensions: list[bytes]) -> bytes:
    h_mm, v_mm = size_mm
    edid = bytearray()

    edid += bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])  # header
    edid += encode_manufacturer(pnp_id)
    edid += product_code.to_bytes(2, "little")
    edid += (0).to_bytes(4, "little")   # serial number: none, keeps blobs identical
    edid += bytes([0x00])               # week: unspecified
    edid += bytes([year - 1990])
    edid += bytes([0x01, 0x04])         # EDID 1.4

    # Digital input, 8 bits per colour, HDMI-a signalling.
    edid += bytes([0x80 | (0b010 << 4) | 0b0010])
    edid += bytes([round(h_mm / 10), round(v_mm / 10)])
    edid += bytes([120])                # gamma 2.20 -> 2.20*100-100
    # Continuous-frequency display, sRGB colour space, preferred timing carries
    # the native pixel format and refresh rate.
    edid += bytes([0x08 | 0x04 | 0x02 | 0x01])

    edid += encode_chromaticity()
    edid += bytes([0x00, 0x00, 0x00])   # no established timings
    edid += b"\x01\x01" * 8             # no standard timings

    edid += detailed_timing_descriptor(t, size_mm)
    edid += range_limits_descriptor(t)
    edid += string_descriptor(0xFC, name)
    edid += dummy_descriptor()

    edid += bytes([len(extensions)])
    edid += bytes([(256 - sum(edid) % 256) % 256])

    assert len(edid) == 128, f"the base block must be 128 bytes, built {len(edid)}"
    return bytes(edid) + b"".join(extensions)


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("--output", required=True, help="path to write the .bin blob to")
    p.add_argument(
        "--profile",
        choices=sorted(PROFILES),
        help="named mode; overrides --width/--height/--refresh/--diagonal",
    )
    p.add_argument("--width", type=int, default=2960)
    p.add_argument("--height", type=int, default=1848)
    p.add_argument("--refresh", type=float, default=60.0)
    p.add_argument("--diagonal", type=float, default=14.6,
                   help="panel diagonal in inches, used for the physical size")
    p.add_argument("--pnp-id", default="LNX",
                   help="3-letter vendor id (default: LNX, a neutral placeholder)")
    p.add_argument("--product-code", type=int, default=0x0001)
    p.add_argument("--year", type=int, default=2026)
    p.add_argument("--name", default="Virtual Sub",
                   help="monitor name, max 13 ASCII characters")
    p.add_argument("--no-cta", action="store_true",
                   help="omit the CTA-861 block; the sink is then treated as "
                        "DVI and capped at 165 MHz")
    p.add_argument("--scdc", action="store_true",
                   help="declare SCDC and scrambling in the HDMI Forum VSDB "
                        "(spec-correct above 340 MHz, but a forced connector "
                        "has no sink to answer SCDC)")
    return p.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    if args.profile:
        width, height, refresh, diagonal = PROFILES[args.profile]
    else:
        width, height, refresh, diagonal = (
            args.width, args.height, args.refresh, args.diagonal,
        )

    try:
        timing = Timing(width, height, refresh)
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    size_mm = physical_size_mm(width, height, diagonal)
    try:
        extensions = [] if args.no_cta else [
            cta_extension_block(timing, scdc=args.scdc)
        ]
        blob = build_edid(
            timing,
            pnp_id=args.pnp_id,
            product_code=args.product_code,
            name=args.name,
            year=args.year,
            size_mm=size_mm,
            extensions=extensions,
        )
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    with open(args.output, "wb") as fh:
        fh.write(blob)

    print(f"Wrote {len(blob)} bytes to {args.output}")
    print(f"  Mode          {width}x{height} @ {timing.refresh_actual:.3f} Hz "
          f"(requested {timing.refresh_requested:g})")
    print(f"  Pixel clock   {timing.pixel_clock / 1e6:.2f} MHz")
    print(f"  Horizontal    {timing.h_active} active, "
          f"{timing.h_front_porch} front, {timing.h_sync} sync, "
          f"{timing.h_blank - timing.h_front_porch - timing.h_sync} back, "
          f"{timing.h_total} total")
    print(f"  Vertical      {timing.v_active} active, "
          f"{timing.v_front_porch} front, {timing.v_sync} sync, "
          f"{timing.v_back_porch} back, {timing.v_total} total")
    print(f"  H rate        {timing.h_rate_khz:.3f} kHz")
    print(f"  Physical      {size_mm[0]}x{size_mm[1]} mm")
    if extensions:
        hf = " + HDMI Forum VSDB" if timing.pixel_clock > HDMI_14_MAX_TMDS_HZ else ""
        print(f"  Extension     CTA-861 with HDMI VSDB{hf}")
    else:
        print("  Extension     none (sink will be treated as DVI, 165 MHz cap)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
