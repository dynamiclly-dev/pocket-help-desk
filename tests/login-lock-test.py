#!/usr/bin/env python3
"""Login-lock test (macOS/Linux): drives the real launcher in a pseudo-terminal,
typing like a person, with a FAKE Claude token - no real account involved.

  python3 tests/login-lock-test.py <stick-path>

Checks: an old unlocked token gets locked (age) - and the unlocked copy is KEPT until a
locked login has actually worked;
the right passphrase unlocks; Claude rejecting the token stops the launch (no
fallback sign-in); a wrong passphrase refuses; no unlocked token is left on the
stick.
"""
import os, pty, sys, time, select, subprocess

STICK = sys.argv[1]
# This test DELETES the stick's Claude login and plants a fake one. Never run it on a real stick:
# it refuses unless the folder is explicitly marked as a throwaway test copy.
if not os.path.exists(os.path.join(STICK, ".disposable-test-stick")):
    sys.exit("Refusing: %s is not marked as a throwaway test stick (create an empty file named "
             ".disposable-test-stick in it - only ever on a COPY built for testing)." % STICK)
FAKE = "sk-ant-oat01-FAKEtokenForLockTestOnly0123456789abcdefABCDEF"
PASS = "correct horse battery staple"
secrets = os.path.join(STICK, "secrets")
login, legacy = os.path.join(secrets, "claude-login.age"), os.path.join(secrets, "claude-token.txt")
for f in (login, legacy):
    if os.path.exists(f): os.remove(f)
os.makedirs(secrets, exist_ok=True)
open(legacy, "w").write(FAKE)

def run(script, timeout=90):
    """script = list of (wait_for_text, text_to_type). Returns the full screen output."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp("bash", ["bash", os.path.join(STICK, "system", "launch.sh")])
    out, step, mark, deadline = b"", 0, 0, time.time() + timeout   # mark: only look at output after the last keystroke
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.5)
        if r:
            try: chunk = os.read(fd, 4096)
            except OSError: break
            if not chunk: break
            out += chunk
        if step < len(script) and script[step][0].encode() in out[mark:]:
            time.sleep(0.4); os.write(fd, script[step][1].encode()); step += 1
            out += b"\n<<typed step %d>>\n" % step; mark = len(out)
    try: os.kill(pid, 9)
    except ProcessLookupError: pass
    global last_screen; last_screen = out.decode(errors="replace")
    return last_screen

results = []
last_screen = ""
def check(name, ok):
    results.append((name, ok)); print(("PASS " if ok else "FAIL ") + name)
    if not ok and last_screen:   # show what was on screen, minus colour codes
        import re
        clean = re.sub(chr(27) + r"\[[0-9;?]*[A-Za-z]", "", last_screen)
        print("   screen tail:", clean[-500:].replace(chr(10), " | "))

# 1+2+3: lock the legacy token, unlock with the right passphrase, Claude rejects the fake token
# (the launcher offers to lock an unlocked login at start, before the menu)
o = run([("(Y/n)", "y\n"), ("Enter passphrase", PASS + "\n"), ("Confirm passphrase", PASS + "\n"),
         ("> ", "1\n"), ("Enter passphrase", PASS + "\n"), ("> ", "q\n")])
check("legacy token locked into claude-login.age", os.path.exists(login) and os.path.getsize(login) > 0)
check("old unlocked copy KEPT (fake login never proves itself, so nothing is lost)", os.path.exists(legacy))
check("right passphrase unlocks", "Checking the login" in o)
check("rejected login stops the launch (no fallback sign-in)", "didn't accept the saved login" in o)
check("passphrase never echoed on screen", PASS not in o)
check("token never shown on screen", FAKE not in o)

# 4: wrong passphrase refuses
o = run([("> ", "1\n"), ("Enter passphrase", "wrong words entirely\n"), ("> ", "q\n")])
check("wrong passphrase refuses", "Couldn't unlock it" in o and "Checking the login" not in o)

# 5: the token is nowhere on the stick in the clear
hits = subprocess.run(["grep", "-rl", FAKE, STICK], capture_output=True, text=True).stdout.strip()
hits = [h for h in hits.splitlines() if os.path.realpath(h) != os.path.realpath(legacy)]
check("no unlocked token anywhere on the stick (besides the kept old copy)", hits == [])
if hits: print("   found in:", hits)

# 5b: once the locked login WORKS, the old unlocked copy is removed. Claude is swapped for a
# stand-in that accepts any token (this is a throwaway copy), so no real account is involved.
import glob
for claude in glob.glob(os.path.join(STICK, "system", "bin", "*", "claude")):
    open(claude, "w").write("#!/bin/sh\necho OK\nexit 0\n"); os.chmod(claude, 0o755)
o = run([("> ", "1\n"), ("Enter passphrase", PASS + "\n"), ("> ", "q\n")])
check("old unlocked copy removed once the locked login worked", not os.path.exists(legacy)
      and "Removed the old unlocked copy" in o)

# 5c: a brand-new user (no login at all): menu 1 -> sign-in -> passphrase twice -> straight into
# Claude, with NO third passphrase prompt. The stand-in plays `claude setup-token` too.
for f in (login, legacy):
    if os.path.exists(f): os.remove(f)
for claude in glob.glob(os.path.join(STICK, "system", "bin", "*", "claude")):
    open(claude, "w").write('#!/bin/sh\nif [ "$1" = setup-token ]; then\n'
        '  printf "Your OAuth token (valid for 1 year):\\n\\n%s\\n\\nStore this token securely.\\n" "' + FAKE + '"\n'
        '  exit 0\nfi\necho OK\nexit 0\n')
    os.chmod(claude, 0o755)
o = run([("> ", "1\n"), ("Enter passphrase", PASS + "\n"), ("Confirm passphrase", PASS + "\n"), ("> ", "q\n")])
check("new user: sign-in captured and locked", os.path.exists(login) and "Signed in to Claude" in o)
check("new user: passphrase asked only twice (no extra unlock)", o.count("Enter passphrase") == 1 and "Unlocking your Claude login" not in o)
check("new user: login checked and Claude started", "Checking the login" in o and "didn't accept" not in o)
check("new user: token never on screen", FAKE not in o)

# 5d: Codex login mode (main menu 3 = Logins, then 3 = the Codex switch): guest by default; SAVE switches to saved; back to guest
settings = os.path.join(STICK, "home", "stick-settings.txt")
codex_login = os.path.join(STICK, "home", "codex", "auth.json")
if os.path.exists(settings): os.remove(settings)
o = run([("> ", "3\n"), ("> ", "3\n"), ("Type SAVE", "nope\n"), ("> ", "b\n"), ("> ", "q\n")])
check("codex: anything but SAVE cancels", "Codex stays a guest" in o and not (os.path.exists(settings) and "CODEX_LOGIN=saved" in open(settings).read()))
o = run([("> ", "3\n"), ("> ", "3\n"), ("Type SAVE", "SAVE\n"), ("> ", "b\n"), ("> ", "q\n")])
check("codex: SAVE switches to a saved login", os.path.exists(settings) and "CODEX_LOGIN=saved" in open(settings).read()
      and "login saved on this stick" in o)
os.makedirs(os.path.dirname(codex_login), exist_ok=True); open(codex_login, "w").write("{}")
o = run([("> ", "q\n")])
check("codex saved: an existing login is left alone at start", os.path.exists(codex_login) and "set to guest" not in o)
o = run([("> ", "3\n"), ("> ", "3\n"), ("(Y/n)", "y\n"), ("> ", "b\n"), ("> ", "q\n")])
check("codex: back to guest deletes the saved login", not os.path.exists(codex_login) and "guest again" in o
      and "CODEX_LOGIN=saved" not in open(settings).read())
open(codex_login, "w").write("{}")
o = run([("(Y/n)", "y\n"), ("> ", "q\n")])
check("codex guest: a leftover login is offered for removal at start", "set to guest" in o and not os.path.exists(codex_login))

# 6 (macOS): a sign-in that slipped into the Keychain is removed - only the stick's own entry
if sys.platform == "darwin":
    import hashlib
    cfg = os.path.join(os.path.realpath(STICK), "home", "claude")
    svc = "Claude Code-credentials-" + hashlib.sha256(cfg.encode()).hexdigest()[:8]
    def kc_count(name):
        r = subprocess.run(["security", "dump-keychain"], capture_output=True, text=True).stdout
        return r.count('"svce"<blob>="%s"' % name)
    host_before = kc_count("Claude Code-credentials")
    added = subprocess.run(["security", "add-generic-password", "-U", "-s", svc, "-a", "locktest", "-w", "fake"],
                           capture_output=True).returncode == 0
    if not added:
        print("SKIP Keychain cleanup (Keychain is locked in this session - run from a desktop Terminal)")
    else:
        run([("> ", "q\n")])
        check("stray stick sign-in removed from the Keychain", kc_count(svc) == 0)
        check("the Mac's own Claude login untouched", kc_count("Claude Code-credentials") == host_before)
        subprocess.run(["security", "delete-generic-password", "-s", svc], capture_output=True)

print("\n%d/%d passed" % (sum(ok for _, ok in results), len(results)))
sys.exit(0 if all(ok for _, ok in results) else 1)
