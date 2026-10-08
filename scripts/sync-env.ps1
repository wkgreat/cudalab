# sync-env.ps1 - refresh env.json and regenerate the clangd compile database.
#
# env.json is the only file in the repository that knows anything about this
# machine. Everything else - the CMake cache and the compile database clangd
# reads - is derived from it. On a new machine, run this once (it detects the
# CUDA toolkit, the GPU's compute capability, the MSVC environment, the Windows
# SDK and CMake), correct anything it got wrong by hand, and carry on. Deleting
# env.json works too: it gets rewritten from detection.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/sync-env.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/sync-env.ps1 -Refresh
#   powershell -ExecutionPolicy Bypass -File scripts/sync-env.ps1 -Preset ninja-release

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
Write-Host '==> env.json (the only machine-specific file)' -ForegroundColor Cyan
Write-Host "    file         : $envPath"
Write-Host "    CUDA toolkit : $($cudalabEnv.cuda.root)   (sm_$($cudalabEnv.cuda.arch))"
Write-Host "    MSVC env     : $($cudalabEnv.msvc.vcvars64)"
Write-Host "    Windows SDK  : $($cudalabEnv.windowsSdk.ucrtInclude)"
Write-Host "    CMake        : $($cudalabEnv.cmake.path)"

# --- clangd's compile database ---------------------------------------------
# It is rendered from CMake's own database plus the paths above, so it has to
# wait for a configure to have happened.
$buildDir = Resolve-CudalabBuildDir -RepoRoot $repoRoot -Preset $Preset

if (-not (Test-Path (Join-Path $buildDir 'compile_commands.json'))) {
    Write-Host ''
    Write-Host "==> no build tree at $buildDir yet" -ForegroundColor Yellow
    Write-Host "    run: scripts/build-cmake.ps1 -Preset $Preset" -ForegroundColor Yellow
    return
}

$entryCount = New-CudalabClangDatabase -RepoRoot $repoRoot -BuildDir $buildDir -Env $cudalabEnv

Write-Host ''
Write-Host "==> clangd database: $entryCount entries (sources + headers)" -ForegroundColor Green
Write-Host "    $(Join-Path $repoRoot 'compile_commands.json')"
