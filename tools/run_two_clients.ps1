# Tamaroyn - Launch two client instances locally.

$GODOT_EXE = "C:\Path\To\Godot_v4.5.1-stable_win64.exe"  # <-- EDIT THIS

$ProjectDir = Resolve-Path (Join-Path $PSScriptRoot "..")

$Args = @(
  "--path", $ProjectDir,
  "--",
  "--connect", "127.0.0.1",
  "--port", "2456"
)

Write-Host "Launching Client #1..."
Start-Process -FilePath $GODOT_EXE -ArgumentList $Args

Start-Sleep -Milliseconds 500

Write-Host "Launching Client #2..."
Start-Process -FilePath $GODOT_EXE -ArgumentList $Args

Write-Host "Done."
