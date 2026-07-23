<# LiteLLM - AI gateway (:4000)
   Interactive model + API key picker; choices are saved for next time.
   Ollama models are offered first when Ollama is installed.
   -ServerOnly: start with the saved configuration, no prompts (used by Manager). #>
[CmdletBinding()]
param([switch]$ServerOnly)

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

. (Join-Path $scriptDir "VerityUI.ps1")

Start-VyTranscript "litellm-launcher.log"

# ------------------------------------------------------------ config load ---
$cfg = Read-VyConfig $scriptDir

Write-VyBanner "LiteLLM - AI Gateway" "OpenAI-compatible proxy for 100+ LLMs"

# ------------------------------------------------------- locate executable --
$exe = Get-VyCfg $cfg "LiteLLMExe"
if (-not $exe -or -not (Test-Path $exe)) { $exe = Join-Path $scriptDir "LiteLLM\.venv\Scripts\litellm.exe" }
if (-not (Test-Path $exe)) { $exe = (Get-Command litellm -EA SilentlyContinue).Source }
if (-not $exe) {
    foreach ($cand in @(
        (Join-Path (Get-VyCfg $cfg "UvBin") "litellm.exe"),
        "$env:USERPROFILE\.local\bin\litellm.exe"
    )) { if ($cand -and (Test-Path $cand)) { $exe = $cand; break } }
}
if (-not $exe -or -not (Test-Path $exe)) {
    Write-VyErr "litellm not found. Run Setup.bat first."
    Stop-VyTranscript; Read-Host "Press Enter"; exit 1
}

# ------------------------------------------------------------- ollama -------
$hasOllama = [bool](Get-Command ollama -EA SilentlyContinue)
$ollamaModels = @()
if ($hasOllama) {
    $raw = & ollama list 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        foreach ($line in ($raw -split "`r?`n" | Select-Object -Skip 1)) {
            $m = ([regex]::Split($line.Trim(), '\s+'))[0]
            if ($m) { $ollamaModels += $m }
        }
        # keep the picker single-key friendly: digits 1-9
        if ($ollamaModels.Count -gt 3) { $ollamaModels = @($ollamaModels | Select-Object -First 3) }
    }
}

function Test-OllamaUp {
    try {
        $null = Invoke-WebRequest "http://127.0.0.1:11434/" -TimeoutSec 2 -UseBasicParsing -EA SilentlyContinue
        return $true
    } catch { return ($null -ne $_.Exception.Response) }
}

function Ensure-OllamaServe {
    if (Test-OllamaUp) { return $true }
    if ($hasOllama) {
        Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
        for ($i = 0; $i -lt 15; $i++) { Start-Sleep 1; if (Test-OllamaUp) { return $true } }
    }
    return (Test-OllamaUp)
}

# ------------------------------------------------------------- catalog ------
$catalog = @()
foreach ($m in $ollamaModels) { $catalog += @{ id = "ollama/$m"; label = "$m (Ollama, local)"; key = "" } }
$cfgOllamaModel = Get-VyCfg $cfg "OllamaModel"
if ($cfgOllamaModel -and ($catalog.id -notcontains $cfgOllamaModel)) {
    $catalog = @(@{ id = $cfgOllamaModel; label = "$($cfgOllamaModel -replace '^ollama/','') (Ollama, local)"; key = "" }) + $catalog
}
if ($hasOllama) { $catalog += @{ id = "__pull__"; label = "Pull a new Ollama model..."; key = "" } }
$catalog += @(
    @{ id = "gpt-4o-mini";                label = "gpt-4o-mini (OpenAI)";       key = "OPENAI_API_KEY" },
    @{ id = "gpt-4o";                     label = "gpt-4o (OpenAI)";            key = "OPENAI_API_KEY" },
    @{ id = "claude-sonnet-4-20250514";   label = "Claude Sonnet 4 (Anthropic)"; key = "ANTHROPIC_API_KEY" },
    @{ id = "gemini/gemini-2.5-flash";    label = "Gemini 2.5 Flash (Google)";  key = "GEMINI_API_KEY" },
    @{ id = "groq/llama-3.3-70b-versatile"; label = "Llama 3.3 70B (Groq)";     key = "GROQ_API_KEY" }
)

function Get-ApiKey($name) {
    foreach ($scope in @("Process", "User", "Machine")) {
        $v = [Environment]::GetEnvironmentVariable($name, $scope)
        if ($v) { return $v }
    }
    return ""
}

function Save-Model($m) {
    Set-VyCfg $scriptDir "LiteLLMModel" $m
    $script:savedModel = $m
}

# ------------------------------------------------------------ pick model ----
$savedModel = Get-VyCfg $cfg "LiteLLMModel"
$entry = $null

if ($ServerOnly) {
    if ($savedModel) {
        $entry = $catalog | Where-Object { $_.id -eq $savedModel } | Select-Object -First 1
        if (-not $entry) { $entry = @{ id = $savedModel; key = "" } }
    } else {
        foreach ($c in $catalog) {
            if ($c.id -eq "__pull__") { continue }
            if ($c.key -and (Get-ApiKey $c.key)) { $entry = $c; break }
            if (-not $c.key -and $c.id -like "ollama/*" -and $hasOllama) { $entry = $c; break }
        }
        if (-not $entry) { $entry = @{ id = "gpt-4o-mini"; key = "OPENAI_API_KEY" } }
        Write-VyWarn "no saved model - defaulting to $($entry.id). Run LiteLLM.bat once to choose."
    }
} else {
    Write-VyRule "Available models"
    Write-Host ""
    $pick = @($catalog | Where-Object { $_.id -ne "__pull__" })
    for ($i = 0; $i -lt $pick.Count; $i++) {
        $mark = if ($pick[$i].id -eq $savedModel) { " *" } else { "" }
        Write-Host ("  [{0}] " -f ($i + 1)) -F $VyColor.Title -NoNewline
        Write-Host $pick[$i].label -F White -NoNewline
        if ($mark) { Write-Host $mark -F $VyColor.Accent -NoNewline }
        Write-Host ""
    }
    Write-Host ""
    $hint = "  (* = saved)  [1-$($pick.Count)] pick"
    if ($hasOllama) { $hint += "   [P] pull Ollama model" }
    $hint += "   [C] custom   [Enter] keep saved"
    Write-Host $hint -F $VyColor.Dim
    $k = Read-VyKey
    Write-Host ""
    if ($null -ne $k -and $k.KeyChar -match '^\d$') {
        $ix = [int]"$($k.KeyChar)" - 1
        if ($ix -ge 0 -and $ix -lt $pick.Count) { $entry = $pick[$ix] }
    } elseif ($null -ne $k -and ($k.KeyChar -eq 'p' -or $k.KeyChar -eq 'P') -and $hasOllama) {
        Write-Host "  Model to pull (e.g. llama3.2, gemma3n:e4b): " -NoNewline -F $VyColor.Title
        $nm = Read-Host
        if ($nm.Trim()) {
            $nm = $nm.Trim() -replace '^ollama/', ''
            if (Ensure-OllamaServe) {
                Write-Host "  Pulling $nm ..." -F $VyColor.Dim
                & ollama pull $nm
                if ($LASTEXITCODE -eq 0) { $entry = @{ id = "ollama/$nm"; key = "" } }
                else { Write-VyErr "pull failed" }
            } else { Write-VyErr "Ollama daemon not running" }
        }
    } elseif ($null -ne $k -and ($k.KeyChar -eq 'c' -or $k.KeyChar -eq 'C')) {
        Write-Host "  Model id (e.g. openrouter/auto, ollama/llama3.2): " -NoNewline -F $VyColor.Title
        $cid = Read-Host
        if ($cid.Trim()) {
            $entry = @{ id = $cid.Trim(); key = "" }
            if     ($entry.id -like "gpt*")    { $entry.key = "OPENAI_API_KEY" }
            elseif ($entry.id -like "claude*") { $entry.key = "ANTHROPIC_API_KEY" }
            elseif ($entry.id -like "gemini*") { $entry.key = "GEMINI_API_KEY" }
            elseif ($entry.id -like "groq/*")  { $entry.key = "GROQ_API_KEY" }
        }
    }
    if (-not $entry -and $savedModel) {
        $entry = $catalog | Where-Object { $_.id -eq $savedModel } | Select-Object -First 1
        if (-not $entry) { $entry = @{ id = $savedModel; key = "" } }
    }
    if (-not $entry) { Write-VyErr "no model selected"; Stop-VyTranscript; Read-Host "Press Enter"; exit 1 }
}

$model = $entry.id
Write-VyOk "model: $model"
if (-not $ServerOnly -and $model -ne $savedModel) { Save-Model $model }

# -------------------------------------------------------- ollama handling ---
if ($model -like "ollama/*") {
    $ollamaName = $model -replace '^ollama/', ''
    if (-not $hasOllama) {
        Write-VyErr "Ollama is not installed - run Setup.bat and choose it, or https://ollama.com"
        Stop-VyTranscript; if (-not $ServerOnly) { Read-Host "Press Enter" }; exit 1
    }
    if (-not (Ensure-OllamaServe)) {
        Write-VyErr "Ollama daemon not responding on :11434"
        Stop-VyTranscript; if (-not $ServerOnly) { Read-Host "Press Enter" }; exit 1
    }
    if ($ollamaModels -notcontains $ollamaName) {
        if ($ServerOnly) {
            Write-VyWarn "model $ollamaName not pulled - pulling now..."
            & ollama pull $ollamaName 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Write-VyErr "pull failed: ollama pull $ollamaName"; Stop-VyTranscript; exit 1 }
        } else {
            Write-Host "  Model $ollamaName is not pulled yet. Pull now? [Y/n] " -F $VyColor.Title -NoNewline
            $a = Read-VyKey; Write-Host ""
            if ($null -eq $a -or ($a.KeyChar -ne 'n' -and $a.KeyChar -ne 'N')) {
                & ollama pull $ollamaName
                if ($LASTEXITCODE -ne 0) { Write-VyErr "pull failed"; Stop-VyTranscript; Read-Host "Press Enter"; exit 1 }
            }
        }
    }
}

# ------------------------------------------------------------- API key ------
if ($entry.key) {
    $val = Get-ApiKey $entry.key
    if (-not $val) {
        if ($ServerOnly) {
            Write-VyErr "$($entry.key) is not set. Run LiteLLM.bat once interactively to save it."
            Stop-VyTranscript; exit 1
        }
        Write-Host ""
        Write-Host "  Enter your $($entry.key) (stored for your user only): " -F $VyColor.Title -NoNewline
        $val = Read-Host
        if ($val.Trim()) {
            $val = $val.Trim()
            [Environment]::SetEnvironmentVariable($entry.key, $val, "User")
            Set-Item "env:$($entry.key)" $val
            Write-VyOk "$($entry.key) saved (user environment)"
        } else {
            Write-VyWarn "no key entered - the provider will reject requests"
        }
    } else {
        Set-Item "env:$($entry.key)" $val
    }
}

# ---------------------------------------------------------------- port ------
$port = "4000"
if (-not $ServerOnly) {
    Write-Host "  Port [4000]: " -F $VyColor.Title -NoNewline
    $p = Read-Host
    if ($p -match '^\d+$' -and [int]$p -ge 1 -and [int]$p -le 65535) { $port = $p }
}
if (Test-VyPort ([int]$port)) {
    Write-VyWarn "port $port already in use - LiteLLM is probably already running"
    Write-VyInfo "API: http://127.0.0.1:$port/v1/"
    Stop-VyTranscript
    if ($ServerOnly) { exit 0 }
    Read-Host "Press Enter"; exit 0
}

# ----------------------------------------------------------------- run ------
$env:LITELLM_LOG = "INFO"
$env:PYTHONUTF8 = "1"   # litellm's banner is Unicode; hidden/redirected stdout is cp1252 otherwise -> crash

Write-Host ""
Write-VyOk "starting on http://127.0.0.1:$port/v1/  (model: $model)"

if ($ServerOnly) {
    $logDir = Join-Path $scriptDir "logs"
    $outLog = Join-Path $logDir "litellm-server.out.log"
    $errLog = Join-Path $logDir "litellm-server.err.log"
    Remove-Item $outLog, $errLog -Force -EA SilentlyContinue
    $proc = Start-Process -FilePath $exe -ArgumentList "--model", $model, "--port", $port, "--host", "127.0.0.1" `
        -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    $up = $false
    for ($i = 0; $i -lt 45 -and -not $up; $i++) {
        Start-Sleep -Seconds 2
        if ($proc.HasExited) { break }
        if (Test-VyPort ([int]$port)) { $up = $true }
    }
    if ($up) { Write-VyOk "SERVER READY: http://127.0.0.1:$port/v1/"; Stop-VyTranscript; exit 0 }
    Write-VyErr "LiteLLM did not start. Last log lines:"
    Get-VyLogTail $errLog 12
    Get-VyLogTail $outLog 6
    Stop-VyTranscript; exit 1
}

Write-Host "  Press Ctrl+C to stop" -F $VyColor.Dim
Write-Host ""
& $exe --model $model --port $port --host 127.0.0.1
Stop-VyTranscript
