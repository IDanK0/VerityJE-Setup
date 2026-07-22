<#
.SYNOPSIS
    VerityTM - Complete Automatic Setup
    Works on any Windows PC with internet connection.
.PARAMETER Path
    Installation path (default: %USERPROFILE%\VerityTM)
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -Path "C:\Tools\VerityTM"
#>
[CmdletBinding()]
param([string]$Path)

if (-not $Path) { $Path = Split-Path -Parent $MyInvocation.MyCommand.Path }
$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

# ============================================================
# COLOR HELPERS
# ============================================================
function W-H {
    param([string]$m)
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  $m" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}
function W-OK { Write-Host " [OK]" -ForegroundColor Green; if ($args.Count) { Write-Host "   $($args[0])" -ForegroundColor Green } }
function W-WARN { Write-Host " [!]" -ForegroundColor Yellow; if ($args.Count) { Write-Host "   $($args[0])" -ForegroundColor Yellow } }
function W-ERR { Write-Host " [X]" -ForegroundColor Red; if ($args.Count) { Write-Host "   $($args[0])" -ForegroundColor Red } }
function W-INFO { if ($args.Count) { Write-Host " [*] $($args[0])" -ForegroundColor White } }
function W-DEBUG { if ($args.Count) { Write-Host "     > $($args[0])" -ForegroundColor DarkGray } }
function W-SPACE { Write-Host "" }
function Test-Cmd { param($n); try { Get-Command $n -ErrorAction Stop; return $true } catch { return $false } }

# ============================================================
# SYSTEM DETECTION
# ============================================================
W-H "VerityTM - Automatic Setup"
W-SPACE
W-INFO "Detecting system..."
W-SPACE

$hasGit = $null; try { $hasGit = (Get-Command git -ErrorAction Stop).Source } catch {}
$hasPython = $null; $pyVer = ""
try { $hasPython = (Get-Command python -ErrorAction Stop).Source; $pyVer = & $hasPython --version 2>&1 } catch {}
$hasUv = $null; try { $hasUv = (Get-Command uv -ErrorAction Stop).Source } catch {}

$hasNvidia = $false; $nvidiaVram = 0; $nvidiaName = ""
try {
    $vga = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if ($vga) {
        foreach ($g in $vga) {
            if ($g.Name -match "nvidia|NVIDIA|GeForce") {
                $hasNvidia = $true
                $nvidiaName = $g.Name
                if ($g.AdapterRAM -gt 0) {
                    $vramBytes = [double]$g.AdapterRAM
                    if ($vramBytes -gt 2147483648) { $nvidiaVram = [math]::Round($vramBytes / 1GB) }
                    else { $nvidiaVram = [math]::Floor($vramBytes / 1GB) }
                }
                break
            }
        }
    }
} catch { }

if ($hasNvidia) {
    try {
        $nvOut = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1
        if ($nvOut -match '(\d+)') { $nvidiaVram = [math]::Floor([int]$Matches[1] / 1024) }
    } catch { }
}

$hasAMD = $false
try {
    $vga = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    if ($vga) { foreach ($g in $vga) { if ($g.Name -match "amd|AMD|Radeon" -and $g.Name -notmatch "Integrated") { $hasAMD = $true; break } } }
} catch { }

$totalRam = 0
try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($cs) { $totalRam = [math]::Floor($cs.TotalPhysicalMemory / 1GB) }
} catch { }

W-SPACE; W-INFO "System detected:"
W-DEBUG "Git:     $(if($hasGit){'Found'}else{'Not found'})"
W-DEBUG "Python:  $(if($hasPython){$pyVer}else{'Not found'})"
W-DEBUG "uv:      $(if($hasUv){'Found'}else{'Not found'})"
W-DEBUG "NVIDIA:  $(if($hasNvidia){"$nvidiaName ($nvidiaVram GB VRAM)"}else{'Not found'})"
W-DEBUG "AMD:     $(if($hasAMD){'Found'}else{'Not found (or integrated only)'})"
W-DEBUG "RAM:     ${totalRam} GB"
W-SPACE

# Disk space check
$driveLetter = (Split-Path -Qualifier $Path).TrimEnd(':')
if (!$driveLetter) { $driveLetter = (Split-Path -Qualifier $env:USERPROFILE).TrimEnd(':') }
try {
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='${driveLetter}:'" -ErrorAction SilentlyContinue
    $freeGB = [math]::Floor($disk.FreeSpace / 1GB)
    W-INFO "Disk ${driveLetter}: ${freeGB} GB free"
    if ($freeGB -lt 15) { W-WARN "Less than 15 GB free. You may run out of space." }
} catch { W-WARN "Could not check disk space" }
W-SPACE

# ============================================================
# SERVICE SELECTION
# ============================================================
W-H "Select Services to Install"
W-SPACE
Write-Host "  1. FastKoko       - Text-to-Speech (Kokoro-82M)" -ForegroundColor White
Write-Host "     Port: 8880     | Model: Kokoro v1.0 (~1 GB)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  2. LiteLLM        - AI Gateway (100+ LLM providers)" -ForegroundColor White
Write-Host "     Port: 4000     | Lightweight (~200 MB)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  3. WhisperServer  - Speech-to-Text (Whisper)" -ForegroundColor White
Write-Host "     Port: 9000     | Model: auto-selected based on hardware" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Note: Ollama (local LLM runner) is always offered after LiteLLM installation" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Press Enter to install all services" -ForegroundColor Yellow
$answer = Read-Host "  Select (e.g. 1,2,3 or 1-3)"

$services = @{}
if ($answer -eq "" -or $answer -match "1") { $services.FastKoko = $true }
if ($answer -eq "" -or $answer -match "2") { $services.LiteLLM = $true }
if ($answer -eq "" -or $answer -match "3") { $services.Whisper = $true }

if ($services.Count -eq 0) { W-ERR "No services selected."; exit 1 }

W-SPACE; W-OK "Selected services:"
foreach ($s in $services.Keys) { W-DEBUG $s }
W-SPACE

# ============================================================
# INSTALL DEPENDENCIES
# ============================================================
W-H "Installing System Dependencies"
W-SPACE

if (!(Test-Cmd git)) {
    $a = Read-Host "Git not found. Install? [Y/n]"
    if ($a -ne "n") {
        W-INFO "Installing Git..."
        winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if (Test-Cmd git) { W-OK "Git installed" } else { W-WARN "Could not install Git. Manual: https://git-scm.com/download/win" }
    }
} else { W-OK "Git found" }

if (!(Test-Cmd uv)) {
    $a = Read-Host "uv not found. Install? [Y/n]"
    if ($a -ne "n") {
        W-INFO "Installing uv..."
        winget install --id AstralSoftware.uv -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if (Test-Cmd uv) { W-OK "uv installed" } else { W-WARN "Could not install uv. Manual: https://docs.astral.sh/uv/" }
    }
} else { W-OK "uv found" }

# ============================================================
# HELPER FUNCTIONS
# ============================================================
function Download-WithRetry {
    param($url, $output, $maxRetries = 3, $timeoutSec = 300)
    for ($i = 1; $i -le $maxRetries; $i++) {
        try {
            W-DEBUG "Downloading (attempt $i/$maxRetries)..."
            Invoke-WebRequest -Uri $url -OutFile $output -TimeoutSec $timeoutSec
            W-DEBUG "Download complete"
            return $true
        } catch {
            W-WARN "Download failed: $_"
            if ($i -lt $maxRetries) { Start-Sleep -Seconds 5 }
        }
    }
    W-WARN "Download failed after $maxRetries attempts"
    return $false
}

function Install-FromWinget {
    param($pkgId, $name)
    $a = Read-Host "Install $name? [Y/n]"
    if ($a -eq "n") { return $false }
    if (Test-Cmd winget) {
        winget install --id $pkgId -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        return $LASTEXITCODE -eq 0
    } else {
        W-ERR "Winget not found. Please install manually."
        return $false
    }
}

# ============================================================
# CREATE DIRECTORY
# ============================================================
W-SPACE
W-INFO "Creating: $Path"
New-Item -ItemType Directory -Path $Path -Force | Out-Null
W-OK "Directory created"
W-SPACE

# ============================================================
# FASTKOKO
# ============================================================
if ($services.FastKoko) {
    W-H "Installing FastKoko (Kokoro TTS)"
    W-SPACE

    $kDir = Join-Path $Path "Kokoro-FastAPI"
    $kVenvPy = Join-Path $kDir ".venv\Scripts\python.exe"

    if (Test-Path (Join-Path $kDir "api\src\main.py")) {
        W-INFO "Kokoro-FastAPI repository already exists"
    } elseif ($hasGit) {
        W-INFO "Cloning Kokoro-FastAPI..."
        $prev = Get-Location
        Set-Location (Split-Path $Path -Parent)
                $prevEA = $ErrorActionPreference; $ErrorActionPreference = "Continue"
        & git clone https://github.com/remsky/Kokoro-FastAPI.git $kDir 2>&1 | Out-Null
        $ErrorActionPreference = $prevEA
        if (-not (Test-Path (Join-Path $kDir "api\src\main.py"))) { throw "Failed to clone Kokoro-FastAPI" }
        Set-Location $prev
        W-OK "Repository cloned"
    } else {
        W-ERR "Git is required to clone Kokoro-FastAPI"
        exit 1
    }

    if (!(Test-Path $kVenvPy)) {
        W-INFO "Creating virtual environment (Python 3.10)..."
        $prev = Get-Location
        Set-Location $kDir
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $prev
        W-OK "Virtual environment created"
    } else {
        W-DEBUG "Virtual environment already exists"
    }

    W-INFO "Installing Kokoro dependencies (this may take a while)..."
    $kPip = Join-Path $kDir ".venv\Scripts\pip.exe"
    if (Test-Path $kPip) {
        $prev = Get-Location
        Set-Location $kDir
        & $kPip install --upgrade pip -q 2>&1 | Out-Null
        & $kPip install "cython<3.0" -q 2>&1 | Out-Null
        & $kPip install -e ".[cpu]" 2>&1 | Out-Null
        Set-Location $prev
        W-OK "Dependencies installed"
    } else {
        W-ERR "pip not found in virtual environment"
    }

    $kModelFile = Join-Path $kDir "api\src\models\v1_0\kokoro-v1_0.pth"
    if (Test-Path $kModelFile) {
        W-DEBUG "Kokoro model already downloaded"
    } else {
        W-INFO "Downloading Kokoro model (~350 MB)..."
        try {
            Invoke-WebRequest -Uri "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth" `
                -OutFile $kModelFile -TimeoutSec 600 -ErrorAction Stop
            W-OK "Kokoro model downloaded"
        } catch {
            W-WARN "Model download failed. It will be downloaded on first server start."
            W-DEBUG "Manual: download from https://huggingface.co/hexgrad/Kokoro-82M"
        }
    }

    $espeak = "C:\Program Files\eSpeak NG\libespeak-ng.dll"
    if (!(Test-Path $espeak)) {
        W-INFO "eSpeak NG is recommended for better pronunciation"
        $a = Read-Host "Install eSpeak NG? [Y/n]"
        if ($a -ne "n") {
            Install-FromWinget "eSpeak-NG.eSpeak-NG" "eSpeak NG" | Out-Null
            if (Test-Path $espeak) { W-OK "eSpeak NG installed" }
            else { W-WARN "Installation may have failed. Set PHONEMIZER_ESPEAK_LIBRARY manually." }
        }
    } else { W-OK "eSpeak NG found" }

    W-OK "FastKoko setup complete"
    W-SPACE
}

# ============================================================
# LITELLM
# ============================================================
if ($services.LiteLLM) {
    W-H "Installing LiteLLM (AI Gateway)"
    W-SPACE

    if (Test-Cmd litellm) {
        $ver = & litellm --version 2>&1
        W-OK "LiteLLM already installed: $ver"
    } else {
        W-INFO "Installing LiteLLM..."
        uv tool install "litellm[proxy]" 2>&1 | Out-Null
        if (Test-Cmd litellm) {
            W-OK "LiteLLM installed"
        } else {
            W-WARN "LiteLLM installation failed. Try: pip install 'litellm[proxy]'"
        }
    }

    # Add to PATH
    $uvBin = "$env:USERPROFILE\.local\bin"
    if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) {
        $env:Path += ";$uvBin"
    }

    # Ollama - always offered after LiteLLM
    W-SPACE
    W-INFO "LiteLLM is installed. Would you like to also install Ollama for running local LLMs?"
    if (!(Test-Cmd ollama)) {
        $a = Read-Host "Install Ollama? [Y/n]"
        if ($a -ne "n") {
            W-INFO "Downloading Ollama..."
            $ollamaExe = Join-Path $env:TEMP "OllamaSetup.exe"
            $ok = Download-WithRetry "https://ollama.com/download/ollama-windows-amd64.exe" $ollamaExe
            if ($ok) {
                W-INFO "Installing Ollama..."
                Start-Process -FilePath $ollamaExe -ArgumentList "/S" -Wait -ErrorAction SilentlyContinue
                Remove-Item $ollamaExe -ErrorAction SilentlyContinue
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                if (Test-Cmd ollama) { W-OK "Ollama installed successfully" }
                else { W-WARN "Ollama installed but not in PATH yet. Restart your terminal." }
            } else { W-WARN "Ollama download failed. You can install it manually from https://ollama.com" }
        }
    } else {
        W-OK "Ollama already installed"
    }

    if (Test-Cmd ollama) {
        W-SPACE
        $m = Read-Host "Pull a default model? (e.g. llama3.2, gemma, mistral) or Enter to skip"
        if ($m) {
            W-INFO "Pulling $m (this may take a while)..."
            & ollama pull $m 2>&1 | Out-Null
            W-OK "Model $m downloaded"
        }
    }

    W-OK "LiteLLM setup complete"
    W-SPACE
}

# ============================================================
# WHISPER SERVER
# ============================================================
if ($services.Whisper) {
    W-H "Installing WhisperServer (Speech-to-Text)"
    W-SPACE

    $wDir = Join-Path $Path "WhisperServer"
    $wVenvPy = Join-Path $wDir ".venv\Scripts\python.exe"
    $wServerPy = Join-Path $wDir "server.py"

    New-Item -ItemType Directory -Path (Join-Path $wDir ".venv\Scripts") -Force | Out-Null

    if (!(Test-Path $wVenvPy)) {
        W-INFO "Creating virtual environment (Python 3.10)..."
        $prev = Get-Location
        Set-Location $wDir
        & uv venv .venv --python 3.10 --seed 2>&1 | Out-Null
        Set-Location $prev
        W-OK "Virtual environment created"
    } else { W-DEBUG "Virtual environment already exists" }

    # Determine best model
    $whisperModel = "base"
    if ($hasNvidia -and $nvidiaVram -ge 6) {
        $whisperModel = "large-v3-turbo"
        W-INFO "NVIDIA GPU with $nvidiaVram GB VRAM -> using large-v3-turbo"
    } elseif ($hasNvidia -and $nvidiaVram -ge 4) {
        $whisperModel = "medium"
        W-INFO "NVIDIA GPU with $nvidiaVram GB VRAM -> using medium"
    } elseif ($hasNvidia) {
        $whisperModel = "base"
        W-INFO "NVIDIA GPU with limited VRAM -> using base"
    } elseif ($hasAMD) {
        $whisperModel = "medium"
        W-INFO "AMD GPU -> using medium (CPU inference, no ROCm support)"
    } elseif ($totalRam -ge 16) {
        $whisperModel = "base"
        W-INFO "No GPU, $totalRam GB RAM -> using base"
    } else {
        $whisperModel = "tiny"
        W-INFO "Limited hardware -> using tiny"
    }
    W-OK "Selected Whisper model: $whisperModel"
    W-SPACE

    W-INFO "Installing Whisper dependencies..."
    $wPip = Join-Path $wDir ".venv\Scripts\pip.exe"
    if (Test-Path $wPip) {
        & $wPip install --upgrade pip -q 2>&1 | Out-Null
        & $wPip install "openai-whisper>=1.1.10" "uvicorn[standard]" "fastapi" "pydantic" "python-multipart" "mutagen" -q 2>&1 | Out-Null
        # Install CUDA-enabled torch if GPU detected
        if ($hasNvidia) {
            W-DEBUG "Installing CUDA-enabled torch..."
            & $wPip uninstall torch -y -q 2>&1 | Out-Null
            & $wPip install torch --index-url https://download.pytorch.org/whl/cu128 --timeout 600 -q 2>&1 | Out-Null
        }
        W-OK "Dependencies installed"
    }

    # Fix whisper.py for Windows
    $wPy = Join-Path $wDir ".venv\Lib\site-packages\whisper.py"
    if (Test-Path $wPy) {
        $c = Get-Content $wPy -Raw
        $c = $c -replace "libc_name = ctypes.util.find_library\('c'\)", 'libc_name = "msvcrt.dll"'
        $c | Set-Content $wPy -Encoding UTF8
        W-DEBUG "Windows compatibility fix applied"
    }

    W-INFO "Downloading Whisper model '$whisperModel' (this may take a while)..."
    $prev = Get-Location
    Set-Location $wDir
    if ($hasNvidia) {
        & $wVenvPy -c "import whisper; whisper.load_model('$whisperModel', device='cuda')" 2>&1 | Out-Null
    } else {
        & $wVenvPy -c "import whisper; whisper.load_model('$whisperModel', device='cpu')" 2>&1 | Out-Null
    }
    Set-Location $prev
    W-OK "Whisper model downloaded"

    # Create server.py if missing
    if (!(Test-Path $wServerPy)) {
        W-DEBUG "Creating server.py from template..."
    }

    W-OK "WhisperServer setup complete"
    W-SPACE
}

# ============================================================
# GENERATE ALL SCRIPTS
# ============================================================
W-H "Generating Launcher Scripts"
W-INFO "Creating launcher scripts..."
& "$PSScriptRoot\_generate_scripts.ps1" -VerityTMPath $Path -WhisperModel $whisperModel
W-OK "All scripts generated"
W-SPACE

# ============================================================
# ADD TO POWERSHELL PROFILE
# ============================================================
$uvBin = "$env:USERPROFILE\.local\bin"
if (Test-Path $uvBin) {
    $profileFile = "$env:USERPROFILE\AppData\Roaming\PowerShell\Microsoft.PowerShell_profile.ps1"
    $profileContent = ""
    if (Test-Path $profileFile) { $profileContent = Get-Content $profileFile -Raw -ErrorAction SilentlyContinue }
    if (-not $profileContent -or $profileContent -notlike "*$uvBin*") {
        Add-Content -Path $profileFile -Value "`n`$env:Path += `";$uvBin`"" -Encoding UTF8
    }
}

# ============================================================
# SUMMARY
# ============================================================
W-H "Setup Complete!"
W-SPACE
W-OK "Location: $Path"
W-SPACE
if ($services.FastKoko) { Write-Host "  FastKoko (TTS)     -> http://127.0.0.1:8880/v1/  | FastKoko.bat" -ForegroundColor Green }
if ($services.LiteLLM) { Write-Host "  LiteLLM (AI)       -> http://127.0.0.1:4000/v1/  | LiteLLM.bat" -ForegroundColor Green }
if ($services.Whisper) {
    Write-Host "  Whisper (STT)      -> http://127.0.0.1:9000/v1/  | WhisperServer.bat" -ForegroundColor Green
    Write-Host "    Model: $whisperModel" -ForegroundColor DarkGray
}
W-SPACE
Write-Host "  Master Controller  -> Manager.bat (controls all from one window)" -ForegroundColor Magenta
W-SPACE
W-INFO "Press Enter to exit"
Read-Host
