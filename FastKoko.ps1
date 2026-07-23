<# FastKoko - Kokoro TTS server (:8880)
   Starts the server hidden, waits for readiness, then offers a voice picker
   and a TTS test. The picked voice is saved as default for next time.
   -ServerOnly: just start the server (used by Manager). #>
[CmdletBinding()]
param([switch]$ServerOnly)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

. (Join-Path $scriptDir "VerityUI.ps1")

Start-VyTranscript "fastkoko-launcher.log"

$cfg = Read-VyConfig $scriptDir

$repoPath = Join-Path $scriptDir "Kokoro-FastAPI"
$venvPy   = Join-Path $repoPath ".venv\Scripts\python.exe"
$uvicorn  = Join-Path $repoPath ".venv\Scripts\uvicorn.exe"
$model    = Join-Path $repoPath "api\src\models\v1_0\kokoro-v1_0.pth"
$logDir   = Join-Path $scriptDir "logs"

Write-VyBanner "FastKoko - Kokoro TTS" "OpenAI-compatible TTS on :8880"

# ------------------------------------------------------------- preflight ----
foreach ($check in @(
    @((Test-Path (Join-Path $repoPath "api\src\main.py")), "Kokoro-FastAPI not found. Run Setup.bat first."),
    @((Test-Path $venvPy),  "Python environment missing. Run Setup.bat first."),
    @((Test-Path $uvicorn), "uvicorn missing in venv. Run Setup.bat to repair."),
    @((Test-Path $model),   "Kokoro model file missing. Run Setup.bat to download it.")
)) {
    if (-not $check[0]) { Write-VyErr $check[1]; Stop-VyTranscript; Read-Host "Press Enter"; exit 1 }
}

$alreadyUp = Test-VyPort 8880
if ($alreadyUp -and $ServerOnly) {
    Write-VyWarn "port 8880 already in use - the server is probably already running"
    Write-VyInfo "API: http://127.0.0.1:8880/v1/"
    Stop-VyTranscript; exit 0
}

if (-not $alreadyUp) {
    # ------------------------------------------------------- environment ----
    $env:PYTHONUTF8 = "1"
    $env:MODEL_DIR  = Join-Path $repoPath "api\src\models"
    $env:VOICES_DIR = Join-Path $repoPath "api\src\voices\v1_0"
    $env:PYTHONPATH = $repoPath

    $useGpu = Get-VyCfg $cfg "KokoroUseGpu" $false
    $env:USE_GPU = if ($useGpu -eq $true -or "$useGpu" -eq "true") { "true" } else { "false" }

    $esLib  = Get-VyCfg $cfg "EspeakLibrary"
    $esData = Get-VyCfg $cfg "EspeakDataPath"
    if (-not $esLib) {
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

    # ------------------------------------------------------------ launch ----
    $outLog = Join-Path $logDir "fastkoko-server.out.log"
    $errLog = Join-Path $logDir "fastkoko-server.err.log"
    Remove-Item $outLog, $errLog -Force -EA SilentlyContinue

    Write-VyInfo "starting server (GPU: $env:USE_GPU)..."
    $proc = Start-Process -FilePath $uvicorn `
        -ArgumentList "api.src.main:app", "--host", "127.0.0.1", "--port", "8880" `
        -WorkingDirectory $repoPath -WindowStyle Hidden `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru

    Write-VyInfo "waiting for readiness (first start warms up the model)..."
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
        Write-VyErr "server did not start. Last log lines:"
        Get-VyLogTail $errLog 12
        Get-VyLogTail $outLog 6
        Stop-VyTranscript; Read-Host "Press Enter"; exit 1
    }
}

Write-VyOk "SERVER READY"
Write-VyInfo "API: http://127.0.0.1:8880/v1/"
Write-VyInfo "Web: http://127.0.0.1:8880/web/"

if ($ServerOnly) { Stop-VyTranscript; exit 0 }

# ---------------------------------------------------- voice picker + test ---
Write-Host ""
try {
    $vd = Invoke-RestMethod "http://127.0.0.1:8880/v1/audio/voices" -TimeoutSec 10
    $names = @()
    foreach ($v in @($vd.voices)) {
        if ($v -is [string]) { $names += $v }
        elseif ($v.id) { $names += [string]$v.id }
    }
} catch {
    Write-VyErr "could not load voices: $_"
    Stop-VyTranscript; Read-Host "Press Enter"; exit 1
}

if ($names.Count -eq 0) { Write-VyErr "no voices reported by the server"; Stop-VyTranscript; Read-Host "Press Enter"; exit 1 }

$italian = @($names | Where-Object { $_ -match '^i[fm]_' })
$english = @($names | Where-Object { $_ -match '^[abef][fm]_' })
$other   = @($names | Where-Object { $_ -notmatch '^i[fm]_' -and $_ -notmatch '^[abef][fm]_' })
$all = @($italian) + @($english) + @($other)

$savedVoice = Get-VyCfg $cfg "KokoroVoice"
if (-not $savedVoice -or $all -notcontains $savedVoice) { $savedVoice = $all[0] }

Write-VyRule "Voices"
$opt = 1
if ($italian.Count) { Write-Host ""; Write-Host "  ITALIAN" -F $VyColor.Accent; foreach ($v in $italian) { $m = if ($v -eq $savedVoice) { " *" } else { "" }; Write-Host ("  [{0}] {1}{2}" -f $opt, $v, $m) -F White; $opt++ } }
if ($english.Count) { Write-Host ""; Write-Host "  ENGLISH" -F $VyColor.Accent; foreach ($v in $english) { $m = if ($v -eq $savedVoice) { " *" } else { "" }; Write-Host ("  [{0}] {1}{2}" -f $opt, $v, $m) -F White; $opt++ } }
if ($other.Count)   { Write-Host ""; Write-Host "  OTHER" -F $VyColor.Accent;   foreach ($v in $other)   { $m = if ($v -eq $savedVoice) { " *" } else { "" }; Write-Host ("  [{0}] {1}{2}" -f $opt, $v, $m) -F White; $opt++ } }

Write-Host ""
Write-Host "  (* = saved)  [1-9] pick   [Enter] keep $savedVoice" -F $VyColor.Dim
$k = Read-VyKey
Write-Host ""
$voice = $savedVoice
if ($null -ne $k -and $k.KeyChar -match '^\d$') {
    $ix = [int]"$($k.KeyChar)" - 1
    if ($ix -ge 0 -and $ix -lt [Math]::Min(9, $all.Count)) { $voice = $all[$ix] }
}
Write-VyOk "voice: $voice"
if ($voice -ne (Get-VyCfg $cfg "KokoroVoice")) { Set-VyCfg $scriptDir "KokoroVoice" $voice }
Write-VyInfo "note: the Verity mod sends its own voice per request - this is the local default"

Write-Host ""
Write-Host "  Text (empty line to submit):" -F $VyColor.Title
$lines = @()
while ($true) {
    $line = Read-Host "  >"
    if (-not $line.Trim()) { break }
    $lines += $line
}
$text = $lines -join "`n"
if (-not $text.Trim()) { Write-VyWarn "no text entered"; Stop-VyTranscript; Read-Host "Press Enter"; exit 0 }

Write-VyInfo "generating..."
try {
    $body = @{ model = "kokoro"; voice = $voice; input = $text; response_format = "mp3" } | ConvertTo-Json
    $resp = Invoke-WebRequest "http://127.0.0.1:8880/v1/audio/speech" -Method Post -ContentType "application/json" -Body $body -TimeoutSec 180 -UseBasicParsing
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $desktop) { $desktop = $scriptDir }
    $outFile = Join-Path $desktop "tts_$voice`_$ts.mp3"
    [IO.File]::WriteAllBytes($outFile, $resp.Content)
    Write-VyOk "saved: $outFile"
} catch {
    Write-VyErr "generation failed: $_"
}
Stop-VyTranscript
Read-Host "Press Enter"
