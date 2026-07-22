$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Find litellm in PATH (uv tool install puts it in ~/.local/bin)
$uvBin = "$env:USERPROFILE\.local\bin"
if ((Test-Path $uvBin) -and ($env:Path -notlike "*$uvBin*")) { $env:Path += ";$uvBin" }

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LiteLLM - AI Gateway" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$modelOptions = @(
    "gpt-4o                      (OpenAI GPT-4o)"
    "gpt-4o-mini                 (OpenAI GPT-4o Mini)"
    "gpt-3.5-turbo               (OpenAI GPT-3.5 Turbo)"
    "claude-sonnet-4-20250514    (Anthropic Claude Sonnet)"
    "claude-3-opus-20240229      (Anthropic Claude Opus)"
    "gemini-2.5-flash            (Google Gemini Flash)"
    "gemini-2.5-pro              (Google Gemini Pro)"
    "groq/llama-3.3-70b          (Groq Llama 70b)"
    "huggingface/mistralai/Mistral-7B-Instruct (HuggingFace Mistral)"
)

Write-Host "Available models:" -ForegroundColor Cyan
for ($i = 0; $i -lt $modelOptions.Count; $i++) {
    $prefix = ("  {0,2}. " -f ($i+1))
    $description = $modelOptions[$i].Substring(28)
    $modelName = $modelOptions[$i].Substring(0, 28).Trim()
    Write-Host "$prefix$description" -ForegroundColor White
    Write-Host ("       " + $modelName) -ForegroundColor DarkGray
}
Write-Host "      0. Custom model" -ForegroundColor Yellow

Write-Host ""
Write-Host "Choose model (number or name):" -ForegroundColor Yellow
$choice = Read-Host

if ($choice -match '^\d+$') {
    $idx = [int]$choice - 1
    if ($idx -ge 0 -and $idx -lt $modelOptions.Count) {
        $model = $modelOptions[$idx].Substring(0, 28).Trim()
    } else { $model = "gpt-4o" }
} elseif ($choice.Trim()) {
    $model = $choice.Trim()
} else {
    $model = "gpt-4o"
}

Write-Host ""
Write-Host "Model: $model" -ForegroundColor Green

# Detect API keys from environment
$knownKeys = @("OPENAI_API_KEY","ANTHROPIC_API_KEY","GEMINI_API_KEY","GROQ_API_KEY","HUGGINGFACE_API_KEY","COHERE_API_KEY","TOGETHERAI_API_KEY","REPLICATE_API_KEY","MISTRAL_API_KEY","PERPLEXITY_API_KEY","DEEPSEEK_API_KEY","XAI_API_KEY")
$foundKey = $false
foreach ($k in $knownKeys) {
    if (Test-Path "env:$k" -and (Get-Item "env:$k").Value) { $foundKey = $true; break }
}

if (-not $foundKey) {
    Write-Host ""
    Write-Host "No API key detected in environment." -ForegroundColor Yellow
    Write-Host "Enter your API key (or press Enter to skip):" -ForegroundColor Yellow
    $key = Read-Host
    if ($key.Trim()) {
        $keyVarName = ($model.ToUpper() -replace '[^A-Z0-9_]','_').Replace('OPENAI','OPENAI').Replace('_','_API_')
        if ($model -match "gpt|openai") { Set-Item -Path "env:OPENAI_API_KEY" -Value $key.Trim(); Write-Host "Set OPENAI_API_KEY" -ForegroundColor Green }
        elseif ($model -match "claude|anthropic") { Set-Item -Path "env:ANTHROPIC_API_KEY" -Value $key.Trim(); Write-Host "Set ANTHROPIC_API_KEY" -ForegroundColor Green }
        elseif ($model -match "gemini") { Set-Item -Path "env:GEMINI_API_KEY" -Value $key.Trim(); Write-Host "Set GEMINI_API_KEY" -ForegroundColor Green }
        elseif ($model -match "groq") { Set-Item -Path "env:GROQ_API_KEY" -Value $key.Trim(); Write-Host "Set GROQ_API_KEY" -ForegroundColor Green }
        elseif ($model -match "huggingface") { Set-Item -Path "env:HUGGINGFACE_API_KEY" -Value $key.Trim(); Write-Host "Set HUGGINGFACE_API_KEY" -ForegroundColor Green }
        else { Set-Item -Path "env:API_KEY" -Value $key.Trim(); Write-Host "Set API_KEY" -ForegroundColor Green }
    }
}

Write-Host ""
Write-Host "Port (default 4000):" -ForegroundColor Yellow
$port = Read-Host
if (-not ($port -match '^\d+$')) { $port = "4000" }

Write-Host ""
Write-Host "Starting LiteLLM on http://127.0.0.1:$port/v1/" -ForegroundColor Green
Write-Host "Docs: http://127.0.0.1:$port/docs" -ForegroundColor Yellow
Write-Host ""
Write-Host "Press Ctrl+C to stop" -ForegroundColor DarkGray
Write-Host ""

$env:LITELLM_LOG = "INFO"
litellm --model $model --port $port
