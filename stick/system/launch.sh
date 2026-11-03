#!/usr/bin/env bash
# Pocket Help Desk launcher for macOS and Linux (bash 3.2 compatible - stock macOS bash).
# Windows twin: launch.ps1. Keep the two in step.
#
# Rule: no login ever lands on this computer. Claude's login is saved on the
# stick LOCKED with your passphrase (age); it is unlocked straight into memory
# and handed to Claude in an environment variable - never written unlocked
# anywhere. Codex is a guest: it signs in each session and keeps that login in
# memory only. Everything else Claude/Codex write goes to the stick (home/, tmp/).

# Everything sits inside { ... } so bash reads the whole script before running
# any of it. Otherwise bash reads it piece by piece from the stick as it goes,
# and an update (or a stick hiccup) mid-run feeds it half a line.
{
STICK="$(cd "$(dirname "$0")/.." && pwd)"
LOGIN_FILE="$STICK/secrets/claude-login.age"     # Claude's token, locked with your passphrase
LEGACY_TOKEN="$STICK/secrets/claude-token.txt"   # unlocked token from before locking existed

case "$(uname -s)" in Darwin) OS=mac;; Linux) OS=linux;; *) echo "Unsupported system: $(uname -s)"; exit 1;; esac
case "$(uname -m)" in arm64|aarch64) ARCH=arm64;; x86_64|amd64) ARCH=x64;; *) echo "Unsupported CPU: $(uname -m)"; exit 1;; esac
# Apple Silicon running this shell under Rosetta still reports x86_64; prefer the native build
if [ "$OS" = mac ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then ARCH=arm64; fi
BIN="$STICK/system/bin/$OS-$ARCH"
CLAUDE="$BIN/claude"; CODEX="$BIN/codex"; AGE="$BIN/age"
[ -f "$CLAUDE" ] || { echo "This stick has no programs for $OS-$ARCH. Rebuild it with that platform."; exit 1; }
# exFAT sticks show every file as runnable; a copy on another disk may have lost the flag
[ -x "$CLAUDE" ] && [ -x "$CODEX" ] && [ -x "$AGE" ] || chmod +x "$CLAUDE" "$CODEX" "$AGE" 2>/dev/null

# ---- keep everything on the stick ------------------------------------------
mkdir -p "$STICK/home/claude" "$STICK/home/codex" "$STICK/secrets" "$STICK/Reports" "$STICK/Files" "$STICK/tmp"
# One launcher at a time: a second one would wipe the first one's scratch files.
INUSE="$STICK/home/.in-use"; ME="$(hostname) $$"
if [ -f "$INUSE" ]; then
  read -r other_host other_pid < "$INUSE" 2>/dev/null
  if [ "$other_host" = "$(hostname)" ] && [ "$other_pid" != "$$" ] && kill -0 "$other_pid" 2>/dev/null; then
    echo "Pocket Help Desk is already running in another window on this computer - use that one, or close it first."
    exit 1
  fi
fi
rm -rf "$STICK/tmp/"* "$STICK/home/codex/tmp" 2>/dev/null   # leftovers, e.g. from a session where the stick was pulled out
export CLAUDE_CONFIG_DIR="$STICK/home/claude"
export CLAUDE_CODE_TMPDIR="$STICK/tmp"
export TMPDIR="$STICK/tmp"
export DISABLE_UPDATES=1 DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CODEX_HOME="$STICK/home/codex"
# Codex databases are not portable between Windows/macOS/Linux builds (a DB made
# by one is rejected by another as "modified"), so each system gets its own.
# Login, settings and chat history stay shared in home/codex.
export CODEX_SQLITE_HOME="$STICK/home/codex/db-$OS"; mkdir -p "$CODEX_SQLITE_HOME"
export POCKET_HELP_DESK="$STICK"
export BROWSER="$STICK/system/open-private.sh"   # sign-in pages open in a private window
# Start clean: drop anything inherited from this computer that could redirect or
# replace our logins (other keys, custom endpoints, cloud providers).
for v in $(env | cut -d= -f1 | grep -E '^(ANTHROPIC_|OPENAI_|CLAUDE_CODE_USE_|CLAUDE_CODE_OAUTH|CODEX_API|CODEX_ACCESS)'); do unset "$v"; done

# ---- "did we leave anything behind" ----------------------------------------
# Default places Claude Code and Codex use on a computer. We note what exists
# before; at the end anything NEW is a leak. A folder that already existed
# (this computer has its own Claude) is a leak only if it now holds something
# named after the stick: Claude files its history under the working folder's
# path with every non-letter/digit turned into '-' (/Volumes/X/work -> -Volumes-X-work).
trace_paths() {
  echo "$HOME/.claude"; echo "$HOME/.claude.json"; echo "$HOME/.codex"
  echo "$HOME/.config/anthropic"; echo "$HOME/.local/share/claude"; echo "$HOME/.local/state/claude"
  echo "$HOME/.cache/claude"; echo "$HOME/.cache/claude-cli-nodejs"; echo "$HOME/.local/bin/claude"
  if [ "$OS" = mac ]; then
    echo "$HOME/Library/Caches/claude-cli-nodejs"; echo "$HOME/Library/Application Support/claude-code"
  fi
}
MARK="$STICK/tmp/.session-start"
keychain_names() { [ "$OS" = mac ] && security dump-keychain 2>/dev/null | grep -E '"svce"<blob>="(Claude Code|Codex|codex)' | sort; }
trace_start() {
  touch "$MARK"
  BEFORE_KEYCHAIN="$(keychain_names)"
  BEFORE_EXIST=""
  local p; while IFS= read -r p; do [ -e "$p" ] && BEFORE_EXIST="$BEFORE_EXIST|$p"; done <<EOF
$(trace_paths)
EOF
}
trace_report() {
  local found=0 own=0 p ours fp
  fp="$(printf '%s' "$STICK/work" | sed 's/[^A-Za-z0-9]/-/g')"
  echo
  echo "Checking this computer for anything Claude or Codex left behind..."
  while IFS= read -r p; do
    [ -e "$p" ] || continue
    case "$BEFORE_EXIST|" in *"|$p|"*)
      [ -d "$p" ] || continue
      ours="$(find "$p" -newer "$MARK" -name "*$fp*" -print 2>/dev/null | head -3)"
      if [ -n "$ours" ]; then echo "  FOUND stick data in: $p"; echo "$ours" | sed 's/^/    /'; found=1
      elif [ -n "$(find "$p" -newer "$MARK" -print -quit 2>/dev/null)" ]; then own=1; fi;;
    *) echo "  NEW:     $p"; found=1;;
    esac
  done <<EOF
$(trace_paths)
EOF
  remove_stray_claude_login
  if [ "$OS" = mac ]; then
    local after; after="$(keychain_names)"
    if [ "$after" != "$BEFORE_KEYCHAIN" ]; then echo "  KEYCHAIN changed (Claude/Codex entries):"; diff <(echo "$BEFORE_KEYCHAIN") <(echo "$after") | sed 's/^/    /'; found=1; fi
  fi
  if [ $found = 0 ]; then echo "  No Claude or Codex files or saved logins found in the usual places on this computer."; fi
  if [ $own = 1 ]; then echo "  (This computer's own Claude/Codex was busy meanwhile - its files were left alone.)"; fi
}

# ---- logins ------------------------------------------------------------------
# Claude/Codex leave terminal replies in the keyboard buffer when they exit;
# without this the next prompt reads them as if you had typed them.
clear_keys() {
  local saved; saved="$(stty -g </dev/tty 2>/dev/null)" || return 0
  stty -icanon -echo min 0 time 0 </dev/tty 2>/dev/null; cat </dev/tty >/dev/null 2>&1
  stty "$saved" </dev/tty 2>/dev/null
}
read_choice() { clear_keys; printf "> "; read -r REPLY; }
claude_new_token() { # runs the sign-in, returns the token on stdout
  echo >&2
  echo "Claude sign-in: a private browser window opens. Sign in and approve," >&2
  echo "then close that window and come back here. Waiting for you..." >&2
  # Captured, not shown: Claude prints the token on a screen it wipes on exit.
  # Output: "Your OAuth token (valid for ...): <token>  Store this token securely..."
  local out rest t
  out="$("$CLAUDE" setup-token 2>&1 </dev/tty | sed $'s/\x1b\\[[0-9;?]*[A-Za-z]//g')"
  rest="${out#*sk-ant-oat}"
  if [ "$rest" != "$out" ]; then
    case "$rest" in *"Store this token"*) rest="${rest%%Store this token*}";; *) rest="${rest%%[[:space:]]*}";; esac
    t="sk-ant-oat$(printf '%s' "$rest" | tr -d '[:space:]')"   # the token may be wrapped over several lines
    if [[ "$t" =~ ^sk-ant-oat[A-Za-z0-9_-]+$ ]]; then echo "Signed in to Claude." >&2; echo "$t"; return; fi
  fi
  echo "Couldn't read a Claude token from the sign-in - nothing was saved. Try again (Logins, menu 3)." >&2
}
# Lock a token with a passphrase. age asks for the passphrase itself, straight
# from the keyboard - this script never sees it. Written to a new file first and
# swapped in only on success, so a mistake never destroys the existing login.
lock_claude_login() { # token
  echo
  echo "Choose a passphrase to lock your Claude login. Use 4 or more random words."
  echo "(Leave it empty and age makes up a strong one - write it down.) You type it twice."
  rm -f "$LOGIN_FILE.new"; clear_keys
  if printf '%s' "$1" | "$AGE" -p -o "$LOGIN_FILE.new" && [ -s "$LOGIN_FILE.new" ] && mv -f "$LOGIN_FILE.new" "$LOGIN_FILE"; then
    echo "Locked. From now on Claude asks for this passphrase when it starts."
  else
    rm -f "$LOGIN_FILE.new"; echo "Not locked - nothing changed."; return 1
  fi
}
unlock_claude_login() { # -> token on stdout, or nothing
  local t
  echo "Unlocking your Claude login..." >&2; clear_keys
  t="$("$AGE" -d "$LOGIN_FILE")" || { echo "Couldn't unlock it. Nothing was started." >&2; return 1; }
  t="$(printf '%s' "$t" | tr -d '[:space:]')"
  [[ "$t" =~ ^sk-ant-oat[A-Za-z0-9_-]+$ ]] || { echo "That file doesn't hold a Claude login. Nothing was started." >&2; return 1; }
  printf '%s' "$t"
}
# Fail closed: if the saved login no longer works, stop here. Otherwise Claude
# would offer its own sign-in, and that saves a login outside our control.
test_claude_login() { # token
  local out
  echo "Checking the login..."
  # A bare one-line request from the stick's own folder: no hooks, no MCP servers,
  # no tools; given up after 30 s (perl's alarm, on every Mac and most Linux).
  local cap=()
  if command -v perl >/dev/null 2>&1; then cap=(perl -e 'alarm 30; exec @ARGV')
  elif command -v timeout >/dev/null 2>&1; then cap=(timeout 30); fi
  if out="$(cd "$STICK/work" && CLAUDE_CODE_OAUTH_TOKEN="$1" "${cap[@]}" "$CLAUDE" -p --model haiku --max-turns 1 \
      --no-session-persistence --strict-mcp-config --tools= --settings "$STICK/system/login-check-settings.json" \
      'Reply with exactly: OK' 2>&1)"; then return 0; fi
  out="$(printf '%s' "$out" | sed 's/sk-ant-[A-Za-z0-9_-]*/[hidden]/g' | tr -s '[:space:]' ' ' | cut -c1-200)"
  echo "Claude didn't accept the saved login (or no answer in 30 s): $out"
  echo "If it expired or was revoked: Logins (menu 3) > sign Claude in again. No internet? Connect and retry."
  return 1
}
# Belt and braces: a Claude sign-in that slipped through (someone typed /login)
# lands in home/claude (Linux, or macOS when the Keychain refuses) or in the
# Keychain under a name tied to the stick's config folder. Remove exactly those.
remove_stray_claude_login() {
  if [ -f "$CLAUDE_CONFIG_DIR/.credentials.json" ]; then
    rm -f "$CLAUDE_CONFIG_DIR/.credentials.json"; echo "  Removed a Claude sign-in that was saved outside the lock."
  fi
  if [ "$OS" = mac ]; then
    # Claude names it "Claude Code-credentials-" + the first 8 hex of sha256(CLAUDE_CONFIG_DIR).
    # The computer's own entry has no suffix, so it can never match.
    local svc; svc="Claude Code-credentials-$(printf '%s' "$CLAUDE_CONFIG_DIR" | shasum -a 256 | cut -c1-8)"
    if security find-generic-password -s "$svc" >/dev/null 2>&1; then
      security delete-generic-password -s "$svc" >/dev/null 2>&1 && echo "  Removed a Claude sign-in that slipped into this Mac's Keychain."
    fi
  fi
}
run_claude() {
  local token
  if [ ! -s "$LOGIN_FILE" ]; then
    if [ -s "$LEGACY_TOKEN" ]; then
      echo "Your Claude login on this stick isn't locked yet - let's lock it now (once)."
      token="$(tr -d '[:space:]' < "$LEGACY_TOKEN")"
    else
      echo "No Claude login on this stick yet - let's set it up once (best done at home)."
      token="$(claude_new_token)"
    fi
    [ -n "$token" ] || return
    lock_claude_login "$token" || { token=""; return; }
    # A brand-new sign-in: use it straight away rather than asking for the passphrase a third
    # time. (With an old unlocked copy we DO unlock again below - that proves the locked file
    # works before the old copy is deleted.)
    [ -f "$LEGACY_TOKEN" ] && token=""
  fi
  if [ -z "$token" ]; then token="$(unlock_claude_login)" || return; fi
  test_claude_login "$token" || { token=""; return; }
  # The locked login just proved it works - only now is an old unlocked copy safe to delete.
  [ -f "$LEGACY_TOKEN" ] && rm -f "$LEGACY_TOKEN" && echo "Removed the old unlocked copy of the Claude login."
  ( cd "$STICK/work" && CLAUDE_CODE_OAUTH_TOKEN="$token" "$CLAUDE" )
  token=""
  remove_stray_claude_login
}
# Codex login mode, a plain setting on the stick (home/stick-settings.txt):
#   guest (default) - signs in each session, the login lives in memory only
#   saved           - the login is kept on the stick UNLOCKED (Codex reads it as a file and
#                     renews it itself, so it cannot be passphrase-locked like Claude's).
#                     Only for a stick that never leaves you, or a hardware-encrypted drive.
SETTINGS_FILE="$STICK/home/stick-settings.txt"
CODEX_LOGIN="$CODEX_HOME/auth.json"
codex_mode() { if [ -f "$SETTINGS_FILE" ] && grep -qE '^CODEX_LOGIN=saved[[:space:]]*$' "$SETTINGS_FILE"; then echo saved; else echo guest; fi; }
set_codex_mode() { # guest|saved
  local rest; rest="$([ -f "$SETTINGS_FILE" ] && grep -vE '^CODEX_LOGIN=' "$SETTINGS_FILE")"
  { if [ -n "$rest" ]; then printf '%s\n' "$rest"; fi
    if [ "$1" = saved ]; then echo "CODEX_LOGIN=saved"; fi
  } > "$SETTINGS_FILE.new"   # (if, not &&: a false last test would skip the swap below)
  mv -f "$SETTINGS_FILE.new" "$SETTINGS_FILE"
}
codex_store() { if [ "$(codex_mode)" = saved ]; then echo file; else echo ephemeral; fi; }
remove_codex_login() { # sign out with OpenAI, then delete it from the stick
  local said
  said="$("$CODEX" -c 'cli_auth_credentials_store="file"' -c check_for_update_on_startup=false logout 2>&1 | sed -E 's/[A-Za-z0-9_-]{40,}/[hidden]/g' | tr -s '[:space:]' ' ')"
  rm -f "$CODEX_LOGIN"
  if [ -f "$CODEX_LOGIN" ]; then echo "Couldn't delete it: $CODEX_LOGIN"; else echo "Codex's login is deleted from the stick."; fi
  [ -n "$said" ] && echo "Codex's sign-out said: $said"
}
run_codex() {
  if [ "$(codex_mode)" = saved ]; then
    if [ ! -s "$CODEX_LOGIN" ]; then
      echo "Codex keeps its login on this stick (unlocked). Sign in once: pick 'Sign in with Device Code'"
      echo "and type the code on your phone. Only ever type a code this screen just showed you."
    fi
  else
    echo "Codex is a guest on this stick: sign in each time (nothing is saved)."
    echo "Pick 'Sign in with Device Code' and type the code on your phone (needs the device-code"
    echo "switch on in ChatGPT security settings). Only ever type a code this screen just showed you."
  fi
  # exFAT has no symlinks, so Linux Codex can't make its PATH shortcuts; it works without them
  [ "$OS" = linux ] && echo "(A 'could not create PATH aliases' warning is expected here and harmless.)"
  # SSH_CONNECTION tells Codex there is no usable desktop, so even 'Sign in with ChatGPT'
  # shows a link and code instead of opening this computer's browser.
  ( cd "$STICK/work" && SSH_CONNECTION='127.0.0.1 0 127.0.0.1 0' "$CODEX" -c "cli_auth_credentials_store=\"$(codex_store)\"" \
      -c check_for_update_on_startup=false --sandbox workspace-write --ask-for-approval on-request )
}
logins_menu() {
  while true; do
    echo
    echo "Logins"
    echo "  1) Sign Claude in again (new login, locked with a passphrase)"
    echo "  2) Forget the saved Claude login"
    if [ "$(codex_mode)" = saved ]; then echo "  3) Codex: login SAVED on this stick - switch back to guest (signs out, deletes it)"
    else echo "  3) Codex: guest (signs in each time) - switch to keeping its login on this stick"; fi
    echo "  B) Back"
    read_choice; c="$REPLY"
    case "$c" in
      1) t="$(claude_new_token)"
         if [ -n "$t" ] && lock_claude_login "$t"; then
           echo "Tip: remove the old token in your Claude account settings."
         fi; t="";;
      2) rm -f "$LOGIN_FILE" "$LEGACY_TOKEN"; echo "The saved Claude login is deleted from the stick."
         echo "If the stick was ever out of your hands, also remove the token in your Claude account settings.";;
      3) if [ "$(codex_mode)" = saved ]; then
           clear_keys; printf "Sign Codex out and delete its saved login from this stick? (Y/n) "; read -r a
           case "$a" in n|N*) ;; *) [ -f "$CODEX_LOGIN" ] && remove_codex_login
             set_codex_mode guest; echo "Codex is a guest again: it signs in each time.";; esac
         else
           echo; echo "Codex can't lock its login with your passphrase: it would sit UNLOCKED on this stick,"
           echo "and anyone holding the stick could use your ChatGPT account. Only do this on a stick that"
           echo "never leaves you, or on a hardware-encrypted (keypad) drive."
           clear_keys; printf "Type SAVE to keep Codex signed in on this stick (anything else cancels): "; read -r a
           if [ "$a" = SAVE ]; then set_codex_mode saved; echo "Done. Next time you start Codex, sign in once and it stays signed in."
           else echo "Nothing changed - Codex stays a guest."; fi
         fi;;
      b|B|"") return;;
    esac
  done
}
# Old logins from before locking existed. Interactive only, and only with a yes.
resolve_old_logins() {
  local a said
  if [ -f "$LEGACY_TOKEN" ] && [ -s "$LOGIN_FILE" ]; then
    # Never delete the old copy just because a locked file exists: it goes only after the
    # locked login has been unlocked and accepted by Claude (see run_claude).
    echo; echo "Note: an old unlocked copy of the Claude login is still on the stick. It will be"
    echo "removed automatically the first time your locked login starts Claude successfully."
  elif [ -s "$LEGACY_TOKEN" ]; then
    echo; echo "Your Claude login on this stick is NOT locked yet."
    clear_keys; printf "Lock it now with a passphrase? (Y/n) "; read -r a
    case "$a" in n|N*) ;; *)
      if lock_claude_login "$(tr -d '[:space:]' < "$LEGACY_TOKEN")"; then echo "The old unlocked copy goes as soon as the locked login starts Claude successfully."; fi;;
    esac
  fi
  # A Codex login on a stick set to "guest" (e.g. from an older stick): offer to remove it.
  if [ -f "$CODEX_LOGIN" ] && [ "$(codex_mode)" = guest ]; then
    echo; echo "This stick holds a saved Codex login, but Codex is set to guest (sign in each time),"
    echo "so that login should go: Codex signs it out with OpenAI, then it is deleted from the stick."
    echo "(To keep Codex signed in instead, answer n and use Logins, menu 3.)"
    clear_keys; printf "Do that now? (Y/n) "; read -r a
    case "$a" in n|N*) ;; *) remove_codex_login;; esac
  fi
}

# ---- non-interactive: launch.sh claude|codex [args...] (scripts and tests) --
if [ $# -gt 0 ]; then
  tool="$1"; shift
  cd "$STICK/work" || exit 1
  case "$tool" in
    # POCKET_HELP_DESK_NO_LOGIN=1: run without unlocking (tests)
    claude) if [ -s "$LOGIN_FILE" ] && [ -z "${POCKET_HELP_DESK_NO_LOGIN:-}" ]; then t="$(unlock_claude_login)" || exit 1; export CLAUDE_CODE_OAUTH_TOKEN="$t"; t=""; fi
            "$CLAUDE" "$@"; rc=$?; remove_stray_claude_login; (exit $rc);;
    codex)  "$CODEX" -c "cli_auth_credentials_store=\"$(codex_store)\"" -c check_for_update_on_startup=false "$@";;
    *) echo "usage: launch.sh [claude|codex [args...]]"; exit 2;;
  esac
  rc=$?; rm -rf "$STICK/tmp/"* 2>/dev/null; exit $rc
fi

# ---- pull the stick = everything stops ----------------------------------------
# A running program - and its login - stays in memory after the stick is pulled,
# so whoever sits down next could keep chatting. A watcher checks for the stick
# every 1.5 s; when it has been gone for 3 checks in a row (~4.5 s - a busy or
# briefly stalled drive never trips it) it kills Claude/Codex and this launcher.
LAUNCHER_PID=$$
( cd / || exit   # never sit in a folder on the stick
  missing=0
  while [ $missing -lt 3 ]; do
    sleep 1.5
    if [ -f "$STICK/system/launch.sh" ]; then missing=0; else missing=$((missing + 1)); fi
  done
  pkill -9 -f "$STICK/system/bin/" 2>/dev/null; kill -9 "$LAUNCHER_PID" 2>/dev/null ) &
WATCHDOG=$!
trap 'kill "$WATCHDOG" 2>/dev/null; rm -f "$INUSE"' EXIT

# ---- main --------------------------------------------------------------------
echo "$ME" > "$INUSE"
trace_start
resolve_old_logins
VER="$(head -3 "$STICK/system/VERSIONS.txt" 2>/dev/null | tail -2 | tr '\n' ' ')"
while true; do
  echo
  echo "=== Pocket Help Desk ===  ($OS-$ARCH)  $VER"
  echo "  1) Claude"
  if [ "$(codex_mode)" = saved ]; then echo "  2) Codex (login saved on this stick)"; else echo "  2) Codex (guest - requires login)"; fi
  echo "  3) Logins"
  echo "  Q) Quit (cleans up and checks this computer)"
  read_choice || break; choice="$REPLY"
  case "$choice" in
    1) run_claude;;
    2) run_codex;;
    3) logins_menu;;
    q|Q) break;;
  esac
done
trace_report
rm -rf "$STICK/tmp/"* "$STICK/tmp/".session-start 2>/dev/null
echo "Done. You can unplug the stick."
exit
}
