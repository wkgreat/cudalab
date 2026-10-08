# common.ps1 - helpers shared by the scripts in this directory.
#
# Not meant to be run directly; dot-source it:
#     . (Join-Path $PSScriptRoot 'common.ps1')

# Every demo under src/demos that has sources, sorted by name.
# Each entry: Name, Dir, Sources (absolute paths), HasCuda.
# Directories without sources (a demo still being started) are skipped.
function Get-CudalabDemos {
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    $demosDir = Join-Path $RepoRoot 'src\demos'
    if (-not (Test-Path $demosDir)) {
        throw "demo directory not found: $demosDir"
    }

    $demos = @()
    foreach ($dir in (Get-ChildItem $demosDir -Directory | Sort-Object Name)) {
        $sources = @(Get-ChildItem $dir.FullName -File |
                Where-Object { $_.Extension -in '.cu', '.cpp', '.cxx', '.cc' } |
                Sort-Object Name)

        if ($sources.Count -eq 0) {
            continue
        }

        $demos += [pscustomobject]@{
            Name    = $dir.Name
            Dir     = $dir.FullName
            Sources = @($sources | Select-Object -ExpandProperty FullName)
            HasCuda = [bool]($sources | Where-Object { $_.Extension -eq '.cu' })
        }
    }

    return $demos
}

# Filter a demo list by name; an empty name selects everything. Throws with the
# available names when the requested demo does not exist.
function Select-CudalabDemo {
    param(
        [Parameter(Mandatory)][object[]]$Demos,
        [string]$Name = ''
    )

    if (-not $Name) {
        return $Demos
    }

    $match = @($Demos | Where-Object { $_.Name -eq $Name })
    if ($match.Count -eq 0) {
        $available = ($Demos | Select-Object -ExpandProperty Name) -join ', '
        throw "demo '$Name' not found. Available demos: $available"
    }

    return $match
}

# Install path of the Visual Studio providing cl.exe, which nvcc needs as its
# host compiler on Windows.
function Get-CudalabMsvcInstallPath {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) {
        throw 'vswhere.exe not found; install Visual Studio with the C++ workload (nvcc needs cl.exe as its host compiler).'
    }

    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) {
        throw 'No Visual Studio installation with the MSVC C++ toolset was found (nvcc needs cl.exe as its host compiler).'
    }

    return $vsPath
}

# The MSVC environment script for that install.
#
# env.json wins when it points at a file that exists, so a machine where vswhere
# cannot find the toolset only needs env.json edited by hand.
function Get-CudalabVcVars {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $envPath = Join-Path $repoRoot 'env.json'
    if (Test-Path $envPath) {
        try {
            $fromFile = (Get-Content $envPath -Raw | ConvertFrom-Json).msvc.vcvars64
            if ($fromFile -and (Test-Path $fromFile)) {
                return $fromFile
            }
        }
        catch {
            # A malformed env.json is reported by Get-CudalabEnv; detection here
            # just carries on.
        }
    }

    $vsPath = Get-CudalabMsvcInstallPath

    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat not found under '$vsPath'."
    }

    return $vcvars
}

# Run a command line inside the MSVC environment. Returns the exit code.
#
# Ninja needs cl.exe on PATH, so every CMake invocation goes through vcvars64
# first. Native tools also write progress to stderr, and Windows PowerShell 5.1
# turns a captured stderr stream into a terminating error while
# $ErrorActionPreference is 'Stop'; relax it here and judge success by the exit
# code instead.
function Invoke-InCudalabEnv {
    param(
        [Parameter(Mandatory)][string]$VcVars,
        [Parameter(Mandatory)][string]$CommandLine
    )

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        # Piping the native stdout through Out-Host is load-bearing: without it
        # that output joins this function's return value, and the caller would
        # compare cmake's console text (plus the exit code) against 0 instead of
        # just the exit code. Out-Host still streams it live to the console,
        # and stderr is left alone so real diagnostics keep their own stream.
        cmd /c "call `"$VcVars`" >nul 2>&1 && $CommandLine" | Out-Host
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

# Join arguments into a command line, quoting the ones that contain spaces.
function Format-CudalabCommandLine {
    param(
        [Parameter(Mandatory)][string[]]$Arguments
    )

    return (($Arguments | ForEach-Object {
                if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
            }) -join ' ')
}

# Read a configure preset's binary directory from CMakePresets.json.
function Resolve-CudalabBuildDir {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string]$Preset = 'ninja-debug'
    )

    $presetsPath = Join-Path $RepoRoot 'CMakePresets.json'
    $presets = Get-Content $presetsPath -Raw | ConvertFrom-Json

    $configurePreset = $presets.configurePresets | Where-Object { $_.name -eq $Preset }
    if (-not $configurePreset) {
        throw "configure preset '$Preset' is not defined in CMakePresets.json"
    }

    return ($configurePreset.binaryDir -replace '\$\{sourceDir\}', $RepoRoot)
}

# Every demo executable present in a build directory, restricted to $Demos when
# a list is given.
function Get-CudalabBuiltExecutables {
    param(
        [Parameter(Mandatory)][string]$BuildDir,
        [object[]]$Demos = @()
    )

    if (-not (Test-Path $BuildDir)) {
        throw "build directory not found: $BuildDir (build the demos first)"
    }

    $names = if ($Demos.Count -gt 0) { @($Demos | Select-Object -ExpandProperty Name) } else { $null }

    $found = @()
    foreach ($exe in (Get-ChildItem $BuildDir -Filter '*.exe' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        if ($names -and ($names -notcontains $exe.BaseName)) {
            continue
        }
        $found += $exe
    }

    return $found
}

# ---------------------------------------------------------------------------
# env.json - the one file that knows anything about this machine
#
# CUDA toolkit root and compute capability, the MSVC environment script, the
# Windows SDK UCRT include directory and CMake's location all live there. Every
# other artifact (the CMake cache, compile_commands.json) is derived from it, so
# moving to another machine means refreshing that single file - or deleting it
# and letting the detection below write a fresh one.
# ---------------------------------------------------------------------------

function Get-CudalabEnvPath {
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    return (Join-Path $RepoRoot 'env.json')
}

# Read env.json, detecting and writing it when it is missing, unreadable or
# incomplete, or when -Refresh asks for it.
function Get-CudalabEnv {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [switch]$Refresh
    )

    $path = Get-CudalabEnvPath -RepoRoot $RepoRoot

    if (-not $Refresh -and (Test-Path $path)) {
        try {
            $loaded = Get-Content $path -Raw | ConvertFrom-Json
            if ($loaded.cuda.root -and $loaded.cuda.arch -and
                $loaded.msvc.vcvars64 -and $loaded.windowsSdk.ucrtInclude -and
                $loaded.cmake.path) {
                return $loaded
            }
            Write-Host '==> env.json is incomplete; detecting again' -ForegroundColor Yellow
        }
        catch {
            Write-Host "==> env.json is unreadable ($($_.Exception.Message)); detecting again" -ForegroundColor Yellow
        }
    }

    return (New-CudalabEnv -RepoRoot $RepoRoot)
}

# Detect this machine's paths and write env.json. Detection is deliberately
# best-effort and transparent: every value it finds can be corrected by hand.
function New-CudalabEnv {
    param(
        [Parameter(Mandatory)][string]$RepoRoot
    )

    Write-Host '==> detecting this machine and writing env.json' -ForegroundColor Cyan

    # --- CUDA toolkit -------------------------------------------------------
    $cudaRoot = $env:CUDA_PATH
    if (-not $cudaRoot -or -not (Test-Path $cudaRoot)) {
        $nvcc = (Get-Command nvcc -ErrorAction SilentlyContinue).Source
        if ($nvcc) {
            $cudaRoot = Split-Path -Parent (Split-Path -Parent $nvcc)
        }
    }
    if (-not $cudaRoot -or -not (Test-Path $cudaRoot)) {
        throw 'CUDA toolkit not found: set CUDA_PATH or put nvcc on PATH, then retry.'
    }
    $cudaRoot = $cudaRoot -replace '\\', '/'

    # --- compute capability of the installed GPU ----------------------------
    $arch = '120'
    try {
        $capability = (& nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>$null | Select-Object -First 1)
        if ($capability -and ($capability.Trim() -match '^(\d+)\.(\d+)$')) {
            $arch = "$($Matches[1])$($Matches[2])"
        }
    }
    catch {
        # No GPU or no driver: keep the fallback and let the user correct it.
    }

    # --- MSVC environment ---------------------------------------------------
    $vsPath = Get-CudalabMsvcInstallPath
    $vcvars = Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
    if (-not (Test-Path $vcvars)) {
        throw "vcvars64.bat not found under '$vsPath'."
    }

    # --- Windows SDK UCRT include ------------------------------------------
    $sdkInclude = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\Include'
    $ucrt = $null
    if (Test-Path $sdkInclude) {
        $ucrt = Get-ChildItem $sdkInclude -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'ucrt' } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
    }
    if (-not $ucrt) {
        throw "Windows SDK UCRT include directory not found under '$sdkInclude'."
    }

    # --- CMake --------------------------------------------------------------
    $cmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
    if (-not $cmake) {
        $cmake = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    }

    # Written by hand rather than ConvertTo-Json: this file is meant to be read
    # and corrected by a human on a new machine, and ConvertTo-Json's indentation
    # is unreadable for that. No BOM either - CMake reads it with string(JSON ...)
    # and a BOM would end up inside the first key.
    $json = @"
{
  "_comment": "Machine-specific paths for this checkout. Regenerate with scripts/sync-env.ps1 -Refresh; everything else is derived from here.",
  "cuda": {
    "root": "$cudaRoot",
    "arch": "$arch"
  },
  "msvc": {
    "vcvars64": "$($vcvars -replace '\\', '/')"
  },
  "windowsSdk": {
    "ucrtInclude": "$($ucrt -replace '\\', '/')"
  },
  "cmake": {
    "path": "$($cmake -replace '\\', '/')"
  }
}
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Get-CudalabEnvPath -RepoRoot $RepoRoot), $json, $utf8NoBom)

    return ($json | ConvertFrom-Json)
}

# ---------------------------------------------------------------------------
# clangd compile database
#
# clangd cannot be pointed at CMake's database directly: those command lines are
# nvcc for the .cu files and cl.exe for the .cpp files, and -- more subtly --
# headers are never compiled, so they have no entry at all and clangd guesses one
# from a neighbouring source file. Instead of patching that up with a .clangd
# file full of machine paths, this renders a clang-native database covering every
# source *and* every header, with the paths taken from env.json.
# ---------------------------------------------------------------------------

# Split a command line into arguments, honouring double quotes.
function Split-CudalabCommandLine {
    param(
        [Parameter(Mandatory)][string]$CommandLine
    )

    $tokens = @()
    $current = ''
    $inQuotes = $false

    foreach ($character in $CommandLine.ToCharArray()) {
        if ($character -eq '"') {
            $inQuotes = -not $inQuotes
            continue
        }
        if (-not $inQuotes -and [char]::IsWhiteSpace($character)) {
            if ($current) {
                $tokens += $current
                $current = ''
            }
            continue
        }
        $current += $character
    }
    if ($current) {
        $tokens += $current
    }

    return $tokens
}

# Pull include directories and preprocessor defines out of a CMake command line.
function Get-CudalabCommandFlags {
    param(
        [Parameter(Mandatory)][string]$CommandLine
    )

    $tokens = Split-CudalabCommandLine -CommandLine $CommandLine
    $includes = @()
    $defines = @()

    for ($i = 0; $i -lt $tokens.Count; ++$i) {
        $token = $tokens[$i]

        if ($token -eq '-I' -or $token -eq '/I' -or $token -eq '-isystem' -or $token -eq '-imsvc') {
            if ($i + 1 -lt $tokens.Count) {
                $includes += $tokens[$i + 1]
                ++$i
            }
        }
        elseif ($token -like '-I?*' -or $token -like '/I?*') {
            $includes += $token.Substring(2)
        }
        elseif ($token -like '-external:I?*' -or $token -like '/external:I?*') {
            $includes += $token.Substring(11)
        }
        elseif ($token -like '-isystem?*') {
            $includes += $token.Substring(9)
        }
        elseif ($token -eq '-D' -or $token -eq '/D') {
            if ($i + 1 -lt $tokens.Count) {
                $defines += $tokens[$i + 1]
                ++$i
            }
        }
        elseif ($token -like '-D?*' -or $token -like '/D?*') {
            $defines += $token.Substring(2)
        }
    }

    return [pscustomobject]@{
        Includes = $includes
        Defines  = $defines
        # /MDd and -MDd imply _DEBUG for the MSVC headers.
        Debug    = (($tokens -contains '-MDd') -or ($tokens -contains '/MDd'))
    }
}

# Render a clang-native compile_commands.json at the repository root, where
# clangd finds it on its own. Returns the number of entries written.
function New-CudalabClangDatabase {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$BuildDir,
        [Parameter(Mandatory)][object]$Env
    )

    $cmakeDb = Join-Path $BuildDir 'compile_commands.json'
    if (-not (Test-Path $cmakeDb)) {
        throw "compile_commands.json not found in '$BuildDir'; configure the project first."
    }

    $cudaRoot = $Env.cuda.root -replace '\\', '/'
    $ucrt = $Env.windowsSdk.ucrtInclude -replace '\\', '/'

    # Added by this generator; dropped from the copied flags to avoid duplicates.
    $managedIncludes = @($ucrt, "$cudaRoot/include", "$cudaRoot/include/cccl") |
        ForEach-Object { $_.ToLowerInvariant() }

    $systemIncludes = @(
        '-isystem', $ucrt
        '-isystem', "$cudaRoot/include"
        '-isystem', "$cudaRoot/include/cccl"
    )
    $cudaFlags = @(
        '-x', 'cuda'
        "--cuda-path=$cudaRoot"
        "--cuda-gpu-arch=sm_$($Env.cuda.arch)"
        '-Wno-unknown-cuda-version'
    )

    $buildDirSlash = $BuildDir -replace '\\', '/'
    $entries = @()
    $byFile = @{}

    foreach ($item in (Get-Content $cmakeDb -Raw | ConvertFrom-Json)) {
        $file = $item.file -replace '\\', '/'
        $flags = Get-CudalabCommandFlags -CommandLine $item.command
        $isCuda = $file -match '\.cu$'

        $arguments = @('clang++')
        if ($isCuda) {
            $arguments += $cudaFlags
        }
        else {
            $arguments += @('-x', 'c++')
        }
        $arguments += @('-std=c++17')
        $arguments += $systemIncludes

        foreach ($include in $flags.Includes) {
            $normalized = $include -replace '\\', '/'
            if ($managedIncludes -notcontains $normalized.ToLowerInvariant()) {
                $arguments += @('-I', $normalized)
            }
        }
        if ($flags.Debug) {
            $arguments += '-D_DEBUG'
        }
        foreach ($define in $flags.Defines) {
            $arguments += "-D$define"
        }
        $arguments += @('-c', $file)

        $entry = [pscustomobject]@{
            directory = $buildDirSlash
            file      = $file
            arguments = $arguments
        }
        $entries += $entry
        $byFile[$file.ToLowerInvariant()] = $entry
    }

    if ($entries.Count -eq 0) {
        throw "no translation units found in '$cmakeDb'."
    }

    # Give every header an explicit entry, so clangd never has to guess one from a
    # neighbouring source. Headers are parsed as CUDA, which accepts plain C++ too.
    $headers = Get-ChildItem (Join-Path $RepoRoot 'src') -Recurse -File -Include '*.h', '*.cuh', '*.hpp', '*.hxx' -ErrorAction SilentlyContinue
    foreach ($header in $headers) {
        $file = $header.FullName -replace '\\', '/'
        if ($byFile.ContainsKey($file.ToLowerInvariant())) {
            continue
        }

        # Model the header on the source that shares its name, else on a source in
        # the same directory, else on any source at all.
        $donor = $entries | Where-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.file) -eq $header.BaseName
        } | Select-Object -First 1
        if (-not $donor) {
            $donor = $entries | Where-Object {
                [System.IO.Path]::GetDirectoryName($_.file) -eq ($header.DirectoryName -replace '\\', '/')
            } | Select-Object -First 1
        }
        if (-not $donor) {
            $donor = $entries[0]
        }

        $headerIncludes = @()
        $headerDefines = @()
        for ($i = 0; $i -lt $donor.arguments.Count; ++$i) {
            $token = $donor.arguments[$i]
            if ($token -eq '-I' -and ($i + 1) -lt $donor.arguments.Count) {
                $headerIncludes += $donor.arguments[$i + 1]
                ++$i
            }
            elseif ($token -eq '-D_DEBUG' -or $token -like '-D?*') {
                $headerDefines += $token
            }
        }

        $arguments = @('clang++') + $cudaFlags + @('-std=c++17') + $systemIncludes
        foreach ($include in $headerIncludes) {
            $arguments += @('-I', $include)
        }
        $arguments += $headerDefines
        $arguments += @('-c', $file)

        $entries += [pscustomobject]@{
            directory = $buildDirSlash
            file      = $file
            arguments = $arguments
        }
    }

    $json = ConvertTo-Json -InputObject @($entries) -Depth 6
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $RepoRoot 'compile_commands.json'), $json, $utf8NoBom)

    return $entries.Count
}
