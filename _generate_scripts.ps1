param($VerityTMPath, $WhisperModel = "large-v3-turbo", $EspeakDll = "", $UvBin = "")
if (-not $VerityTMPath) { $VerityTMPath = Split-Path -Parent $MyInvocation.MyCommand.Path }

# ==== LiteLLM.bat ====
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0LiteLLM.ps1"
pause
"@ | Set-Content (Join-Path $VerityTMPath "LiteLLM.bat") -Enc UTF8

# ==== LiteLLM.ps1 ====
Set-Content (Join-Path $VerityTMPath "LiteLLM.ps1") -Enc UTF8 -Value @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$uvBin = "$UvBin"
if ((Test-Path `$uvBin) -and (`$env:Path -notlike "*`$uvBin*")) { `$env:Path += ";`$uvBin" }

Write-Host "";Write-Host "================================================" -F Yellow
Write-Host "  LiteLLM - AI Gateway" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

`$models = @("gpt-4o (OpenAI)","gpt-4o-mini (OpenAI)","gpt-3.5-turbo (OpenAI)","claude-sonnet-4-20250514","gemini-2.5-flash (Google)","llama-3.3-70b-instruct (Meta)","groq/llama-3.3-70b (Groq)")
Write-Host "Available models:" -F White
for (`$i = 0; `$i -lt `$models.Count; `$i++) { Write-Host ("  {0,2}. {1}" -f (`$i+1), `$models[`$i]) -F White }
Write-Host "      0. Custom" -F DarkGray
Write-Host ""; `$c = Read-Host "Choose (number or name)"
if (`$c -match '^\d+$') { `$id = [int]`$c - 1; if (`$id -ge 0 -and `$id -lt `$models.Count) { `$m = (`$models[`$id] -split '\(')[0].Trim() } else { `$m = "gpt-4o" } } else { `$m = `$c.Trim(); if (!`$m) { `$m = "gpt-4o" } }
Write-Host "Model: `$m" -F Green

`$keys = @("OPENAI_API_KEY","ANTHROPIC_API_KEY","GEMINI_API_KEY","GROQ_KEY","HUGGINGFACE_KEY")
`$fk = `$false; foreach (`$e in `$keys) { if (Test-Path "env:`$e" -and (Get-Item "env:`$e").Value) { `$fk = `$true; break } }
if (!`$fk) { Write-Host "`nNo API key found." -F Yellow; Write-Host "Enter API key:" -F Yellow; `$k = Read-Host; if (`$k.Trim()) { Set-Item -Path "env:OPENAI_API_KEY" -Value `$k.Trim(); Write-Host "Set OPENAI_API_KEY" -F Green } }

Write-Host ""; Write-Host "Port (default 4000):" -F Yellow; `$p = Read-Host; if (!(`$p -match '^\d+$')) { `$p = "4000" }
Write-Host "`nStarting on http://127.0.0.1:`$p/v1/" -F Green
Write-Host "Press Ctrl+C to stop`n" -F DarkGray
`$env:LITELLM_LOG = "INFO"; litellm --model `$m --port `$p
"@

# ==== FastKoko.bat ====
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0FastKoko.ps1"
pause
"@ | Set-Content (Join-Path $VerityTMPath "FastKoko.bat") -Enc UTF8

# ==== FastKoko.ps1 ====
$edLine = if ($EspeakDll) { '$env:PHONEMIZER_ESPEAK_LIBRARY=' + "'$EspeakDll';" } else { "" }
$edCmd = if ($EspeakDll) { "if(Test-Path '$EspeakDll'){`$env:PHONEMIZER_ESPEAK_LIBRARY='$EspeakDll'};" } else { "" }
Set-Content (Join-Path $VerityTMPath "FastKoko.ps1") -Enc UTF8 -Value @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$repoPath = Join-Path `$scriptDir "Kokoro-FastAPI"
`$vu = Join-Path `$repoPath ".venv\Scripts\uvicorn.exe"
if (!(Test-Path `$vu)) { Write-Host "ERROR: Kokoro-FastAPI not found. Run setup.ps1 first." -F Red; Read-Host; exit 1 }
`$env:PYTHONUTF8 = "1"
$($edLine)
`$env:MODEL_DIR = Join-Path `$repoPath "api\src\models"
`$env:VOICES_DIR = Join-Path `$repoPath "api\src\voices\v1_0"
`$env:PYTHONPATH = "`$repoPath;`$repoPath\api"

Write-Host "";Write-Host "================================================" -F Yellow
Write-Host "  FastKoko - Kokoro TTS  :8880" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

Write-Host "Starting server..." -F Yellow
Start-Process powershell -NoExit -Arg "-NoExit","-Command","`$env:PYTHONUTF8='1';$($edCmd)`$env:MODEL_DIR='$(`$env:MODEL_DIR)';`$env:VOICES_DIR='$(`$env:VOICES_DIR)';`$env:PYTHONPATH='$(`$env:PYTHONPATH)'; & '`$vu' api.src.main:app --host 127.0.0.1 --port 8880" -WindowStyle Minimized

Write-Host "Waiting for server..." -F Yellow
`$rd = `$false;for(`$i=1;`$i -le 50;`$i++){Start-Sleep -Milliseconds 600;try{`$r=Invoke-WebRequest "http://127.0.0.1:8880/docs" -TimeoutSec 2 -EA SilentlyContinue;if(`$r.StatusCode -eq 200){`$rd=`$true;break}}catch{}}
if (!`$rd) { Write-Host "ERROR: Server not started" -F Red; Read-Host; exit 1 }
Write-Host "SERVER READY!" -F Green
Write-Host "API: http://127.0.0.1:8880/v1/" -F Yellow
Write-Host "Web: http://127.0.0.1:8880/web/" -F DarkGray

try { `$vd = Invoke-RestMethod "http://127.0.0.1:8880/v1/audio/voices"; `$av = `$vd.voices } catch { Write-Host "Error loading voices" -F Red; Read-Host; exit 1 }
`$it = @(); `$en = @(); `$ot = @()
foreach (`$v in `$av) { `$id = `$v.id.ToLower(); if (`$id -match "^i[fm]_") { `$it += `$v } elseif (`$id -match "^[abef]_[a-z]+") { `$en += `$v } else { `$ot += `$v } }
`$opt = 1;Write-Host "";Write-Host "[ITALIAN]" -F Magenta;foreach(`$v in `$it){Write-Host "  `$opt. `$(`$v.id)";`$opt++}
Write-Host "";Write-Host "[ENGLISH]" -F Magenta;foreach(`$v in `$en){Write-Host "  `$opt. `$(`$v.id)";`$opt++}
Write-Host "";Write-Host "[OTHER]" -F Magenta;foreach(`$v in `$ot){Write-Host "  `$opt. `$(`$v.id)";`$opt++}
`$al = @(`$it) + @(`$en) + @(`$ot); `$dv = `$al[0].id
Write-Host "";Write-Host "Voice [`$dv]:" -F Yellow; `$c = Read-Host "  >"
if (`$c) { `$id=[int]`$c-1; if(`$id -ge 0 -and `$id -lt `$al.Count){`$sv=`$al[`$id].id}else{`$sv=`$dv} } else { `$sv = `$dv }
Write-Host "Voice: `$sv" -F Green

Write-Host "`nText (Enter twice to submit):" -F Yellow; `$tl = @(); `$f = `$true
while (`$true) { if (`$f) { `$l = Read-Host "  >"; `$f = `$false } else { `$l = Read-Host "  > (Enter to submit)" }; if (!`$l.Trim()) { break }; `$tl += `$l }
`$t = `$tl -join "`n"; if (!`$t.Trim()) { Write-Host "No text" -F Red; Read-Host; exit 0 }
Write-Host "`nGenerating..." -F Yellow
try { `$b = @{model="kokoro";voice=`$sv;input=`$t;response_format="mp3"} | ConvertTo-Json; `$r = Invoke-WebRequest "http://127.0.0.1:8880/v1/audio/speech" -Method Post -ContentType "application/json" -Body `$b -TimeoutSec 120; `$ts = Get-Date -Format "yyyyMMdd_HHmmss"; `$o = Join-Path `$env:USERPROFILE\Desktop "tts_`$sv`_`$ts.mp3"; [IO.File]::WriteAllBytes(`$o, `$r.Content); Write-Host "Saved: `$o" -F Green } catch { Write-Host "ERROR: `$_" -F Red }
Read-Host "`nPress Enter"
"@

# ==== WhisperServer.bat ====
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0WhisperLauncher.ps1"
pause
"@ | Set-Content (Join-Path $VerityTMPath "WhisperServer.bat") -Enc UTF8

# ==== WhisperLauncher.ps1 ====
Set-Content (Join-Path $VerityTMPath "WhisperLauncher.ps1") -Enc UTF8 -Value @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$venvPython = Join-Path `$scriptDir "WhisperServer\.venv\Scripts\python.exe"
`$serverPy = Join-Path `$scriptDir "WhisperServer\server.py"
if (!(Test-Path `$venvPython)) { Write-Host "ERROR: WhisperServer not found. Run setup.ps1 first." -F Red; Read-Host; exit 1 }
if (!(Test-Path `$serverPy)) { Write-Host "ERROR: server.py not found." -F Red; Read-Host; exit 1 }

Write-Host "";Write-Host "================================================" -F Yellow
Write-Host "  WhisperServer - STT ($WhisperModel)  :9000" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

Write-Host "Starting server..." -F Yellow
`$cmd = "& `$venvPython `$serverPy"
Start-Process powershell -NoExit -WindowStyle Minimized -Arg "-NoExit","-Command",`$cmd

Write-Host "Waiting (model may take a minute)..." -F Yellow
`$rd = `$false
for (`$i = 1; `$i -le 120; `$i++) { Start-Sleep -Milliseconds 500; try { `$r = Invoke-WebRequest "http://127.0.0.1:9000/v1/models" -TimeoutSec 2 -EA SilentlyContinue; if (`$r.StatusCode -eq 200) { `$rd = `$true; break } } catch {} }
if (!`$rd) { Write-Host "ERROR: Server not started" -F Red; Read-Host; exit 1 }

Write-Host "SERVER READY!" -F Green
Write-Host "API: http://127.0.0.1:9000/v1/" -F Yellow
Write-Host "  curl -X POST http://127.0.0.1:9000/v1/audio/speech -F `"file=@audio.mp3`"" -F DarkGray
Read-Host "`nPress Enter"
"@

# ==== Manager.bat ====
@"
@echo off
powershell -ExecutionPolicy Bypass -File "%~dp0Manager.ps1"
"@ | Set-Content (Join-Path $VerityTMPath "Manager.bat") -Enc UTF8

# ==== Manager.ps1 ====
Set-Content (Join-Path $VerityTMPath "Manager.ps1") -Enc UTF8 -Value @"
`$scriptDir = Split-Path -Parent `$MyInvocation.MyCommand.Path
`$uvBin = "$UvBin"
if ((Test-Path `$uvBin) -and (`$env:Path -notlike "*`$uvBin*")) { `$env:Path += ";`$uvBin" }

`$services = @{
  FastKoko = @{ n = "FastKoko (TTS)"; p = 8880; u = "http://127.0.0.1:8880/v1/"; r = `$false }
  LiteLLM  = @{ n = "LiteLLM (AI)";  p = 4000; u = "http://127.0.0.1:4000/v1/"; r = `$false }
  Whisper   = @{ n = "Whisper (STT)"; p = 9000; u = "http://127.0.0.1:9000/v1/"; r = `$false }
}

function tp(`$p) {
  try { `$t = New-Object Net.Sockets.TcpClient; `$t.ConnectAsync("127.0.0.1", `$p).Wait(300); `$c = `$t.Client.Connected; `$t.Close(); return `$c } catch { return `$false }
}

function Menu {
  Write-Host ""
  Write-Host "================================================" -F Yellow
  Write-Host "  Verity JE - Manager" -F Yellow
  Write-Host "================================================" -F Yellow
  Write-Host "  [S] Start all  [A] Stop all  [R] Restart all" -F White
  Write-Host ""
  Write-Host "  -- Services --" -F Yellow
  `$services.GetEnumerator() | Sort Name | ForEach-Object {
    `$k = `$_.Key; `$s = `$_.Value
    `$st = if (`$s.r) { "ON " } else { "OFF" }
    `$co = if (`$s.r) { "Green" } else { "Red" }
    Write-Host "  [`$(`$k.Substring(0,1))] `$(`$s.n,-22) ``$st  `$(`$s.u)" -F `$co
  }
  Write-Host ""
  Write-Host "  [Q] Quit" -F Yellow
  Write-Host ""
}

function StartS(`$n, `$bat) {
  `$s = `$services[`$n]; if (`$s.r) { Write-Host "  [``$n] already running" -F Yellow; return }
  `$b = Join-Path `$scriptDir `$bat
  if (!(Test-Path `$b)) { Write-Host "  [``$n] script not found" -F Red; return }
  Write-Host "  [``$n] starting..." -F Yellow
  `$p = Start-Process powershell -NoExit -Arg "-EP","Bypass","-File",`$b -WindowStyle Minimized -PassThru
  Start-Sleep 2
  if (tp `$s.p) { `$s.r = `$true; Write-Host "  [``$n] started" -F Green } else { Write-Host "  [``$n] starting (wait)..." -F Yellow }
}

function StopS(`$n) {
  `$s = `$services[`$n]; if (!`$s.r) { Write-Host "  [``$n] already stopped" -F Yellow; return }
  Write-Host "  [``$n] stopping..." -F Yellow
  Get-NetTCPConnection -LocalPort `$s.p -EA SilentlyContinue | ForEach-Object { Stop-Process -Id `$_.OwningProcess -Force -EA SilentlyContinue }
  `$s.r = `$false; Write-Host "  [``$n] stopped" -F Red
}

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  Verity JE - Manager" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""
foreach (`$k in `$services.Keys) { if (tp `$services[`$k].p) { `$services[`$k].r = `$true; Write-Host "  [``$(`$services[`$k].n)] detected" -F Green } }

while (`$true) {
  Menu
  `$k = (Read-Host "Choice").ToUpper()
  switch (`$k) {
    "S" { StartS FastKoko "FastKoko.bat"; StartS LiteLLM "LiteLLM.bat"; StartS Whisper "WhisperServer.bat" }
    "A" { StopS FastKoko; StopS LiteLLM; StopS Whisper }
    "R" { StopS FastKoko; StopS LiteLLM; StopS Whisper; Start-Sleep 2; StartS FastKoko "FastKoko.bat"; StartS LiteLLM "LiteLLM.bat"; StartS Whisper "WhisperServer.bat" }
    "F" { StartS FastKoko "FastKoko.bat" }
    "I" { StartS LiteLLM "LiteLLM.bat" }
    "W" { StartS Whisper "WhisperServer.bat" }
    "Q" { Write-Host "`nShutting down..." -F Yellow; StopS FastKoko; StopS LiteLLM; StopS Whisper; Write-Host "Done" -F Green; break }
    default { Write-Host "  Invalid choice" -F Red }
  }
}
"@

Write-Host "All scripts generated"
