# Pocket Help Desk - design

## Goal

One stick, any computer (Windows, macOS, Linux; x64 and ARM): Claude Code with its login locked on the stick, Codex as a guest that signs in each session. Nothing installed, nothing left behind, safe if the stick is lost or pulled out mid-session.

"Claude" is Anthropic's trademark, so the product never uses it as its name - it describes what it runs. Internal names follow the product (`POCKET_HELP_DESK`, `POCKET_HELP_DESK_NO_LOGIN`, exFAT label `PocketHelp`).

## Binding rules

1. **No login is ever saved on the host computer, on any OS, however the stick is removed.** Claude's token lives locked on the stick and unlocked only in program memory; Codex's login lives only in memory. Never in the host's home folder, Keychain or Credential Manager. Honest boundary (independent review, 24 Oct): no program can stop the host OS itself from copying memory to disk (pagefile, hibernation, crash dumps) or a compromised host from watching - true of every option, a keypad drive included.
2. **Everything the programs write goes to the stick**: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `CODEX_SQLITE_HOME`, `CLAUDE_CODE_TMPDIR`, `TMPDIR`/`TEMP` all point into the stick.
3. **No updates, no installs**: `DISABLE_UPDATES=1`. The builder installs the exact versions in `versions.txt` (tested ones); `./build-stick.sh --check` shows what is newer.
4. **Sign-in pages open only in a private browser window** (`BROWSER` = `system/open-private.*`). No private-capable browser = refuse (Claude then shows the link to open privately by hand) - never a normal window.
5. **Ask before changing the host** - ground rules in `work/CLAUDE.md` (+ `AGENTS.md`). Codex on Windows runs with no sandbox (its `elevated` Windows sandbox setup would add users and firewall rules to the host) and `--ask-for-approval on-request` - Codex 0.164 dropped `untrusted`, so on Windows "ask first" rests on the ground rules, not on the tool. On macOS/Linux it keeps its normal `workspace-write` sandbox. (A stick owner may set Claude's `permissions.defaultMode` to `bypassPermissions` in the stick's own `home/claude/settings.json`; sticks never ship with it.)

## Logins (Claude locked with age; Codex a guest, or optionally saved)

| | How | On the stick | If the stick is lost / pulled |
|---|---|---|---|
| Claude | one-time `claude setup-token` (1-year, inference-only token, captured by the launcher) locked with **age** (passphrase, scrypt) in `secrets/claude-login.age`. Each start: age asks for the passphrase itself (the launcher never sees it), the token goes to memory only, then into `CLAUDE_CODE_OAUTH_TOKEN` | the locked file only | nothing usable without the passphrase; revoke the token in the Claude account (documented by Anthropic) |
| Codex - guest (default) | signs in every session ("Sign in with Device Code" from a phone, or "Sign in with ChatGPT" on your own computer); `cli_auth_credentials_store="ephemeral"` | nothing | nothing |
| Codex - saved (opt-in, Logins menu 3, typed `SAVE`) | signs in once; `cli_auth_credentials_store="file"` - `home/codex/auth.json`, renewed by Codex itself | the login, UNLOCKED | someone holding the stick can use the ChatGPT account; OpenAI documents no sure single-login revocation. Meant for a stick that never leaves you or a keypad (hardware-encrypted) drive - this is the "v1" saved-login design, kept as one setting (`CODEX_LOGIN=saved` in `home/stick-settings.txt`) instead of a second project. Switching back to guest signs Codex out and deletes the file. |

- **Third review (Codex, 24 Oct):** confirmed the fixes; found that an old unlocked copy was deleted just because a locked file existed (data-loss risk) - now it is deleted only after the locked login has unlocked AND been accepted by Claude. Verdict: fine for supervised use on your own computers; borrowed-host use still needs the real-hardware checks listed below. No private browser = the link is shown on screen (not swallowed).
- **Second review (Codex, 24 Oct, on the code) - all must-fix items addressed:** macOS cleanup now removes ONLY the stick's own Keychain entry (`Claude Code-credentials-` + first 8 hex of sha256(`CLAUDE_CONFIG_DIR`), read from Claude's source; the host's entry has no suffix); a failed lock swap reports failure and keeps everything; old logins are handled only interactively and with a yes (Codex's sign-out output is reported, not assumed); the login check runs from the stick's folder with no hooks, MCP servers or tools and a 30 s limit, its output redacted; inherited `ANTHROPIC_*`, `OPENAI_*`, `CLAUDE_CODE_USE_*` variables are dropped; no raw sign-in output or paste fallback; one launcher at a time (`home/.in-use`); the test script refuses any folder not marked `.disposable-test-stick`.
- **Codex guest and the browser:** Codex ignores `BROWSER` on Windows/macOS. The launcher sets `SSH_CONNECTION` for Codex so it believes there is no usable desktop and uses its link-and-code sign-in even for "Sign in with ChatGPT" (from Codex's `headless_chatgpt_login`). Not yet proven - an automated terminal could not drive Codex's screen, so it needs a check on a real Windows computer. Worst case = today's behaviour (a browser opens).
- **Fail closed:** before starting Claude, a one-line `claude -p --model haiku --no-session-persistence` check (~2 s) proves the token works. A rejected token stops the launch, so Claude never offers its own `/login` (which would save a login outside the lock - into the macOS Keychain). Belt and braces: at the end of a session the launcher deletes any `home/claude/.credentials.json` and, on macOS, any Claude Keychain entry that appeared during the session.
- **Locking is transactional:** age writes `claude-login.age.new`; it replaces the old file only on success. A failed or cancelled lock changes nothing.
- **Migration:** an old unlocked `secrets/claude-token.txt` is locked on first use (no new sign-in needed) and then deleted. An old saved Codex login (`home/codex/auth.json`) is signed out and deleted once.
- **Passphrase strength is the security.** age's scrypt (N=2^18, ~256 MiB, ~1 s per guess) makes 4+ random words impractical to brute-force; a weak passphrase is not.
- **A lost stick that comes back is rebuilt** (`build-stick.sh` rewrites every program and launcher): the programs are not locked, so a trojaned launcher could catch the passphrase.
- Chat history (`home/`) is NOT locked - the owner's call. It can contain details of machines that were repaired.
- Facts: Claude's token path never writes credentials; on macOS a sign-in's Keychain entry is keyed to `CLAUDE_CONFIG_DIR`. Claude opens sign-in via `process.env.BROWSER` and redirects to `localhost` (approve on the same computer). Codex 0.164 store values: `file | keyring | auto | ephemeral`; device-code sign-in needs the ChatGPT security switch. OpenAI's Active Sessions page does NOT cover Codex CLI sessions - irrelevant now that Codex stores nothing.

## Why age (independent review by Codex, 24 Oct)

The design was reviewed read-only by Codex (GPT), with web access, against the four rules. Findings:
- **age** is the right software tool: published binaries for all six platforms, Sigsum proofs, scrypt KDF, reads the passphrase straight from the console (`CONIN$` on Windows, `/dev/tty` elsewhere). No published independent audit was found - "widely used", not "audited".
- **Rejected:** Cryptomator (driver-free WebDAV mode keeps a decrypted cache on Windows; other modes need WinFsp/macFUSE), VeraCrypt (admin + driver), gocryptfs / rclone mount (FUSE), KeePassXC / 7-Zip / OpenSSL (same file problem, weaker or unauthenticated), Bitwarden / 1Password CLIs (another login to protect), age + YubiKey (pcscd on Linux), OS-native encryption (no common format).
- **Codex's saved login cannot be protected in software:** Codex reads `auth.json` as a file, reloads it during refresh and rotates refresh tokens, so any decrypt-at-start / re-encrypt-at-quit scheme leaves plaintext after a yank and can restore a stale token. Hence Codex = guest.
- **Keypad drive** remains the best whole-drive option (protects chats too, no passphrase typed on the host). Optional upgrade, not needed for the logins.

## Test results

| Date | Host | Result |
|---|---|---|
| 23 Oct 2026 | Windows 11 Pro laptop, staging folder | CLEAN for Claude + Codex. Only `AppData\Local\Microsoft\Windows\PowerShell\StartupProfileData-NonInteractive` appeared - Windows PowerShell's own startup cache; no data. |
| 23 Oct 2026 | macOS 26.6 (Mac mini, arm64), exFAT disk image | CLEAN; Keychain unchanged. Both binaries signed (Anthropic PBC; OpenAI 2DC432GLL2). |
| 23 Oct 2026 | Ubuntu mini PC (x64), ext4 folder | CLEAN. |
| 24 Oct 2026 | Windows 11 laptop, REAL stick, real logins | Claude + Codex from saved logins; check CLEAN; real yank closes everything ~3 s. |
| 24 Oct 2026 | macOS 26.6 (Mac mini), REAL stick | Claude from the saved token; check CLEAN; the Mac's own Keychain entry survived; folder-trust question once per path. Codex needed per-OS DBs (fixed). |
| 24 Oct 2026 | Ubuntu mini PC, REAL stick, exFAT | Claude OK. Codex ran a command + edited a file once `codex-code-mode-host` was on the stick. |
| 24 Oct 2026 | Windows, BitLocker'd real stick | Claude (saved token) ran `smartctl` from the toolkit; Windows Codex ran a command; leak test clean. |
| 25 Oct 2026 | REAL stick: age lock + unlock on Windows, then Mac after BitLocker off + full format | Works. (A Mac once showed the stick as USB but no disk until replugged - a connection hiccup, not the format.) |
| 25 Oct 2026 | Windows-native setup, rehearsed from the LIVE 34 KB download | setup OK, leak test clean, login logic 6/6, no bypass setting on a fresh stick. Codex-mode switch: 11/11 Windows (plumbing test); Linux + macOS via login-lock-test.py. |
| 27 Oct 2026 | Windows laptop, Ubuntu mini PC, macOS (Mac mini, stock bash 3.2), each a fresh throwaway stick built by that OS's own builder | Windows: login plumbing 11/11, leak test = only the known PowerShell startup cache. Linux: login-lock 18/18, leak CLEAN. macOS: login-lock 18/18, leak CLEAN, Keychain unchanged. Building ON a Mac had never worked (bash 3.2 sources nothing from `. <(...)`, and an empty array under `set -u` aborts) - both fixed. |
| 24 Oct 2026 | Linux + macOS `tests/login-lock-test.py` (fake token + stand-in Claude) and Windows `tests/login-plumbing-test.ps1` (stand-in age + a real token) | 9/9 on all three after the third review: lock; failed lock changes nothing; wrong passphrase refuses; rejected login stops the launch; the old unlocked copy is KEPT until the locked login has worked and removed right after; token and passphrase never printed. Earlier 8/8 run: old token locked + unlocked copy removed; right passphrase unlocks; wrong one refuses; rejected login stops the launch; passphrase and token never on screen or on the stick in the clear; Mac Keychain unchanged. |

## Admin and toolkit (24 Oct)

- **Admin by default:** `Start (Windows).cmd` asks Windows for administrator rights itself. Declined, or no admin password = it starts normally (Claude can diagnose, not fix everything). The header says "administrator". Mac/Linux: Claude gives `sudo` commands for the user to run.
- **Toolkit** (`tools/tools.txt`): Sysinternals, smartmontools, 7-Zip, NirSoft BlueScreenView/DriverView/LastActivityView/WifiInfoView, PSWindowsUpdate for Claude; WinUtil, Rufus, O&O ShutUp10++ for the user. All free for organisations. Brand driver tools, SDIO, Safety Scanner, DDU are fetched on demand - listed in `work/TOOLS.md`. `Tools/Where these came from.txt` lists every tool's official link; nothing is stored in git. Mac/Linux: built-ins only, documented in `TOOLS.md`.
- Sysinternals writes `HKCU\Software\Sysinternals\<tool>\EulaAccepted`; the launcher removes notes the session added at Q. A yanked session leaves them - harmless, no data.
- Not chosen (personal-use-only licences): WizTree, HWiNFO, Malwarebytes free.

## The guide and the website (25 + 27 Oct)

- People don't read text files, so every stick carries `Guide.html` instead of a `READ ME FIRST.txt`: the website's guide page itself, one file in two places (`tools/build-site.ps1` publishes it at `/guide/`). Opened from the stick (`file:`) it hides setup and leads with "Start here"; it works offline (fonts fall back), which matters because its "No internet?" section (phone USB tethering) is exactly what a laptop without Wi-Fi needs. The builders delete the old `.txt` / `.url` when they update a stick.
- `site/index.html` is the homepage (pockethelpdesk.com). Honest claims only: no pricing yet, the user brings their own Claude Pro/Max plan, "leaves nothing behind in the usual places", independent of Anthropic.

## Lessons

- Pulling the stick did NOT stop Codex - Windows keeps a running program and its login in memory. Watchdog (both launchers): stick gone for 3 checks in a row (~4.5 s) = close everything. The first Windows version failed on a REAL yank (it started `taskkill` from a folder that no longer existed); it now kills the window's process tree directly. **Simulations (rename/subst) did not reproduce a pulled USB - prove yank behaviour on real hardware.**
- `claude setup-token` wipes its screen on exit - the launcher captures the token itself. Terminal replies left in the keyboard buffer were once saved as the "token" - every prompt clears the buffer first and only an `sk-ant-oat...` shape is accepted.
- The leave-behind check flags only NEW Claude/Codex folders or stick-named items inside existing ones (a busy host Claude is not a leak). Its message says "found in the usual places" - it cannot prove absence from caches, pagefiles or dumps.
- Codex DBs are not portable between OS builds - `CODEX_SQLITE_HOME` per OS. `codex-code-mode-host` is REQUIRED for Codex to run commands. exFAT has no symlinks - Codex's "PATH aliases" warning is harmless.
- Updating `launch.sh` while it ran made bash execute a fragment - the script is wrapped in `{ ... }`; never update a stick in use.
- macOS indexes sticks with Spotlight - `.metadata_never_index` at the root stops it. macOS also keeps a log of changed file names in `.fseventsd` - the stick ships `.fseventsd/no_log`, which turns that off. `._*` files (Finder metadata, e.g. beside `Start (Mac).command`) still appear after Mac use; harmless.
- Codex releases can drop CLI flags (0.164 removed `untrusted`) - versions are pinned; re-test after every bump.
- The builders copy the WORKING copy onto a stick, not what git stores. A script rewritten on Windows can silently gain CRLF line endings (Python's text mode did it to `build-stick.sh`, which then failed on Linux with `set: pipefail: invalid option name`). Check bytes, not Git Bash `grep -c $'\r'` (it miscounts); `.gitattributes` fixes only what git checks out.

## Open questions

1. Settled 25 Oct: claude.ai Settings > Claude Code lists authorization tokens with a delete icon (Anthropic support article) - the lost-stick fix.
2. Codex guest end to end: device-code sign-in with the `ephemeral` store on each OS, and whether `SSH_CONNECTION` stops "Sign in with ChatGPT" from opening a browser.
3. macOS Keychain cleanup of a stray stick sign-in: safe by construction, not exercised (the Keychain is locked over SSH).
4. Known OS-level traces we cannot prevent: Windows USB device history, PowerShell startup cache, Defender scan history, Prefetch entries; macOS/Linux mount logs; macOS Terminal history keeps the launch line.
