$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$venvPython = Join-Path $scriptDir "WhisperServer\.venv\Scripts\python.exe"
$serverPy = Join-Path $scriptDir "WhisperServer\server.py"
if (!(Test-Path $venvPython)) { Write-Host "ERROR: WhisperServer not found. Run setup.ps1 first." -F Red; Read-Host; exit 1 }
if (!(Test-Path $serverPy)) { Write-Host "ERROR: server.py not found." -F Red; Read-Host; exit 1 }

Write-Host "";Write-Host "================================================" -F Yellow
Write-Host "  WhisperServer - STT (large-v3-turbo)  :9000" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

Write-Host "Starting server..." -F Yellow
$cmd = "& $venvPython $serverPy"
Start-Process powershell -NoExit -WindowStyle Minimized -Arg "-NoExit","-Command",$cmd

Write-Host "Waiting (model may take a minute)..." -F Yellow
$rd = $false
for ($i = 1; $i -le 120; $i++) { Start-Sleep -Milliseconds 500; try { $r = Invoke-WebRequest "http://127.0.0.1:9000/v1/models" -TimeoutSec 2 -EA SilentlyContinue; if ($r.StatusCode -eq 200) { $rd = $true; break } } catch {} }
if (!$rd) { Write-Host "ERROR: Server not started" -F Red; Read-Host; exit 1 }

Write-Host "SERVER READY!" -F Green
Write-Host "API: http://127.0.0.1:9000/v1/" -F Yellow
Write-Host "  curl -X POST http://127.0.0.1:9000/v1/audio/speech -F "file=@audio.mp3"" -F DarkGray
Read-Host "
Press Enter"
