# export.ps1 - builds a debug Windows test export into build/ and copies the tracker.py sidecar beside it.
# Requires the Godot 4.7.2 export templates (Editor > Manage Export Templates).
# Usage: ./export.ps1   (set $env:GODOT to override the Godot binary path)
$ErrorActionPreference = "Stop"

$godot = $env:GODOT
if (-not $godot) {
    $godot = "C:\Users\chase\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) { throw "Godot binary not found: $godot (set `$env:GODOT)" }

$build = Join-Path $PSScriptRoot "build"
$exe = Join-Path $build "PandaProd.exe"
New-Item -ItemType Directory -Force $build | Out-Null
if (Test-Path $exe) { Remove-Item $exe }

& $godot --headless --path $PSScriptRoot --export-debug "Windows Desktop" $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw "Export failed (exit code $LASTEXITCODE)" }

Copy-Item (Join-Path $PSScriptRoot "sidecar/tracker.py") $build -Force
Write-Host "Exported to $build"
