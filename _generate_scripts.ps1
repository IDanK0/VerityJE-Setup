param($VerityTMPath, $WhisperModel = "large-v3-turbo", $EspeakDll = "", $UvBin = "")
if (-not $VerityTMPath) { $VerityTMPath = Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Bat($folder, $name, $ps1File) {
    $path = Join-Path $folder $name
    $content = "@echo off`r`npowershell -ExecutionPolicy Bypass -File `"%~dp0$ps1File`"`r`npause`r`n"
    [System.IO.File]::WriteAllText($path, $content, [Text.Encoding]::ASCII)
}

Write-Bat $VerityTMPath "LiteLLM.bat"       "LiteLLM.ps1"
Write-Bat $VerityTMPath "FastKoko.bat"       "FastKoko.ps1"
Write-Bat $VerityTMPath "WhisperServer.bat"  "WhisperLauncher.ps1"
Write-Bat $VerityTMPath "Manager.bat"        "Manager.ps1"

# ============================================================
# LiteLLM.ps1
# ============================================================
Set-Content (Join-Path $VerityTMPath "LiteLLM.ps1") -Encoding UTF8 -Value @'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$uvBin = "__UVBIN__"
if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  LiteLLM - AI Gateway" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

$models = @(
    "gpt-4o (OpenAI)",
    "gpt-4o-mini (OpenAI)",
    "gpt-3.5-turbo (OpenAI)",
    "claude-sonnet-4-20250514",
    "gemini-2.5-flash (Google)",
    "llama-3.3-70b-instruct (Meta)",
    "groq/llama-3.3-70b (Groq)"
)
Write-Host "Available models:" -F White
for ($i = 0; $i -lt $models.Count; $i++) {
    Write-Host ("  {0,2}. {1}" -f ($i + 1), $models[$i]) -F White
}
Write-Host "      0. Custom" -F DarkGray
Write-Host ""
$c = Read-Host "Choose (number or name)"
if ($c -match '^\d+$') {
    $id = [int]$c - 1
    if ($id -ge 0 -and $id -lt $models.Count) { $m = ($models[$id] -split '\(')[0].Trim() }
    else { $m = "gpt-4o" }
} else {
    $m = $c.Trim()
    if (-not $m) { $m = "gpt-4o" }
}
Write-Host "Model: $m" -F Green

$knownKeys = @("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GROQ_API_KEY", "HUGGINGFACE_API_KEY")
$found = $false
foreach ($e in $knownKeys) {
    if (Test-Path "env:$e" -and (Get-Item "env:$e").Value) { $found = $true; break }
}
if (-not $found) {
    Write-Host ""
    Write-Host "No API key found." -F Yellow
    Write-Host "Enter your API key:" -F Yellow
    $k = Read-Host
    if ($k.Trim()) {
        Set-Item -Path "env:OPENAI_API_KEY" -Value $k.Trim()
        Write-Host "Set OPENAI_API_KEY" -F Green
    }
}

Write-Host ""
Write-Host "Port (default 4000):" -F Yellow
$p = Read-Host
if (-not ($p -match '^\d+$')) { $p = "4000" }
Write-Host ""
Write-Host "Starting on http://127.0.0.1:$p/v1/" -F Green
Write-Host "Docs: http://127.0.0.1:$p/docs" -F Yellow
Write-Host "Press Ctrl+C to stop" -F DarkGray
Write-Host ""
$env:LITELLM_LOG = "INFO"
litellm --model $m --port $p
'@ -replace '__UVBIN__', $UvBin

# ============================================================
# FastKoko.ps1
# ============================================================
$espeakSetup = if ($EspeakDll) { "`$env:PHONEMIZER_ESPEAK_LIBRARY=`'$EspeakDll`';" } else { "" }
Set-Content (Join-Path $VerityTMPath "FastKoko.ps1") -Encoding UTF8 -Value @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$repoPath = Join-Path `$scriptDir "Kokoro-FastAPI"
`$vu = Join-Path `$repoPath ".venv\Scripts\uvicorn.exe"

if (!(Test-Path `$vu)) {
    Write-Host "ERROR: Kokoro-FastAPI not found. Run setup.ps1 first." -F Red
    Read-Host; exit 1
}

`$env:PYTHONUTF8 = "1"
$($espeakSetup)

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  FastKoko - Kokoro TTS  :8880" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

Write-Host "Starting server..." -F Yellow
Start-Process powershell -NoExit -Arg "-NoExit", "-Command", "& '`$vu' api.src.main:app --host 127.0.0.1 --port 8880" -WindowStyle Minimized

Write-Host "Waiting for server..." -F Yellow
`$ready = `$false
for (`$i = 1; `$i -le 50; `$i++) {
    Start-Sleep -Milliseconds 600
    try {
        `$r = Invoke-WebRequest "http://127.0.0.1:8880/docs" -TimeoutSec 2 -EA SilentlyContinue
        if (`$r.StatusCode -eq 200) { `$ready = `$true; break }
    } catch {}
}
if (!`$ready) { Write-Host "ERROR: Server not started." -F Red; Read-Host; exit 1 }

Write-Host "SERVER READY!" -F Green
Write-Host "API: http://127.0.0.1:8880/v1/" -F Yellow
Write-Host "Web: http://127.0.0.1:8880/web/" -F DarkGray

try {
    `$voicesData = Invoke-RestMethod "http://127.0.0.1:8880/v1/audio/voices"
    `$allVoices = `$voicesData.voices
} catch {
    Write-Host "Error loading voices." -F Red; Read-Host; exit 1
}

`$italian = @(); `$english = @(); `$other = @()
foreach (`$v in `$allVoices) {
    `$id = `$v.id.ToLower()
    if (`$id -match "^i[fm]_") { `$italian += `$v }
    elseif (`$id -match "^[abef]_[a-z]+") { `$english += `$v }
    else { `$other += `$v }
}

`$opt = 1
Write-Host ""; Write-Host "[ITALIAN]" -F Magenta
foreach (`$v in `$italian) { Write-Host "  `$opt. `$(`$v.id)"; `$opt++ }
Write-Host ""; Write-Host "[ENGLISH]" -F Magenta
foreach (`$v in `$english) { Write-Host "  `$opt. `$(`$v.id)"; `$opt++ }
if (`$other.Count -gt 0) { Write-Host ""; Write-Host "[OTHER]" -F Magenta; foreach (`$v in `$other) { Write-Host "  `$opt. `$(`$v.id)"; `$opt++ } }

`$all = @(`$italian) + @(`$english) + @(`$other)
`$default = `$all[0].id
Write-Host ""; Write-Host "Voice [`$default]:" -F Yellow
`$choice = Read-Host "  >"
if (`$choice) {
    `$idx = [int]`$choice - 1
    if (`$idx -ge 0 -and `$idx -lt `$all.Count) { `$selectedVoice = `$all[`$idx].id } else { `$selectedVoice = `$default }
} else { `$selectedVoice = `$default }
Write-Host "Voice: `$selectedVoice" -F Green

Write-Host ""; Write-Host "Text (Enter twice to submit):" -F Yellow
`$lines = @(); `$first = `$true
while (`$true) {
    if (`$first) { `$line = Read-Host "  >"; `$first = `$false }
    else { `$line = Read-Host "  > (Enter to submit)" }
    if (!`$line.Trim()) { break }
    `$lines += `$line
}
`$text = `$lines -join "`n"
if (!`$text.Trim()) { Write-Host "No text entered." -F Red; Read-Host; exit 0 }

Write-Host ""; Write-Host "Generating..." -F Yellow
try {
    `$body = @{ model = "kokoro"; voice = `$selectedVoice; input = `$text; response_format = "mp3" } | ConvertTo-Json
    `$resp = Invoke-WebRequest "http://127.0.0.1:8880/v1/audio/speech" -Method Post -ContentType "application/json" -Body `$body -TimeoutSec 120
    `$ts = Get-Date -Format "yyyyMMdd_HHmmss"
    `$outFile = Join-Path `$env:USERPROFILE\Desktop "tts_`$selectedVoice`_`$ts.mp3"
    [System.IO.File]::WriteAllBytes(`$outFile, `$resp.Content)
    Write-Host "Saved: `$outFile" -F Green
} catch { Write-Host "ERROR: `$_" -F Red }
Read-Host "`nPress Enter"
"@

# ============================================================
# WhisperLauncher.ps1
# ============================================================
Set-Content (Join-Path $VerityTMPath "WhisperLauncher.ps1") -Encoding UTF8 -Value @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$venvPython = Join-Path `$scriptDir "WhisperServer\.venv\Scripts\python.exe"
`$serverPy = Join-Path `$scriptDir "WhisperServer\server.py"

if (!(Test-Path `$venvPython)) {
    Write-Host "ERROR: WhisperServer not found. Run setup.ps1 first." -F Red; Read-Host; exit 1
}
if (!(Test-Path `$serverPy)) {
    Write-Host "ERROR: server.py not found." -F Red; Read-Host; exit 1
}

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  WhisperServer - STT ($WhisperModel)  :9000" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

Write-Host "Starting server..." -F Yellow
`$cmd = "& `$venvPython `$serverPy"
Start-Process powershell -NoExit -WindowStyle Minimized -Arg "-NoExit", "-Command", `$cmd

Write-Host "Waiting for server (model loading may take a minute)..." -F Yellow
`$ready = `$false
for (`$i = 1; `$i -le 120; `$i++) {
    Start-Sleep -Milliseconds 500
    try {
        `$r = Invoke-WebRequest "http://127.0.0.1:9000/v1/models" -TimeoutSec 2 -EA SilentlyContinue
        if (`$r.StatusCode -eq 200) { `$ready = `$true; break }
    } catch {}
}
if (!`$ready) {
    Write-Host "ERROR: Server did not start." -F Red; Read-Host; exit 1
}

Write-Host "SERVER READY!" -F Green
Write-Host "API: http://127.0.0.1:9000/v1/" -F Yellow
Write-Host "Example:" -F DarkGray
Write-Host '  curl -X POST http://127.0.0.1:9000/v1/audio/speech -F "file=@audio.mp3"' -F DarkGray
Read-Host "`nPress Enter"
"@

# ============================================================
# Manager.ps1
# ============================================================
Set-Content (Join-Path $VerityTMPath "Manager.ps1") -Encoding UTF8 -Value @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$uvBin = "$UvBin"
if ((Test-Path `$uvBin) -and (`$env:Path -notlike "*`$uvBin*")) { `$env:Path += ";`$uvBin" }

`$services = @{
    FastKoko = @{ name = "FastKoko (TTS)"; port = 8880; url = "http://127.0.0.1:8880/v1/"; running = `$false }
    LiteLLM  = @{ name = "LiteLLM (AI)";  port = 4000; url = "http://127.0.0.1:4000/v1/"; running = `$false }
    Whisper  = @{ name = "Whisper (STT)"; port = 9000; url = "http://127.0.0.1:9000/v1/"; running = `$false }
}

function Test-Port(`$port) {
    try {
        `$tcp = New-Object Net.Sockets.TcpClient
        `$tcp.ConnectAsync("127.0.0.1", `$port).Wait(300)
        `$connected = `$tcp.Client.Connected
        `$tcp.Close()
        return `$connected
    } catch { return `$false }
}

function Show-Menu {
    Write-Host ""
    Write-Host "================================================" -F Yellow
    Write-Host "  Verity JE - Manager" -F Yellow
    Write-Host "================================================" -F Yellow
    Write-Host "  [S] Start all    [A] Stop all    [R] Restart all" -F White
    Write-Host ""
    Write-Host "  -- Services --" -F Yellow
    foreach (`$kv in `$services.GetEnumerator()) {
        `$key = `$kv.Key
        `$svc = `$kv.Value
        `$status = if (`$svc.running) { "ON " } else { "OFF" }
        `$color = if (`$svc.running) { "Green" } else { "Red" }
        Write-Host ("  [{0}] {1,-22} {2}  {3}" -f `$key.Substring(0, 1), `$svc.name, `$status, `$svc.url) -F `$color
    }
    Write-Host ""
    Write-Host "  [Q] Quit" -F Yellow
    Write-Host ""
}

function Start-Service(`$name, `$batFile) {
    `$svc = `$services[`$name]
    if (`$svc.running) { Write-Host "  already running" -F Yellow; return }
    `$fullPath = Join-Path `$scriptDir `$batFile
    if (!(Test-Path `$fullPath)) { Write-Host "  script not found: `$batFile" -F Red; return }
    Write-Host "  starting..." -F Yellow
    Start-Process powershell -NoExit -Arg "-EP", "Bypass", "-File", `$fullPath -WindowStyle Minimized
    Start-Sleep 2
    if (Test-Port `$svc.port) { `$svc.running = `$true; Write-Host "  started" -F Green }
    else { Write-Host "  starting (wait)..." -F Yellow }
}

function Stop-Service(`$name) {
    `$svc = `$services[`$name]
    if (!`$svc.running) { return }
    Get-NetTCPConnection -LocalPort `$svc.port -EA SilentlyContinue | ForEach-Object {
        Stop-Process -Id `$_.OwningProcess -Force -EA SilentlyContinue
    }
    `$svc.running = `$false
    Write-Host "  stopped" -F Red
}

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  Verity JE - Manager" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

foreach (`$k in `$services.Keys) {
    if (Test-Port `$services[`$k].port) {
        `$services[`$k].running = `$true
        Write-Host "  detected: `$(`$services[`$k].name)" -F Green
    }
}

while (`$true) {
    Show-Menu
    `$choice = (Read-Host "Choice").ToUpper()
    switch (`$choice) {
        "S" {
            Start-Service "FastKoko" "FastKoko.bat"
            Start-Service "LiteLLM"  "LiteLLM.bat"
            Start-Service "Whisper"  "WhisperServer.bat"
        }
        "A" {
            Stop-Service "FastKoko"
            Stop-Service "LiteLLM"
            Stop-Service "Whisper"
        }
        "R" {
            Stop-Service "FastKoko"; Stop-Service "LiteLLM"; Stop-Service "Whisper"
            Start-Sleep 2
            Start-Service "FastKoko" "FastKoko.bat"
            Start-Service "LiteLLM"  "LiteLLM.bat"
            Start-Service "Whisper"  "WhisperServer.bat"
        }
        "F" { Start-Service "FastKoko" "FastKoko.bat" }
        "I" { Start-Service "LiteLLM"  "LiteLLM.bat" }
        "W" { Start-Service "Whisper"  "WhisperServer.bat" }
        "Q" {
            Write-Host "`nShutting down..." -F Yellow
            Stop-Service "FastKoko"; Stop-Service "LiteLLM"; Stop-Service "Whisper"
            Write-Host "Done." -F Green
            break
        }
        default { Write-Host "  Invalid choice." -F Red }
    }
}
"@

Write-Host "All scripts generated."
