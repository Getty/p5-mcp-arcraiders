# MCP-ArcRaiders

MCP/REST server that exposes ARC Raiders game data to AI assistants. It holds no
game data of its own — everything comes from `WWW::MetaForge::ArcRaiders`
(`p5-www-metaforge`, the upstream twin).

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it
yourself — principle in the shared rule `agent-delegation` (skilletor bundle
`getty-cpan-dist@getty`), lanes and hazards in `.claude/rules/mcp-arcraiders-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `mcp-arcraiders-worker` (default) |
| Commits, `Changes`, card → done, pre-release audit | `mcp-arcraiders-release-manager` |

The agents carry their skills via `briefing.skills` (see `.claude/agents/`); the
main agent delegates rather than loading them. Skill sources live under
`.claude/skills/` — architecture is `mcp-arcraiders-core`.

Upstream data gaps go to `p5-www-metaforge` as karr tickets, never patched here.
