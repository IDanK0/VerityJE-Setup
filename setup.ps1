<# Verity JE Setup #>
[CmdletBinding()] param([string]$Path)
$ErrorActionPreference = "Continue"
if (-not $Path) { $Path = Split-Path -Parent $MyInvocation.MyCommand.Path }
$startDir = Get-Location
$Yl = "Yellow"; $Gn = "Green"; $Rd = "Red"; $Wh = "White"; $Dg = "DarkGray"
function T($n) { try { Get-Command $n -EA Stop; return $true } catch { return $false } }
function K { [Console]::ReadKey($true) }
Clear-Host

function spn($label, $step, $total, [scriptblock]$sb, $xa = @()) {
    $ja = @($Path, $startDir) + $xa
    $job = Start-Job -ScriptBlock $sb -ArgumentList $ja
    $ch = @("\", "|", "/", "-"); $i = 0; $sw = [Diagnostics.Stopwatch]::StartNew()
    $pf = if ($total -gt 0) { "[$step/$total] " } else { "" }
    while ($job.State -eq "Running") {
        $el = [math]::Floor($sw.Elapsed.TotalSeconds)
        $ts = if ($el -gt 60) { "$([math]::Floor($el/60))m$($el%60)s" } else { "${el}s" }
        Write-Host ("`r  {0} {1}{2}... ({3})" -f $ch[$i % 4], $pf, $label, $ts) -NoNewline -F $Wh
        Start-Sleep -Milliseconds 200; $i++
    }
    $el = [math]::Floor($sw.Elapsed.TotalSeconds)
    $ts = if ($el -gt 60) { "$([math]::Floor($el/60))m$($el%60)s" } else { "${el}s" }
    $result = $job | Receive-Job; Remove-Job $job -Force
    if ($job.State -eq "Completed") { Write-Host "`r  done  ${pf}${label} (${ts})" -F $Gn } else { Write-Host "`r  FAIL  ${pf}${label}" -F $Rd; Write-Host "  ERROR: $result" -F $Rd; Read-Host; exit 1 }
}

function phase($t) { Clear-Host; Write-Host "`n  Verity JE Setup - $t`n" -F $Yl }
function wait { Start-Sleep -Seconds 1 }
function die($msg) { Write-Host "  FAIL: $msg" -F $Rd; Read-Host; exit 1 }

function Get-CudaIndex { try { $nv = & nvidia-smi 2>&1 | Out-String; if ($nv -match "CUDA UMD Version:\s*(\d+)\.(\d+)") { $m = [int]$Matches[1]; $n = [int]$Matches[2]; $av = @("cu129","cu128","cu126","cu124","cu121"); foreach ($a in $av) { $v = [int]($a -replace 'cu','').Substring(0,2)*100+[int]($a -replace 'cu','').Substring(2); if ($v -le ($m*100+$n)) { return $a } }; return $av[-1] } } catch { }; return "cu128" }
function Get-BestPython { foreach ($v in @("3.10","3.11","3.12","3.13")) { try { $o = & uv python find $v 2>&1; if ($LASTEXITCODE -eq 0 -and $o) { return $v } } catch { } }; return "3.10" }
function Get-EspeakDll { foreach ($p in @("$env:ProgramFiles\eSpeak NG\libespeak-ng.dll","${env:ProgramFiles(x86)}\eSpeak NG\libespeak-ng.dll","$env:LOCALAPPDATA\Programs\eSpeak NG\libespeak-ng.dll")) { if (Test-Path $p) { return $p } }; return "" }
function Get-UvBin { foreach ($p in @("$env:USERPROFILE\.local\bin","$env:APPDATA\uv\bin")) { if (Test-Path $p) { return $p } }; return "" }
function Pip-Has($vd,$pkg) { $py = Join-Path $vd ".venv\Scripts\python.exe"; if (Test-Path $py) { try { & $py -c "import $pkg" 2>&1 | Out-Null; return $LASTEXITCODE -eq 0 } catch { return $false } }; return $false }
function Pip-Install($vd,$pkgList,$extra="") { $pip = Join-Path $vd ".venv\Scripts\pip.exe"; & $pip install --upgrade pip -q 2>&1 | Out-Null; foreach ($p in $pkgList) { & $pip install $p -q 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { die "pip failed to install: $p" } }; if ($extra) { & $pip install $extra -q 2>&1 | Out-Null }; return $true }

$cudaIdx = "cu128"; $bestPy = "3.10"; $espeakPath = ""; $uvBin = ""

# === DETECT ===
while ($true) { Clear-Host; Write-Host "`n  Verity JE Setup - System Detection`n" -F $Yl
    $hasGit = T git; $hasPy = T python; if ($hasPy) { $pyVer = & python --version 2>&1 }; $hasUv = T uv
    $hasGPU = $false; $vramGB = 0; $gpuName = ""
    try { $vg = Get-CimInstance Win32_VideoController -EA SilentlyContinue; if ($vg) { foreach ($item in $vg) { if ($item.Name -match "NVIDIA|GeForce") { $hasGPU = $true; $gpuName = $item.Name; break } } } } catch { }
    if ($hasGPU) { try { $nv = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1; if ($nv -match '(\d+)') { $vramGB = [math]::Floor([int]$Matches[1] / 1024) } } catch { if ($vramGB -lt 1) { $vramGB = 4 } }; $cudaIdx = Get-CudaIndex }
    $ramGB = 0; try { $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue; if ($cs) { $ramGB = [math]::Floor($cs.TotalPhysicalMemory / 1GB) } } catch { }
    if ($hasUv) { $bestPy = Get-BestPython; $uvBin = Get-UvBin }; $espeakPath = Get-EspeakDll
    $co = if ($hasGit) { $Gn } else { $Rd }; Write-Host "  Git    " -NoNewline -F $Dg; Write-Host $(if ($hasGit) { "found" } else { "missing" }) -F $co
    $co = if ($hasPy) { $Gn } else { $Rd }; Write-Host "  Python " -NoNewline -F $Dg; Write-Host $(if ($hasPy) { $pyVer } else { "missing" }) -F $co
    $co = if ($hasUv) { $Gn } else { $Rd }; Write-Host "  uv     " -NoNewline -F $Dg; Write-Host $(if ($hasUv) { "found" } else { "missing" }) -F $co
    $co = if ($hasGPU) { $Gn } else { $Dg }; Write-Host "  GPU    " -NoNewline -F $Dg; Write-Host $(if ($hasGPU) { "$gpuName ($vramGB GB)" } else { "CPU only" }) -F $co
    Write-Host "  RAM    " -NoNewline -F $Dg; Write-Host "$ramGB GB" -F $Wh
    Write-Host "  CUDA   " -NoNewline -F $Dg; Write-Host " $cudaIdx" -F $Gn
    Write-Host "  Python " -NoNewline -F $Dg; Write-Host " $bestPy (venv)" -F $Gn
    Write-Host "`n  [Enter] continue  [Q] quit" -F $Dg; $k = K; if ($k.Key -eq "Q") { exit 0 }; if ($k.Key -eq "Enter") { break }
}

# === SERVICES ===
$svc = @{ K=$true; L=$true; W=$true }; $cursor = 0
while ($true) { Clear-Host; Write-Host "`n  Verity JE Setup - Service Selection`n" -F $Yl
    $items = @(("FastKoko","Text-to-Speech    Kokoro-82M    :8880","K"),("LiteLLM","AI Gateway        100+ LLMs     :4000","L"),("WhisperServer","Speech-to-Text    Whisper       :9000","W"))
    for ($i=0; $i -lt 3; $i++) { $cur = if ($i -eq $cursor) { " >>" } else { "   " }; $chk = if ($svc[$items[$i][2]]) { "[X]" } else { "[ ]" }; Write-Host "  $cur $chk " -NoNewline -F $Wh; Write-Host $items[$i][0].PadRight(15) -NoNewline -F $Wh; Write-Host $items[$i][1] -F $Dg }
    Write-Host "`n  [Up/Down] move  [Space] toggle  [Enter] confirm  [B] back  [Q] quit" -F $Dg; $k = K
    if ($k.Key -eq "Q") { exit 0 }; if ($k.Key -eq "B") { break }
    if ($k.Key -eq "UpArrow") { $cursor=[Math]::Max(0,$cursor-1) }; if ($k.Key -eq "DownArrow") { $cursor=[Math]::Min(2,$cursor+1) }
    if ($k.Key -eq "Spacebar") { $svc[$items[$cursor][2]] = -not $svc[$items[$cursor][2]] }
    if ($k.Key -eq "Enter") { if (-not ($svc.K -or $svc.L -or $svc.W)) { Write-Host "`n  Select at least one." -F $Rd; wait } else { break } }
}

# === CONFIRM ===
while ($true) { Clear-Host; Write-Host "`n  Verity JE Setup - Confirm`n" -F $Yl; Write-Host "  Will install:`n" -F $Wh
    if ($svc.K) { Write-Host "    [X] FastKoko" -F $Gn }
    if ($svc.L) { Write-Host "    [X] LiteLLM" -F $Gn }
    if ($svc.W) { Write-Host "    [X] WhisperServer" -F $Gn }
    Write-Host "`n  Path: $Path" -F $Dg; Write-Host "  CUDA: $cudaIdx  Python: $bestPy" -F $Dg
    Write-Host "`n  [Y] proceed  [B] back  [Q] quit" -F $Dg; $k = K; if ($k.Key -eq "Q") { exit 0 }; if ($k.Key -eq "B") { break }; if ($k.KeyChar -eq 'y') { break }
}

# === SYSTEM DEPS ===
if (-not $hasGit -or -not $hasUv -or (-not $espeakPath -and $svc.K)) { phase "System Dependencies"
    if (-not $hasGit) {
        Write-Host "  Installing Git..." -F $Wh
        if (T winget) { winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null; $env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User") }
        else { $t=Join-Path$env:TEMP"GitSetup.exe"; (New-Object Net.WebClient).DownloadFile("https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe",$t); Start-Process -FilePath$t -Arg"/SILENT" -Wait; Remove-Item$t -EA SilentlyContinue; $env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User") }
        if (T git) { Write-Host "  Git installed" -F $Gn; $hasGit=$true } else { die "Git install failed" }
    }
    if (-not $hasUv) {
        Write-Host "  Installing uv..." -F $Wh
        if (T winget) { winget install --id AstralSoftware.uv -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null; $env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User") }
        else { powershell -NoProfile -EP Bypass -Command "Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression" 2>&1 | Out-Null; $env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User") }
        if (T uv) { Write-Host "  uv installed" -F $Gn; $hasUv=$true; $bestPy=Get-BestPython; $uvBin=Get-UvBin } else { die "uv install failed" }
    }
    if (-not $espeakPath -and $svc.K) { if (T winget) { winget install --id eSpeak-NG.eSpeak-NG -e --silent --accept-source-agreements 2>&1 | Out-Null } else { Write-Host "  eSpeak NG skipped (optional)" -F $Dg }; $espeakPath=Get-EspeakDll; if ($espeakPath) { Write-Host "  eSpeak NG installed" -F $Gn } }
    wait
}

# === FASTKOKO ===
if ($svc.K) { $kD=Join-Path$Path"Kokoro-FastAPI"; $kPy=Join-Path$kD".venv\Scripts\python.exe"; $kM=Join-Path$kD"api\src\models\v1_0\kokoro-v1_0.pth"
    phase "FastKoko - Kokoro TTS"
    if (Test-Path(Join-Path$kD"api\src\main.py")) { Write-Host "  skip  [1/5] Repository" -F $Dg } else { spn "Clone repository" 1 5 { param($P,$S) Set-Location$S; & git clone https://github.com/remsky/Kokoro-FastAPI.git(Join-Path$P"Kokoro-FastAPI") 2>&1|Out-Null; if (-not(Test-Path(Join-Path$P"Kokoro-FastAPI\api\src\main.py"))){throw"Clone failed"} } }
    if (Test-Path$kPy) { Write-Host "  skip  [2/5] Environment" -F $Dg } else { Write-Host "  [2/5] Creating Python environment ($bestPy)..." -F $Wh; Set-Location$kD; $e=& uv venv .venv --python$bestPy --seed 2>&1; if (-not(Test-Path".venv\Scripts\python.exe")){die"venv failed: $e"}; Set-Location$startDir; Write-Host "  done  [2/5] Environment" -F $Gn }
    if (Pip-Has$kD"kokoro") { Write-Host "  skip  [3/5] Dependencies" -F $Dg } else { Write-Host "  [3/5] Installing dependencies..." -F $Wh; Set-Location$kD; Pip-Install$kD @("cython<3.0") "-e.[cpu]"; & (Join-Path$kD".venv\Scripts\pip.exe") uninstall torch -y -q 2>&1|Out-Null; & (Join-Path$kD".venv\Scripts\pip.exe") install torch --index-url"https://download.pytorch.org/whl/$cudaIdx" --timeout 600 -q 2>&1|Out-Null; Set-Location$startDir; Write-Host "  done  [3/5] Dependencies" -F $Gn }
    Set-Location$startDir
    if (Test-Path$kM) { Write-Host "  skip  [4/5] Model" -F $Dg } else { Write-Host "  [4/5] Downloading Kokoro model (350 MB)..." -F $Wh; (New-Object Net.WebClient).DownloadFile("https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth",$kM); Write-Host "  done  [4/5] Model" -F $Gn }
    Write-Host "  [5/5] Ready" -F $Gn; wait
}

# === LITELLM ===
if ($svc.L) { phase "LiteLLM - AI Gateway"
    if (T litellm) { Write-Host "  skip  LiteLLM ($(& litellm --version 2>&1))" -F $Dg } else { spn "Install LiteLLM" 0 0 { param($P,$S) uv tool install "litellm[proxy]" 2>&1|Out-Null }; Write-Host "  done  LiteLLM installed" -F $Gn }
    if ($uvBin -and ($env:Path -notlike"*$uvBin*")) { $env:Path+=";$uvBin" }
    wait
}

# === WHISPER ===
if ($svc.W) { $wD=Join-Path$Path"WhisperServer"; $wPy=Join-Path$wD".venv\Scripts\python.exe"; New-Item -ItemType Dir -Path$wD -Force|Out-Null
    $wModel="base"; if ($hasGPU -and$vramGB -ge 6) { $wModel="large-v3-turbo" } elseif ($hasGPU -and$vramGB -ge 4) { $wModel="medium" } elseif ($hasGPU) { $wModel="base" } elseif ($ramGB -lt 16) { $wModel="tiny" }
    $device = if ($hasGPU) { "cuda" } else { "cpu" }
    phase "WhisperServer - STT ($wModel)"
    if (Test-Path$wPy) { Write-Host "  skip  [1/3] Environment" -F $Dg } else { Write-Host "  [1/3] Creating Python environment ($bestPy)..." -F $Wh; Set-Location$wD; $e=& uv venv .venv --python$bestPy --seed 2>&1; if (-not(Test-Path".venv\Scripts\python.exe")){die"venv failed: $e"}; Set-Location$startDir; Write-Host "  done  [1/3] Environment" -F $Gn }
    if (Pip-Has$wD"whisper") { Write-Host "  skip  [2/3] Dependencies" -F $Dg } else { Write-Host "  [2/3] Installing dependencies..." -F $Wh; Set-Location$wD; Pip-Install$wD @("openai-whisper>=1.1.10","uvicorn[standard]","fastapi","pydantic","python-multipart","mutagen"); if ($hasGPU) { & (Join-Path$wD".venv\Scripts\pip.exe") uninstall torch -y -q 2>&1|Out-Null; & (Join-Path$wD".venv\Scripts\pip.exe") install torch --index-url"https://download.pytorch.org/whl/$cudaIdx" --timeout 600 -q 2>&1|Out-Null }; Set-Location$startDir; Write-Host "  done  [2/3] Dependencies" -F $Gn }
    $wFix=Join-Path$wD".venv\Lib\site-packages\whisper.py"; if (Test-Path$wFix) { $c=Get-Content$wFix -Raw; if ($c -notmatch"msvcrt") { $c=$c-replace"libc_name = ctypes.util.find_library\('c'\)",'libc_name = "msvcrt.dll"'; $c|Set-Content$wFix -Enc UTF8 } }
    Write-Host "  [3/3] Downloading Whisper model ($wModel, $device)..." -F $Wh; Set-Location$wD; $r=& $wPy -c "import whisper; whisper.load_model('$wModel',device='$device');print('OK')" 2>&1; Set-Location$startDir
    if ($r -match "OK") { Write-Host "  done  [3/3] Model loaded" -F $Gn } else { die "Model load failed: $r" }
    wait
}

# === OLLAMA ===
if (-not (T ollama)) { phase "Ollama (optional)"
    Write-Host "  Ollama runs LLMs locally (private, offline)." -F $Wh; Write-Host "  [Y] install  [N] skip" -F $Dg; $k=K
    if ($k.KeyChar -eq 'y') { $t=Join-Path$env:TEMP"OllamaSetup.exe"; spn "Download Ollama" 0 0 { param($P,$S) (New-Object Net.WebClient).DownloadFile("https://ollama.com/download/ollama-windows-amd64.exe",(Join-Path$env:TEMP"OllamaSetup.exe")) }; if (Test-Path$t) { Start-Process -FilePath$t -Arg"/S" -Wait -EA SilentlyContinue; Remove-Item$t -EA SilentlyContinue; $env:Path=[Environment]::GetEnvironmentVariable("Path","Machine")+";"+[Environment]::GetEnvironmentVariable("Path","User") }; if (T ollama) { Write-Host "  Ollama installed" -F $Gn } else { Write-Host "  Ollama installed (restart terminal)" -F $Dg } }
    wait
}
if (T ollama) { Write-Host "`n  Pull a model? (e.g. llama3.2) Enter = skip" -F $Wh; Write-Host "  > " -NoNewline -F $Dg; $m=Read-Host; if ($m) { spn "Pull $m" 0 0 { param($P,$S,$mod) & ollama pull$mod 2>&1|Out-Null } -xa$m|Out-Null; Write-Host "  Model $m pulled" -F $Gn } }

# === SCRIPTS ===
phase "Generating Launcher Scripts"; Write-Host "  Creating .bat and .ps1 files..." -F $Wh
. "$PSScriptRoot\_generate_scripts.ps1" -VerityTMPath$Path -WhisperModel$wModel -EspeakDll$espeakPath -UvBin$uvBin
Write-Host "  Scripts generated" -F $Gn; wait

# === DONE ===
Clear-Host; Write-Host "`n  Verity JE Setup - Complete!`n" -F $Yl; Write-Host "  Location: $Path`n" -F $Dg
if ($svc.K) { Write-Host "  FastKoko -> http://127.0.0.1:8880/v1/" -F $Gn }
if ($svc.L) { Write-Host "  LiteLLM  -> http://127.0.0.1:4000/v1/" -F $Gn }
if ($svc.W) { Write-Host "  Whisper  -> http://127.0.0.1:9000/v1/ ($wModel)" -F $Gn }
Write-Host "`n  [Y] Launch Manager  [N] Exit" -F $Dg; $k = K
if ($k.KeyChar -eq 'y') { Start-Process powershell -Arg"-NoExit","-EP","Bypass","-File",(Join-Path$Path"Manager.bat") } else { Write-Host "`n  cd `"$Path`" ; .\Manager.bat" -F $Dg }
Write-Host "`n  Press any key." -F $Dg; K | Out-Null
