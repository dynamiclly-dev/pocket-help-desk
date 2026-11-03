# Toolkit

Everything here runs from the stick; nothing gets installed. On Windows the launcher puts the main tool folders on PATH, so run them by name. Tools live under `$POCKET_HELP_DESK/Tools`. Save any output you want to keep in `$POCKET_HELP_DESK/Files`, scratch in `$POCKET_HELP_DESK/tmp`.

Prefer TEXT output. Many tools here can write a text report (`/stext <file>`, `-c` CSV, `--json`) - use that, then read the file.

## Windows - on the stick

| Need | Tool | Example |
|---|---|---|
| Is the disk dying? | `smartctl` (smartmontools) | `smartctl --scan` then `smartctl -a /dev/sda` (admin). Read: overall-health, Reallocated/Pending sectors, NVMe "Percentage Used", "Media and Data Integrity Errors". |
| What starts with Windows? | `autorunsc64` (Sysinternals) | `autorunsc64 -accepteula -nobanner -a * -c -h -s -m` (CSV; `-m` hides Microsoft entries) |
| Is this file genuine / signed? | `sigcheck64` | `sigcheck64 -accepteula -nobanner -e -u -s C:\Users\x\AppData` (unsigned executables) |
| What's running / using the network | `pslist64`, `tcpvcon64` | `tcpvcon64 -accepteula -nobanner -a -c` |
| What is locking a file? | `handle64` | `handle64 -accepteula -nobanner <name>` |
| What is using the disk space? | `du64` | `du64 -accepteula -nobanner -l 1 C:\Users` |
| System summary | `PsInfo64` | `PsInfo64 -accepteula -nobanner -d -s` (output is UTF-16) |
| Why did it blue-screen? | `BlueScreenView` (NirSoft) | `BlueScreenView /stext $env:POCKET_HELP_DESK\tmp\bsod.txt` - then read the file |
| Which drivers, which versions? | `DriverView` (NirSoft) | `DriverView /stext $env:POCKET_HELP_DESK\tmp\drivers.txt` |
| What happened, and when? | `LastActivityView` (NirSoft) | `LastActivityView /stext $env:POCKET_HELP_DESK\tmp\activity.txt` (installs, crashes, shutdowns, logons) |
| Wi-Fi neighbours, channels, signal | `WifiInfoView` (NirSoft) | `WifiInfoView /stext $env:POCKET_HELP_DESK\tmp\wifi.txt` |
| Windows Update | `PSWindowsUpdate` module | `Import-Module PSWindowsUpdate; Get-WUHistory -Last 20; Get-WindowsUpdate` (admin to install: `Install-WindowsUpdate -AcceptAll`) |
| Open any archive / unpack an installer without running it | `7z` | `7z x file.exe -o$env:POCKET_HELP_DESK\tmp\x` |

Sysinternals tools need `-accepteula` (otherwise a licence window pops up and blocks). The launcher removes the "accepted" registry notes at the end of the session.

## Windows - built in (no tool needed)

- Health: `sfc /scannow`, `DISM /Online /Cleanup-Image /RestoreHealth` (admin), `chkdsk C: /scan`
- Devices with problems: `Get-PnpDevice -PresentOnly | Where-Object Status -ne 'OK'`; drivers: `pnputil /enum-drivers`, `pnputil /add-driver <inf> /install`
- Events: `Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-3)}`; reliability history: `Get-CimInstance Win32_ReliabilityRecords`
- Battery: `powercfg /batteryreport /output $env:POCKET_HELP_DESK\tmp\battery.html`; sleep/power problems: `powercfg /energy`, `powercfg /requests`
- Network: `ipconfig /all`, `Test-NetConnection <host> -Port 443`, `netsh wlan show interfaces`, `netsh wlan show wlanreport`
- Speed test: `curl.exe -o NUL -s -w "%{speed_download}" "https://speed.cloudflare.com/__down?bytes=100000000"` (bytes/second)
- Printers: `Get-Printer`, `Get-PrintJob -PrinterName <n>`, `Restart-Service Spooler` (admin)
- Windows Update reset (admin, ask first): stop `wuauserv`/`bits`/`cryptsvc`, rename `C:\Windows\SoftwareDistribution`, start them again
- Restore point before a risky change (admin): `Checkpoint-Computer -Description "Before Pocket Help Desk fix" -RestorePointType MODIFY_SETTINGS`
- Features: `Get-WindowsOptionalFeature -Online`, `Enable-/Disable-WindowsOptionalFeature` (admin)
- Am I admin? The launcher header says "administrator" when it is. If a fix needs admin and you are not, say so - the user can restart the stick with right-click > Run as administrator.

## Windows - fetch only when needed

These change often or fit only one brand. Download the current version from the official site into `$POCKET_HELP_DESK/Files/downloads` (ask first; tell the user what and why):

- Manufacturer drivers + BIOS: **HP Image Assistant** (HP), **Lenovo Thin Installer / System Update** (Lenovo), **Dell Command | Update** (Dell - needs installing: ask the owner). Find the brand with `Get-CimInstance Win32_ComputerSystem`.
- No internet because the network driver is missing: **Snappy Driver Installer Origin** (glenn.delahoy.com) - fetch it and its network driver pack on a working computer first.
- Second-opinion malware scan: **Microsoft Safety Scanner** - `https://go.microsoft.com/fwlink/?LinkId=212732` (x64; expires 10 days after download, so always fresh)
- Graphics driver clean reinstall: **Display Driver Uninstaller (DDU)** (wagnardsoft.com)

## For the user (windows to click) - `Tools/For you`

Point the user to these when a window is easier than commands:
- **WinUtil** (Chris Titus): Windows features, tweaks, repairs, app installs. Admin PowerShell: `powershell -ExecutionPolicy Bypass -File "$env:POCKET_HELP_DESK\Tools\For you\WinUtil\winutil.ps1"`
- **Rufus**: make a bootable USB stick. **O&O ShutUp10++**: privacy settings.
- Sysinternals windows in `Tools\sysinternals`: `procexp64` (Process Explorer), `Autoruns64`, `Tcpview64`, `Procmon64`.
- `7zFM` in `Tools\7zip`: 7-Zip's window.

## macOS - built in

- Hardware/storage: `system_profiler SPHardwareDataType SPStorageDataType SPPowerDataType`, `diskutil list`, `diskutil info disk0`, `diskutil verifyVolume /`
- Logs: `log show --last 1h --predicate 'messageType == error' --style compact | tail -200`; crashes: `ls ~/Library/Logs/DiagnosticReports /Library/Logs/DiagnosticReports`
- Updates: `softwareupdate -l`; battery: `pmset -g batt`, `system_profiler SPPowerDataType` (cycle count, condition)
- Network: `networkQuality` (speed test), `ifconfig`, `scutil --dns`, `ping -c 4 1.1.1.1`
- Space: `df -h`, `du -hd1 ~ 2>/dev/null | sort -h | tail`
- Startup items: `launchctl list | grep -v com.apple`, `ls ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons`
- Admin commands need `sudo`: give the user the exact command to run; do not ask for their password.

## Linux - built in

- Errors: `journalctl -p err -b --no-pager | tail -100`, `dmesg --level=err,warn | tail -50`, `systemctl --failed`
- Hardware: `lsblk -f`, `lspci -k`, `lsusb`, `free -h`, `df -h`, `upower -d` (battery); disk health: `smartctl -a /dev/sda` if installed
- Network: `ip a`, `nmcli dev status`, `nmcli dev wifi list`, `resolvectl status`
- Updates: `apt list --upgradable` / `dnf check-update`
- Admin commands need `sudo`: give the user the exact command to run; do not ask for their password.
