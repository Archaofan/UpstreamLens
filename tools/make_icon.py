"""Generate the UpstreamLens app icon (1024x1024) without external dependencies.

Draws the dot.radiowaves motif on a cyan-teal gradient using signed distance
fields for anti-aliasing, then writes a PNG with zlib.
"""
import math
import struct
import zlib

SIZE = 1024
CENTER = SIZE / 2

# Gradient endpoints (sRGB, 0-255)
TOP = (0x2A, 0xC5, 0xDB)      # bright cyan, top-left
BOTTOM = (0x0B, 0x5F, 0x85)   # deep teal-blue, bottom-right
GLOW = (0x9B, 0xE8, 0xF2)     # soft highlight near the top
GLOW_CENTER = (0.5, 0.18)
GLOW_RADIUS = 0.55

DOT_RADIUS = 0.062 * SIZE
ARC_RADII = (0.155 * SIZE, 0.245 * SIZE)
ARC_STROKE = 0.037 * SIZE
ARC_SPAN = math.radians(52)   # half-angle of each arc around the horizontal axis
ARC_FADE = 3.0                # angular edge softness, in pixels


def coverage(px: float, py: float) -> float:
    """Anti-aliased coverage of the white symbol at pixel center (px, py)."""
    x = abs(px - CENTER)  # mirror so the arcs only need one angular check
    y = py - CENTER
    dist = math.hypot(x, y)
    angle = math.atan2(y, x)

    best = dist - DOT_RADIUS
    for radius in ARC_RADII:
        ring = abs(dist - radius) - ARC_STROKE / 2
        angular = (abs(angle) - ARC_SPAN) * dist
        d = max(ring, angular) if angular > -ARC_FADE else ring
        best = min(best, d)
    return max(0.0, min(1.0, 0.5 - best))


def pixel_color(px: int, py: int) -> tuple:
    x = (px + 0.5) / SIZE
    y = (py + 0.5) / SIZE
    t = (x + y) / 2
    color = [TOP[i] + (BOTTOM[i] - TOP[i]) * t for i in range(3)]
    gx, gy = x - GLOW_CENTER[0], y - GLOW_CENTER[1]
    glow = max(0.0, 1.0 - math.hypot(gx, gy) / GLOW_RADIUS) ** 2 * 0.35
    for i, value in enumerate(GLOW):
        color[i] += (value - color[i]) * glow
    symbol = coverage(px + 0.5, py + 0.5)
    for i in range(3):
        color[i] += (255 - color[i]) * symbol
    return int(color[0] + 0.5), int(color[1] + 0.5), int(color[2] + 0.5)


def main() -> None:
    rows = []
    for py in range(SIZE):
        row = bytearray([0])
        for px in range(SIZE):
            row += bytes(pixel_color(px, py))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    out = "Assets/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    with open(out, "wb") as handle:
        handle.write(png)
    print(f"wrote {out} ({len(png)} bytes)")


if __name__ == "__main__":
    main()
