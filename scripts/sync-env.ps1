# sync-env.ps1 - refresh env.json and regenerate the clangd compile database.
#
# On Windows env.json holds the paths pixi cannot supply: the CUDA toolkit, the
# MSVC environment and the Windows SDK. On Linux there is nothing to record -
# pixi supplies CMake, Ninja, clangd, CUDA and gcc - so the script only
# regenerates the clangd database. Either way CMake, Ninja and clangd come from
# pixi (pixi.toml) and the GPU's architecture from CMake's "native".
#
# Usage:
#   pixi run env
#   powershell -ExecutionPolicy Bypass -File scripts/sync-env.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/sync-env.ps1 -Refresh
#   pwsh -NoProfile -File scripts/sync-env.ps1 -Preset ninja-release

[CmdletBinding()]
param(
    # Which build tree holds CMake's compile_commands.json.
    [string]$Preset = 'ninja-debug',

    # Re-detect every value instead of keeping what env.json already has.
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot

$cudalabEnv = Get-CudalabEnv -RepoRoot $repoRoot -Refresh:$Refresh
$envPath = Get-CudalabEnvPath -RepoRoot $repoRoot

Write-Host ''
if (Test-CudalabWindows) {
    Write-Host '==> env.json (the only machine-specific file)' -ForegroundColor Cyan
    Write-Host "    file         : $envPath"
    Write-Host "    CUDA toolkit : $($cudalabEnv.cuda.root)"
    Write-Host "    MSVC env     : $($cudalabEnv.msvc.vcvars64)"
    Write-Host "    Windows SDK  : $($cudalabEnv.windowsSdk.ucrtInclude)"
}
else {
    Write-Host '==> Linux needs no env.json; refreshing the clangd database only' -ForegroundColor Cyan
    Write-Host "    CUDA toolkit : $($cudalabEnv.cuda.root)"
}

# --- clangd's compile database ---------------------------------------------
# It is rendered from CMake's own database plus the paths above, so it has to
# wait for a configure to have happened.
$buildDir = Resolve-CudalabBuildDir -RepoRoot $repoRoot -Preset $Preset

if (-not (Test-Path (Join-Path $buildDir 'compile_commands.json'))) {
    Write-Host ''
    Write-Host "==> no build tree at $buildDir yet" -ForegroundColor Yellow
    Write-Host "    configure first: pixi run build ($Preset)" -ForegroundColor Yellow
    return
}

$entryCount = New-CudalabClangDatabase -RepoRoot $repoRoot -BuildDir $buildDir -Env $cudalabEnv

Write-Host ''
Write-Host "==> clangd database: $entryCount entries (sources + headers)" -ForegroundColor Green
Write-Host "    $(Join-Path $repoRoot 'compile_commands.json')"
