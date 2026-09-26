# MCP-ArcRaiders House Rules

Apply to every task in this repository unless explicitly overridden. Bias:
caution over speed on non-trivial work; use judgment on trivial tasks. Loaded
automatically at launch (same priority as `CLAUDE.md`). Subagents get their
discipline from the skills force-loaded via `briefing.skills` — this file is for
the orchestrating agent.

## Engineering discipline

1. **Think before coding** — State assumptions. When uncertain, ask rather than
   guess. Push back when a simpler approach exists. Stop when confused; name
   what's unclear.
2. **Simplicity first** — Minimum code that solves the problem. No abstractions
   for single-use code.
3. **Surgical changes** — Touch only what you must. Don't "improve" adjacent
   code or formatting. Match existing style.
4. **Read before you write** — Before new code, read the tool's registration in
   `lib/MCP/ArcRaiders.pm`, its REST/OpenAPI twin in `bin/mcp-arcraiders-http`,
   and the `_*_to_hash` shapers.
5. **Fail loud** — "Done" is wrong if anything was skipped silently. "Tests
   pass" is wrong if any were skipped. Surface uncertainty, don't hide it.
6. **A red test is a claim before a failure** — Say what a test asserts before
   changing code to make it green; don't satisfy an assertion by deleting the
   property it samples.

## Delegation

This rule depends on whether the Agent/Task tool is available to you.

- **You can spawn subagents** (orchestrating main agent): Do NOT touch
  behavior-relevant code yourself — delegate to `mcp-arcraiders-worker`. Your
  lane: coordinate, inspect, plan, review diffs, run tests, edit
  non-behavioral docs. Only the `mcp-arcraiders-*` agents get their skills
  force-loaded via `briefing.skills`; you get no briefing.

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug behavior-relevant code | `mcp-arcraiders-worker` (default) |
  | Commits, `Changes`, card → done, pre-release audit | `mcp-arcraiders-release-manager` |

- **You cannot spawn subagents** (you ARE a `mcp-arcraiders-*` agent): The
  delegation lock does not apply — implement, refactor, debug, and test per
  these rules.

Behavior-relevant = MCP tools, REST/OpenAPI routes, the `_*_to_hash` shapers,
the cache namespace, error handling, and tests. Pure prose docs and `Changes`
notes are not.

**Only `mcp-arcraiders-release-manager` commits.** A worker leaves a commit-ready tree and hands its card
to `review`; you then dispatch `mcp-arcraiders-release-manager` to cut the commit and close the card.

## Coordination — karr board (always in scope)

Ticket coordination is the orchestrating agent's job, so `karr` is always in
scope — just use it (skill `kanban-issues-karr-coordination` for the full surface).
Git-native kanban; state lives in `refs/karr/*`; this repo has its own board.

- `karr list --compact` / `karr board` — open work · `karr show ID` — detail
- `karr create "Title" --priority high --body '…'` — new ticket
- `karr move ID in-progress --claim NAME` — start · `karr handoff ID --claim NAME --note "…"` — to review

**Serialize board mutations when fanning out.** Keep implementation parallel if
you like, but loop `karr move`/`handoff`/`sync` sequentially — N landing at once
is a resource event, not a cheap command.

## Upstream coupling — p5-www-metaforge (ZWILLING)

All game data and the object model live in `WWW::MetaForge` (`p5-www-metaforge`,
`>= 0.003`), the twin repo. A missing field, wrong shape, or needed API method
is a **karr ticket filed against p5-www-metaforge** — never a workaround here,
and never a direct edit of the neighbor repo. This repo only registers tools and
shapes upstream objects into JSON.

## The three-surface trap

Every tool lives in three hand-maintained places that do not generate from each
other: the MCP tool (`lib/MCP/ArcRaiders.pm`), the REST route, and the
`/openapi.json` path (both in `bin/mcp-arcraiders-http`). A change that lands in
only one silently diverges the ChatGPT/REST surface from MCP. Touch one → grep
the others for the same operation and update them together.

## Release — never without permission

`dzil build` / `prove -lr t/` are fine anytime. `dzil release` and any upload or
deploy are STRICTLY forbidden without the maintainer's explicit go-ahead — even
if a plan lists "release" as the next step. Stop and ask.

## Perl / MCP specifics — reference, don't restate

Moo class patterns live in skill `getty-perl-moo`; MCP::Server mechanics in
`perl-mcp`; dist.ini/release conventions in `perl-release-dist-ini` and
`getty-perl-release-author-getty`; this distribution's architecture in
`mcp-arcraiders-core` (all force-loaded for `mcp-arcraiders-*` agents). Do not
duplicate that content here.
