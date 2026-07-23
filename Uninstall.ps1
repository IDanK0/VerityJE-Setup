<# Verity JE Uninstall - removes everything this setup installed.
   Stops services, deletes venvs/models/config, optionally the Whisper cache.
   System dependencies (Git, uv, ffmpeg, VC++ Runtime, Ollama) are left alone;
   remove them via winget if you want (commands are printed at the end). #>
[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

. (Join-Path $scriptDir "VerityUI.ps1")

Write-VyBanner "Verity JE - Uninstall" "removes everything installed by this setup"
Write-Host "  This will:" -F $VyColor.Text
Write-Host "   - stop all Verity services" -F $VyColor.Dim
Write-Host "   - delete Kokoro-FastAPI, LiteLLM and Whisper virtual environments" -F $VyColor.Dim
Write-Host "   - delete downloaded tools, logs and config.psd1" -F $VyColor.Dim
Write-Host ""
Write-Host "  Git, uv, ffmpeg, VC++ Runtime and Ollama are NOT removed." -F $VyColor.Dim
Write-Host ""
Write-Host "  Type YES to continue: " -F $VyColor.Title -NoNewline
$ans = Read-Host
if ($ans -ne "YES") { Write-Host "  Aborted." -F $VyColor.Dim; exit 0 }

# ---------------------------------------------------------------- stop all --
Write-VyInfo "stopping services..."
foreach ($port in @(8880, 4000, 9000)) {
    Get-NetTCPConnection -LocalPort $port -State Listen -EA SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.OwningProcess -Force -EA SilentlyContinue
    }
}

# ------------------------------------------------------------------ delete --
$targets = @(
    "Kokoro-FastAPI",
    "LiteLLM",
    "tools",
    "logs",
    "config.psd1",
    "WhisperServer\.venv",
    "WhisperServer\__pycache__"
)
foreach ($t in $targets) {
    $full = Join-Path $scriptDir $t
    if (Test-Path $full) {
        Remove-Item $full -Recurse -Force -EA SilentlyContinue
        if (Test-Path $full) { Write-VyErr "could not fully remove: $t (file in use?)" }
        else { Write-VyOk "removed $t" }
    }
}

Write-Host ""
Write-Host "  Also delete the Whisper model cache (~/.cache/whisper, redownloads on demand)? [y/N] " -F $VyColor.Title -NoNewline
$k = Read-VyKey; Write-Host ""
if ($k -and ($k.KeyChar -eq 'y' -or $k.KeyChar -eq 'Y')) {
    Remove-Item "$env:USERPROFILE\.cache\whisper" -Recurse -Force -EA SilentlyContinue
    Write-VyOk "whisper cache removed"
}

Write-Host ""
Write-VyOk "Verity JE backend removed."
Write-Host ""
Write-Host "  Left on the system (shared tools, remove only if you want):" -F $VyColor.Text
Write-Host "   - Git / uv / ffmpeg / VC++ Runtime: winget uninstall Git.Git; winget uninstall astral-sh.uv; winget uninstall Gyan.FFmpeg.Essentials; winget uninstall Microsoft.VCRedist.2015+.x64" -F $VyColor.Dim
Write-Host "   - Ollama + its models: winget uninstall Ollama.Ollama (models in ~\.ollama)" -F $VyColor.Dim
Write-Host "   - the Kokoro/Whisper models were inside the deleted folders" -F $VyColor.Dim
Write-Host ""
Write-Host "  To finish, delete this folder:" -F $VyColor.Text
Write-Host "   $scriptDir" -F $VyColor.Dim
Write-Host ""
Read-Host "Press Enter"
