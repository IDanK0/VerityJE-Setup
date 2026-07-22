$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$uvBin = "$env:USERPROFILE\.local\bin"
if((Test-Path $uvBin)-and($env:Path -notlike "*$uvBin*")){$env:Path+=";$uvBin"}

Write-Host "";Write-Host "================================================" -F Yellow
Write-Host "  LiteLLM - AI Gateway" -F Yellow;Write-Host "================================================" -F Yellow

$models = @("gpt-4o (OpenAI)","gpt-4o-mini (OpenAI)","gpt-3.5-turbo (OpenAI)","claude-sonnet-4-20250514","gemini-2.5-flash (Google)","llama-3.3-70b-instruct (Meta)","groq/llama-3.3-70b (Groq)")
Write-Host "`nAvailable models:" -F White
for($i=0;$i -lt $models.Count;$i++){Write-Host ("  {0,2}. {1}" -f ($i+1),$models[$i]) -F White}
Write-Host "      0. Custom" -F DarkGray
Write-Host "";$c=Read-Host "Choose (number or name)"
if($c -match '^\d+$'){$id=[int]$c-1;if($id -ge 0 -and $id -lt $models.Count){$m=($models[$id] -split '\(')[0].Trim()}else{$m="gpt-4o"}}else{$m=$c.Trim();if(!$m){$m="gpt-4o"}}
Write-Host "Model: $m" -F Green

$keys=@("OPENAI_API_KEY","ANTHROPIC_API_KEY","GEMINI_API_KEY","GROQ_KEY","HUGGINGFACE_KEY","COHERE_KEY","TOGETHERAI_KEY","REPLICATE_KEY","MISTRAL_KEY","PERPLEXITY_KEY","DEEPSEEK_KEY","XAI_KEY")
$fk=$false;foreach($e in $keys){if(Test-Path "env:$e" -and (Get-Item "env:$e").Value){$fk=$true;break}}
if(!$fk){Write-Host "`nNo API key found in environment." -F Yellow;Write-Host "Enter your API key (or Enter to skip):" -F Yellow;$k=Read-Host;if($k.Trim()){Set-Item -Path "env:OPENAI_API_KEY" -Value $k.Trim();Write-Host "Set OPENAI_API_KEY" -F Green}}

Write-Host "";Write-Host "Port (default 4000):" -F Yellow;$p=Read-Host;if(!($p -match '^\d+$')){$p="4000"}
Write-Host "`nStarting on http://127.0.0.1:$p/v1/" -F Green;Write-Host "Docs: http://127.0.0.1:$p/docs" -F Yellow
Write-Host "`nPress Ctrl+C to stop`n" -F DarkGray
$env:LITELLM_LOG="INFO";litellm --model $m --port $p
