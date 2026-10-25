#!/usr/bin/env python3
"""Create HOTICE Android launcher PNGs without third-party Python packages.

Run after: flutter create . --project-name hotice --platforms=android
This is preview branding, not the final brand identity.
"""
from pathlib import Path
import math
import struct
import zlib


def segment_distance(x, y, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - (ax + t * dx), y - (ay + t * dy))


def color_at(x, y):
    # Coordinates normalized to 0..1; anti-alias with supersampling.
    x, y = (x + 0.5), (y + 0.5)
    curve = 0.21
    sx, sy = max(abs(x - 0.5) - (0.5 - curve), 0), max(abs(y - 0.5) - (0.5 - curve), 0)
    if math.hypot(sx, sy) > curve:
        return 0, 0, 0, 0
    t = min(1, max(0, (x * 0.55 + y * 0.45)))
    bg = (int(44 + 85 * t), int(186 - 60 * t), int(244 - 5 * t))
    # Stylized white H: two vertical stems, one diagonal-leaning crossbar.
    strokes = [
        (0.33, 0.26, 0.33, 0.75),
        (0.67, 0.26, 0.67, 0.75),
        (0.33, 0.49, 0.67, 0.49),
    ]
    distance = min(segment_distance(x, y, *s) for s in strokes)
    blend = min(1, max(0, (0.057 - distance) * 180))
    return (*[round(bg[i] * (1 - blend) + 255 * blend) for i in range(3)], 255)


def write_png(path, size):
    samples = 3
    rows = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            colors = [
                color_at((px + (sx + 0.5) / samples) / size - 0.5,
                         (py + (sy + 0.5) / samples) / size - 0.5)
                for sy in range(samples) for sx in range(samples)
            ]
            row.extend(round(sum(c[i] for c in colors) / len(colors)) for i in range(4))
        rows.append(b"\x00" + bytes(row))
    raw = b"".join(rows)

    def chunk(kind, data):
        return (struct.pack("!I", len(data)) + kind + data +
                struct.pack("!I", zlib.crc32(kind + data) & 0xffffffff))

    data = (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack("!2I5B", size, size, 8, 6, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(raw, 9)) +
            chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def main():
    root = Path(__file__).resolve().parents[1]
    manifest = root / "android/app/src/main/AndroidManifest.xml"
    if not manifest.is_file():
        raise SystemExit("Android project missing. Run flutter create --platforms=android first.")
    source = manifest.read_text()
    source = source.replace('android:label="hotice"', 'android:label="HOTICE"')
    manifest.write_text(source)
    for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                          ("xxhdpi", 144), ("xxxhdpi", 192)):
        path = root / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        write_png(path, size)
    print("HOTICE launcher icons generated; Android label set.")


if __name__ == "__main__":
    main()
