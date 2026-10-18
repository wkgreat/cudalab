# setup-vcpkg.ps1 - bootstrap the vcpkg checkout pixi manages for this project.
#
# Clones microsoft/vcpkg into .vcpkg/ at the repository root and bootstraps it.
# The clone is full (not --depth 1) on purpose: vcpkg resolves the manifest's
# builtin-baseline through git, which needs the baseline commit present locally.
#
# Re-running is cheap: an existing .vcpkg/ is left alone, and an existing vcpkg
# binary skips the bootstrap. CMakeLists.txt picks the directory up on its own,
# so VCPKG_ROOT does not have to be set by hand.
#
# Usage:
#   pixi run vcpkg
#   powershell -ExecutionPolicy Bypass -File scripts/setup-vcpkg.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/setup-vcpkg.ps1 -Force

[CmdletBinding()]
param(
    # vcpkg repository to clone from; override to use a fork or a local mirror.
    [string]$Repo = 'https://github.com/microsoft/vcpkg',

    # Throw away an existing .vcpkg/ and clone again.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$vcpkgDir = Join-Path $repoRoot '.vcpkg'

$onWindows = if ($null -ne $IsWindows) { [bool]$IsWindows } else { $env:OS -eq 'Windows_NT' }

if ($Force -and (Test-Path $vcpkgDir)) {
    Write-Host "==> removing $vcpkgDir" -ForegroundColor Yellow
    Remove-Item -Recurse -Force $vcpkgDir
}

if (-not (Test-Path $vcpkgDir)) {
    Write-Host "==> git clone $Repo -> $vcpkgDir" -ForegroundColor Cyan
    git clone $Repo $vcpkgDir
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }
}

if ($onWindows) {
    $bootstrapper = Join-Path $vcpkgDir 'bootstrap-vcpkg.bat'
    $vcpkgExe = Join-Path $vcpkgDir 'vcpkg.exe'
}
else {
    $bootstrapper = Join-Path $vcpkgDir 'bootstrap-vcpkg.sh'
    $vcpkgExe = Join-Path $vcpkgDir 'vcpkg'
}

if (-not (Test-Path $vcpkgExe)) {
    Write-Host '==> bootstrapping vcpkg' -ForegroundColor Cyan
    if ($bootstrapper -like '*.bat') {
        cmd /c "`"$bootstrapper`" -disableMetrics"
    }
    else {
        & $bootstrapper -disableMetrics
    }
    if ($LASTEXITCODE -ne 0) {
        throw "vcpkg bootstrap failed with exit code $LASTEXITCODE"
    }
}

Write-Host ''
Write-Host "==> vcpkg ready: $vcpkgExe" -ForegroundColor Green
Write-Host "    manifest   : $(Join-Path $repoRoot 'vcpkg.json')"
