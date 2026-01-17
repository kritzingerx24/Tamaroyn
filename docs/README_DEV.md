# Tamaroyn (Wulfram-inspired) – Developer Quickstart

## What this repo contains
- A Godot 4.5 project with:
  - A dedicated server scene (authoritative simulation): `res://server/ServerMain.tscn`
  - A client scene (renders world and connects to server): `res://game/GameClient.tscn`
  - Imported terrain scenes (from the Wulfram map exporter): `res://imported_maps/*.tscn`

## Running in the Godot Editor (no command line)
### 1) Start the server
1. Open the project in Godot.
2. In the **FileSystem** dock (left), open `server/ServerMain.tscn`.
3. Press **F6** (**Run Current Scene**).
4. At the bottom of the editor, open the **Output** tab and verify you see:
   - `Server listening on port 2456`

### 2) Start the client
1. Open `game/GameClient.tscn`.
2. Press **F6** (**Run Current Scene**).
3. The client auto-connects to `127.0.0.1:2456`.

## Running from command line
- Dedicated server:
  - `godot4.5 --headless --path . --scene res://server/ServerMain.tscn -- --port 2456`
- Client:
  - `godot4.5 --path . --scene res://game/GameClient.tscn -- --connect 127.0.0.1 --port 2456 --map aberdour`

## Controls (prototype)
- WASD: move (server-authoritative)
- Mouse: aim + turn
- Left Mouse Button: autocannon (server-authoritative hitscan)
- Right Mouse Button: pulse (tank AoE)/ scout beam (scout)
- TAB: cycle target
- E: hunter missile
- F: flare
- G: drop mine
- B: build powercell (consumes 1 cargo; grants fuel+HP regen in radius)
- T: build turret (consumes 1 cargo; auto-fires at enemy players in range)
- K: spawn a cargo crate nearby (test/debug)
- Cargo pickup: drive through/near a crate to auto-pickup (HUD toast confirms)
- C: toggle vehicle (tank <-> scout)
- 0-9: set speed (7 is neutral)
- Fuel drains when overdriving (8-9) and firing; powercells regen fuel/HP and scout charge
- Q/Z: adjust hover height
- V: toggle camera (cockpit <-> chase)
- Esc: release mouse cursor (editor window)

## Troubleshooting
- If you only see a gray/empty screen:
  - Confirm the server is running and the client says “Connected”.
  - Check the Output tab for errors.


## Wulfram texture extraction (optional)

To keep the repo clean and avoid bundling original game assets, Tamaroyn ships with **placeholder** textures by default.
If you own a copy of the original Wulfram 2 data, you can extract textures locally and drop them into the project.

1) Put your original zip somewhere on disk (for example: `wulfram - copy.zip`)
2) From the Tamaroyn project folder, run:

```bash
python tools/extract_wulfram_bitmaps.py "PATH/TO/wulfram - copy.zip"
```

This will create:
- `assets/wulfram_textures/extracted/*.png`

Current hooks:
- Terrain shader will automatically use `grass.png`, `dirt.png`, `rock.png` if present.
- Vehicle materials will use `dark-grey_44.png` if present (fallback: `game/textures/placeholders/metal.png`)
- Skybox will use `aurora001.png` if present (fallback: `game/textures/placeholders/aurora001.png`)

If you change extracted textures, restart the running game so resources reload cleanly.
