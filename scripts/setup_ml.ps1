$ErrorActionPreference = "Stop"

Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path ".venv")) {
    py -3.11 -m venv .venv
}

& ".\.venv\Scripts\python.exe" -m pip install --upgrade pip
& ".\.venv\Scripts\python.exe" -m pip install -e ".\ml[dev]"

Write-Host "RecoverySense ML environment is ready."
Write-Host "Activate it with: .\.venv\Scripts\Activate.ps1"
