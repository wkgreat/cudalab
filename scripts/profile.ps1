# profile.ps1 - profile a demo executable with Nsight Compute or Nsight Systems.
#
# Neither tool is on PATH in a normal shell: the CUDA toolkit installer puts
# them under "C:\Program Files\NVIDIA Corporation\Nsight ..." instead. This
# script finds them and runs the tool against an executable produced by the
# CMake build.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/profile.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/profile.ps1 -Demo demo_add_one
#   powershell -ExecutionPolicy Bypass -File scripts/profile.ps1 -Preset ninja-release
#   powershell -ExecutionPolicy Bypass -File scripts/profile.ps1 -Tool systems
#   powershell -ExecutionPolicy Bypass -File scripts/profile.ps1 -Set full
#   powershell -ExecutionPolicy Bypass -File scripts/profile.ps1 -Exe build\ninja-debug\demo_add_one.exe

[CmdletBinding()]
param(
    [ValidateSet('compute', 'systems')]
    [string]$Tool = 'compute',

    # Demo to profile; empty picks the first demo found under src/demos.
    [string]$Demo = '',

    # Which CMake build tree holds the executable.
    [string]$Preset = 'ninja-debug',

    # Explicit executable path, relative to the repository root unless
    # absolute. Overrides -Demo / -Preset.
    [string]$Exe = '',

    # Nsight Compute section set: basic, detailed, full, or a section name.
    [string]$Set = 'detailed',

    # Directory for the report files.
    [string]$OutDir = 'profiles'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot

# --- Resolve the executable -------------------------------------------------
if (-not $Exe) {
    $demos = @(Get-CudalabDemos -RepoRoot $repoRoot)
    if ($demos.Count -eq 0) {
        throw "no demos with sources found under $(Join-Path $repoRoot 'src\demos')"
    }
    $selected = @(Select-CudalabDemo -Demos $demos -Name $Demo)[0]
    $Exe = Join-Path (Resolve-CudalabBuildDir -RepoRoot $repoRoot -Preset $Preset) "$($selected.Name).exe"
}

$exePath = if ([System.IO.Path]::IsPathRooted($Exe)) { $Exe } else { Join-Path $repoRoot $Exe }

if (-not (Test-Path $exePath)) {
    throw "executable not found: $exePath (build it first, e.g. scripts/build-cmake.ps1 -Preset $Preset)"
}

$outPath = Join-Path $repoRoot $OutDir
New-Item -ItemType Directory -Force -Path $outPath | Out-Null

# --- Locate the requested profiler ------------------------------------------
$nsightRoot = Join-Path $env:ProgramFiles 'NVIDIA Corporation'
$searchRoots = @()
if ($Tool -eq 'compute') {
    $searchRoots += (Get-ChildItem $nsightRoot -Directory -Filter 'Nsight Compute*' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
    $toolName = 'ncu.exe'
}
else {
    $searchRoots += (Get-ChildItem $nsightRoot -Directory -Filter 'Nsight Systems*' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName)
    $toolName = 'nsys.exe'
}

$toolPath = $null
foreach ($root in $searchRoots) {
    $found = Get-ChildItem $root -Recurse -Filter $toolName -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if ($found) { $toolPath = $found; break }
}

if (-not $toolPath) {
    throw "$toolName not found under '$nsightRoot'; install Nsight Compute / Nsight Systems."
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)

# Profilers write progress to stderr; Windows PowerShell 5.1 would turn that
# into a terminating error while $ErrorActionPreference is 'Stop'.
$previousPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

if ($Tool -eq 'compute') {
    $report = Join-Path $outPath "$baseName-ncu-$stamp"
    Write-Host "==> ncu --set $Set  -> $report.ncu-rep" -ForegroundColor Cyan
    & $toolPath --set $Set --launch-count 1 --export $report --force-overwrite $exePath
}
else {
    $report = Join-Path $outPath "$baseName-nsys-$stamp"
    Write-Host "==> nsys profile  -> $report.nsys-rep" -ForegroundColor Cyan
    & $toolPath profile --force-overwrite true --output $report $exePath
    $profileExit = $LASTEXITCODE

    if ($profileExit -eq 0) {
        Write-Host '==> nsys stats' -ForegroundColor Cyan
        & $toolPath stats "$report.nsys-rep"
    }
}

$toolExit = $LASTEXITCODE
$ErrorActionPreference = $previousPreference

if ($toolExit -ne 0) {
    throw "$toolName exited with code $toolExit"
}

Write-Host "==> report written to $outPath" -ForegroundColor Green
