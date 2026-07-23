<# LiteLLM - AI gateway (:4000)
   Interactive model + API key picker; saves your choices for next time.
   -ServerOnly: start with the saved configuration, no prompts (used by Manager). #>
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

Write-Host ""
Write-Host "================================================" -F Yellow
Write-Host "  LiteLLM - AI Gateway" -F Yellow
Write-Host "================================================" -F Yellow
Write-Host ""

# ------------------------------------------------------- locate executable --
$exe = Cfg "LiteLLMExe"
if (-not $exe -or -not (Test-Path $exe)) { $exe = (Get-Command litellm -EA SilentlyContinue).Source }
if (-not $exe) {
    foreach ($cand in @(
        (Join-Path (Cfg "UvBin") "litellm.exe"),
        "$env:USERPROFILE\.local\bin\litellm.exe"
    )) { if ($cand -and (Test-Path $cand)) { $exe = $cand; break } }
}
if (-not $exe) {
    if (Get-Command uv -EA SilentlyContinue) {
        $bin = (& uv tool dir --bin 2>&1 | Out-String).Trim()
        $cand = Join-Path $bin "litellm.exe"
        if (Test-Path $cand) { $exe = $cand }
    }
}
if (-not $exe) {
    Write-Host "ERROR: litellm not found. Run Setup.bat first." -F Red
    Read-Host "Press Enter"; exit 1
}

# ------------------------------------------------------------- catalog ------
$catalog = @(
    @{ id = "gpt-4o-mini";                label = "gpt-4o-mini          (OpenAI, cheap)";   key = "OPENAI_API_KEY" },
    @{ id = "gpt-4o";                     label = "gpt-4o               (OpenAI)";          key = "OPENAI_API_KEY" },
    @{ id = "claude-sonnet-4-20250514";   label = "Claude Sonnet 4      (Anthropic)";       key = "ANTHROPIC_API_KEY" },
    @{ id = "gemini/gemini-2.5-flash";    label = "Gemini 2.5 Flash     (Google)";          key = "GEMINI_API_KEY" },
    @{ id = "groq/llama-3.3-70b-versatile"; label = "Llama 3.3 70B      (Groq, fast)";      key = "GROQ_API_KEY" },
    @{ id = "ollama/llama3.2";            label = "Llama 3.2 local      (Ollama, offline)"; key = "" }
)

function Get-ApiKey($name) {
    foreach ($scope in @("Process", "User", "Machine")) {
        $v = [Environment]::GetEnvironmentVariable($name, $scope)
        if ($v) { return $v }
    }
    return ""
}

function Test-OllamaUp {
    try {
        $null = Invoke-WebRequest "http://127.0.0.1:11434/" -TimeoutSec 2 -UseBasicParsing -EA SilentlyContinue
        return $true
    } catch { return ($null -ne $_.Exception.Response) }
}

# ------------------------------------------------------------ pick model ----
$savedModel = Cfg "LiteLLMModel"
$entry = $null

if ($ServerOnly) {
    if ($savedModel) {
        $entry = $catalog | Where-Object { $_.id -eq $savedModel } | Select-Object -First 1
        if (-not $entry) { $entry = @{ id = $savedModel; key = "" } }
    } else {
        # first unattended start: prefer a provider that already has a key
        foreach ($c in $catalog) {
            if ($c.key -and (Get-ApiKey $c.key)) { $entry = $c; break }
        }
        if (-not $entry -and (Get-Command ollama -EA SilentlyContinue)) { $entry = $catalog[-1] }
        if (-not $entry) { $entry = $catalog[0] }
        Write-Host "No saved model - defaulting to $($entry.id). Run LiteLLM.bat once to choose." -F Yellow
    }
} else {
    Write-Host "Available models:" -F White
    for ($i = 0; $i -lt $catalog.Count; $i++) {
        $mark = if ($catalog[$i].id -eq $savedModel) { " (saved)" } else { "" }
        Write-Host ("  {0,2}. {1}{2}" -f ($i + 1), $catalog[$i].label, $mark) -F White
    }
    Write-Host "   0. Custom model id" -F DarkGray
    Write-Host ""
    $c = Read-Host "Choose (number or model id)"
    if ($c -match '^\d+$') {
        $id = [int]$c - 1
        if ($id -ge 0 -and $id -lt $catalog.Count) { $entry = $catalog[$id] }
    }
    if (-not $entry -and $c.Trim()) {
        $entry = @{ id = $c.Trim(); key = "" }
        if     ($entry.id -like "gpt*")                    { $entry.key = "OPENAI_API_KEY" }
        elseif ($entry.id -like "claude*")                 { $entry.key = "ANTHROPIC_API_KEY" }
        elseif ($entry.id -like "gemini*")                 { $entry.key = "GEMINI_API_KEY" }
        elseif ($entry.id -like "groq/*")                  { $entry.key = "GROQ_API_KEY" }
        elseif ($entry.id -like "ollama/*")                { $entry.key = "" }
    }
    if (-not $entry) {
        if ($savedModel) { $entry = @{ id = $savedModel; key = "" } }
        else { $entry = $catalog[0] }
    }
}
$model = $entry.id
Write-Host "Model: $model" -F Green

# ------------------------------------------------------------- API key ------
if ($entry.key) {
    $val = Get-ApiKey $entry.key
    if (-not $val) {
        if ($ServerOnly) {
            Write-Host "ERROR: $($entry.key) is not set. Run LiteLLM.bat once interactively to save it." -F Red
            exit 1
        }
        Write-Host ""
        $val = Read-Host "Enter your $($entry.key) (stored for your user only)"
        if ($val.Trim()) {
            $val = $val.Trim()
            [Environment]::SetEnvironmentVariable($entry.key, $val, "User")
            Set-Item "env:$($entry.key)" $val
            Write-Host "Saved $($entry.key) (user environment)" -F Green
        } else {
            Write-Host "No key entered - the provider will reject requests." -F Yellow
        }
    } else {
        Set-Item "env:$($entry.key)" $val   # make sure this process has it
    }
} elseif ($model -like "ollama/*") {
    if (-not (Test-OllamaUp)) {
        Write-Host "Ollama is not responding on :11434 - trying to start it..." -F Yellow
        if (Get-Command ollama -EA SilentlyContinue) {
            Start-Process ollama -ArgumentList "serve" -WindowStyle Hidden
            Start-Sleep 3
        }
    }
    if (-not (Test-OllamaUp)) {
        Write-Host "WARNING: Ollama still not reachable. Install/start Ollama and pull the model:" -F Yellow
        Write-Host "  ollama pull $($model -replace 'ollama/','')" -F DarkGray
    }
}

# save model choice for unattended starts
if (-not $ServerOnly -and $model -ne $savedModel) {
    $cfg["LiteLLMModel"] = $model
    $lines = @("@{")
    foreach ($k in ($cfg.Keys | Sort-Object)) {
        $v = $cfg[$k]
        if ($v -is [bool]) { $vv = if ($v) { '$true' } else { '$false' } }
        else { $vv = "'" + ([string]$v -replace "'", "''") + "'" }
        $lines += "    $k = $vv"
    }
    $lines += "}"
    [IO.File]::WriteAllLines($cfgPath, $lines, (New-Object Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- port ------
$port = "4000"
if (-not $ServerOnly) {
    $p = Read-Host "Port [4000]"
    if ($p -match '^\d+$' -and [int]$p -ge 1 -and [int]$p -le 65535) { $port = $p }
}
$busy = Get-NetTCPConnection -LocalPort ([int]$port) -State Listen -EA SilentlyContinue
if ($busy) {
    Write-Host "Port $port is already in use - LiteLLM is probably already running." -F Yellow
    Write-Host "API: http://127.0.0.1:$port/v1/" -F Yellow
    if ($ServerOnly) { exit 0 }
    Read-Host "Press Enter"; exit 0
}

# ----------------------------------------------------------------- run ------
$env:PYTHONUTF8 = "1"   # litellm's banner is Unicode; hidden/redirected stdout is cp1252 otherwise -> crash
Write-Host ""
Write-Host "Starting on http://127.0.0.1:$port/v1/" -F Green
Write-Host "Model: $model" -F Yellow
Write-Host "Press Ctrl+C to stop" -F DarkGray
Write-Host ""
$env:LITELLM_LOG = "INFO"

if ($ServerOnly) {
    $logDir = Join-Path $scriptDir "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $outLog = Join-Path $logDir "litellm-server.out.log"
    $errLog = Join-Path $logDir "litellm-server.err.log"
    Remove-Item $outLog, $errLog -Force -EA SilentlyContinue
    $proc = Start-Process -FilePath $exe -ArgumentList "--model", $model, "--port", $port, "--host", "127.0.0.1" `
        -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
    $up = $false
    for ($i = 0; $i -lt 45 -and -not $up; $i++) {
        Start-Sleep -Seconds 2
        if ($proc.HasExited) { break }
        $busy = Get-NetTCPConnection -LocalPort ([int]$port) -State Listen -EA SilentlyContinue
        if ($busy) { $up = $true }
    }
    if ($up) { Write-Host "SERVER READY: http://127.0.0.1:$port/v1/" -F Green; exit 0 }
    Write-Host "ERROR: LiteLLM did not start. Last log lines:" -F Red
    foreach ($f in @($errLog, $outLog)) {
        if (Test-Path $f) { Get-Content $f -Tail 12 | ForEach-Object { Write-Host "  $_" -F DarkGray } }
    }
    exit 1
}

& $exe --model $model --port $port --host 127.0.0.1
