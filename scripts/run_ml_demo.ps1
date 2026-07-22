$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path ".venv\Scripts\recoverysense-ml.exe")) {
    throw "Run scripts\setup_ml.ps1 first."
}

& ".\.venv\Scripts\recoverysense-ml.exe" --config ml/config/default.yaml run-demo
& ".\.venv\Scripts\python.exe" -m pytest ml/tests
