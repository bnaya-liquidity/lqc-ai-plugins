# lqc-tokens

Token cost optimizer plugin for Claude Code. Reduces context waste through pre-prompt advisory hooks, database-backed context offloading, and session cost reporting.

## Installation

Copy this directory to your project's `.claude-plugin/` or install via the Claude Code plugin marketplace.

Run setup after installing:

    /lqc-tokens:setup

## Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| setup | `/lqc-tokens:setup` | Inject CLAUDE.md entry, verify Docker, configure MCP |
| cost-estimate | `/lqc-tokens:cost-estimate` | Token cost tiers and mitigation options |
| optimize-prompt | `/lqc-tokens:optimize-prompt` | Rewrite current prompt for token economy |
| docker-advisor | `/lqc-tokens:docker-advisor` | DB strategy for data-heavy tasks |
| graph-context | `/lqc-tokens:graph-context` | FalkorDB GraphRAG patterns |
| session-hygiene | `/lqc-tokens:session-hygiene` | Context drift detection + session reset |
| eval | `/lqc-tokens:eval` | Token savings report vs. baseline |

## Optional MCP Integration

For live Docker container management (vs. generating compose files), add to `.mcp.json`:

```json
{
  "mcpServers": {
    "docker": {
      "command": "docker",
      "args": ["mcp", "gateway", "run"],
      "type": "stdio"
    }
  }
}
```

See `.mcp.json.example` for the full template.

## Settings

`~/.claude/lqc-tokens.local.md` (auto-managed, gitignored): tracks ephemeral Docker containers for cleanup at session end.
