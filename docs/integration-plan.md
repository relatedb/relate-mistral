# Relate x Mistral Vibe — integration plan

Repo: `relatedb/relate-mistral`. This document is the plan; the repo root is
itself a Vibe plugin package (Agent Plugins 1.0) that implements the
"Vibe-side" half of the integration.

## 1. What each side brings

### Relate by Neo4j (`relatedb/relate`, installed here as `relate` v1.0.1)

An embedded, in-memory property-graph engine in a single Rust binary.
One graph store = a directory, a single `.rl` file, or `:memory:`. Durable
via fsync'd WAL + Parquet checkpoints. Cypher 25 / GQL-aligned, vector and
spatial indexes. Surfaces:

| Surface | Invocation | Shape |
|---|---|---|
| CLI one-shot / REPL | `relate query "CYPHER" --database PATH [--mode envelope]` | JSON envelope (`columns`, `rows`, `stats`, `error`, …) — script-friendly |
| MCP stdio | `relate serve --mcp stdio --database PATH` | newline-delimited JSON-RPC; tools `get_schema`, `read_cypher`, `write_cypher`; no auth on stdio |
| MCP streamable HTTP | `relate serve --mcp PORT --auth USER:PASS` | POST JSON-RPC, Basic auth |
| HTTP Query API v2 | `relate serve --http PORT` | Neo4j-shaped JSON query API |
| Bolt | `relate serve --bolt PORT` | neo4j drivers / cypher-shell / Neo4j Browser work |
| Skill bundle | `relate skill install [--agent NAME]` | writes `SKILL.md` + references into an agent's skills dir, ownership-marked |
| Agent briefing | `relate agent-context [COMMAND]` | compact command index + exit codes for agent harnesses (ADR-0242) |
| Extensions | `relate run git-to-graph …`, `relate run fs-to-graph …` | command-kind extension packages |
| Aura bridge | `relate pull --from …`, `relate push --to …` | subgraph sync with Neo4j/Aura over HTTP Query API v2 |
| Embedded clients | Python `relate-db`, Node `@relate/relate`, Rust crate, WASM, Java, Go, Swift, C ABI | in-process, no server |

MCP tool contract (verified against the installed binary):

- `read_cypher {statement, parameters?}` — read-only gate; writes and DDL are
  rejected with `Only MATCH queries are allowed for read-query`.
- `write_cypher {statement, parameters?}` — write gate; absent entirely under
  `--read-only`.
- `get_schema {sample_size?}` — labels, property keys/types, relationship
  types; `sample_size: -1` = full scan.
- All cypher tools return the canonical wire envelope as text content.

### Mistral Vibe (this CLI)

Extension points (see `vibe:vibe` skill):

| Vibe mechanism | Where it lives | Use for Relate |
|---|---|---|
| MCP servers | `[[mcp_servers]]` in `config.toml`, `vibe mcp add`, or plugin `mcp.json` | expose `read_cypher` / `write_cypher` / `get_schema` as `mcp_relate.*` tools |
| Plugins (Agent Plugins 1.0) | `~/.vibe/plugins/<name>/` (user) or `.vibe/plugins/<name>/` (project, trusted) | this repo ships as one plugin |
| Skills | `~/.vibe/skills/`, `~/.agents/skills/`, `.vibe/skills/`, `skill_paths`, plugin `skills/` | teach the agent Relate CLI + Cypher + patterns |
| Hooks | `hooks.toml` / plugin `ai.mistral.vibe/hooks.toml` | `session_start` hook injecting Relate availability/context |
| Shell | `bash` tool | `relate query --mode envelope` one-shots, `relate run …`, pull/push |

## 2. Integration map (what this repo builds)

| # | Integration | Mechanism | Status |
|---|---|---|---|
| 1 | Graph queries as agent tools | plugin `mcp.json` → `relate serve --mcp stdio` → `mcp_relate.read_cypher` / `write_cypher` / `get_schema` | built here |
| 2 | CLI fallback + scripting from the agent | `skills/relate/SKILL.md` documents `relate query … --mode envelope` via `bash` | built here |
| 3 | Relate knowledge at session start | plugin hook runs `relate --version` / availability check and injects `additional_context` | built here |
| 4 | Agent-memory pattern | `skills/relate-memory/SKILL.md` (facts/decisions as nodes, MERGE-on-read) | built here |
| 5 | Relate's own skill bundle lands in Vibe | `relate skill install --agent cline` writes to `~/.agents/skills/relate`, which Vibe loads natively (user-global search path) | zero-code path, documented + smoke-tested; **gap**: Vibe is not in relate's agent catalog, see §4 |
| 6 | Shared/persistent graph across sessions | one long-running `relate serve --mcp 7475 --database ./graph --auth …`, Vibe attaches with `vibe mcp add relate --url http://127.0.0.1:7475/mcp …` (streamable-http) | documented in README |
| 7 | Per-session scratch graph | plugin default `:memory:`; `RELATE_DATABASE` env overrides (see `serve-relate-mcp.sh`) | built here |
| 8 | Subgraph sync with Neo4j Aura | `relate pull` / `relate push` from `bash`, covered in the skill | documented |
| 9 | Repo history as a graph | `relate run git-to-graph` from `bash` | documented |

Why stdio for the plugin and HTTP for the shared server: Relate is
single-writer per store, so concurrent Vibe sessions must not each open the
same store writable. Default plugin config therefore uses `:memory:` (zero
conflicts, zero setup); anything shared goes through one `serve` process.

## 3. Repo layout (repo root = the plugin)

```
relate-mistral/
├── plugin.json                  # Agent Plugins 1.0 manifest + ai.mistral.vibe extension
├── mcp.json                     # stdio MCP server "relate" → serve-relate-mcp.sh
├── serve-relate-mcp.sh          # launcher: RELATE_DATABASE (default :memory:) → relate serve --mcp stdio
├── skills/
│   ├── relate/SKILL.md          # core: MCP tools + CLI + storage + safety
│   └── relate-memory/SKILL.md   # structured agent memory pattern
├── ai.mistral.vibe/
│   └── hooks.toml               # session_start hook
├── scripts/
│   ├── install.sh               # symlink repo → ~/.vibe/plugins/relate
│   ├── session-context.sh       # hook script (version + pointers as additional_context)
│   └── smoke-test.sh            # JSON validation + live MCP stdio roundtrip + skill-install drill
├── docs/integration-plan.md     # this file
├── README.md
└── AGENTS.md
```

Install: `scripts/install.sh` symlinks the repo into
`~/.vibe/plugins/relate`, then `/reload-plugins` (or a fresh session).
Manual alternative (no plugin): copy `skills/relate` to `~/.vibe/skills/relate`
and add the `[[mcp_servers]]` block from the README to `~/.vibe/config.toml`.

## 4. Gaps and upstream proposals

1. **`relate skill install` does not detect Vibe.** The catalog in
   `surfaces/relate-cli/src/skill/agents.rs` (`pub const AGENTS`) lists 11
   agents (claude-code, cursor, windsurf, copilot, antigravity, gemini-cli,
   cline, codex, pi, opencode, junie) — no Vibe. Proposed upstream entry:

   ```rust
   Agent {
       name: "vibe",
       display_name: "Mistral Vibe",
       detect_dir: "~/.vibe",
       skills_dir: "~/.vibe/skills",
   },
   ```

   (The struct has exactly four fields: `name`, `display_name`, `detect_dir`,
   `skills_dir`; tests in the same file assert the catalog length and order,
   so the PR must update `catalog_has_eleven_entries_in_order`.) Filed
   upstream as https://github.com/relatedb/relate/issues/527. Until that
   lands, path 5 above (`--agent cline` → `~/.agents/skills`, which Vibe also
   searches) works today.

2. **Namespace prefix on MCP tools.** `relate serve` supports an optional
   `<namespace>-` prefix on tool names; the plugin keeps the unprefixed
   names (`mcp_relate.read_cypher`) for parity with the reference server.

3. **Read-only mode for untrusted projects.** `relate serve --read-only`
   drops `write_cypher` from `tools/list` entirely. Recommended when pointing
   a shared server at a store other agents write to. `RELATE_SERVE_ARGS` in
   `serve-relate-mcp.sh` passes flags through.

## 5. Verification

`scripts/smoke-test.sh`:

1. Validates `plugin.json` / `mcp.json` parse and carry required fields.
2. Spawns `relate serve --mcp stdio --database :memory:` and runs
   initialize → tools/list → write_cypher → read_cypher → get_schema,
   asserting the row round-trips (same assertions as relate's own
   `tests/stdio_tools.rs`).
3. Drills `relate skill install --agent cline` under a fake `$HOME`,
   proving the bundle lands in `<home>/.agents/skills/relate` — the path
   Vibe searches — and `relate skill check` passes there.

Manual end-to-end in Vibe: after install, `/plugins` lists `relate`,
`/mcp` shows the `relate` server with its three tools, and asking the agent
"what's in the graph?" makes it call `mcp_relate.get_schema`.

## 6. Decision log

- **Plugin, not config-only**: the repo is the plugin so skills, MCP wiring,
  and the hook ship together and stay versioned with the integration.
- **stdio default, `:memory:` store**: single-writer engine → no shared-store
  lock conflicts between concurrent Vibe sessions; sharing is done via one
  HTTP/Bolt server instead.
- **Wrapper script over direct args in `mcp.json`**: lets `RELATE_DATABASE` /
  `RELATE_SERVE_ARGS` env vars configure the store without editing JSON, and
  keeps `mcp.json` free of host-specific paths (`${PLUGIN_ROOT}` expansion is
  only guaranteed inside the plugin).
- **Hook fails open**: no `relate` binary → hook exits 0 silently; a missing
  dependency must never degrade a session.
