# MCP::ArcRaiders

MCP and REST server that gives AI assistants access to ARC Raiders game data.

## Synopsis

```perl
use MCP::ArcRaiders;

# stdio MCP server (Claude Desktop and other MCP clients)
MCP::ArcRaiders->new->run_stdio;

# or mounted in a Mojolicious app
use Mojolicious::Lite;
my $mcp = MCP::ArcRaiders->new;
any '/mcp' => $mcp->server->to_action;
app->start;
```

## Description

MCP::ArcRaiders wraps [WWW::MetaForge::ArcRaiders](https://metacpan.org/pod/WWW::MetaForge::ArcRaiders)
in [MCP::Server](https://metacpan.org/pod/MCP::Server) tools. It holds no game
data of its own: items, ARCs, quests, traders, event timers and map markers all
come from the MetaForge API. Responses are JSON strings; an empty result is a
plain sentence.

The distribution ships two executables:

- `mcp-arcraiders` - MCP server over stdio
- `mcp-arcraiders-http` - Mojolicious server with the MCP endpoint at `/mcp`,
  a REST API under `/api/...` and an OpenAPI description at `/openapi.json`

## Tools

| Tool | REST route | Purpose |
|---|---|---|
| `search_items` | `GET /api/items` | search items by `search`, limited by `limit` |
| `get_item_details` | `GET /api/items/:name` | full details of an item by name |
| `get_arcs` | `GET /api/arcs` | ARC enemies, optionally with loot |
| `get_quests` | `GET /api/quests` | quests, filterable by `type` |
| `get_traders` | `GET /api/traders` | traders and their inventories |
| `find_item_seller` | - | which trader sells an item |
| `get_event_timers` | `GET /api/events` | scheduled events |
| `get_active_events` | `GET /api/events/active` | events running now |
| `get_map_data` | `GET /api/maps/:map` | map markers by `category`, `subcategory`, `search` |
| `list_maps` | `GET /api/maps` | available maps with display names |
| `calculate_requirements` | `POST /api/requirements` | crafting materials for a list of items |

## Usage

### Claude Desktop (stdio)

```json
{
  "mcpServers": {
    "arcraiders": { "command": "mcp-arcraiders" }
  }
}
```

### HTTP server

```bash
mcp-arcraiders-http daemon -l http://*:3939
```

Claude Desktop connects to the MCP endpoint:

```json
{
  "mcpServers": {
    "arcraiders": { "url": "https://your-server/mcp" }
  }
}
```

### ChatGPT Actions

Import `https://your-server/openapi.json` as an Action schema. The environment
variable `OPENAPI_SERVER_URL` overrides the server URL in the generated
specification.

### Custom API object (tests)

```perl
my $mcp = MCP::ArcRaiders->new(
    api => WWW::MetaForge::ArcRaiders->new(ua => $mock_ua),
);
```

## Installation

```bash
cpanm MCP::ArcRaiders
```

## Testing

```bash
prove -lr t/                  # mocked API fixtures
USE_LIVE_API=1 prove -lr t/   # real MetaForge API
```

## License

This software is copyright (c) 2026 by Torsten Raudssus.

This is free software; you can redistribute it and/or modify it under the same
terms as the Perl 5 programming language system itself.
