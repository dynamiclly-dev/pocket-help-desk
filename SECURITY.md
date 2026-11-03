# Security

Pocket Help Desk exists to keep a Claude login safe on a stick that can be lost, and to leave nothing behind on the computers it fixes. If you find a way around either, please tell us privately first.

## Report a problem

Use **Report a vulnerability** on this repository's **Security** tab (GitHub private vulnerability reporting). Please don't open a public issue for a security problem.

Helpful to include: the operating system, what you did, what you expected, and what happened.

## What counts

- A login (Claude or Codex) ending up on the host computer, or readable from a lost stick without the passphrase
- Files, settings or credentials left on the host after a session, beyond the known traces listed in [docs/DESIGN.md](docs/DESIGN.md) ("Open questions")
- A launcher or builder doing something the user did not agree to
- A download that is not checked against its publisher's hash or signature

The design, its honest limits (for example, no program can stop the host's own pagefile or a compromised host), and how it was tested are in [docs/DESIGN.md](docs/DESIGN.md).
