#!/bin/sh
# Install the relate plugin into Vibe's user plugin scope as a symlink:
#   ~/.vibe/plugins/relate -> this repo
# Then start Vibe (or /reload-plugins) and check /plugins and /mcp.
#
# Options:
#   --copy    copy the repo instead of symlinking (edits then don't propagate)
#   --project install into <cwd>/.vibe/plugins/ instead (folder must be trusted)
set -eu

SRC="$(cd "$(dirname "$0")/.." && pwd)"
MODE="symlink"
SCOPE="user"
for arg in "$@"; do
    case "$arg" in
        --copy) MODE="copy" ;;
        --project) SCOPE="project" ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

if [ "$SCOPE" = "project" ]; then
    DEST="$(pwd)/.vibe/plugins/relate"
else
    DEST="${VIBE_HOME:-$HOME/.vibe}/plugins/relate"
fi

mkdir -p "$(dirname "$DEST")"

if [ "$MODE" = "symlink" ]; then
    if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
        echo "refusing to replace non-symlink: $DEST" >&2
        exit 1
    fi
    ln -sfn "$SRC" "$DEST"
    echo "linked $DEST -> $SRC"
else
    rm -rf "$DEST"
    cp -R "$SRC" "$DEST"
    echo "copied $SRC -> $DEST"
fi

echo "Done. In Vibe run /reload-plugins (or start a new session), then:"
echo "  /plugins   — the 'relate' plugin should be listed"
echo "  /mcp       — the 'relate' server should list get_schema, read_cypher, write_cypher"
echo "Ask the agent: \"what tools do you have for the relate graph?\""
