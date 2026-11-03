#!/usr/bin/env bash
# Leak test (macOS/Linux): run the stick with a brand-new, empty fake HOME,
# then list everything that appeared there. Anything listed = a leak.
# On macOS it also compares Claude/Codex Keychain entries before and after.
#
#   bash tests/leak-test.sh <stick-path>
#
# Uses no logins: the stick's locked Claude login is never unlocked.
set -u
STICK="$1"
FAKE="$(mktemp -d "${TMPDIR:-/tmp}/stick-leaktest-XXXXXX")"
L="$STICK/system/launch.sh"
export POCKET_HELP_DESK_NO_LOGIN=1   # never unlock (or wait for) a real login during the test
kc() { [ "$(uname -s)" = Darwin ] && security dump-keychain 2>/dev/null | grep -E '"svce"<blob>="(Claude|Codex|codex)' | sort; }
KC_BEFORE="$(kc)"

run() { echo "--- launch.sh $*"; HOME="$FAKE" XDG_CONFIG_HOME='' XDG_CACHE_HOME='' XDG_DATA_HOME='' XDG_STATE_HOME='' bash "$L" "$@" 2>&1 | head -15 | sed 's/^/    /'; }
run claude --version
run codex --version
run codex login status
run claude -p "Reply with exactly: STICK OK"   # without a token this fails at sign-in - startup still runs
echo "--- interactive menu, then Q (runs the exit check)"
# 'n' declines first-run questions (lock an old login? remove an old Codex login?); at the menu it is ignored
printf 'n\nn\nq\n' | HOME="$FAKE" bash "$L" 2>&1 | tail -5 | sed 's/^/    /'

echo
LEFT="$(cd "$FAKE" && find . -mindepth 1 2>/dev/null)"
if [ -z "$LEFT" ]; then echo "RESULT: CLEAN - nothing written to the fake home ($FAKE)"
else echo "RESULT: LEAK - in the fake home:"; echo "$LEFT" | sed 's/^/    /'; fi
if [ "$(uname -s)" = Darwin ]; then
  if [ "$(kc)" = "$KC_BEFORE" ]; then echo "KEYCHAIN: unchanged"; else echo "KEYCHAIN: CHANGED"; diff <(echo "$KC_BEFORE") <(kc); fi
fi
rm -rf "$FAKE"
