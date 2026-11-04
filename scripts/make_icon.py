#!/usr/bin/env python3
"""Generate the 1024x1024 RGB (no alpha) app icon. Pure Python (zlib only).

Usage: python3 scripts/make_icon.py [output.png]
"""
import math, struct, sys, zlib, os

N = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

def smooth(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)

C0 = (20, 16, 58)     # deep indigo
C1 = (109, 40, 217)   # violet
C2 = (219, 39, 119)   # pink
WHITE = (255, 255, 255)

def sd_round_box(px, py, cx, cy, hw, hh, r):
    qx = abs(px - cx) - hw + r
    qy = abs(py - cy) - hh + r
    return math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - r

def sd_triangle(px, py, a, b, c):
    # iq's signed distance to triangle (a, b, c)
    def sub(p, q): return (p[0] - q[0], p[1] - q[1])
    def dot(p, q): return p[0] * q[0] + p[1] * q[1]
    p = (px, py)
    e0, e1, e2 = sub(b, a), sub(c, b), sub(a, c)
    v0, v1, v2 = sub(p, a), sub(p, b), sub(p, c)
    def clampd(v, e):
        t = max(0.0, min(1.0, dot(v, e) / dot(e, e)))
        d = (v[0] - e[0] * t, v[1] - e[1] * t)
        return dot(d, d)
    d = min(clampd(v0, e0), clampd(v1, e1), clampd(v2, e2))
    s = e0[0] * e2[1] - e0[1] * e2[0]
    sg = min(s * (v0[0] * e0[1] - v0[1] * e0[0]),
             s * (v1[0] * e1[1] - v1[1] * e1[0]),
             s * (v2[0] * e2[1] - v2[1] * e2[0]))
    return -math.copysign(math.sqrt(d), sg)

cx = cy = N / 2
# play triangle, optically centred (shifted right a bit), rounded by radius R
R = 36
tri = ((cx - 120 + 30, cy - 175), (cx - 120 + 30, cy + 175), (cx + 205 + 30 - R, cy))
rows = []
for y in range(N):
    row = bytearray([0])
    for x in range(N):
        fx, fy = x + 0.5, y + 0.5
        # diagonal gradient indigo -> violet -> pink
        t = (fx * 0.45 + fy * 0.55) / N
        col = mix(C0, C1, smooth(0.0, 0.62, t)) if t < 0.62 else mix(C1, C2, smooth(0.62, 1.05, t))
        # soft glow behind the symbol
        g = math.hypot(fx - cx, fy - cy) / (N * 0.5)
        col = mix(col, (167, 110, 255), 0.30 * max(0.0, 1 - g) ** 2)
        # translucent rounded plate
        dp = sd_round_box(fx, fy, cx, cy, 330, 330, 150)
        a_plate = 0.13 * (1 - smooth(-1.0, 1.0, dp))
        ring = 0.30 * (1 - smooth(0.0, 2.0, abs(dp + 2) - 2))
        col = mix(col, WHITE, min(1.0, a_plate + ring))
        # soft shadow of triangle
        ds = sd_triangle(fx - 0, fy - 16, *tri) - R
        col = mix(col, (30, 10, 80), 0.35 * (1 - smooth(-4.0, 34.0, ds)))
        # white play triangle
        d = sd_triangle(fx, fy, *tri) - R
        col = mix(col, WHITE, 1 - smooth(-0.8, 0.8, d))
        row += bytes(max(0, min(255, int(round(v)))) for v in col)
    rows.append(bytes(row))

raw = b"".join(rows)
def chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", N, N, 8, 2, 0, 0, 0))  # 8-bit RGB, no alpha
       + chunk(b"IDAT", zlib.compress(raw, 9))
       + chunk(b"IEND", b""))
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
with open(OUT, "wb") as f:
    f.write(png)
print("wrote", OUT, len(png), "bytes")
