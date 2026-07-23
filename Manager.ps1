<# Verity JE Manager - live control panel for the AI services.
   Single-key commands (no Enter), live status, failure log tails. #>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

. (Join-Path $scriptDir "VerityUI.ps1")

$services = [ordered]@{
    F = @{ name = "FastKoko (TTS)"; port = 8880; launcher = "FastKoko.ps1";
           check = "Kokoro-FastAPI\.venv\Scripts\uvicorn.exe";
           sLog = "fastkoko-server.err.log"; lLog = "fastkoko-launcher.log" }
    I = @{ name = "LiteLLM (AI)";   port = 4000; launcher = "LiteLLM.ps1";
           check = "LiteLLM\.venv\Scripts\litellm.exe";
           sLog = "litellm-server.err.log"; lLog = "litellm-launcher.log" }
    W = @{ name = "Whisper (STT)";  port = 9000; launcher = "WhisperLauncher.ps1";
           check = "WhisperServer\.venv\Scripts\python.exe";
           sLog = "whisper-server.err.log"; lLog = "whisper-launcher.log" }
}
$pending = @{}   # key -> @{ proc; since; failedShown }

function Test-Installed($key) {
    $svc = $services[$key]
    if ($svc.check -and (Test-Path (Join-Path $scriptDir $svc.check))) { return $true }
    if ($key -eq "I") {
        # LiteLLM may also live in a previous uv-tool install
        $cfg = Read-VyConfig $scriptDir
        if ($cfg.LiteLLMExe -and (Test-Path $cfg.LiteLLMExe)) { return $true }
        if (Get-Command litellm -EA SilentlyContinue) { return $true }
    }
    return $false
}

function Test-LiteLLMReady {
    # can LiteLLM start unattended? saved model + (key present | ollama model | ollama app)
    $cfg = Read-VyConfig $scriptDir
    $model = Get-VyCfg $cfg "LiteLLMModel"
    $ollamaModel = $model -like "ollama/*"
    if (-not $model) {
        # no saved model: ready only if some provider key exists or ollama is installed
        foreach ($k in @("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "GROQ_API_KEY")) {
            foreach ($scope in @("Process", "User", "Machine")) {
                if ([Environment]::GetEnvironmentVariable($k, $scope)) { return $true }
            }
        }
        return [bool](Get-Command ollama -EA SilentlyContinue)
    }
    if ($ollamaModel) { return [bool](Get-Command ollama -EA SilentlyContinue) }
    $keyFor = @{ "gpt*" = "OPENAI_API_KEY"; "claude*" = "ANTHROPIC_API_KEY"; "gemini*" = "GEMINI_API_KEY"; "groq/*" = "GROQ_API_KEY" }
    foreach ($pat in $keyFor.Keys) {
        if ($model -like $pat) {
            foreach ($scope in @("Process", "User", "Machine")) {
                if ([Environment]::GetEnvironmentVariable($keyFor[$pat], $scope)) { return $true }
            }
            return $false
        }
    }
    return $true   # custom model id: let it try
}

function Get-ServiceState($key) {
    $svc = $services[$key]
    if (Test-VyPort $svc.port) { return "RUNNING", "Green" }
    if ($pending.ContainsKey($key)) {
        $p = $pending[$key]
        if (-not $p.proc.HasExited) { return "STARTING", "Yellow" }
        if (-not $p.tail) {
            # capture failure log tail once; dashboard renders it under the row
            $lines = @()
            foreach ($f in @($svc.lLog, $svc.sLog)) {
                $fp = Join-Path $scriptDir "logs\$f"
                if (Test-Path $fp) { $lines += @(Get-Content $fp -Tail 5 -Encoding UTF8 -EA SilentlyContinue) }
            }
            $p.tail = $lines
        }
        return "FAILED", "Red"
    }
    if (Test-Installed $key) { return "off", "DarkGray" }
    return "MISSING", "Red"
}

function Show-Dashboard($states) {
    Clear-Host
    Write-VyBanner "Verity JE - Manager" "AI backend control panel"
    Write-VyRule "Services"
    Write-Host ""
    $cfg = Read-VyConfig $scriptDir
    foreach ($key in $services.Keys) {
        $svc = $services[$key]
        $state = $states[$key][0]; $color = $states[$key][1]
        $note = ""
        if ($key -eq "F" -and $cfg.KokoroVoice)  { $note = $cfg.KokoroVoice }
        if ($key -eq "I" -and $cfg.LiteLLMModel) { $note = $cfg.LiteLLMModel }
        if ($key -eq "W" -and $cfg.WhisperModel) { $note = $cfg.WhisperModel }
        Write-Host ("   [{0}] " -f $key) -F $VyColor.Title -NoNewline
        Write-Host ("{0,-16}" -f $svc.name) -F White -NoNewline
        Write-Host ("{0,-10}" -f $state) -F $color -NoNewline
        Write-Host (":{0,-6}" -f $svc.port) -F $VyColor.Dim -NoNewline
        Write-Host ("http://127.0.0.1:{0}/v1/" -f $svc.port) -F $VyColor.Dim -NoNewline
        if ($note) { Write-Host ("  {0}" -f $note) -F $VyColor.Dim } else { Write-Host "" }
        if ($state -eq "FAILED" -and $pending.ContainsKey($key) -and $pending[$key].tail) {
            foreach ($l in $pending[$key].tail) {
                Write-Host ("        {0}" -f $l) -F $VyColor.Dim
            }
        }
    }
    Write-Host ""
    Write-VyRule
    Write-VyKeys @(@("S","Start all"), @("A","Stop all"), @("R","Restart all"), @("F/I/W","Toggle one"), @("C","Configure"), @("Q","Quit"))
    if ($services.I -and -not (Test-VyPort 4000) -and -not (Test-LiteLLMReady)) {
        Write-Host ""
        Write-VyWarn "LiteLLM not configured: press [C] to pick model + API key"
    }
}

function Start-VerityService($key) {
    $svc = $services[$key]
    if (Test-VyPort $svc.port) { return }
    if (-not (Test-Installed $key)) {
        Write-Host ""; Write-VyErr "$($svc.name): not installed - run Setup.bat"; Start-Sleep 2; return
    }
    if ($key -eq "I" -and -not (Test-LiteLLMReady)) {
        Write-Host ""; Write-VyWarn "LiteLLM needs configuration first - press [C]"; Start-Sleep 2; return
    }
    $launcher = Join-Path $scriptDir $svc.launcher
    if (-not (Test-Path $launcher)) { Write-Host ""; Write-VyErr "launcher missing: $($svc.launcher)"; Start-Sleep 2; return }
    $proc = Start-Process powershell -ArgumentList "-NoProfile", "-EP", "Bypass", "-File", "`"$launcher`"", "-ServerOnly" -WindowStyle Minimized -PassThru
    $pending[$key] = @{ proc = $proc; since = Get-Date; tail = $null }
}

function Stop-ProcessTree($rootId) {
    # kill a process and all its descendants (launchers spawn server children;
    # torch/uvicorn spawn grandchildren - plain kill leaves orphans)
    try {
        $kids = Get-CimInstance Win32_Process -Filter "ParentProcessId=$rootId" -EA SilentlyContinue
        foreach ($k in $kids) { Stop-ProcessTree $k.ProcessId }
        Stop-Process -Id $rootId -Force -EA SilentlyContinue
    } catch { }
}

function Stop-VerityService($key) {
    $svc = $services[$key]
    if ($pending.ContainsKey($key)) {
        try { if (-not $pending[$key].proc.HasExited) { Stop-ProcessTree $pending[$key].proc.Id } } catch { }
        $pending.Remove($key)
    }
    if (-not (Test-VyPort $svc.port)) { return }
    Get-NetTCPConnection -LocalPort $svc.port -State Listen -EA SilentlyContinue | ForEach-Object {
        Stop-ProcessTree $_.OwningProcess
    }
}

function Toggle-VerityService($key) {
    if (Test-VyPort $services[$key].port) { Stop-VerityService $key }
    else { Start-VerityService $key }
}

function Invoke-Configure {
    # configuration center: FastKoko voice, LiteLLM model/key, Whisper model
    $cfg = Read-VyConfig $scriptDir
    while ($true) {
        Clear-Host
        Write-VyBanner "Configure" "saved to config.psd1 - applied on next (re)start"
        Write-VyRule "Current settings"
        Write-Host ""
        Write-Host ("   [F] FastKoko voice   ") -F $VyColor.Title -NoNewline
        Write-Host ("{0}" -f $(if ($cfg.KokoroVoice) { $cfg.KokoroVoice } else { "(not set)" })) -F White
        Write-Host ("   [I] LiteLLM model    ") -F $VyColor.Title -NoNewline
        Write-Host ("{0}" -f $(if ($cfg.LiteLLMModel) { $cfg.LiteLLMModel } else { "(not set)" })) -F White
        Write-Host ("   [W] Whisper model    ") -F $VyColor.Title -NoNewline
        Write-Host ("{0}" -f $(if ($cfg.WhisperModel) { $cfg.WhisperModel } else { "(not set)" })) -F White
        Write-Host ("   [M] Microphone       ") -F $VyColor.Title -NoNewline
        Write-Host ("{0}" -f $(if ($cfg.MicDevice) { $cfg.MicDevice } else { "(not set - used by the mic test)" })) -F White
        Write-Host ""
        Write-VyRule
        Write-VyKeys @(@("F","voice"), @("I","LLM + API key"), @("W","Whisper model"), @("M","microphone"), @("B","back"))
        $k = Read-VyKey
        if ($null -eq $k) { return }
        switch ([string]$k.KeyChar.ToString().ToUpper()) {
            "F" { Edit-FastKokoVoice; $cfg = Read-VyConfig $scriptDir }
            "I" {
                $bat = Join-Path $scriptDir "LiteLLM.bat"
                if (Test-Path $bat) { Start-Process cmd -ArgumentList "/c", "`"$bat`"" -Wait }
                $cfg = Read-VyConfig $scriptDir
            }
            "W" { Edit-WhisperModel; $cfg = Read-VyConfig $scriptDir }
            "M" { Edit-Microphone; $cfg = Read-VyConfig $scriptDir }
            "B" { return }
            default { }
        }
    }
}

function Edit-Microphone {
    # the mod uses the Windows DEFAULT recording device; here you pick the device
    # for the built-in mic test (mic -> wav -> Whisper) and save it for later.
    $cfg = Read-VyConfig $scriptDir
    $ffBin = Get-VyCfg $cfg "FfmpegBin"
    Clear-Host
    Write-VyBanner "Microphone" "pick the capture device used by the mic test"

    Write-VyInfo "enumerating DirectShow devices..."
    $devices = @(Get-VyAudioDevices $ffBin)
    if (-not $devices.Count) {
        Write-VyErr "no audio devices found (or ffmpeg missing - run Setup.bat)"
        Start-Sleep 2; return
    }
    $saved = Get-VyCfg $cfg "MicDevice" $devices[0]
    if ($devices -notcontains $saved) { $saved = $devices[0] }
    Write-Host ""
    for ($i = 0; $i -lt [Math]::Min(9, $devices.Count); $i++) {
        $m = if ($devices[$i] -eq $saved) { " *" } else { "" }
        Write-Host ("   [{0}] {1}{2}" -f ($i + 1), $devices[$i], $m) -F White
    }
    Write-Host ""
    Write-VyKeys @(@("1-$([Math]::Min(9, $devices.Count))","pick"), @("T","test mic"), @("S","Windows sound settings"), @("B","back"))
    $k = Read-VyKey
    if ($null -eq $k) { return }
    $ch = [string]$k.KeyChar.ToString().ToUpper()
    if ($ch -match '^\d$') {
        $ix = [int]$ch - 1
        if ($ix -ge 0 -and $ix -lt [Math]::Min(9, $devices.Count)) {
            $saved = $devices[$ix]
            Set-VyCfg $scriptDir "MicDevice" $saved
            Write-Host ""; Write-VyOk "microphone saved: $saved"
        }
    } elseif ($ch -eq "S") {
        Start-Process "ms-settings:sound"
    } elseif ($ch -eq "T") {
        Write-Host ""
        if (-not (Test-VyPort 9000)) {
            Write-VyWarn "Whisper is not running - start it first ([W] in the dashboard)"
            Start-Sleep 2; return
        }
        Write-Host "  Recording 5 seconds from:" -F $VyColor.Title
        Write-Host "  $saved" -F White
        Write-Host "  Speak now..." -F $VyColor.Accent
        for ($c = 5; $c -ge 1; $c--) { Write-Host ("`r  rec " + ("#" * (6 - $c)) + ("." * $c) + " $c ") -NoNewline -F $VyColor.Warn; Start-Sleep 1 }
        Write-Host ""
        $r = Invoke-VyMicTest $saved 9000 $ffBin
        Write-Host ""
        if ($r.ok) { Write-VyOk "Whisper heard: $($r.text)" }
        else { Write-VyErr $r.error }
        Write-Host ""
        Write-Host "  Press any key..." -F $VyColor.Dim
        $null = Read-VyKey
    }
}

function Edit-FastKokoVoice {
    $voiceDir = Join-Path $scriptDir "Kokoro-FastAPI\api\src\voices\v1_0"
    if (-not (Test-Path $voiceDir)) { Write-Host ""; Write-VyErr "Kokoro-FastAPI not installed - run Setup.bat"; Start-Sleep 2; return }
    $names = @(Get-ChildItem $voiceDir -Filter "*.pt" -EA SilentlyContinue | ForEach-Object { $_.BaseName } | Sort-Object)
    if (-not $names.Count) { Write-Host ""; Write-VyErr "no voice files found"; Start-Sleep 2; return }

    $cfg = Read-VyConfig $scriptDir
    $saved = Get-VyCfg $cfg "KokoroVoice" $names[0]
    $italian = @($names | Where-Object { $_ -match '^i[fm]_' })
    $english = @($names | Where-Object { $_ -match '^[abef][fm]_' })
    $other   = @($names | Where-Object { $_ -notmatch '^i[fm]_' -and $_ -notmatch '^[abef][fm]_' })
    $all = @($italian) + @($english) + @($other)

    Clear-Host
    Write-VyBanner "FastKoko voice" "the mod sends its own voice per request; this is the local default"
    $opt = 1
    if ($italian.Count) { Write-Host "  ITALIAN" -F $VyColor.Accent; foreach ($v in $italian) { $m = if ($v -eq $saved) { " *" } else { "" }; Write-Host ("  {0,2}. {1}{2}" -f $opt, $v, $m) -F White; $opt++ } }
    if ($english.Count) { Write-Host "  ENGLISH" -F $VyColor.Accent; foreach ($v in $english) { $m = if ($v -eq $saved) { " *" } else { "" }; Write-Host ("  {0,2}. {1}{2}" -f $opt, $v, $m) -F White; $opt++ } }
    if ($other.Count)   { Write-Host "  OTHER" -F $VyColor.Accent;   foreach ($v in $other)   { $m = if ($v -eq $saved) { " *" } else { "" }; Write-Host ("  {0,2}. {1}{2}" -f $opt, $v, $m) -F White; $opt++ } }
    Write-Host ""
    Write-Host "  (* = current)  number or name, [Enter] keep $saved" -F $VyColor.Dim
    Write-Host "  > " -NoNewline -F $VyColor.Title
    $vc = Read-Host
    $pick = $saved
    if ($vc -match '^\d+$') {
        $ix = [int]$vc - 1
        if ($ix -ge 0 -and $ix -lt $all.Count) { $pick = $all[$ix] }
    } elseif ($vc.Trim() -and ($all -contains $vc.Trim())) { $pick = $vc.Trim() }
    Set-VyCfg $scriptDir "KokoroVoice" $pick
    Write-Host ""; Write-VyOk "voice saved: $pick"; Start-Sleep 1
}

function Edit-WhisperModel {
    $models = @(
        @("tiny",           "~75 MB",   "fastest, lowest accuracy - low-end CPUs"),
        @("base",           "~145 MB",  "good on CPU"),
        @("small",          "~465 MB",  "better, 2+ GB VRAM / decent CPU"),
        @("medium",         "~1.5 GB",  "great, 4-6 GB VRAM"),
        @("large-v3-turbo", "~1.6 GB",  "best speed/quality ratio, 6+ GB VRAM"),
        @("large-v3",       "~2.9 GB",  "most accurate, 8+ GB VRAM")
    )
    $cfg = Read-VyConfig $scriptDir
    $saved = Get-VyCfg $cfg "WhisperModel" "base"
    $cacheDir = Join-Path $env:USERPROFILE ".cache\whisper"

    Clear-Host
    Write-VyBanner "Whisper model" "larger = more accurate, slower - applied on next start"
    Write-Host ""
    for ($i = 0; $i -lt $models.Count; $i++) {
        $id = $models[$i][0]
        $m = if ($id -eq $saved) { " *" } else { "" }
        $cached = $false
        if (Test-Path $cacheDir) {
            $cached = ($null -ne (Get-ChildItem $cacheDir -Filter "*.pt" -EA SilentlyContinue | Where-Object { $_.Name -like "*$id*" }))
        }
        $note = if ($cached) { "cached" } else { "will download on first use" }
        Write-Host ("   [{0}] " -f ($i + 1)) -F $VyColor.Title -NoNewline
        Write-Host ("{0,-16}" -f $id) -F White -NoNewline
        Write-Host ("{0,-9}" -f $models[$i][1]) -F $VyColor.Dim -NoNewline
        Write-Host ("{0,-44}" -f $models[$i][2]) -F $VyColor.Dim -NoNewline
        Write-Host $note -F $(if ($cached) { $VyColor.Ok } else { $VyColor.Warn }) -NoNewline
        Write-Host $m -F $VyColor.Accent
    }
    Write-Host ""
    Write-VyKeys @(@("1-$($models.Count)","pick"), @("Enter","keep $saved"))
    $k = Read-VyKey
    if ($null -ne $k -and $k.KeyChar -match '^\d$') {
        $ix = [int]"$($k.KeyChar)" - 1
        if ($ix -ge 0 -and $ix -lt $models.Count) {
            $pick = $models[$ix][0]
            Set-VyCfg $scriptDir "WhisperModel" $pick
            Write-Host ""; Write-VyOk "Whisper model saved: $pick (applies on next start)"
            if (Test-VyPort 9000) { Write-VyWarn "Whisper is RUNNING - toggle [W] to apply now" }
            Start-Sleep 2
        }
    }
}

function Get-States {
    $states = @{}
    foreach ($key in $services.Keys) { $states[$key] = @(Get-ServiceState $key) }
    return $states
}

$redirected = [Console]::IsInputRedirected

if ($redirected) {
    # line-input mode (piped/automation): one render, then classic prompt loop
    Show-Dashboard (Get-States)
    while ($true) {
        $c = (Read-Host "Choice").ToUpper()
        switch ($c) {
            "S" { foreach ($k in $services.Keys) { Start-VerityService $k } }
            "A" { foreach ($k in $services.Keys) { Stop-VerityService $k } }
            "R" { foreach ($k in $services.Keys) { Stop-VerityService $k }; foreach ($k in $services.Keys) { Start-VerityService $k } }
            "F" { Toggle-VerityService "F" }
            "I" { Toggle-VerityService "I" }
            "W" { Toggle-VerityService "W" }
            "Q" { break }
            default { }
        }
        if ($c -eq "Q") { break }
        Start-Sleep 1
        Show-Dashboard (Get-States)
    }
    foreach ($k in $services.Keys) { Stop-VerityService $k }
    exit 0
}

# interactive: flicker-free - redraw ONLY when a state actually changed or after an action
$prev = @{}
$forceRedraw = $true
:main while ($true) {
    $states = Get-States
    $changed = $forceRedraw
    foreach ($key in $services.Keys) {
        if (-not $prev.ContainsKey($key) -or $prev[$key][0] -ne $states[$key][0]) { $changed = $true; break }
    }
    if ($changed) {
        Show-Dashboard $states
        $prev = @{}; foreach ($key in $states.Keys) { $prev[$key] = $states[$key] }
        $forceRedraw = $false
    }
    $k = Read-VyKeyTimeout 1500
    if ($null -eq $k) { continue }   # silent poll, no redraw unless something changed
    $forceRedraw = $true
    switch ([string]$k.KeyChar.ToString().ToUpper()) {
        "S" { foreach ($key in $services.Keys) { Start-VerityService $key } }
        "A" { foreach ($key in $services.Keys) { Stop-VerityService $key } }
        "R" { foreach ($key in $services.Keys) { Stop-VerityService $key }; foreach ($key in $services.Keys) { Start-VerityService $key } }
        "F" { Toggle-VerityService "F" }
        "I" { Toggle-VerityService "I" }
        "W" { Toggle-VerityService "W" }
        "C" { Invoke-Configure }
        "Q" {
            Write-Host ""
            Write-Host "  Stop services before quitting? [Y/n] " -F $VyColor.Title -NoNewline
            $a = Read-VyKey
            if ($null -eq $a -or $a.KeyChar -ne 'n' -and $a.KeyChar -ne 'N') {
                foreach ($key in $services.Keys) { Stop-VerityService $key }
            }
            Write-Host ""
            Write-Host "  Bye." -F $VyColor.Ok
            Start-Sleep 1
            break main
        }
        default { }
    }
}
