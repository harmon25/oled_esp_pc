#!/usr/bin/env python3
"""
Convert a TTF/OTF/BDF/PCF font to AtomGL ufontlib IFF format (.uff).

Usage: python3 tools/gen_font.py <font_path> <size_px> <output.uff>

The generated binary can be registered with the display port:
  AVMPort.call(display, {:register_font, :my_font, font_binary})
Then use :my_font in {:text, x, y, :my_font, fg, bg, text} items.

For BDF/PCF sources the pixel_size argument is ignored (the font has a
fixed embedded strike), but you still need to pass it for CLI compatibility.

Pixel format: 4bpp, 2 pixels per byte.
  byte[n] = (pixel[2n] & 0xF) | ((pixel[2n+1] & 0xF) << 4)
  0x0 = background, 0xF = foreground (white)

IFF layout:
  FORM (4) | iff_size BE (4) | uFL0 (4)
  uFH0 chunk: interval_count(u32) | compressed(u8) | advance_y(u16) | ascender(u16) | descender(u16)
  uFP0 chunk: EpdGlyph[] (18 bytes each, packed LE)
  uFI0 chunk: EpdUnicodeInterval[] (12 bytes each, packed LE)
  uFB0 chunk: raw 4bpp glyph bitmaps
"""

import sys
import struct
import math
import freetype


CHARS = range(0x20, 0x7F)  # printable ASCII


def align4(n):
    return ((n + 3) // 4) * 4


def make_chunk(name: bytes, data: bytes) -> bytes:
    size = len(data)
    total = align4(size + 8)
    padding = bytes(total - 8 - size)
    return name + struct.pack(">I", size) + data + padding


def is_bitmap_font(face):
    """True if the face is from a BDF/PCF file with fixed strikes."""
    return face.num_fixed_sizes > 0


def render_glyph_1bit(face):
    """Return (pixels_4bpp_bytes, width, height, advance_x, left, top).

    Uses FT_LOAD_RENDER | FT_LOAD_MONOCHROME | FT_LOAD_TARGET_MONO to get a
    clean 1-bit, pixel-hinted bitmap from FreeType. Each set bit becomes nibble
    0xF (white), each clear bit becomes nibble 0x0 (black/transparent).

    This avoids the anti-aliased grayscale path where thin strokes at small
    sizes quantize to zero and disappear on a 1-bit OLED.
    """
    g = face.glyph
    bm = g.bitmap
    width = bm.width
    height = bm.rows
    advance_x = round(g.advance.x / 64)
    left = g.bitmap_left
    top = g.bitmap_top

    byte_width = (width + 1) // 2
    buf = bytearray(byte_width * height)

    pitch = abs(bm.pitch)

    # BDF/PCF or mono-loaded TTF: FreeType returns FT_PIXEL_MODE_MONO
    # (1-bit packed, MSB first per byte).  If for some reason a TTF face
    # returns 8bpp gray, fall back to thresholding at the midpoint.
    if bm.pixel_mode == freetype.FT_PIXEL_MODE_MONO:
        for y in range(height):
            for x in range(width):
                byte = bm.buffer[y * pitch + x // 8]
                bit = byte & (0x80 >> (x & 7))
                nibble = 0xF if bit else 0x0
                idx = y * byte_width + x // 2
                if x % 2 == 0:
                    buf[idx] |= nibble
                else:
                    buf[idx] |= (nibble << 4)
    else:
        # Fallback for non-mono bitmaps (should not happen with our flags)
        for y in range(height):
            for x in range(width):
                gray = bm.buffer[y * pitch + x]
                nibble = 0xF if gray >= 128 else 0x0
                idx = y * byte_width + x // 2
                if x % 2 == 0:
                    buf[idx] |= nibble
                else:
                    buf[idx] |= (nibble << 4)

    return bytes(buf), width, height, advance_x, left, top


def convert(font_path, pixel_size, output_path):
    face = freetype.Face(font_path)

    if is_bitmap_font(face):
        # BDF/PCF: select the embedded strike (ignore pixel_size).
        # FreeType already has the correct metrics loaded; just pick the
        # first (and usually only) available size.
        face.select_size(0)
        print(f"  bitmap font strike selected (ignoring size={pixel_size})")
    else:
        face.set_pixel_sizes(0, pixel_size)

    m = face.size
    ascender  = math.ceil(m.ascender  / 64)
    descender = math.ceil(-m.descender / 64)   # positive magnitude
    advance_y = ascender + descender

    print(f"  ascender={ascender}  descender={descender}  advance_y={advance_y}")

    glyph_structs = bytearray()   # uFP0
    bitmap_data   = bytearray()   # uFB0

    load_flags = (
        freetype.FT_LOAD_RENDER |
        freetype.FT_LOAD_MONOCHROME |
        freetype.FT_LOAD_TARGET_MONO
    )

    for cp in CHARS:
        face.load_char(cp, load_flags)
        pix, w, h, adv_x, left, top = render_glyph_1bit(face)

        data_offset = len(bitmap_data)
        bitmap_data.extend(pix)

        # EpdGlyph (packed, 18 bytes): u16 w, h, adv_x; i16 left, top; u32 comp_size, data_offset
        glyph_structs.extend(struct.pack("<HHHhhII", w, h, adv_x, left, top, 0, data_offset))

    # uFH0: serialized_ufont (packed, 11 bytes)
    header = struct.pack("<IBHHH",
        1,           # interval_count
        0,           # compressed = false
        advance_y,
        ascender,
        descender,
    )

    # uFI0: one interval covering all CHARS
    interval = struct.pack("<III", min(CHARS), max(CHARS), 0)  # offset=0

    h_chunk  = make_chunk(b"uFH0", header)
    p_chunk  = make_chunk(b"uFP0", bytes(glyph_structs))
    i_chunk  = make_chunk(b"uFI0", interval)
    b_chunk  = make_chunk(b"uFB0", bytes(bitmap_data))

    body = h_chunk + p_chunk + i_chunk + b_chunk

    # Standard IFF: size field = total_file_size - 8
    iff_size = 4 + len(body)   # "uFL0"(4) + body
    iff = b"FORM" + struct.pack(">I", iff_size) + b"uFL0" + body

    with open(output_path, "wb") as f:
        f.write(iff)

    print(f"  {len(CHARS)} glyphs, {len(bitmap_data)} bitmap bytes → {len(iff)} bytes → {output_path}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <font_path> <size_px> <output.uff>")
        sys.exit(1)
    convert(sys.argv[1], int(sys.argv[2]), sys.argv[3])
