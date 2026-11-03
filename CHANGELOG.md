# Changelog

## 1.0.0 - 2026-11

First public release.

- One exFAT stick for Windows, macOS and Linux on x64 and arm64.
- Claude Code with its login locked by age (passphrase, scrypt), unlocked into memory only, checked before launch (fail closed).
- Codex as an optional guest: signs in each session, or optionally keeps a saved login on the stick.
- Launchers redirect every program's settings, history and temp files to the stick; auto-updates off; inherited API-key variables dropped.
- Watchdog: pulling the stick closes everything within about 5 seconds. Quit runs a leftovers check.
- Windows: one-click setup (`Set up my stick.cmd`), optional administrator rights, a verified repair toolkit (Sysinternals, smartmontools, NirSoft, PSWindowsUpdate, 7-Zip; WinUtil, Rufus, O&O ShutUp10++).
- Pinned downloads from official sources: SHA-256 checked wherever the publisher provides one, Authenticode checked for Windows toolkit binaries. Nothing redistributed.
- `Guide.html` on every stick, also published at pockethelpdesk.com/guide.
- Tests: leak tests (Windows, macOS, Linux), login-lock tests, watchdog smoke test.
