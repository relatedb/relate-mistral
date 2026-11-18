#!/bin/sh
# session_start hook for the relate plugin.
#
# Reads the hook payload on stdin (not needed here). When the relate binary
# is available, prints a structured response whose additional_context is
# injected into the session's first message. Fails open: no output and
# exit 0 when relate is missing or anything unexpected happens, so a missing
# dependency never degrades a session.
set -u

cat >/dev/null 2>&1 || true

if ! command -v relate >/dev/null 2>&1; then
    exit 0
fi

VER="$(relate --version 2>/dev/null | head -n 1 || true)"
[ -n "$VER" ] || VER="unknown version"

# JSON-escape the version string conservatively.
VER="$(printf '%s' "$VER" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"

CTX="Relate by Neo4j (embedded Cypher graph DB) is installed: $VER. The relate plugin exposes MCP tools mcp_relate.get_schema, mcp_relate.read_cypher, mcp_relate.write_cypher (server relate, stdio; store :memory: unless RELATE_DATABASE is set). Load skill relate:relate for CLI/Cypher guidance and relate:relate-memory for the agent-memory pattern. CLI fallback: relate query CYPHER --database PATH --mode envelope."

printf '{"hook_specific_output": {"additional_context": "%s"}}\n' "$CTX"
exit 0
