#!/bin/sh
# MCP stdio launcher for Relate, spawned by Vibe (see mcp.json).
#
# Store selection:
#   RELATE_DATABASE     used verbatim when set (path, .rl file, or :memory:)
#   otherwise           :memory: — Relate is single-writer per store, so a
#                       per-session in-memory graph avoids lock conflicts
#                       between concurrent Vibe sessions. For a persistent
#                       or shared graph, run one `relate serve --mcp PORT
#                       --database PATH` and attach Vibe to it over HTTP
#                       (see README.md), or export RELATE_DATABASE.
# Extra flags pass through: RELATE_SERVE_ARGS="--read-only" sh serve-relate-mcp.sh
set -eu

DB="${RELATE_DATABASE:-:memory:}"

if ! command -v relate >/dev/null 2>&1; then
    echo "relate binary not found on PATH; install from https://relatedb.ai (curl -sSfL https://relatedb.ai/install.sh | bash)" >&2
    exit 1
fi

# shellcheck disable=SC2086
exec relate serve --mcp stdio --database "$DB" ${RELATE_SERVE_ARGS:-} "$@"
