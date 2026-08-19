#!/usr/bin/env python3
"""Generate the master-catalogue imagery the demo scenario ships with.

Every seeded master — item, client, vendor, machine, die, department, set — gets
a picture, because a catalogue with half its tiles showing initials looks
unfinished. These are generated rather than photographed: real product
photography is a licensing question, not a code one.

Each tile is a diagonal gradient in its domain's colour, a domain motif, and the
record's monogram. Deterministic: same name in, same image out, so reseeding
does not churn the files.

Pure standard library — a minimal PNG encoder and a hand-encoded 5x7 font, so it
runs anywhere without Pillow.

    python3 backend/tools/generate-seed-images.py
"""

import os
import struct
import zlib
import hashlib

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'public', 'seed')
W, H = 480, 360

# Domain palettes: (top-left, bottom-right, motif, monogram).
PALETTES = {
    'item':       ((0x4B, 0x3C, 0xC4), (0x7A, 0x6B, 0xF0), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
    'client':     ((0x0E, 0x6B, 0x63), (0x2A, 0xA1, 0x95), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
    'vendor':     ((0x8A, 0x4B, 0x0A), (0xD3, 0x8B, 0x2C), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
    'machine':    ((0x28, 0x33, 0x52), (0x4C, 0x5F, 0x8F), (0xC9, 0xD4, 0xF0), (0xFF, 0xFF, 0xFF)),
    'die':        ((0x4A, 0x22, 0x6B), (0x82, 0x47, 0xB0), (0xE6, 0xD8, 0xF5), (0xFF, 0xFF, 0xFF)),
    'department': ((0x14, 0x5A, 0x32), (0x35, 0x94, 0x5C), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
    'employee':   ((0x33, 0x3B, 0x52), (0x5E, 0x6A, 0x8C), (0xE2, 0xE8, 0xF4), (0xFF, 0xFF, 0xFF)),
    'set':        ((0x8C, 0x1D, 0x45), (0xC8, 0x4B, 0x74), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
    'group':      ((0x1F, 0x44, 0x6B), (0x3F, 0x7C, 0xB0), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
}

# 5x7 bitmap font, enough for a monogram.
FONT = {
    'A': ['01110','10001','10001','11111','10001','10001','10001'],
    'B': ['11110','10001','10001','11110','10001','10001','11110'],
    'C': ['01110','10001','10000','10000','10000','10001','01110'],
    'D': ['11110','10001','10001','10001','10001','10001','11110'],
    'E': ['11111','10000','10000','11110','10000','10000','11111'],
    'F': ['11111','10000','10000','11110','10000','10000','10000'],
    'G': ['01110','10001','10000','10111','10001','10001','01110'],
    'H': ['10001','10001','10001','11111','10001','10001','10001'],
    'I': ['11111','00100','00100','00100','00100','00100','11111'],
    'J': ['00111','00010','00010','00010','00010','10010','01100'],
    'K': ['10001','10010','10100','11000','10100','10010','10001'],
    'L': ['10000','10000','10000','10000','10000','10000','11111'],
    'M': ['10001','11011','10101','10101','10001','10001','10001'],
    'N': ['10001','11001','10101','10011','10001','10001','10001'],
    'O': ['01110','10001','10001','10001','10001','10001','01110'],
    'P': ['11110','10001','10001','11110','10000','10000','10000'],
    'Q': ['01110','10001','10001','10001','10101','10011','01111'],
    'R': ['11110','10001','10001','11110','10100','10010','10001'],
    'S': ['01111','10000','10000','01110','00001','00001','11110'],
    'T': ['11111','00100','00100','00100','00100','00100','00100'],
    'U': ['10001','10001','10001','10001','10001','10001','01110'],
    'V': ['10001','10001','10001','10001','10001','01010','00100'],
    'W': ['10001','10001','10001','10101','10101','11011','10001'],
    'X': ['10001','10001','01010','00100','01010','10001','10001'],
    'Y': ['10001','10001','01010','00100','00100','00100','00100'],
    'Z': ['11111','00001','00010','00100','01000','10000','11111'],
    '0': ['01110','10001','10011','10101','11001','10001','01110'],
    '1': ['00100','01100','00100','00100','00100','00100','01110'],
    '2': ['01110','10001','00001','00110','01000','10000','11111'],
    '3': ['11110','00001','00001','01110','00001','00001','11110'],
    '4': ['00010','00110','01010','10010','11111','00010','00010'],
    '5': ['11111','10000','11110','00001','00001','10001','01110'],
    '6': ['00110','01000','10000','11110','10001','10001','01110'],
    '7': ['11111','00001','00010','00100','01000','01000','01000'],
    '8': ['01110','10001','10001','01110','10001','10001','01110'],
    '9': ['01110','10001','10001','01111','00001','00010','01100'],
    '-': ['00000','00000','00000','11111','00000','00000','00000'],
    ' ': ['00000','00000','00000','00000','00000','00000','00000'],
}


def monogram(name):
    parts = [p for p in name.replace('-', ' ').split() if p]
    letters = ''.join(p[0] for p in parts[:2]).upper()
    letters = ''.join(c for c in letters if c in FONT)
    return letters or (name[:2].upper() if name else '??')


def blank():
    return [[(0, 0, 0) for _ in range(W)] for _ in range(H)]


def gradient(px, a, b):
    for y in range(H):
        for x in range(W):
            t = (x / (W - 1) * 0.55) + (y / (H - 1) * 0.45)
            px[y][x] = tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def blend(px, x, y, colour, alpha):
    if 0 <= x < W and 0 <= y < H:
        base = px[y][x]
        px[y][x] = tuple(round(base[i] + (colour[i] - base[i]) * alpha) for i in range(3))


def ring(px, cx, cy, radius, thickness, colour, alpha):
    inner = (radius - thickness) ** 2
    outer = radius ** 2
    for y in range(max(0, cy - radius), min(H, cy + radius + 1)):
        for x in range(max(0, cx - radius), min(W, cx + radius + 1)):
            d = (x - cx) ** 2 + (y - cy) ** 2
            if inner <= d <= outer:
                blend(px, x, y, colour, alpha)


def bar(px, x0, y0, w, h, colour, alpha):
    for y in range(y0, min(H, y0 + h)):
        for x in range(x0, min(W, x0 + w)):
            blend(px, x, y, colour, alpha)


def motif(px, domain, colour, salt):
    """A quiet domain mark, offset per record so no two tiles look identical."""
    jitter = salt % 40 - 20
    if domain in ('die', 'item', 'set'):
        for i, r in enumerate((150, 112, 74)):
            ring(px, 360 + jitter, 96, r, 8, colour, 0.10 + i * 0.03)
    elif domain in ('machine', 'vendor'):
        for i in range(5):
            bar(px, 300 + i * 34 + jitter, 210 - i * 26, 16, 120 + i * 24, colour, 0.10)
    else:
        ring(px, 372 + jitter, 250, 120, 10, colour, 0.14)
        ring(px, 372 + jitter, 250, 76, 10, colour, 0.10)


def draw_text(px, text, colour):
    """Centre the monogram on a 5x7 grid scaled up, with a soft shadow."""
    scale = 34
    gap = scale
    tw = len(text) * 5 * scale + (len(text) - 1) * gap
    ox = (W - tw) // 2
    oy = (H - 7 * scale) // 2
    for i, ch in enumerate(text):
        glyph = FONT.get(ch, FONT[' '])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit != '1':
                    continue
                x0 = ox + i * (5 * scale + gap) + gx * scale
                y0 = oy + gy * scale
                bar(px, x0 + 3, y0 + 3, scale, scale, (0, 0, 0), 0.18)
                bar(px, x0, y0, scale, scale, colour, 0.96)


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


def make(domain, name):
    a, b, motif_colour, text_colour = PALETTES[domain]
    px = blank()
    gradient(px, a, b)
    salt = int(hashlib.md5(f'{domain}:{name}'.encode()).hexdigest()[:8], 16)
    motif(px, domain, motif_colour, salt)
    draw_text(px, monogram(name), text_colour)
    path = os.path.join(OUT, f'{domain}-{slug(name)}.png')
    write_png(path, px)
    return os.path.basename(path)


CATALOGUE = {
    'item': [
        'Anchor Roma Classic Switch 10A 1-Way', 'Anchor Roma Classic Switch 20A 1-Way',
        'Anchor Roma Classic Socket 10A', 'Anchor Roma Classic Socket 20A',
        'Anchor Roma Penta Switch 10A', 'Anchor Roma Penta Switch 20A',
        'Anchor Roma Penta Socket 10A', 'Anchor Roma Penta Socket 20A',
        'Polycab 1.5 sq mm FR PVC Wire (90m)', 'Polycab 2.5 sq mm FR PVC Wire (90m)',
        'Orient Electric 1200mm Ceiling Fan', 'Crompton Greaves 1200mm Ceiling Fan',
        'Philips 9W LED Bulb',
        # Raw stock the manufacturing dataset layers in.
        'Aluminum Billet', 'Copper Coil', 'Steel Sheet', 'Brass Rod',
    ],
    'client': [
        'Acme Packaging Pvt. Ltd.', 'Sunrise Retail LLP', 'Legacy Trading Co.',
        'Northstar Pharma Packs', 'Orbit Consumer Goods', 'BluePeak Exports',
    ],
    'vendor': [
        'Bharat Metals & Alloys', 'Deccan Copper Works', 'Shree Polymers',
        'Konark Plating Services', 'Vidarbha Packaging', 'Precision Tool & Die',
    ],
    'machine': [
        'Power Press 60T', 'Power Press 100T', 'Cutter 04', 'Hydraulic Press 150T',
        'Riveting Station 1', 'Riveting Station 2', 'Polishing Barrel', 'Weld Station A',
    ],
    'die': [
        'DIE-SW10-A', 'DIE-SW20-A', 'DIE-SKT10-B', 'DIE-SKT20-B', 'DIE-PNT-C', 'DIE-TRM-D',
    ],
    'department': [
        'Press Shop', 'Assembly', 'Quality & Dispatch', 'Maintenance', 'Accounts & Admin',
    ],
    'employee': [
        'Ramesh Kulkarni', 'Sunil Pawar', 'Ganesh Shinde', 'Vikas More',
        'Anita Deshmukh', 'Sonal Jadhav', 'Priya Salunke', 'Kavita Bhosale',
        'Mahesh Gaikwad', 'Nitin Chavan', 'Sachin Patil', 'Amit Jagtap',
        'Deepa Kale', 'Rohit Sawant',
    ],
    'set': ['Starter Pack', 'Marketing Kit', 'Switchboard Kit'],
    # Groups show on the Items master too.
    'group': ['Raw Materials', 'Finished Goods', 'Consumables', 'Scrap',
              'Primary Group', 'Electrical Fittings'],
}

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    total = 0
    for domain, names in CATALOGUE.items():
        for name in names:
            make(domain, name)
            total += 1
        print(f'  {domain:11s} {len(names):3d}')
    print(f'{total} images -> backend/public/seed/')
