#!/usr/bin/env python3
"""Swatches for the material master, one per material.

Generated rather than fetched. A photograph of brass is somebody's photograph,
and thirty-six of them is thirty-six licensing questions for a card that only
has to say "this is the brass one". A swatch says that without borrowing
anything, weighs a couple of kilobytes, and looks like the rest of its row
because it was made the same way.

Each material gets a colour taken from what it actually looks like and a
surface taken from how it behaves: metals are brushed, plastics are matte,
liquids are pooled, glass is translucent. Two materials that look alike in life
look alike here, which is the point — nobody should have to read the label to
tell copper from steel.

Pure standard library, like generate-seed-images.py beside it. No pillow, no
network, no download.
"""

import math
import os
import struct
import zlib

OUT = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..', 'public', 'materials'
)
W, H = 400, 300

# (base, highlight, surface). Colours are what the material looks like in the
# hand, not what a brand guide would pick — a card of tasteful greys would tell
# you nothing about which one is copper.
#
# surface:
#   brushed   directional grain, the way rolled metal reads
#   polished  a broad soft sheen, for the precious and the plated
#   matte     flat with a fine speckle, for plastics
#   cast      mottled, for iron and stone-like things
#   liquid    pooled with a meniscus edge
#   glassy    translucent, banded
MATERIALS = {
    'Steel / MS':      ((0x8A, 0x8F, 0x98), (0xC9, 0xCE, 0xD6), 'brushed'),
    'Stainless Steel': ((0x9B, 0xA3, 0xAC), (0xE2, 0xE8, 0xEF), 'brushed'),
    'Aluminium':       ((0xA8, 0xAE, 0xB4), (0xE8, 0xEC, 0xEF), 'brushed'),
    'Brass':           ((0xB5, 0x8C, 0x2E), (0xE8, 0xC9, 0x6B), 'polished'),
    'Copper':          ((0xA5, 0x5A, 0x2A), (0xE0, 0x93, 0x55), 'polished'),
    'Bronze':          ((0x8C, 0x62, 0x2E), (0xC9, 0x9A, 0x5C), 'polished'),
    'Cast Iron':       ((0x4A, 0x4C, 0x50), (0x74, 0x77, 0x7C), 'cast'),
    'Acrylic':         ((0xD8, 0xE4, 0xEC), (0xF4, 0xF9, 0xFC), 'glassy'),
    'Beryllium':       ((0x8E, 0x8F, 0x86), (0xC4, 0xC5, 0xBA), 'cast'),
    'Chrome':          ((0x9E, 0xA8, 0xB2), (0xF2, 0xF6, 0xFA), 'polished'),
    'Columbium':       ((0x7E, 0x84, 0x8C), (0xB6, 0xBD, 0xC6), 'brushed'),
    'Duralumin':       ((0x9C, 0xA0, 0xA4), (0xD6, 0xDA, 0xDE), 'brushed'),
    'Glass':           ((0xC2, 0xDA, 0xD8), (0xEE, 0xF8, 0xF7), 'glassy'),
    'Gold':            ((0xC8, 0x9B, 0x18), (0xF6, 0xDC, 0x74), 'polished'),
    'Lead':            ((0x66, 0x6A, 0x74), (0x93, 0x98, 0xA3), 'cast'),
    'Magnesium':       ((0xA3, 0xA2, 0x99), (0xD8, 0xD7, 0xCC), 'matte'),
    'Mercury':         ((0x97, 0x9C, 0xA4), (0xE4, 0xE9, 0xEF), 'liquid'),
    'Molybdenum':      ((0x76, 0x7C, 0x83), (0xAE, 0xB5, 0xBC), 'brushed'),
    'Nickel':          ((0x9A, 0x99, 0x8C), (0xD2, 0xD1, 0xC2), 'polished'),
    'Nylon':           ((0xE4, 0xDF, 0xD2), (0xF7, 0xF4, 0xEC), 'matte'),
    'PB / Gunmetal':   ((0x6E, 0x6A, 0x5C), (0x9E, 0x99, 0x87), 'cast'),
    'Platinum':        ((0xB4, 0xB8, 0xBC), (0xEC, 0xEF, 0xF2), 'polished'),
    'Polycarbonate':   ((0xCF, 0xDA, 0xE2), (0xF0, 0xF6, 0xFA), 'glassy'),
    'Polyethylene':    ((0xDA, 0xDE, 0xD8), (0xF2, 0xF5, 0xF0), 'matte'),
    'Polypropylene':   ((0xD5, 0xDC, 0xDD), (0xEF, 0xF4, 0xF5), 'matte'),
    'Potassium':       ((0xB9, 0xB6, 0xA6), (0xE4, 0xE2, 0xD5), 'matte'),
    'PVDF':            ((0xE8, 0xE8, 0xE4), (0xFA, 0xFA, 0xF8), 'matte'),
    'Silver':          ((0xB8, 0xBC, 0xC0), (0xF4, 0xF6, 0xF8), 'polished'),
    'Tantalum':        ((0x6C, 0x70, 0x78), (0x9E, 0xA3, 0xAC), 'brushed'),
    'Teflon':          ((0xF0, 0xF0, 0xEE), (0xFF, 0xFF, 0xFE), 'matte'),
    'Tin':             ((0xAE, 0xB2, 0xB6), (0xE0, 0xE3, 0xE6), 'polished'),
    'Titanium':        ((0x84, 0x88, 0x8E), (0xBC, 0xC1, 0xC8), 'brushed'),
    'Tungsten':        ((0x5E, 0x62, 0x68), (0x8C, 0x91, 0x99), 'cast'),
    'Water':           ((0x4E, 0x93, 0xC4), (0xA9, 0xD6, 0xEE), 'liquid'),
    'Zinc':            ((0x9A, 0xA2, 0xA8), (0xD4, 0xDA, 0xDE), 'brushed'),
    'Zirconium':       ((0x8C, 0x90, 0x94), (0xC2, 0xC6, 0xCA), 'brushed'),
}


def clamp(value):
    return 0 if value < 0 else (255 if value > 255 else int(value))


def mix(a, b, t):
    return tuple(clamp(a[i] + (b[i] - a[i]) * t) for i in range(3))


def noise(x, y, salt):
    """Deterministic value noise. The same material draws the same swatch on
    every machine, so a regenerated set does not churn in version control."""
    n = (x * 374761393 + y * 668265263 + salt * 1442695040888963407) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 0xFFFF


def smooth(x, y, scale, salt):
    """Value noise with the samples interpolated.

    Integer division alone (`x // 7`) gives square blocks, and at any visible
    scale those read as compression artefacts rather than as a cast surface.
    Interpolating between the lattice points is what makes mottling look like
    metal instead of like a broken JPEG.
    """
    fx, fy = x / scale, y / scale
    x0, y0 = int(fx), int(fy)
    tx, ty = fx - x0, fy - y0
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    n00 = noise(x0, y0, salt)
    n10 = noise(x0 + 1, y0, salt)
    n01 = noise(x0, y0 + 1, salt)
    n11 = noise(x0 + 1, y0 + 1, salt)
    top = n00 + (n10 - n00) * tx
    bottom = n01 + (n11 - n01) * tx
    return top + (bottom - top) * ty


def surface_value(kind, x, y, salt):
    """How light this pixel sits, 0..1, before the colour is applied."""
    u, v = x / W, y / H
    if kind == 'brushed':
        # Directional grain: fine lines along the roll, faint banding across.
        # The grain stays sharp — a rolled surface really is fine parallel
        # scratches — but the banding is smooth so it does not tile.
        grain = noise(x, y // 3, salt) * 0.16
        banding = smooth(x, y, 90, salt + 5) * 0.14
        return 0.34 + (1 - v) * 0.26 + grain + banding
    if kind == 'polished':
        # One broad sweep of light, the way a buffed face catches a window.
        sweep = math.exp(-(((u - v) - 0.15) ** 2) / 0.06)
        return 0.26 + sweep * 0.62 + smooth(x, y, 6, salt) * 0.05
    if kind == 'matte':
        return 0.52 + (1 - v) * 0.16 + smooth(x, y, 3, salt) * 0.10
    if kind == 'cast':
        # Three octaves, each interpolated: broad patches, then grain, then a
        # fine speckle — which is how a cast face actually reads.
        mottle = (
            smooth(x, y, 34, salt) * 0.52
            + smooth(x, y, 13, salt + 1) * 0.30
            + smooth(x, y, 5, salt + 2) * 0.18
        )
        return 0.30 + mottle * 0.44
    if kind == 'liquid':
        # Pooled: bright where it beads, dark at the meniscus.
        cx, cy = 0.5, 0.56
        d = math.hypot((u - cx) * 1.25, v - cy)
        pool = max(0.0, 1 - (d / 0.52) ** 2)
        return 0.24 + pool * 0.66 + smooth(x, y, 20, salt) * 0.06
    # glassy: translucent bands, brighter towards the top edge.
    band = 0.5 + 0.5 * math.sin((u * 2.2 + v * 0.7) * math.pi)
    return 0.55 + band * 0.22 + (1 - v) * 0.14


def swatch(name, base, highlight, kind):
    salt = sum(ord(c) * (i + 3) for i, c in enumerate(name)) & 0xFFFF
    rows = []
    for y in range(H):
        row = []
        for x in range(W):
            t = surface_value(kind, x, y, salt)
            t = 0.0 if t < 0 else (1.0 if t > 1 else t)
            colour = mix(base, highlight, t)
            # A soft vignette so the swatch reads as an object on a card rather
            # than as a background that has escaped its bounds.
            u, v = (x / W - 0.5) * 2, (y / H - 0.5) * 2
            edge = max(abs(u), abs(v))
            if edge > 0.82:
                colour = mix(colour, (0x22, 0x25, 0x2A), (edge - 0.82) * 0.9)
            row.append(colour)
        rows.append(row)
    return rows


def write_png(path, px):
    raw = bytearray()
    for row in px:
        raw.append(0)
        for r, g, b in row:
            raw += bytes((r, g, b))

    def chunk(tag, data):
        out = struct.pack('>I', len(data)) + tag + data
        return out + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 6))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as fh:
        fh.write(png)


def slug(name):
    keep = [c.lower() if c.isalnum() else '-' for c in name]
    out = ''.join(keep)
    while '--' in out:
        out = out.replace('--', '-')
    return out.strip('-')[:48]


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (base, highlight, kind) in sorted(MATERIALS.items()):
        path = os.path.join(OUT, f'{slug(name)}.png')
        write_png(path, swatch(name, base, highlight, kind))
    print(f'{len(MATERIALS)} swatches -> backend/public/materials/')


if __name__ == '__main__':
    main()
