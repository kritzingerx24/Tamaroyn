#!/usr/bin/env python3
"""
Extract Wulfram 2 indexed/paletted bitmap files into PNG textures usable by Godot.

Usage (from project root):
  python tools/extract_wulfram_bitmaps.py "path/to/Wulfram 2 - Copy.zip"

Output:
  res://assets/wulfram_textures/extracted/*.png
  res://assets/wulfram_textures/extracted/manifest.json

Notes:
- Wulfram 2 stores textures in data/bitmaps/*.zip inside the main zip.
- Files are raw 8-bit indexed images preceded by a 1368-byte header.
- Colors come from data/palette0 (256 * RGB or RGBA). Many copies store RGB (768 bytes).
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import zipfile
from pathlib import Path

try:
    from PIL import Image
except Exception as e:
    raise SystemExit("This script requires Pillow. Install with: pip install Pillow") from e

HEADER_BYTES = 1368

COMMON_WIDTHS = [16, 24, 32, 48, 64, 96, 128, 160, 192, 224, 256, 320, 384, 512, 640, 768, 800, 1024]


def load_palette_rgba(root_zip: zipfile.ZipFile) -> list[tuple[int, int, int, int]]:
    # Most copies use "data/palette0" but be tolerant.
    cand = None
    for name in root_zip.namelist():
        if name.lower().endswith("data/palette0"):
            cand = name
            break
    if cand is None:
        raise FileNotFoundError("Could not find data/palette0 in the provided zip.")

    raw = root_zip.read(cand)

    # Wulfram 2 palette0 is commonly 256*3 bytes (RGB). Some ports store 256*4 (RGBA).
    if len(raw) >= 256 * 4:
        stride = 4
    elif len(raw) >= 256 * 3:
        stride = 3
    else:
        raise ValueError(f"palette0 is unexpectedly small: {len(raw)} bytes")

    pal: list[tuple[int, int, int, int]] = []
    for i in range(256):
        r = raw[i * stride + 0]
        g = raw[i * stride + 1]
        b = raw[i * stride + 2]
        a = raw[i * stride + 3] if stride == 4 else 255
        pal.append((r, g, b, a))
    return pal



def infer_dims(pixel_count: int) -> tuple[int, int] | None:
    # Try common widths first
    for w in COMMON_WIDTHS:
        if pixel_count % w == 0:
            h = pixel_count // w
            if 1 <= h <= 2048:
                return w, h
    # Fallback: search for a reasonable factor pair
    for w in range(8, 2049):
        if pixel_count % w == 0:
            h = pixel_count // w
            if 8 <= h <= 2048:
                # avoid extreme aspect ratios
                r = w / float(h)
                if 0.2 <= r <= 5.0:
                    return w, h
    return None


def _decode_indexed_with_header(raw: bytes, palette: list[tuple[int, int, int, int]], header_bytes: int) -> Image.Image | None:
    """Decode an indexed bitmap using a given header size.

    Wulfram 2 appears to have *two* common bitmap layouts:
    - Most world textures: 1368-byte header + 8-bit indices
    - Many UI sprites/icons: headerless 8-bit indices (small files)
    """
    if len(raw) <= header_bytes:
        return None
    px = raw[header_bytes:]
    dims = infer_dims(len(px))
    if dims is None:
        return None
    w, h = dims
    out = bytearray(w * h * 4)
    for i, idx in enumerate(px):
        r, g, b, a = palette[idx]
        out[i * 4 + 0] = r
        out[i * 4 + 1] = g
        out[i * 4 + 2] = b
        out[i * 4 + 3] = a
    return Image.frombytes("RGBA", (w, h), bytes(out))


def decode_indexed(raw: bytes, palette: list[tuple[int, int, int, int]]) -> Image.Image | None:
    # Try the standard headered layout first (most textures).
    if len(raw) > HEADER_BYTES:
        img = _decode_indexed_with_header(raw, palette, HEADER_BYTES)
        if img is not None:
            return img

    # Fallback: headerless (common for small UI bitmaps/icons).
    return _decode_indexed_with_header(raw, palette, 0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("wulfram_zip", help='Path to "Wulfram 2 - Copy.zip" (or similar).')
    ap.add_argument("--out", default="assets/wulfram_textures/extracted", help="Output folder relative to project root.")
    ap.add_argument("--limit", type=int, default=0, help="Optional max number of images to extract (0=unlimited).")
    args = ap.parse_args()

    proj_root = Path(__file__).resolve().parents[1]  # .../Tamaroyn
    out_dir = (proj_root / args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "source_zip": str(Path(args.wulfram_zip).resolve()),
        "extracted": [],
        "skipped": 0,
    }

    with zipfile.ZipFile(args.wulfram_zip, "r") as root_zip:
        palette = load_palette_rgba(root_zip)

        # Find inner zips: data/bitmaps/*.zip
        bitmap_zips = [n for n in root_zip.namelist() if n.lower().startswith("data/bitmaps/") and n.lower().endswith(".zip")]
        bitmap_zips.sort()

        count = 0
        for inner_name in bitmap_zips:
            inner_bytes = root_zip.read(inner_name)
            with zipfile.ZipFile(io.BytesIO(inner_bytes), "r") as z:
                for n in z.namelist():
                    if n.endswith("/"):
                        continue
                    raw = z.read(n)
                    img = decode_indexed(raw, palette)
                    if img is None:
                        manifest["skipped"] += 1
                        continue
                    # Sanitize name to a stable filename
                    base = Path(n).name
                    base = re.sub(r"[^A-Za-z0-9._-]+", "_", base)
                    if not base.lower().endswith(".png"):
                        base += ".png"

                    out_path = out_dir / base
                    img.save(out_path)
                    manifest["extracted"].append({"name": base, "inner_zip": inner_name, "inner_file": n, "size": [img.width, img.height]})
                    count += 1
                    if args.limit and count >= args.limit:
                        break
            if args.limit and count >= args.limit:
                break

    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Extracted {len(manifest['extracted'])} textures to: {out_dir}")
    print(f"Skipped {manifest['skipped']} files that did not match the expected format.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
