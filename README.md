# SeedFlow

Inserts Fileflows/Tdarr encoding between qBittorrent and Sonarr/Radarr without breaking seeding and fixing container mismatch on imports.

Uses hardlinks to segregate Fileflows working folder while qBittorrent keeps seeding original. Sonarr/Radarr imports the encoded file via a custom import script that handles any container mismatch (fixes "No files found are eligible for import" error from remuxing), and everything cleans up automatically once your seeding conditions are met.

```
qBittorrent downloads → 2Downloaded
SeedFlow hardlinks    → 3Converting
Fileflows encodes     → 4Converted, awaits Sonarr/Radarr import
Sonarr/Radarr import  ← 4Converted, removes converted file after import
SeedFlow deletes      → qbittorrent + 2Downloaded when seeding done
```

---

### Repository Contents

- `SeedFlow.ps1` — main pipeline script, watches downloads and manages cleanup
- `RunSeedFlow.bat` — launches SeedFlow.ps1
- `4ConvertedCleanup.ps1` — custom script for Sonarr/Radarr
- `AV1 Automation.json` — example Fileflows flow to import, which ensures all files are either av1 in mp4 or hevc in mkv (configure to your needs)

---

### Tested on

- Windows 10
- qBittorrent 5.1.0
- Sonarr 4.0.17.2969
- Radarr 5.28.0.10274 & 6.2.1.10461
- Fileflows (Tdarr or similar should work same way)

---

# Setup

## Default Folder Structure

Create these folders before setup (or wherever you need):

```
C:\Videos\
  1Downloading\   ← qbit incomplete downloads
  2Downloaded\    ← qbit completed downloads
  3Converting\    ← hardlink staging, Fileflows reads from here
  4Converted\     ← Fileflows outputs here, Sonarr/Radarr imports from here
```

---

## Script Configuration

### SeedFlow.ps1

Edit the config block at the top:

```powershell
$source            = "C:\Videos\2Downloaded"
$dest              = "C:\Videos\3Converting"
$converted         = "C:\Videos\4Converted"
$qbitUrl           = "http://localhost:8080"
$username          = "YOURUSERNAME"
$password          = "YOURPASSWORD"
$allowedCategories = @("tv-sonarr", "radarr")
$targetRatio       = 2.0
$targetSeedMinutes = 10080        # 7 days
$checkIntervalSecs = 60
$refreshSecs       = 10
$deleteOnPause     = $true
```

---

## qBittorrent Setup

**Tools → Options → Downloads**
- Default Save Path: `C:\Videos\2Downloaded`
- Keep incomplete torrents in: `C:\Videos\1Downloading` (enable and set path)
- Content Layout: `Create subfolder` (you can alternatively set this inside Sonarr/Radarr if you don't want it globally)

**Tools → Options → BitTorrent**
- Disable all global seeding limits — set ratio to 0 or unchecked (SeedFlow handles deletion)

**Tools → Options → Web UI**
- Enable the Web UI: ✓
- Port: `8080`
- Set a username and password
- Uncheck `Use HTTPS`
- Check `Bypass authentication for clients on localhost`

**Confirm category names** — these must match `$allowedCategories` in PlexFlow.ps1:
- Sonarr: **Settings → Download Clients → qBittorrent → Category** (default: `tv-sonarr`)
- Radarr: **Settings → Download Clients → qBittorrent → Category** (default: `radarr`)

---

## Fileflows Setup (Tdarr or others should be similar)

**Library**
- Source: `C:\Videos\3Converting`
- Scan interval: 1 minute (preference)

**Flow**

If using my example flow:
- import flow
- double-click the "Move File" node, change the `Destination Folder` to your path (keeping the end two "{ }" intact)
- adjust other nodes to your needs

For your own flow, just ensure these nodes are at the end:
1. Move File → `C:\Videos\4Converted\{folder.Orig.Name}\{file.Orig.FileName}` or whatever your folder is, ensuring it ends with those parameters
2. Delete Original
3. Delete Source Folder (check `If empty`)

---

## Sonarr Setup

**Settings → Download Clients → qBittorrent**
- Host: `localhost`
- Port: `8080`
- Username/Password: your qbit Web UI credentials
- Category: `tv-sonarr`

**Settings → Download Clients → Remote Path Mappings**
- Host: `localhost`
- Remote Path: `C:\Videos\2Downloaded`
- Local Path: `C:\Videos\4Converted`

**Settings → Download Clients**
- Enable Completed Download Handling: ✓
- Remove Completed: ✗

**Settings → Media Management** (enable Show Advanced)
- Use Hardlinks instead of Copy: ✗ (preference, but SeedFlow hardlinks where needed and enabling won't do anything if you're encoding on a non-storage drive
- Delete Empty Folders: ✓

**Settings → Connect → Custom Script**
- Uncheck all except `On File Import` and `On File Upgrade`
- Path: `C:\Path\To\4ConvertedCleanup.ps1`

---

## Radarr Setup

Same as Sonarr:

**Settings → Download Clients → qBittorrent**
- Category: `radarr`

**Settings → Download Clients → Remote Path Mappings**
- Remote Path: `C:\Videos\2Downloaded`
- Local Path: `C:\Videos\4Converted`

**Settings → Media Management** (enable Show Advanced)
- Use Hardlinks instead of Copy: ✗
- Delete Empty Folders: ✓

**Settings → Connect → Custom Script**
- Uncheck all except `On File Import` and `On File Upgrade`
- Path: `C:\Path\To\4ConvertedCleanup.ps1`

---

## Running SeedFlow

Double-click `RunPlexFlow.bat` to start. Keep the window open while qBittorrent is active. The log will show each file as it moves through the pipeline:

```
SeedFlow started | 22:01:00
watching: C:\Videos\2Downloaded

22:01:23 | LINKED   | Clarksons.Farm.S05E07.1080p
22:10:34 | ENCODING | Clarksons.Farm.S05E07.1080p
22:42:11 | SEEDING  | Clarksons.Farm.S05E07.1080p | encoded, imported, deleted converted file from 4Converted, waiting on qbit to delete original
23:15:00 | DELETED  | Clarksons.Farm.S05E07.1080p | ratio 2.01 reached, original deleted. Only file remaining is the converted file in your end media destination
```

---

## Deletion Conditions

A torrent is deleted (along with its files in `2Downloaded` and `4Converted`) when any one of these is met:

- Ratio reached `$targetRatio` (default 2.0)
- Seeding time reached `$targetSeedMinutes` (default 7 days)
- Torrent manually stopped/paused `$deleteOnPause` (default true)

Manual downloads without a Sonarr/Radarr category untouched.

---

## Notes

- SeedFlow must be running for the pipeline to function.
- If restarted mid-pipeline, files already in `2Downloaded` are re-detected and re-linked automatically.
- The SonarrImport script only acts on files inside `4Converted`
- This is the solution that worked for me; it may or may not help your situation. You can get away with Using 3Converted as 2Downloaded, but I just prefer to separate them.
