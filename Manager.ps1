$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$uvBin = "C:\Users\rreza\.local\bin"
if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

$services = @{
  FastKoko = @{ n = "FastKoko (TTS)"; p = 8880; u = "http://127.0.0.1:8880/v1/"; r = $false }
  LiteLLM  = @{ n = "LiteLLM (AI)";  p = 4000; u = "http://127.0.0.1:4000/v1/"; r = $false }
  Whisper   = @{ n = "Whisper (STT)"; p = 9000; u = "http://127.0.0.1:9000/v1/"; r = $false }
}

function tp($p) {
  try { $t = New-Object Net.Sockets.TcpClient; $t.ConnectAsync("127.0.0.1", $p).Wait(300); $c = $t.Client.Connected; $t.Close(); return $c } catch { return $false }
}

function Menu {
  Write-Host ""
  Write-Host "================================================" -F Yellow
  Write-Host "  Verity JE - Manager" -F Yellow
  Write-Host "================================================" -F Yellow
  Write-Host "  [S] Start all  [A] Stop all  [R] Restart all" -F White
  Write-Host ""
  Write-Host "  -- Services --" -F Yellow
  $services.GetEnumerator() | Sort Name | ForEach-Object {
    $k = $_.Key; $s = $_.Value
    $st = if ($s.r) { "ON " } else { "OFF" }
    $co = if ($s.r) { "Green" } else { "Red" }
    Write-Host "  [$($k.Substring(0,1))] $($s.n,-22) `  $($s.u)" -F $co
  }
  Write-Host ""
  Write-Host "  [Q] Quit" -F Yellow
  Write-Host ""
}

function StartS($n, $bat) {
  $s = $services[$n]; if ($s.r) { Write-Host "  [`] already running" -F Yellow; return }
  $b = Join-Path $scriptDir $bat
  if (!(Test-Path $b)) { Write-Host "  [`] script not found" -F Red; return }
  Write-Host "  [`] starting..." -F Yellow
  $p = Start-Process powershell -NoExit -Arg "-EP","Bypass","-File",$b -WindowStyle Minimized -PassThru
  Start-Sleep 2
  if (tp $s.p) { $s.r = $true; Write-Host "  [`] started" -F Green } else { Write-Host "  [`] starting (wait)..." -F Yellow }
}

function StopS($n) {
  $s = $services[$n]; if (!$s.r) { Write-Host "  [`] already stopped" -F Yellow; return }
  Write-Host "  [`] stopping..." -F Yellow
  Get-NetTCPConnection -LocalPort $s.p -EA SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue }
  $s.r = $false; Write-Host "  [`] stopped" -F Red
}

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  Verity JE - Manager" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""
foreach ($k in $services.Keys) { if (tp $services[$k].p) { $services[$k].r = $true; Write-Host "  [`] detected" -F Green } }

while ($true) {
  Menu
  $k = (Read-Host "Choice").ToUpper()
  switch ($k) {
    "S" { StartS FastKoko "FastKoko.bat"; StartS LiteLLM "LiteLLM.bat"; StartS Whisper "WhisperServer.bat" }
    "A" { StopS FastKoko; StopS LiteLLM; StopS Whisper }
    "R" { StopS FastKoko; StopS LiteLLM; StopS Whisper; Start-Sleep 2; StartS FastKoko "FastKoko.bat"; StartS LiteLLM "LiteLLM.bat"; StartS Whisper "WhisperServer.bat" }
    "F" { StartS FastKoko "FastKoko.bat" }
    "I" { StartS LiteLLM "LiteLLM.bat" }
    "W" { StartS Whisper "WhisperServer.bat" }
    "Q" { Write-Host "
Shutting down..." -F Yellow; StopS FastKoko; StopS LiteLLM; StopS Whisper; Write-Host "Done" -F Green; break }
    default { Write-Host "  Invalid choice" -F Red }
  }
}
