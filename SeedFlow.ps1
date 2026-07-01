$source            = "C:\Videos\2Downloaded"
$dest              = "C:\Videos\3Converting"
$converted         = "C:\Videos\4Converted"
$qbitUrl           = "http://localhost:8080"
$username          = "USERNAME"
$password          = "PASSWORD"
$allowedCategories = @("tv-sonarr", "radarr")
$targetRatio       = 2.0
$targetSeedMinutes = 10080
$checkIntervalSecs = 60
$refreshSecs       = 10
$deleteOnPause     = $true

$files   = @{}
$deleted = 0

function Get-QbitSession {
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    Invoke-WebRequest -Uri "$qbitUrl/api/v2/auth/login" `
        -Method POST `
        -Body "username=$username&password=$password" `
        -UseBasicParsing `
        -SessionVariable session | Out-Null
    return $session
}

function Get-TorrentName($relativePath) {
    return $relativePath.Split('\')[0]
}

function Log($msg, $color = "Gray") {
    $line = "$(Get-Date -Format 'HH:mm:ss') | $msg"
    Write-Host $line -ForegroundColor $color
}

function Check-AndDelete {
    try {
        $session = Get-QbitSession
        foreach ($key in @($files.Keys)) {
            $f           = $files[$key]
            $torrentName = $f.TorrentName
            $found       = $false

            foreach ($cat in $allowedCategories) {
                $resp = Invoke-WebRequest -Uri "$qbitUrl/api/v2/torrents/info?category=$cat" `
                    -UseBasicParsing -WebSession $session
                $torrents = $resp.Content | ConvertFrom-Json

                $match = $torrents | Where-Object {
                    $cp = $_.content_path -replace "/", "\"
                    $cp -eq (Join-Path $source $torrentName) -or
                    $cp.StartsWith((Join-Path $source $torrentName) + "\")
                } | Select-Object -First 1

                if ($match) {
                    $found    = $true
                    $newRatio = [math]::Round($match.ratio, 2)
                    $newMins  = [math]::Round($match.seeding_time / 60)
                    $newState = $match.state

                    $files[$key].Ratio    = $newRatio
                    $files[$key].SeedMins = $newMins
                    $files[$key].State    = $newState

                    $hitRatio    = $match.ratio -ge $targetRatio
                    $hitSeedTime = ($match.seeding_time / 60) -ge $targetSeedMinutes
                    $isPaused = $deleteOnPause -and ($newState -eq "pausedUP" -or $newState -eq "stoppedUP" -or $newState -eq "stopped")

                    if ($hitRatio -or $hitSeedTime -or $isPaused) {
                        Invoke-WebRequest -Uri "$qbitUrl/api/v2/torrents/delete" `
                            -Method POST `
                            -Body "hashes=$($match.hash)&deleteFiles=true" `
                            -UseBasicParsing -WebSession $session | Out-Null
                        $files.Remove($key)
                        $script:deleted++
                        $reason = if ($hitRatio) { "ratio $newRatio" } elseif ($hitSeedTime) { "seed time $newMins min" } else { "manually stopped" }
                        Log "DELETED  | $torrentName | $reason" "Red"

                        $convertedPath = Join-Path $converted $torrentName
                        if (Test-Path -LiteralPath $convertedPath) {
                            Remove-Item -LiteralPath $convertedPath -Recurse -Force
                            Log "CLEANED  | $torrentName | removed from 4Converted" "DarkGray"
                        }
                    }
                    break
                }
            }

            if (-not $found) {
                if ($files[$key].Status -ne "seeding") {
                    $files[$key].Status = "seeding"
                    Log "SEEDING  | $torrentName | not found in qbit categories, may be manual" "DarkGray"
                }
            }
        }
    } catch {
        Log "ERROR    | qbit check failed: $_" "DarkRed"
    }
}

function Update-FileStatuses {
    foreach ($key in @($files.Keys)) {
        $destPath  = Join-Path $dest $key
        $srcPath   = Join-Path $source $key
        $oldStatus = $files[$key].Status

        if (Test-Path -LiteralPath $destPath) {
            if ($oldStatus -eq "linking") {
                $files[$key].Status = "encoding"
                Log "ENCODING | $($files[$key].TorrentName)" "Green"
            }
        } elseif (Test-Path -LiteralPath $srcPath) {
            if ($oldStatus -ne "seeding") {
                $files[$key].Status = "seeding"
                Log "SEEDING  | $($files[$key].TorrentName) | encoded, waiting on qbit" "Yellow"

                $hardlinkFile = Join-Path $dest $key
                if (Test-Path -LiteralPath $hardlinkFile) {
                    Remove-Item -LiteralPath $hardlinkFile -Force
                }
                $hardlinkDir = Split-Path (Join-Path $dest $key) -Parent
                if ((Test-Path -LiteralPath $hardlinkDir) -and (Get-ChildItem -LiteralPath $hardlinkDir).Count -eq 0) {
                    Remove-Item -LiteralPath $hardlinkDir -Force
                }
            }
        }
    }
}

function Scan-NewFiles {
    $sourceFiles = Get-ChildItem -LiteralPath $source -Recurse -File
    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($source.Length).TrimStart('\')
        if (-not $files.ContainsKey($relativePath)) {
            $destPath = Join-Path $dest $relativePath
            $destDir  = Split-Path $destPath -Parent
            try {
                if (-not (Test-Path -LiteralPath $destDir)) {
                    New-Item -ItemType Directory -Path $destDir | Out-Null
                }
                if (-not (Test-Path -LiteralPath $destPath)) {
                    cmd /c mklink /H "`"$destPath`"" "`"$($file.FullName)`"" | Out-Null
                }
                $files[$relativePath] = @{
                    Key         = $relativePath
                    TorrentName = Get-TorrentName $relativePath
                    Name        = $file.Name
                    Status      = "linking"
                    Ratio       = 0
                    SeedMins    = 0
                    State       = "unknown"
                    Added       = (Get-Date).ToString('Hmm:ss')
                }
                Log "LINKED   | $(Get-TorrentName $relativePath)" "Magenta"
            } catch {
                Log "ERROR    | failed to hardlink $relativePath`: $_" "DarkRed"
            }
        }
    }
}

Write-Host "PlexFlow started | $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor DarkGray
Write-Host "watching: $source" -ForegroundColor DarkGray
Write-Host ""

$lastCheck = (Get-Date).AddSeconds(-$checkIntervalSecs)

while ($true) {
    Scan-NewFiles
    Update-FileStatuses

    if ((Get-Date) -gt $lastCheck.AddSeconds($checkIntervalSecs)) {
        Check-AndDelete
        $lastCheck = Get-Date
    }

    Start-Sleep -Seconds $refreshSecs
}
