# Contributing to Pocket Help Desk

Thanks for helping. The most useful contributions, in order:

1. **Platform reports.** "It worked (or didn't) on my Dell / ThinkPad / M1 / Fedora" is gold. Open an issue with the *Platform report* template.
2. **Bug reports** with the OS, what you did, what you expected and what happened.
3. **Pull requests** for fixes, toolkit additions and guide improvements.

Security problems go through private reporting, never a public issue. See [SECURITY.md](SECURITY.md).

## Ground rules for changes

- **The two launchers stay in step.** `stick/system/launch.ps1` (Windows) and `stick/system/launch.sh` (macOS / Linux) implement the same behaviour. A change to one needs the matching change to the other, or a note explaining why it's platform-specific.
- **The four binding rules in [docs/DESIGN.md](docs/DESIGN.md) don't bend:** no login saved on the host, everything written to the stick, no updates or installs, sign-in only in a private window.
- **Downloads are verified.** Anything the builders or `tools/fetch-tools.ps1` fetch must be checked against its publisher's hash or signature. Toolkit additions must be free for organisations (no personal-use-only licences).
- **Versions are pinned.** Bumping `versions.txt` means building a test stick and re-running the tests.
- **Line endings matter.** `.sh`, `.command` and `.py` are LF; `.cmd` and `.ps1` are CRLF (see `.gitattributes`). A shell script with CRLF fails on Linux.
- **Docs follow the code.** If behaviour changes, update `docs/DESIGN.md` (and `stick/Guide.html` if people will notice) in the same pull request.

## Running the tests

See the *Tested on real hardware* section of the [README](README.md#tested-on-real-hardware). The login tests are destructive and refuse to run on a folder without a `.disposable-test-stick` marker; use a throwaway copy of a stick.

CI runs `shellcheck` on every shell script and syntax-checks the Python test. It can't test a real USB stick: the hardware tests are run by hand before a release.

## License

By contributing, you agree that your contribution is licensed under the [GPL-3.0](LICENSE).
