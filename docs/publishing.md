# Publishing relate-mistral to Vibe users

## How Vibe distributes plugins (current state)

- The **Agent Plugins 1.0 spec deliberately has no registry**: the package unit
  is a filesystem directory, versioned with git — "distribution, installation,
  … remain under each client's control" (agent-plugins.org, spec 1.0.0).
- Vibe (this version) loads plugins from exactly three places:
  `~/.vibe/plugins/<name>/` (user scope, always), `./.vibe/plugins/<name>/`
  (project scope, trusted folder or `--add-dir`), and built-ins. There is no
  `vibe plugin install <url>` subcommand (only `mcp`, `config`, `help`), so
  "install from another source" means placing the directory into a plugins
  root — clone, copy, or symlink.
- Name collisions: project > user > built-in; two same-name plugins at one
  scope load neither.
- Sessions **pin** plugin content at start; `/reload-plugins` re-pins. MCP
  servers reconnect every session (not pinned).
- Trust: project plugins load only in trusted folders; user plugins load in
  every session; plugin tools go through the same approval/permission rules;
  admins can disable plugin MCP with `enable_mcp = false`. Docs flag plugin
  support as experimental.
- Skills-only channel: `experimental_enable_registry_skills` pulls shared
  workspace skills from Mistral's AI Registry (api.mistral.ai) with version
  pins (ADR-0021 in mistralai/mistral-vibe). Registry skills cannot carry
  `mcp.json` or hooks, so the MCP wiring still needs the plugin or a plain
  `[[mcp_servers]]` config block.

## Publishing checklist for this repo

1. **Create the public repo** `relatedb/relate-mistral` and push `main`
   (this directory is already the plugin root).
2. **License**: `LICENSE` (Apache-2.0, matching Relate) — `plugin.json` already
   declares `"license": "Apache-2.0"`.
3. **Tag releases**: `git tag v0.1.0 && git push origin v0.1.0`. The directory
   is the package; a GitHub Release with a `git archive` tarball is a
   convenience, not required by the format. Bump `version` in `plugin.json`
   with each release.
4. **Keep the manifest registry-ready**: exact `$schema`, semver `version`,
   `repository`/`homepage` — so the repo works unchanged if Vibe later adds a
   plugin registry or marketplace.
5. **One-line install** (README): `scripts/bootstrap.sh` clones (or tarball-
   falls back) into `~/.vibe/plugins/relate`; updates on re-run.
6. **CI gate per release**: `.github/workflows/ci.yml` installs `relate` and
   runs `scripts/smoke-test.sh`; release only when green.
7. **Team distribution**: commit `.vibe/plugins/relate` (vendored copy or
   symlink) into a shared repo — every trusted checkout loads it; project
   scope wins over user scope.
8. **Announce**: link from relatedb.ai / relate docs and upstream issue
   https://github.com/relatedb/relate/issues/527.

## User install options (documented in README)

| Option | Command | Scope |
|---|---|---|
| One-line bootstrap | `curl -LsSf https://raw.githubusercontent.com/relatedb/relate-mistral/main/scripts/bootstrap.sh \| sh` | user |
| Git clone | `git clone https://github.com/relatedb/relate-mistral ~/.vibe/plugins/relate` | user |
| Dev symlink | `git clone … && cd relate-mistral && scripts/install.sh` | user, live edits |
| Team repo | commit `.vibe/plugins/relate` in the project | project (trusted) |
| No plugin | copy `skills/relate` → `~/.vibe/skills/relate` + `[[mcp_servers]]` block in `config.toml` | user, config-only |

After install: `/reload-plugins` (or new session) → `/plugins` lists `relate`,
`/mcp` shows the server with `get_schema` / `read_cypher` / `write_cypher`.

## Caveats

- The plugin needs the `relate` binary on `PATH`; it fails open with a clear
  error otherwise. Auto-downloading `relate` inside the launcher was rejected
  on supply-chain grounds — the README points at the official installer.
- Plugin support is experimental in Vibe; the format may change between
  releases. Pin by git tag if stability matters.
