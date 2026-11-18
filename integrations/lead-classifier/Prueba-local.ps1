# Run in a normal PowerShell, without administrator privileges. No install or paid fallback.
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (!(Get-Command node -ErrorAction SilentlyContinue) -or ([int](& node -p 'process.versions.node.split(".")[0]')) -lt 22) { throw 'Necesitas Node.js 22 o posterior (nodejs.org).' }
if (!(Get-Command ollama -ErrorAction SilentlyContinue)) { throw 'Instala Ollama desde ollama.com/download/windows y vuelve a abrir PowerShell.' }
$env:OLLAMA_HOST='127.0.0.1:11434'
$env:OLLAMA_NO_CLOUD='1'
$model='qwen3:4b-instruct-2507-q4_K_M'
& ollama pull $model
if ($LASTEXITCODE -ne 0) {throw 'No se pudo descargar el modelo local.'}
& node quality.mjs
if ($LASTEXITCODE -ne 0) {throw 'No se ha superado el control de calidad. No actives la clasificación.'}
