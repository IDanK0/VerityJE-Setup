<# WhisperLauncher - starts WhisperServer (STT) on :9000
   Uses the model chosen by setup (config.psd1) and adds ffmpeg to PATH.
   -ServerOnly: just start the server (used by Manager). #>
[CmdletBinding()]
param([switch]$ServerOnly)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

. (Join-Path $scriptDir "VerityUI.ps1")

Start-VyTranscript "whisper-launcher.log"

$cfg = Read-VyConfig $scriptDir

$venvPy   = Join-Path $scriptDir "WhisperServer\.venv\Scripts\python.exe"
$serverPy = Join-Path $scriptDir "WhisperServer\server.py"
$model    = Get-VyCfg $cfg "WhisperModel" "base"
$logDir   = Join-Path $scriptDir "logs"

Write-VyBanner "WhisperServer - STT" "model: $model on :9000"

# ------------------------------------------------------------- preflight ----
if (-not (Test-Path $venvPy))   { Write-VyErr "Whisper venv not found. Run Setup.bat first."; Stop-VyTranscript; Read-Host "Press Enter"; exit 1 }
if (-not (Test-Path $serverPy)) { Write-VyErr "server.py not found."; Stop-VyTranscript; Read-Host "Press Enter"; exit 1 }

if (Test-VyPort 9000) {
    Write-VyWarn "port 9000 already in use - the server is probably already running"
    Write-VyInfo "API: http://127.0.0.1:9000/v1/"
    Stop-VyTranscript
    if ($ServerOnly) { exit 0 }
    Read-Host "Press Enter"; exit 0
}

# ----------------------------------------------------------- environment ----
$env:WHISPER_MODEL = $model
$env:PYTHONUTF8 = "1"

$ff = Get-VyCfg $cfg "FfmpegBin"
if ($ff -and (Test-Path (Join-Path $ff "ffmpeg.exe"))) {
    if ($env:Path -notlike "*$ff*") { $env:Path = "$ff;$env:Path" }
} elseif (-not (Get-Command ffmpeg -EA SilentlyContinue)) {
    Write-VyWarn "ffmpeg not found - transcription will fail. Re-run Setup.bat."
}

# --------------------------------------------------------------- launch -----
$outLog = Join-Path $logDir "whisper-server.out.log"
$errLog = Join-Path $logDir "whisper-server.err.log"
Remove-Item $outLog, $errLog -Force -EA SilentlyContinue

Write-VyInfo "starting server..."
$proc = Start-Process -FilePath $venvPy -ArgumentList "`"$serverPy`"" `
    -WorkingDirectory $scriptDir -WindowStyle Hidden `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru

$ready = Wait-VyFor "Whisper readiness (model loading can take a minute)" {
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:9000/v1/models" -TimeoutSec 2 -UseBasicParsing -EA SilentlyContinue
        return ($r.StatusCode -eq 200)
    } catch { return $false }
} 300 $proc

if (-not $ready) {
    Write-VyErr "server did not start. Last log lines:"
    Get-VyLogTail $errLog 12
    Get-VyLogTail $outLog 6
    Stop-VyTranscript; Read-Host "Press Enter"; exit 1
}

Write-VyOk "SERVER READY"
Write-VyInfo "API:    http://127.0.0.1:9000/v1/"
Write-VyInfo "Health: http://127.0.0.1:9000/health"
Write-VyInfo 'curl -X POST http://127.0.0.1:9000/v1/audio/transcriptions -F "file=@audio.mp3" -F "model=whisper-1"'
Stop-VyTranscript
if (-not $ServerOnly) { Read-Host "Press Enter" }
