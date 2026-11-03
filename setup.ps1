# setup.ps1 - "Set up my stick": turns a USB stick into a Pocket Help Desk (Windows).
# Started by "Set up my stick.cmd". Finds the stick, checks (or offers to fix) its
# format, then runs build-stick.ps1, which downloads everything from the official
# sources. Re-run it any time to update a stick: logins and chats are kept.
#   setup.ps1 [-Target <folder>]   (-Target skips the drive questions - for testing)
param([string]$Target)
$ErrorActionPreference = 'Stop'
Get-ChildItem $PSScriptRoot -Recurse -File | Unblock-File -ErrorAction SilentlyContinue   # downloaded zip: clear "from the internet" marks

Write-Host ''
Write-Host 'POCKET HELP DESK SETUP' -ForegroundColor Cyan
Write-Host 'This puts Claude Code (and Codex as a guest) on a USB stick, plus the repair toolkit.'
Write-Host 'Everything is downloaded from the official sources (about 1.3 GB). It takes 10-30 minutes.'
Write-Host ''

if ($Target) { $stick = $Target } else {
    $drives = @(Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Sort-Object DriveLetter)
    if (-not $drives.Count) { Write-Host 'No USB stick found. Plug one in (32 GB or more) and run this again.'; return }
    Write-Host 'USB sticks plugged in:'
    foreach ($d in $drives) {
        Write-Host ("  {0}:  {1,-14} {2,-6} {3,6:N1} GB" -f $d.DriveLetter, $(if ($d.FileSystemLabel) { $d.FileSystemLabel } else { '(no name)' }), $d.FileSystem, ($d.Size / 1GB))
    }
    $letter = (Read-Host "`nWhich one? Type its letter (e.g. $($drives[0].DriveLetter))").Trim().TrimEnd(':').ToUpper()
    $vol = $drives | Where-Object { [string]$_.DriveLetter -eq $letter }
    if (-not $vol) { Write-Host "No USB stick with letter $letter - nothing done."; return }

    # exFAT = the one format Windows, Mac and Linux all read and write
    if ($vol.FileSystem -ne 'exFAT') {
        Write-Host ''
        Write-Host "$letter`: is formatted as $(if ($vol.FileSystem) { $vol.FileSystem } else { 'nothing' }). A Pocket Help Desk needs exFAT."
        Write-Host "Formatting ERASES EVERYTHING on $letter`:." -ForegroundColor Yellow
        if ((Read-Host 'Type ERASE to format it now (anything else stops)') -cne 'ERASE') { Write-Host 'Stopped - nothing changed.'; return }
        Format-Volume -DriveLetter $letter -FileSystem exFAT -NewFileSystemLabel 'PocketHelp' -Confirm:$false | Out-Null
        Write-Host 'Formatted.'
    }
    $vol = Get-Volume -DriveLetter $letter
    if ($vol.SizeRemaining -lt 3GB) { Write-Host "Not enough room: $letter`: needs at least 3 GB free."; return }
    $stick = "$letter`:\"
    if (Test-Path (Join-Path $stick 'system\launch.ps1')) { Write-Host 'This stick already has Pocket Help Desk - updating it. Your login and chats are kept.' }
}

$platforms = @('windows-x64')
$a = Read-Host "`nWill this stick also be used on a Mac or Linux computer? (y/N)"
if ($a -match '^[yY]') { $platforms = @('windows-x64', 'windows-arm64', 'mac-arm64', 'mac-x64', 'linux-x64', 'linux-arm64'); Write-Host 'OK - adding Mac and Linux (about 3 GB more).' }

Write-Host ''
& (Join-Path $PSScriptRoot 'build-stick.ps1') -Stick $stick -Platforms $platforms
Write-Host ''
Write-Host 'ALL DONE.' -ForegroundColor Green
Write-Host "Open the stick and double-click 'Start (Windows).cmd'. The first time, press 1: you sign in to Claude"
Write-Host 'in a private browser window and choose a passphrase (4 or more random words). Best done at home.'
Write-Host "Everything else is in 'Guide.html' on the stick: double-click it."
