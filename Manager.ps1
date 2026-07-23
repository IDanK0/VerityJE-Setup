<# Verity JE Manager - start/stop all AI services from one panel. #>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$services = [ordered]@{
    F = @{ name = "FastKoko (TTS)"; port = 8880; launcher = "FastKoko.ps1";
           check = "Kokoro-FastAPI\.venv\Scripts\uvicorn.exe"; url = "http://127.0.0.1:8880/v1/" }
    I = @{ name = "LiteLLM (AI)";   port = 4000; launcher = "LiteLLM.ps1";
           check = ""; url = "http://127.0.0.1:4000/v1/" }
    W = @{ name = "Whisper (STT)";  port = 9000; launcher = "WhisperLauncher.ps1";
           check = "WhisperServer\.venv\Scripts\python.exe"; url = "http://127.0.0.1:9000/v1/" }
}

function Test-Port($port) {
    try {
        return ($null -ne (Get-NetTCPConnection -LocalPort $port -State Listen -EA SilentlyContinue))
    } catch { return $false }
}

function Test-Installed($svc) {
    if ($svc.check) { return (Test-Path (Join-Path $scriptDir $svc.check)) }
    $cfgPath = Join-Path $scriptDir "config.psd1"
    if (Test-Path $cfgPath) {
        try {
            $cfg = Import-PowerShellDataFile $cfgPath
            if ($cfg.LiteLLMExe -and (Test-Path $cfg.LiteLLMExe)) { return $true }
        } catch { }
    }
    return ($null -ne (Get-Command litellm -EA SilentlyContinue))
}

function Start-VerityService($key) {
    $svc = $services[$key]
    if (Test-Port $svc.port) { Write-Host "  $($svc.name): already running" -F DarkGray; return }
    if (-not (Test-Installed $svc)) { Write-Host "  $($svc.name): not installed - run Setup.bat" -F Red; return }
    $launcher = Join-Path $scriptDir $svc.launcher
    if (-not (Test-Path $launcher)) { Write-Host "  $($svc.name): launcher missing ($($svc.launcher))" -F Red; return }
    Write-Host "  $($svc.name): starting..." -F Yellow
    Start-Process powershell -ArgumentList "-NoProfile", "-EP", "Bypass", "-File", "`"$launcher`"", "-ServerOnly" -WindowStyle Minimized
    $deadline = (Get-Date).AddSeconds(150)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Test-Port $svc.port) { Write-Host "  $($svc.name): RUNNING  $($svc.url)" -F Green; return }
    }
    Write-Host "  $($svc.name): not up yet - check logs\ folder" -F Red
}

function Stop-VerityService($key) {
    $svc = $services[$key]
    if (-not (Test-Port $svc.port)) { Write-Host "  $($svc.name): already stopped" -F DarkGray; return }
    Get-NetTCPConnection -LocalPort $svc.port -State Listen -EA SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue
    }
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline -and (Test-Port $svc.port)) { Start-Sleep -Milliseconds 500 }
    Write-Host "  $($svc.name): stopped" -F Yellow
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "================================================" -F Yellow
    Write-Host "  Verity JE - Manager" -F Yellow
    Write-Host "================================================" -F Yellow
    Write-Host "  [S] Start all   [A] Stop all   [R] Restart all" -F White
    Write-Host ""
    foreach ($key in $services.Keys) {
        $svc = $services[$key]
        $running = Test-Port $svc.port
        $installed = Test-Installed $svc
        if ($running)     { $status = "RUNNING"; $color = "Green" }
        elseif ($installed) { $status = "OFF    "; $color = "DarkGray" }
        else              { $status = "MISSING"; $color = "Red" }
        Write-Host ("  [{0}] {1,-16} {2,-8} {3}" -f $key, $svc.name, $status, $svc.url) -F $color
    }
    Write-Host ""
    Write-Host "  [Q] Quit (stops services)" -F Yellow
    Write-Host ""
}

:main while ($true) {
    Show-Menu
    $choice = (Read-Host "Choice").ToUpper()
    switch ($choice) {
        "S" { foreach ($key in $services.Keys) { Start-VerityService $key } }
        "A" { foreach ($key in $services.Keys) { Stop-VerityService $key } }
        "R" {
            foreach ($key in $services.Keys) { Stop-VerityService $key }
            foreach ($key in $services.Keys) { Start-VerityService $key }
        }
        "F" { Start-VerityService "F" }
        "I" { Start-VerityService "I" }
        "W" { Start-VerityService "W" }
        "Q" {
            Write-Host "Stopping services..." -F Yellow
            foreach ($key in $services.Keys) { Stop-VerityService $key }
            Write-Host "Bye." -F Green
            break main
        }
        default { Start-Sleep -Milliseconds 400 }
    }
    if ($choice -in @("S", "A", "R", "F", "I", "W")) { Start-Sleep 1 }
}
