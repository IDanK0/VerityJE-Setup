$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$uvBin = "$env:USERPROFILE\.local\bin"
if((Test-Path $uvBin)-and($env:Path -notlike "*$uvBin*")){$env:Path+=";$uvBin"}

$services = @{
  FastKoko = @{n="FastKoko (TTS)";p=8880;u="http://127.0.0.1:8880/v1/";r=$false}
  LiteLLM  = @{n="LiteLLM (AI)";p=4000;u="http://127.0.0.1:4000/v1/";r=$false}
  Whisper   = @{n="Whisper (STT)";p=9000;u="http://127.0.0.1:9000/v1/";r=$false}
}
function tp($p){try{$t=New-Object Net.Sockets.TcpClient;$t.ConnectAsync("127.0.0.1",$p).Wait(300);$t.Client.Connected;$t.Close()}catch{$false}}

function Menu {
  Write-Host "";Write-Host "================================================" -F Yellow
  Write-Host "  Verity JE - Manager" -F Yellow
  Write-Host "================================================" -F Yellow
  Write-Host "  [S] Start all  [A] Stop all  [R] Restart all" -F White
  Write-Host ""
  Write-Host "-- Services --" -F Yellow
  $services.GetEnumerator()|Sort Name|%{$k=$_.Key;$s=$_.Value;$st=if($s.r){"ON"}else{"OFF"};$co=if($s.r){"Green"}else{"Red"};Write-Host "  [$($k.Substring(0,1))] $($s.n,-20) $st  $($s.u)" -F $co}
  Write-Host "";Write-Host "  [Q] Quit" -F Yellow
}

function StartS($n,$bat){$s=$services[$n];if($s.r){return};$b=Join-Path $scriptDir $bat;if(!(Test-Path $b)){Write-Host "  $bat missing" -F Red;return};$p=Start-Process powershell -NoExit -Arg "-EP","Bypass","-File",$b -WindowStyle Minimized -PassThru;Start-Sleep 2;if(tp $s.p){$s.r=$true;Write-Host "  $($s.n) started" -F Green}else{Write-Host "  $($s.n) starting..." -F Yellow}}

function StopS($n){$s=$services[$n];if(!$s.r){return};Get-NetTCPConnection -LocalPort $s.p -EA SilentlyContinue|%{Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue};$s.r=$false;Write-Host "  $($s.n) stopped" -F Red}

Write-Host "";Write-Host "================================================" -F Yellow;Write-Host "  Verity JE - Manager" -F Yellow
Write-Host "================================================`n" -F Yellow
foreach($k in $services.Keys){if(tp $services[$k].p){$services[$k].r=$true;Write-Host "  $($services[$k].n) detected" -F Green}}

while($true){Menu;$k=(Read-Host ">").ToUpper()
  switch($k){
    "S"{StartS FastKoko "FastKoko.bat";StartS LiteLLM "LiteLLM.bat";StartS Whisper "WhisperServer.bat"}
    "A"{StopS FastKoko;StopS LiteLLM;StopS Whisper}
    "R"{StopS FastKoko;StopS LiteLLM;StopS Whisper;Start-Sleep 2;StartS FastKoko "FastKoko.bat";StartS LiteLLM "LiteLLM.bat";StartS Whisper "WhisperServer.bat"}
    "F"{StartS FastKoko "FastKoko.bat"}"I"{StartS LiteLLM "LiteLLM.bat"}"W"{StartS Whisper "WhisperServer.bat"}
    "Q"{Write-Host "`nShutting down..." -F Yellow;StopS FastKoko;StopS LiteLLM;StopS Whisper;Write-Host "Done" -F Green;break}
    default{Write-Host "  Invalid" -F Red}
}}
