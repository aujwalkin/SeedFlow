$ErrorActionPreference = 'Continue'
$root    = 'C:\Videos\4Converted'
$logFile = 'C:\Documents\Scripts\PostImportCleanup.log'

function Log($m) { "$([DateTime]::Now.ToString('s'))  $m" | Out-File -LiteralPath $logFile -Append -Encoding utf8 }

$sourceFile = $env:radarr_moviefile_sourcepath
if (-not $sourceFile) { $sourceFile = $env:sonarr_episodefile_sourcepath }

$eventType = $env:radarr_eventtype
if (-not $eventType)  { $eventType = $env:sonarr_eventtype }
if ($eventType -eq 'Test') { Log "Test event"; exit 0 }
if (-not $sourceFile)      { Log "No sourceFile";  exit 0 }

Log "sourceFile = [$sourceFile]"

$rootFull = $root.TrimEnd('\')

# Case-insensitive prefix check — file must live under root, with a separator after
if ($sourceFile.Length -le ($rootFull.Length + 1)) { Log "Too short for under root"; exit 0 }
$prefix = $sourceFile.Substring(0, $rootFull.Length)
if (-not [string]::Equals($prefix, $rootFull, [StringComparison]::OrdinalIgnoreCase)) {
    Log "Prefix [$prefix] != root [$rootFull]"; exit 0
}
if ($sourceFile[$rootFull.Length] -ne '\') {
    Log "No separator after root"; exit 0
}

# Relative path under root, then take the first segment (the torrent folder)
$rel = $sourceFile.Substring($rootFull.Length + 1)
$firstSep = $rel.IndexOf('\')
if ($firstSep -lt 1) { Log "File sits directly in root - nothing to clean"; exit 0 }

$topName = $rel.Substring(0, $firstSep)
$topDir  = Join-Path $rootFull $topName
Log "topDir = [$topDir]"

# Sanity: topDir must be inside root and not equal to it
if ([string]::Equals($topDir, $rootFull, [StringComparison]::OrdinalIgnoreCase)) {
    Log "topDir equals root - refusing"; exit 0
}
if (-not $topDir.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
    Log "topDir not inside root - refusing"; exit 0
}

if (Test-Path -LiteralPath $topDir) {
    try {
        Remove-Item -LiteralPath $topDir -Recurse -Force -ErrorAction Stop
        Log "Removed [$topDir]"
    } catch {
        Log "Remove failed: $($_.Exception.Message)"
    }
} else {
    Log "topDir does not exist"
}

exit 0
