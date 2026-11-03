# Pocket Help Desk launcher for Windows (Windows PowerShell 5.1 compatible).
# macOS/Linux twin: launch.sh. Keep the two in step.
#
# Rule: no login ever lands on this computer. Claude's login is saved on the
# stick LOCKED with your passphrase (age); it is unlocked straight into memory
# and handed to Claude in an environment variable - never written unlocked
# anywhere. Codex is a guest: it signs in each session and keeps that login in
# memory only. Everything else Claude/Codex write goes to the stick (home\, tmp\).

$ErrorActionPreference = 'Continue'
$Stick = Split-Path -Parent $PSScriptRoot
$LoginFile = Join-Path $Stick 'secrets\claude-login.age'     # Claude's token, locked with your passphrase
$LegacyToken = Join-Path $Stick 'secrets\claude-token.txt'   # unlocked token from before locking existed

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
$Bin = Join-Path $Stick "system\bin\windows-$arch"
$Claude = Join-Path $Bin 'claude.exe'
$Codex = Join-Path $Bin 'codex.exe'
$Age = Join-Path $Bin 'age.exe'
if (-not (Test-Path $Claude)) { Write-Host "This stick has no programs for windows-$arch. Rebuild it with that platform."; exit 1 }

# ---- keep everything on the stick --------------------------------------------
foreach ($d in 'home\claude', 'home\codex', 'secrets', 'Reports', 'Files', 'tmp') { New-Item -ItemType Directory -Force (Join-Path $Stick $d) | Out-Null }
$Tmp = Join-Path $Stick 'tmp'
# One launcher at a time: a second one would wipe the first one's scratch files.
$InUse = Join-Path $Stick 'home\.in-use'
$me = "$env:COMPUTERNAME $PID"
if (Test-Path $InUse) {
    $other = (Get-Content $InUse -ErrorAction SilentlyContinue | Select-Object -First 1) -split ' '
    if ($other.Count -eq 2 -and $other[0] -eq $env:COMPUTERNAME -and [int]$other[1] -ne $PID -and (Get-Process -Id ([int]$other[1]) -ErrorAction SilentlyContinue)) {
        Write-Host 'Pocket Help Desk is already running in another window on this computer - use that one, or close it first.'
        exit 1
    }
}
Get-ChildItem $Tmp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue  # leftovers, e.g. from a pulled stick
Remove-Item (Join-Path $Stick 'home\codex\tmp') -Recurse -Force -ErrorAction SilentlyContinue
$env:CLAUDE_CONFIG_DIR = Join-Path $Stick 'home\claude'
$env:CLAUDE_CODE_TMPDIR = $Tmp
$env:TEMP = $Tmp; $env:TMP = $Tmp
$env:DISABLE_UPDATES = '1'; $env:DISABLE_AUTOUPDATER = '1'
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
$env:CODEX_HOME = Join-Path $Stick 'home\codex'
# Codex databases are not portable between Windows/macOS/Linux builds (a DB made
# by one is rejected by another as "modified"), so each system gets its own.
# Login, settings and chat history stay shared in home\codex.
$env:CODEX_SQLITE_HOME = Join-Path $Stick 'home\codex\db-windows'
New-Item -ItemType Directory -Force $env:CODEX_SQLITE_HOME | Out-Null
$env:POCKET_HELP_DESK = $Stick
$env:BROWSER = Join-Path $Stick 'system\open-private.cmd'   # sign-in pages open in a private window
# Start clean: drop anything inherited from this computer that could redirect or
# replace our logins (other keys, custom endpoints, cloud providers).
Get-ChildItem env: | Where-Object { $_.Name -match '^(ANTHROPIC_|OPENAI_|CLAUDE_CODE_USE_|CLAUDE_CODE_OAUTH|CODEX_API|CODEX_ACCESS)' } | ForEach-Object { Remove-Item "env:$($_.Name)" }
$Work = Join-Path $Stick 'work'
# The toolkit (see work\TOOLS.md) on PATH, so Claude can run smartctl, autorunsc... by name
$ToolsDir = Join-Path $Stick 'Tools'
$toolPaths = @('sysinternals', 'smartmontools\bin', '7zip', 'nirsoft') | ForEach-Object { Join-Path $ToolsDir $_ } | Where-Object { Test-Path $_ }
if ($toolPaths) { $env:PATH = ($toolPaths -join ';') + ';' + $env:PATH; $env:PSModulePath = $ToolsDir + ';' + $env:PSModulePath }
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ---- "did we leave anything behind" ------------------------------------------
# Default places Claude Code and Codex use on a computer. We note what exists
# before; at the end anything NEW is a leak. A folder that already existed
# (this computer has its own Claude) is a leak only if it now holds something
# named after the stick: Claude files its history under the working folder's
# path with every non-letter/digit turned into '-' (E:\work -> E--work).
$TracePaths = @(
    "$env:USERPROFILE\.claude", "$env:USERPROFILE\.claude.json", "$env:USERPROFILE\.codex",
    "$env:USERPROFILE\.local\bin\claude.exe", "$env:USERPROFILE\.local\share\claude",
    "$env:APPDATA\Anthropic", "$env:LOCALAPPDATA\claude-cli-nodejs",
    "$env:LOCALAPPDATA\Temp\claude"   # the computer's own temp folder (ours is redirected to the stick)
)
function Get-CredNames { (cmdkey /list 2>$null) | Where-Object { $_ -match 'Target:.*(claude|codex|anthropic|openai)' } }
$Start = Get-Date
$BeforeExist = @($TracePaths | Where-Object { Test-Path $_ })
$BeforeCreds = @(Get-CredNames)
# Sysinternals tools note "licence accepted" in the registry (HKCU\Software\Sysinternals\<tool>).
# Remember what was there, and at the end remove only the notes this session added.
$SysKey = 'HKCU:\Software\Sysinternals'
$SysKeyExisted = Test-Path $SysKey
$SysBefore = @(if ($SysKeyExisted) { (Get-ChildItem $SysKey).PSChildName })
function Remove-SysinternalsNotes {
    if (-not (Test-Path $SysKey)) { return }
    $removed = @()
    foreach ($k in @(Get-ChildItem $SysKey)) {
        $vals = @($k.GetValueNames())
        if ($SysBefore -notcontains $k.PSChildName -and @($vals | Where-Object { $_ -ne 'EulaAccepted' }).Count -eq 0 -and $k.SubKeyCount -eq 0) {
            Remove-Item $k.PSPath -Recurse -Force; $removed += $k.PSChildName
        }
    }
    $root = Get-Item $SysKey
    if (-not $SysKeyExisted -and $root.SubKeyCount -eq 0 -and @($root.GetValueNames()).Count -eq 0) { Remove-Item $SysKey -Force }
    if ($removed.Count) { Write-Host "  Removed Sysinternals licence notes this session added: $($removed -join ', ')" }
}

function Show-TraceReport {
    Write-Host ''
    Write-Host 'Checking this computer for anything Claude or Codex left behind...'
    Remove-SysinternalsNotes
    Remove-StrayClaudeLogin
    $found = $false; $ownInUse = $false
    $fingerprint = $Work -replace '[^A-Za-z0-9]', '-'
    foreach ($p in $TracePaths) {
        if (-not (Test-Path $p)) { continue }
        if ($BeforeExist -contains $p) {
            if (-not (Get-Item $p -Force).PSIsContainer) { continue }
            $recent = @(Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $Start })
            $ours = @($recent | Where-Object { $_.FullName -like "*$fingerprint*" })
            if ($ours.Count) { Write-Host "  FOUND stick data in: $p"; $ours | Select-Object -First 3 | ForEach-Object { Write-Host "    $($_.FullName)" }; $found = $true }
            elseif ($recent.Count) { $ownInUse = $true }
        } else { Write-Host "  NEW:     $p"; $found = $true }
    }
    $after = @(Get-CredNames)
    $newCreds = @($after | Where-Object { $BeforeCreds -notcontains $_ })
    if ($newCreds.Count) { Write-Host '  NEW saved Windows credentials:'; $newCreds | ForEach-Object { Write-Host "    $_" }; $found = $true }
    if (-not $found) { Write-Host '  No Claude or Codex files or saved logins found in the usual places on this computer.' }
    if ($ownInUse) { Write-Host "  (This computer's own Claude/Codex was busy meanwhile - its files were left alone.)" }
}

# ---- logins ------------------------------------------------------------------
# Claude/Codex leave terminal replies in the keyboard buffer when they exit;
# without this the next prompt reads them as if you had typed them.
function Clear-Keys { try { $Host.UI.RawUI.FlushInputBuffer() } catch {} }
function Read-Choice { Clear-Keys; return (Read-Host '>') }
function New-ClaudeToken {
    Write-Host ''
    Write-Host 'Claude sign-in: a private browser window opens. Sign in and approve,'
    Write-Host 'then close that window and come back here. Waiting for you...'
    # Captured, not shown: Claude prints the token on a screen it wipes on exit.
    # Output: "Your OAuth token (valid for ...): <token>  Store this token securely..."
    $out = (& $Claude setup-token 2>&1 | Out-String) -replace "\x1b\[[0-9;?]*[A-Za-z]", ''
    $i = $out.IndexOf('sk-ant-oat')
    if ($i -ge 0) {
        $rest = $out.Substring($i)
        $j = $rest.IndexOf('Store this token')
        $rest = if ($j -gt 0) { $rest.Substring(0, $j) } else { ($rest -split '\s')[0] }
        $t = $rest -replace '\s', ''   # the token may be wrapped over several lines
        if ($t -match '^sk-ant-oat[0-9A-Za-z_\-]+$') { Write-Host 'Signed in to Claude.'; return $t }
    }
    Write-Host "Couldn't read a Claude token from the sign-in - nothing was saved. Try again (Logins, menu 3)."
    return ''
}
# Lock a token with a passphrase. age asks for the passphrase itself, straight
# from the keyboard - this script never sees it. Written to a new file first and
# swapped in only on success, so a mistake never destroys the existing login.
function Lock-ClaudeLogin($token) {
    Write-Host ''
    Write-Host 'Choose a passphrase to lock your Claude login. Use 4 or more random words.'
    Write-Host '(Leave it empty and age makes up a strong one - write it down.) You type it twice.'
    $new = "$LoginFile.new"
    Remove-Item $new -Force -ErrorAction SilentlyContinue
    Clear-Keys
    $token | & $Age -p -o $new
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $new) -or (Get-Item $new).Length -eq 0) {
        Remove-Item $new -Force -ErrorAction SilentlyContinue
        Write-Host 'Not locked - nothing changed.'; return $false
    }
    try { Move-Item $new $LoginFile -Force -ErrorAction Stop }
    catch {
        Remove-Item $new -Force -ErrorAction SilentlyContinue
        Write-Host "Couldn't save the locked login ($($_.Exception.Message)) - nothing changed."; return $false
    }
    Write-Host 'Locked. From now on Claude asks for this passphrase when it starts.'
    return $true
}
function Unlock-ClaudeLogin {
    Write-Host 'Unlocking your Claude login...'
    Clear-Keys
    $res = & $Age -d $LoginFile 2>&1
    $ok = ($LASTEXITCODE -eq 0)
    $t = (@($res | Where-Object { $_ -is [string] }) -join '').Trim()
    if (-not $ok -or $t -notmatch '^sk-ant-oat[0-9A-Za-z_\-]+$') {
        $why = @($res | Where-Object { $_ -isnot [string] }) -join ' '
        Write-Host "Couldn't unlock it ($why). Nothing was started."
        return $null
    }
    return $t
}
# Fail closed: if the saved login no longer works, stop here. Otherwise Claude
# would offer its own sign-in, and that saves a login outside our control.
function Test-ClaudeLogin($token) {
    Write-Host 'Checking the login...'
    # A bare one-line request from the stick's own folder: no hooks, no MCP servers, no tools.
    $psi = New-Object Diagnostics.ProcessStartInfo $Claude
    $psi.Arguments = '-p --model haiku --max-turns 1 --no-session-persistence --strict-mcp-config --tools= --settings "' +
        (Join-Path $PSScriptRoot 'login-check-settings.json') + '" "Reply with exactly: OK"'
    $psi.WorkingDirectory = $Work
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['CLAUDE_CODE_OAUTH_TOKEN'] = $token
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(30000)) {
        try { $p.Kill() } catch {}
        Write-Host 'The login check got no answer in 30 s (no internet?) - nothing was started.'; return $false
    }
    if ($p.ExitCode -eq 0) { return $true }
    $msg = (($o.Result + ' ' + $e.Result) -replace 'sk-ant-[A-Za-z0-9_\-]+', '[hidden]' -replace '\s+', ' ').Trim()
    if ($msg.Length -gt 200) { $msg = $msg.Substring(0, 200) + '...' }
    Write-Host "Claude didn't accept the saved login: $msg"
    Write-Host 'If it expired or was revoked: Logins (menu 3) > sign Claude in again. No internet? Connect and retry.'
    return $false
}
# Belt and braces: a Claude sign-in that slipped through would land in home\claude
function Remove-StrayClaudeLogin {
    $f = Join-Path $env:CLAUDE_CONFIG_DIR '.credentials.json'
    if (Test-Path $f) { Remove-Item $f -Force; Write-Host '  Removed a Claude sign-in that was saved outside the lock.' }
}
function Test-HasLockedLogin { return ((Test-Path $LoginFile) -and (Get-Item $LoginFile).Length -gt 0) }
function Start-Claude {
    $token = $null
    if (-not (Test-HasLockedLogin)) {
        if (Test-Path $LegacyToken) {
            Write-Host "Your Claude login on this stick isn't locked yet - let's lock it now (once)."
            $t = [IO.File]::ReadAllText($LegacyToken).Trim()
        } else {
            Write-Host "No Claude login on this stick yet - let's set it up once (best done at home)."
            $t = New-ClaudeToken
        }
        if (-not $t) { return }
        if (-not (Lock-ClaudeLogin $t)) { $t = $null; return }
        # A brand-new sign-in: use it straight away rather than asking for the passphrase a third
        # time. (With an old unlocked copy we DO unlock again below - that proves the locked file
        # works before the old copy is deleted.)
        if (-not (Test-Path $LegacyToken)) { $token = $t }
        $t = $null
    }
    if (-not $token) { $token = Unlock-ClaudeLogin }
    if (-not $token) { return }
    if (-not (Test-ClaudeLogin $token)) { $token = $null; return }
    # The locked login just proved it works - only now is an old unlocked copy safe to delete.
    if (Test-Path $LegacyToken) { Remove-Item $LegacyToken -Force; Write-Host 'Removed the old unlocked copy of the Claude login.' }
    Push-Location $Work
    try { $env:CLAUDE_CODE_OAUTH_TOKEN = $token; & $Claude }
    finally { Remove-Item env:CLAUDE_CODE_OAUTH_TOKEN -ErrorAction SilentlyContinue; $token = $null; Pop-Location; Remove-StrayClaudeLogin }
}
# Codex login mode, a plain setting on the stick (home\stick-settings.txt):
#   guest (default) - signs in each session, the login lives in memory only
#   saved           - the login is kept on the stick UNLOCKED (Codex reads it as a file and
#                     renews it itself, so it cannot be passphrase-locked like Claude's).
#                     Only for a stick that never leaves you, or a hardware-encrypted drive.
$SettingsFile = Join-Path $Stick 'home\stick-settings.txt'
$CodexLogin = Join-Path $env:CODEX_HOME 'auth.json'
function Get-CodexMode {
    if ((Test-Path $SettingsFile) -and (Select-String -Path $SettingsFile -Pattern '^CODEX_LOGIN=saved\s*$' -Quiet)) { return 'saved' }
    return 'guest'
}
function Set-CodexMode($mode) {
    $lines = @(if (Test-Path $SettingsFile) { Get-Content $SettingsFile | Where-Object { $_ -notmatch '^CODEX_LOGIN=' } })
    if ($mode -eq 'saved') { $lines += 'CODEX_LOGIN=saved' }
    Set-Content -Path $SettingsFile -Value $lines -Encoding ASCII
}
function Get-CodexStore { if ((Get-CodexMode) -eq 'saved') { return 'file' } return 'ephemeral' }
function Remove-CodexLogin {   # sign out with OpenAI, then delete it from the stick
    $said = (& $Codex -c 'cli_auth_credentials_store=file' -c 'check_for_update_on_startup=false' logout 2>&1 | Out-String)
    $said = ($said -replace '[A-Za-z0-9_\-]{40,}', '[hidden]' -replace '\s+', ' ').Trim()
    Remove-Item $CodexLogin -Force -ErrorAction SilentlyContinue
    if (Test-Path $CodexLogin) { Write-Host "Couldn't delete it: $CodexLogin" } else { Write-Host "Codex's login is deleted from the stick." }
    if ($said) { Write-Host "Codex's sign-out said: $said" }
}
function Start-Codex {
    if ((Get-CodexMode) -eq 'saved') {
        if (-not (Test-Path $CodexLogin)) {
            Write-Host "Codex keeps its login on this stick (unlocked). Sign in once: pick 'Sign in with Device Code'"
            Write-Host 'and type the code on your phone. Only ever type a code this screen just showed you.'
        }
    } else {
        Write-Host 'Codex is a guest on this stick: sign in each time (nothing is saved).'
        Write-Host "Pick 'Sign in with Device Code' and type the code on your phone (needs the device-code"
        Write-Host 'switch on in ChatGPT security settings). Only ever type a code this screen just showed you.'
    }
    # No Codex sandbox on Windows: setting it up would add users and firewall rules to this computer.
    # Codex 0.164 only offers on-request|never approvals, so on Windows the "ask before every change" rule rests on the ground rules (AGENTS.md).
    # SSH_CONNECTION tells Codex there is no usable desktop, so even 'Sign in with ChatGPT' shows a
    # link and code instead of opening this computer's browser (Codex ignores BROWSER on Windows).
    $env:SSH_CONNECTION = '127.0.0.1 0 127.0.0.1 0'
    Push-Location $Work
    try { & $Codex -c "cli_auth_credentials_store=$(Get-CodexStore)" -c 'check_for_update_on_startup=false' --sandbox danger-full-access --ask-for-approval on-request }
    finally { Remove-Item env:SSH_CONNECTION -ErrorAction SilentlyContinue; Pop-Location }
}
function Show-LoginsMenu {
    while ($true) {
        Write-Host ''
        Write-Host 'Logins'
        Write-Host '  1) Sign Claude in again (new login, locked with a passphrase)'
        Write-Host '  2) Forget the saved Claude login'
        if ((Get-CodexMode) -eq 'saved') { Write-Host '  3) Codex: login SAVED on this stick - switch back to guest (signs out, deletes it)' }
        else { Write-Host '  3) Codex: guest (signs in each time) - switch to keeping its login on this stick' }
        Write-Host '  B) Back'
        $c = Read-Choice
        switch ($c) {
            '1' { $t = New-ClaudeToken
                  if ($t -and (Lock-ClaudeLogin $t)) { Write-Host 'Tip: remove the old token in your Claude account settings.' }
                  $t = $null }
            '2' { Remove-Item $LoginFile, $LegacyToken -Force -ErrorAction SilentlyContinue
                  Write-Host 'The saved Claude login is deleted from the stick.'
                  Write-Host 'If the stick was ever out of your hands, also remove the token in your Claude account settings.' }
            '3' { if ((Get-CodexMode) -eq 'saved') {
                      if ((Read-Host 'Sign Codex out and delete its saved login from this stick? (Y/n)') -notmatch '^[nN]') {
                          if (Test-Path $CodexLogin) { Remove-CodexLogin }
                          Set-CodexMode 'guest'; Write-Host 'Codex is a guest again: it signs in each time.'
                      }
                  } else {
                      Write-Host ''
                      Write-Host "Codex can't lock its login with your passphrase: it would sit UNLOCKED on this stick," -ForegroundColor Yellow
                      Write-Host 'and anyone holding the stick could use your ChatGPT account. Only do this on a stick that' -ForegroundColor Yellow
                      Write-Host 'never leaves you, or on a hardware-encrypted (keypad) drive.' -ForegroundColor Yellow
                      if ((Read-Host 'Type SAVE to keep Codex signed in on this stick (anything else cancels)') -ceq 'SAVE') {
                          Set-CodexMode 'saved'; Write-Host 'Done. Next time you start Codex, sign in once and it stays signed in.'
                      } else { Write-Host 'Nothing changed - Codex stays a guest.' }
                  } }
            default { return }
        }
    }
}
# Old logins from before locking existed. Interactive only, and only with a yes.
function Resolve-OldLogins {
    if ((Test-Path $LegacyToken) -and (Test-HasLockedLogin)) {
        # Never delete the old copy just because a locked file exists: it goes only after
        # the locked login has been unlocked and accepted by Claude (see Start-Claude).
        Write-Host ''
        Write-Host 'Note: an old unlocked copy of the Claude login is still on the stick. It will be'
        Write-Host 'removed automatically the first time your locked login starts Claude successfully.'
    } elseif (Test-Path $LegacyToken) {
        Write-Host ''
        Write-Host 'Your Claude login on this stick is NOT locked yet.'
        if ((Read-Host 'Lock it now with a passphrase? (Y/n)') -notmatch '^[nN]') {
            $t = [IO.File]::ReadAllText($LegacyToken).Trim()
            if (Lock-ClaudeLogin $t) { Write-Host 'The old unlocked copy goes as soon as the locked login starts Claude successfully.' }
            $t = $null
        }
    }
    # A Codex login on a stick set to "guest" (e.g. from an older stick): offer to remove it.
    if ((Test-Path $CodexLogin) -and (Get-CodexMode) -eq 'guest') {
        Write-Host ''
        Write-Host 'This stick holds a saved Codex login, but Codex is set to guest (sign in each time),'
        Write-Host 'so that login should go: Codex signs it out with OpenAI, then it is deleted from the stick.'
        Write-Host '(To keep Codex signed in instead, answer n and use Logins, menu 3.)'
        if ((Read-Host 'Do that now? (Y/n)') -notmatch '^[nN]') { Remove-CodexLogin }
    }
}

# ---- non-interactive: launch.ps1 claude|codex [args...] (scripts and tests) --
if ($args.Count -gt 0) {
    $tool = $args[0]; $rest = @($args | Select-Object -Skip 1)
    Push-Location $Work
    if ($tool -eq 'claude') {
        # POCKET_HELP_DESK_NO_LOGIN=1: run without unlocking (tests)
        if ((Test-HasLockedLogin) -and -not $env:POCKET_HELP_DESK_NO_LOGIN) { $t = Unlock-ClaudeLogin; if (-not $t) { exit 1 }; $env:CLAUDE_CODE_OAUTH_TOKEN = $t; $t = $null }
        & $Claude @rest
        Remove-StrayClaudeLogin
    } elseif ($tool -eq 'codex') {
        & $Codex -c "cli_auth_credentials_store=$(Get-CodexStore)" -c 'check_for_update_on_startup=false' @rest
    } else { Write-Host 'usage: launch.ps1 [claude|codex [args...]]'; exit 2 }
    $rc = $LASTEXITCODE
    Pop-Location
    Get-ChildItem $Tmp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    exit $rc
}

# ---- pull the stick = everything stops ----------------------------------------
# Windows keeps a running program - and its login - in memory after the stick is
# pulled, so whoever sits down next could keep chatting. A watcher (a thread in
# this process, nothing written anywhere) checks for the stick every 1.5 s; when
# it has been gone for 3 checks in a row (~4.5 s - a busy or briefly stalled
# drive never trips it) it closes Claude/Codex, this launcher and its window.
$top = $PID
$parent = Get-CimInstance Win32_Process -Filter "ProcessId=$((Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId)" -ErrorAction SilentlyContinue
if ($parent -and $parent.Name -eq 'cmd.exe' -and $parent.CommandLine -like "*$Stick*") { $top = $parent.ProcessId }
$Watchdog = [PowerShell]::Create()
[void]$Watchdog.AddScript({
    param($marker, $top)
    $missing = 0
    while ($missing -lt 3) {
        Start-Sleep -Milliseconds 1500
        if (Test-Path $marker) { $missing = 0 } else { $missing++ }
    }
    # Claude runs with its working folder on the stick, which is now gone, and Windows
    # won't start any program from a vanished folder - so move off it, and close the
    # processes directly (no helper program): the window's tree by exact PID, this one last.
    [Environment]::CurrentDirectory = $env:SystemRoot
    $all = @(Get-CimInstance Win32_Process)
    $tree = New-Object System.Collections.Generic.List[int]; $tree.Add([int]$top)
    for ($i = 0; $i -lt $tree.Count; $i++) {
        foreach ($p in $all) { if ($p.ParentProcessId -eq $tree[$i] -and -not $tree.Contains([int]$p.ProcessId)) { $tree.Add([int]$p.ProcessId) } }
    }
    for ($i = $tree.Count - 1; $i -ge 0; $i--) {
        if ($tree[$i] -ne $PID) { try { [Diagnostics.Process]::GetProcessById($tree[$i]).Kill() } catch {} }
    }
    [Diagnostics.Process]::GetCurrentProcess().Kill()
}).AddArgument($PSCommandPath).AddArgument($top)
[void]$Watchdog.BeginInvoke()

# ---- main --------------------------------------------------------------------
Set-Content -Path $InUse -Value $me -Encoding ASCII
Resolve-OldLogins
$ver = (Get-Content (Join-Path $Stick 'system\VERSIONS.txt') -ErrorAction SilentlyContinue | Select-Object -Skip 1 -First 2) -join '  '
while ($true) {
    Write-Host ''
    $who = if ($IsAdmin) { ", administrator" } else { "" }
    Write-Host "=== Pocket Help Desk ===  (windows-$arch$who)  $ver"
    Write-Host '  1) Claude'
    if ((Get-CodexMode) -eq 'saved') { Write-Host '  2) Codex (login saved on this stick)' } else { Write-Host '  2) Codex (guest - requires login)' }
    Write-Host '  3) Logins'
    Write-Host '  Q) Quit (cleans up and checks this computer)'
    $choice = Read-Choice
    if ($null -eq $choice) { break }   # input closed (e.g. piped) - don't spin
    if ($choice -eq '1') { Start-Claude }
    elseif ($choice -eq '2') { Start-Codex }
    elseif ($choice -eq '3') { Show-LoginsMenu }
    elseif ($choice -eq 'q' -or $choice -eq 'Q') { break }
}
Show-TraceReport
Get-ChildItem $Tmp -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $InUse -Force -ErrorAction SilentlyContinue
Write-Host 'Done. You can unplug the stick.'
