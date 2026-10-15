#!/bin/sh
# saystop installer: https://github.com/DevArtsLab/saystop
# Usage: curl -fsSL https://raw.githubusercontent.com/DevArtsLab/saystop/main/install.sh | sh
# Options (env):
#   SAYSTOP_VERSION=v0.1.0   install a specific release (default: latest)
#   SAYSTOP_PREFIX=/usr/local install location prefix (default: first writable of
#                             /opt/homebrew, /usr/local, ~/.local)
#   SAYSTOP_SHIM=1           also install the `say` shim after install
set -e

REPO="DevArtsLab/saystop"
VERSION="${SAYSTOP_VERSION:-}"
PREFIX="${SAYSTOP_PREFIX:-}"

if [ -z "$PREFIX" ]; then
  if [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then
    PREFIX=/opt/homebrew
  elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    PREFIX=/usr/local
  else
    PREFIX="$HOME/.local"
  fi
fi
BINDIR="$PREFIX/bin"

if [ -z "$VERSION" ]; then
  VERSION=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
fi
[ -n "$VERSION" ] || { echo "could not resolve release version" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL="https://github.com/$REPO/releases/download/$VERSION/saystop"
echo "downloading $URL"
curl -fsSL "$URL" -o "$TMP/saystop"
curl -fsSL "$URL.sha256" -o "$TMP/saystop.sha256" 2>/dev/null || true

if [ -s "$TMP/saystop.sha256" ]; then
  EXPECTED=$(awk '{print $1}' "$TMP/saystop.sha256")
  ACTUAL=$(shasum -a 256 "$TMP/saystop" | awk '{print $1}')
  [ "$EXPECTED" = "$ACTUAL" ] || { echo "checksum mismatch" >&2; exit 1; }
fi

mkdir -p "$BINDIR"
install -m 755 "$TMP/saystop" "$BINDIR/saystop"
# The release binary is unsigned; clear the download quarantine flag.
xattr -d com.apple.quarantine "$BINDIR/saystop" 2>/dev/null || true

echo "installed $BINDIR/saystop"

case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "note: $BINDIR is not on your PATH" ;;
esac

if [ "$SAYSTOP_SHIM" = "1" ]; then
  "$BINDIR/saystop" --install-shim
else
  echo "run '$BINDIR/saystop --install-shim' to give every 'say' call the stop button"
fi
