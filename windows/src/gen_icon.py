#!/usr/bin/env python3
"""Generate celist.db Windows .ico from the 1024x1024 master icon."""
import os
from PIL import Image

SRC = "/tmp/iconbuild/icon.png"
OUT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "build", "icon.ico")
)

os.makedirs(os.path.dirname(OUT), exist_ok=True)

img = Image.open(SRC).convert("RGBA")
sizes = [16, 20, 24, 32, 48, 64, 128, 256]
img.save(OUT, format="ICO", sizes=[(s,s) for s in sizes])
print(f"wrote {OUT} ({os.path.getsize(OUT)//1024} KB)")
