---
name: setup
description: Installs lqc-tokens into the current project by injecting a CLAUDE.md entry and optionally configuring the Docker MCP server. Use when the user says "set up lqc-tokens", "install lqc-tokens", "configure lqc-tokens", or runs /lqc-tokens:setup for the first time. Also use to upgrade an existing installation when the plugin version has changed.
allowed-tools: Read, Write, Edit, Bash
---

# lqc-tokens Setup

## Step 1: Check current installation

Read `CLAUDE.md` (or `~/.claude/CLAUDE.md` if no project CLAUDE.md exists).

Search for the string `lqc-tokens`. If found, extract the version number from the line:
```
## Token Cost Optimization (lqc-tokens vX.Y.Z)
```

Compare against plugin version `0.1.0`.

- If not found: proceed to Step 2 (fresh install)
- If found and version matches: tell user "lqc-tokens v0.1.0 is already installed" — done
- If found and version is older: proceed to Step 2 (upgrade — replace the block)

## Step 2: Inject CLAUDE.md entry

Find `CLAUDE.md` in the project root. If it doesn't exist, create it with just this block.

If upgrading, find and replace the block from the line `## Token Cost Optimization (lqc-tokens v` through the last bullet line starting with `- When session context drifts` (inclusive). Replace the entire range with the new block below. If fresh install, append to the end of the file.

Block to inject:
```markdown
## Token Cost Optimization (lqc-tokens v0.1.0)

- Consider using this plugin proactively, especially when context is growing large or the task involves large datasets.
- When a prompt is predicted to be medium or high cost, consult the `cost-estimate` skill for mitigation options.
- For data-heavy tasks (files, bulk analysis, web data), invoke the `docker-advisor` skill to suggest a database strategy.
- For relationship-heavy or knowledge-graph tasks, invoke the `graph-context` skill.
- When session context drifts or grows stale, invoke the `session-hygiene` skill.
```

## Step 3: Verify Docker

```bash
docker --version
```

If Docker is not installed, tell the user:
> "Docker is not installed. The docker-advisor skill will generate compose files but cannot spin up containers automatically. Install Docker Desktop from docker.com to enable live container management."

If Docker is installed, show the version and confirm.

## Step 4: Capture baseline (first install only)

On fresh install (not upgrade), capture a token usage baseline:

```bash
node ~/.claude/plugins/cache/claude-plugins-official/session-report/unknown/skills/session-report/analyze-sessions.mjs --json --since 7d > ~/.claude/lqc-tokens-baseline.json 2>/dev/null
```

If the command fails (session-report not installed), skip silently.

If it succeeds, confirm: "Baseline captured. Run `/lqc-tokens:eval` after 7+ days to measure token savings."

## Step 5: Optional Docker MCP configuration

Ask the user:
> "Configure Docker MCP for live container management? This lets docker-advisor actually spin up containers instead of only generating compose files. (yes/no)"

If yes:
1. Read `.mcp.json` from project root, or start with `{}` if it doesn't exist
2. Parse the JSON. Check if `mcpServers.docker` already exists — if so, skip (already configured)
3. If `mcpServers` key is absent, add it as an empty object first
4. Add ONLY the `docker` key under `mcpServers`, preserving all other existing server entries:
   ```json
   "docker": {
     "command": "docker",
     "args": ["mcp", "gateway", "run"],
     "type": "stdio"
   }
   ```
5. Write the merged JSON back to `.mcp.json` with 2-space indentation
6. Confirm: "Docker MCP configured. Restart Claude Code for it to take effect."

If no: skip.

## Step 6: Confirm installation

Output summary:
```
lqc-tokens v0.1.0 installed
─────────────────────────────────
✓ CLAUDE.md updated
✓ Docker: {version or 'not found'}
✓ Baseline: {captured or 'skipped (install session-report for eval)'}
✓ Docker MCP: {configured or 'skipped'}

Available skills: /lqc-tokens:cost-estimate, /lqc-tokens:optimize-prompt,
  /lqc-tokens:docker-advisor, /lqc-tokens:graph-context,
  /lqc-tokens:session-hygiene, /lqc-tokens:eval
```
