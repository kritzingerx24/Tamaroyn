Wulfram 2 -> Godot map import starter kit (with headless batch import)
====================================================================

This kit imports Wulfram 2 maps into Godot 4:
- Terrain from data/maps/<map>/land (grid + world size + heights + template ids)
- Map objects from data/maps/<map>/state (buildings/utilities/lights; best-effort mapping)
- Map metadata node (MapMeta) with world size + 6x6 sector helpers (for strategic layer)

Workflows
---------

1) In-Editor import (recommended for debugging)
   - Copy your extracted Wulfram `data/` folder into your Godot project.
     Common layouts:
       - res://data/maps/...                (data folder at project root)
       - res://wulfram_data/data/maps/...   (data folder nested)
   - Enable the addon in Project Settings -> Plugins.
   - Use Editor menu: "Wulfram -> Import Map (choose land file)..."
   - Output: res://imported_maps/<map>.tscn

2) Headless batch import (CI / pipelines / no-window)
   - Same folder layout as above.
   - Run:
       godot --headless -s res://tools/import_maps_headless.gd -- \
         --data_root res://wulfram_data \
         --out_root res://generated_maps

     Options:
       --data_root <path>   Folder containing either `data/maps` or `maps`
       --out_root  <path>   Output folder for generated .tscn scenes
       --maps <a,b,c>       Optional comma-separated map list (defaults to ALL maps found)

3) Optional preconvert
   - tools/convert_land_to_png.py exports a 16-bit heightmap + ids for external processing.

Notes
-----
- This is intentionally best-effort and does NOT yet decode Wulfram's texture system (tagmap2/templates/bitmaps).
  It builds correct terrain geometry + collision, and places placeholder meshes for state objects.
- For a public release, do NOT ship original assets. Replace art/audio with your own.

Files
-----
- addons/wulfram_importer/plugin.cfg
- addons/wulfram_importer/wulfram_importer_plugin.gd
- addons/wulfram_importer/wulfram_map_builder.gd
- addons/wulfram_importer/wulfram_map_meta.gd
- tools/import_maps_headless.gd   (NEW)
- tools/convert_land_to_png.py
