# Running multiple clients (local multiplayer test)

This project is configured so that the **default main scene** is the client:
`res://game/GameClient.tscn`.

## Option A: Use the helper scripts (recommended)

In `tools/`, there are scripts that launch one or two client processes.

1. Edit the script and set `GODOT_EXE` (the full path to your Godot v4.5.1 executable).
2. Run the script:
   - Windows (PowerShell): `tools/run_two_clients.ps1`
   - Windows (CMD): `tools/run_client_1.bat` and `tools/run_client_2.bat`

Each client is launched with command-line user args (what `GameClient.gd` reads):
`--connect 127.0.0.1 --port 2456`

## Option B: Use Godot Editor “Run Multiple Instances”

If you prefer the editor:

1. Open the project in Godot.
2. In the top menu: **Debug → Run Multiple Instances...**
3. Set “Instances” to 2 (or more), then run.

## Targeting

Press **TAB** to cycle targets. Hunter missiles require an active target.
