param(
    [switch]$SkipSubmodules,
    [switch]$SkipBuild,
    [switch]$SkipPortablePack
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Info {
    param([string]$Message)
    Write-Host "[monitoring-windows] $Message"
}

function Assert-Windows {
    $platform = [System.Environment]::OSVersion.Platform
    $isWindows = $platform -eq [System.PlatformID]::Win32NT
    if (-not $isWindows) {
        throw "This script must run on Windows."
    }
}

function Get-RepoRoot {
    $scriptDir = Split-Path -Parent $PSCommandPath
    return (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Test-CommandAvailable {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-UsableCommandPath {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $commands = @(Get-Command $name -All -ErrorAction SilentlyContinue)
        foreach ($command in $commands) {
            if ($null -eq $command -or [string]::IsNullOrWhiteSpace($command.Source)) {
                continue
            }

            if ($command.Source -like "*\\WindowsApps\\*") {
                continue
            }

            return $command.Source
        }

        if ($commands.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($commands[0].Source)) {
            return $commands[0].Source
        }
    }

    return $null
}

function Import-VsDevCmdEnvironment {
    if (Test-CommandAvailable "link.exe") {
        return $true
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        return $false
    }

    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ([string]::IsNullOrWhiteSpace($installPath)) {
        return $false
    }

    $vsDevCmd = Join-Path $installPath "Common7\Tools\VsDevCmd.bat"
    if (-not (Test-Path $vsDevCmd)) {
        return $false
    }

    Write-Info "Loading Visual Studio developer environment..."
    $envDump = & cmd /c "`"$vsDevCmd`" -arch=x64 && set"
    foreach ($line in $envDump) {
        if ($line -match "^(.*?)=(.*)$") {
            [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }

    return (Test-CommandAvailable "link.exe")
}

function Ensure-Tooling {
    if (-not (Test-CommandAvailable "git")) {
        throw "git is required."
    }
    if (-not (Test-CommandAvailable "cargo")) {
        throw "cargo is required."
    }
    if (-not (Test-CommandAvailable "flutter")) {
        throw "flutter is required and must be on PATH."
    }

    $hasLinker = Import-VsDevCmdEnvironment
    if (-not $hasLinker) {
        throw "link.exe was not found. Install Visual Studio Build Tools (Desktop development with C++) and re-run."
    }
}

function Enable-PythonCompatAliases {
    $pythonCmd = $null
    $shimPythonLine = $null
    $shimPipLine = $null
    $python3Path = Get-UsableCommandPath @("python3")
    $pythonPath = Get-UsableCommandPath @("python")
    $pyPath = Get-UsableCommandPath @("py")

    if ($python3Path) {
        $pythonCmd = $python3Path
        $shimPythonLine = "`"$pythonCmd`" %*"
        $shimPipLine = "`"$pythonCmd`" -m pip %*"
    } elseif ($pythonPath) {
        $pythonCmd = $pythonPath
        $shimPythonLine = "`"$pythonCmd`" %*"
        $shimPipLine = "`"$pythonCmd`" -m pip %*"
    } elseif ($pyPath) {
        $pythonCmd = $pyPath
        $shimPythonLine = "`"$pythonCmd`" -3 %*"
        $shimPipLine = "`"$pythonCmd`" -3 -m pip %*"
    } else {
        throw "Python is required (python3, py, or python)."
    }

    if ($python3Path -and (Get-UsableCommandPath @("pip3"))) {
        return $pythonCmd
    }

    $shimDir = Join-Path $env:TEMP "rustdesk-monitoring-python-shims"
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null

    $python3Shim = Join-Path $shimDir "python3.cmd"
    $pip3Shim = Join-Path $shimDir "pip3.cmd"

    if (-not (Test-Path $python3Shim)) {
@"
@echo off
$shimPythonLine
"@ | Set-Content -Path $python3Shim -NoNewline
    }
    if (-not (Test-Path $pip3Shim)) {
@"
@echo off
$shimPipLine
"@ | Set-Content -Path $pip3Shim -NoNewline
    }

    if (-not ($env:PATH -split ";" | Where-Object { $_ -eq $shimDir })) {
        $env:PATH = "$shimDir;$env:PATH"
    }

    return $pythonCmd
}

Assert-Windows
$repoRoot = Get-RepoRoot
Set-Location $repoRoot

Write-Info "Repo root: $repoRoot"
Ensure-Tooling
$pythonCmd = Enable-PythonCompatAliases

if (-not $SkipSubmodules) {
    Write-Info "Updating git submodules..."
    git submodule update --init --recursive
}

if ($SkipBuild) {
    Write-Info "Checks completed. Build skipped by -SkipBuild."
    exit 0
}

$buildArgs = @("build.py", "--flutter")
if ($SkipPortablePack) {
    $buildArgs += "--skip-portable-pack"
}

Write-Info "Building installer..."
if ((Split-Path $pythonCmd -Leaf) -ieq "py.exe" -or (Split-Path $pythonCmd -Leaf) -ieq "py") {
    & $pythonCmd -3 @buildArgs
} else {
    & $pythonCmd @buildArgs
}

$installer = Get-ChildItem -Path $repoRoot -Filter "rustdesk-*-install.exe" -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $installer) {
    if ($SkipPortablePack) {
        Write-Info "Build finished with -SkipPortablePack. No installer exe is expected."
        exit 0
    }
    throw "Build finished but no rustdesk-*-install.exe was found."
}

Write-Info "Installer generated: $($installer.FullName)"
