#!/usr/bin/env bash
# build-stick.sh - lay out a Pocket Help Desk on a drive (or any folder).
#
#   ./build-stick.sh <stick-path> [platform ...]
#   ./build-stick.sh --check            # what is newer upstream than versions.txt
#
#   platforms: windows-x64 windows-arm64 mac-arm64 mac-x64 linux-x64 linux-arm64
#   (default: all six)
#
# Downloads the exact Claude Code, Codex and age versions pinned in versions.txt
# (cached in .cache/), verifies every file against the publisher's SHA-256, and
# copies them plus the launchers in stick/ onto the target. Re-running updates
# the programs and launchers but never touches the stick's own data (home/,
# secrets/, Reports/, Files/).
#
# Runs on Windows (Git Bash), macOS and Linux. Needs: curl, tar, unzip, sha256sum or shasum.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="$HERE/.cache"
CLAUDE_BASE="https://downloads.claude.ai/claude-code-releases"
ALL_PLATFORMS="windows-x64 windows-arm64 mac-arm64 mac-x64 linux-x64 linux-arm64"

die() { echo "ERROR: $*" >&2; exit 1; }
say() { echo "==> $*"; }

# Read line by line: macOS's bash 3.2 silently sources nothing from `. <(...)`.
while IFS='=' read -r key val || [ -n "$key" ]; do
  val="${val%$'\r'}"
  case "$key" in CLAUDE_VERSION) CLAUDE_VERSION="$val";; CODEX_TAG) CODEX_TAG="$val";; AGE_TAG) AGE_TAG="$val";; esac
done < "$HERE/versions.txt"
[ -n "${CLAUDE_VERSION:-}" ] && [ -n "${CODEX_TAG:-}" ] && [ -n "${AGE_TAG:-}" ] || die "versions.txt is incomplete"

AUTH=()
[ -n "${GH_TOKEN:-}" ] && AUTH=(-H "Authorization: Bearer $GH_TOKEN")
gh_release() { curl -fsSL ${AUTH[@]+"${AUTH[@]}"} "https://api.github.com/repos/$1/releases/$2" | tr -d '\n\r'; }

if [ "${1:-}" = "--check" ]; then
  latest_claude="$(curl -fsSL "$CLAUDE_BASE/stable")"
  [[ "$(gh_release openai/codex latest)" =~ \"tag_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && latest_codex="${BASH_REMATCH[1]}"
  [[ "$(gh_release FiloSottile/age latest)" =~ \"tag_name\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]] && latest_age="${BASH_REMATCH[1]}"
  echo "Claude Code  pinned $CLAUDE_VERSION   stable now $latest_claude"
  echo "Codex        pinned $CODEX_TAG   latest now ${latest_codex:-?}"
  echo "age          pinned $AGE_TAG   latest now ${latest_age:-?}"
  exit 0
fi

[ $# -ge 1 ] || die "usage: $0 <stick-path> [platform ...]   |   $0 --check"
STICK="$1"; shift
[ -d "$STICK" ] || die "stick path not found: $STICK"
PLATFORMS="${*:-$ALL_PLATFORMS}"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# platform name on the stick -> Claude manifest key, Codex target triple, age os-arch, exe suffix
claude_key() { case "$1" in
  windows-x64) echo win32-x64;; windows-arm64) echo win32-arm64;;
  mac-arm64) echo darwin-arm64;; mac-x64) echo darwin-x64;;
  linux-x64) echo linux-x64;; linux-arm64) echo linux-arm64;;
  *) die "unknown platform $1";; esac; }
codex_target() { case "$1" in
  windows-x64) echo x86_64-pc-windows-msvc;; windows-arm64) echo aarch64-pc-windows-msvc;;
  mac-arm64) echo aarch64-apple-darwin;; mac-x64) echo x86_64-apple-darwin;;
  linux-x64) echo x86_64-unknown-linux-musl;; linux-arm64) echo aarch64-unknown-linux-musl;;
  esac; }
age_key() { case "$1" in
  windows-x64) echo windows-amd64;; windows-arm64) echo windows-arm64;;
  mac-arm64) echo darwin-arm64;; mac-x64) echo darwin-amd64;;
  linux-x64) echo linux-amd64;; linux-arm64) echo linux-arm64;;
  esac; }
exe() { case "$1" in windows-*) echo .exe;; *) echo "";; esac; }

# download URL to FILE unless FILE already has the expected hash
fetch_verified() { # url file sha256
  local url="$1" file="$2" want="$3"
  if [ -f "$file" ] && [ "$(sha256 "$file")" = "$want" ]; then return 0; fi
  mkdir -p "$(dirname "$file")"
  curl -fL --retry 3 --progress-bar -o "$file.part" "$url"
  local got; got="$(sha256 "$file.part")"
  [ "$got" = "$want" ] || { rm -f "$file.part"; die "checksum mismatch for $url"; }
  mv "$file.part" "$file"
}

gh_sum() { # release-json asset-name -> sha256 digest published by GitHub
  local name="${2//./\\.}"
  # GitHub lists "digest" a few fields before "browser_download_url" in each asset
  if [[ $1 =~ \"digest\"[[:space:]]*:[[:space:]]*\"sha256:([a-f0-9]{64})\"[^{}]*\"browser_download_url\"[[:space:]]*:[[:space:]]*\"[^\"]*/$name\" ]]; then
    echo "${BASH_REMATCH[1]}"
  else die "no digest for $2"; fi
}

say "Pinned: Claude Code $CLAUDE_VERSION, Codex $CODEX_TAG, age $AGE_TAG (versions.txt)"
CLAUDE_MANIFEST="$(curl -fsSL "$CLAUDE_BASE/$CLAUDE_VERSION/manifest.json" | tr -d '\n\r')"
claude_sum() { # manifest key -> checksum (same regex the official installer uses)
  if [[ $CLAUDE_MANIFEST =~ \"$1\"[[:space:]]*:[[:space:]]*[{][^{}]*\"checksum\"[[:space:]]*:[[:space:]]*\"([a-f0-9]{64})\" ]]; then
    echo "${BASH_REMATCH[1]}"
  else die "no checksum for $1 in Claude manifest"; fi
}
CODEX_JSON="$(gh_release openai/codex "tags/$CODEX_TAG")"
AGE_JSON="$(gh_release FiloSottile/age "tags/$AGE_TAG")"

# ---- lay out ---------------------------------------------------------------
for P in $PLATFORMS; do
  X="$(exe "$P")"; BIN="$STICK/system/bin/$P"
  mkdir -p "$BIN"

  K="$(claude_key "$P")"
  say "$P: Claude Code"
  CF="$CACHE/claude/$CLAUDE_VERSION/$K/claude$X"
  fetch_verified "$CLAUDE_BASE/$CLAUDE_VERSION/$K/claude$X" "$CF" "$(claude_sum "$K")"
  cp "$CF" "$BIN/claude$X"

  T="$(codex_target "$P")"
  # codex = the CLI; codex-code-mode-host = its tool runner (without it Codex cannot run commands)
  for PART in codex codex-code-mode-host; do
    say "$P: $PART"
    ASSET="$PART-$T$X.tar.gz"
    AF="$CACHE/codex/$CODEX_TAG/$ASSET"
    fetch_verified "https://github.com/openai/codex/releases/download/$CODEX_TAG/$ASSET" "$AF" "$(gh_sum "$CODEX_JSON" "$ASSET")"
    TMPX="$CACHE/codex/$CODEX_TAG/x-$P"; rm -rf "$TMPX"; mkdir -p "$TMPX"
    tar -xzf "$AF" -C "$TMPX"
    cp "$TMPX/$PART-$T$X" "$BIN/$PART$X"
    rm -rf "$TMPX"
  done

  # age = locks the saved Claude login with your passphrase
  say "$P: age"
  A="$(age_key "$P")"
  case "$P" in windows-*) ASSET="age-$AGE_TAG-$A.zip";; *) ASSET="age-$AGE_TAG-$A.tar.gz";; esac
  AF="$CACHE/age/$AGE_TAG/$ASSET"
  fetch_verified "https://github.com/FiloSottile/age/releases/download/$AGE_TAG/$ASSET" "$AF" "$(gh_sum "$AGE_JSON" "$ASSET")"
  TMPX="$CACHE/age/$AGE_TAG/x-$P"; rm -rf "$TMPX"; mkdir -p "$TMPX"
  case "$ASSET" in *.zip) unzip -q "$AF" -d "$TMPX";; *) tar -xzf "$AF" -C "$TMPX";; esac
  cp "$TMPX/age/age$X" "$BIN/age$X"
  rm -rf "$TMPX"

  chmod +x "$BIN"/* 2>/dev/null || true
done

case " $PLATFORMS " in *" windows-"*)
  if command -v powershell.exe >/dev/null 2>&1; then
    say "Windows toolkit (tools/tools.txt)"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$HERE/tools/fetch-tools.ps1" 2>/dev/null || echo "$HERE/tools/fetch-tools.ps1")" \
      -Stick "$(cygpath -w "$STICK" 2>/dev/null || echo "$STICK")" || die "toolkit fetch failed"
  else
    say "Skipping the Windows toolkit: build on Windows to include it"
  fi;;
esac

say "Copying launchers and playbook"
# Template files are code: always refreshed. Data folders are created once, never overwritten.
cp -R "$HERE/stick/." "$STICK/"
rm -f "$STICK/READ ME FIRST.txt" "$STICK/Guide (online).url"   # replaced by Guide.html
for d in home/claude home/codex secrets Reports Files tmp; do mkdir -p "$STICK/$d"; done
cp "$STICK/work/CLAUDE.md" "$STICK/work/AGENTS.md"   # Codex reads AGENTS.md: same ground rules
chmod +x "$STICK/Start (Mac).command" "$STICK/start-linux.sh" "$STICK/system/"*.sh 2>/dev/null || true

{
  echo "Pocket Help Desk - built $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "Claude Code $CLAUDE_VERSION"
  echo "Codex $CODEX_TAG (guest)"
  echo "age $AGE_TAG"
  echo "Platforms: $PLATFORMS"
} > "$STICK/system/VERSIONS.txt"
cat "$STICK/system/VERSIONS.txt"
say "Done."
