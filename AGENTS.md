# AGENTS.md — relate-mistral

This repo is a Vibe plugin package (Agent Plugins 1.0); the repo root is the
plugin root. See `docs/integration-plan.md` for the integration map and
decision log.

- Keep `plugin.json` schema-valid: `$schema` must stay exactly
  `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`; Vibe-specific
  settings go in the `extensions.ai.mistral.vibe` object only.
- Skill frontmatter `name` must match its directory name under `skills/`.
- After any change, run `scripts/smoke-test.sh` and keep it green.
- Never read or write `~/.vibe/.env` or any `.env` file; credentials belong
  to the user.
- The plugin must fail open: if the `relate` binary is missing, the MCP server
  and the session-start hook degrade silently (no session errors).
- `serve-relate-mcp.sh` defaults the store to `:memory:` on purpose (Relate is
  single-writer per store); document `RELATE_DATABASE` / `RELATE_SERVE_ARGS`
  rather than changing the default.
