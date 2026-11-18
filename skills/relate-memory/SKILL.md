---
name: relate-memory
description: Pattern for using the Relate graph (via the mcp_relate.* tools) as structured, queryable agent memory — facts, decisions, entities, and session notes as nodes and relationships instead of prose files. Load when the user wants the agent to remember things across turns or sessions in a graph.
user-invocable: true
allowed-tools: bash read_file
---

# Relate as agent memory

Use the graph as the agent's structured memory: entities as nodes,
relationships as edges, observations as properties or dated `:Note` nodes.
Unlike prose notes, every entry is addressable by pattern, not by recall.

## Conventions

- One node per entity, keyed by a stable property, merged on write:

  ```cypher
  MERGE (p:Person {name: $name})
  SET p.lastSeen = datetime()
  RETURN p
  ```

- Link, don't nest: `(:Decision {id})-[:ABOUT]->(:Project {name})`,
  `(:Note)-[:MENTIONS]->(:Person)`.
- Timestamp everything: `SET n.created = datetime()`, and query ranges with
  `n.created >= datetime() - duration('P7D')`.
- Keep the schema discoverable: call `mcp_relate.get_schema {}` before
  inventing new labels/types; reuse existing ones.

## Write path

Always `MERGE` on the key property, then `SET` — idempotent, safe to replay:

```text
mcp_relate.write_cypher {
  "statement": "MERGE (d:Decision {id: $id}) SET d.summary = $summary, d.at = datetime() RETURN d.id AS id",
  "parameters": {"id": "…", "summary": "…"}
}
```

## Read path

Recall by relationship, not by keyword search:

```text
mcp_relate.read_cypher {"statement": "MATCH (d:Decision)-[:ABOUT]->(p:Project {name: $p}) RETURN d.summary, d.at ORDER BY d.at DESC LIMIT 10", "parameters": {"p": "…"}}
```

For "what do I know about X": `MATCH (n)-[r]-(m) WHERE n.name = $x OR m.name = $x RETURN …`.

## Session hygiene

- At the start of a task, read what's already known (`get_schema`, then a
  targeted MATCH) before writing — dedupe via `MERGE`.
- At the end of a substantive turn, record outcomes as `:Decision` /
  `:Note` nodes linked to the relevant entity.
- The plugin's MCP server defaults to `:memory:`, so memory lasts for the
  session. For cross-session memory, set `RELATE_DATABASE` to a durable
  store (or run one shared `relate serve --mcp PORT`) — see
  `skills/relate/SKILL.md` → "Store selection and sharing".

## When NOT to use the graph

Small, flat, per-project config → files. The graph earns its keep when
entries interconnect (people ↔ projects ↔ decisions ↔ notes) and you query
by traversal.
