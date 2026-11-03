# Package the small "Set up my stick" download (scripts only - no programs: every
# program is downloaded from its official source by setup, so nothing is redistributed).
#
#   pwsh -File tools\make-setup-zip.ps1        -> .cache\pocket-help-desk-setup.zip
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $repo '.cache\setup-zip\Pocket Help Desk setup'
$out = Join-Path $repo '.cache\pocket-help-desk-setup.zip'
Remove-Item (Split-Path $stage) -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force (Join-Path $stage 'tools') | Out-Null
foreach ($f in 'Set up my stick.cmd', 'setup.ps1', 'build-stick.ps1', 'versions.txt') { Copy-Item (Join-Path $repo $f) $stage }
foreach ($f in 'tools.txt', 'fetch-tools.ps1') { Copy-Item (Join-Path $repo "tools\$f") (Join-Path $stage 'tools') }
Copy-Item (Join-Path $repo 'stick') (Join-Path $stage 'stick') -Recurse
Set-Content (Join-Path $stage 'READ ME.txt') -Encoding ASCII -Value @(
    'POCKET HELP DESK SETUP',
    '',
    '1. Plug in the USB stick you want to use (32 GB or more).',
    '2. Double-click "Set up my stick.cmd" and follow the questions. It downloads everything from the official sources (10-30 minutes).',
    '3. Open the stick and double-click "Start (Windows).cmd". The first time, press 1 to sign in to Claude and choose a passphrase - best done at home.',
    '',
    'The full guide: https://pockethelpdesk.com/guide/',
    'Run "Set up my stick.cmd" again any time to update a stick - your login and chats are kept.')
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
Remove-Item $out -Force -ErrorAction SilentlyContinue
Compress-Archive -Path $stage -DestinationPath $out
"{0}  {1:N0} KB" -f $out, ((Get-Item $out).Length / 1KB)
