<# Verity JE Setup - AI Backend Installer #>
[CmdletBinding()] param([string]$Path)

Clear-Host
if (-not $Path) { $Path = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ErrorActionPreference = "Continue"
$startDir = Get-Location

$APP = "Verity JE Setup"
$FG = "Yellow"; $DG = "DarkGray"; $GR = "Green"; $RD = "Red"; $WH = "White"

function bar { Write-Host "`n  " -NoNewline; Write-Host ("-" * 60) -F $DG }
function keyhint { Write-Host "`n  [Enter] continue  [B] back  [Q] quit" -F $DG }
function ReadKey { [Console]::ReadKey($true) }
function T { param($n); try { Get-Command $n -EA Stop; return $true } catch { return $false } }

# ====================================================================
# PHASE 1: SYSTEM DETECTION
# ====================================================================
while ($true) {
    Clear-Host
    Write-Host "`n  $APP - System Detection`n" -F $FG

    $hasGit = T git; $hasPy = T python
    if ($hasPy) { $pyVer = & python --version 2>&1 }; $hasUv = T uv
    $hasGPU = $false; $vramGB = 0; $gpuName = ""
    try { $vg = Get-CimInstance Win32_VideoController -EA SilentlyContinue; if ($vg) { foreach ($g in $vg) { if ($g.Name -match "NVIDIA|GeForce") { $hasGPU = $true; $gpuName = $g.Name; break } } } } catch { }
    if ($hasGPU) { try { $nv = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1; if ($nv -match '(\d+)') { $vramGB = [math]::Floor([int]$Matches[1]/1024) } } catch { if ($vramGB -lt 1) { $vramGB = 4 } } }
    $ramGB = 0; try { $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue; if ($cs) { $ramGB = [math]::Floor($cs.TotalPhysicalMemory/1GB) } } catch { }

    Write-Host "  Git     " -F $DG -NoNewline; Write-Host $(if($hasGit){"found"}else{"missing"}) -F $(if($hasGit){$GR}else{$RD})
    Write-Host "  Python  " -F $DG -NoNewline; Write-Host $(if($hasPy){$pyVer}else{"missing"}) -F $(if($hasPy){$GR}else{$RD})
    Write-Host "  uv      " -F $DG -NoNewline; Write-Host $(if($hasUv){"found"}else{"missing"}) -F $(if($hasUv){$GR}else{$RD})
    Write-Host "  GPU     " -F $DG -NoNewline; Write-Host $(if($hasGPU){"$gpuName ($vramGB GB)"}else{"CPU only"}) -F $(if($hasGPU){$GR}else{$RD})
    Write-Host "  RAM     " -F $DG -NoNewline; Write-Host "$ramGB GB" -F $WH

    bar; keyhint
    $ki = ReadKey
    if ($ki.Key -eq "Q") { exit 0 }
    if ($ki.Key -eq "B") { continue }
    if ($ki.Key -eq "Enter") { break }
}

# ====================================================================
# PHASE 2: SERVICE SELECTION
# ====================================================================
$svc = @{K=$true; L=$true; W=$true}
$cursor = 0
while ($true) {
    Clear-Host
    Write-Host "`n  $APP - Service Selection`n" -F $FG

    $items = @(
        @("FastKoko", "Text-to-Speech    Kokoro-82M    :8880", "K"),
        @("LiteLLM", "AI Gateway        100+ LLMs     :4000", "L"),
        @("WhisperServer", "Speech-to-Text    Whisper       :9000", "W")
    )
    for ($i = 0; $i -lt 3; $i++) {
        $cur = if ($i -eq $cursor) { " >>" } else { "   " }
        $chk = if ($svc[$items[$i][2]]) { "[X]" } else { "[ ]" }
        Write-Host "  $cur $chk " -NoNewline -F $WH
        Write-Host $items[$i][0].PadRight(15) -NoNewline -F $WH
        Write-Host $items[$i][1] -F $DG
    }
    Write-Host "`n  [Up/Down] move  [Space] toggle  [Enter] confirm  [B] back  [Q] quit" -F $DG
    $ki = ReadKey
    if ($ki.Key -eq "Q") { exit 0 }
    if ($ki.Key -eq "B") { continue }
    if ($ki.Key -eq "UpArrow") { $cursor = [Math]::Max(0, $cursor - 1) }
    if ($ki.Key -eq "DownArrow") { $cursor = [Math]::Min(2, $cursor + 1) }
    if ($ki.Key -eq "Spacebar") { $svc[$items[$cursor][2]] = -not $svc[$items[$cursor][2]] }
    if ($ki.Key -eq "Enter") { $any = $svc.K -or $svc.L -or $svc.W; if (!$any) { Write-Host "`n  Select at least one." -F $RD; Start-Sleep 1 } else { break } }
}

# ====================================================================
# PHASE 3: CONFIRMATION
# ====================================================================
while ($true) {
    Clear-Host
    Write-Host "`n  $APP - Confirm Installation`n" -F $FG
    Write-Host "  The following will be installed:`n" -F $WH
    if ($svc.K) { Write-Host "    [X] FastKoko        ~1.5 GB  (Kokoro-82M TTS)" -F $GR }
    if ($svc.L) { Write-Host "    [X] LiteLLM         ~200 MB  (AI Gateway)" -F $GR }
    if ($svc.W) { Write-Host "    [X] WhisperServer   ~3 GB    (Speech-to-Text)" -F $GR }

    if (-not $hasGit) { Write-Host "`n  [!] Git is missing. It will be installed." -F $RD }
    if (-not $hasUv) { Write-Host "  [!] uv is missing. It will be installed." -F $RD }

    Write-Host "`n  Installation path: $Path" -F $DG
    Write-Host "`n  [Y] proceed  [B] back  [Q] quit" -F $DG
    $ki = ReadKey
    if ($ki.Key -eq "Q") { exit 0 }
    if ($ki.Key -eq "B") { continue }
    if ($ki.KeyChar -eq 'y' -or $ki.KeyChar -eq 'Y' -or $ki.Key -eq "Enter") { break }
}

# ====================================================================
# INSTALL FUNCTIONS
# ====================================================================
function phase { Clear-Host; Write-Host "`n  $APP - $($args[0])`n" -F $FG }

function download($url,$out,$msg) {
    Write-Host "  $msg" -F $WH
    try {
        $wc = New-Object System.Net.WebClient
        $total = 0
        $wc.DownloadProgressChanged += {
            if ($_.TotalBytesToReceive -gt 0) {
                $pct = [math]::Round($_.BytesReceived / $_.TotalBytesToReceive * 100, 2)
                Write-Host "`r  $msg  $pct%" -NoNewline -F $WH
            }
        }
        $wc.DownloadFile($url, $out)
        Write-Host "`r  $msg  done" -F $GR
        return (Test-Path $out) -and (Get-Item $out).Length -gt 0
    } catch {
        Write-Host "`r  $msg  FAILED" -F $RD
        return $false
    }
}

# ====================================================================
# PHASE 4: SYSTEM DEPS
# ====================================================================
if (-not $hasGit -or -not $hasUv) {
    phase "System Dependencies"
    if (-not $hasGit) {
        Write-Host "  Installing Git..." -F $WH
        winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if (T git) { Write-Host "  Git installed" -F $GR } else { Write-Host "  Git failed" -F $RD; Read-Host; exit 1 }
    }
    if (-not $hasUv) {
        Write-Host "  Installing uv..." -F $WH
        winget install --id AstralSoftware.uv -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if (T uv) { Write-Host "  uv installed" -F $GR } else { Write-Host "  uv failed" -F $RD; Read-Host; exit 1 }
    }
    Write-Host ""; Write-Host "  [Enter] continue" -F $DG; $null = ReadKey
}

# ====================================================================
# PHASE 5: FASTKOKO
# ====================================================================
if ($svc.K) {
    $kDir = Join-Path $Path "Kokoro-FastAPI"
    $kPy = Join-Path $kDir ".venv\Scripts\python.exe"
    $kModel = Join-Path $kDir "api\src\models\v1_0\kokoro-v1_0.pth"

    phase "FastKoko - Kokoro TTS"

    # Clone
    if (Test-Path (Join-Path $kDir "api\src\main.py")) {
        Write-Host "  Repository   already cloned" -F $GR
    } else {
        Write-Host "  Cloning Kokoro-FastAPI..." -F $WH
        $prevEA = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & git clone https://github.com/remsky/Kokoro-FastAPI.git $kDir 2>&1 | Out-Null
        $ErrorActionPreference = $prevEA
        if (Test-Path (Join-Path $kDir "api\src\main.py")) { Write-Host "  Repository   done" -F $GR }
        else { Write-Host "  Repository   FAILED" -F $RD; Read-Host; exit 1 }
    }

    # Venv
    if (Test-Path $kPy) {
        Write-Host "  Environment  already exists" -F $GR
    } else {
        Write-Host "  Creating Python 3.10 environment..." -F $WH
        Set-Location $kDir
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $startDir
        if (Test-Path $kPy) { Write-Host "  Environment  done" -F $GR }
        else { Write-Host "  Environment  FAILED" -F $RD; Read-Host; exit 1 }
    }

    # Dependencies
    $kPip = Join-Path $kDir ".venv\Scripts\pip.exe"
    Write-Host "  Installing dependencies..." -F $WH
    Set-Location $kDir
    & $kPip install --upgrade pip -q 2>&1 | Out-Null
    & $kPip install "cython<3.0" -q 2>&1 | Out-Null
    & $kPip install -e ".[cpu]" 2>&1 | Out-Null
    Set-Location $startDir
    Write-Host "  Dependencies done" -F $GR

    # Model
    if (Test-Path $kModel) {
        Write-Host "  Model        already downloaded" -F $GR
    } else {
        download "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth" $kModel "Downloading Kokoro model (350 MB)"
    }

    Write-Host ""; Write-Host "  [Enter] continue" -F $DG; $null = ReadKey
}

# ====================================================================
# PHASE 6: LITELLM
# ====================================================================
if ($svc.L) {
    phase "LiteLLM - AI Gateway"

    if (T litellm) {
        $ver = & litellm --version 2>&1
        Write-Host "  LiteLLM      $ver" -F $GR
    } else {
        Write-Host "  Installing LiteLLM..." -F $WH
        uv tool install "litellm[proxy]" 2>&1 | Out-Null
        if (T litellm) { Write-Host "  LiteLLM      installed" -F $GR }
        else { Write-Host "  LiteLLM      FAILED" -F $RD }
    }

    $uvBin = "$env:USERPROFILE\.local\bin"
    if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

    if (T ollama) {
        Write-Host "  Ollama       already installed" -F $GR
    } else {
        Write-Host "  Ollama lets you run LLMs locally (private, no internet)." -F $WH
        Write-Host "  [Y] install  [N] skip" -F $DG
        if ($(ReadKey).KeyChar -eq 'y') {
            $tmp = Join-Path $env:TEMP "OllamaSetup.exe"
            download "https://ollama.com/download/ollama-windows-amd64.exe" $tmp "Downloading Ollama"
            Start-Process -FilePath $tmp -ArgumentList "/S" -Wait -EA SilentlyContinue
            Remove-Item $tmp -EA SilentlyContinue
            $env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")
            if (T ollama) { Write-Host "  Ollama       installed" -F $GR } else { Write-Host "  Ollama       restart terminal to use" -F $DG }
        } else { Write-Host "  Ollama       skipped" -F $DG }
    }

    if (T ollama) {
        Write-Host "`n  Pull a model? (e.g. llama3.2, gemma) or Enter to skip:" -F $WH
        Write-Host "  > " -NoNewline -F $DG; $m = Read-Host
        if ($m) { Write-Host "  Pulling $m..." -F $WH; & ollama pull $m 2>&1 | Out-Null; Write-Host "  Model pulled" -F $GR }
    }

    Write-Host ""; Write-Host "  [Enter] continue" -F $DG; $null = ReadKey
}

# ====================================================================
# PHASE 7: WHISPER SERVER
# ====================================================================
if ($svc.W) {
    $wDir = Join-Path $Path "WhisperServer"
    $wPy = Join-Path $wDir ".venv\Scripts\python.exe"
    New-Item -ItemType Directory -Path $wDir -Force | Out-Null

    $wModel = "base"
    if ($hasGPU -and $vramGB -ge 6) { $wModel = "large-v3-turbo" }
    elseif ($hasGPU -and $vramGB -ge 4) { $wModel = "medium" }
    elseif ($hasGPU) { $wModel = "base" }
    elseif ($ramGB -lt 16) { $wModel = "tiny" }

    phase "WhisperServer - STT ($wModel)"

    if (Test-Path $wPy) {
        Write-Host "  Environment  already exists" -F $GR
    } else {
        Write-Host "  Creating Python 3.10 environment..." -F $WH
        Set-Location $wDir
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $startDir
        if (Test-Path $wPy) { Write-Host "  Environment  done" -F $GR }
        else { Write-Host "  Environment  FAILED. uv venv .venv --python 3.10 --seed" -F $RD; Read-Host; exit 1 }
    }

    $wPip = Join-Path $wDir ".venv\Scripts\pip.exe"
    Write-Host "  Installing dependencies..." -F $WH
    & $wPip install --upgrade pip -q 2>&1 | Out-Null
    & $wPip install "openai-whisper>=1.1.10" "uvicorn[standard]" "fastapi" "pydantic" "python-multipart" "mutagen" -q 2>&1 | Out-Null
    if ($hasGPU) { & $wPip uninstall torch -y -q 2>&1 | Out-Null; & $wPip install torch --index-url https://download.pytorch.org/whl/cu128 --timeout 600 -q 2>&1 | Out-Null }
    Write-Host "  Dependencies done" -F $GR

    $wFix = Join-Path $wDir ".venv\Lib\site-packages\whisper.py"
    if (Test-Path $wFix) {
        $c = Get-Content $wFix -Raw
        if ($c -notmatch "msvcrt\.dll") {
            $c = $c -replace "libc_name = ctypes.util.find_library\('c'\)", 'libc_name = "msvcrt.dll"'
            $c | Set-Content $wFix -Encoding UTF8
        }
    }

    $dev = if ($hasGPU) { "cuda" } else { "cpu" }
    Write-Host "  Downloading Whisper model ($wModel, $dev)..." -F $WH
    Set-Location $wDir
    $script = "import whisper; m = whisper.load_model('$wModel', device='$dev'); print('OK')"
    $result = & $wPy -c $script 2>&1
    Set-Location $startDir
    if ($result -match "OK") { Write-Host "  Model        loaded" -F $GR }
    else { Write-Host "  Model        FAILED: $result" -F $RD }

    Write-Host ""; Write-Host "  [Enter] continue" -F $DG; $null = ReadKey
}

# ====================================================================
# PHASE 8: GENERATE SCRIPTS
# ====================================================================
phase "Generating Launcher Scripts"
Write-Host "  Creating .bat and .ps1 files..." -F $WH
. "$PSScriptRoot\_generate_scripts.ps1" -VerityTMPath $Path -WhisperModel $wModel
Write-Host "  Scripts generated" -F $GR

Write-Host ""; Write-Host "  [Enter] continue" -F $DG; $null = ReadKey

# ====================================================================
# PHASE 9: DONE
# ====================================================================
Clear-Host
Write-Host "`n  $APP - Complete!`n" -F $FG
Write-Host "  All services are ready.`n" -F $WH
Write-Host "  Location: $Path" -F $DG
Write-Host ""

if ($svc.K) { Write-Host "  FastKoko (TTS)   -> http://127.0.0.1:8880/v1/   FastKoko.bat" -F $GR }
if ($svc.L) { Write-Host "  LiteLLM (AI)     -> http://127.0.0.1:4000/v1/   LiteLLM.bat" -F $GR }
if ($svc.W) { Write-Host "  Whisper (STT)    -> http://127.0.0.1:9000/v1/   WhisperServer.bat" -F $GR }

Write-Host "`n  [Y] Launch Manager.bat now  [N] Exit" -F $DG
$ki = ReadKey
if ($ki.KeyChar -eq 'y' -or $ki.KeyChar -eq 'Y') {
    Start-Process powershell -ArgumentList "-NoExit","-ExecutionPolicy","Bypass","-File",(Join-Path $Path "Manager.bat")
} else {
    Write-Host "`n  To start later: cd `"$Path`" ; .\Manager.bat" -F $DG
}
Write-Host "`n  Done. Press any key to exit." -F $DG
$null = ReadKey
