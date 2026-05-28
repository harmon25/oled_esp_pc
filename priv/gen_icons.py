#!/usr/bin/env python3
"""
priv/gen_icons.py — Regenerate weather icon .rgba binaries from Dhole XBM source.

Converts 16x16 XBM (X11 format, LSB-first bit order) to RGBA8888 raw binaries.
Writes weather .rgba files to priv/icons/ and preview PNGs (8x scaled, black
background) for all icons (weather + utility) to icon_previews/ (project root,
outside priv/ so they are not packed into the firmware).
"""

import os
import struct
from collections import deque
from pathlib import Path

try:
    from PIL import Image
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

# 16x16 XBM data from https://github.com/Dhole/weather-pixel-icons (CC BY-SA 4.0)
# Keyed by the base name we use in priv/icons/weather_<name>.rgba
XBM_DATA = {
    "sun": bytes([
        0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x08, 0x21, 0x10, 0x10, 0x80, 0x03,
        0x40, 0x04, 0x20, 0x08, 0x2E, 0xE8, 0x20, 0x08, 0x40, 0x04, 0x80, 0x03,
        0x10, 0x10, 0x08, 0x21, 0x00, 0x01, 0x00, 0x01,
    ]),
    "cloud": bytes([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x03, 0x20, 0x04,
        0x20, 0x08, 0x18, 0x10, 0x04, 0x20, 0x02, 0x20, 0x02, 0x20, 0x04, 0x10,
        0xF8, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]),
    "cloud_sun": bytes([
        0x00, 0x00, 0x00, 0x08, 0x00, 0x5D, 0x00, 0x22, 0xC0, 0x43, 0x20, 0xC4,
        0x20, 0x48, 0x18, 0x30, 0x04, 0x20, 0x02, 0x20, 0x02, 0x20, 0x04, 0x10,
        0xF8, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]),
    "rain1": bytes([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x03, 0x20, 0x04,
        0x20, 0x08, 0x18, 0x10, 0x04, 0x20, 0x02, 0x20, 0x42, 0x21, 0x44, 0x11,
        0x28, 0x0D, 0xA0, 0x00, 0x80, 0x00, 0x00, 0x00,
    ]),
    "lightning": bytes([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x03, 0x20, 0x04,
        0x20, 0x08, 0x18, 0x10, 0x04, 0x20, 0x02, 0x20, 0x82, 0x23, 0x84, 0x11,
        0xB8, 0x0D, 0x00, 0x01, 0x80, 0x00, 0x80, 0x00,
    ]),
    "snow": bytes([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x03, 0x20, 0x04,
        0x20, 0x08, 0x18, 0x10, 0x04, 0x20, 0x02, 0x20, 0x82, 0x20, 0x44, 0x11,
        0x90, 0x04, 0x28, 0x0A, 0x10, 0x04, 0x00, 0x00,
    ]),
    "wind": bytes([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x08, 0x00, 0x28, 0xFC, 0x47,
        0x00, 0x40, 0xFE, 0x3F, 0x00, 0x00, 0xFC, 0x0F, 0x00, 0x10, 0x00, 0x10,
        0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]),
    "moon": bytes([
        0x00, 0x00, 0xE0, 0x00, 0x90, 0x00, 0x48, 0x00, 0x24, 0x00, 0x22, 0x00,
        0x22, 0x00, 0x22, 0x00, 0x22, 0x60, 0x42, 0x50, 0x82, 0x4F, 0x04, 0x20,
        0x08, 0x10, 0x10, 0x08, 0xE0, 0x07, 0x00, 0x00,
    ]),
    "rain2": bytes([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x03, 0x20, 0x04,
        0x20, 0x08, 0x18, 0x10, 0x04, 0x20, 0x02, 0x20, 0xA2, 0x2A, 0x94, 0x0A,
        0x50, 0x0A, 0x50, 0x09, 0x40, 0x01, 0x00, 0x00,
    ]),
    "rain_lightning": bytes([
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x03, 0x20, 0x04,
        0x20, 0x08, 0x18, 0x10, 0x04, 0x20, 0x02, 0x20, 0xA2, 0x2E, 0x94, 0x06,
        0x50, 0x06, 0x50, 0x04, 0x40, 0x02, 0x00, 0x02,
    ]),
}

WHITE_OPAQUE = struct.pack("<I", 0xFFFFFFFF)
TRANSPARENT = struct.pack("<I", 0x00000000)


def xbm_to_grid(data: bytes, width: int = 16, height: int = 16) -> list[list[bool]]:
    """Unpack XBM bit-packed data (LSB-first, row-major) into a bool grid."""
    bpr = (width + 7) // 8
    grid = []
    for y in range(height):
        row = []
        for x in range(width):
            byte = data[y * bpr + x // 8]
            mask = 1 << (x % 8)
            row.append(bool(byte & mask))
        grid.append(row)
    return grid


def direct_convert(grid: list[list[bool]]) -> list[list[bool]]:
    """Return the grid as-is (direct XBM to RGBA, no fill)."""
    return grid


def grid_to_rgba(grid: list[list[bool]]) -> bytes:
    """Convert a bool grid to little-endian RGBA8888 binary."""
    rows = []
    for row in grid:
        for pixel in row:
            rows.append(WHITE_OPAQUE if pixel else TRANSPARENT)
    return b"".join(rows)


def write_rgba(name: str, grid: list[list[bool]], out_dir: Path):
    path = out_dir / f"weather_{name}.rgba"
    path.write_bytes(grid_to_rgba(grid))
    print(f"  wrote {path} ({len(grid) * len(grid[0]) * 4} bytes)")


def write_preview(filename: str, grid: list[list[bool]], out_dir: Path):
    if not PIL_AVAILABLE:
        return
    # Local import avoids unbound-name warnings when Pillow is absent
    from PIL import Image as PilImage  # noqa: F811
    h = len(grid)
    w = len(grid[0])
    # Scale up 8x for visibility; black background matches OLED rendering
    scale = 8
    img = PilImage.new("RGBA", (w * scale, h * scale), (0, 0, 0, 255))
    for y, row in enumerate(grid):
        for x, pixel in enumerate(row):
            color = (255, 255, 255, 255) if pixel else (0, 0, 0, 255)
            for dy in range(scale):
                for dx in range(scale):
                    img.putpixel((x * scale + dx, y * scale + dy), color)
    path = out_dir / f"{filename}.png"
    img.save(path)
    print(f"  wrote {path}")


def rgba_to_grid(data: bytes, width: int = 16, height: int = 16) -> list[list[bool]]:
    """Decode an RGBA8888 binary back to a bool grid (any non-zero alpha = True)."""
    grid = []
    for y in range(height):
        row = []
        for x in range(width):
            offset = (y * width + x) * 4
            a = data[offset + 3]
            row.append(a > 0)
        grid.append(row)
    return grid


def write_utility_previews(icons_dir: Path, preview_dir: Path):
    """Generate preview PNGs for the 4 pre-built utility .rgba icons."""
    utility_names = ["utility_wifi1", "utility_temperature", "utility_humidity", "utility_clock"]
    for name in utility_names:
        path = icons_dir / f"{name}.rgba"
        if not path.exists():
            print(f"  skipping {path} (not found)")
            continue
        data = path.read_bytes()
        grid = rgba_to_grid(data)
        print(f"\n{name}:")
        write_preview(name, grid, preview_dir)


def main():
    script_dir = Path(__file__).parent.resolve()
    icons_dir = script_dir / "icons"
    preview_dir = script_dir.parent / "icon_previews"
    icons_dir.mkdir(exist_ok=True)
    preview_dir.mkdir(exist_ok=True)

    print(f"Generating weather icons in {icons_dir}")
    for name, data in XBM_DATA.items():
        print(f"\n{name}:")
        grid = xbm_to_grid(data)
        write_rgba(name, grid, icons_dir)
        write_preview(f"weather_{name}", grid, preview_dir)

    print(f"\nGenerating utility icon previews from existing .rgba files")
    write_utility_previews(icons_dir, preview_dir)

    print(f"\nDone. {len(XBM_DATA)} weather icons regenerated, utility previews written.")


if __name__ == "__main__":
    main()
