# build-stick.ps1 - lay out a Pocket Help Desk on a drive (or any folder), from Windows.
# Windows-native twin of build-stick.sh (no Git Bash needed). Windows PowerShell 5.1+.
#
#   powershell -ExecutionPolicy Bypass -File build-stick.ps1 -Stick E:\ [-Platforms windows-x64,mac-arm64] [-NoTools]
#
#   platforms: windows-x64 windows-arm64 mac-arm64 mac-x64 linux-x64 linux-arm64 (default: windows-x64)
#
# Downloads the exact Claude Code, Codex and age versions pinned in versions.txt,
# verifies every file against the publisher's SHA-256, adds the Windows toolkit
# (tools\tools.txt) and the launchers in stick\. Re-running updates programs and
# launchers but never touches the stick's own data (home, secrets, Reports, Files).
param(
    [Parameter(Mandatory)][string]$Stick,
    [string[]]$Platforms = @('windows-x64'),
    [switch]$NoTools
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is many times slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Here = $PSScriptRoot
$Cache = Join-Path $Here '.cache'
$ClaudeBase = 'https://downloads.claude.ai/claude-code-releases'
if (-not (Test-Path $Stick)) { throw "Stick path not found: $Stick" }
$Platforms = @($Platforms | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

function Say($m) { Write-Host "==> $m" }
$v = @{}
Get-Content (Join-Path $Here 'versions.txt') | Where-Object { $_ -match '^([A-Z_]+)=(.+)$' } | ForEach-Object { $v[$Matches[1]] = $Matches[2].Trim() }
foreach ($k in 'CLAUDE_VERSION', 'CODEX_TAG', 'AGE_TAG') { if (-not $v[$k]) { throw "versions.txt has no $k" } }

$ghHeaders = @{ 'User-Agent' = 'pocket-help-desk' }
if ($env:GH_TOKEN) { $ghHeaders['Authorization'] = "Bearer $env:GH_TOKEN" }
function Get-Release($repo, $tag) { Invoke-RestMethod "https://api.github.com/repos/$repo/releases/tags/$tag" -Headers $ghHeaders }
function Get-Verified($url, $file, $sha256) {
    # download unless the cached copy already matches; always check the hash
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    if (-not ((Test-Path $file) -and (Get-FileHash $file -Algorithm SHA256).Hash -eq $sha256.ToUpper())) {
        Invoke-WebRequest $url -OutFile "$file.part" -UseBasicParsing
        if ((Get-FileHash "$file.part" -Algorithm SHA256).Hash -ne $sha256.ToUpper()) { Remove-Item "$file.part"; throw "checksum mismatch: $url" }
        Move-Item "$file.part" $file -Force
    }
    return $file
}
function Get-AssetSha($release, $name) {
    $a = @($release.assets | Where-Object { $_.name -eq $name })[0]
    if (-not $a -or $a.digest -notmatch '^sha256:([0-9a-f]{64})$') { throw "no checksum for $name" }
    return $Matches[1]
}

$map = @{   # stick platform -> Claude manifest key, Codex target, age os-arch, exe suffix
    'windows-x64'   = @('win32-x64', 'x86_64-pc-windows-msvc', 'windows-amd64', '.exe')
    'windows-arm64' = @('win32-arm64', 'aarch64-pc-windows-msvc', 'windows-arm64', '.exe')
    'mac-arm64'     = @('darwin-arm64', 'aarch64-apple-darwin', 'darwin-arm64', '')
    'mac-x64'       = @('darwin-x64', 'x86_64-apple-darwin', 'darwin-amd64', '')
    'linux-x64'     = @('linux-x64', 'x86_64-unknown-linux-musl', 'linux-amd64', '')
    'linux-arm64'   = @('linux-arm64', 'aarch64-unknown-linux-musl', 'linux-arm64', '')
}
foreach ($p in $Platforms) { if (-not $map.ContainsKey($p)) { throw "unknown platform: $p" } }

Say "Pinned: Claude Code $($v.CLAUDE_VERSION), Codex $($v.CODEX_TAG), age $($v.AGE_TAG)"
$manifest = Invoke-RestMethod "$ClaudeBase/$($v.CLAUDE_VERSION)/manifest.json"
$codexRel = Get-Release 'openai/codex' $v.CODEX_TAG
$ageRel = Get-Release 'FiloSottile/age' $v.AGE_TAG

foreach ($p in $Platforms) {
    $ck, $ct, $ak, $x = $map[$p]
    $bin = Join-Path $Stick "system\bin\$p"
    New-Item -ItemType Directory -Force $bin | Out-Null

    Say "${p}: Claude Code"
    $sum = $manifest.platforms.$ck.checksum
    $f = Get-Verified "$ClaudeBase/$($v.CLAUDE_VERSION)/$ck/claude$x" (Join-Path $Cache "claude\$($v.CLAUDE_VERSION)\$ck\claude$x") $sum
    Copy-Item $f (Join-Path $bin "claude$x") -Force

    # codex = the CLI; codex-code-mode-host = its tool runner (without it Codex cannot run commands)
    foreach ($part in 'codex', 'codex-code-mode-host') {
        Say "${p}: $part"
        $asset = "$part-$ct$x.tar.gz"
        $f = Get-Verified "https://github.com/openai/codex/releases/download/$($v.CODEX_TAG)/$asset" (Join-Path $Cache "codex\$($v.CODEX_TAG)\$asset") (Get-AssetSha $codexRel $asset)
        $tmp = Join-Path $Cache "codex\$($v.CODEX_TAG)\x-$p"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $tmp | Out-Null
        & "$env:SystemRoot\System32\tar.exe" -xzf $f -C $tmp; if ($LASTEXITCODE) { throw "could not unpack $asset" }
        Copy-Item (Join-Path $tmp "$part-$ct$x") (Join-Path $bin "$part$x") -Force
        Remove-Item $tmp -Recurse -Force
    }

    # age = locks the saved Claude login with your passphrase
    Say "${p}: age"
    $asset = if ($x) { "age-$($v.AGE_TAG)-$ak.zip" } else { "age-$($v.AGE_TAG)-$ak.tar.gz" }
    $f = Get-Verified "https://github.com/FiloSottile/age/releases/download/$($v.AGE_TAG)/$asset" (Join-Path $Cache "age\$($v.AGE_TAG)\$asset") (Get-AssetSha $ageRel $asset)
    $tmp = Join-Path $Cache "age\$($v.AGE_TAG)\x-$p"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $tmp | Out-Null
    if ($x) { Expand-Archive $f -DestinationPath $tmp -Force } else { & "$env:SystemRoot\System32\tar.exe" -xzf $f -C $tmp; if ($LASTEXITCODE) { throw "could not unpack $asset" } }
    Copy-Item (Join-Path $tmp "age\age$x") (Join-Path $bin "age$x") -Force
    Remove-Item $tmp -Recurse -Force
}

if (-not $NoTools -and @($Platforms | Where-Object { $_ -like 'windows-*' }).Count) {
    Say 'Windows toolkit (tools\tools.txt)'
    & (Join-Path $Here 'tools\fetch-tools.ps1') -Stick $Stick
}

Say 'Copying launchers and playbook'
# Template files are code: always refreshed. Data folders are created once, never overwritten.
Copy-Item (Join-Path $Here 'stick\*') $Stick -Recurse -Force
Copy-Item (Join-Path $Here 'stick\.metadata_never_index') $Stick -Force
foreach ($old in 'READ ME FIRST.txt', 'Guide (online).url') { Remove-Item -LiteralPath (Join-Path $Stick $old) -Force -ErrorAction SilentlyContinue }   # replaced by Guide.html
foreach ($d in 'home\claude', 'home\codex', 'secrets', 'Reports', 'Files', 'tmp') { New-Item -ItemType Directory -Force (Join-Path $Stick $d) | Out-Null }
Copy-Item (Join-Path $Stick 'work\CLAUDE.md') (Join-Path $Stick 'work\AGENTS.md') -Force   # Codex reads AGENTS.md: same rules

Set-Content (Join-Path $Stick 'system\VERSIONS.txt') -Encoding ASCII -Value @(
    "Pocket Help Desk - built $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mmZ'))",
    "Claude Code $($v.CLAUDE_VERSION)", "Codex $($v.CODEX_TAG) (guest)", "age $($v.AGE_TAG)", "Platforms: $($Platforms -join ' ')")
Get-Content (Join-Path $Stick 'system\VERSIONS.txt')
Say 'Done.'
