$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoPath = Join-Path $scriptDir "Kokoro-FastAPI"
$vu = Join-Path $repoPath ".venv\Scripts\uvicorn.exe"
if(!(Test-Path $vu)){Write-Host "ERROR: Kokoro-FastAPI not found. Run setup.ps1 first." -F Red;Read-Host;exit 1}
$env:PYTHONUTF8="1";$ed="C:\Program Files\eSpeak NG\libespeak-ng.dll"
if(Test-Path $ed){$env:PHONEMIZER_ESPEAK_LIBRARY=$ed}
$env:MODEL_DIR=Join-Path $repoPath "api\src\models"
$env:VOICES_DIR=Join-Path $repoPath "api\src\voices\v1_0"
$env:PYTHONPATH="$repoPath;$repoPath\api"

Write-Host "";Write-Host "================================================" -F Yellow
Write-Host "  FastKoko - Kokoro TTS  :8880" -F Yellow
Write-Host "================================================" -F Yellow

Write-Host "`nStarting server..." -F Yellow
Start-Process powershell -NoExit -Arg "-NoExit","-Command","$env:PYTHONUTF8='1';if(Test-Path '$ed'){$env:PHONEMIZER_ESPEAK_LIBRARY='$ed'};$env:MODEL_DIR='$env:MODEL_DIR';$env:VOICES_DIR='$env:VOICES_DIR';$env:PYTHONPATH='$env:PYTHONPATH';& '$vu' api.src.main:app --host 127.0.0.1 --port 8880" -WindowStyle Minimized

Write-Host "Waiting for server..." -F Yellow
$rd=$false;for($i=1;$i -le 50;$i++){Start-Sleep -Milliseconds 600;try{$r=Invoke-WebRequest "http://127.0.0.1:8880/docs" -TimeoutSec 2 -EA SilentlyContinue;if($r.StatusCode -eq 200){$rd=$true;break}}catch{}}
if(!$rd){Write-Host "ERROR: Server not started" -F Red;Read-Host;exit 1}
Write-Host "SERVER READY!" -F Green
Write-Host "API: http://127.0.0.1:8880/v1/" -F Yellow
Write-Host "Web: http://127.0.0.1:8880/web/" -F DarkGray

try{$vd=Invoke-RestMethod "http://127.0.0.1:8880/v1/audio/voices";$av=$vd.voices}catch{Write-Host "Error loading voices" -F Red;Read-Host;exit 1}
$it=@();$en=@();$ot=@();foreach($v in $av){$id=$v.id.ToLower();if($id -match "^i[fm]_"){$it+=$v}elseif($id -match "^[abef]_[a-z]+"){$en+=$v}else{$ot+=$v}}
$opt=1;Write-Host "";Write-Host "[ITALIAN]" -F Magenta;foreach($v in $it){Write-Host "  $opt. $($v.id)";$opt++}
Write-Host "";Write-Host "[ENGLISH]" -F Magenta;foreach($v in $en){Write-Host "  $opt. $($v.id)";$opt++}
Write-Host "";Write-Host "[OTHER]" -F Magenta;foreach($v in $ot){Write-Host "  $opt. $($v.id)";$opt++}
$al=@($it)+@($en)+@($ot);$dv=$al[0].id
Write-Host "";Write-Host "Voice [$dv]:" -F Yellow;$c=Read-Host "  >"
if($c){$id=[int]$c-1;if($id -ge 0 -and $id -lt $al.Count){$sv=$al[$id].id}else{$sv=$dv}}else{$sv=$dv}
Write-Host "Voice: $sv" -F Green

Write-Host "`nText (Enter twice to submit):" -F Yellow;$tl=@();$f=$true
while($true){if($f){$l=Read-Host "  >";$f=$false}else{$l=Read-Host "  > (Enter to submit)"};if(!$l.Trim()){break};$tl+=$l}
$t=$tl -join "`n";if(!$t.Trim()){Write-Host "No text" -F Red;Read-Host;exit 0}
Write-Host "`nGenerating..." -F Yellow
try{$b=@{model="kokoro";voice=$sv;input=$t;response_format="mp3"}|ConvertTo-Json;$r=Invoke-WebRequest "http://127.0.0.1:8880/v1/audio/speech" -Method Post -ContentType "application/json" -Body $b -TimeoutSec 120;$ts=Get-Date -Format "yyyyMMdd_HHmmss";$o=Join-Path $env:USERPROFILE\Desktop "tts_$sv`_$ts.mp3";[IO.File]::WriteAllBytes($o,$r.Content);Write-Host "Saved: $o" -F Green}catch{Write-Host "ERROR: $_" -F Red}
Read-Host "`nPress Enter"
