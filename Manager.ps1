$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Add uv tool path
$uvBin = "$env:USERPROFILE\.local\bin"
if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

# Service registry
$services = @{
    "FastKoko" = @{
        name = "FastKoko (TTS)"
        port = 8880
        url = "http://127.0.0.1:8880/v1/"
        batFile = "FastKoko.bat"
        running = $false
        pid = $null
    }
    "LiteLLM" = @{
        name = "LiteLLM (AI)"
        port = 4000
        url = "http://127.0.0.1:4000/v1/"
        batFile = "LiteLLM.bat"
        running = $false
        pid = $null
    }
    "Whisper" = @{
        name = "Whisper (STT)"
        port = 9000
        url = "http://127.0.0.1:9000/v1/"
        batFile = "WhisperServer.bat"
        running = $false
        pid = $null
    }
}

function Test-PortInUse {
    param([int]$port)
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        $tcp.ConnectAsync("127.0.0.1", $port).Wait(500)
        $result = $tcp.Client.Connected
        $tcp.Close()
        return $result
    } catch { return $false }
}

function Show-Menu {
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  VerityTM Manager" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [S]  Start all services" -ForegroundColor White
    Write-Host "  [A]  Stop all services" -ForegroundColor White
    Write-Host "  [R]  Restart all services" -ForegroundColor White
    Write-Host ""
    Write-Host "--- Individual Services ---" -ForegroundColor Yellow

    $services.GetEnumerator() | Sort-Object Name | ForEach-Object {
        $key = $_.Key
        $svc = $_.Value
        $status = if ($svc.running) { "RUNNING" } else { "STOPPED" }
        $color = if ($svc.running) { "Green" } else { "Red" }
        $shortcut = $key.Substring(0, 1).ToUpper()

        Write-Host "  [$shortcut] $($svc.name,-22) $status" -ForegroundColor $color
        Write-Host "       $($svc.url)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "--- Tools ---" -ForegroundColor Yellow
    Write-Host "  [L]  Change LiteLLM model" -ForegroundColor White
    Write-Host "  [K]  List Kokoro voices" -ForegroundColor White
    Write-Host ""
    Write-Host "  [Q]  Quit (stops all services)" -ForegroundColor Yellow
    Write-Host ""
}

function Start-Service {
    param([string]$name)

    $svc = $services[$name]
    if (-not $svc) { return }

    if ($svc.running) {
        Write-Host "  [$name] Already running" -ForegroundColor Yellow
        return
    }

    $batPath = Join-Path $scriptDir $svc.batFile
    if (-not (Test-Path $batPath)) {
        Write-Host "  [$name] Script not found: $batPath" -ForegroundColor Red
        return
    }

    Write-Host "  [$name] Starting..." -ForegroundColor Yellow

    $proc = Start-Process -FilePath "powershell" `
        -ArgumentList "-NoExit", "-ExecutionPolicy", "Bypass", "-File", $batPath `
        -WindowStyle Minimized `
        -PassThru

    if ($proc) {
        # Wait for port to become available
        for ($i = 1; $i -le 10; $i++) {
            Start-Sleep -Milliseconds 1000
            if (Test-PortInUse $svc.port) {
                $svc.running = $true
                $svc.pid = $proc.Id
                Write-Host "  [$name] Started successfully (PID: $($proc.Id))" -ForegroundColor Green
                return
            }
        }
        Write-Host "  [$name] Process started but port not responding yet (check the window)" -ForegroundColor Yellow
        $svc.running = $true
        $svc.pid = $proc.Id
    } else {
        Write-Host "  [$name] Failed to start" -ForegroundColor Red
    }
}

function Stop-Service {
    param([string]$name)

    $svc = $services[$name]
    if (-not $svc) { return }

    if (-not $svc.running) {
        Write-Host "  [$name] Already stopped" -ForegroundColor DarkGray
        return
    }

    Write-Host "  [$name] Stopping..." -ForegroundColor Yellow

    if ($svc.pid) {
        try {
            Stop-Process -Id $svc.pid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 500
        } catch { }
    }

    # Kill any process on the service port
    $portPid = (Get-NetTCPConnection -LocalPort $svc.port -ErrorAction SilentlyContinue | Select-Object -First 1).OwningProcess
    if ($portPid) {
        try { Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue } catch { }
    }

    $svc.running = $false
    $svc.pid = $null
    Write-Host "  [$name] Stopped" -ForegroundColor Red
}

function Change-Model {
    if (-not $services["LiteLLM"].running) {
        Write-Host "LiteLLM is not running. Start it first." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "Model list (same as LiteLLM launcher):" -ForegroundColor Cyan
    Write-Host "  1. gpt-4o         5. claude-3-opus       9. huggingface/mistral"
    Write-Host "  2. gpt-4o-mini    6. gemini-2.5-flash   10. Custom..."
    Write-Host "  3. gpt-3.5-turbo  7. gemini-2.5-pro"
    Write-Host "  4. claude-sonnet  8. groq/llama-3.3-70b"
    Write-Host ""

    $choice = Read-Host "Choice (number or custom model name)"
    $modelMap = @{
        "1" = "gpt-4o"; "2" = "gpt-4o-mini"; "3" = "gpt-3.5-turbo"
        "4" = "claude-sonnet-4-20250514"; "5" = "claude-3-opus-20240229"
        "6" = "gemini-2.5-flash"; "7" = "gemini-2.5-pro"
        "8" = "groq/llama-3.3-70b"; "9" = "huggingface/mistralai/Mistral-7B-Instruct"
    }

    if ($modelMap.ContainsKey($choice)) { $m = $modelMap[$choice] }
    elseif ($choice -eq "10" -or -not $modelMap.ContainsKey($choice)) { $m = Read-Host "Custom model:" }
    else { $m = $modelMap[$choice] }

    if ($m) {
        Write-Host "Restarting LiteLLM with model: $m" -ForegroundColor Yellow
        Stop-Service "LiteLLM"
        Start-Sleep -Seconds 1
        # We restart via the bat file normally, but with a custom model we use the litellm command directly
        Start-Process powershell -NoExit -WindowStyle Minimized -ArgumentList "-Command", "`$env:LITELLM_LOG='INFO'; litellm --model $m --port 4000"
        Write-Host "LiteLLM restarted with model: $m on http://127.0.0.1:4000/v1/" -ForegroundColor Green
        $services["LiteLLM"].running = $true
    }
}

function List-Voices {
    if (-not $services["FastKoko"].running) {
        Write-Host "FastKoko is not running. Start it first." -ForegroundColor Yellow
        return
    }
    try {
        $voices = Invoke-RestMethod -Uri "http://127.0.0.1:8880/v1/audio/voices" -Method Get
        Write-Host ""
        Write-Host "Available Kokoro voices:" -ForegroundColor Cyan
        $i = 1
        foreach ($v in $voices.voices) {
            $id = $v.id.ToLower()
            if ($id -match "^i[fm]_") { $tag = "[IT]" } elseif ($id -match "^[abef]_[a-z]+") { $tag = "[EN]" } else { $tag = "   " }
            Write-Host "  $tag $($v.id)" -ForegroundColor White
        }
    } catch {
        Write-Host "Could not load voices. Is the server running?" -ForegroundColor Red
    }
}

# ============================================================
# MAIN
# ============================================================
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  VerityTM Manager" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Check for already running services
foreach ($key in $services.Keys) {
    if (Test-PortInUse $services[$key].port) {
        $services[$key].running = $true
        Write-Host "  [$($services[$key].name)] Already detected as running" -ForegroundColor Green
    }
}

while ($true) {
    Show-Menu
    $key = (Read-Host "Choice").ToUpper()

    switch ($key) {
        "S" {
            Write-Host "`nStarting all services..." -ForegroundColor Green
            Start-Service "FastKoko"
            Start-Service "LiteLLM"
            Start-Service "Whisper"
        }
        "A" {
            Write-Host "`nStopping all services..." -ForegroundColor Red
            Stop-Service "FastKoko"
            Stop-Service "LiteLLM"
            Stop-Service "Whisper"
        }
        "R" {
            Write-Host "`nRestarting all services..." -ForegroundColor Yellow
            Stop-Service "FastKoko"
            Stop-Service "LiteLLM"
            Stop-Service "Whisper"
            Start-Sleep -Seconds 2
            Start-Service "FastKoko"
            Start-Service "LiteLLM"
            Start-Service "Whisper"
        }
        "F" { Start-Service "FastKoko" }
        "I" { Start-Service "LiteLLM" }
        "W" { Start-Service "Whisper" }
        "L" { Change-Model }
        "K" { List-Voices }
        "Q" {
            Write-Host "`nShutting down all services..." -ForegroundColor Yellow
            Stop-Service "FastKoko"
            Stop-Service "LiteLLM"
            Stop-Service "Whisper"
            Write-Host "Goodbye!" -ForegroundColor Cyan
            break
        }
        default {
            Write-Host "  Invalid choice. Use S/A/R/F/I/W/L/K/Q" -ForegroundColor Red
        }
    }
}
