# export.ps1 - builds the Windows export into build/, copies the tracker.py sidecar and
# dist/README.txt beside it, and zips the three into build/PandaProd.zip for sharing.
# Requires the Godot 4.7.2 export templates (Editor > Manage Export Templates).
# Usage: ./export.ps1 [-DebugBuild]   (set $env:GODOT to override the Godot binary path)
# A release build by default: what ships. -DebugBuild adds PandaProd.console.exe (Godot output in
# a terminal) and opens a console for the sidecar, which prints every focused window's title.
param([switch]$DebugBuild)
$ErrorActionPreference = "Stop"

$godot = $env:GODOT
if (-not $godot) {
    $godot = "C:\Users\chase\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) { throw "Godot binary not found: $godot (set `$env:GODOT)" }

$build = Join-Path $PSScriptRoot "build"
$exe = Join-Path $build "PandaProd.exe"
New-Item -ItemType Directory -Force $build | Out-Null
# The console wrapper only comes with debug builds; don't leave an old one beside a release build.
foreach ($old in @($exe, (Join-Path $build "PandaProd.console.exe"))) {
    if (Test-Path $old) { Remove-Item $old }
}

$mode = if ($DebugBuild) { "--export-debug" } else { "--export-release" }
& $godot --headless --path $PSScriptRoot $mode "Windows Desktop" $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) { throw "Export failed (exit code $LASTEXITCODE)" }

Copy-Item (Join-Path $PSScriptRoot "sidecar/tracker.py") $build -Force
Copy-Item (Join-Path $PSScriptRoot "dist/README.txt") $build -Force
# The zip to hand out: everything a friend needs, in one download.
$zip = Join-Path $build "PandaProd.zip"
Compress-Archive -Force -DestinationPath $zip -Path $exe, (Join-Path $build "tracker.py"), (Join-Path $build "README.txt")
Write-Host "Exported $(if ($DebugBuild) { 'debug' } else { 'release' }) build to $build"
