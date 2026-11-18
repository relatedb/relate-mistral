#!/bin/sh
# Smoke test for the relate-mistral plugin. Exits non-zero on the first
# failure. Requires: python3, and the relate binary (skips MCP roundtrip with
# a warning when absent).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

say() { printf '%s\n' "$*"; }
ok()  { say "ok   - $*"; }
bad() { say "FAIL - $*"; FAIL=1; }

say "== 1. manifest validation =="
python3 - "$ROOT" <<'PY' || FAIL=1
import json, re, sys
root = sys.argv[1]

def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)

plugin = load(f"{root}/plugin.json")
assert plugin["$schema"] == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json", "bad $schema"
assert re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", plugin["name"]), "bad name"
ext = plugin["extensions"]["ai.mistral.vibe"]
assert ext["schemaVersion"] == 1
assert re.fullmatch(r"[A-Za-z_$][A-Za-z0-9_$]*", ext["toolNamespace"]), "bad toolNamespace"
assert ext["toolNamespace"] not in {"file_system", "self", "process", "skill", "subagent", "vibe"}
print("plugin.json ok:", plugin["name"], plugin["version"])

mcp = load(f"{root}/mcp.json")
server = mcp["mcpServers"]["relate"]
assert server["type"] == "stdio" and server["command"], "mcp server must be stdio with a command"
print("mcp.json ok: server 'relate' ->", server["command"], server["args"])

import os
for d in ("skills/relate", "skills/relate-memory"):
    skill = open(f"{root}/{d}/SKILL.md", encoding="utf-8").read()
    assert skill.startswith("---"), f"{d}: missing frontmatter"
    name = re.search(r"^name:\s*(\S+)", skill, re.M).group(1)
    assert name == os.path.basename(d), f"{d}: frontmatter name {name} != dir"
    assert re.search(r"^description:\s*\S", skill, re.M), f"{d}: missing description"
    print(f"{d}/SKILL.md ok: name={name}")

hooks = open(f"{root}/ai.mistral.vibe/hooks.toml", encoding="utf-8").read()
assert 'type = "session_start"' in hooks and "session-context.sh" in hooks
print("hooks.toml ok")
PY
[ "$FAIL" -eq 0 ] && ok "manifests valid" || bad "manifest validation"

say "== 2. MCP stdio roundtrip =="
if command -v relate >/dev/null 2>&1; then
    OUT="$(printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0"}}}' \
        '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
        '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"write_cypher","arguments":{"statement":"CREATE (:Smoke {name: '"'"'ok'"'"'})"}}}' \
        '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"read_cypher","arguments":{"statement":"MATCH (s:Smoke) RETURN s.name AS name"}}}' \
        '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_schema","arguments":{}}}' \
        | "$ROOT/serve-relate-mcp.sh" 2>/dev/null)"
    # Tool results nest the wire envelope as an escaped JSON string inside
    # the MCP text content, so match the escaped forms (\"key\":value).
    echo "$OUT" | grep -q '"name":"relate-mcp"' && ok "initialize" || bad "initialize"
    echo "$OUT" | grep -q '"name":"read_cypher"' && echo "$OUT" | grep -q '"name":"write_cypher"' && echo "$OUT" | grep -q '"name":"get_schema"' \
        && ok "tools/list exposes read_cypher, write_cypher, get_schema" || bad "tools/list"
    echo "$OUT" | grep -qF '\"nodes_created\":1' && ok "write_cypher created a node" || bad "write_cypher"
    echo "$OUT" | grep -qF '\"rows\":[{\"name\":\"ok\"}]' && ok "read_cypher round-trips the row" || bad "read_cypher"
    echo "$OUT" | grep -qF '\"Smoke\"' && ok "get_schema sees the label" || bad "get_schema"
else
    say "skip - relate binary not on PATH (install: curl -sSfL https://relatedb.ai/install.sh | bash)"
fi

say "== 3. skill bundle into a Vibe-searched path (fake HOME) =="
if command -v relate >/dev/null 2>&1; then
    FAKE="$(mktemp -d)"
    HOME="$FAKE" XDG_CONFIG_HOME="$FAKE/.config" relate skill install --agent cline >/dev/null 2>&1
    if [ -f "$FAKE/.agents/skills/relate/SKILL.md" ]; then
        ok "relate skill install --agent cline lands in ~/.agents/skills/relate (a Vibe user-global skills path)"
        HOME="$FAKE" XDG_CONFIG_HOME="$FAKE/.config" relate skill check --agent cline >/dev/null 2>&1 \
            && ok "relate skill check passes (no drift)" || bad "skill check"
    else
        bad "bundle not found at $FAKE/.agents/skills/relate"
    fi
    rm -rf "$FAKE"
else
    say "skip - relate binary not on PATH"
fi

say "== 4. session-context hook output =="
if command -v relate >/dev/null 2>&1; then
    HOOK_OUT="$(echo '{"hook_event_name":"session_start"}' | "$ROOT/scripts/session-context.sh")"
    echo "$HOOK_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["hook_specific_output"]["additional_context"]; print("hook JSON ok")' \
        && ok "session-context.sh emits valid additional_context" || bad "session-context.sh output"
else
    say "skip - relate binary not on PATH"
fi

if [ "$FAIL" -eq 0 ]; then say "ALL CHECKS PASSED"; else say "FAILURES PRESENT"; exit 1; fi
