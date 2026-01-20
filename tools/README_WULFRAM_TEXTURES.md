# Wulfram 2 texture extraction (optional)

Tamaroyn can automatically use real Wulfram 2 terrain/vehicle textures **if you extract them locally**.

## Why this exists
The Wulfram 2 assets in `Wulfram 2 - Copy.zip` are stored in a custom paletted bitmap format inside nested zip files.
Godot can't import those directly, so we provide a small extractor.

## Extract
1. Put your original `Wulfram 2 - Copy.zip` somewhere on your machine.
2. From the project root (`Tamaroyn/`), run:

```bash
python tools/extract_wulfram_bitmaps.py "C:/path/to/Wulfram 2 - Copy.zip"
```

This creates:
- `res://assets/wulfram_textures/extracted/*.png`
- `res://assets/wulfram_textures/extracted/manifest.json`

## What Tamaroyn uses automatically
If the following files exist, Tamaroyn will load them at runtime:

- `greenmartian001.png` (grass)
- `2marsdirt001.png` (dirt)
- `marsrock001.png` (rock)
- `dark-grey_44.png` (vehicle metal)

If they don't exist, Tamaroyn falls back to built-in placeholder textures.
