# Login plumbing test (Windows): the launcher's lock / unlock / fail-closed / keep-until-proven
# logic, with age swapped for a stand-in (age reads the passphrase straight from the console,
# which a script cannot type into - a hands-on test on a real stick covers real age on Windows).
#
#   pwsh -File tests\login-plumbing-test.ps1 -Stick <throwaway copy> [-RealToken <file>]
#
# DESTRUCTIVE to the stick it is given: refuses unless the folder has .disposable-test-stick.
# -RealToken: a file holding a real Claude token, to prove the success path (stays on this computer).
param([Parameter(Mandatory)][string]$Stick, [string]$RealToken)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $Stick '.disposable-test-stick'))) { throw "Refusing: $Stick is not marked as a throwaway test stick (.disposable-test-stick)." }
$launcher = Join-Path $Stick 'system\launch.ps1'
$secrets = Join-Path $Stick 'secrets'; $login = Join-Path $secrets 'claude-login.age'; $legacy = Join-Path $secrets 'claude-token.txt'
$bin = Join-Path $Stick 'system\bin\windows-x64'

# stand-in age: "-p -o FILE" stores stdin as MOCK:<text>; "-d FILE" prints it back. Same interface the launcher uses.
Set-Content (Join-Path $bin 'age-mock.ps1') -Encoding ASCII -Value @'
$a = $args
if ($a[0] -eq '-p') { $t = [Console]::In.ReadToEnd().Trim(); [IO.File]::WriteAllText($a[2], "MOCK:$t"); exit 0 }
if ($a[0] -eq '-d') { $s = [IO.File]::ReadAllText($a[1]); if (-not $s.StartsWith('MOCK:')) { [Console]::Error.WriteLine('age: error: incorrect passphrase'); exit 1 }; [Console]::Out.Write($s.Substring(5)); exit 0 }
exit 2
'@
Set-Content (Join-Path $bin 'age.cmd') -Encoding ASCII -Value '@powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0age-mock.ps1" %*'
(Get-Content $launcher -Raw).Replace("Join-Path `$Bin 'age.exe'", "Join-Path `$Bin 'age.cmd'") | Set-Content $launcher -Encoding UTF8

function Run([string[]]$keys, [int]$seconds = 90) {
    $in = Join-Path $env:TEMP 'plumb-in.txt'; Set-Content $in ($keys -join "`r`n") -Encoding ASCII
    $p = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$launcher`"" `
        -RedirectStandardInput $in -RedirectStandardOutput "$in.out" -RedirectStandardError "$in.err" -NoNewWindow -PassThru
    if (-not $p.WaitForExit($seconds * 1000)) { $p.Kill() }
    $o = (Get-Content "$in.out" -Raw) + (Get-Content "$in.err" -Raw)
    Remove-Item $in, "$in.out", "$in.err" -ErrorAction SilentlyContinue
    return $o
}
$results = @()
function Check($name, $ok) { $script:results += [pscustomobject]@{ name = $name; ok = [bool]$ok }; Write-Host ("{0} {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name) }

# 1. fake old token: lock at start (y), then Claude (1) rejects it -> launch stops, old copy kept
Remove-Item $login, $legacy -ErrorAction SilentlyContinue
$fake = 'sk-ant-oat01-FAKEplumbingTest0123456789abcdefABCDEF'
[IO.File]::WriteAllText($legacy, $fake)
$o = Run @('y', '1', 'q')
Check 'old token locked (claude-login.age written)' ((Test-Path $login) -and (Get-Content $login -Raw).StartsWith('MOCK:'))
Check 'rejected login stops the launch' ($o -match "didn't accept the saved login")
Check 'old unlocked copy KEPT when the login did not work' (Test-Path $legacy)
Check 'token never printed' ($o -notmatch [regex]::Escape($fake))

# 2. a failed lock changes nothing (age stand-in refuses)
Remove-Item $login -ErrorAction SilentlyContinue
(Get-Content (Join-Path $bin 'age-mock.ps1') -Raw).Replace("if (`$a[0] -eq '-p') {", "if (`$a[0] -eq '-p') { exit 1;") | Set-Content (Join-Path $bin 'age-mock.ps1') -Encoding ASCII
$o = Run @('y', 'q')
Check 'failed lock reports failure and changes nothing' (($o -match 'Not locked - nothing changed') -and -not (Test-Path $login) -and (Test-Path $legacy))
(Get-Content (Join-Path $bin 'age-mock.ps1') -Raw).Replace("if (`$a[0] -eq '-p') { exit 1;", "if (`$a[0] -eq '-p') {") | Set-Content (Join-Path $bin 'age-mock.ps1') -Encoding ASCII

# 3. wrong "passphrase" (file not produced by this age) refuses before anything starts
[IO.File]::WriteAllText($login, 'not-an-age-file')
$o = Run @('1', 'q')
Check 'unreadable lock refuses, nothing started' (($o -match "Couldn't unlock it") -and ($o -notmatch 'Checking the login'))

# 4. success path with a REAL token: login accepted -> old copy removed
if ($RealToken) {
    Remove-Item $login -ErrorAction SilentlyContinue
    [IO.File]::WriteAllText($legacy, ([IO.File]::ReadAllText($RealToken).Trim()))
    $o = Run @('y', '1', 'q') 120
    Check 'real login accepted' ($o -match 'Checking the login' -and $o -notmatch "didn't accept")
    Check 'old unlocked copy removed once the locked login worked' (($o -match 'Removed the old unlocked copy') -and -not (Test-Path $legacy))
    Check 'real token never printed' ($o -notmatch 'sk-ant-oat01-[A-Za-z0-9_\-]{20,}')
    Remove-Item $login, $legacy -ErrorAction SilentlyContinue
}
Remove-Item $login, $legacy -ErrorAction SilentlyContinue

# 5. Codex login mode (main menu 3 = Logins, then 3 = the Codex switch): guest by default; SAVE switches to saved; back to guest
$settings = Join-Path $Stick 'home\stick-settings.txt'; $codexLogin = Join-Path $Stick 'home\codex\auth.json'
Remove-Item $settings, $codexLogin -ErrorAction SilentlyContinue
function IsSaved { (Test-Path $settings) -and (Select-String -Path $settings -Pattern '^CODEX_LOGIN=saved' -Quiet) }
$o = Run @('3', '3', 'nope', 'b', 'q')
Check 'codex: anything but SAVE cancels' (($o -match 'Codex stays a guest') -and -not (IsSaved))
$o = Run @('3', '3', 'SAVE', 'b', 'q')
Check 'codex: SAVE switches to a saved login' ((IsSaved) -and ($o -match 'login saved on this stick'))
Set-Content $codexLogin '{}'
$o = Run @('q')
Check 'codex saved: an existing login is left alone at start' ((Test-Path $codexLogin) -and ($o -notmatch 'set to guest'))
$o = Run @('3', '3', 'y', 'b', 'q')
Check 'codex: back to guest deletes the saved login' ((-not (Test-Path $codexLogin)) -and ($o -match 'guest again') -and -not (IsSaved))
Set-Content $codexLogin '{}'
$o = Run @('y', 'q')
Check 'codex guest: a leftover login is offered for removal at start' (($o -match 'set to guest') -and -not (Test-Path $codexLogin))
Remove-Item $settings, $codexLogin -ErrorAction SilentlyContinue
"`n{0}/{1} passed" -f @($results | Where-Object ok).Count, $results.Count
