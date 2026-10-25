# MCP-ArcRaiders House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

MCP server providing ARC Raiders game data for AI assistants. Read first: the tool's
registration in `lib/MCP/ArcRaiders.pm`, its REST/OpenAPI twin in `bin/mcp-arcraiders-http`, and
the `_*_to_hash` shapers.

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `mcp-arcraiders-worker` (default) |
| Commits, `Changes`, card → done, pre-release audit | `mcp-arcraiders-release-manager` |
| Read-only research, audit, gap analysis | `mcp-arcraiders-worker` ("read-only, change nothing") |

Behavior-relevant = MCP tools, REST/OpenAPI routes, the `_*_to_hash` shapers, the cache
namespace, error handling, and tests. Pure prose docs and `Changes` notes are not.

## Release

The release also builds, tags and pushes the Docker image `raudssus/mcp-arcraiders` (`dist.ini`
`docker_image`) — the publish gate covers it as part of the release, and any deploy.
`DZIL_DOCKER_API_SKIP=1` keeps `dzil build`/`dzil test` off the container engine.

## Deviations from the house rules

- **CPAN RT counts as a public tracker** alongside GitHub issues on `Getty/p5-mcp-arcraiders`.

## Hazards — the background is in skill `mcp-arcraiders-core`

- **Three surfaces per tool** — the MCP tool, the REST route and the `/openapi.json` path do not
  generate from each other. Change one → grep the others for the same operation and update them
  together, or the surfaces silently diverge.
- **Upstream owns the data** (`p5-www-metaforge`, ZWILLING) — a missing field, a wrong shape or a
  needed API method is a **karr ticket against `p5-www-metaforge`**, never a workaround here and
  never a direct edit of the neighbor repo.

## Perl / MCP specifics — reference, don't restate

Moo class patterns live in skill `getty-perl-moo`; MCP::Server mechanics in `perl-mcp`;
dist.ini/release conventions in `perl-release-dist-ini` and `getty-perl-release-author-getty`;
architecture in `mcp-arcraiders-core` (all force-loaded for `mcp-arcraiders-*` agents).
