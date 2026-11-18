#!/bin/sh
# One-line install of the relate plugin into Vibe's user plugin scope:
#
#   curl -LsSf https://raw.githubusercontent.com/relatedb/relate-mistral/main/scripts/bootstrap.sh | sh
#
# Clones the repo into ${VIBE_HOME:-~/.vibe}/plugins/relate (git if available,
# otherwise a tarball of main). Re-running updates an existing clone.
set -eu

REPO="${RELATE_MISTRAL_REPO:-https://github.com/relatedb/relate-mistral.git}"
TARBALL="${RELATE_MISTRAL_TARBALL:-https://github.com/relatedb/relate-mistral/archive/refs/heads/main.tar.gz}"
DEST="${VIBE_HOME:-$HOME/.vibe}/plugins/relate"

mkdir -p "$(dirname "$DEST")"

if [ -d "$DEST/.git" ]; then
    echo "updating existing clone at $DEST"
    git -C "$DEST" fetch --depth 1 origin main
    git -C "$DEST" reset --hard origin/main
elif [ -e "$DEST" ] || [ -L "$DEST" ]; then
    echo "refusing to replace non-clone: $DEST (remove it first)" >&2
    exit 1
elif command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO" "$DEST"
else
    echo "git not found; fetching tarball"
    TMP="$(mktemp -d)"
    curl -LsSf "$TARBALL" | tar -xz -C "$TMP" --strip-components=1
    mv "$TMP" "$DEST"
fi

echo "Installed relate plugin to $DEST"
echo "In Vibe: /reload-plugins (or start a new session), then check /plugins and /mcp."
