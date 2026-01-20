# Tamaroyn - Launch a headless server locally.
#
# 1) Edit $GODOT_EXE to point at your Godot 4.5.1 executable.
# 2) From the project folder, run:
#      powershell -ExecutionPolicy Bypass -File tools\run_server.ps1
#
# Optional args:
#   -Port 2456
#   -Map  aberdour

param(
  [int]$Port = 2456,
  [string]$Map = "aberdour"
)

$GODOT_EXE = "C:\Path\To\Godot_v4.5.1-stable_win64.exe"  # <-- EDIT THIS

$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot "..")

$Args = @(
  "--headless",
  "--path", $ProjectDir,
  "-s", "res://tools/boot_server.gd",
  "--",
  "--port", $Port,
  "--map", $Map
)

Write-Host "Launching Server on port $Port (map: $Map)..."
& $GODOT_EXE @Args
