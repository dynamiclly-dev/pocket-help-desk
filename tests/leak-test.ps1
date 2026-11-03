# Leak test (Windows): run the stick with a brand-new, empty fake user profile,
# then list everything that appeared in that profile. Anything listed = a leak.
#
#   pwsh -File tests\leak-test.ps1 -Stick E:\
#
# Uses no logins: the stick's locked Claude login is never unlocked.
param([Parameter(Mandatory)] [string]$Stick)
$ErrorActionPreference = 'Stop'
$Fake = Join-Path ([IO.Path]::GetTempPath()) ("stick-leaktest-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
foreach ($d in 'AppData\Roaming', 'AppData\Local\Temp') { New-Item -ItemType Directory -Force (Join-Path $Fake $d) | Out-Null }
$launcher = Join-Path $Stick 'system\launch.ps1'
$env:POCKET_HELP_DESK_NO_LOGIN = '1'   # never unlock (or wait for) a real login during the test

# The child inherits a profile that points at the empty fake folder.
$env:USERPROFILE = $Fake; $env:HOME = $Fake; $env:HOMEPATH = $Fake.Substring(2); $env:HOMEDRIVE = $Fake.Substring(0, 2)
$env:APPDATA = "$Fake\AppData\Roaming"; $env:LOCALAPPDATA = "$Fake\AppData\Local"
$env:TEMP = "$Fake\AppData\Local\Temp"; $env:TMP = $env:TEMP

function Run([string[]]$a) {
    Write-Host "--- launch.ps1 $($a -join ' ')"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $launcher @a 2>&1 | Select-Object -First 15 | ForEach-Object { Write-Host "    $_" }
}
Run @('claude', '--version')
Run @('codex', '--version')
Run @('codex', 'login', 'status')
Run @('claude', '-p', 'Reply with exactly: STICK OK')   # without a token this fails at sign-in - startup still runs
Write-Host '--- interactive menu, then Q (runs the exit check)'
# 'n' declines first-run questions (lock an old login? remove an old Codex login?); at the menu it is ignored
@('n', 'n', 'q') | & powershell -NoProfile -ExecutionPolicy Bypass -File $launcher 2>&1 | Select-Object -Last 6 | ForEach-Object { Write-Host "    $_" }

Write-Host ''
$left = @(Get-ChildItem $Fake -Recurse -Force -File -ErrorAction SilentlyContinue)
if ($left.Count -eq 0) { Write-Host "RESULT: CLEAN - nothing written to the fake profile ($Fake)" }
else { Write-Host "RESULT: LEAK - $($left.Count) file(s) in the fake profile:"; $left | ForEach-Object { Write-Host "    $($_.FullName.Substring($Fake.Length))" } }
Remove-Item $Fake -Recurse -Force -ErrorAction SilentlyContinue
