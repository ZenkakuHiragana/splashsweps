<#
.SYNOPSIS
Runs the SplashSWEPs autonomous render-test harness through DATA files.

.DESCRIPTION
This script writes data/splashsweps/render_tests/request.json, optionally
launches Garry's Mod, waits for the matching result.json, prints it, and exits
with a status code based on the harness result.

Exit codes:
  0: pass
  1: fail, error, timeout, or script error
  2: unsupported
#>
[CmdletBinding()]
param(
    [string]$Case = "all",
    [string]$Map = "gm_construct",
    [int]$Width = 1024,
    [int]$Height = 768,
    [int]$TimeoutSeconds = 180,
    [int]$LockWaitSeconds = 300,
    [string]$RequestId = "",
    [switch]$NoLaunch,
    [switch]$Launch,
    [switch]$CloseAfterRun,
    [switch]$CapturePng,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Value, $encoding)
}

function Read-JsonWhenStable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $raw = Get-Content -LiteralPath $Path -Raw
        $json = $raw | ConvertFrom-Json
        return @{
            Raw = $raw
            Json = $json
        }
    }
    catch {
        return $null
    }
}

$addonRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$garrysmodDir = Split-Path -Parent (Split-Path -Parent $addonRoot)
$installRoot = Split-Path -Parent $garrysmodDir
$dataRoot = Join-Path $garrysmodDir "data"
$requestRoot = Join-Path $dataRoot "splashsweps\render_tests"
$runsRoot = Join-Path $requestRoot "runs"
$requestPath = Join-Path $requestRoot "request.json"
$lockPath = Join-Path $requestRoot "driver.lock"
$gmodExe = Join-Path $installRoot "gmod.exe"

if ([string]::IsNullOrWhiteSpace($RequestId)) {
    $RequestId = "codex-{0}" -f (Get-Date -Format "yyyyMMddTHHmmssfff")
}

$request = [ordered]@{
    request_id = $RequestId
    source = "powershell"
    case = $Case
    map = $Map
    resolution = @($Width, $Height)
    timeout_seconds = $TimeoutSeconds
    close_after_run = [bool]$CloseAfterRun
    capture_png = [bool]$CapturePng
    write_metrics = $true
}

New-Item -ItemType Directory -Force -Path $requestRoot | Out-Null
New-Item -ItemType Directory -Force -Path $runsRoot | Out-Null

$lockDeadline = (Get-Date).AddSeconds($LockWaitSeconds)
$lockAcquired = $false
while (-not $lockAcquired) {
    try {
        New-Item -ItemType Directory -Path $lockPath -ErrorAction Stop | Out-Null
        $lockAcquired = $true
    }
    catch {
        if ((Get-Date) -ge $lockDeadline) {
            throw "Timed out waiting for render-test driver lock: $lockPath"
        }
        Start-Sleep -Seconds 1
    }
}

try {
Write-Utf8NoBom -Path $requestPath -Value ($request | ConvertTo-Json -Depth 8)

if (-not $Quiet) {
    Write-Host ("request_id={0}" -f $RequestId)
    Write-Host ("request_path={0}" -f $requestPath)
}

$processes = @(Get-Process -Name "gmod" -ErrorAction SilentlyContinue)
$shouldLaunch = $Launch -or ((-not $NoLaunch) -and ($processes.Count -eq 0))

if ($shouldLaunch) {
    if (-not (Test-Path -LiteralPath $gmodExe)) {
        throw "Garry's Mod executable was not found: $gmodExe"
    }

    $args = @(
        "-game", "garrysmod",
        "-windowed",
        "-w", [string]$Width,
        "-h", [string]$Height,
        "-allowquit",
        "-systemtest",
        "+map", $Map
    )

    if (-not $Quiet) {
        Write-Host ("launching={0}" -f $gmodExe)
    }

    Start-Process -FilePath $gmodExe -ArgumentList $args -WorkingDirectory $installRoot | Out-Null
}
elseif (-not $Quiet) {
    if ($processes.Count -gt 0) {
        Write-Host "using_existing_gmod=true"
    }
    else {
        Write-Host "using_existing_gmod=false"
    }
}

$runDir = Join-Path $runsRoot $RequestId
$statusPath = Join-Path $runDir "status.json"
$resultPath = Join-Path $runDir "result.json"
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$lastStatus = ""
$scriptExitCode = $null

while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $resultPath) {
        $result = Read-JsonWhenStable -Path $resultPath
        if ($result -ne $null) {
            Write-Output $result.Raw
            $statusValue = [string]$result.Json.status
            if ($statusValue -eq "pass") {
                $scriptExitCode = 0
            }
            elseif ($statusValue -eq "unsupported") {
                $scriptExitCode = 2
            }
            else {
                $scriptExitCode = 1
            }
            break
        }
    }

    if ((-not $Quiet) -and (Test-Path -LiteralPath $statusPath)) {
        $status = Read-JsonWhenStable -Path $statusPath
        if ($status -ne $null -and $status.Raw -ne $lastStatus) {
            $lastStatus = $status.Raw
            Write-Host $lastStatus
        }
    }

    Start-Sleep -Seconds 1
}

if ($null -eq $scriptExitCode) {
    if (Test-Path -LiteralPath $statusPath) {
        Write-Host "--- last status ---"
        Get-Content -LiteralPath $statusPath
    }

    throw "Timed out waiting for result.json: $resultPath"
}
}
finally {
    if ($lockAcquired) {
        Remove-Item -LiteralPath $lockPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $scriptExitCode
