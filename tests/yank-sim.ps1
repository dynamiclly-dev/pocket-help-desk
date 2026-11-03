# Yank simulation (Windows): run the stick from a temporary drive letter (subst),
# start Claude from the real Start (Windows).cmd, then delete the drive letter -
# like pulling the stick. PASS = window, launcher and Claude all gone.
#   pwsh -File tests\yank-sim.ps1 -Launcher <path to launch.ps1 to test>
param([Parameter(Mandatory)][string]$Launcher, [string]$Letter = 'Y')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $repo ".cache\yanksim-$([guid]::NewGuid().ToString('N').Substring(0,6))"
New-Item -ItemType Directory -Force "$root\system\bin\windows-x64", "$root\secrets" | Out-Null
Copy-Item "$repo\stick\*" $root -Recurse -Force
Copy-Item $Launcher "$root\system\launch.ps1" -Force
$c = Get-ChildItem "$repo\.cache\claude" -Recurse -Filter claude.exe | Where-Object FullName -like '*win32-x64*' | Select-Object -First 1
Copy-Item $c.FullName "$root\system\bin\windows-x64\claude.exe"; Copy-Item $c.FullName "$root\system\bin\windows-x64\codex.exe"
Set-Content "$root\secrets\claude-token.txt" 'sk-ant-oat01-notarealtokenjustatest' -NoNewline
# test-only: pick menu item 1 (Claude) automatically on the first pass
$f = "$root\system\launch.ps1"
(Get-Content $f -Raw).Replace('    $choice = Read-Choice', '    if (-not $auto) { $auto = 1; $choice = ''1'' } else { $choice = Read-Choice }') | Set-Content $f
if (Test-Path "${Letter}:\") { throw "${Letter}: is in use" }
subst "${Letter}:" $root
$p = Start-Process cmd.exe -ArgumentList '/c', "`"`"${Letter}:\Start (Windows).cmd`" `"" -WindowStyle Minimized -PassThru
Start-Sleep 10
$cl = Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -like "${Letter}:\*claude.exe" -or $_.ExecutablePath -like "$root\*claude.exe" }
"Claude running before yank: $([bool]$cl)"
subst "${Letter}:" /d; $t0 = Get-Date
Start-Sleep 10
$left = @(Get-Process -Id (@($p.Id) + @($cl.ProcessId)) -ErrorAction SilentlyContinue)
if ($left.Count) { "FAIL: still running 10 s after the yank: $($left.ProcessName -join ', ')"; $left | ForEach-Object { Stop-Process -Id $_.Id -Force } }
else { 'PASS: window, launcher and Claude all closed after the yank' }
Start-Sleep 1; Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
