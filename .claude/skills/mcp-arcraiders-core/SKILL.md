---
name: mcp-arcraiders-core
description: Use when implementing, extending, or debugging the MCP-ArcRaiders distribution — its MCP/REST tools, the WWW::MetaForge::ArcRaiders data source, the cache namespace, the two bin entrypoints, or the Docker deployment. Read before adding or changing a tool.
---

# MCP-ArcRaiders — architecture and invariants

MCP-ArcRaiders is a thin MCP/REST facade over game data. It holds **no game
data and no HTTP logic of its own** — every fact comes from
`WWW::MetaForge::ArcRaiders` (the upstream `p5-www-metaforge` distribution).
This repo's job is: register tools, shape upstream objects into JSON, and serve
them over two transports. Data-model questions ("does an item have a `weight`
field?", "what does `map_data` return?") are answered in `p5-www-metaforge`, not
here — see the coupling note at the bottom.

General MCP::Server mechanics are in the `perl-mcp` skill; the class is Moo, per
`getty-perl-moo`. This skill is only what is true about *this* distribution.

## The data source and cache

`MCP::ArcRaiders` composes two upstream objects, both lazy:

- `cache` → `WWW::MetaForge::Cache->new(namespace => 'mcp-arcraiders')`. The
  namespace string is load-bearing — it isolates this server's cache from other
  MetaForge consumers. Do not change it without a migration reason.
- `api` → `WWW::MetaForge::ArcRaiders->new(cache => $self->cache)`.

The `api` attribute is injectable — tests and the HTTP `daemon` pass their own
(`MCP::ArcRaiders->new(api => $custom)`). Never call `WWW::MetaForge::ArcRaiders`
directly from tool code; always go through `$self->api`, so the injected
instance wins.

Event data is deliberately fetched via `event_timers_hourly` (hourly-cached),
not a raw call — timers refresh hourly, and both event tools rely on that.

## The tool-handler pattern (this repo's shape)

Every tool is registered inside `_build_server`. The handler `code` sub here
**returns a plain string** — either `$self->_to_json($data)` or a bare
human-readable message for the empty case (`"No items found matching '...'"`).
It does *not* call `$self->text_result(...)`; MCP::Server accepts the plain
return. Match that: JSON on success, a plain sentence when there is nothing to
return.

`_to_json` uses one shared `JSON::MaybeXS` configured `utf8, pretty, canonical,
convert_blessed` — canonical ordering keeps output diffable, `convert_blessed`
lets blessed upstream objects serialize. Booleans go out as `\1` / `\0`.

Upstream objects are never handed to the encoder whole. Each type has a private
`_<type>_to_hash` shaper (`_item_to_hash`, `_arc_to_hash`, `_quest_to_hash`,
`_trader_to_hash`, `_event_to_hash`) that picks an explicit field list. Adding a
field to the output means editing the shaper, not the tool. Note `search_items`
uses the short `_item_to_hash`, while `get_item_details` inlines a *longer*
field set (crafting_requirements, sold_by, used_in, compatible_with,
recycle_yield) — details is intentionally heavier than search.

`get_map_data` requires both `map` and `category` and filters client-side,
because a map can carry 500+ markers; never drop the required `category` guard.

## The dual-surface invariant — three places per tool

A tool exists in up to **three** hand-maintained surfaces, and they do not
generate from each other:

1. **`lib/MCP/ArcRaiders.pm`** — the MCP tool (`$server->tool(...)`).
2. **`bin/mcp-arcraiders-http`** — a REST route (`get '/api/...'`) with its own
   inlined `_*_hash` helpers (a second, leaner copy of the shapers).
3. **`bin/mcp-arcraiders-http`** — an OpenAPI path under `/openapi.json`, which
   ChatGPT Actions import.

Adding or changing a tool means touching all three (plus the `/` info endpoint's
route list and the POD tool catalogue in `lib/`). A change that lands in only
the MCP tool silently diverges the REST/ChatGPT surface. When you edit one,
grep the other bin surface for the same operation and keep them in step.

## Two entrypoints

- `bin/mcp-arcraiders` — stdio server for Claude Desktop. One line:
  `MCP::ArcRaiders->run_stdio`. `run_stdio` self-instantiates if called as a
  class method.
- `bin/mcp-arcraiders-http` — `Mojolicious::Lite` app serving `/mcp` (MCP over
  HTTP via `$mcp->server->to_action`), the REST `/api/*` tree, `/openapi.json`,
  and a `/` info page. It prepends `$ENV{METAFORGE_LIB}` to `@INC` at BEGIN so a
  runtime-mounted upstream is found.

## Docker deployment

`WWW::MetaForge` is **not installed into the image** — the Dockerfile greps it
out of the cpanfile and installs only *its* dependencies; the module itself is
bind-mounted at runtime (`METAFORGE_LIB` + `PERL5LIB`, see
`docker-compose.example.yml`). This keeps the fast-moving data layer editable
without rebuilding. The cpanfile still declares `WWW::MetaForge >= 0.003` for
CPAN/test installs — both facts are true and intentional; do not "fix" the
apparent contradiction by adding it to the Docker install.

The compose example serves on port 3939 behind Traefik. The `.cache` dir is a
mounted volume so the MetaForge cache survives restarts.

## Upstream coupling (ZWILLING)

`p5-www-metaforge` (module `WWW::MetaForge`, `>= 0.003`) is the twin that owns
all game data and the object model. This repo must never be modified to work
around an upstream data gap — a missing field, a wrong shape, or a needed API
method is a **karr ticket filed against `p5-www-metaforge`**, not a patch here.
Do not edit the neighbor repo from this one.
