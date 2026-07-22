<#
.SYNOPSIS
    VerityTM - Generate all launcher scripts
.PARAMETER VerityTMPath
    Root path of VerityTM installation
.PARAMETER WhisperModel
    Whisper model to embed in the launcher
#>
param(
    [string]$VerityTMPath,
    [string]$WhisperModel = "large-v3-turbo"
)

if (-not $VerityTMPath) {
    $VerityTMPath = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# ============================================================
# LiteLLM.bat
# ============================================================
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0LiteLLM.ps1"
pause
"@ | Set-Content (Join-Path $VerityTMPath "LiteLLM.bat") -Encoding UTF8

# ============================================================
# LiteLLM.ps1
# ============================================================
Set-Content (Join-Path $VerityTMPath "LiteLLM.ps1") -Encoding UTF8 -Value @'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Find litellm in PATH (uv tool install puts it in ~/.local/bin)
$uvBin = "$env:USERPROFILE\.local\bin"
if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LiteLLM - AI Gateway" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$modelOptions = @(
    "gpt-4o                      (OpenAI GPT-4o)"
    "gpt-4o-mini                 (OpenAI GPT-4o Mini)"
    "gpt-3.5-turbo               (OpenAI GPT-3.5 Turbo)"
    "claude-sonnet-4-20250514    (Anthropic Claude Sonnet)"
    "claude-3-opus-20240229      (Anthropic Claude Opus)"
    "gemini-2.5-flash            (Google Gemini Flash)"
    "gemini-2.5-pro              (Google Gemini Pro)"
    "groq/llama-3.3-70b          (Groq Llama 70b)"
    "huggingface/mistralai/Mistral-7B-Instruct (HuggingFace Mistral)"
)

Write-Host "Available models:" -ForegroundColor Cyan
for ($i = 0; $i -lt $modelOptions.Count; $i++) {
    $prefix = ("  {0,2}. " -f ($i+1))
    $description = $modelOptions[$i].Substring(28)
    $modelName = $modelOptions[$i].Substring(0, 28).Trim()
    Write-Host "$prefix$description" -ForegroundColor White
    Write-Host ("       " + $modelName) -ForegroundColor DarkGray
}
Write-Host "      0. Custom model" -ForegroundColor Yellow

Write-Host ""
Write-Host "Choose model (number or name):" -ForegroundColor Yellow
$choice = Read-Host

if ($choice -match '^\d+$') {
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $modelOptions.Count) {
        $model = $modelOptions[$idx].Substring(0, 28).Trim()
    } else { $model = "gpt-4o" }
} elseif ($choice.Trim()) {
    $model = $choice.Trim()
} else {
    $model = "gpt-4o"
}

Write-Host ""
Write-Host "Model: $model" -ForegroundColor Green

# Detect API keys from environment
$knownKeys = @("OPENAI_API_KEY","ANTHROPIC_API_KEY","GEMINI_API_KEY","GROQ_API_KEY","HUGGINGFACE_API_KEY","COHERE_API_KEY","TOGETHERAI_API_KEY","REPLICATE_API_KEY","MISTRAL_API_KEY","PERPLEXITY_API_KEY","DEEPSEEK_API_KEY","XAI_API_KEY")
$foundKey = $false
foreach ($k in $knownKeys) {
    if (Test-Path "env:$k" -and (Get-Item "env:$k").Value) { $foundKey = $true; break }
}

if (-not $foundKey) {
    Write-Host ""
    Write-Host "No API key detected in environment." -ForegroundColor Yellow
    Write-Host "Enter your API key (or press Enter to skip):" -ForegroundColor Yellow
    $key = Read-Host
    if ($key.Trim()) {
        $keyVarName = ($model.ToUpper() -replace '[^A-Z0-9_]','_').Replace('OPENAI','OPENAI').Replace('_','_API_')
        if ($model -match "gpt|openai") { Set-Item -Path "env:OPENAI_API_KEY" -Value $key.Trim(); Write-Host "Set OPENAI_API_KEY" -ForegroundColor Green }
        elseif ($model -match "claude|anthropic") { Set-Item -Path "env:ANTHROPIC_API_KEY" -Value $key.Trim(); Write-Host "Set ANTHROPIC_API_KEY" -ForegroundColor Green }
        elseif ($model -match "gemini") { Set-Item -Path "env:GEMINI_API_KEY" -Value $key.Trim(); Write-Host "Set GEMINI_API_KEY" -ForegroundColor Green }
        elseif ($model -match "groq") { Set-Item -Path "env:GROQ_API_KEY" -Value $key.Trim(); Write-Host "Set GROQ_API_KEY" -ForegroundColor Green }
        elseif ($model -match "huggingface") { Set-Item -Path "env:HUGGINGFACE_API_KEY" -Value $key.Trim(); Write-Host "Set HUGGINGFACE_API_KEY" -ForegroundColor Green }
        else { Set-Item -Path "env:API_KEY" -Value $key.Trim(); Write-Host "Set API_KEY" -ForegroundColor Green }
    }
}

Write-Host ""
Write-Host "Port (default 4000):" -ForegroundColor Yellow
$port = Read-Host
if (-not ($port -match '^\d+$')) { $port = "4000" }

Write-Host ""
Write-Host "Starting LiteLLM on http://127.0.0.1:$port/v1/" -ForegroundColor Green
Write-Host "Docs: http://127.0.0.1:$port/docs" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Ctrl+C to stop" -ForegroundColor DarkGray
Write-Host ""

$env:LITELLM_LOG = "INFO"
litellm --model $model --port $port
'@

# ============================================================
# FastKoko.bat
# ============================================================
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0FastKoko.ps1"
pause
"@ | Set-Content (Join-Path $VerityTMPath "FastKoko.bat") -Encoding UTF8

# ============================================================
# FastKoko.ps1
# ============================================================
Set-Content (Join-Path $VerityTMPath "FastKoko.ps1") -Encoding UTF8 -Value @'
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
'@

# ============================================================
# WhisperServer.bat
# ============================================================
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0WhisperLauncher.ps1"
pause
"@ | Set-Content (Join-Path $VerityTMPath "WhisperServer.bat") -Encoding UTF8

# ============================================================
# WhisperLauncher.ps1
# ============================================================
$wlContent = @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$venvPython = Join-Path `$scriptDir "WhisperServer\.venv\Scripts\python.exe"
`$serverPy = Join-Path `$scriptDir "WhisperServer\server.py"

if (-not (Test-Path `$venvPython)) {
    Write-Host "ERROR: WhisperServer virtual environment not found." -ForegroundColor Red
    Write-Host "Run setup.ps1 first or make sure WhisperServer is properly installed." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path `$serverPy)) {
    Write-Host "ERROR: WhisperServer server.py not found." -ForegroundColor Red
    Write-Host "Run setup.ps1 first." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Whisper Server - Speech to Text" -ForegroundColor Cyan
Write-Host "  Model: $WhisperModel" -ForegroundColor Cyan
Write-Host "  Port: 9000" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Starting Whisper server..." -ForegroundColor Yellow
Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '``$venvPython' '``$serverPy'" -WindowStyle Minimized

Write-Host "Waiting for server to be ready (model loading may take a minute)..." -ForegroundColor Yellow
`$ready = `$false
for (`$i = 1; `$i -le 120; `$i++) {
    Start-Sleep -Milliseconds 500
    try {
        `$r = Invoke-WebRequest -Uri "http://127.0.0.1:9000/v1/models" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if (`$r.StatusCode -eq 200) { `$ready = `$true; break }
    } catch {}
}

if (-not `$ready) {
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
"@
Set-Content (Join-Path $VerityTMPath "WhisperLauncher.ps1") -Value $wlContent -Encoding UTF8

# ============================================================
# Manager.bat
# ============================================================
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0Manager.ps1"
"@ | Set-Content (Join-Path $VerityTMPath "Manager.bat") -Encoding UTF8

# ============================================================
# Manager.ps1
# ============================================================
Set-Content (Join-Path $VerityTMPath "Manager.ps1") -Encoding UTF8 -Value @'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Add uv tool path
$uvBin = "$env:USERPROFILE\.local\bin"
if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

# Service registry
$services = @{
    "FastKoko" = @{
        name = "FastKoko (TTS)"
        port = 8880
        url = "http://127.0.0.1:8880/v1/"
        batFile = "FastKoko.bat"
        running = $false
        pid = $null
    }
    "LiteLLM" = @{
        name = "LiteLLM (AI)"
        port = 4000
        url = "http://127.0.0.1:4000/v1/"
        batFile = "LiteLLM.bat"
        running = $false
        pid = $null
    }
    "Whisper" = @{
        name = "Whisper (STT)"
        port = 9000
        url = "http://127.0.0.1:9000/v1/"
        batFile = "WhisperServer.bat"
        running = $false
        pid = $null
    }
}

function Test-PortInUse {
    param([int]$port)
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        $tcp.ConnectAsync("127.0.0.1", $port).Wait(500)
        $result = $tcp.Client.Connected
        $tcp.Close()
        return $result
    } catch { return $false }
}

function Show-Menu {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  VerityTM Manager" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [S]  Start all services" -ForegroundColor White
    Write-Host "  [A]  Stop all services" -ForegroundColor White
    Write-Host "  [R]  Restart all services" -ForegroundColor White
    Write-Host ""
    Write-Host "--- Individual Services ---" -ForegroundColor Yellow

    $services.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $key = $_.Key
        $svc = $_.Value
        $status = if ($svc.running) { "RUNNING" } else { "STOPPED" }
        $color = if ($svc.running) { "Green" } else { "Red" }
        $shortcut = $key.Substring(0, 1).ToUpper()

        Write-Host "  [$shortcut] $($svc.name,-22) $status" -ForegroundColor $color
        Write-Host "       $($svc.url)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "--- Tools ---" -ForegroundColor Yellow
    Write-Host "  [L]  Change LiteLLM model" -ForegroundColor White
    Write-Host "  [K]  List Kokoro voices" -ForegroundColor White
    Write-Host ""
    Write-Host "  [Q]  Quit (stops all services)" -ForegroundColor Yellow
    Write-Host ""
}

function Start-Service {
    param([string]$name)

    $svc = $services[$name]
    if (-not $svc) { return }

    if ($svc.running) {
        Write-Host "  [$name] Already running" -ForegroundColor Yellow
        return
    }

    $batPath = Join-Path $scriptDir $svc.batFile
    if (-not (Test-Path $batPath)) {
        Write-Host "  [$name] Script not found: $batPath" -ForegroundColor Red
        return
    }

    Write-Host "  [$name] Starting..." -ForegroundColor Yellow

    $proc = Start-Process -FilePath "powershell" `
        -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", $batPath `
        -WindowStyle Minimized `
        -PassThru

    if ($proc) {
        # Wait for port to become available
        for ($i = 1; $i -le 10; $i++) {
            Start-Sleep -Milliseconds 1000
            if (Test-PortInUse $svc.port) {
                $svc.running = $true
                $svc.pid = $proc.Id
                Write-Host "  [$name] Started successfully (PID: $($proc.Id))" -ForegroundColor Green
                return
            }
        }
        Write-Host "  [$name] Process started but port not responding yet (check the window)" -ForegroundColor Yellow
        $svc.running = $true
        $svc.pid = $proc.Id
    } else {
        Write-Host "  [$name] Failed to start" -ForegroundColor Red
    }
}

function Stop-Service {
    param([string]$name)

    $svc = $services[$name]
    if (-not $svc) { return }

    if (-not $svc.running) {
        Write-Host "  [$name] Already stopped" -ForegroundColor DarkGray
        return
    }

    Write-Host "  [$name] Stopping..." -ForegroundColor Yellow

    if ($svc.pid) {
        try {
            Stop-Process -Id $svc.pid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        } catch { }
    }

    # Kill any process on the service port
    $portPid = (Get-NetTCPConnection -LocalPort $svc.port -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    if ($portPid) {
        try { Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue } catch { }
    }

    $svc.running = $false
    $svc.pid = $null
    Write-Host "  [$name] Stopped" -ForegroundColor Red
}

function Change-Model {
    if (-not $services["LiteLLM"].running) {
        Write-Host "LiteLLM is not running. Start it first." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "Model list (same as LiteLLM launcher):" -ForegroundColor Cyan
    Write-Host "  1. gpt-4o         5. claude-3-opus       9. huggingface/mistral"
    Write-Host "  2. gpt-4o-mini    6. gemini-2.5-flash   10. Custom..."
    Write-Host "  3. gpt-3.5-turbo  7. gemini-2.5-pro"
    Write-Host "  4. claude-sonnet  8. groq/llama-3.3-70b"
    Write-Host ""

    $choice = Read-Host "Choice (number or custom model name)"
    $modelMap = @{
        "1" = "gpt-4o"; "2" = "gpt-4o-mini"; "3" = "gpt-3.5-turbo"
        "4" = "claude-sonnet-4-20250514"; "5" = "claude-3-opus-20240229"
        "6" = "gemini-2.5-flash"; "7" = "gemini-2.5-pro"
        "8" = "groq/llama-3.3-70b"; "9" = "huggingface/mistralai/Mistral-7B-Instruct"
    }

    if ($modelMap.ContainsKey($choice)) { $m = $modelMap[$choice] }
    elseif ($choice -eq "10" -or -not $modelMap.ContainsKey($choice)) { $m = Read-Host "Custom model:" }
    else { $m = $modelMap[$choice] }

    if ($m) {
        Write-Host "Restarting LiteLLM with model: $m" -ForegroundColor Yellow
        Stop-Service "LiteLLM"
        Start-Sleep -Seconds 1
        # We restart via the bat file normally, but with a custom model we use the litellm command directly
        Start-Process powershell -NoExit -WindowStyle Minimized -ArgumentList "-Command", "`$env:LITELLM_LOG='INFO'; litellm --model $m --port 4000"
        Write-Host "LiteLLM restarted with model: $m on http://127.0.0.1:4000/v1/" -ForegroundColor Green
        $services["LiteLLM"].running = $true
    }
}

function List-Voices {
    if (-not $services["FastKoko"].running) {
        Write-Host "FastKoko is not running. Start it first." -ForegroundColor Yellow
        return
    }
    try {
        $voices = Invoke-RestMethod -Uri "http://127.0.0.1:8880/v1/audio/voices" -Method Get
        Write-Host ""
        Write-Host "Available Kokoro voices:" -ForegroundColor Cyan
        $i = 1
        foreach ($v in $voices.voices) {
            $id = $v.id.ToLower()
            if ($id -match "^i[fm]_") { $tag = "[IT]" } elseif ($id -match "^[abef]_[a-z]+") { $tag = "[EN]" } else { $tag = "   " }
            Write-Host "  $tag $($v.id)" -ForegroundColor White
        }
    } catch {
        Write-Host "Could not load voices. Is the server running?" -ForegroundColor Red
    }
}

# ============================================================
# MAIN
# ============================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  VerityTM Manager" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check for already running services
foreach ($key in $services.Keys) {
    if (Test-PortInUse $services[$key].port) {
        $services[$key].running = $true
        Write-Host "  [$($services[$key].name)] Already detected as running" -ForegroundColor Green
    }
}

while ($true) {
    Show-Menu
    $key = (Read-Host "Choice").ToUpper()

    switch ($key) {
        "S" {
            Write-Host "`nStarting all services..." -ForegroundColor Green
            Start-Service "FastKoko"
            Start-Service "LiteLLM"
            Start-Service "Whisper"
        }
        "A" {
            Write-Host "`nStopping all services..." -ForegroundColor Red
            Stop-Service "FastKoko"
            Stop-Service "LiteLLM"
            Stop-Service "Whisper"
        }
        "R" {
            Write-Host "`nRestarting all services..." -ForegroundColor Yellow
            Stop-Service "FastKoko"
            Stop-Service "LiteLLM"
            Stop-Service "Whisper"
            Start-Sleep -Seconds 2
            Start-Service "FastKoko"
            Start-Service "LiteLLM"
            Start-Service "Whisper"
        }
        "F" { Start-Service "FastKoko" }
        "I" { Start-Service "LiteLLM" }
        "W" { Start-Service "Whisper" }
        "L" { Change-Model }
        "K" { List-Voices }
        "Q" {
            Write-Host "`nShutting down all services..." -ForegroundColor Yellow
            Stop-Service "FastKoko"
            Stop-Service "LiteLLM"
            Stop-Service "Whisper"
            Write-Host "Goodbye!" -ForegroundColor Cyan
            break
        }
        default {
            Write-Host "  Invalid choice. Use S/A/R/F/I/W/L/K/Q" -ForegroundColor Red
        }
    }
}
'@

Write-Host "All scripts generated successfully!"
Write-Host "  - setup.ps1"
Write-Host "  - Manager.bat / Manager.ps1"
Write-Host "  - FastKoko.bat / FastKoko.ps1"
Write-Host "  - LiteLLM.bat / LiteLLM.ps1"
Write-Host "  - WhisperServer.bat / WhisperLauncher.ps1"
