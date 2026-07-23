<# WhisperLauncher - starts WhisperServer (STT) on :9000
   Uses the model chosen by setup (config.psd1) and adds ffmpeg to PATH. #>
[CmdletBinding()]
param([switch]$ServerOnly)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

# ------------------------------------------------------------ config load ---
$cfg = @{}
$cfgPath = Join-Path $scriptDir "config.psd1"
if (Test-Path $cfgPath) { try { $cfg = Import-PowerShellDataFile $cfgPath } catch { } }
function Cfg($name, $default = "") {
    if ($cfg -and $cfg.Contains($name) -and $null -ne $cfg[$name] -and "$($cfg[$name])" -ne "") { return $cfg[$name] }
    return $default
}

$venvPy   = Join-Path $scriptDir "WhisperServer\.venv\Scripts\python.exe"
$serverPy = Join-Path $scriptDir "WhisperServer\server.py"
$model    = Cfg "WhisperModel" "base"
$logDir   = Join-Path $scriptDir "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  WhisperServer - STT ($model)  :9000" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

# ------------------------------------------------------------- preflight ----
if (-not (Test-Path $venvPy))   { Write-Host "ERROR: Whisper venv not found. Run Setup.bat first." -F Red; Read-Host "Press Enter"; exit 1 }
if (-not (Test-Path $serverPy)) { Write-Host "ERROR: server.py not found." -F Red; Read-Host "Press Enter"; exit 1 }

$busy = Get-NetTCPConnection -LocalPort 9000 -State Listen -EA SilentlyContinue
if ($busy) {
    Write-Host "Port 9000 is already in use - the server is probably already running." -F Yellow
    Write-Host "API: http://127.0.0.1:9000/v1/" -F Yellow
    Read-Host "Press Enter"; exit 0
}

# ----------------------------------------------------------- environment ----
$env:WHISPER_MODEL = $model
$env:PYTHONUTF8 = "1"

$ff = Cfg "FfmpegBin"
if ($ff -and (Test-Path (Join-Path $ff "ffmpeg.exe"))) {
    if ($env:Path -notlike "*$ff*") { $env:Path = "$ff;$env:Path" }
} elseif (-not (Get-Command ffmpeg -EA SilentlyContinue)) {
    Write-Host "WARNING: ffmpeg not found - transcription will fail. Re-run Setup.bat." -F Yellow
}

# --------------------------------------------------------------- launch -----
$outLog = Join-Path $logDir "whisper-server.out.log"
$errLog = Join-Path $logDir "whisper-server.err.log"
Remove-Item $outLog, $errLog -Force -EA SilentlyContinue

Write-Host "Starting server..." -F Yellow
$proc = Start-Process -FilePath $venvPy -ArgumentList "`"$serverPy`"" `
    -WorkingDirectory $scriptDir -WindowStyle Hidden `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru

Write-Host "Waiting for readiness (model loading can take a minute)..." -F Yellow
$ready = $false
for ($i = 0; $i -lt 150 -and -not $ready; $i++) {
    Start-Sleep -Seconds 2
    if ($proc.HasExited) { break }
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:9000/v1/models" -TimeoutSec 2 -UseBasicParsing -EA SilentlyContinue
        if ($r.StatusCode -eq 200) { $ready = $true }
    } catch { }
}

if (-not $ready) {
    Write-Host "ERROR: server did not start. Last log lines:" -F Red
    foreach ($f in @($errLog, $outLog)) {
        if (Test-Path $f) { Get-Content $f -Tail 12 | ForEach-Object { Write-Host "  $_" -F DarkGray } }
    }
    Read-Host "Press Enter"; exit 1
}

Write-Host "SERVER READY!" -F Green
Write-Host "API:    http://127.0.0.1:9000/v1/" -F Yellow
Write-Host "Health: http://127.0.0.1:9000/health" -F DarkGray
Write-Host 'Example: curl -X POST http://127.0.0.1:9000/v1/audio/transcriptions -F "file=@audio.mp3" -F "model=whisper-1"' -F DarkGray
Write-Host "Logs: $logDir" -F DarkGray
if (-not $ServerOnly) { Read-Host "Press Enter" }
