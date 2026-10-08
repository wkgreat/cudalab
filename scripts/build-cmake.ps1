# build-cmake.ps1 - configure and build the demos with CMake.
#
# This is the only build path for the project. Every demo under src/demos is one
# executable target; this script drives CMake for all of them, or for a single
# one with -Demo.
#
# Ninja needs cl.exe on PATH (nvcc uses MSVC as its host compiler on Windows),
# so the script imports the MSVC environment before calling CMake. That is the
# only reason Visual Studio appears here at all - the build system is CMake.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/build-cmake.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/build-cmake.ps1 -Preset ninja-release
#   powershell -ExecutionPolicy Bypass -File scripts/build-cmake.ps1 -Demo demo_add_one -Run
#   powershell -ExecutionPolicy Bypass -File scripts/build-cmake.ps1 -Clean
#   powershell -ExecutionPolicy Bypass -File scripts/build-cmake.ps1 -Run

[CmdletBinding()]
param(
    # Configure preset from CMakePresets.json.
    [string]$Preset = 'ninja-debug',

    # Demo directory name to build; empty builds every demo target.
    [string]$Demo = '',

    # Build preset name; defaults to the configure preset name.
    [string]$BuildPreset,

    # Delete the preset's binary directory before configuring.
    [switch]$Clean,

    # Run every built demo executable when the build succeeds.
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot

# The one file that knows this machine's paths; detected and written on first
# use, so a fresh checkout only needs the build to be run once.
$cudalabEnv = Get-CudalabEnv -RepoRoot $repoRoot

# --- Locate CMake -----------------------------------------------------------
# A standalone CMake on PATH always wins; env.json is the fallback for a machine
# where CMake is not on PATH, and Visual Studio's bundled copy the last resort.
$cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
if (-not $cmake -and $cudalabEnv.cmake.path -and (Test-Path $cudalabEnv.cmake.path)) {
    $cmake = $cudalabEnv.cmake.path
}
if (-not $cmake) {
    $cmake = Join-Path (Get-CudalabMsvcInstallPath) 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
}
if (-not (Test-Path $cmake)) {
    throw 'cmake.exe not found; install CMake (winget install Kitware.CMake) or use a shell where it is on PATH.'
}

# --- Resolve the presets ----------------------------------------------------
$presets = Get-Content (Join-Path $repoRoot 'CMakePresets.json') -Raw | ConvertFrom-Json
if (-not ($presets.configurePresets | Where-Object { $_.name -eq $Preset })) {
    $available = ($presets.configurePresets | Select-Object -ExpandProperty name) -join ', '
    throw "configure preset '$Preset' is not defined in CMakePresets.json. Available: $available"
}

if (-not $BuildPreset) {
    $BuildPreset = $Preset
}

$vcvars = Get-CudalabVcVars

$useFresh = $false
if ($Clean) {
    $configureDir = Resolve-CudalabBuildDir -RepoRoot $repoRoot -Preset $Preset
    if (Test-Path $configureDir) {
        try {
            Remove-Item -Recurse -Force $configureDir -ErrorAction Stop
            Write-Host "==> removed $configureDir" -ForegroundColor Yellow
        }
        catch {
            # A running editor, debugger or indexer can hold the directory open.
            # 'cmake --fresh' gives the same from-scratch configure without
            # deleting it.
            Write-Host "==> could not remove $configureDir" -ForegroundColor Yellow
            Write-Host "    ($($_.Exception.Message))" -ForegroundColor DarkGray
            Write-Host '==> falling back to cmake --fresh' -ForegroundColor Yellow
            $useFresh = $true
        }
    }
}

# --- Configure inside the MSVC environment ----------------------------------
$freshFlag = if ($useFresh) { ' --fresh' } else { '' }

Write-Host "==> cmake$freshFlag --preset $Preset" -ForegroundColor Cyan

$configureExit = Invoke-InCudalabEnv -VcVars $vcvars -CommandLine "`"$cmake`"$freshFlag --preset $Preset"

if ($configureExit -ne 0) {
    throw "CMake configure failed with exit code $configureExit"
}

# --- Refresh the compilation database clangd reads --------------------------
# Rendered from CMake's own database plus the paths in env.json, and done before
# the build on purpose: editing code that does not compile yet is exactly when
# IntelliSense matters. A failure here must not fail the build.
$buildDir = Resolve-CudalabBuildDir -RepoRoot $repoRoot -Preset $Preset
try {
    $entryCount = New-CudalabClangDatabase -RepoRoot $repoRoot -BuildDir $buildDir -Env $cudalabEnv
    Write-Host "==> clangd database: $entryCount entries -> $(Join-Path $repoRoot 'compile_commands.json')" -ForegroundColor DarkGray
}
catch {
    Write-Host "==> clangd database not refreshed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# --- Build ------------------------------------------------------------------
if ($Demo) {
    Write-Host "==> cmake --build --preset $BuildPreset --target $Demo" -ForegroundColor Cyan
    $buildCommand = "`"$cmake`" --build --preset $BuildPreset --target $Demo"
}
else {
    Write-Host "==> cmake --build --preset $BuildPreset" -ForegroundColor Cyan
    $buildCommand = "`"$cmake`" --build --preset $BuildPreset"
}

$buildExit = Invoke-InCudalabEnv -VcVars $vcvars -CommandLine $buildCommand

if ($buildExit -ne 0) {
    throw "CMake build failed with exit code $buildExit"
}

$demos = @(Select-CudalabDemo -Demos @(Get-CudalabDemos -RepoRoot $repoRoot) -Name $Demo)
$executables = @(Get-CudalabBuiltExecutables -BuildDir $buildDir -Demos $demos)

if ($executables.Count -eq 0) {
    throw "build succeeded but no demo executable was found under '$buildDir'."
}

foreach ($exe in $executables) {
    Write-Host "==> built $($exe.FullName)" -ForegroundColor Green
}

if ($Run) {
    $failed = @()
    foreach ($exe in $executables) {
        Write-Host "==> running $($exe.Name)" -ForegroundColor Cyan
        & $exe.FullName
        if ($LASTEXITCODE -ne 0) {
            $failed += $exe.BaseName
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host "==> run failures: $($failed -join ', ')" -ForegroundColor Red
        exit 1
    }
}
