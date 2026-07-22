<# Verity JE Setup #>
[CmdletBinding()] param([string]$Path)
$ErrorActionPreference = "Continue"
if (!$Path) { $Path = Split-Path -Parent $MyInvocation.MyCommand.Path }
$startDir = Get-Location
$Yl = "Yellow"; $Gn = "Green"; $Rd = "Red"; $Wh = "White"; $Dg = "DarkGray"
function T($n) { try { Get-Command $n -EA Stop; return $true } catch { return $false } }
function K { [Console]::ReadKey($true) }

Clear-Host

# ================================================================
# PROGRESS
# ================================================================
function dl($url,$out,$label) {
    $wc = New-Object System.Net.WebClient; $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $wc.DownloadProgressChanged += {
        if ($_.TotalBytesToReceive -gt 0) {
            $p = [math]::Round($_.BytesReceived/$_.TotalBytesToReceive*100,1)
            $mbD = [math]::Round($_.BytesReceived/1MB,1); $mbT = [math]::Round($_.TotalBytesToReceive/1MB,1)
            $el = [Math]::Max($sw.Elapsed.TotalSeconds, 0.1)
            $sp = [math]::Round($mbD/$el,1); $eta = [math]::Round(($mbT-$mbD)/[Math]::Max($sp,0.01),0)
            Write-Host ("`r  {0}% {1}  {2}/{3} MB  {4} MB/s  ETA {5}s" -f $p,$label,$mbD,$mbT,$sp,$eta) -NoNewline -F $Wh
        }
    }
    $wc.DownloadFile($url, $out); $sw.Stop()
    $ok = (Test-Path $out) -and (Get-Item $out).Length -gt 0
    if ($ok) { Write-Host "`r  done  $label" -F $Gn } else { Write-Host "`r  FAILED  $label" -F $Rd }
    return $ok
}

function spin {
    param($label, [scriptblock]$sb)
    $job = Start-Job -ScriptBlock $sb -ArgumentList $Path, $startDir
    $chars = @("\", "|", "/", "-"); $i = 0; $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($job.State -eq "Running") {
        $el = [math]::Floor($sw.Elapsed.TotalSeconds)
        $ts = if ($el -gt 60) { "$([math]::Floor($el/60))m$($el%60)s" } else { "${el}s" }
        Write-Host ("`r  {0} {1}  {2}" -f $chars[$i%4], $label, $ts) -NoNewline -F $Wh
        Start-Sleep -Milliseconds 200; $i++
    }
    $sw.Stop(); $el = [math]::Floor($sw.Elapsed.TotalSeconds)
    $ts = if ($el -gt 60) { "$([math]::Floor($el/60))m$($el%60)s" } else { "${el}s" }
    $result = $job | Receive-Job; Remove-Job $job -Force
    if ($job.State -eq "Completed") { Write-Host "`r  done  $label  $ts" -F $Gn } else { Write-Host "`r  FAILED  $label" -F $Rd; throw $result }
}

function phase($t) { Clear-Host; Write-Host "`n  Verity JE Setup - $t`n" -F $Yl }

# ================================================================
# PHASE 1: DETECT
# ================================================================
while ($true) {
    Clear-Host; Write-Host "`n  Verity JE Setup - System Detection`n" -F $Yl
    $hasGit = T git; $hasPy = T python; if ($hasPy) { $pyVer = & python --version 2>&1 }; $hasUv = T uv
    $hasGPU = $false; $vramGB = 0; $gpuName = ""
    try { $vg = Get-CimInstance Win32_VideoController -EA SilentlyContinue; if ($vg) { foreach ($dev in $vg) { if ($dev.Name -match "NVIDIA|GeForce") { $hasGPU = $true; $gpuName = $dev.Name; break } } } } catch { }
    if ($hasGPU) { try { $nv = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1; if ($nv -match '(\d+)') { $vramGB = [math]::Floor([int]$Matches[1]/1024) } } catch { if ($vramGB -lt 1) { $vramGB = 4 } } }
    $ramGB = 0; try { $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue; if ($cs) { $ramGB = [math]::Floor($cs.TotalPhysicalMemory/1GB) } } catch { }
    $colorOk = if($hasGit) { $Gn } else { $Rd }
    Write-Host "  Git    " -NoNewline -F $Dg; Write-Host $(if($hasGit){"found"}else{"missing"}) -F $colorOk
    $colorOk = if($hasPy) { $Gn } else { $Rd }
    Write-Host "  Python " -NoNewline -F $Dg; Write-Host $(if($hasPy){$pyVer}else{"missing"}) -F $colorOk
    $colorOk = if($hasUv) { $Gn } else { $Rd }
    Write-Host "  uv     " -NoNewline -F $Dg; Write-Host $(if($hasUv){"found"}else{"missing"}) -F $colorOk
    $colorOk = if($hasGPU) { $Gn } else { $Dg }
    Write-Host "  GPU    " -NoNewline -F $Dg; Write-Host $(if($hasGPU){"$gpuName ($vramGB GB)"}else{"CPU only"}) -F $colorOk
    Write-Host "  RAM    " -NoNewline -F $Dg; Write-Host "$ramGB GB" -F $Wh
    Write-Host "`n  [Enter] continue  [Q] quit" -F $Dg; $k = K; if ($k.Key -eq "Q") { exit 0 }; if ($k.Key -eq "Enter") { break }
}

# ================================================================
# PHASE 2: SERVICE SELECTION
# ================================================================
$svc = @{K=$true; L=$true; W=$true}; $cursor = 0
while ($true) {
    Clear-Host; Write-Host "`n  Verity JE Setup - Service Selection`n" -F $Yl
    $items = @(("FastKoko","Text-to-Speech    Kokoro-82M    :8880","K"),("LiteLLM","AI Gateway        100+ LLMs     :4000","L"),("WhisperServer","Speech-to-Text    Whisper       :9000","W"))
    for ($i = 0; $i -lt 3; $i++) {
        $cur = if ($i -eq $cursor) { " >>" } else { "   " }
        $chk = if ($svc[$items[$i][2]]) { "[X]" } else { "[ ]" }
        Write-Host "  $cur $chk " -NoNewline -F $Wh
        Write-Host $items[$i][0].PadRight(15) -NoNewline -F $Wh
        Write-Host $items[$i][1] -F $Dg
    }
    Write-Host "`n  [Up/Down] move  [Space] toggle  [Enter] confirm  [B] back  [Q] quit" -F $Dg
    $k = K
    if ($k.Key -eq "Q") { exit 0 }
    if ($k.Key -eq "B") { break }
    if ($k.Key -eq "UpArrow") { $cursor = [Math]::Max(0, $cursor - 1) }
    if ($k.Key -eq "DownArrow") { $cursor = [Math]::Min(2, $cursor + 1) }
    if ($k.Key -eq "Spacebar") { $svc[$items[$cursor][2]] = -not $svc[$items[$cursor][2]] }
    if ($k.Key -eq "Enter") { $any = $svc.K -or $svc.L -or $svc.W; if (!$any) { Write-Host "`n  Select at least one service." -F $Rd; Start-Sleep 1 } else { break } }
}

# ================================================================
# PHASE 3: CONFIRM
# ================================================================
while ($true) {
    Clear-Host; Write-Host "`n  Verity JE Setup - Confirm`n" -F $Yl; Write-Host "  Will install:`n" -F $Wh
    if ($svc.K) { Write-Host "    [X] FastKoko        ~1.5 GB  TTS (Kokoro-82M)" -F $Gn }
    if ($svc.L) { Write-Host "    [X] LiteLLM         ~200 MB  AI Gateway" -F $Gn }
    if ($svc.W) { Write-Host "    [X] WhisperServer   ~3 GB    STT (Whisper)" -F $Gn }
    if (!$hasGit) { Write-Host "`n  Git will be installed." -F $Rd }
    if (!$hasUv) { Write-Host "  uv will be installed." -F $Rd }
    Write-Host "`n  Path: $Path" -F $Dg
    Write-Host "`n  [Y] proceed  [B] back  [Q] quit" -F $Dg
    $k = K
    if ($k.Key -eq "Q") { exit 0 }
    if ($k.Key -eq "B") { break }
    if ($k.KeyChar -eq 'y' -or $k.KeyChar -eq 'Y' -or $k.Key -eq "Enter") { break }
}

# ================================================================
# PHASE 4: SYSTEM DEPS
# ================================================================
if (!$hasGit -or !$hasUv) {
    phase "System Dependencies"
    if (!$hasGit) { Write-Host "  Installing Git..." -F $Wh; winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null; if (T git) { Write-Host "  Git installed" -F $Gn } else { Write-Host "  Git FAILED" -F $Rd; Read-Host; exit 1 } }
    if (!$hasUv) { Write-Host "  Installing uv..." -F $Wh; winget install --id AstralSoftware.uv -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null; if (T uv) { Write-Host "  uv installed" -F $Gn } else { Write-Host "  uv FAILED" -F $Rd; Read-Host; exit 1 } }
    Write-Host "`n  Press any key..." -F $Dg; K | Out-Null
}

# ================================================================
# PHASE 5: FASTKOKO
# ================================================================
if ($svc.K) {
    $kDir = Join-Path $Path "Kokoro-FastAPI"
    $kPy = Join-Path $kDir ".venv\Scripts\python.exe"
    $kModel = Join-Path $kDir "api\src\models\v1_0\kokoro-v1_0.pth"
    phase "FastKoko - Kokoro TTS"
    if (Test-Path (Join-Path $kDir "api\src\main.py")) { Write-Host "  Repository  already cloned" -F $Gn }
    else { spin "Cloning Kokoro-FastAPI" { param($P,$S); Set-Location $S; & git clone https://github.com/remsky/Kokoro-FastAPI.git (Join-Path $P "Kokoro-FastAPI") 2>&1 | Out-Null; if (!(Test-Path(Join-Path $P "Kokoro-FastAPI\api\src\main.py"))) { throw "Clone failed" } } }
    if (Test-Path $kPy) { Write-Host "  Environment already exists" -F $Gn }
    else { spin "Creating Python 3.10 environment" { param($P, $S); Set-Location (Join-Path $P "Kokoro-FastAPI"); & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null; if (!(Test-Path ".venv\Scripts\python.exe")) { throw "venv creation failed" } } }
    spin "Installing dependencies (torch + kokoro)" { param($P, $S); Set-Location (Join-Path $P "Kokoro-FastAPI"); $pip = ".venv\Scripts\pip.exe"; & $pip install --upgrade pip -q 2>&1 | Out-Null; & $pip install "cython<3.0" -q 2>&1 | Out-Null; & $pip install -e ".[cpu]" 2>&1 | Out-Null }
    Set-Location $startDir
    if (Test-Path $kModel) { Write-Host "  Model  already downloaded" -F $Gn }
    else { dl "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth" $kModel "Kokoro model (350 MB)" }
    Write-Host "`n  Press any key..." -F $Dg; K | Out-Null
}

# ================================================================
# PHASE 6: LITELLM
# ================================================================
if ($svc.L) {
    phase "LiteLLM - AI Gateway"
    if (T litellm) { $v = & litellm --version 2>&1; Write-Host "  LiteLLM  $v" -F $Gn }
    else { spin "Installing LiteLLM" { param($P,$S); uv tool install "litellm[proxy]" 2>&1 | Out-Null }; if (T litellm) { Write-Host "  LiteLLM  installed" -F $Gn } else { Write-Host "  LiteLLM  FAILED" -F $Rd } }
    $ub = "$env:USERPROFILE\.local\bin"; if ((Test-Path $ub) -and ($env:Path -notlike "*$ub*")) { $env:Path += ";$ub" }
    if (T ollama) { Write-Host "  Ollama  already installed" -F $Gn }
    else {
        Write-Host "`n  Ollama runs LLMs locally (private, offline)." -F $Wh
        Write-Host "  [Y] install  [N] skip" -F $Dg; $k = K
        if ($k.KeyChar -eq 'y') {
            $tmp = Join-Path $env:TEMP "OllamaSetup.exe"
            dl "https://ollama.com/download/ollama-windows-amd64.exe" $tmp "Ollama"
            if (Test-Path $tmp) { Start-Process -FilePath $tmp -Arg "/S" -Wait -EA SilentlyContinue; Remove-Item $tmp -EA SilentlyContinue; $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User") }
            if (T ollama) { Write-Host "  Ollama  installed" -F $Gn } else { Write-Host "  Ollama  restart terminal to use" -F $Dg }
        } else { Write-Host "  Ollama  skipped" -F $Dg }
    }
    if (T ollama) {
        Write-Host "`n  Pull a model? (e.g. llama3.2, gemma) Enter = skip" -F $Wh
        Write-Host "  > " -NoNewline -F $Dg; $m = Read-Host
        if ($m) { spin "Pulling $m" { param($P,$S); & ollama pull $args[0] 2>&1 | Out-Null } -ArgumentList $m | Out-Null; Write-Host "  Model $m pulled" -F $Gn }
    }
    Write-Host "`n  Press any key..." -F $Dg; K | Out-Null
}

# ================================================================
# PHASE 7: WHISPER
# ================================================================
if ($svc.W) {
    $wDir = Join-Path $Path "WhisperServer"; $wPy = Join-Path $wDir ".venv\Scripts\python.exe"; New-Item -ItemType Dir -Path $wDir -Force | Out-Null
    $wModel = "base"; if ($hasGPU -and $vramGB -ge 6) { $wModel = "large-v3-turbo" } elseif ($hasGPU -and $vramGB -ge 4) { $wModel = "medium" } elseif ($hasGPU) { $wModel = "base" } elseif ($ramGB -lt 16) { $wModel = "tiny" }
    phase "WhisperServer - STT ($wModel)"
    if (Test-Path $wPy) { Write-Host "  Environment already exists" -F $Gn }
    else { spin "Creating Python 3.10 environment" { param($P,$S); Set-Location (Join-Path $P "WhisperServer"); & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null; if (!(Test-Path ".venv\Scripts\python.exe")) { throw "venv creation failed" } } }
    $wPip = Join-Path $wDir ".venv\Scripts\pip.exe"
    $env:GPU = if ($hasGPU) { "1" } else { "0" }
    spin "Installing dependencies (whisper + torch)" { param($P,$S); Set-Location (Join-Path $P "WhisperServer"); $pip = ".venv\Scripts\pip.exe"; & $pip install --upgrade pip -q 2>&1 | Out-Null; & $pip install "openai-whisper>=1.1.10" "uvicorn[standard]" "fastapi" "pydantic" "python-multipart" "mutagen" -q 2>&1 | Out-Null; if ((Get-Item env:GPU -EA SilentlyContinue).Value -eq "1") { & $pip uninstall torch -y -q 2>&1 | Out-Null; & $pip install torch --index-url https://download.pytorch.org/whl/cu128 --timeout 600 -q 2>&1 | Out-Null } }
    $wFix = Join-Path $wDir ".venv\Lib\site-packages\whisper.py"
    if (Test-Path $wFix) { $Yl = Get-Content $wFix -Raw; if ($Yl -notmatch "msvcrt") { $Yl = $Yl -replace "libc_name = ctypes.util.find_library\('c'\)", 'libc_name = "msvcrt.dll"'; $Yl | Set-Content $wFix -Enc UTF8 } }
    $dev = if ($hasGPU) { "cuda" } else { "cpu" }
    spin "Downloading Whisper model ($wModel, $dev)" { param($P,$S); Set-Location (Join-Path $P "WhisperServer"); $Rd = & ".venv\Scripts\python.exe" -c "import whisper; whisper.load_model('$($args[0])',device='$($args[1])');print('OK')" 2>&1; if ($Rd -notmatch "OK") { throw $Rd } } -ArgumentList $wModel, $dev
    Set-Location $startDir
    Write-Host "`n  Press any key..." -F $Dg; K | Out-Null
}

# ================================================================
# PHASE 8: SCRIPTS + DONE
# ================================================================
phase "Generating Launcher Scripts"
Write-Host "  Creating .bat and .ps1 files..." -F $Wh
. "$PSScriptRoot\_generate_scripts.ps1" -VerityTMPath $Path -WhisperModel $wModel
Write-Host "  Scripts generated" -F $Gn
Write-Host "`n  Press any key..." -F $Dg; K | Out-Null

Clear-Host; Write-Host "`n  Verity JE Setup - Complete!`n" -F $Yl
Write-Host "  Location: $Path`n" -F $Dg
if ($svc.K) { Write-Host "  FastKoko (TTS) -> http://127.0.0.1:8880/v1/   FastKoko.bat" -F $Gn }
if ($svc.L) { Write-Host "  LiteLLM (AI)  -> http://127.0.0.1:4000/v1/   LiteLLM.bat" -F $Gn }
if ($svc.W) { Write-Host "  Whisper (STT) -> http://127.0.0.1:9000/v1/   WhisperServer.bat ($wModel)" -F $Gn }
Write-Host "`n  [Y] Launch Manager  [N] Exit" -F $Dg; $k = K
if ($k.KeyChar -eq 'y' -or $k.KeyChar -eq 'Y') { Start-Process powershell -Arg "-NoExit","-EP","Bypass","-File",(Join-Path $Path "Manager.bat") }
else { Write-Host "`n  To start later: cd `"$Path`" ; .\Manager.bat" -F $Dg }
Write-Host "`n  Press any key." -F $Dg; K | Out-Null

