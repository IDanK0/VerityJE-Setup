<#
.SYNOPSIS
    Verity JE Setup - One-click AI backend installer
#>
[CmdletBinding()]
param([string]$Path)

Clear-Host

if (-not $Path) { $Path = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ErrorActionPreference = "Continue"

$V = "Verity JE Setup"
$STEP = 0
$TOTAL = 0

# ============================================================
# UI HELPERS
# ============================================================
function Header {
    param([string]$title, [string]$subtitle)
    Clear-Host
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host ("$([char]0x2588)" * 3) -ForegroundColor Cyan -NoNewline
    Write-Host "  $title" -ForegroundColor White
    if ($subtitle) { Write-Host "      $subtitle" -ForegroundColor DarkGray }
    Write-Host ""
}

function Step {
    param([string]$msg)
    $global:STEP++
    $pct = if ($TOTAL -gt 0) { "$STEP/$TOTAL" } else { "$STEP" }
    Write-Host "  [$pct] " -NoNewline -ForegroundColor Cyan
    Write-Host $msg -NoNewline -ForegroundColor White
}

function Done {
    Write-Host "  done" -ForegroundColor Green
}

function Warn {
    Write-Host "  skip" -ForegroundColor Yellow
    if ($args.Count) { Write-Host "    $($args[0])" -ForegroundColor Yellow }
}

function Fail {
    Write-Host "  FAIL" -ForegroundColor Red
    if ($args.Count) { Write-Host "    $($args[0])" -ForegroundColor Red }
}

function Info {
    Write-Host "       $($args[0])" -ForegroundColor DarkGray
}

function Spinner {
    param($job)
    $chars = @("|", "/", "-", "\")
    $i = 0
    while (-not $job.IsCompleted) {
        Write-Host "`r  [$($chars[$i % 4])] " -NoNewline -ForegroundColor Cyan
        Write-Host $job.Name -NoNewline -ForegroundColor White
        Start-Sleep -Milliseconds 200
        $i++
    }
    Write-Host "`r  " -NoNewline
}

function Test-Cmd { param($n); try { Get-Command $n -ErrorAction Stop; return $true } catch { return $false } }

function DownloadWithRetry {
    param($url, $out, $max = 3)
    for ($i = 1; $i -le $max; $i++) {
        if ($i -gt 1) { Info "Retry $i/$max..." }
        try {
            $p = Start-Process powershell -ArgumentList "-NoProfile", "-Command", "Invoke-WebRequest -Uri '$url' -OutFile '$out' -TimeoutSec 300" -PassThru -Wait -WindowStyle Hidden
            if ((Test-Path $out) -and (Get-Item $out).Length -gt 0) { return $true }
        } catch { }
    }
    return $false
}

function InstallWinget {
    param($id, $name)
    $a = Read-Host "  Install $name? [Y/n]"
    if ($a -eq "n") { return $false }
    winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    return $?
}

# ============================================================
# PHASE 1: SYSTEM DETECTION
# ============================================================
Header "$V" "System Detection"
Write-Host ""

$hasGit = Test-Cmd git
$hasPython = Test-Cmd python
if ($hasPython) { $pyVer = & python --version 2>&1 } else { $pyVer = "n/a" }
$hasUv = Test-Cmd uv

$hasNvidia = $false; $vram = 0; $gpuName = ""
try { $vga = Get-CimInstance Win32_VideoController -EA SilentlyContinue; if ($vga) { foreach ($g in $vga) { if ($g.Name -match "nvidia|NVIDIA|GeForce") { $hasNvidia = $true; $gpuName = $g.Name; if ($g.AdapterRAM -gt 0) { $v = [double]$g.AdapterRAM; $vram = if ($v -gt 2147483648) { [math]::Round($v/1GB) } else { [math]::Floor($v/1GB) } } break } } } } catch { }
if ($hasNvidia) { try { $nv = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1; if ($nv -match '(\d+)') { $vram = [math]::Floor([int]$Matches[1]/1024) } } catch { } }

$hasAMD = $false
try { $vga = Get-CimInstance Win32_VideoController -EA SilentlyContinue; if ($vga) { foreach ($g in $vga) { if ($g.Name -match "amd|AMD|Radeon" -and $g.Name -notmatch "Integrated") { $hasAMD = $true; break } } } } catch { }

$ram = 0
try { $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue; if ($cs) { $ram = [math]::Floor($cs.TotalPhysicalMemory/1GB) } } catch { }

$drv = (Split-Path -Qualifier $Path).TrimEnd(':')
if (!$drv) { $drv = "C" }
$free = 0
try { $d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${drv}:'" -EA SilentlyContinue; $free = [math]::Floor($d.FreeSpace/1GB) } catch { }

Write-Host "  Git      " -NoNewline -F DarkGray; Write-Host $(if($hasGit){"found"}else{"missing"}) -F $(if($hasGit){"Green"}else{"Red"})
Write-Host "  Python   " -NoNewline -F DarkGray; Write-Host $(if($hasPython){$pyVer}else{"missing"}) -F $(if($hasPython){"Green"}else{"Red"})
Write-Host "  uv       " -NoNewline -F DarkGray; Write-Host $(if($hasUv){"found"}else{"missing"}) -F $(if($hasUv){"Green"}else{"Red"})
Write-Host "  GPU      " -NoNewline -F DarkGray
if ($hasNvidia) { Write-Host "$gpuName ($vram GB)" -F Green }
elseif ($hasAMD) { Write-Host "AMD (CPU inference)" -F Yellow }
else { Write-Host "CPU only" -F Yellow }
Write-Host "  RAM      " -NoNewline -F DarkGray; Write-Host "${ram} GB" -F White
Write-Host "  Disk     " -NoNewline -F DarkGray; Write-Host "${free} GB free ($drv`:\\)" -F White

if ($free -lt 15 -and $free -gt 0) { Write-Host "`n  [!] Less than 15 GB free. Models may not fit." -F Yellow }
if ($free -eq 0) { Write-Host "`n  [!] Could not check disk space." -F Yellow }

Write-Host ""
Write-Host "  Press Enter to continue..." -F Cyan
Read-Host | Out-Null

# ============================================================
# PHASE 2: SERVICE SELECTION
# ============================================================
Header "$V" "Service Selection"
Write-Host ""
Write-Host "  [1] FastKoko       Text-to-Speech     Kokoro-82M    Port 8880" -F White
Write-Host "  [2] LiteLLM        AI Gateway         100+ LLMs    Port 4000" -F White
Write-Host "  [3] WhisperServer  Speech-to-Text     Whisper      Port 9000" -F White
Write-Host ""
Write-Host "  Ollama is offered after LiteLLM installation." -F DarkGray
Write-Host ""
Write-Host "  Enter = all | e.g. 1,2,3 or 1-3" -F Cyan
$ans = Read-Host "  Choice"

$svc = @{}
if ($ans -eq "" -or $ans -match "1") { $svc.FastKoko = $true }
if ($ans -eq "" -or $ans -match "2") { $svc.LiteLLM = $true }
if ($ans -eq "" -or $ans -match "3") { $svc.Whisper = $true }
if ($svc.Count -eq 0) { Write-Host "  No services selected." -F Red; exit 1 }

Write-Host ""; Write-Host "  Selected:" -F Green
foreach ($s in $svc.Keys) { Write-Host "    + $s" -F White }
Write-Host ""
Write-Host "  Press Enter to start installation..." -F Cyan
Read-Host | Out-Null

$TOTAL = ($svc.Keys).Count + 2
$STEP = 0

# ============================================================
# PHASE 3: SYSTEM DEPS
# ============================================================
Header "$V" "System Dependencies ($($STEP+1)/$TOTAL)"
Write-Host ""

Step "Git"; if ($hasGit) { Done } else { Warn "not found. Install manually: winget install Git.Git" }
Step "uv";  if ($hasUv) { Done } else { Warn "not found. Install manually: winget install AstralSoftware.uv" }
Step "Directory"; try { New-Item -ItemType Directory -Path $Path -Force | Out-Null; Done } catch { Fail "cannot create $Path" }
Write-Host ""

# ============================================================
# PHASE 4: FASTKOKO
# ============================================================
if ($svc.FastKoko) {
    Header "$V" "FastKoko - Kokoro TTS ($($STEP+1)/$TOTAL)"
    Write-Host ""

    $kDir = Join-Path $Path "Kokoro-FastAPI"
    $kVenvPy = Join-Path $kDir ".venv\Scripts\python.exe"
    $kModel = Join-Path $kDir "api\src\models\v1_0\kokoro-v1_0.pth"

    Step "Clone Kokoro-FastAPI"
    if (Test-Path (Join-Path $kDir "api\src\main.py")) { Done; Info "already exists" }
    else {
        $prevEA = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & git clone https://github.com/remsky/Kokoro-FastAPI.git $kDir 2>&1 | Out-Null
        $ErrorActionPreference = $prevEA
        if (Test-Path (Join-Path $kDir "api\src\main.py")) { Done } else { Fail; exit 1 }
    }

    Step "Virtual environment (Python 3.10)"
    if (Test-Path $kVenvPy) { Done; Info "already exists" }
    else {
        $prev = Get-Location; Set-Location $kDir
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $prev
        if (Test-Path $kVenvPy) { Done } else { Fail; exit 1 }
    }

    Step "Install dependencies"
    $kPip = Join-Path $kDir ".venv\Scripts\pip.exe"
    if (Test-Path $kPip) {
        $prev = Get-Location; Set-Location $kDir
        & $kPip install --upgrade pip -q 2>&1 | Out-Null
        & $kPip install "cython<3.0" -q 2>&1 | Out-Null
        & $kPip install -e ".[cpu]" 2>&1 | Out-Null
        Set-Location $prev
        Done
    } else { Fail; exit 1 }

    Step "Download Kokoro model (~350 MB)"
    if (Test-Path $kModel) { Done; Info "already exists" }
    else {
        try {
            Invoke-WebRequest -Uri "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth" -OutFile $kModel -TimeoutSec 600 -EA Stop
            Done
        } catch { Warn "download failed"; Info "try again or download manually from HuggingFace" }
    }

    Step "eSpeak NG"
    $espeak = "C:\Program Files\eSpeak NG\libespeak-ng.dll"
    if (Test-Path $espeak) { Done }
    else { Warn "not found"; $a = Read-Host "  Install? [Y/n]"; if ($a -ne "n") { InstallWinget "eSpeak-NG.eSpeak-NG" "eSpeak NG" | Out-Null } }

    Write-Host ""; Write-Host "  FastKoko ready!" -F Green
    Write-Host ""; Write-Host "  Press Enter to continue..." -F Cyan; Read-Host | Out-Null
}

# ============================================================
# PHASE 5: LITELLM
# ============================================================
if ($svc.LiteLLM) {
    Header "$V" "LiteLLM - AI Gateway ($($STEP+1)/$TOTAL)"
    Write-Host ""

    Step "LiteLLM"
    if (Test-Cmd litellm) { $ver = & litellm --version 2>&1; Done; Info $ver }
    else {
        uv tool install "litellm[proxy]" 2>&1 | Out-Null
        if (Test-Cmd litellm) { Done }
        else { Warn "install failed"; Info "pip install 'litellm[proxy]'" }
    }

    $uvBin = "$env:USERPROFILE\.local\bin"
    if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

    Step "Ollama"
    if (Test-Cmd ollama) { Done; Info "already installed" }
    else {
        Write-Host ""
        Write-Host "  Ollama lets you run LLMs locally (offline, private)." -F White
        Write-Host "  Recommended if you want Verity to work without internet." -F DarkGray
        Write-Host ""
        $a = Read-Host "  Install Ollama? [Y/n]"
        if ($a -ne "n") {
            $tmp = Join-Path $env:TEMP "OllamaSetup.exe"
            if (DownloadWithRetry "https://ollama.com/download/ollama-windows-amd64.exe" $tmp) {
                Start-Process -FilePath $tmp -ArgumentList "/S" -Wait -EA SilentlyContinue
                Remove-Item $tmp -EA SilentlyContinue
                $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
                if (Test-Cmd ollama) { Done; Info "installed" } else { Warn "installed, restart terminal" }
            } else { Warn "download failed" }
        } else { Warn "skipped" }
    }

    if (Test-Cmd ollama) {
        Step "Ollama model"
        Write-Host ""
        $m = Read-Host "  Pull a model? (e.g. llama3.2, gemma, mistral) or Enter to skip"
        if ($m) { & ollama pull $m 2>&1 | Out-Null; Done; Info $m }
        else { Warn "skipped" }
    }

    Write-Host ""; Write-Host "  LiteLLM ready!" -F Green
    Write-Host ""; Write-Host "  Press Enter to continue..." -F Cyan; Read-Host | Out-Null
}

# ============================================================
# PHASE 6: WHISPER SERVER
# ============================================================
if ($svc.Whisper) {
    Header "$V" "WhisperServer - STT ($($STEP+1)/$TOTAL)"
    Write-Host ""

    $wDir = Join-Path $Path "WhisperServer"
    $wVenvPy = Join-Path $wDir ".venv\Scripts\python.exe"
    New-Item -ItemType Directory -Path (Join-Path $wDir ".venv\Scripts") -Force | Out-Null

    Step "Virtual environment (Python 3.10)"
    if (Test-Path $wVenvPy) { Done; Info "already exists" }
    else {
        $prev = Get-Location; Set-Location $wDir
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $prev
        if (Test-Path $wVenvPy) { Done } else { Fail; exit 1 }
    }

    $wModel = "base"
    if ($hasNvidia -and $vram -ge 6) { $wModel = "large-v3-turbo" }
    elseif ($hasNvidia -and $vram -ge 4) { $wModel = "medium" }
    elseif ($hasNvidia) { $wModel = "base" }
    elseif ($ram -ge 16) { $wModel = "base" }
    else { $wModel = "tiny" }
    Info "Model: $wModel"

    Step "Install dependencies"
    $wPip = Join-Path $wDir ".venv\Scripts\pip.exe"
    if (Test-Path $wPip) {
        & $wPip install --upgrade pip -q 2>&1 | Out-Null
        & $wPip install "openai-whisper>=1.1.10" "uvicorn[standard]" "fastapi" "pydantic" "python-multipart" "mutagen" -q 2>&1 | Out-Null
        if ($hasNvidia) { & $wPip uninstall torch -y -q 2>&1 | Out-Null; & $wPip install torch --index-url https://download.pytorch.org/whl/cu128 --timeout 600 -q 2>&1 | Out-Null }
        Done
    } else { Fail; exit 1 }

    Step "Windows compatibility"
    $wPy = Join-Path $wDir ".venv\Lib\site-packages\whisper.py"
    if (Test-Path $wPy) {
        $c = Get-Content $wPy -Raw
        if ($c -notmatch "msvcrt.dll") {
            $c = $c -replace "libc_name = ctypes.util.find_library\('c'\)", 'libc_name = "msvcrt.dll"'
            $c | Set-Content $wPy -Encoding UTF8
        }
        Done
    } else { Warn }

    Step "Download Whisper model ($wModel)"
    $prev = Get-Location; Set-Location $wDir
    $dev = if ($hasNvidia) { "cuda" } else { "cpu" }
    & $wVenvPy -c "import whisper; whisper.load_model('$wModel', device='$dev')" 2>&1 | Out-Null
    Set-Location $prev
    Done

    Write-Host ""; Write-Host "  WhisperServer ready!" -F Green
    Write-Host ""; Write-Host "  Press Enter to continue..." -F Cyan; Read-Host | Out-Null
}

# ============================================================
# PHASE 7: GENERATE SCRIPTS
# ============================================================
Header "$V" "Generating Scripts ($($STEP+1)/$TOTAL)"
Write-Host ""
Step "Generate launcher scripts"
. "$PSScriptRoot\_generate_scripts.ps1" -VerityTMPath $Path -WhisperModel $wModel
Done
Write-Host ""; Write-Host "  Press Enter to continue..." -F Cyan; Read-Host | Out-Null

# ============================================================
# PHASE 8: DONE
# ============================================================
Header "$V" "Setup Complete!"
Write-Host ""
Write-Host "  Location: $Path" -F White
Write-Host ""

if ($svc.FastKoko) { Write-Host "  FastKoko   -> http://127.0.0.1:8880/v1/  | FastKoko.bat" -F Green }
if ($svc.LiteLLM) { Write-Host "  LiteLLM    -> http://127.0.0.1:4000/v1/  | LiteLLM.bat" -F Green }
if ($svc.Whisper) {
    Write-Host "  Whisper    -> http://127.0.0.1:9000/v1/  | WhisperServer.bat" -F Green
    Write-Host "    Model: $wModel" -F DarkGray
}
Write-Host ""
Write-Host "  Manager.bat controls all services from one window." -F Magenta
Write-Host ""
Write-Host "  Press Enter to exit..." -F Cyan
Read-Host | Out-Null
