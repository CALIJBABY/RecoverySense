[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$RemoveGeneratedMLArtifacts
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Mode = if ($Apply) { 'REMOVE' } else { 'DRY RUN' }
Write-Host "RecoverySense repository cleanup - $Mode"
Write-Host "Repository: $RepoRoot"

$targets = New-Object System.Collections.Generic.List[string]

# Local/generated caches that should never be the source of truth.
$directoryNames = @(
    '.dart_tool', 'build', '.gradle', '.kotlin', '.pytest_cache',
    '__pycache__', 'Pods', 'DerivedData', 'xcuserdata'
)

Get-ChildItem -LiteralPath $RepoRoot -Force -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object {
        $directoryNames -contains $_.Name -or $_.Name -like '*.egg-info'
    } |
    ForEach-Object { $targets.Add($_.FullName) }

Get-ChildItem -LiteralPath $RepoRoot -Force -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -eq 'local.properties' -or
        $_.Name -eq '.flutter-plugins-dependencies' -or
        $_.Name -eq 'Generated.xcconfig' -or
        $_.Name -eq 'flutter_export_environment.sh' -or
        $_.Extension -in @('.pyc', '.pyo')
    } |
    ForEach-Object { $targets.Add($_.FullName) }

# Model bundles and reports can be scientifically important. They are removed
# only when the caller opts in after preserving any validated artifacts.
if ($RemoveGeneratedMLArtifacts) {
    $generatedRoots = @(
        (Join-Path $RepoRoot 'ml\data\processed'),
        (Join-Path $RepoRoot 'ml\models'),
        (Join-Path $RepoRoot 'ml\reports')
    )
    foreach ($generatedRoot in $generatedRoots) {
        if (Test-Path -LiteralPath $generatedRoot) {
            Get-ChildItem -LiteralPath $generatedRoot -Force -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne '.gitkeep' } |
                ForEach-Object { $targets.Add($_.FullName) }
        }
    }
}

$uniqueTargets = $targets |
    Sort-Object { $_.Length } -Descending |
    Select-Object -Unique

foreach ($target in $uniqueTargets) {
    $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $target)
    if ($Apply) {
        Remove-Item -LiteralPath $target -Force -Recurse -ErrorAction SilentlyContinue
        Write-Host "Removed: $relative"
    } else {
        Write-Host "Would remove: $relative"
    }
}

$obsoleteCandidates = @(
    (Join-Path $RepoRoot 'apps\wear_android\app'),
    (Join-Path $RepoRoot 'apps\wear_android\gradle')
)
foreach ($candidate in $obsoleteCandidates) {
    if (Test-Path -LiteralPath $candidate) {
        $hasContent = Get-ChildItem -LiteralPath $candidate -Force -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $hasContent) {
            $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $candidate)
            if ($Apply) {
                Remove-Item -LiteralPath $candidate -Force -Recurse
                Write-Host "Removed empty obsolete directory: $relative"
            } else {
                Write-Host "Would remove empty obsolete directory: $relative"
            }
        }
    }
}

if (-not $Apply) {
    Write-Host ''
    Write-Host 'No files were changed. Review the list, then rerun with -Apply.'
    if (-not $RemoveGeneratedMLArtifacts) {
        Write-Host 'Validated/generated model artifacts were intentionally excluded.'
        Write-Host 'Add -RemoveGeneratedMLArtifacts only after preserving anything needed.'
    }
}
