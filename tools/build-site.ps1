# Assemble the website in .cache\deploy - plain static files for any static host.
#   /                              site\        the homepage
#   /guide/                        stick\Guide.html - the same file every stick carries
#   /pocket-help-desk-setup.zip    the scripts-only setup (tools\make-setup-zip.ps1)
#
#   pwsh -File tools\build-site.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$out = Join-Path $repo '.cache\deploy'
& (Join-Path $PSScriptRoot 'make-setup-zip.ps1')
if (Test-Path $out) { Remove-Item $out -Recurse -Force }   # fails loudly if something (a preview server) holds it open
New-Item -ItemType Directory $out | Out-Null
Copy-Item (Join-Path $repo 'site\*') $out -Recurse
New-Item -ItemType Directory -Force (Join-Path $out 'guide') | Out-Null
Copy-Item (Join-Path $repo 'stick\Guide.html') (Join-Path $out 'guide\index.html')
Copy-Item (Join-Path $repo '.cache\pocket-help-desk-setup.zip') $out
Get-ChildItem $out -Recurse -File | ForEach-Object { $_.FullName.Substring($out.Length + 1) }
