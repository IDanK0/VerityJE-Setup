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
        if (-not $p.failedShown) {
            $p.failedShown = $true
            Show-Failure $key
        }
        return "FAILED", "Red"
    }
    if (Test-Installed $key) { return "off", "DarkGray" }
    return "MISSING", "Red"
}

function Show-Failure($key) {
    $svc = $services[$key]
    Write-Host ""
    Write-VyErr "$($svc.name) failed to start - last log lines:"
    Get-VyLogTail (Join-Path $scriptDir "logs\$($svc.lLog)") 6
    Get-VyLogTail (Join-Path $scriptDir "logs\$($svc.sLog)") 8
    Write-Host ""
}

function Show-Dashboard {
    Clear-Host
    Write-VyBanner "Verity JE - Manager" "AI backend control panel"
    Write-VyRule "Services"
    Write-Host ""
    foreach ($key in $services.Keys) {
        $svc = $services[$key]
        $state, $color = Get-ServiceState $key
        Write-Host ("   [{0}] " -f $key) -F $VyColor.Title -NoNewline
        Write-Host ("{0,-16}" -f $svc.name) -F White -NoNewline
        Write-Host ("{0,-10}" -f $state) -F $color -NoNewline
        Write-Host (":{0,-6}" -f $svc.port) -F $VyColor.Dim -NoNewline
        Write-Host "http://127.0.0.1:$($svc.port)/v1/" -F $VyColor.Dim
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
    $pending[$key] = @{ proc = $proc; since = Get-Date; failedShown = $false }
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
    # interactive LiteLLM configuration in a visible window
    $bat = Join-Path $scriptDir "LiteLLM.bat"
    if (Test-Path $bat) { Start-Process cmd -ArgumentList "/c", "`"$bat`"" }
}

$redirected = [Console]::IsInputRedirected

if ($redirected) {
    # line-input mode (piped/automation): one render, then classic prompt loop
    Show-Dashboard
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
        Show-Dashboard
    }
    foreach ($k in $services.Keys) { Stop-VerityService $k }
    exit 0
}

:main while ($true) {
    Show-Dashboard
    $k = Read-VyKeyTimeout 2000
    if ($null -eq $k) { continue }   # live refresh
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
