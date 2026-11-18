# relate-mistral

Integrations between [**Relate by Neo4j**](https://github.com/relatedb/relate)
— an embedded, single-binary Cypher graph database — and
[**Mistral Vibe**](https://mistral.ai/vibe).

This repository **is** a Vibe plugin (Agent Plugins 1.0 format). Installing it
gives every Vibe session:

- **MCP tools** `mcp_relate.get_schema`, `mcp_relate.read_cypher`,
  `mcp_relate.write_cypher` — backed by `relate serve --mcp stdio`
  (`mcp.json` + `serve-relate-mcp.sh`)
- **Skills** `relate:relate` (CLI + Cypher + storage + safety) and
  `relate:relate-memory` (graph-as-agent-memory pattern) under `skills/`
- **A session-start hook** that tells the model Relate is available and which
  tools/skills to use (`ai.mistral.vibe/hooks.toml`)

## Prerequisites

```bash
curl -sSfL https://relatedb.ai/install.sh | bash   # installs the relate binary
relate --version
```

## Install

```bash
scripts/install.sh          # symlinks this repo to ~/.vibe/plugins/relate
```

Then in Vibe: `/reload-plugins` (or start a new session), and check
`/plugins` (the `relate` plugin) and `/mcp` (the `relate` server with its
three tools).

`scripts/install.sh --project` installs into `<cwd>/.vibe/plugins/` instead
(the folder must be trusted); `--copy` copies instead of symlinking.

### Manual install (no plugin)

```bash
mkdir -p ~/.vibe/skills
cp -R skills/relate ~/.vibe/skills/relate
```

and add to `~/.vibe/config.toml`:

```toml
[[mcp_servers]]
name = "relate"
transport = "stdio"
command = "relate"
args = ["serve", "--mcp", "stdio", "--database", ":memory:"]
```

### Relate's own skill bundle (zero-code path)

`relate skill install --agent cline` writes Relate's bundled `SKILL.md` into
`~/.agents/skills/relate` — a directory Vibe searches natively — so the
upstream Relate skill also loads in Vibe today. (`relate skill install` does
not yet detect Vibe by name; the proposed `vibe` catalog entry is in
`docs/integration-plan.md` §4.)

## Usage

Ask the agent anything graph-shaped; it will use the MCP tools:

> "Create two Person nodes, link them with KNOWS, then show me the schema."

From the shell, the CLI works as usual and returns the same JSON envelope the
MCP tools return:

```bash
relate query "MATCH (p:Person) RETURN p.name" --database ./friends --mode envelope
```

### Persistent or shared graphs

The plugin's MCP server defaults to `:memory:` because Relate is single-writer
per store (concurrent sessions must not open the same store). For a durable
per-session store, set `RELATE_DATABASE=/path/graph.rl` in Vibe's environment
(or pass `--read-only` etc. via `RELATE_SERVE_ARGS`). For a graph shared across
sessions, run one server and attach Vibe over HTTP:

```bash
relate serve --database ./graph --mcp 7475 --auth neo4j:s3cret
vibe mcp add relate-shared --url http://127.0.0.1:7475/mcp \
  --transport streamable-http --api-key-env RELATE_MCP_TOKEN
```

## Verify

```bash
scripts/smoke-test.sh
```

validates the manifests, runs a live MCP stdio roundtrip
(initialize → tools/list → write → read → schema) against the installed
`relate`, drills `relate skill install` into a fake `$HOME` to prove the
`~/.agents/skills` path, and checks the hook emits valid JSON.

## Layout

```
├── plugin.json               # Agent Plugins 1.0 manifest (+ ai.mistral.vibe extension)
├── mcp.json                  # stdio MCP server "relate"
├── serve-relate-mcp.sh       # launcher: RELATE_DATABASE / RELATE_SERVE_ARGS -> relate serve --mcp stdio
├── skills/
│   ├── relate/SKILL.md       # core skill: MCP tools, CLI, storage, safety
│   └── relate-memory/SKILL.md
├── ai.mistral.vibe/hooks.toml
├── scripts/                  # install.sh, smoke-test.sh, session-context.sh
└── docs/integration-plan.md  # full plan: surfaces, integration map, gaps, upstream proposal
```

## Links

- Relate: https://github.com/relatedb/relate · docs https://relatedb.ai
- Vibe docs: https://docs.mistral.ai/vibe/code/overview
- Plan and gap analysis (incl. the upstream `skill install` Vibe entry):
  `docs/integration-plan.md`
