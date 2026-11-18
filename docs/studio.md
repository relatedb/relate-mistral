# Relate × Mistral Studio

Mistral Studio's extension point for external tools is **Connectors**
(Studio → Context → Connectors): a custom MCP server registered by URL,
discoverable and callable in conversations, agents, workflows, and direct
tool calls via the API/SDK. Relate plugs in as a **live MCP server**
(`relate serve --mcp PORT`, streamable HTTP) — there is no stdio path from
Studio's cloud, hence the long-running server.

```
relate serve --database /srv/graph --mcp 7475 --auth relate:$TOKEN
        │  plaintext HTTP, binds 127.0.0.1 by default (single writer per store)
        ▼
TLS-terminating proxy or tunnel (Caddy / nginx / cloudflared) → https://graph.example.com/
        │  MCP answers POST / (and /mcp) with 200 application/json; 401 without auth
        ▼
Studio connector: {"protocol":"mcp", "server":"https://graph.example.com/", "headers":{…}}
        ▼
conversations · agents · workflows · direct tool calls · (workspace admin) Vibe
```

## 1. Run the server

One `serve` process per store — Relate is single-writer, and every Studio
user shares the graph through that one endpoint (the MCP HTTP transport is
stateless per request, so this is safe):

```bash
relate serve --database /srv/graph --mcp 7475 --auth relate:$RELATE_TOKEN
# read-only shared graph (write_cypher disappears from tools/list):
#   add --read-only          (snapshot)  or  --read-only=live  (tails a writer's WAL)
```

- Default bind is loopback; a non-loopback `--host` prints a loud plaintext
  warning. **serve has no TLS** — always front it.
- Auth is RFC 7617 Basic, one credential shared by all served surfaces:
  `--auth user:pass`, `RELATE_AUTH`, or a generated token persisted to
  `<dir>.auth-token`. `--auth none` disables it (then let the proxy
  authenticate).

## 2. Expose it over TLS

Studio needs an `https://` URL. Bind loopback and terminate TLS in front:

```bash
# Caddy example
caddy reverse-proxy --from graph.example.com --to 127.0.0.1:7475
# or a quick tunnel for testing
cloudflared tunnel --url http://127.0.0.1:7475
```

Verified locally: `POST /` and `POST /mcp` both answer `tools/list` with
`200 application/json` (with `Content-Type: application/json`); without the
credential they answer `401`.

## 3. Register the connector in Studio

UI: Studio → Context → Connectors → add an MCP connector with the server
URL and a visibility scope. API/SDK:

```python
import asyncio, base64
from mistralai.client import Mistral

client = Mistral(api_key="your-api-key")

async def main() -> None:
    basic = base64.b64encode(b"relate:" + RELATE_TOKEN.encode()).decode()
    connector = await client.beta.connectors.create_async(request={
        "protocol": "mcp",
        "name": "relate",
        "description": "Relate embedded graph DB — Cypher tools (get_schema, read_cypher, write_cypher)",
        "server": "https://graph.example.com/",
        "visibility": "shared_workspace",  # private | shared_workspace | shared_org (org admins only)
        "headers": {"Authorization": f"Basic {basic}"},  # static header sent with every request
    })
    print(connector.id, connector.name, connector.server)

asyncio.run(main())
```

Optional create fields: `title`, `icon_url`, `system_prompt` (added when the
model uses this connector's tools), `oauth2_server_metadata` (only if the
server must do OAuth instead of a static header).

If you keep auth in the credential layer instead, connect with:

```python
await client.beta.connectors.create_credentials_async(
    connector_id_or_name=connector.id,
    consumer_scope="user",
    name="relate-default",
    credentials={"headers": {"Authorization": f"Basic {basic}"}},
    is_default=True,
)
```

## 4. Test, then use

1. **Connectors Debugger**: `tools/list` should show `get_schema`,
   `read_cypher`, `write_cypher` (absent under `--read-only`).
2. Use the connector in **conversations**, attach it to **agents**
   (including Durable/Managed Agents — the agent calls connector tools in
   its loop), **workflows**, or call its tools directly via
   `client.beta.connectors...` / conversation API with the connector name or id.
3. Workspace admins can also expose the connector to **Vibe** for the
   workspace ("Connectors and Connector tools available in Studio and Vibe"),
   so one registration serves both surfaces.

Programmatic agents in your own code can attach the same URL directly via the
`mistralai` Agents SDK's `MCPServerStreamableHttp`.

## Caveats

- Studio is cloud-side: the URL must be reachable and `https`. Relate itself
  stays plaintext on loopback behind your proxy.
- Single-writer: don't run two `serve` processes (or a writable CLI open)
  on the same store; share via the one server. Use `--read-only=live` on the
  server if another process writes.
- Tool results return Relate's wire envelope as JSON text
  (`rows`, `stats`, `notifications`, `error`) — the model reads `rows`.
- Connector names: ≤64 chars, letters/digits/underscore/dash; reference by
  `name` or `id` afterwards.

## Verified against

- `relate` v1.0.1: `POST /` and `POST /mcp` → `200` with `tools/list`
  (needs `Content-Type: application/json`); no auth → `401`.
- Studio docs: `docs.mistral.ai/studio/connectors/management` (create /
  credentials / visibility / `headers`), `…/debugger`,
  `docs.mistral.ai/admin/workspaces/workspaces-in-studio` (Studio+Vibe
  connector sharing).
