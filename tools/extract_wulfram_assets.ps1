param(
    [Parameter(Mandatory=$true)]
    [string]$WulframZip
)

$ErrorActionPreference = "Stop"

Write-Host "Wulfram zip:" $WulframZip

# Use the Python launcher if available.
$py = "py"
try { & $py -V | Out-Null } catch { $py = "python" }

Write-Host "Using python command:" $py

& $py tools\extract_wulfram_bitmaps.py "$WulframZip"
& $py tools\extract_wulfram_shapes.py "$WulframZip"

Write-Host "Done."
