param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Set-Location $RepositoryRoot

Write-Host "RecoverySense research checks" -ForegroundColor Cyan
Write-Host "Repository: $RepositoryRoot"

python scripts\research_static_audit.py

$env:PYTHONPATH = "ml/src"
python -m pytest -q ml/tests

$env:PYTHONPATH = "ml/src;backend/api"
python -m pytest -q backend/api/tests

Write-Host ""
Write-Host "Python/static checks passed." -ForegroundColor Green
Write-Host "Still required on this computer:" -ForegroundColor Yellow
Write-Host "  cd apps\phone_flutter_new"
Write-Host "  flutter clean"
Write-Host "  flutter pub get"
Write-Host "  dart format lib"
Write-Host "  flutter analyze"
Write-Host "  flutter test"
Write-Host "  flutter build apk --release"
Write-Host ""
Write-Host "  cd ..\wear_android\wear_android"
Write-Host "  .\gradlew.bat clean assembleDebug"
