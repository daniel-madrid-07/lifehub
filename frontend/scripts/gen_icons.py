"""Genera los iconos PNG de la PWA (sin dependencias, PNG a mano).

Motivo: anillo ámbar con check sobre fondo café oscuro, mismo motivo que
el favicon.svg y el CheckButton de la app.

Uso:  python scripts/gen_icons.py   (desde frontend/)
"""
import math
import struct
import zlib

BG_TOP = (26, 19, 13)
BG_BOT = (15, 11, 8)
EMBER_A = (255, 122, 69)   # #ff7a45
EMBER_B = (255, 176, 59)   # #ffb03b


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def smoothstep(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def dist_segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / (vx * vx + vy * vy)))
    dx, dy = px - (ax + vx * t), py - (ay + vy * t)
    return math.hypot(dx, dy)


def make_icon(size):
    cx = cy = size / 2
    ring_r = size * 0.30
    stroke = size * 0.062
    # Check con las mismas proporciones que el path "M5 13l4 4L19 7" (viewBox 24)
    box = size * 0.46
    off = (size - box) / 2
    pts = [(5 / 24, 13 / 24), (9 / 24, 17 / 24), (19 / 24, 7 / 24)]
    segs = []
    for i in range(len(pts) - 1):
        ax, ay = off + pts[i][0] * box, off + pts[i][1] * box
        bx, by = off + pts[i + 1][0] * box, off + pts[i + 1][1] * box
        segs.append((ax, ay, bx, by))

    aa = max(1.0, size / 180)  # borde anti-alias ~1px a 180
    rows = []
    for y in range(size):
        row = []
        bg = lerp(BG_TOP, BG_BOT, y / size)
        for x in range(size):
            # gradiente del trazo en diagonal
            t = (x + (size - y)) / (2 * size)
            ember = lerp(EMBER_A, EMBER_B, t)
            d_ring = abs(math.hypot(x - cx, y - cy) - ring_r)
            d_chk = min(dist_segment(x, y, *s) for s in segs)
            d = min(d_ring, d_chk - stroke * 0.08)  # check un pelin mas fino
            alpha = 1.0 - smoothstep(stroke / 2 - aa, stroke / 2 + aa, d)
            px = lerp(bg, ember, alpha)
            row.append((px[0], px[1], px[2], 255))
        rows.append(row)
    return rows


def write_png(path, size):
    rows = make_icon(size)

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
    print(f"{path} ({size}x{size})")


if __name__ == "__main__":
    write_png("public/apple-touch-icon.png", 180)
    write_png("public/icon-192.png", 192)
    write_png("public/icon-512.png", 512)
