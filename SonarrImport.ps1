# ============================================================
# SonarrImport.ps1
# Intercepts Sonarr's import to find the actual video file
# regardless of extension mismatch between source and encoded output.
# Set your path below, everything else is automatic.
# ============================================================

$convertedFolder = "C:\Videos\4Converted"

# ============================================================
# DO NOT EDIT BELOW THIS LINE
# ============================================================

$videoExtensions = @("*.mp4", "*.mkv", "*.avi", "*.m4v")
$sourcePath      = $env:Sonarr_SourcePath
$destPath        = $env:Sonarr_DestinationPath

if ($env:Sonarr_EventType -eq "Test") { exit 0 }

$sourceDir = Split-Path $sourcePath -Parent

if (-not $sourceDir.StartsWith($convertedFolder)) {
    Write-Output "[MoveStatus]MoveComplete"
    exit 0
}

$videoFile = $null
foreach ($ext in $videoExtensions) {
    $found = Get-ChildItem -LiteralPath $sourceDir -Filter $ext -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        $videoFile = $found.FullName
        break
    }
}

if (-not $videoFile) {
    Write-Error "No video file found in $sourceDir"
    exit 1
}

$destDir  = Split-Path $destPath -Parent
$destBase = [System.IO.Path]::GetFileNameWithoutExtension($destPath)
$srcExt   = [System.IO.Path]::GetExtension($videoFile)
$newDest  = Join-Path $destDir ($destBase + $srcExt)

if (-not (Test-Path -LiteralPath $destDir)) {
    New-Item -ItemType Directory -Path $destDir | Out-Null
}

Move-Item -LiteralPath $videoFile -Destination $newDest -Force

Write-Output "[MediaFile]$newDest"
Write-Output "[MoveStatus]MoveComplete"
exit 0
