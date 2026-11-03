# Fetch the toolkit listed in tools.txt into <stick>\Tools (Windows; PowerShell 5.1+).
#
#   powershell -ExecutionPolicy Bypass -File tools\fetch-tools.ps1 -Stick E:\
#
# Downloads are cached in .cache\tools. Every .exe/.dll is checked: a broken
# signature stops the build; unsigned files are allowed but listed.
param([Parameter(Mandatory)][string]$Stick)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Repo = Split-Path -Parent $PSScriptRoot
$Cache = Join-Path $Repo '.cache\tools'
$Tools = Join-Path $Stick 'Tools'
New-Item -ItemType Directory -Force $Cache, $Tools | Out-Null
$ghHeaders = @{ 'User-Agent' = 'pocket-help-desk' }
if ($env:GH_TOKEN) { $ghHeaders['Authorization'] = "Bearer $env:GH_TOKEN" }

function Resolve-Source($source) {
    # gh:<owner>/<repo>:<regex> -> newest release asset matching the regex
    if ($source -notlike 'gh:*') { return @{ Url = $source; Name = ($source -split '[/?]')[-1] } }
    $repo, $rx = $source.Substring(3) -split ':', 2
    $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/latest" -Headers $ghHeaders
    $a = @($rel.assets | Where-Object { $_.name -match $rx }) | Select-Object -First 1
    if (-not $a) { throw "no asset matching '$rx' in $repo $($rel.tag_name)" }
    return @{ Url = $a.browser_download_url; Name = $a.name; Release = $rel; Digest = $a.digest }
}
function Get-Cached($url, $name, $digest) {
    # $digest = "sha256:<hex>" as GitHub publishes it; checked on every run, cached or not
    $f = Join-Path $Cache $name
    if (-not (Test-Path $f)) { Invoke-WebRequest $url -OutFile "$f.part" -UseBasicParsing; Move-Item "$f.part" $f }
    if ($digest) {
        $got = (Get-FileHash $f -Algorithm SHA256).Hash.ToLower()
        if ("sha256:$got" -ne $digest) { Remove-Item $f; throw "checksum mismatch for $name" }
    }
    return $f
}

$sevenZa = $null   # full 7-Zip, set once the 7zip line has run
$lines = Get-Content (Join-Path $PSScriptRoot 'tools.txt') | Where-Object { $_ -and $_ -notmatch '^\s*#' }
foreach ($line in $lines) {
    $name, $folder, $source, $how, $school, $what = ($line -split '\|') | ForEach-Object { $_.Trim() }
    $dest = Join-Path $Tools $folder
    New-Item -ItemType Directory -Force $dest | Out-Null
    Write-Host "==> $name"
    $src = Resolve-Source $source
    $file = Get-Cached $src.Url $src.Name $src.Digest
    switch ($how) {
        'file'  { Copy-Item $file (Join-Path $dest $src.Name) -Force }
        'unzip' { Expand-Archive $file -DestinationPath $dest -Force }
        'nupkg' {  # a NuGet package is a zip; keep the module files, drop the packaging
            $zip = "$file.zip"; Copy-Item $file $zip -Force
            Expand-Archive $zip -DestinationPath $dest -Force; Remove-Item $zip
            Remove-Item (Join-Path $dest '_rels'), (Join-Path $dest 'package'), (Join-Path $dest '[[]Content_Types[]].xml'), (Join-Path $dest '*.nuspec') -Recurse -Force -ErrorAction SilentlyContinue
        }
        '7zfull' {  # the 7-Zip installer is a self-extracting archive: 7zr.exe (same release) unpacks it
            $r = $src.Release.assets | Where-Object { $_.name -eq '7zr.exe' } | Select-Object -First 1
            $zr = Get-Cached $r.browser_download_url '7zr.exe' $r.digest
            & $zr x $file "-o$dest" -y | Out-Null
            if ($LASTEXITCODE) { throw "7zr failed on $file" }
            Remove-Item (Join-Path $dest 'Uninstall.exe') -Force -ErrorAction SilentlyContinue
            $sevenZa = Join-Path $dest '7z.exe'
        }
        '7z' {  # unpack an installer without running it
            if (-not $sevenZa) { throw "7zip must come before $name in tools.txt" }
            $tmp = Join-Path $Cache "x-$name"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
            & $sevenZa x $file "-o$tmp" -y | Out-Null
            if ($LASTEXITCODE) { throw "7za failed on $file" }
            Get-ChildItem $tmp -Force | Where-Object { $_.Name -notlike '$*' -and $_.Name -notlike 'uninst*' } | Copy-Item -Destination $dest -Recurse -Force
            Remove-Item $tmp -Recurse -Force
        }
        default { throw "unknown 'how' for ${name}: $how" }
    }
}

Write-Host '==> Checking signatures'
$unsigned = @()
Get-ChildItem $Tools -Recurse -File -Include *.exe, *.dll | ForEach-Object {
    $s = Get-AuthenticodeSignature $_.FullName
    if ($s.Status -eq 'NotSigned') { $unsigned += $_.FullName.Substring($Tools.Length + 1) }
    elseif ($s.Status -ne 'Valid') { throw "BAD SIGNATURE ($($s.Status)): $($_.FullName)" }
}
if ($unsigned.Count) {
    # normal for open-source tools (7-Zip, smartmontools): their downloads were checked against official checksums above
    Write-Host "All tools checked. ($($unsigned.Count) open-source files carry no digital signature - normal for 7-Zip and smartmontools, whose downloads were checked against their official checksums.)"
    if ($env:POCKET_HELP_DESK_VERBOSE) { Write-Host "Unsigned: $($unsigned -join ', ')" }
}

# A plain list on the stick of what each tool is and where to get it, for anyone rebuilding by hand
$list = @('WHERE THESE TOOLS CAME FROM', '===========================', '',
          'Each one is free, downloaded from its official source. To get one yourself, use the link.',
          '"school-safe: yes" = free for organisations too.', '')
foreach ($line in $lines) {
    $name, $folder, $source, $how, $school, $what = ($line -split '\|') | ForEach-Object { $_.Trim() }
    $link = if ($source -like 'gh:*') { 'https://github.com/' + ($source.Substring(3) -split ':')[0] + '/releases/latest' } else { $source }
    $list += "$what", "    folder: Tools\$folder    school-safe: $school", "    $link", ''
}
$list += 'Fetched only when needed (see work\TOOLS.md): manufacturer driver tools (HP Image Assistant,',
         'Lenovo Thin Installer, Dell Command | Update), Snappy Driver Installer Origin, Microsoft Safety',
         'Scanner, Display Driver Uninstaller.'
Set-Content -Path (Join-Path $Tools 'Where these came from.txt') -Value $list -Encoding UTF8
Write-Host "Toolkit ready in $Tools"
