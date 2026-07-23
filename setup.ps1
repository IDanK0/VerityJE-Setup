<# ============================================================================
 Verity JE Setup - one-click AI backend installer
 Installs and configures: FastKoko (TTS), LiteLLM (LLM gateway), Whisper (STT)

 Usage:
   .\setup.ps1                    interactive install
   .\setup.ps1 -Yes               unattended install (all services, defaults)
   .\setup.ps1 -Services K,W      only FastKoko + Whisper
   .\setup.ps1 -SelfTest          detect hardware/software only, change nothing
   .\setup.ps1 -Path D:\Verity    install into a custom folder
============================================================================ #>
[CmdletBinding()]
param(
    [string]$Path,
    [switch]$Yes,
    [string]$Services = "",
    [switch]$SkipOllama,
    [switch]$SelfTest
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptRoot) { $scriptRoot = (Get-Location).Path }
if (-not $Path) { $Path = $scriptRoot }
$Path = [IO.Path]::GetFullPath($Path)
$startDir = (Get-Location).Path

$Yl = "Yellow"; $Gn = "Green"; $Rd = "Red"; $Wh = "White"; $Dg = "DarkGray"

# ---------------------------------------------------------------- logging ---
$logDir = Join-Path $Path "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$setupLog = Join-Path $logDir "setup.log"
"[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] === setup started ===" | Out-File $setupLog -Append -Encoding utf8

function Log($msg, $color = $null) {
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $msg"
    $line | Out-File $setupLog -Append -Encoding utf8
    if ($color) { Write-Host $msg -F $color } else { Write-Host $msg }
}

function T($n) { try { $null = Get-Command $n -EA Stop; return $true } catch { return $false } }

function K {
    if ($script:Yes) { return $null }
    try { return [Console]::ReadKey($true) } catch { return $null }
}

function Pause-OrExit($code) {
    if ($script:Yes) { exit $code }
    Read-Host "  Press Enter to exit"
    exit $code
}

function die($msg) {
    Log "  FAIL: $msg" $Rd
    Log "  Details in: $setupLog" $Dg
    Pause-OrExit 1
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Add-UserPath($dir) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$dir*") {
        [Environment]::SetEnvironmentVariable("Path", "$userPath;$dir", "User")
        Log "  added to user PATH: $dir" $Dg
    }
    if ($env:Path -notlike "*$dir*") { $env:Path += ";$dir" }
}

# ------------------------------------------------------------ job spinner ---
function spn($label, $step, $total, [scriptblock]$sb, $xa = @()) {
    $job = Start-Job -ScriptBlock $sb -ArgumentList $xa
    $ch = @("\", "|", "/", "-"); $i = 0; $sw = [Diagnostics.Stopwatch]::StartNew()
    $pf = if ($total -gt 0) { "[$step/$total] " } else { "" }
    while ($job.State -eq "Running") {
        $el = [math]::Floor($sw.Elapsed.TotalSeconds)
        $ts = if ($el -gt 60) { "$([math]::Floor($el/60))m$($el%60)s" } else { "${el}s" }
        Write-Host ("`r  {0} {1}{2}... ({3})   " -f $ch[$i % 4], $pf, $label, $ts) -NoNewline -F $Wh
        Start-Sleep -Milliseconds 200; $i++
    }
    $state = $job.State
    $out = ($job | Receive-Job 2>&1 | Out-String).Trim()
    $errs = @(); foreach ($cj in $job.ChildJobs) { foreach ($e in $cj.Error) { $errs += $e } }
    Remove-Job $job -Force
    $el = [math]::Floor($sw.Elapsed.TotalSeconds)
    $ts = if ($el -gt 60) { "$([math]::Floor($el/60))m$($el%60)s" } else { "${el}s" }
    if ($state -eq "Completed") {
        Write-Host "`r  done  ${pf}${label} (${ts})          " -F $Gn
        if ($out) { "[$label] $out" | Out-File $setupLog -Append -Encoding utf8 }
    } else {
        Write-Host "`r  FAIL  ${pf}${label}                    " -F $Rd
        if ($out)  { Log "  output: $out" $Rd }
        if ($errs) { Log "  error : $($errs[0])" $Rd }
        die "$label failed (see $setupLog)"
    }
}

function phase($t) { if (-not $script:Yes) { Clear-Host }; Write-Host "`n  Verity JE Setup - $t`n" -F $Yl }

# ----------------------------------------------------------- download helper ---
function Download-File($url, $dest, $tries = 3) {
    $parent = Split-Path $dest -Parent
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    for ($i = 1; $i -le $tries; $i++) {
        try {
            if (Test-Path $dest) { Remove-Item $dest -Force }
            if (T "curl.exe") {
                $cout = & curl.exe -fsSL --connect-timeout 30 --retry 2 -o $dest $url 2>&1 | Out-String
                if ($LASTEXITCODE -eq 0 -and (Test-Path $dest) -and (Get-Item $dest).Length -gt 0) { return }
                Log "  download attempt $i/$tries failed: curl exit $LASTEXITCODE $cout" $Dg
            } else {
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -TimeoutSec 900 -EA Stop
                if ((Test-Path $dest) -and (Get-Item $dest).Length -gt 0) { return }
            }
        } catch {
            Log "  download attempt $i/$tries failed: $($_.Exception.Message)" $Dg
        }
        Start-Sleep -Seconds (2 * $i)
    }
    throw "Download failed after $tries attempts: $url"
}

# --------------------------------------------------------------- detection ---
function Get-CudaIndex {
    # Maps the driver CUDA level to the newest compatible pytorch wheel index.
    # nvidia-smi prints "CUDA Version: X.Y" on most drivers, "CUDA UMD Version: X.Y" on newest ones.
    try {
        $nv = & nvidia-smi 2>&1 | Out-String
        if ($nv -match "CUDA (?:UMD )?Version:\s*(\d+)\.(\d+)") {
            $driverVer = [int]$Matches[1] * 100 + [int]$Matches[2]
            foreach ($a in @("cu129", "cu128", "cu126", "cu124", "cu121", "cu118")) {
                $n = [int]($a -replace 'cu', '')
                $idxVer = [math]::Floor($n / 10) * 100 + ($n % 10)
                if ($idxVer -le $driverVer) {
                    $idx = $a; break
                }
            }
            if (-not $idx) { return "" }   # driver too old for any CUDA wheel
        } else {
            $idx = "cu126"                  # version unreadable: conservative default
        }
        # Blackwell (RTX 50-series, sm_120+) kernels only ship in cu128+ wheels.
        $cc = & nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>&1 | Out-String
        if ($cc -match '(\d+)\.(\d+)' -and [int]$Matches[1] -ge 12) {
            $cur = [int]($idx -replace 'cu', '')
            if ($cur -lt 128) { $idx = $(if ($driverVer -ge 1209) { "cu129" } else { "cu128" }) }
        }
        return $idx
    } catch { }
    return "cu126"
}

function Get-BestPython {
    # 3.12 first: best wheel coverage for torch/spacy/numba right now.
    foreach ($v in @("3.12", "3.11", "3.10", "3.13")) {
        try {
            $out = & uv python find $v 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0 -and $out.Trim()) { return $v }
        } catch { }
    }
    try {
        & uv python install 3.12 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return "3.12" }
    } catch { }
    return "3.12"
}

function Get-UvToolBin {
    try {
        $out = & uv tool dir --bin 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $out.Trim() -and (Test-Path $out.Trim())) { return $out.Trim() }
    } catch { }
    foreach ($p in @("$env:USERPROFILE\.local\bin", "$env:APPDATA\uv\bin")) {
        if (Test-Path $p) { return $p }
    }
    return ""
}

function Get-SystemEspeakDll {
    foreach ($p in @(
        "$env:ProgramFiles\eSpeak NG\libespeak-ng.dll",
        "${env:ProgramFiles(x86)}\eSpeak NG\libespeak-ng.dll",
        "$env:LOCALAPPDATA\Programs\eSpeak NG\libespeak-ng.dll"
    )) { if ($p -and (Test-Path $p)) { return $p } }
    return ""
}

function Test-PortFree($port) {
    try {
        $c = Get-NetTCPConnection -LocalPort $port -State Listen -EA SilentlyContinue
        return ($null -eq $c)
    } catch { return $true }
}

# ---------------------------------------------------------------- venv utils ---
function Pip-Has($venvDir, $module) {
    $py = Join-Path $venvDir ".venv\Scripts\python.exe"
    if (Test-Path $py) {
        try { & $py -c "import $module" 2>&1 | Out-Null; return ($LASTEXITCODE -eq 0) } catch { return $false }
    }
    return $false
}

# uv handles >260-char paths internally (torch ships very long license paths);
# plain pip dies with WinError 206 in any moderately deep install folder.
function Pip-Run($venvDir, $arguments) {
    $py = Join-Path $venvDir ".venv\Scripts\python.exe"
    $logF = Join-Path $logDir "pip-last.log"
    $env:UV_HTTP_TIMEOUT = "600"
    & uv pip install --python $py @arguments *> $logF
    if ($LASTEXITCODE -ne 0) {
        $tail = (Get-Content $logF -Tail 15 | Out-String).Trim()
        Log "  uv pip failed: install $($arguments -join ' ')" $Rd
        Log $tail $Dg
        die "package install failed (see $logF)"
    }
}

function Pip-Uninstall($venvDir, $pkg) {
    $py = Join-Path $venvDir ".venv\Scripts\python.exe"
    & uv pip uninstall --python $py $pkg 2>&1 | Out-Null
}

# Remove debris from interrupted installs (corrupt dist-info breaks uv/pip later)
function Repair-Venv($venvDir) {
    $sp = Join-Path $venvDir ".venv\Lib\site-packages"
    if (-not (Test-Path $sp)) { return }
    Get-ChildItem $sp -Directory -Force -EA SilentlyContinue |
        Where-Object { $_.Name -like "~*" } |
        Remove-Item -Recurse -Force -EA SilentlyContinue
    foreach ($di in (Get-ChildItem $sp -Directory -Filter "*.dist-info" -EA SilentlyContinue)) {
        if (-not (Test-Path (Join-Path $di.FullName "METADATA"))) {
            Remove-Item $di.FullName -Recurse -Force -EA SilentlyContinue
        }
    }
}

function New-Venv($dir, $pyVer) {
    Push-Location $dir
    $out = & uv venv .venv --python $pyVer --seed 2>&1 | Out-String
    Pop-Location
    if (-not (Test-Path (Join-Path $dir ".venv\Scripts\python.exe"))) {
        die "venv creation failed in $dir : $out"
    }
}

function Install-Torch($venvDir, $cudaIdx) {
    $py = Join-Path $venvDir ".venv\Scripts\python.exe"
    if ($cudaIdx) { $idx = "https://download.pytorch.org/whl/$cudaIdx" }
    else          { $idx = "https://download.pytorch.org/whl/cpu" }
    # real compute test: catches "CUDA not available" AND "no kernel image" (Blackwell on old wheels)
    $probe = "import torch`n" +
             "ok = torch.cuda.is_available()`n" +
             "if ok:`n" +
             "    x = torch.randn(64, 64, device='cuda')`n" +
             "    torch.cuda.synchronize()`n" +
             "    _ = (x @ x).sum().item()`n" +
             "print('RESULT:' + ('cuda' if ok else 'cpu'))"
    for ($try = 1; $try -le 2; $try++) {
        Pip-Run $venvDir @("torch", "--index-url", $idx, "-q")
        $out = & $py -c $probe 2>&1 | Out-String
        $res = ([regex]::Match($out, 'RESULT:(cuda|cpu)')).Groups[1].Value
        if ($cudaIdx -and $res -eq "cuda") { return "cuda" }
        if (-not $cudaIdx) { return "cpu" }
        Log "  torch CUDA compute test failed (attempt $try): $($out.Trim())" $Yl
        Pip-Uninstall $venvDir "torch"
    }
    # GPU requested but CUDA unusable (old driver, sandbox, etc.): fall back to CPU torch.
    Log "  CUDA not usable by torch - falling back to CPU build" $Yl
    Pip-Run $venvDir @("torch", "--index-url", "https://download.pytorch.org/whl/cpu", "-q")
    return "cpu"
}

# ------------------------------------------------------------ config output ---
function Save-Config($ht) {
    $cfgPath = Join-Path $Path "config.psd1"
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("@{")
    foreach ($k in ($ht.Keys | Sort-Object)) {
        $v = $ht[$k]
        if ($v -is [bool]) { $vv = if ($v) { '$true' } else { '$false' } }
        else { $vv = "'" + ([string]$v -replace "'", "''") + "'" }
        [void]$sb.AppendLine("    $k = $vv")
    }
    [void]$sb.AppendLine("}")
    [IO.File]::WriteAllText($cfgPath, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
    Log "  config written: $cfgPath" $Dg
}

# ================================================================ DETECTION ==
$hasGit = $false; $hasUv = $false
$hasGPU = $false; $vramGB = 0; $gpuName = ""; $cudaIdx = ""; $ramGB = 0
$bestPy = "3.12"; $uvBin = ""; $espeakSys = ""; $ffmpegBin = ""

function Read-System {
    $script:hasGit = T git
    $script:hasUv  = T uv

    $script:hasGPU = $false; $script:vramGB = 0; $script:gpuName = ""
    try {
        $vg = Get-CimInstance Win32_VideoController -EA SilentlyContinue
        foreach ($dev in $vg) {
            if ($dev.Name -match "NVIDIA|GeForce|RTX|GTX") {
                $script:hasGPU = $true; $script:gpuName = $dev.Name; break
            }
        }
    } catch { }

    if ($script:hasGPU) {
        if (T "nvidia-smi") {
            try {
                $nvVram = & nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>&1 | Out-String
                if ($nvVram -match '(\d+)') { $script:vramGB = [math]::Floor([int]$Matches[1] / 1024) }
                $script:cudaIdx = Get-CudaIndex
            } catch { $script:cudaIdx = "cu126" }
        } else {
            # nvidia-smi missing = no usable CUDA driver (VM / Sandbox paravirtualized GPU): CPU mode.
            # Avoids downloading ~3GB of CUDA wheels that can never work here.
            $script:cudaIdx = ""
        }
        if ($script:vramGB -lt 1) { $script:vramGB = 4 }
    } else {
        $script:cudaIdx = ""            # CPU-only machine
    }

    $script:ramGB = 0
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -EA SilentlyContinue
        if ($cs) { $script:ramGB = [math]::Floor($cs.TotalPhysicalMemory / 1GB) }
    } catch { }

    if ($script:hasUv) { $script:bestPy = Get-BestPython; $script:uvBin = Get-UvToolBin }
    $script:espeakSys = Get-SystemEspeakDll
    if (T "ffmpeg") {
        $script:ffmpegBin = Split-Path -Parent (Get-Command ffmpeg).Source
    }
}

function Show-System {
    $fg = if ($hasGit) { $Gn } else { $Rd }
    Write-Host "  Git        " -NoNewline -F $Dg; Write-Host $(if ($hasGit) { "found" } else { "missing (will install)" }) -F $fg
    $fg = if ($hasUv) { $Gn } else { $Rd }
    Write-Host "  uv         " -NoNewline -F $Dg; Write-Host $(if ($hasUv) { "found" } else { "missing (will install)" }) -F $fg
    $fg = if ($hasGPU) { $Gn } else { $Dg }
    Write-Host "  GPU        " -NoNewline -F $Dg; Write-Host $(if ($hasGPU) { "$gpuName ($vramGB GB)" } else { "none - CPU mode" }) -F $fg
    Write-Host "  RAM        " -NoNewline -F $Dg; Write-Host "$ramGB GB" -F $Wh
    Write-Host "  Torch idx  " -NoNewline -F $Dg; Write-Host $(if ($cudaIdx) { $cudaIdx } else { "cpu" }) -F $Gn
    Write-Host "  Python     " -NoNewline -F $Dg; Write-Host " $bestPy (managed by uv)" -F $Gn
    $fg = if ($ffmpegBin) { $Gn } else { $Dg }
    Write-Host "  ffmpeg     " -NoNewline -F $Dg; Write-Host $(if ($ffmpegBin) { "found" } else { "missing (will install for Whisper)" }) -F $fg
}

if (-not $Yes) { Clear-Host }
Read-System

if ($SelfTest) {
    Write-Host "`n  Verity JE Setup - Self Test (no changes made)`n" -F $Yl
    Show-System
    Write-Host ""
    Write-Host "  Install path : $Path" -F $Dg
    Write-Host "  8880 free    : $(Test-PortFree 8880)" -F $Dg
    Write-Host "  4000 free    : $(Test-PortFree 4000)" -F $Dg
    Write-Host "  9000 free    : $(Test-PortFree 9000)" -F $Dg
    Write-Host ""
    exit 0
}

# ------------------------------------------------------------------ PHASE 1 --
while ($true) {
    if ($Yes) { break }
    Clear-Host; Write-Host "`n  Verity JE Setup - System Detection`n" -F $Yl
    Show-System
    Write-Host "`n  [Enter] continue  [R] rescan  [Q] quit" -F $Dg
    $k = K
    if ($k -and $k.Key -eq "Q") { exit 0 }
    if ($k -and $k.Key -eq "R") { Refresh-Path; Read-System; continue }
    if ($k -and $k.Key -eq "Enter") { break }
}

# ------------------------------------------------------------------ PHASE 2 --
$svc = @{ K = $true; L = $true; W = $true }
if ($Services) {
    $svc = @{ K = ($Services -match "K"); L = ($Services -match "L"); W = ($Services -match "W") }
}
if (-not ($svc.K -or $svc.L -or $svc.W)) { die "No service selected." }

if (-not $Yes) {
    $cursor = 0; $confirmed = $false
    while (-not $confirmed) {
        Clear-Host; Write-Host "`n  Verity JE Setup - Service Selection`n" -F $Yl
        $items = @(
            @("FastKoko",      "Text-to-Speech  Kokoro-82M   :8880", "K"),
            @("LiteLLM",       "AI Gateway      100+ LLMs    :4000", "L"),
            @("WhisperServer", "Speech-to-Text  Whisper      :9000", "W")
        )
        for ($i = 0; $i -lt 3; $i++) {
            $cur = if ($i -eq $cursor) { " >>" } else { "   " }
            $chk = if ($svc[$items[$i][2]]) { "[X]" } else { "[ ]" }
            Write-Host "  $cur $chk " -NoNewline -F $Wh
            Write-Host $items[$i][0].PadRight(15) -NoNewline -F $Wh
            Write-Host $items[$i][1] -F $Dg
        }
        Write-Host "`n  [Up/Down] move  [Space] toggle  [Enter] confirm  [Q] quit" -F $Dg
        $k = K
        if ($k.Key -eq "Q") { exit 0 }
        if ($k.Key -eq "UpArrow")   { $cursor = [Math]::Max(0, $cursor - 1) }
        if ($k.Key -eq "DownArrow") { $cursor = [Math]::Min(2, $cursor + 1) }
        if ($k.Key -eq "Spacebar")  { $svc[$items[$cursor][2]] = -not $svc[$items[$cursor][2]] }
        if ($k.Key -eq "Enter") {
            if ($svc.K -or $svc.L -or $svc.W) {
                # -------------------------------------------------- PHASE 3 --
                Clear-Host; Write-Host "`n  Verity JE Setup - Confirm`n" -F $Yl
                Write-Host "  Will install:`n" -F $Wh
                if ($svc.K) { Write-Host "    [X] FastKoko        TTS (Kokoro-82M)    ~1.5 GB" -F $Gn }
                if ($svc.L) { Write-Host "    [X] LiteLLM         AI Gateway          ~400 MB" -F $Gn }
                if ($svc.W) { Write-Host "    [X] WhisperServer   STT (Whisper)       ~1-3 GB" -F $Gn }
                if (-not $hasGit) { Write-Host "`n  + Git (system)" -F $Rd }
                if (-not $hasUv)  { Write-Host "  + uv (user)" -F $Rd }
                if ($svc.W -and -not $ffmpegBin) { Write-Host "  + ffmpeg (required by Whisper)" -F $Rd }
                Write-Host "`n  Install path : $Path" -F $Dg
                Write-Host "  Torch index  : $(if ($cudaIdx) { $cudaIdx } else { 'cpu' })" -F $Dg
                Write-Host "  Python       : $bestPy" -F $Dg
                Write-Host "`n  [Y] proceed  [B] back  [Q] quit" -F $Dg
                $k2 = K
                if ($k2.Key -eq "Q") { exit 0 }
                if ($k2.Key -eq "B") { continue }          # back to selection
                if ($k2.KeyChar -eq 'y' -or $k2.KeyChar -eq 'Y' -or $k2.Key -eq 'Enter') { $confirmed = $true }
            } else {
                Write-Host "`n  Select at least one service." -F $Rd; Start-Sleep 1
            }
        }
    }
}

New-Item -ItemType Directory -Path $Path -Force | Out-Null
Set-Location $Path

# Port preflight: installing over busy ports causes confusing failures later.
foreach ($pp in @(@(8880, "FastKoko", $svc.K), @(4000, "LiteLLM", $svc.L), @(9000, "Whisper", $svc.W))) {
    if ($pp[2] -and -not (Test-PortFree $pp[0])) {
        Log "  WARNING: port $($pp[0]) is already in use ($($pp[1])). Stop that service first." $Yl
    }
}

# ================================================================= PHASE 4 ==
# System dependencies
$needVCRedist = -not ((Test-Path "$env:SystemRoot\System32\vcruntime140.dll") -and (Test-Path "$env:SystemRoot\System32\msvcp140.dll"))
$needDeps = $needVCRedist -or (-not $hasGit) -or (-not $hasUv) -or ($svc.W -and -not $ffmpegBin)
if ($needDeps) {
    phase "System Dependencies"

    # long paths save pip/uv from WinError 206 with deeply nested packages (best effort, needs admin)
    try { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -EA Stop } catch { }

    if ($needVCRedist) {
        # torch (and espeak-ng.dll) need the MSVC runtime; Sandbox/fresh Windows don't have it
        spn "Install VC++ Runtime" 1 4 {
            $ErrorActionPreference = "Continue"
            $tmp = Join-Path $env:TEMP "vc_redist.x64.exe"
            $dlErr = ""
            if (Get-Command curl.exe -EA SilentlyContinue) {
                $cout = & curl.exe -fsSL -o $tmp "https://aka.ms/vs/17/release/vc_redist.x64.exe" 2>&1 | Out-String
                if ($LASTEXITCODE -ne 0) { $dlErr = "curl exit ${LASTEXITCODE}: $cout" }
            } else {
                try { Invoke-WebRequest "https://aka.ms/vs/17/release/vc_redist.x64.exe" -OutFile $tmp -UseBasicParsing -TimeoutSec 300 -EA Stop } catch { $dlErr = "$_" }
            }
            if ($dlErr) { throw "VC++ download failed - $dlErr" }
            $p = Start-Process -FilePath $tmp -ArgumentList "/install", "/quiet", "/norestart" -Wait -PassThru
            Remove-Item $tmp -Force -EA SilentlyContinue
            # 0 = ok, 3010 = ok (reboot pending), 1638 = newer version already present
            if ($p.ExitCode -notin @(0, 3010, 1638)) { throw "vc_redist exited $($p.ExitCode)" }
        }
        if ((Test-Path "$env:SystemRoot\System32\vcruntime140.dll") -and (Test-Path "$env:SystemRoot\System32\msvcp140.dll")) {
            Log "  VC++ Runtime installed" $Gn
        } else { die "VC++ Runtime install failed - install it manually: https://aka.ms/vs/17/release/vc_redist.x64.exe" }
    }

    if (-not $hasGit) {
        if (T winget) {
            spn "Install Git (winget)" 2 4 {
                $ErrorActionPreference = "Continue"
                & winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            }
            Refresh-Path
        }
        if (-not (T git)) {
            # winget missing or failed (common in Windows Sandbox): direct download
            spn "Install Git (direct download)" 2 4 {
                $ErrorActionPreference = "Continue"   # native stderr must never terminate the job
                $rel = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest" -Headers @{ "User-Agent" = "VerityJE-Setup" }
                $asset = $null
                if ($rel) { $asset = $rel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1 }
                if (-not $asset) { throw "GitHub API: no Git installer asset found" }
                $tmp = Join-Path $env:TEMP "GitSetup.exe"
                $dlErr = ""
                if (Get-Command curl.exe -EA SilentlyContinue) {
                    $cout = & curl.exe -fsSL -o $tmp $asset.browser_download_url 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) { $dlErr = "curl exit ${LASTEXITCODE}: $cout" }
                } else {
                    try { Invoke-WebRequest $asset.browser_download_url -OutFile $tmp -UseBasicParsing -TimeoutSec 900 -EA Stop } catch { $dlErr = "$_" }
                }
                if ($dlErr) { throw "Git download failed - $dlErr" }
                if (-not (Test-Path $tmp) -or (Get-Item $tmp).Length -lt 10MB) { throw "Git installer missing or truncated" }
                Start-Process -FilePath $tmp -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/SUPPRESSMSGBOXES" -Wait
                Remove-Item $tmp -Force -EA SilentlyContinue
            }
            Refresh-Path
        }
        if (T git) { Log "  Git installed" $Gn; $hasGit = $true } else { die "Git installation failed" }
    }

    if (-not $hasUv) {
        if (T winget) {
            spn "Install uv (winget)" 3 4 {
                $ErrorActionPreference = "Continue"
                & winget install --id astral-sh.uv -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    & winget install --id AstralSoftware.uv -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
                }
            }
            Refresh-Path
        }
        if (-not (T uv)) {
            # winget missing or failed: standalone binary into ~/.local/bin
            spn "Install uv (direct download)" 3 4 {
                $ErrorActionPreference = "Continue"   # native stderr must never terminate the job
                $zip = Join-Path $env:TEMP "uv.zip"
                $dst = "$env:USERPROFILE\.local\bin"
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
                $url = "https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-pc-windows-msvc.zip"
                $dlErr = ""
                if (Get-Command curl.exe -EA SilentlyContinue) {
                    $cout = & curl.exe -fsSL -o $zip $url 2>&1 | Out-String
                    if ($LASTEXITCODE -ne 0) { $dlErr = "curl exit ${LASTEXITCODE}: $cout" }
                } else {
                    try { Invoke-WebRequest $url -OutFile $zip -UseBasicParsing -TimeoutSec 300 -EA Stop } catch { $dlErr = "$_" }
                }
                if ($dlErr) { throw "uv download failed - $dlErr" }
                Expand-Archive $zip $dst -Force
                Remove-Item $zip -Force -EA SilentlyContinue
                if (-not (Test-Path (Join-Path $dst "uv.exe"))) { throw "uv.exe not found after extraction" }
            }
            Add-UserPath "$env:USERPROFILE\.local\bin"
            Refresh-Path
        }
        if (T uv) {
            Log "  uv installed" $Gn; $hasUv = $true
            $bestPy = Get-BestPython; $uvBin = Get-UvToolBin
        } else { die "uv installation failed" }
    }

    if ($svc.W -and -not $ffmpegBin) {
        $installed = $false
        if (T winget) {
            spn "Install ffmpeg (winget)" 4 4 {
                $ErrorActionPreference = "Continue"
                & winget install --id Gyan.FFmpeg.Essentials -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            }
            Refresh-Path
            if (T ffmpeg) { $installed = $true; $ffmpegBin = Split-Path -Parent (Get-Command ffmpeg).Source }
        }
        if (-not $installed) {
            $ffDir = Join-Path $Path "tools\ffmpeg"
            spn "Install ffmpeg (direct download)" 4 4 {
                param($ffDirArg)
                $ErrorActionPreference = "Continue"   # native stderr must never terminate the job
                $zip = Join-Path $env:TEMP "ffmpeg.zip"
                $ok = $false; $lastErr = ""
                foreach ($url in @(
                    "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip",
                    "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
                )) {
                    if (Get-Command curl.exe -EA SilentlyContinue) {
                        $cout = & curl.exe -fsSL --retry 2 -o $zip $url 2>&1 | Out-String
                        if ($LASTEXITCODE -eq 0 -and (Test-Path $zip) -and (Get-Item $zip).Length -gt 10MB) { $ok = $true; break }
                        $lastErr = "curl exit ${LASTEXITCODE}: $cout"
                    } else {
                        try {
                            Invoke-WebRequest $url -OutFile $zip -UseBasicParsing -TimeoutSec 900 -EA Stop
                            if ((Test-Path $zip) -and (Get-Item $zip).Length -gt 10MB) { $ok = $true; break }
                        } catch { $lastErr = "$_" }
                    }
                }
                if (-not $ok) { throw "ffmpeg download failed - $lastErr" }
                if (Test-Path $ffDirArg) { Remove-Item $ffDirArg -Recurse -Force }
                Expand-Archive $zip $ffDirArg -Force
                Remove-Item $zip -Force -EA SilentlyContinue
                $exe = Get-ChildItem $ffDirArg -Recurse -Filter ffmpeg.exe | Select-Object -First 1
                if (-not $exe) { throw "ffmpeg.exe not found after extraction" }
            } -xa @($ffDir)
            $exe = Get-ChildItem $ffDir -Recurse -Filter ffmpeg.exe | Select-Object -First 1
            if ($exe) { $ffmpegBin = $exe.DirectoryName; Log "  ffmpeg installed: $ffmpegBin" $Gn }
            else { die "ffmpeg installation failed" }
        } else {
            Log "  ffmpeg installed" $Gn
        }
    }
}

if (-not $hasUv) { die "uv is required but not available." }

# ================================================================= PHASE 5 ==
# FastKoko (Kokoro TTS)
$kokoroUseGpu = $false
if ($svc.K) {
    $kD   = Join-Path $Path "Kokoro-FastAPI"
    $kPy  = Join-Path $kD ".venv\Scripts\python.exe"
    $kM   = Join-Path $kD "api\src\models\v1_0\kokoro-v1_0.pth"
    $tag  = "v0.6.0"

    phase "FastKoko - Kokoro TTS"

    # 1/5 Repository (pinned tag, recover from broken clones)
    if (Test-Path (Join-Path $kD "api\src\main.py")) {
        Log "  skip  [1/5] Repository (present)" $Dg
    } else {
        if (Test-Path $kD) {
            $bak = "$kD.broken-$(Get-Date -Format 'yyyyMMddHHmmss')"
            Log "  incomplete clone found, moving to: $bak" $Yl
            Move-Item $kD $bak -Force
        }
        spn "Clone repository ($tag)" 1 5 {
            param($P, $tagArg)
            $ErrorActionPreference = "Continue"
            $dst = Join-Path $P "Kokoro-FastAPI"
            & git clone --depth 1 --branch $tagArg https://github.com/remsky/Kokoro-FastAPI.git $dst 2>&1 | Out-Null
            if (-not (Test-Path (Join-Path $dst "api\src\main.py"))) {
                # fallback: full clone then checkout tag
                if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
                & git clone https://github.com/remsky/Kokoro-FastAPI.git $dst 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
                Push-Location $dst
                & git checkout $tagArg 2>&1 | Out-Null
                Pop-Location
            }
            if (-not (Test-Path (Join-Path $dst "api\src\main.py"))) { throw "Clone verification failed" }
        } -xa @($Path, $tag)
    }

    # Patch pyproject: misaki[ja] pulls pyopenjtalk = C++ source build (needs VS Build
    # Tools, missing on normal PCs/Sandbox). Verity JE uses EN/IT voices -> misaki[en].
    # Applied on every run so existing clones are covered too.
    $pyproj = Join-Path $kD "pyproject.toml"
    if (Test-Path $pyproj) {
        $pp = [IO.File]::ReadAllText($pyproj)
        if ($pp -match 'misaki\[[^\]]*\]' -and $Matches[0] -ne 'misaki[en]') {
            $pp = $pp -replace 'misaki\[[^\]]*\]', 'misaki[en]'
            [IO.File]::WriteAllText($pyproj, $pp, (New-Object Text.UTF8Encoding($false)))
            Log "  patched pyproject: misaki[en] (no C++ build deps)" $Dg
        }
    }

    # 2/5 Environment
    if (Test-Path $kPy) {
        Log "  skip  [2/5] Environment (present)" $Dg
    } else {
        Log "  [2/5] Creating Python environment ($bestPy)..." $Wh
        New-Venv $kD $bestPy
        Log "  done  [2/5] Environment" $Gn
    }

    # 3/5 Dependencies: torch first (right index), then the app
    if (Pip-Has $kD "kokoro") {
        Log "  skip  [3/5] Dependencies (present)" $Dg
        $out = & $kPy -c "import torch`nok = torch.cuda.is_available()`nif ok:`n    x = torch.randn(64, 64, device='cuda'); torch.cuda.synchronize(); _ = (x @ x).sum().item()`nprint('RESULT:' + ('cuda' if ok else 'cpu'))" 2>&1 | Out-String
        $kokoroUseGpu = (([regex]::Match($out, 'RESULT:(cuda|cpu)')).Groups[1].Value -eq "cuda")
    } else {
        Log "  [3/5] Installing dependencies (torch index: $(if ($cudaIdx) { $cudaIdx } else { 'cpu' }))..." $Wh
        Repair-Venv $kD
        Pip-Run $kD @("--upgrade", "pip", "setuptools", "wheel", "-q")
        Pip-Run $kD @("cython<3.0", "-q")
        $torchDev = Install-Torch $kD $cudaIdx
        $kokoroUseGpu = ($torchDev -eq "cuda")
        Push-Location $kD
        try { Pip-Run $kD @(".", "-q") } finally { Pop-Location }
        & $kPy -c "import kokoro, misaki, fastapi, uvicorn" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { die "Kokoro dependency verification failed" }
        Log "  done  [3/5] Dependencies ($(if ($kokoroUseGpu) { 'GPU' } else { 'CPU' }))" $Gn
    }

    # eSpeak via bundled espeakng-loader (no admin, no winget needed)
    $espeakLib = ""; $espeakData = ""
    $esOut = & $kPy -c "from espeakng_loader import get_library_path, get_data_path; print(get_library_path()); print(get_data_path())" 2>&1
    if ($LASTEXITCODE -eq 0 -and $esOut.Count -ge 2) {
        $espeakLib = ([string]$esOut[0]).Trim(); $espeakData = ([string]$esOut[1]).Trim()
        Log "  eSpeak: bundled loader OK" $Dg
    } elseif ($espeakSys) {
        $espeakLib = $espeakSys
        Log "  eSpeak: system DLL" $Dg
    } else {
        Log "  WARNING: no eSpeak found - TTS pronunciation may degrade" $Yl
    }

    # 4/5 Model
    if ((Test-Path $kM) -and (Get-Item $kM).Length -gt 100MB) {
        Log "  skip  [4/5] Model (present)" $Dg
    } else {
        Log "  [4/5] Downloading Kokoro model (~350 MB)..." $Wh
        try {
            Download-File "https://huggingface.co/hexgrad/Kokoro-82M/resolve/main/kokoro-v1_0.pth" $kM
            if ((Get-Item $kM).Length -lt 100MB) { throw "model file too small (truncated)" }
            Log "  done  [4/5] Model" $Gn
        } catch { die "Model download failed: $_" }
    }

    # .env inside the repo: makes the server work even when started manually
    $envFile = Join-Path $kD ".env"
    $envContent = @(
        "MODEL_DIR=$(Join-Path $kD 'api\src\models')",
        "VOICES_DIR=$(Join-Path $kD 'api\src\voices\v1_0')",
        "USE_GPU=$(if ($kokoroUseGpu) { 'true' } else { 'false' })"
    )
    [IO.File]::WriteAllLines($envFile, $envContent, (New-Object Text.UTF8Encoding($false)))

    # 5/5 Smoke test: boot the real server, wait for readiness, shut it down
    Log "  [5/5] Smoke test (booting server once)..." $Wh
    $smokePort = 8899
    $savedEnv = @{
        MODEL_DIR = $env:MODEL_DIR; VOICES_DIR = $env:VOICES_DIR; USE_GPU = $env:USE_GPU
        PHONEMIZER_ESPEAK_LIBRARY = $env:PHONEMIZER_ESPEAK_LIBRARY; ESPEAK_DATA_PATH = $env:ESPEAK_DATA_PATH
        PYTHONUTF8 = $env:PYTHONUTF8
    }
    $env:MODEL_DIR = Join-Path $kD "api\src\models"
    $env:VOICES_DIR = Join-Path $kD "api\src\voices\v1_0"
    $env:USE_GPU = if ($kokoroUseGpu) { "true" } else { "false" }
    $env:PYTHONUTF8 = "1"
    if ($espeakLib)  { $env:PHONEMIZER_ESPEAK_LIBRARY = $espeakLib }
    if ($espeakData) { $env:ESPEAK_DATA_PATH = $espeakData }
    $kUvicorn = Join-Path $kD ".venv\Scripts\uvicorn.exe"
    $sOut = Join-Path $logDir "kokoro-smoke.out.log"; $sErr = Join-Path $logDir "kokoro-smoke.err.log"
    Remove-Item $sOut, $sErr -Force -EA SilentlyContinue
    $proc = Start-Process -FilePath $kUvicorn -ArgumentList "api.src.main:app", "--host", "127.0.0.1", "--port", "$smokePort" `
        -WorkingDirectory $kD -WindowStyle Hidden -RedirectStandardOutput $sOut -RedirectStandardError $sErr -PassThru
    $ok = $false
    for ($i = 0; $i -lt 120 -and -not $ok; $i++) {
        Start-Sleep -Seconds 2
        if ($proc.HasExited) { break }
        try {
            $r = Invoke-WebRequest "http://127.0.0.1:$smokePort/docs" -TimeoutSec 2 -UseBasicParsing -EA SilentlyContinue
            if ($r.StatusCode -eq 200) { $ok = $true }
        } catch { }
    }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -EA SilentlyContinue }
    foreach ($key in $savedEnv.Keys) {
        if ($null -ne $savedEnv[$key]) { Set-Item "env:$key" $savedEnv[$key] } else { Remove-Item "env:$key" -EA SilentlyContinue }
    }
    if ($ok) {
        Log "  done  [5/5] Smoke test passed" $Gn
    } else {
        Log "  smoke test log tail:" $Dg
        if (Test-Path $sErr) { Get-Content $sErr -Tail 12 | ForEach-Object { Log "    $_" $Dg } }
        if (Test-Path $sOut) { Get-Content $sOut -Tail 12 | ForEach-Object { Log "    $_" $Dg } }
        die "FastKoko smoke test failed - server did not become ready"
    }

    Set-Location $Path
}

# ================================================================= PHASE 6 ==
# LiteLLM (AI gateway)
$litellmExe = ""
if ($svc.L) {
    phase "LiteLLM - AI Gateway"

    $litellmExe = (Get-Command litellm -EA SilentlyContinue).Source
    if ($litellmExe) {
        Log "  skip  LiteLLM ($litellmExe)" $Dg
    } else {
        spn "Install LiteLLM" 0 0 {
            param($pyArg)
            $ErrorActionPreference = "Continue"
            & uv tool install "litellm[proxy]" --python $pyArg 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                & uv tool install "litellm[proxy]" 2>&1 | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "uv tool install litellm failed" }
            }
        } -xa @($bestPy)
        Refresh-Path
        $uvBin = Get-UvToolBin
    }

    if (-not $litellmExe) {
        $litellmExe = (Get-Command litellm -EA SilentlyContinue).Source
        if (-not $litellmExe -and $uvBin) {
            $cand = Join-Path $uvBin "litellm.exe"
            if (Test-Path $cand) { $litellmExe = $cand }
        }
        if (-not $litellmExe) {
            $cand = "$env:USERPROFILE\.local\bin\litellm.exe"
            if (Test-Path $cand) { $litellmExe = $cand }
        }
    }
    if (-not $litellmExe) { die "LiteLLM installed but executable not found" }
    Log "  LiteLLM: $litellmExe" $Gn
}

# ================================================================= PHASE 7 ==
# Whisper server (STT)
$wModel = "base"
if ($svc.W) {
    $wD = Join-Path $Path "WhisperServer"
    $wPy = Join-Path $wD ".venv\Scripts\python.exe"
    New-Item -ItemType Directory -Path $wD -Force | Out-Null

    if ($hasGPU -and $cudaIdx -and $vramGB -ge 6)     { $wModel = "large-v3-turbo" }
    elseif ($hasGPU -and $cudaIdx -and $vramGB -ge 4) { $wModel = "medium" }
    elseif ($hasGPU -and $cudaIdx)                    { $wModel = "base" }
    elseif ($ramGB -ge 16)                            { $wModel = "base" }
    else                                              { $wModel = "tiny" }

    phase "WhisperServer - STT ($wModel)"

    # 1/3 Environment
    if (Test-Path $wPy) {
        Log "  skip  [1/3] Environment (present)" $Dg
    } else {
        Log "  [1/3] Creating Python environment ($bestPy)..." $Wh
        New-Venv $wD $bestPy
        Log "  done  [1/3] Environment" $Gn
    }

    # 2/3 Dependencies
    if (Pip-Has $wD "whisper") {
        Log "  skip  [2/3] Dependencies (present)" $Dg
    } else {
        Log "  [2/3] Installing dependencies..." $Wh
        Repair-Venv $wD
        Pip-Run $wD @("--upgrade", "pip", "-q")
        $null = Install-Torch $wD $cudaIdx
        Pip-Run $wD @("openai-whisper", "fastapi", "uvicorn[standard]", "python-multipart", "-q")
        & $wPy -c "import whisper, fastapi, uvicorn" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { die "Whisper dependency verification failed" }
        Log "  done  [2/3] Dependencies" $Gn
    }

    # 3/3 Model pre-download (CPU load: device-independent file, works everywhere)
    $wCacheOk = $false
    $cacheDir = Join-Path $env:USERPROFILE ".cache\whisper"
    if (Test-Path $cacheDir) {
        $expected = Get-ChildItem $cacheDir -Filter "*.pt" -EA SilentlyContinue |
            Where-Object { $_.Length -gt 1MB -and $_.Name -match ($wModel -replace '\.', '') }
        if ($expected) { $wCacheOk = $true }
    }
    if ($wCacheOk) {
        Log "  skip  [3/3] Model cached" $Dg
    } else {
        spn "Download Whisper model ($wModel)" 3 3 {
            param($pyArg, $modelArg, $logF)
            $ErrorActionPreference = "Continue"
            & $pyArg -c "import whisper; whisper.load_model('$modelArg', device='cpu'); print('MODEL_OK')" 2>&1 | Out-File $logF -Encoding utf8
            if ($LASTEXITCODE -ne 0) { throw "whisper load_model exited $LASTEXITCODE (see $logF)" }
            $c = Get-Content $logF -Raw -EA SilentlyContinue
            if ($c -notmatch "MODEL_OK") { throw "model check failed (see $logF)" }
        } -xa @($wPy, $wModel, (Join-Path $logDir "whisper-model.log"))
    }

    # ffmpeg warning if still missing at this point
    if (-not $ffmpegBin -and -not (T ffmpeg)) {
        Log "  WARNING: ffmpeg not found - transcription will fail. Re-run setup to install it." $Yl
    }

    Set-Location $Path
}

# ================================================================= PHASE 8 ==
# Ollama (optional, local LLMs)
if ($svc.L -and -not $SkipOllama -and -not $Yes -and -not (T ollama)) {
    phase "Ollama (optional)"
    Write-Host "  Ollama runs LLMs locally (private, offline).`n" -F $Wh
    Write-Host "  [Y] install  [any other key] skip" -F $Dg
    $k = K
    if ($k -and ($k.KeyChar -eq 'y' -or $k.KeyChar -eq 'Y')) {
        $done = $false
        if (T winget) {
            spn "Install Ollama (winget)" 0 0 {
                $ErrorActionPreference = "Continue"
                & winget install --id Ollama.Ollama -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            }
            Refresh-Path
            if (T ollama) { $done = $true }
        }
        if (-not $done) {
            try {
                $tmp = Join-Path $env:TEMP "OllamaSetup.exe"
                Download-File "https://ollama.com/download/ollama-windows-amd64.exe" $tmp
                Start-Process -FilePath $tmp -ArgumentList "/S" -Wait -EA SilentlyContinue
                Remove-Item $tmp -Force -EA SilentlyContinue
                Refresh-Path
                if (T ollama) { $done = $true }
            } catch { Log "  Ollama install failed: $_" $Yl }
        }
        if ($done) { Log "  Ollama installed" $Gn }
        else { Log "  Ollama not installed - install it later from https://ollama.com" $Yl }
    }
}

if ($svc.L -and (T ollama) -and -not $Yes) {
    Write-Host ""
    Write-Host "  Pull a model now? (e.g. llama3.2, qwen2.5, mistral)" -F $Wh
    Write-Host "  Model name (Enter to skip): " -NoNewline -F $Dg
    $modelName = Read-Host
    if ($modelName) {
        spn "Pull $modelName" 0 0 {
            param($mod)
            $ErrorActionPreference = "Continue"
            & ollama pull $mod 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "ollama pull $mod failed" }
        } -xa @($modelName.Trim())
    }
}

# ================================================================= PHASE 9 ==
# Copy launchers if installing outside the repo folder, then write config
phase "Finalizing"

if ($Path -ne $scriptRoot) {
    $toCopy = @("Manager.bat", "Manager.ps1", "FastKoko.bat", "FastKoko.ps1",
                "LiteLLM.bat", "LiteLLM.ps1", "WhisperServer.bat", "WhisperLauncher.ps1")
    foreach ($f in $toCopy) {
        $src = Join-Path $scriptRoot $f
        if (Test-Path $src) { Copy-Item $src (Join-Path $Path $f) -Force }
    }
    $srcSrv = Join-Path $scriptRoot "WhisperServer\server.py"
    if (Test-Path $srcSrv) {
        New-Item -ItemType Directory -Path (Join-Path $Path "WhisperServer") -Force | Out-Null
        Copy-Item $srcSrv (Join-Path $Path "WhisperServer\server.py") -Force
    }
    Log "  launchers copied to $Path" $Dg
}

if (-not $uvBin) { $uvBin = Get-UvToolBin }
if (-not $ffmpegBin -and (T ffmpeg)) { $ffmpegBin = Split-Path -Parent (Get-Command ffmpeg).Source }

Save-Config @{
    WhisperModel   = $wModel
    CudaIndex      = $(if ($cudaIdx) { $cudaIdx } else { "cpu" })
    KokoroUseGpu   = $kokoroUseGpu
    PythonVersion  = $bestPy
    UvBin          = $uvBin
    LiteLLMExe     = $litellmExe
    EspeakLibrary  = $espeakLib
    EspeakDataPath = $espeakData
    FfmpegBin      = $ffmpegBin
    InstallPath    = $Path
}

# ================================================================ PHASE 10 ==
if (-not $Yes) { Clear-Host }
Write-Host "`n  Verity JE Setup - Complete!`n" -F $Yl
Write-Host "  Location: $Path`n" -F $Dg
if ($svc.K) { Write-Host "  FastKoko (TTS) -> http://127.0.0.1:8880/v1/   FastKoko.bat" -F $Gn }
if ($svc.L) { Write-Host "  LiteLLM  (AI)  -> http://127.0.0.1:4000/v1/   LiteLLM.bat" -F $Gn }
if ($svc.W) { Write-Host "  Whisper  (STT) -> http://127.0.0.1:9000/v1/   WhisperServer.bat ($wModel)" -F $Gn }
Write-Host ""
Write-Host "  Logs: $logDir" -F $Dg

if ($Yes) { exit 0 }

Write-Host ""
Write-Host "  [Y] Launch Manager now   [any other key] Exit" -F $Dg
$k = K
if ($k -and ($k.KeyChar -eq 'y' -or $k.KeyChar -eq 'Y')) {
    $mgr = Join-Path $Path "Manager.ps1"
    if (Test-Path $mgr) {
        Start-Process powershell -ArgumentList "-NoProfile", "-EP", "Bypass", "-File", "`"$mgr`""
    }
} else {
    Write-Host "`n  To start later:" -F $Dg
    Write-Host "    cd `"$Path`"" -F $Wh
    Write-Host "    .\Manager.bat" -F $Wh
}
Set-Location $startDir
