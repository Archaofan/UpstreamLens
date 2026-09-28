"""Generate the UpstreamLens app icons (1024x1024, three appearances) without
external dependencies.

Design v2: bold radiowaves motif — a filled dot with two thick round-capped
arcs over a cyan-to-deep-teal diagonal gradient with a top highlight and a
gentle vignette. Emits the light, dark, and grayscale (tinted) variants.
"""
import math
import struct
import zlib

SIZE = 1024
CENTER = SIZE / 2

# Light appearance palette (sRGB 0-255)
LIGHT_TOP = (0x3E, 0xD6, 0xE8)      # bright cyan, top-left
LIGHT_BOTTOM = (0x08, 0x47, 0x66)   # deep ocean teal, bottom-right
LIGHT_GLOW = (0xBE, 0xF3, 0xFA)     # soft highlight near the top
SYMBOL = (255, 255, 255)

# Dark appearance palette
DARK_TOP = (0x0A, 0x33, 0x46)
DARK_BOTTOM = (0x05, 0x14, 0x1E)
DARK_GLOW = (0x14, 0x5C, 0x74)
DARK_SYMBOL = (0xEC, 0xFB, 0xFD)

DOT_RADIUS = 0.085 * SIZE
ARC_RADII = (0.205 * SIZE, 0.335 * SIZE)
ARC_STROKE = 0.062 * SIZE           # bold strokes survive 60px home screen sizes
ARC_SPAN = math.radians(58)         # half-angle around the horizontal axis
GLOW_CENTER = (0.5, 0.16)
GLOW_RADIUS = 0.62


def symbol_distance(px: float, py: float) -> float:
    """Signed distance to the radiowaves symbol (negative inside)."""
    x = abs(px - CENTER)  # mirror so the arcs only need one angular check
    y = py - CENTER
    dist = math.hypot(x, y)
    best = dist - DOT_RADIUS
    for radius in ARC_RADII:
        if dist > 1e-6:
            # 弧线用“夹角到最近弧点”的距离：环身与圆头端帽一次算出。
            angle = math.atan2(y, x)
            clamped = max(-ARC_SPAN, min(ARC_SPAN, angle))
            nearest = (radius * math.cos(clamped), radius * math.sin(clamped))
            d = math.hypot(x - nearest[0], y - nearest[1]) - ARC_STROKE / 2
        else:
            d = (radius - ARC_STROKE / 2) - dist
        best = min(best, d)
    return best


def background_color(x: float, y: float, top, bottom, glow):
    t = (x + y) / 2
    color = [top[i] + (bottom[i] - top[i]) * t for i in range(3)]
    gx, gy = x - GLOW_CENTER[0], y - GLOW_CENTER[1]
    strength = max(0.0, 1.0 - math.hypot(gx, gy) / GLOW_RADIUS) ** 2 * 0.42
    for i, value in enumerate(glow):
        color[i] += (value - color[i]) * strength
    # 暗角：四角略暗，突出中心符号。
    edge = math.hypot(x - 0.5, y - 0.5) / math.hypot(0.5, 0.5)
    vignette = 1.0 - 0.16 * max(0.0, edge - 0.55) / 0.45
    return [c * vignette for c in color]


def render(top, bottom, glow, symbol_color, grayscale=False):
    rows = []
    for py in range(SIZE):
        row = bytearray([0])
        y = (py + 0.5) / SIZE
        for px in range(SIZE):
            x = (px + 0.5) / SIZE
            color = background_color(x, y, top, bottom, glow)
            d = symbol_distance(px + 0.5, py + 0.5)
            coverage = max(0.0, min(1.0, 0.5 - d))
            # 符号边缘留一点背景光晕，避免硬边。
            halo = max(0.0, min(1.0, (6.0 - d) / 12.0)) * 0.10
            for i in range(3):
                target = (color[i] + 255) / 2
                color[i] += (target - color[i]) * halo
                color[i] += (symbol_color[i] - color[i]) * coverage
            if grayscale:
                lum = 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2]
                # 拉开对比：背景压到中灰以下，符号保持接近白。
                lum = (lum / 255.0) ** 1.15 * 255.0
                color = [lum, lum, lum]
            row += bytes(int(c + 0.5) for c in color)
        rows.append(bytes(row))
    return rows


def write_png(path: str, rows) -> None:
    raw = b"".join(rows)

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (struct.pack(">I", len(payload)) + tag + payload
                + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
           + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    with open(path, "wb") as handle:
        handle.write(png)
    print(f"wrote {path} ({len(png)} bytes)")


def main() -> None:
    folder = "Assets/Assets.xcassets/AppIcon.appiconset/"
    write_png(folder + "AppIcon.png",
              render(LIGHT_TOP, LIGHT_BOTTOM, LIGHT_GLOW, SYMBOL))
    write_png(folder + "AppIconDark.png",
              render(DARK_TOP, DARK_BOTTOM, DARK_GLOW, DARK_SYMBOL))
    write_png(folder + "AppIconTinted.png",
              # 着色模式取亮度重上色：用深色版（深底亮符号）灰度化，着色后对比最好。
              render(DARK_TOP, DARK_BOTTOM, DARK_GLOW, DARK_SYMBOL, grayscale=True))


if __name__ == "__main__":
    main()
