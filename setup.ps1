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
    if ($job.State -eq "Completed") { Write-Host "`r  done  ${pf}${label} (${ts})" -F $Gn }
    else { Write-Host "`r  FAIL  ${pf}${label}" -F $Rd; Write-Host "  ERROR: $result" -F $Rd; Read-Host; exit 1 }
}

function phase($t) { Clear-Host; Write-Host "`n  Verity JE Setup - $t`n" -F $Yl }
function wait { Start-Sleep -Seconds 1 }
function die($msg) { Write-Host "  FAIL: $msg" -F $Rd; Read-Host; exit 1 }

function Get-CudaIndex {
    try {
        $nv = & nvidia-smi 2>&1 | Out-String
        if ($nv -match "CUDA UMD Version:\s*(\d+)\.(\d+)") {
            $m = [int]$Matches[1]; $n = [int]$Matches[2]
            $av = @("cu129", "cu128", "cu126", "cu124", "cu121")
            foreach ($a in $av) {
                $ver = [int]($a -replace 'cu', '').Substring(0, 2) * 100 + [int]($a -replace 'cu', '').Substring(2)
                if ($ver -le ($m * 100 + $n)) { return $a }
            }
            return $av[-1]
        }
    } catch { }
    return "cu128"
}

function Get-BestPython {
    foreach ($v in @("3.10", "3.11", "3.12", "3.13")) {
        try {
            $out = & uv python find $v 2>&1
            if ($LASTEXITCODE -eq 0 -and $out) { return $v }
        } catch { }
    }
    return "3.10"
}

function Get-EspeakDll {
    foreach ($p in @(
        "$env:ProgramFiles\eSpeak NG\libespeak-ng.dll",
        "${env:ProgramFiles(x86)}\eSpeak NG\libespeak-ng.dll",
        "$env:LOCALAPPDATA\Programs\eSpeak NG\libespeak-ng.dll"
    )) { if (Test-Path $p) { return $p } }
    return ""
}

function Get-UvBin {
    foreach ($p in @(
        "$env:USERPROFILE\.local\bin",
        "$env:APPDATA\uv\bin",
        "$env:LOCALAPPDATA\Programs\uv"
    )) { if (Test-Path $p) { return $p } }
    return ""
}

function Pip-Has($venvDir, $package) {
    $py = Join-Path $venvDir ".venv\Scripts\python.exe"
    if (Test-Path $py) {
        try { & $py -c "import $package" 2>&1 | Out-Null; return ($LASTEXITCODE -eq 0) } catch { return $false }
    }
    return $false
}

function Pip-Run($venvDir, $arguments) {
    $pip = Join-Path $venvDir ".venv\Scripts\pip.exe"
    & $pip @arguments 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { die "pip failed: $arguments" }
}

$cudaIdx = "cu128"; $bestPy = "3.10"; $espeakPath = ""; $uvBin = ""

# ================================================================
# PHASE 1: SYSTEM DETECTION
# ================================================================
while ($true) {
    Clear-Host; Write-Host "`n  Verity JE Setup - System Detection`n" -F $Yl

    $hasGit = T git
    $hasPy = T python
    if ($hasPy) { $pyVer = & python --version 2>&1 }
    $hasUv = T uv

    $hasGPU = $false; $vramGB = 0; $gpuName = ""
    try {
        $vg = Get-CimInstance Win32_VideoController -EA SilentlyContinue
        if ($vg) {
            foreach ($dev in $vg) {
                if ($dev.Name -match "NVIDIA|GeForce") { $hasGPU = $true; $gpuName = $dev.Name; break }
            }
        }
    } catch { }

    if ($hasGPU) {
        try {
            $nvVram = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1
            if ($nvVram -match '(\d+)') { $vramGB = [math]::Floor([int]$Matches[1] / 1024) }
        } catch { if ($vramGB -lt 1) { $vramGB = 4 } }
        $cudaIdx = Get-CudaIndex
    }

    $ramGB = 0
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
        if ($cs) { $ramGB = [math]::Floor($cs.TotalPhysicalMemory / 1GB) }
    } catch { }

    if ($hasUv) { $bestPy = Get-BestPython; $uvBin = Get-UvBin }
    $espeakPath = Get-EspeakDll

    $fg = if ($hasGit) { $Gn } else { $Rd }
    Write-Host "  Git       " -NoNewline -F $Dg; Write-Host $(if ($hasGit) { "found" } else { "missing" }) -F $fg
    $fg = if ($hasPy) { $Gn } else { $Rd }
    Write-Host "  Python    " -NoNewline -F $Dg; Write-Host $(if ($hasPy) { $pyVer } else { "missing" }) -F $fg
    $fg = if ($hasUv) { $Gn } else { $Rd }
    Write-Host "  uv        " -NoNewline -F $Dg; Write-Host $(if ($hasUv) { "found" } else { "missing" }) -F $fg
    $fg = if ($hasGPU) { $Gn } else { $Dg }
    Write-Host "  GPU       " -NoNewline -F $Dg; Write-Host $(if ($hasGPU) { "$gpuName ($vramGB GB)" } else { "CPU only" }) -F $fg
    Write-Host "  RAM       " -NoNewline -F $Dg; Write-Host "$ramGB GB" -F $Wh
    Write-Host "  CUDA idx  " -NoNewline -F $Dg; Write-Host " $cudaIdx" -F $Gn
    Write-Host "  Python    " -NoNewline -F $Dg; Write-Host " $bestPy (for venvs)" -F $Gn
    Write-Host "  eSpeak    " -NoNewline -F $Dg; Write-Host $(if ($espeakPath) { "found" } else { "not found" }) -F $(if ($espeakPath) { $Gn } else { $Dg })

    Write-Host "`n  [Enter] continue  [Q] quit" -F $Dg
    $k = K
    if ($k.Key -eq "Q") { exit 0 }
    if ($k.Key -eq "Enter") { break }
}

# ================================================================
# PHASE 2: SERVICE SELECTION
# ================================================================
$svc = @{ K = $true; L = $true; W = $true }; $cursor = 0
while ($true) {
    Clear-Host; Write-Host "`n  Verity JE Setup - Service Selection`n" -F $Yl
    $items = @(
        @("FastKoko",      "Text-to-Speech  Kokoro-82M  :8880", "K"),
        @("LiteLLM",       "AI Gateway      100+ LLMs   :4000", "L"),
        @("WhisperServer", "Speech-to-Text  Whisper     :9000", "W")
    )
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
    if ($k.Key -eq "UpArrow")   { $cursor = [Math]::Max(0, $cursor - 1) }
    if ($k.Key -eq "DownArrow") { $cursor = [Math]::Min(2, $cursor + 1) }
    if ($k.Key -eq "Spacebar")  { $svc[$items[$cursor][2]] = -not $svc[$items[$cursor][2]] }
    if ($k.Key -eq "Enter") {
        $any = $svc.K -or $svc.L -or $svc.W
        if (-not $any) { Write-Host "`n  Select at least one service." -F $Rd; wait } else { break }
    }
}

# ================================================================
# PHASE 3: CONFIRM
# ================================================================
while ($true) {
    Clear-Host; Write-Host "`n  Verity JE Setup - Confirm`n" -F $Yl
    Write-Host "  Will install:`n" -F $Wh
    if ($svc.K) { Write-Host "    [X] FastKoko        TTS (Kokoro-82M)    ~1.5 GB" -F $Gn }
    if ($svc.L) { Write-Host "    [X] LiteLLM         AI Gateway           ~200 MB" -F $Gn }
    if ($svc.W) { Write-Host "    [X] WhisperServer   STT (Whisper)        ~3 GB"   -F $Gn }
    if (-not $hasGit)      { Write-Host "`n  Git will be installed."       -F $Rd }
    if (-not $hasUv)       { Write-Host "  uv will be installed."          -F $Rd }
    if (-not $espeakPath)  { Write-Host "  eSpeak NG will be installed."   -F $Rd }
    Write-Host "`n  Install path : $Path"    -F $Dg
    Write-Host "  CUDA          : $cudaIdx"  -F $Dg
    Write-Host "  Python (venv) : $bestPy"   -F $Dg
    Write-Host "`n  [Y] proceed  [B] back  [Q] quit" -F $Dg
    $k = K
    if ($k.Key -eq "Q") { exit 0 }
    if ($k.Key -eq "B") { break }
    if ($k.KeyChar -eq 'y') { break }
}

# ================================================================
# PHASE 4: SYSTEM DEPENDENCIES
# ================================================================
$needDeps = (-not $hasGit) -or (-not $hasUv) -or ((-not $espeakPath) -and $svc.K)
if ($needDeps) {
    phase "System Dependencies"

    if (-not $hasGit) {
        Write-Host "  Installing Git..." -F $Wh
        if (T winget) {
            winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        } else {
            $tmp = Join-Path $env:TEMP "GitSetup.exe"
            (New-Object Net.WebClient).DownloadFile("https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.2/Git-2.47.1.2-64-bit.exe", $tmp)
            Start-Process -FilePath $tmp -ArgumentList "/SILENT" -Wait
            Remove-Item $tmp -EA SilentlyContinue
        }
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        if (T git) { Write-Host "  Git installed" -F $Gn; $hasGit = $true } else { die "Git installation failed" }
    }

    if (-not $hasUv) {
        Write-Host "  Installing uv..." -F $Wh
        if (T winget) {
            winget install --id AstralSoftware.uv -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        } else {
            powershell -NoProfile -EP Bypass -Command "Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression" 2>&1 | Out-Null
        }
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        if (T uv) { Write-Host "  uv installed" -F $Gn; $hasUv = $true; $bestPy = Get-BestPython; $uvBin = Get-UvBin }
        else { die "uv installation failed" }
    }

    if ((-not $espeakPath) -and $svc.K) {
        Write-Host "  Installing eSpeak NG..." -F $Wh
        if (T winget) {
            winget install --id eSpeak-NG.eSpeak-NG -e --silent --accept-source-agreements 2>&1 | Out-Null
            $espeakPath = Get-EspeakDll
            if ($espeakPath) { Write-Host "  eSpeak NG installed" -F $Gn }
            else { Write-Host "  eSpeak NG: could not verify" -F $Dg }
        } else {
            Write-Host "  eSpeak NG unavailable (winget missing). Optional." -F $Dg
        }
    }

    wait
}

# ================================================================
# PHASE 5: FASTKOKO (KOKORO TTS)
# ================================================================
if ($svc.K) {
    $kD = Join-Path $Path "Kokoro-FastAPI"
    $kPy = Join-Path $kD ".venv\Scripts\python.exe"
    $kM = Join-Path $kD "api\src\models\v1_0\kokoro-v1_0.pth"
    $kPip = Join-Path $kD ".venv\Scripts\pip.exe"

    phase "FastKoko - Kokoro TTS"

    # 1/5 Repository
    if (Test-Path (Join-Path $kD "api\src\main.py")) {
        Write-Host "  skip  [1/5] Repository" -F $Dg
    } else {
        spn "Clone repository" 1 5 {
            param($P, $S)
            Set-Location $S
            & git clone https://github.com/remsky/Kokoro-FastAPI.git (Join-Path $P "Kokoro-FastAPI") 2>&1 | Out-Null
            if (-not (Test-Path (Join-Path $P "Kokoro-FastAPI\api\src\main.py"))) { throw "Clone failed" }
        }
    }

    # 2/5 Environment
    if (Test-Path $kPy) {
        Write-Host "  skip  [2/5] Environment" -F $Dg
    } else {
        Write-Host "  [2/5] Creating Python environment ($bestPy)..." -F $Wh
        Push-Location $kD
        $venvOut = & uv venv .venv --python $bestPy --seed 2>&1
        if (-not (Test-Path ".venv\Scripts\python.exe")) { die "venv: $venvOut" }
        Pop-Location
        Write-Host "  done  [2/5] Environment" -F $Gn
    }

    # 3/5 Dependencies
    if (Pip-Has $kD "kokoro") {
        Write-Host "  skip  [3/5] Dependencies" -F $Dg
    } else {
        Write-Host "  [3/5] Installing dependencies..." -F $Wh
        Push-Location $kD
        Pip-Run $kD @("install", "--upgrade", "pip", "-q")
        Pip-Run $kD @("install", "cython<3.0", "-q")
        Pip-Run $kD @("install", "-e", ".[cpu]")
        Pip-Run $kD @("uninstall", "torch", "-y", "-q")
        Pip-Run $kD @("install", "torch", "--index-url", "https://download.pytorch.org/whl/$cudaIdx", "--timeout", "600", "-q")
        Pop-Location
        Write-Host "  done  [3/5] Dependencies" -F $Gn
    }

    # 4/5 Model
    if (Test-Path $kM) {
        Write-Host "  skip  [4/5] Model" -F $Dg
    } else {
        Write-Host "  [4/5] Downloading Kokoro model (350 MB)..." -F $Wh
        try {
            (New-Object Net.WebClient).DownloadFile("https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth", $kM)
            Write-Host "  done  [4/5] Model" -F $Gn
        } catch {
            die "Model download failed: $_"
        }
    }

    Write-Host "  [5/5] Ready" -F $Gn
    Set-Location $startDir
    wait
}

# ================================================================
# PHASE 6: LITELLM (AI GATEWAY)
# ================================================================
if ($svc.L) {
    phase "LiteLLM - AI Gateway"

    if (T litellm) {
        $llmVer = & litellm --version 2>&1
        Write-Host "  skip  LiteLLM ($llmVer)" -F $Dg
    } else {
        spn "Install LiteLLM" 0 0 {
            param($P, $S)
            uv tool install "litellm[proxy]" 2>&1 | Out-Null
        }
        Write-Host "  done  LiteLLM installed" -F $Gn
    }

    if ($uvBin -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }
    wait
}

# ================================================================
# PHASE 7: WHISPER SERVER (SPEECH-TO-TEXT)
# ================================================================
if ($svc.W) {
    $wD = Join-Path $Path "WhisperServer"
    $wPy = Join-Path $wD ".venv\Scripts\python.exe"
    $wPip = Join-Path $wD ".venv\Scripts\pip.exe"
    New-Item -ItemType Dir -Path $wD -Force | Out-Null

    if ($hasGPU -and $vramGB -ge 6)      { $wModel = "large-v3-turbo" }
    elseif ($hasGPU -and $vramGB -ge 4)  { $wModel = "medium" }
    elseif ($hasGPU)                     { $wModel = "base" }
    elseif ($ramGB -ge 16)              { $wModel = "base" }
    else                                 { $wModel = "tiny" }

    $device = if ($hasGPU) { "cuda" } else { "cpu" }

    phase "WhisperServer - STT ($wModel)"

    # 1/3 Environment
    if (Test-Path $wPy) {
        Write-Host "  skip  [1/3] Environment" -F $Dg
    } else {
        Write-Host "  [1/3] Creating Python environment ($bestPy)..." -F $Wh
        Push-Location $wD
        $venvOut = & uv venv .venv --python $bestPy --seed 2>&1
        if (-not (Test-Path ".venv\Scripts\python.exe")) { die "venv: $venvOut" }
        Pop-Location
        Write-Host "  done  [1/3] Environment" -F $Gn
    }

    # 2/3 Dependencies
    if (Pip-Has $wD "whisper") {
        Write-Host "  skip  [2/3] Dependencies" -F $Dg
    } else {
        Write-Host "  [2/3] Installing dependencies..." -F $Wh
        Push-Location $wD
        Pip-Run $wD @("install", "--upgrade", "pip", "-q")
        Pip-Run $wD @("install", "openai-whisper>=1.1.10", "uvicorn[standard]", "fastapi", "pydantic", "python-multipart", "mutagen", "-q")
        if ($hasGPU) {
            Pip-Run $wD @("uninstall", "torch", "-y", "-q")
            Pip-Run $wD @("install", "torch", "--index-url", "https://download.pytorch.org/whl/$cudaIdx", "--timeout", "600", "-q")
        }
        Pop-Location
        Write-Host "  done  [2/3] Dependencies" -F $Gn
    }

    # Windows compatibility fix for whisper.py
    $wFix = Join-Path $wD ".venv\Lib\site-packages\whisper.py"
    if (Test-Path $wFix) {
        $fixContent = Get-Content $wFix -Raw
        if ($fixContent -notmatch "msvcrt\.dll") {
            $fixContent = $fixContent -replace "libc_name = ctypes.util.find_library\('c'\)", 'libc_name = "msvcrt.dll"'
            $fixContent | Set-Content $wFix -Encoding UTF8
        }
    }

    # 3/3 Model
    Write-Host "  [3/3] Downloading Whisper model ($wModel, $device)..." -F $Wh
    Set-Location $wD
    $loadResult = & $wPy -c "import whisper; whisper.load_model('$wModel', device='$device'); print('OK')" 2>&1
    Set-Location $startDir
    if ($loadResult -match "OK") { Write-Host "  done  [3/3] Model loaded" -F $Gn }
    else { die "Model load failed: $loadResult" }

    wait
}

# ================================================================
# PHASE 8: OLLAMA (OPTIONAL)
# ================================================================
if (-not (T ollama)) {
    phase "Ollama (optional)"
    Write-Host "  Ollama lets you run LLMs locally (private, offline)." -F $Wh
    Write-Host "  [Y] install  [N] skip" -F $Dg
    $k = K
    if ($k.KeyChar -eq 'y') {
        $tmp = Join-Path $env:TEMP "OllamaSetup.exe"
        spn "Download Ollama" 0 0 {
            param($P, $S)
            (New-Object Net.WebClient).DownloadFile("https://ollama.com/download/ollama-windows-amd64.exe", (Join-Path $env:TEMP "OllamaSetup.exe"))
        }
        if (Test-Path $tmp) {
            Start-Process -FilePath $tmp -ArgumentList "/S" -Wait -EA SilentlyContinue
            Remove-Item $tmp -EA SilentlyContinue
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
        }
        if (T ollama) { Write-Host "  Ollama installed" -F $Gn } else { Write-Host "  Ollama installed (restart terminal to use)" -F $Dg }
    }
    wait
}

if (T ollama) {
    Write-Host ""
    Write-Host "  Pull a model? (e.g. llama3.2, gemma, mistral)" -F $Wh
    Write-Host "  Enter model name or press Enter to skip:" -F $Dg
    Write-Host "  > " -NoNewline -F $Dg
    $modelName = Read-Host
    if ($modelName) {
        spn "Pull $modelName" 0 0 {
            param($P, $S, $mod)
            & ollama pull $mod 2>&1 | Out-Null
        } -xa $modelName | Out-Null
        Write-Host "  Model $modelName pulled" -F $Gn
    }
}

# ================================================================
# PHASE 9: GENERATE LAUNCHER SCRIPTS
# ================================================================
phase "Generating Launcher Scripts"
Write-Host "  Creating .bat and .ps1 files..." -F $Wh
& "$PSScriptRoot\_generate_scripts.ps1" -VerityTMPath $Path -WhisperModel $wModel -EspeakDll $espeakPath -UvBin $uvBin
Write-Host "  Scripts generated" -F $Gn
wait

# ================================================================
# PHASE 10: DONE
# ================================================================
Clear-Host
Write-Host "`n  Verity JE Setup - Complete!`n" -F $Yl
Write-Host "  Location: $Path`n" -F $Dg
if ($svc.K) { Write-Host "  FastKoko (TTS) -> http://127.0.0.1:8880/v1/   FastKoko.bat"         -F $Gn }
if ($svc.L) { Write-Host "  LiteLLM (AI)  -> http://127.0.0.1:4000/v1/   LiteLLM.bat"          -F $Gn }
if ($svc.W) { Write-Host "  Whisper (STT) -> http://127.0.0.1:9000/v1/   WhisperServer.bat ($wModel)" -F $Gn }
Write-Host ""
Write-Host "  [Y] Launch Manager now     [N] Exit" -F $Dg
$k = K
if ($k.KeyChar -eq 'y') {
    Start-Process powershell -ArgumentList "-NoExit", "-EP", "Bypass", "-File", (Join-Path $Path "Manager.bat")
} else {
    Write-Host "`n  To start later, run:" -F $Dg
    Write-Host "    cd `"$Path`"" -F $Wh
    Write-Host "    .\Manager.bat" -F $Wh
}
Write-Host "`n  Press any key to exit." -F $Dg
K | Out-Null
