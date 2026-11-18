---
name: relate
description: Use Relate by Neo4j — an embedded, single-binary Cypher graph database — from Vibe. Covers the bundled MCP tools (read_cypher, write_cypher, get_schema), the relate CLI for one-shot queries and extensions, store selection, schema discovery, and safety. Load when the user wants to query, build, or inspect a graph, or to use a graph as structured memory.
user-invocable: true
allowed-tools: bash read_file
---

# Relate from Vibe

Relate is an embedded property-graph engine in one binary (`relate`, v1.x).
No server to run for the default setup: this plugin spawns
`relate serve --mcp stdio` as an MCP server, so the graph is available as
tools in every session. Databases are a directory, a single `.rl` file, or
`:memory:` (the plugin default).

## Preferred path: the MCP tools

The plugin's MCP server is named `relate`, so its tools appear as:

| Tool | Purpose |
|---|---|
| `mcp_relate.get_schema` | Labels, property keys + inferred types, relationship types. Args: `{sample_size?}` (`-1` = full scan). |
| `mcp_relate.read_cypher` | Read-only Cypher. Args: `{statement, parameters?}`. Writes and DDL are rejected. |
| `mcp_relate.write_cypher` | Mutating Cypher (CREATE/MERGE/SET/DELETE). Args: `{statement, parameters?}`. Absent if the server runs `--read-only`. |

Each cypher tool returns a JSON **wire envelope** as text content:
`{"columns": [...], "columnTypes": [...], "rows": [{...}], "stats": {"nodes_created": ...}, "notifications": [...], "plan": {...}|null, "elapsed_ms": ..., "error": null}`.
Parse `rows` for results, `stats` for mutation counters, `error`/`isError`
for failures. Pass Cypher parameters as the `parameters` object
(`RETURN $name` ← `{"parameters": {"name": "Ada"}}`); an object with a
`rows` array feeds `$rows`.

## CLI fallback (bash tool)

When you need scripting, bulk output, or a different store than the MCP
server's:

```bash
relate query "MATCH (p:Person) RETURN p.name" --database ./mydata --mode envelope
relate query --database ./mydata < script.cypher      # script from stdin
relate run git-to-graph --help                         # repo history as a graph
```

- `-d` / `--database PATH`: directory, `.rl` bundle, or `:memory:` (default).
- `--mode envelope` (alias `--format`; also `--json`, `--jsonl`, `--csv`,
  `--markdown`, `--toon`) gives the same JSON envelope as the MCP tools.
- The MCP server's store is `:memory:` unless `RELATE_DATABASE` is set in the
  environment; the CLI always takes an explicit `--database`.

## Before writing Cypher: read the schema

```text
mcp_relate.get_schema {}
-- or, for the live ontology (labels/types/keys the store actually uses):
RELATE_PREVIEW=ontology relate query "CALL db.ontology.get()" --database ./mydata
```

Take labels, relationship types, and property names from the schema, not
from guesses. `get_schema` counts are exact; property types are inferred from
a sample (`sample_size`, default 1000).

## Store selection and sharing

- Plugin MCP server: `:memory:` by default (single-writer engine — concurrent
  sessions must not open the same store). Set `RELATE_DATABASE=/path/graph.rl`
  in Vibe's environment to give it a durable store; add `--read-only` via
  `RELATE_SERVE_ARGS` for untrusted contexts (`write_cypher` then disappears
  from the tool list).
- Shared graph across sessions: run one server and attach over HTTP:

  ```bash
  relate serve --database ./graph --mcp 7475 --auth neo4j:s3cret   # long-running
  vibe mcp add relate-shared --url http://127.0.0.1:7475/mcp \
    --transport streamable-http --api-key-env RELATE_TOKEN
  ```

- Move data between Relate and Neo4j Aura: `relate pull --from CREDS
  --query "…" --database ./local` and `relate push --to CREDS --database ./local`.
- One-off load without keeping a store: `relate --load https://…/test.rl
  "MATCH (n) RETURN count(n)"` (runs into `:memory:`, keeps nothing on disk).

## Safety

- Prefer `read_cypher` for exploration; use `write_cypher` only when the user
  asked for a mutation. Both tools classify via EXPLAIN first and refuse the
  wrong class.
- `DETACH DELETE` and unbounded `MATCH` are destructive/full-scan — check the
  schema and bound queries (`LIMIT`, label-anchored `MATCH`) first.
- The `notifications` array in every envelope carries engine warnings
  (cartesian products, unknown labels/keys) — read it before retrying.

## References

- Docs: https://relatedb.ai — CLI, Cypher, vector/spatial, Python/Node/Rust
  references; deep references in `docs/` of https://github.com/relatedb/relate
- Honest limitations: `docs/limitations.md` in the relate repo (in-memory
  working set, one graph per store, single writer per process)
- Full integration plan: `docs/integration-plan.md` in this repo
