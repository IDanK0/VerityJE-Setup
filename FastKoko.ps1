<# FastKoko - Kokoro TTS server (:8880)
   Starts the Kokoro-FastAPI server hidden, waits for readiness, then offers
   an optional interactive TTS test. Run with -ServerOnly to skip the test. #>
[CmdletBinding()]
param([switch]$ServerOnly)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

# ------------------------------------------------------------ config load ---
$cfg = @{}
$cfgPath = Join-Path $scriptDir "config.psd1"
if (Test-Path $cfgPath) { try { $cfg = Import-PowerShellDataFile $cfgPath } catch { } }
function Cfg($name, $default = "") {
    if ($cfg -and $cfg.Contains($name) -and $null -ne $cfg[$name] -and "$($cfg[$name])" -ne "") { return $cfg[$name] }
    return $default
}

$repoPath = Join-Path $scriptDir "Kokoro-FastAPI"
$venvPy   = Join-Path $repoPath ".venv\Scripts\python.exe"
$uvicorn  = Join-Path $repoPath ".venv\Scripts\uvicorn.exe"
$model    = Join-Path $repoPath "api\src\models\v1_0\kokoro-v1_0.pth"
$logDir   = Join-Path $scriptDir "logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  FastKoko - Kokoro TTS  :8880" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

# ------------------------------------------------------------- preflight ----
foreach ($check in @(
    @((Test-Path (Join-Path $repoPath "api\src\main.py")), "Kokoro-FastAPI not found. Run Setup.bat first."),
    @((Test-Path $venvPy),  "Python environment missing. Run Setup.bat first."),
    @((Test-Path $uvicorn), "uvicorn missing in venv. Run Setup.bat to repair."),
    @((Test-Path $model),   "Kokoro model file missing. Run Setup.bat to download it.")
)) {
    if (-not $check[0]) { Write-Host "ERROR: $($check[1])" -F Red; Read-Host "Press Enter"; exit 1 }
}

$busy = Get-NetTCPConnection -LocalPort 8880 -State Listen -EA SilentlyContinue
if ($busy) {
    Write-Host "Port 8880 is already in use - the server is probably already running." -F Yellow
    Write-Host "API: http://127.0.0.1:8880/v1/" -F Yellow
    Read-Host "Press Enter"; exit 0
}

# ----------------------------------------------------------- environment ----
$env:PYTHONUTF8 = "1"
$env:MODEL_DIR  = Join-Path $repoPath "api\src\models"
$env:VOICES_DIR = Join-Path $repoPath "api\src\voices\v1_0"
$env:PYTHONPATH = $repoPath

$useGpu = Cfg "KokoroUseGpu" $false
$env:USE_GPU = if ($useGpu -eq $true -or "$useGpu" -eq "true") { "true" } else { "false" }

$esLib  = Cfg "EspeakLibrary"
$esData = Cfg "EspeakDataPath"
if (-not $esLib) {
    # resolve from the venv's bundled espeakng-loader, or fall back to system eSpeak
    $esOut = & $venvPy -c "from espeakng_loader import get_library_path, get_data_path; print(get_library_path()); print(get_data_path())" 2>&1
    if ($LASTEXITCODE -eq 0 -and $esOut.Count -ge 2) {
        $esLib = ([string]$esOut[0]).Trim(); $esData = ([string]$esOut[1]).Trim()
    } else {
        foreach ($p in @("$env:ProgramFiles\eSpeak NG\libespeak-ng.dll", "${env:ProgramFiles(x86)}\eSpeak NG\libespeak-ng.dll")) {
            if ($p -and (Test-Path $p)) { $esLib = $p; break }
        }
    }
}
if ($esLib -and (Test-Path $esLib)) { $env:PHONEMIZER_ESPEAK_LIBRARY = $esLib }
if ($esData -and (Test-Path $esData)) { $env:ESPEAK_DATA_PATH = $esData }

# --------------------------------------------------------------- launch -----
$outLog = Join-Path $logDir "fastkoko-server.out.log"
$errLog = Join-Path $logDir "fastkoko-server.err.log"
Remove-Item $outLog, $errLog -Force -EA SilentlyContinue

Write-Host "Starting server (GPU: $env:USE_GPU)..." -F Yellow
$proc = Start-Process -FilePath $uvicorn `
    -ArgumentList "api.src.main:app", "--host", "127.0.0.1", "--port", "8880" `
    -WorkingDirectory $repoPath -WindowStyle Hidden `
    -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru

Write-Host "Waiting for readiness (first start warms up the model)..." -F Yellow
$ready = $false
for ($i = 0; $i -lt 90 -and -not $ready; $i++) {
    Start-Sleep -Seconds 2
    if ($proc.HasExited) { break }
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:8880/docs" -TimeoutSec 2 -UseBasicParsing -EA SilentlyContinue
        if ($r.StatusCode -eq 200) { $ready = $true }
    } catch { }
}

if (-not $ready) {
    Write-Host "ERROR: server did not start. Last log lines:" -F Red
    foreach ($f in @($errLog, $outLog)) {
        if (Test-Path $f) { Get-Content $f -Tail 12 | ForEach-Object { Write-Host "  $_" -F DarkGray } }
    }
    Read-Host "Press Enter"; exit 1
}

Write-Host "SERVER READY!" -F Green
Write-Host "API: http://127.0.0.1:8880/v1/" -F Yellow
Write-Host "Web: http://127.0.0.1:8880/web/" -F DarkGray
Write-Host "Logs: $logDir" -F DarkGray

if ($ServerOnly) { exit 0 }

# ---------------------------------------------------- interactive TTS test --
Write-Host ""
try {
    $vd = Invoke-RestMethod "http://127.0.0.1:8880/v1/audio/voices" -TimeoutSec 10
    $names = @()
    foreach ($v in @($vd.voices)) {
        if ($v -is [string]) { $names += $v }
        elseif ($v.id) { $names += [string]$v.id }
    }
} catch {
    Write-Host "Could not load voices: $_" -F Red
    Read-Host "Press Enter"; exit 1
}

if ($names.Count -eq 0) { Write-Host "No voices reported by the server." -F Red; Read-Host "Press Enter"; exit 1 }

$italian = @($names | Where-Object { $_ -match '^i[fm]_' })
$english = @($names | Where-Object { $_ -match '^[abef]_' })
$other   = @($names | Where-Object { $_ -notmatch '^i[fm]_' -and $_ -notmatch '^[abef]_' })
$all = @($italian) + @($english) + @($other)

$opt = 1
if ($italian.Count) { Write-Host ""; Write-Host "[ITALIAN]" -F Magenta; foreach ($v in $italian) { Write-Host "  $opt. $v"; $opt++ } }
if ($english.Count) { Write-Host ""; Write-Host "[ENGLISH]" -F Magenta; foreach ($v in $english) { Write-Host "  $opt. $v"; $opt++ } }
if ($other.Count)   { Write-Host ""; Write-Host "[OTHER]" -F Magenta;   foreach ($v in $other)   { Write-Host "  $opt. $v"; $opt++ } }

$default = $all[0]
Write-Host ""
$choice = Read-Host "Voice [1 = $default]"
$voice = $default
if ($choice -match '^\d+$') {
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $all.Count) { $voice = $all[$idx] }
} elseif ($choice.Trim()) { $voice = $choice.Trim() }
Write-Host "Voice: $voice" -F Green

Write-Host ""
Write-Host "Text (empty line to submit):" -F Yellow
$lines = @()
while ($true) {
    $line = Read-Host "  >"
    if (-not $line.Trim()) { break }
    $lines += $line
}
$text = $lines -join "`n"
if (-not $text.Trim()) { Write-Host "No text entered." -F Yellow; Read-Host "Press Enter"; exit 0 }

Write-Host "Generating..." -F Yellow
try {
    $body = @{ model = "kokoro"; voice = $voice; input = $text; response_format = "mp3" } | ConvertTo-Json
    $resp = Invoke-WebRequest "http://127.0.0.1:8880/v1/audio/speech" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 180
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) { $desktop = $scriptDir }
    $outFile = Join-Path $desktop "tts_$voice`_$ts.mp3"
    [IO.File]::WriteAllBytes($outFile, $resp.Content)
    Write-Host "Saved: $outFile" -F Green
} catch {
    Write-Host "ERROR: $_" -F Red
}
Read-Host "Press Enter"
