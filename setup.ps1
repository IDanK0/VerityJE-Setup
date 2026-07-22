<# Verity JE Setup - AI Backend Installer #>
[CmdletBinding()] param([string]$Path)
Clear-Host
if (-not $Path) { $Path = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ErrorActionPreference = "Continue"

$AppTitle = "Verity JE Setup"
$C = "Yellow"  # user requested #e9de17 - Yellow is closest

function Header { param([string]$t)
    Clear-Host
    Write-Host "`n  Verity JE" -ForegroundColor $C
    Write-Host "  $t" -ForegroundColor White
    Write-Host ""
}
function Sub { if ($args.Count) { Write-Host "  $($args[0])" -ForegroundColor DarkGray } }
function S { param($n,$total,$msg)
    Write-Host "  [$n/$total] $msg" -NoNewline -ForegroundColor $C
}
function OK { Write-Host " -> OK" -ForegroundColor Green }
function SKIP { Write-Host " -> skip" -ForegroundColor DarkGray; if ($args.Count) { Write-Host "    $($args[0])" -ForegroundColor DarkGray } }
function ERR { Write-Host " -> FAIL" -ForegroundColor Red; if ($args.Count) { Write-Host "    $($args[0])" -ForegroundColor Red } }
function I { Write-Host "       $($args[0])" -ForegroundColor DarkGray }
function T { try { Get-Command $args[0] -EA Stop; return $true } catch { return $false } }

function Download {
    param($url,$out)
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $out)
    return (Test-Path $out) -and (Get-Item $out).Length -gt 0
}

function Press { Write-Host "`n  [Enter] continue  [B] back  [Q] quit" -F DarkGray; $k = [Console]::ReadKey($true).KeyChar.ToString().ToUpper(); if ($k -eq "Q") { Write-Host "`n  Aborted." -F Red; exit 0 }; if ($k -eq "B") { return $false }; return $true }

# === DETECT ===
Header "System Detection"

$hasGit = T git; $hasPy = T python; if ($hasPy) { $pyVer = & python --version 2>&1 }; $hasUv = T uv

$hasGPU = $false; $vramGB = 0; $gpuName = ""
try { $vg = Get-CimInstance Win32_VideoController -EA SilentlyContinue; if ($vg) { foreach ($g in $vg) { if ($g.Name -match "NVIDIA|GeForce") { $hasGPU = $true; $gpuName = $g.Name; $raw = [double]$g.AdapterRAM; if ($raw -gt 2147483648) { $vramGB = [math]::Round($raw/1GB) } else { $vramGB = [math]::Floor($raw/1GB) }; break } } } } catch { }
if ($hasGPU) { try { $nv = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1; if ($nv -match '(\d+)') { $vramGB = [math]::Floor([int]$Matches[1]/1024) } } catch { } }

$hasAMD = $false
try { $vg = Get-CimInstance Win32_VideoController -EA SilentlyContinue; if ($vg) { foreach ($g in $vg) { if ($g.Name -match "AMD|Radeon" -and $g.Name -notmatch "Integrated") { $hasAMD = $true; break } } } } catch { }

$ramGB = 0
try { $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue; if ($cs) { $ramGB = [math]::Floor($cs.TotalPhysicalMemory/1GB) } } catch { }

Write-Host "  Git     " -F DarkGray -NoNewline; Write-Host $(if($hasGit){"found"}else{"missing"}) -F $(if($hasGit){"Green"}else{"Red"})
Write-Host "  Python  " -F DarkGray -NoNewline; Write-Host $(if($hasPy){$pyVer}else{"missing"}) -F $(if($hasPy){"Green"}else{"Red"})
Write-Host "  uv      " -F DarkGray -NoNewline; Write-Host $(if($hasUv){"found"}else{"missing"}) -F $(if($hasUv){"Green"}else{"Red"})
Write-Host "  GPU     " -F DarkGray -NoNewline
if ($hasGPU) { Write-Host "$gpuName ($vramGB GB)" -F Green }
elseif ($hasAMD) { Write-Host "AMD (CPU)" -F Yellow }
else { Write-Host "CPU only" -F Yellow }
Write-Host "  RAM     " -F DarkGray -NoNewline; Write-Host "$ramGB GB" -F White

$drv = (Split-Path -Qualifier $Path).TrimEnd(':'); if (!$drv) { $drv = "C" }
try { $freeGB = [math]::Floor((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${drv}:'" -EA Stop).FreeSpace/1GB) } catch { $freeGB = 0 }
Write-Host "  Disk    " -F DarkGray -NoNewline; Write-Host "$freeGB GB (${drv}:)" -F White
if ($freeGB -gt 0 -and $freeGB -lt 15) { I "Warning: less than 15 GB free" }
if (-not (Press)) { exit 0 }

# === SERVICES ===
$svc = @{K=$true;L=$true;W=$true}
while ($true) {
    Header "Service Selection"
    Write-Host "  [1] FastKoko       Text-to-Speech    Kokoro-82M  :8880  " -F White -NoNewline
    Write-Host $(if($svc.K){"ON"}else{"OFF"}) -F $(if($svc.K){"Green"}else{"DarkGray"})
    Write-Host "  [2] LiteLLM        AI Gateway        100+ LLMs   :4000  " -F White -NoNewline
    Write-Host $(if($svc.L){"ON"}else{"OFF"}) -F $(if($svc.L){"Green"}else{"DarkGray"})
    Write-Host "  [3] WhisperServer  Speech-to-Text    Whisper     :9000  " -F White -NoNewline
    Write-Host $(if($svc.W){"ON"}else{"OFF"}) -F $(if($svc.W){"Green"}else{"DarkGray"})
    Write-Host "`n  Press 1/2/3 to toggle  |  Enter to confirm  |  B back  |  Q quit" -F DarkGray
    $k = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
    if ($k -eq "Q") { exit 0 }
    if ($k -eq "B") { return }
    if ($k -eq "1") { $svc.K = -not $svc.K }
    if ($k -eq "2") { $svc.L = -not $svc.L }
    if ($k -eq "3") { $svc.W = -not $svc.W }
    if ($k -eq "`r" -or $k -eq "`n") { break }
}

$any = $svc.K -or $svc.L -or $svc.W
if (-not $any) { Write-Host "`n  No services selected." -F Red; Start-Sleep 1; exit 1 }

Write-Host "`n  Installing:" -F $C
if ($svc.K) { Write-Host "    + FastKoko (TTS)" -F White }
if ($svc.L) { Write-Host "    + LiteLLM (AI)" -F White }
if ($svc.W) { Write-Host "    + WhisperServer (STT)" -F White }
if (-not (Press)) { exit 0 }

# === SYSTEM DEPS ===
Header "System Dependencies"
S 1 2 "Git"; if ($hasGit) { OK } else { SKIP; I "winget install Git.Git" }
S 2 2 "Setup directory"; try { New-Item -ItemType Dir -Path $Path -Force | Out-Null; OK } catch { ERR $_.Exception.Message; Read-Host; exit 1 }
if (-not (Press)) { exit 0 }

# === FASTKOKO ===
if ($svc.K) {
    $kDir = Join-Path $Path "Kokoro-FastAPI"
    $kPy = Join-Path $kDir ".venv\Scripts\python.exe"
    $kModel = Join-Path $kDir "api\src\models\v1_0\kokoro-v1_0.pth"
    $total = 5; $n = 0

    Header "FastKoko - Kokoro TTS"
    S (++$n) $total "Clone repository"
    if (Test-Path (Join-Path $kDir "api\src\main.py")) { OK; I "already cloned" }
    else {
        $prevEA = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & git clone https://github.com/remsky/Kokoro-FastAPI.git $kDir 2>&1 | Out-Null
        $ErrorActionPreference = $prevEA
        if (Test-Path (Join-Path $kDir "api\src\main.py")) { OK } else { ERR "clone failed"; Read-Host; exit 1 }
    }

    S (++$n) $total "Python 3.10 virtual environment"
    if (Test-Path $kPy) { OK; I "already exists" }
    else {
        $prev = Get-Location; Set-Location $kDir
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $prev
        if (Test-Path $kPy) { OK } else { ERR "venv failed"; Read-Host; exit 1 }
    }

    S (++$n) $total "Install Python packages"
    $kPip = Join-Path $kDir ".venv\Scripts\pip.exe"
    if (Test-Path $kPip) {
        $prev = Get-Location; Set-Location $kDir
        I "pip upgrade..."
        & $kPip install --upgrade pip -q 2>&1 | Out-Null
        I "cython..."
        & $kPip install "cython<3.0" -q 2>&1 | Out-Null
        I "torch + kokoro dependencies (this takes a while)..."
        & $kPip install -e ".[cpu]" 2>&1 | Out-Null
        Set-Location $prev
        OK
    } else { ERR "pip missing"; Read-Host; exit 1 }

    S (++$n) $total "Download Kokoro model (350 MB)"
    if (Test-Path $kModel) { OK; I "already downloaded" }
    else {
        I "Downloading from HuggingFace..."
        $ok = Download "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth" $kModel
        if ($ok) { OK } else { SKIP; I "download failed. Try again or download manually" }
    }

    S (++$n) $total "eSpeak NG"
    $esp = "C:\Program Files\eSpeak NG\libespeak-ng.dll"
    if (Test-Path $esp) { OK }
    else {
        SKIP "not found"; I "winget install eSpeak-NG.eSpeak-NG"
    }

    if (-not (Press)) { exit 0 }
}

# === LITELLM ===
if ($svc.L) {
    Header "LiteLLM - AI Gateway"
    S 1 3 "LiteLLM proxy"
    if (T litellm) { $ver = & litellm --version 2>&1; OK; I $ver }
    else {
        I "uv tool install litellm[proxy]..."
        uv tool install "litellm[proxy]" 2>&1 | Out-Null
        if (T litellm) { OK } else { ERR "try: pip install 'litellm[proxy]'" }
    }

    $uvBin = "$env:USERPROFILE\.local\bin"
    if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

    S 2 3 "Ollama (local LLMs)"
    if (T ollama) { OK; I "already installed" }
    else {
        Write-Host "`n  Ollama lets you run LLMs locally (private, no internet)." -F White
        Write-Host "  Install Ollama? [Y/n]" -F Yellow; $b = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
        if ($b -ne "N") {
            $tmp = Join-Path $env:TEMP "OllamaSetup.exe"
            I "Downloading..."
            if (Download "https://ollama.com/download/ollama-windows-amd64.exe" $tmp) {
                I "Installing..."
                Start-Process -FilePath $tmp -ArgumentList "/S" -Wait -EA SilentlyContinue
                Remove-Item $tmp -EA SilentlyContinue
                $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
                if (T ollama) { OK } else { SKIP "restart terminal to use ollama" }
            } else { SKIP "download failed" }
        } else { SKIP }
    }

    S 3 3 "Ollama model"
    if (T ollama) {
        $m = Read-Host "`n  Pull a model? (e.g. llama3.2, gemma, mistral) or Enter"
        if ($m) { I "ollama pull $m..."; & ollama pull $m 2>&1 | Out-Null; OK } else { SKIP }
    } else { SKIP "ollama not installed" }

    if (-not (Press)) { exit 0 }
}

# === WHISPER ===
if ($svc.W) {
    $wDir = Join-Path $Path "WhisperServer"
    $wPy = Join-Path $wDir ".venv\Scripts\python.exe"
    New-Item -ItemType Dir -Path (Join-Path $wDir ".venv\Scripts") -Force | Out-Null
    New-Item -ItemType Dir -Path $wDir -Force | Out-Null

    $wModel = "base"
    if ($hasGPU -and $vramGB -ge 6) { $wModel = "large-v3-turbo" }
    elseif ($hasGPU -and $vramGB -ge 4) { $wModel = "medium" }
    elseif ($hasGPU) { $wModel = "base" }
    elseif ($ramGB -lt 16) { $wModel = "tiny" }

    $total = 4; $n = 0
    Header "WhisperServer - STT ($wModel)"

    S (++$n) $total "Python 3.10 virtual environment"
    if (Test-Path $wPy) { OK; I "already exists" }
    else {
        $prev = Get-Location
        if (Test-Path $wDir) { Set-Location $wDir } else { ERR "no such directory: $wDir"; Read-Host; exit 1 }
        I "uv venv .venv --python 3.10 --seed"
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $prev
        if (Test-Path $wPy) { OK } else { ERR "venv failed. Check: is uv installed? uv venv .venv --python 3.10 --seed"; Read-Host; exit 1 }
    }

    S (++$n) $total "Install Python packages"
    $wPip = Join-Path $wDir ".venv\Scripts\pip.exe"
    if (Test-Path $wPip) {
        I "pip install openai-whisper uvicorn fastapi..."
        & $wPip install --upgrade pip -q 2>&1 | Out-Null
        & $wPip install "openai-whisper>=1.1.10" "uvicorn[standard]" "fastapi" "pydantic" "python-multipart" "mutagen" -q 2>&1 | Out-Null
        if ($hasGPU) {
            I "GPU detected: installing CUDA torch..."
            & $wPip uninstall torch -y -q 2>&1 | Out-Null
            & $wPip install torch --index-url https://download.pytorch.org/whl/cu128 --timeout 600 -q 2>&1 | Out-Null
        }
        OK
    } else { ERR "pip missing"; Read-Host; exit 1 }

    S (++$n) $total "Windows compatibility fix"
    $wFix = Join-Path $wDir ".venv\Lib\site-packages\whisper.py"
    if (Test-Path $wFix) {
        $c = Get-Content $wFix -Raw
        if ($c -notmatch "msvcrt\.dll") {
            $c = $c -replace "libc_name = ctypes.util.find_library\('c'\)", 'libc_name = "msvcrt.dll"'
            $c | Set-Content $wFix -Encoding UTF8
        }
        OK
    } else { SKIP "whisper.py not found yet, will patch on first run" }

    S (++$n) $total "Download Whisper model ($wModel)"
    $dev = if ($hasGPU) { "cuda" } else { "cpu" }
    I "Loading $wModel on $dev (downloads if needed)..."
    $prev = Get-Location
    if (Test-Path $wDir) { Set-Location $wDir }
    $script = "import whisper; m = whisper.load_model('$wModel', device='$dev'); print('OK')"
    $result = & $wPy -c $script 2>&1
    Set-Location $prev
    if ($result -match "OK") { OK } else { ERR "model load failed: $result" }

    if (-not (Press)) { exit 0 }
}

# === SCRIPTS ===
Header "Generating Launcher Scripts"
S 1 1 "Generate all .bat and .ps1 files"
. "$PSScriptRoot\_generate_scripts.ps1" -VerityTMPath $Path -WhisperModel $wModel
OK

# === FINAL ===
Header "Setup Complete!"
Write-Host "  Location: $Path`n" -F White
if ($svc.K) { Write-Host "  FastKoko (TTS)   -> http://127.0.0.1:8880/v1/  | FastKoko.bat" -F Green }
if ($svc.L) { Write-Host "  LiteLLM (AI)     -> http://127.0.0.1:4000/v1/  | LiteLLM.bat" -F Green }
if ($svc.W) { Write-Host "  Whisper (STT)    -> http://127.0.0.1:9000/v1/  | WhisperServer.bat ($wModel)" -F Green }
Write-Host ""
Write-Host "`n  Launch services now?" -F $C
Write-Host "  [Y] Start Manager.bat     [N] Exit" -F White
$launch = [Console]::ReadKey($true).KeyChar.ToString().ToUpper()
if ($launch -eq "Y") {
    Write-Host "  Starting Manager.bat..." -F $C
    Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Path "Manager.bat")
} else {
    Write-Host "  To start later, run:" -F DarkGray
    Write-Host "    cd `"$Path`"" -F White
    Write-Host "    .\Manager.bat" -F White
}
Write-Host "`n  Done." -F Green
Write-Host "  Press any key to exit..." -F DarkGray
[Console]::ReadKey($true) | Out-Null

