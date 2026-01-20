#!/usr/bin/env python3
"""convert_land_to_png.py

Optional helper: converts a Wulfram map 'land' file into:
- height.png (16-bit grayscale)
- ids.png (16-bit grayscale of template ids, modulo 65536)
- meta.json (dims, world size, min/max height)

Usage:
  python convert_land_to_png.py <path/to/land> <out_dir>

This is NOT required if you use the Godot importer that reads land directly.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path
import numpy as np
from PIL import Image

def parse_land(path: Path):
    txt = path.read_text(errors="replace")
    lines=[ln.strip() for ln in txt.splitlines() if ln.strip() and not ln.strip().startswith("#")]
    m=re.match(r"(\d+)x(\d+)", lines[0]); w,h=int(m.group(1)), int(m.group(2))
    m=re.match(r"([0-9.]+)x([0-9.]+)", lines[1]); world_w,world_h=float(m.group(1)), float(m.group(2))
    expected=w*h
    pairs=[]
    for ln in lines[2:]:
        if len(pairs)>=expected: break
        parts=ln.split()
        if len(parts)>=2:
            try:
                pairs.append((int(parts[0]), float(parts[1])))
            except ValueError:
                pass
    if len(pairs)<expected:
        raise SystemExit(f"Only found {len(pairs)} points, expected {expected}")
    ids=np.array([p[0] for p in pairs],dtype=np.int32).reshape(h,w)
    heights=np.array([p[1] for p in pairs],dtype=np.float32).reshape(h,w)
    return w,h,world_w,world_h,ids,heights

def main():
    if len(sys.argv)<3:
        print(__doc__)
        raise SystemExit(2)
    land_path=Path(sys.argv[1])
    out_dir=Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    w,h,world_w,world_h,ids,heights=parse_land(land_path)

    hmin=float(heights.min()); hmax=float(heights.max())
    # normalize to 0..65535
    norm=(heights - hmin) / (hmax - hmin + 1e-9)
    img=(norm*65535.0).round().clip(0,65535).astype(np.uint16)
    Image.fromarray(img, mode="I;16").save(out_dir/"height.png")

    ids_u16=(ids % 65536).astype(np.uint16)
    Image.fromarray(ids_u16, mode="I;16").save(out_dir/"ids.png")

    meta={
        "w": w, "h": h,
        "world_w": world_w, "world_h": world_h,
        "height_min": hmin, "height_max": hmax,
        "note": "height_m = height_min + (pixel/65535)*(height_max-height_min)"
    }
    (out_dir/"meta.json").write_text(json.dumps(meta, indent=2))
    print("Wrote:", out_dir)

if __name__=="__main__":
    main()
