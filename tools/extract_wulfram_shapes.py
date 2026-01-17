#!/usr/bin/env python3
"""
Extract Wulfram 2 shape files into raw binaries for Tamaroyn to load at runtime.

Usage (from project root):
  py tools/extract_wulfram_shapes.py "C:\Path\To\wulfram - Copy.zip"

Output:
  res://assets/wulfram_shapes/extracted/*.bin
  res://assets/wulfram_shapes/extracted/manifest.json

Notes:
- Wulfram stores shapes inside data/shapes.zip within the main zip.
- The binary format is only partially decoded; for now we store the raw bytes and
  record header metadata (name/materials/vertex_count) for debugging and mapping.
"""
from __future__ import annotations

import argparse
import io
import json
import re
import struct
import zipfile
from pathlib import Path


def _read_cstring(buf: bytes, off: int, max_len: int = 256) -> tuple[str, int]:
    end = min(len(buf), off + max_len)
    i = off
    while i < end and buf[i] != 0:
        i += 1
    s = buf[off:i].decode("ascii", errors="ignore")
    # skip null if present
    if i < len(buf) and buf[i] == 0:
        i += 1
    return s, i


def parse_shape_header(data: bytes) -> dict:
    """Best-effort parse of shape header: name, materials, vertex_count."""
    try:
        name, off = _read_cstring(data, 0, 128)
        if off + 2 > len(data):
            return {"name": name, "materials": [], "vertex_count": 0}

        mat_count = struct.unpack_from("<H", data, off)[0]
        off += 2

        mats: list[str] = []
        for _ in range(mat_count):
            m, off = _read_cstring(data, off, 128)
            if m:
                mats.append(m)

        if off + 2 > len(data):
            return {"name": name, "materials": mats, "vertex_count": 0}

        vcount = struct.unpack_from("<H", data, off)[0]
        return {"name": name, "materials": mats, "vertex_count": int(vcount)}
    except Exception:
        return {"name": "", "materials": [], "vertex_count": 0}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("wulfram_zip", help='Path to "wulfram - Copy.zip" (or similar).')
    ap.add_argument("--out", default="assets/wulfram_shapes/extracted", help="Output folder relative to project root.")
    ap.add_argument("--include_lod", action="store_true", help="Also extract *_s low-detail shape variants.")
    args = ap.parse_args()

    proj_root = Path(__file__).resolve().parents[1]  # .../Tamaroyn
    out_dir = (proj_root / args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "source_zip": str(Path(args.wulfram_zip).resolve()),
        "inner_zip": "data/shapes.zip",
        "extracted": [],
        "skipped": 0,
    }

    with zipfile.ZipFile(args.wulfram_zip, "r") as root_zip:
        if "data/shapes.zip" not in root_zip.namelist():
            raise SystemExit("Could not find data/shapes.zip inside the provided Wulfram zip.")

        inner_bytes = root_zip.read("data/shapes.zip")
        with zipfile.ZipFile(io.BytesIO(inner_bytes), "r") as shapes_zip:
            for name in shapes_zip.namelist():
                if name.endswith("/"):
                    continue
                if (not args.include_lod) and name.lower().endswith("_s"):
                    manifest["skipped"] += 1
                    continue

                raw = shapes_zip.read(name)
                safe = re.sub(r"[^A-Za-z0-9._-]+", "_", Path(name).name)
                out_path = out_dir / f"{safe}.bin"
                out_path.write_bytes(raw)

                hdr = parse_shape_header(raw)
                manifest["extracted"].append(
                    {
                        "name": safe,
                        "vertex_count": hdr.get("vertex_count", 0),
                        "materials": hdr.get("materials", []),
                    }
                )

    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Extracted {len(manifest['extracted'])} shapes to: {out_dir}")
    print(f"Skipped {manifest['skipped']} shapes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
