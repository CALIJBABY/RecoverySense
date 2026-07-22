$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path ".venv\Scripts\python.exe")) {
    throw "Run scripts\setup_ml.ps1 first."
}

& ".\.venv\Scripts\python.exe" -m pip install -r backend\api\requirements.txt
Set-Location backend\api
& "..\..\.venv\Scripts\python.exe" -m uvicorn app.main:app --reload
