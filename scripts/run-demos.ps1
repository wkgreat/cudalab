# run-demos.ps1 - run the demo executables that have already been built.
#
# Each demo is self-checking: it prints PASS/FAIL and returns a non-zero exit
# code when the GPU result is wrong, so this script doubles as a smoke test.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/run-demos.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/run-demos.ps1 -Preset ninja-release
#   powershell -ExecutionPolicy Bypass -File scripts/run-demos.ps1 -Demo demo_add_one

[CmdletBinding()]
param(
    # Configure preset whose build tree holds the executables.
    [string]$Preset = 'ninja-debug',

    # Demo directory name to run; empty runs every built demo.
    [string]$Demo = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot

$buildDir = Resolve-CudalabBuildDir -RepoRoot $repoRoot -Preset $Preset
$demos = @(Select-CudalabDemo -Demos @(Get-CudalabDemos -RepoRoot $repoRoot) -Name $Demo)
$executables = @(Get-CudalabBuiltExecutables -BuildDir $buildDir -Demos $demos)

if ($executables.Count -eq 0) {
    throw "no built demo executable found under '$buildDir'. Build them first, e.g. scripts/build-cmake.ps1 -Preset $Preset"
}

# --- Run each demo and collect its exit code --------------------------------
$results = @()
foreach ($exe in $executables) {
    Write-Host ''
    Write-Host "==> $($exe.Name)" -ForegroundColor Cyan

    & $exe.FullName
    $exit = $LASTEXITCODE

    $results += [pscustomobject]@{
        Demo = $exe.BaseName
        Exit = $exit
        Pass = ($exit -eq 0)
    }
}

# --- Summary ----------------------------------------------------------------
Write-Host ''
Write-Host "==> results from $buildDir" -ForegroundColor Cyan
$results | Format-Table -AutoSize | Out-String | Write-Host

$failed = @($results | Where-Object { -not $_.Pass })
if ($failed.Count -gt 0) {
    Write-Host "==> FAILED: $(($failed | Select-Object -ExpandProperty Demo) -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "==> all $($results.Count) demo(s) passed" -ForegroundColor Green
