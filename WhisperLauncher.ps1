$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvPython = Join-Path $scriptDir "WhisperServer\.venv\Scripts\python.exe"
$serverPy = Join-Path $scriptDir "WhisperServer\server.py"

if (-not (Test-Path $venvPython)) {
    Write-Host "ERROR: WhisperServer virtual environment not found." -ForegroundColor Red
    Write-Host "Run setup.ps1 first or make sure WhisperServer is properly installed." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path $serverPy)) {
    Write-Host "ERROR: WhisperServer server.py not found." -ForegroundColor Red
    Write-Host "Run setup.ps1 first." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Whisper Server - Speech to Text" -ForegroundColor Cyan
Write-Host "  Model: large-v3-turbo" -ForegroundColor Cyan
Write-Host "  Port: 9000" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Starting Whisper server..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '' ''" -WindowStyle Minimized

Write-Host "Waiting for server to be ready (model loading may take a minute)..." -ForegroundColor Yellow
$ready = $false
for ($i = 1; $i -le 120; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:9000/v1/models" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
}

if (-not $ready) {
    Write-Host "ERROR: Server did not start within 60 seconds." -ForegroundColor Red
    Write-Host "Check the minimized server window for errors." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "SERVER READY!" -ForegroundColor Green
Write-Host "API:  http://127.0.0.1:9000/v1/" -ForegroundColor Yellow
Write-Host "Docs: http://127.0.0.1:9000/docs" -ForegroundColor Yellow
Write-Host ""
Write-Host "Example usage:" -ForegroundColor Cyan
Write-Host '  curl -X POST http://127.0.0.1:9000/v1/audio/speech -F "file=@audio.mp3"' -ForegroundColor DarkGray
Write-Host ""
Read-Host "Press Enter to close"
