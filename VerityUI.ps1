<# ============================================================================
 VerityUI.ps1 - shared terminal UI helpers for all Verity JE tools.
 Dot-sourced by setup.ps1, Manager.ps1 and the launchers.
 Box glyphs are built from codepoints so this file stays pure ASCII (PS 5.1
 misreads UTF-8 files without BOM); they all exist in cp437/cp850 consoles.
============================================================================ #>

$script:VyColor = @{
    Banner = "Cyan"; Title = "Yellow"; Ok = "Green"; Err = "Red"
    Dim    = "DarkGray"; Text = "White"; Accent = "Magenta"; Warn = "Yellow"
}

# box-drawing glyphs as STRINGS (PS 5.1 has no [char]*[int]; they exist in cp437/cp850)
$script:VyG = @{
    H  = [string][char]0x2500; V  = [string][char]0x2502
    TL = [string][char]0x250C; TR = [string][char]0x2510; BL = [string][char]0x2514; BR = [string][char]0x2518
    LT = [string][char]0x251C; RT = [string][char]0x2524
}

# render unicode box chars correctly everywhere (consoles, pipes, transcripts)
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

$script:VyBoxW = 56

function Write-VyBanner($title, $subtitle = "") {
    $g = $script:VyG; $w = $script:VyBoxW
    $line = $g.H * $w
    Write-Host ""
    Write-Host ("{0}{1}{2}" -f $g.TL, $line, $g.TR) -F $script:VyColor.Banner
    Write-Host $g.V -F $script:VyColor.Banner -NoNewline
    Write-Host ("  " + $title).PadRight($w) -F $script:VyColor.Title -NoNewline
    Write-Host $g.V -F $script:VyColor.Banner
    if ($subtitle) {
        Write-Host $g.V -F $script:VyColor.Banner -NoNewline
        Write-Host ("  " + $subtitle).PadRight($w) -F $script:VyColor.Dim -NoNewline
        Write-Host $g.V -F $script:VyColor.Banner
    }
    Write-Host ("{0}{1}{2}" -f $g.BL, $line, $g.BR) -F $script:VyColor.Banner
}

function Write-VyRule($label = "") {
    $g = $script:VyG; $w = $script:VyBoxW
    if ($label) {
        $pre = "  $label "
        Write-Host ($g.LT + $g.H + $g.H + " ") -F $script:VyColor.Banner -NoNewline
        Write-Host $label -F $script:VyColor.Title -NoNewline
        $rest = $w - $label.Length - 4
        if ($rest -lt 1) { $rest = 1 }
        Write-Host (" " + $g.H * $rest + $g.RT) -F $script:VyColor.Banner
    } else {
        Write-Host ($g.LT + ($g.H * $w) + $g.RT) -F $script:VyColor.Banner
    }
}

function Write-VyStatus($mark, $text, $color) {
    Write-Host "  $mark " -F $color -NoNewline
    Write-Host $text -F $script:VyColor.Text
}

function Write-VyOk($text)   { Write-VyStatus "[+]" $text $script:VyColor.Ok }
function Write-VyErr($text)  { Write-VyStatus "[x]" $text $script:VyColor.Err }
function Write-VyInfo($text) { Write-VyStatus "[i]" $text $script:VyColor.Dim }
function Write-VyWarn($text) { Write-VyStatus "[!]" $text $script:VyColor.Warn }

function Write-VyKeys($pairs) {
    # $pairs = @(@("S","Start all"), @("Q","Quit"), ...)
    Write-Host ""
    Write-Host "  " -NoNewline
    foreach ($p in $pairs) {
        Write-Host "[" -F $script:VyColor.Dim -NoNewline
        Write-Host $p[0] -F $script:VyColor.Title -NoNewline
        Write-Host "]" -F $script:VyColor.Dim -NoNewline
        Write-Host " $($p[1])   " -F $script:VyColor.Dim -NoNewline
    }
    Write-Host ""
}

# ------------------------------------------------------------ key input -----
function Read-VyKey {
    try { return [Console]::ReadKey($true) } catch { return $null }
}

function Test-VyKeyAvailable {
    try {
        if ([Console]::IsInputRedirected) { return $false }
        return [Console]::KeyAvailable
    } catch { return $false }
}

# waits up to $ms for a keypress; returns $null on timeout (live-refresh loops)
function Read-VyKeyTimeout($ms) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $ms) {
        if (Test-VyKeyAvailable) { return [Console]::ReadKey($true) }
        Start-Sleep -Milliseconds 120
    }
    return $null
}

# ------------------------------------------------------------- config -------
function Read-VyConfig($dir) {
    $p = Join-Path $dir "config.psd1"
    if (Test-Path $p) { try { return (Import-PowerShellDataFile $p) } catch { } }
    return @{}
}

function Write-VyConfig($dir, $cfg) {
    $p = Join-Path $dir "config.psd1"
    $lines = @("@{")
    foreach ($k in ($cfg.Keys | Sort-Object)) {
        $v = $cfg[$k]
        if ($v -is [bool]) { $vv = if ($v) { '$true' } else { '$false' } }
        else { $vv = "'" + ([string]$v -replace "'", "''") + "'" }
        $lines += "    $k = $vv"
    }
    $lines += "}"
    [IO.File]::WriteAllLines($p, $lines, (New-Object Text.UTF8Encoding($false)))
}

function Get-VyCfg($cfg, $name, $default = "") {
    if ($cfg -and $cfg.Contains($name) -and $null -ne $cfg[$name] -and "$($cfg[$name])" -ne "") { return $cfg[$name] }
    return $default
}

function Set-VyCfg($dir, $name, $value) {
    $cfg = Read-VyConfig $dir
    $cfg[$name] = $value
    Write-VyConfig $dir $cfg
}

# --------------------------------------------------------------- misc -------
function Test-VyPort($port) {
    try {
        return ($null -ne (Get-NetTCPConnection -LocalPort $port -State Listen -EA SilentlyContinue))
    } catch { return $false }
}

function Get-VyLogTail($file, $n = 8) {
    if (Test-Path $file) {
        $lines = Get-Content $file -Tail $n -Encoding UTF8 -EA SilentlyContinue
        foreach ($l in $lines) { Write-Host "    $l" -F $script:VyColor.Dim }
    }
}

function Start-VyTranscript($name) {
    $logDir = Join-Path (Get-VyRoot) "logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $f = Join-Path $logDir $name
    try { Start-Transcript -Path $f -Force | Out-Null } catch { }
    return $f
}

function Stop-VyTranscript {
    try { Stop-Transcript | Out-Null } catch { }
}

# resolved at dot-source time: in top-level scope $MyInvocation points to this file
$script:VyRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
function Get-VyRoot { return $script:VyRoot }
