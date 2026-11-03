#!/usr/bin/env bash
# Pocket Help Desk: open a sign-in page in a PRIVATE window, so the computer keeps
# no cookies or saved sign-in after the window is closed.
# Claude Code calls this through the BROWSER variable with the URL as $1.
# No private-capable browser = refuse (never a normal window) and show the link
# on the screen, so it can be opened in a private window by hand.
url="$1"
refuse() { # show the link straight on the screen (the program's own output may be captured)
  { echo; echo "[Pocket Help Desk] No browser with a private mode found. Open this link in a PRIVATE window yourself:"
    echo "$url"; echo; } > /dev/tty 2>/dev/null || echo "[Pocket Help Desk] No private browser - open in a private window: $url" >&2
  exit 1; }

if [ "$(uname -s)" = Darwin ]; then
  for pair in "Google Chrome|--incognito" "Microsoft Edge|--inprivate" "Brave Browser|--incognito" "Firefox|-private-window"; do
    app="${pair%%|*}"; flag="${pair##*|}"
    for dir in /Applications "$HOME/Applications"; do
      if [ -d "$dir/$app.app" ]; then open -na "$dir/$app.app" --args "$flag" "$url"; exit 0; fi
    done
  done
  refuse
fi

# Linux: no desktop -> fail, so the program shows the link instead
[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || exit 1
for b in google-chrome google-chrome-stable chromium chromium-browser brave-browser; do
  command -v "$b" >/dev/null 2>&1 && { "$b" --incognito "$url" >/dev/null 2>&1 & exit 0; }
done
command -v microsoft-edge >/dev/null 2>&1 && { microsoft-edge --inprivate "$url" >/dev/null 2>&1 & exit 0; }
command -v firefox >/dev/null 2>&1 && { firefox --private-window "$url" >/dev/null 2>&1 & exit 0; }
refuse
