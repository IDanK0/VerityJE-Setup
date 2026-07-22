$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoPath = Join-Path $scriptDir "Kokoro-FastAPI"
$venvUvicorn = Join-Path $repoPath ".venv\Scripts\uvicorn.exe"

if (-not (Test-Path $venvUvicorn)) {
    Write-Host "ERROR: Kokoro-FastAPI not found at $repoPath" -ForegroundColor Red
    Write-Host "Run setup.ps1 first or make sure Kokoro-FastAPI is in the same directory." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

$env:PYTHONUTF8 = "1"
$espeakDll = "C:\Program Files\eSpeak NG\libespeak-ng.dll"
if (Test-Path $espeakDll) { $env:PHONEMIZER_ESPEAK_LIBRARY = $espeakDll }

$env:MODEL_DIR = Join-Path $repoPath "api\src\models"
$env:VOICES_DIR = Join-Path $repoPath "api\src\voices\v1_0"
$env:PYTHONPATH = "$repoPath;$repoPath\api"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  FastKoko - Kokoro TTS" -ForegroundColor Cyan
Write-Host "  Port: 8880" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Starting server in background..." -ForegroundColor Yellow

$serverArgs = @(
    "-NoExit",
    "-Command",
    "`$env:PYTHONUTF8='1';" +
    $(if (Test-Path $espeakDll) { "`$env:PHONEMIZER_ESPEAK_LIBRARY='$espeakDll';" } else { "" }) +
    "`$env:MODEL_DIR='$env:MODEL_DIR';" +
    "`$env:VOICES_DIR='$env:VOICES_DIR';" +
    "`$env:PYTHONPATH='$env:PYTHONPATH';" +
    "& '$venvUvicorn' api.src.main:app --host 127.0.0.1 --port 8880"
)

Start-Process powershell -ArgumentList $serverArgs -WindowStyle Minimized

Write-Host "Waiting for server to be ready..." -ForegroundColor Yellow
$ready = $false
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Milliseconds 500
    try {
        $r = Invoke-WebRequest -Uri "http://127.0.0.1:8880/docs" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch {}
}

if (-not $ready) {
    Write-Host "ERROR: Server did not start within 30 seconds." -ForegroundColor Red
    Write-Host "Check the minimized server window for errors." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "SERVER READY!" -ForegroundColor Green
Write-Host "API: http://127.0.0.1:8880/v1/" -ForegroundColor Yellow
Write-Host "Web UI: http://127.0.0.1:8880/web/" -ForegroundColor Yellow
Write-Host ""

# Load available voices
Write-Host "Loading available voices..." -ForegroundColor Cyan
try {
    $voicesData = Invoke-RestMethod -Uri "http://127.0.0.1:8880/v1/audio/voices" -Method Get
    $allVoices = $voicesData.voices
} catch {
    Write-Host "Could not load voices. Server might not be fully ready." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Categorize voices
$italian = @(); $english = @(); $other = @()
foreach ($v in $allVoices) {
    $id = $v.id.ToLower()
    if ($id -match "^i[fm]_") { $italian += $v }
    elseif ($id -match "^[abef]_[a-z]+") { $english += $v }
    else { $other += $v }
}

$opt = 1
Write-Host ""
Write-Host "[ITALIAN]" -ForegroundColor Magenta
foreach ($v in $italian) { Write-Host "  $opt. $($v.id)" -ForegroundColor White; $opt++ }
Write-Host ""
Write-Host "[ENGLISH]" -ForegroundColor Magenta
foreach ($v in $english) { Write-Host "  $opt. $($v.id)" -ForegroundColor White; $opt++ }
if ($other.Count -gt 0) {
    Write-Host ""
    Write-Host "[OTHER]" -ForegroundColor Magenta
    foreach ($v in $other) { Write-Host "  $opt. $($v.id)" -ForegroundColor White; $opt++ }
}

$allList = @($italian) + @($english) + @($other)
$defaultVoice = $allList[0].id

Write-Host ""
Write-Host "Default voice: $defaultVoice (press Enter to confirm)" -ForegroundColor Yellow
$choice = Read-Host "Voice number"

if ($choice -and [int]::TryParse($choice, [ref]$null)) {
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $allList.Count) { $selectedVoice = $allList[$idx].id }
    else { $selectedVoice = $defaultVoice }
} else { $selectedVoice = $defaultVoice }

Write-Host "Selected voice: $selectedVoice" -ForegroundColor Green
Write-Host ""
Write-Host "[TEXT INPUT - press Enter on empty line to submit]" -ForegroundColor Cyan
Write-Host "Enter your text (multiple lines OK):" -ForegroundColor Yellow

$textLines = @()
$firstLine = $true
while ($true) {
    if ($firstLine) {
        $line = Read-Host "  Text"
        $firstLine = $false
    } else {
        $line = Read-Host "  (Enter to submit)"
    }
    if (-not $line.Trim()) { break }
    $textLines += $line
}
$text = $textLines -join "`n"

if (-not $text.Trim()) {
    Write-Host "No text entered." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 0
}

Write-Host ""
Write-Host "Generating audio..." -ForegroundColor Yellow
try {
    $body = @{
        model = "kokoro"
        voice = $selectedVoice
        input = $text
        response_format = "mp3"
    } | ConvertTo-Json

    $resp = Invoke-WebRequest -Uri "http://127.0.0.1:8880/v1/audio/speech" `
        -Method Post `
        -ContentType "application/json" `
        -Body $body `
        -TimeoutSec 120

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE\Desktop "tts_${selectedVoice}_${timestamp}.mp3"
    [System.IO.File]::WriteAllBytes($outputPath, $resp.Content)

    Write-Host ""
    Write-Host "Audio saved to: $outputPath" -ForegroundColor Green
} catch {
    Write-Host "ERROR during generation: $_" -ForegroundColor Red
}

Read-Host "`nPress Enter to close"
