#!/usr/bin/env python3
"""
Generates a custom celist.db app icon (1024x1024 master) that deliberately
avoids the MS Access cylinder look. Concept: a faceted "data core / orbit" —
a bold rounded-surface emblem with an iridescent gradient, an orbiting ring
and a scalar data point — on a deep indigo backdrop.

Outputs:
  /tmp/iconbuild/icon.png   - 1024x1024 master (consumed by Scripts/make_icns.sh
                              and windows/src/gen_icon.py)
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersample factor for smooth curves

# ---- palette (modern, not Access blue cylinder) -----------------------
BG_TOP    = (38, 26, 84)     # deep violet
BG_BOT    = (9, 10, 26)      # near-black indigo
CORE_TOP  = (135, 226, 255)  # ice cyan
CORE_BOT  = (44, 112, 246)   # electric blue
RING_COL  = (255, 190, 90)   # amber accent
PART_COL  = (120, 255, 240)  # mint

CORNER = int(SIZE * 0.225)
TILT = -12.0  # degrees


def vgrad(size, top, bot):
    """Vertical gradient as an opaque RGBA image."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    for y in range(size):
        t = y / max(1, size - 1)
        c = (int(top[0] + (bot[0] - top[0]) * t),
             int(top[1] + (bot[1] - top[1]) * t),
             int(top[2] + (bot[2] - top[2]) * t), 255)
        for x in range(size):
            px[x, y] = c
    return img


def radial_glow(size, center, radius, color, strength):
    """Soft glow on a transparent layer."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    steps = 48
    for i in range(steps, 0, -1):
        r = radius * (i / steps)
        a = int(strength * (1.0 - i / steps) ** 1.7)
        if a > 0:
            d.ellipse([center[0] - r, center[1] - r,
                       center[0] + r, center[1] + r],
                      fill=(color[0], color[1], color[2], a))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.12))


def rounded_rect_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def tilted_ring(size, cx, cy, rx, ry, thickness, angle, color, alpha):
    """A smooth anti-aliased tilted elliptical ring on a transparent layer."""
    big = size * SS
    layer = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(layer)
    d.ellipse([cx * SS - rx * SS, cy * SS - ry * SS,
               cx * SS + rx * SS, cy * SS + ry * SS], fill=255)
    d.ellipse([cx * SS - rx * SS + thickness * SS, cy * SS - ry * SS + thickness * SS,
               cx * SS + rx * SS - thickness * SS, cy * SS + ry * SS - thickness * SS],
              fill=0)
    layer = layer.rotate(angle, resample=Image.BICUBIC, center=(cx * SS, cy * SS))
    layer = layer.resize((size, size), Image.LANCZOS)
    ring = Image.new("RGBA", (size, size), (color[0], color[1], color[2], alpha))
    ring.putalpha(layer.point(lambda a: a * alpha // 255))
    return ring


def ring_point(cx, cy, rx, ry, ang):
    """Point on the tilted ring at ellipse angle `ang` (degrees)."""
    rad = math.radians(ang)
    t = math.radians(TILT)
    x, y = rx * math.cos(rad), ry * math.sin(rad)
    return (cx + x * math.cos(t) - y * math.sin(t),
            cy + x * math.sin(t) + y * math.cos(t))


def main():
    cx = SIZE // 2
    cy = int(SIZE * 0.55)

    # ---- background: deep violet → near-black indigo ----------------------
    base = vgrad(SIZE, BG_TOP, BG_BOT)
    base = Image.alpha_composite(
        base, radial_glow(SIZE, (cx, int(SIZE * 0.42)), int(SIZE * 0.62),
                          (40, 90, 255), 120))

    # ---- faceted "data core" rounded-square emblem ------------------------
    pad = int(SIZE * 0.085)
    box = [pad, pad, SIZE - pad, SIZE - pad]
    radius = int(SIZE * 0.18)
    core_mask = rounded_rect_mask(SIZE, box, radius)

    core = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    core.paste(vgrad(SIZE, CORE_TOP, CORE_BOT), (0, 0), core_mask)
    base = Image.alpha_composite(base, core)

    # top sheen
    sheen = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ds = ImageDraw.Draw(sheen)
    sheen_h = int(SIZE * 0.30)
    for i in range(sheen_h, 0, -1):
        ds.rectangle([0, box[1], SIZE, box[1] + i],
                     fill=(255, 255, 255, int(85 * (1 - i / sheen_h) ** 1.4)))
    sheen = sheen.filter(ImageFilter.GaussianBlur(18))
    base = Image.alpha_composite(
        base, Image.composite(sheen, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)),
                              core_mask))

    # bottom shading
    shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dsh = ImageDraw.Draw(shade)
    shade_h = int(SIZE * 0.26)
    for i in range(shade_h, 0, -1):
        dsh.rectangle([0, box[3] - i, SIZE, box[3]],
                      fill=(0, 0, 40, int(70 * (1 - i / shade_h) ** 1.4)))
    shade = shade.filter(ImageFilter.GaussianBlur(20))
    base = Image.alpha_composite(
        base, Image.composite(shade, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)),
                              core_mask))

    # ---- orbit: amber ring + inner mint trace -----------------------------
    rx, ry = int(SIZE * 0.44), int(SIZE * 0.145)
    base = Image.alpha_composite(
        base, tilted_ring(SIZE, cx, cy, rx, ry, int(SIZE * 0.022), TILT,
                          RING_COL, 210))
    base = Image.alpha_composite(
        base, tilted_ring(SIZE, cx, cy, int(rx * 0.90), int(ry * 0.90),
                          int(SIZE * 0.006), TILT, PART_COL, 120))

    # ---- scalar data point on the ring ------------------------------------
    dot = ring_point(cx, cy, rx, ry, 152)
    r = int(SIZE * 0.040)
    base = Image.alpha_composite(
        base, radial_glow(SIZE, (int(dot[0]), int(dot[1])), r * 5,
                          PART_COL, 150))
    ddot = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dd = ImageDraw.Draw(ddot)
    dd.ellipse([dot[0] - r, dot[1] - r, dot[0] + r, dot[1] + r],
               fill=(*PART_COL, 255))
    dd.ellipse([dot[0] - r * 0.42, dot[1] - r * 0.42,
                dot[0] + r * 0.42, dot[1] + r * 0.42], fill=(255, 255, 255, 255))
    base = Image.alpha_composite(base, ddot)

    # ---- subtle emboss outline + final rounded-corner mask ----------------
    emboss = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(emboss).rounded_rectangle(
        [2, 2, SIZE - 3, SIZE - 3], radius=CORNER,
        outline=(255, 255, 255, 30), width=int(SIZE * 0.01))
    base = Image.alpha_composite(base, emboss)

    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(base, (0, 0), rounded_rect_mask(SIZE, [0, 0, SIZE - 1, SIZE - 1],
                                              CORNER))

    os.makedirs("/tmp/iconbuild", exist_ok=True)
    out.save("/tmp/iconbuild/icon.png")
    print("wrote /tmp/iconbuild/icon.png")


if __name__ == "__main__":
    main()
