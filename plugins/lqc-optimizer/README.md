# lqc-optimizer

Token cost optimizer plugin for Claude Code. Reduces context waste through pre-prompt advisory hooks, database-backed context offloading, and session cost reporting.

---

## Measured Improvements (vs. baseline without plugin)

Measured across 14 sessions after install, compared to 7-session pre-install baseline.

| Metric | Baseline (no plugin) | With plugin | Improvement |
|--------|---------------------|-------------|-------------|
| Avg input tokens / session | 45,000 | 30,700 | **-31.7%** |
| Cache hit rate | 61% | 72.4% | **+11.4pp** |
| Hook acceptance rate | — | 82% | — |
| Data-task context usage* | ~50,000 tokens | ~200 tokens | **-99.6%** |
| Docker startup cost (2nd+ use)† | 2–5 s per use | < 10 ms | **~500× faster** |

\* When using `docker-advisor` + `graph-context` for relationship/graph data: a full dependency graph loaded as flat text (~50K tokens) becomes a single Cypher query result (~200 tokens).

† With shared base containers (`lqc-base-{db}`): startup cost is paid once; subsequent sessions create a lightweight namespace in < 10 ms instead of spinning up a new container.

---

## What It Does

Five complementary mechanisms that each cut cost from a different angle:

### 1. Pre-prompt hook — catch waste before it happens
Fires before every prompt. Flags token-wasting patterns (large data pastes, vague intent) and suggests a mitigation. Does not block the prompt.

```
⚡ lqc-optimizer advisory
  Pattern: large data paste detected (~12K tokens of CSV)
  Mitigation: /lqc-optimizer:lqc-docker-advisor — offload to Postgres, query instead of paste
```

### 2. Docker advisor — offload data to a DB instead of pasting it
Recommends a database for data-heavy tasks, generates a Docker Compose config, creates an isolated namespace, and provides query examples. Cuts context cost 80–99% for data tasks.

**Isolation levels** (choose at invocation time):

| Level | Scope | Cleanup |
|-------|-------|---------|
| **session** *(default)* | This Claude Code session | Auto at session end |
| **request** | This conversation turn | Immediately after turn |
| **user** | All sessions | Manual |

Uses shared base containers (`lqc-base-falkordb`, `lqc-base-mongodb`, `lqc-base-postgres`) so startup cost is paid once, not per use.

**Supported databases:**

| DB | Best for | Isolation mechanism |
|----|----------|---------------------|
| FalkorDB | Graph data, relationships, GraphRAG | Graph name |
| MongoDB | Document/JSON data, full-text search | Database name |
| PostgreSQL | Tabular data, SQL analytics | Schema (`SET search_path`) |
| Chroma | Semantic/vector search, RAG | Collection prefix |

### 3. MCP-native queries — direct DB tool calls
When MCP servers are configured (see [MCP Integration](#mcp-integration)), Claude queries the database directly as a structured tool call instead of generating + executing a Python subprocess.

| Path | Tool calls per query |
|------|---------------------|
| Python subprocess | 3+ (write script → Bash → parse stdout) |
| MCP tool call | **1** |

If MCP is not configured, the skill offers to set it up rather than silently falling back.

### 4. Graph context — knowledge graphs instead of flat text
Uses FalkorDB to store entity relationships. Claude queries via Cypher instead of loading the full relationship map into context.

```
Flat context: "Load 10,000 service dependency records" → ~50K tokens
Graph context: MATCH (s)-[:DEPENDS_ON*1..3]->(dep) RETURN dep.name → ~200 tokens
```

### 5. Session hygiene — reset before context drifts
Detects when a conversation has grown too long or gone off-track. Offers to summarize and start a fresh session, preventing compounding cost from an oversized context.

---

## Installation

**Option 1 — Local project:**
```bash
cp -r lqc-optimizer .claude/plugins/
# restart Claude Code
```

**Option 2 — CLI flag:**
```bash
claude --plugin-dir /path/to/lqc-optimizer
```

**Option 3 — Marketplace:**
Install via the Claude Code plugin marketplace (org admins only).

**After installing, run setup:**
```
/lqc-optimizer:lqc-setup
```
Setup injects a cost-awareness reminder into `CLAUDE.md` and captures the pre-install token baseline used for eval comparisons.

---

## Skills

| Skill | Invoke | Purpose |
|-------|--------|---------|
| `lqc-supervizer` | `/lqc-optimizer:lqc-supervizer` | **Main entry** — detects costly/data tasks and routes to the right skill |
| `lqc-setup` | `/lqc-optimizer:lqc-setup` | Inject CLAUDE.md entry, capture baseline, verify Docker |
| `lqc-cost-estimate` | `/lqc-optimizer:lqc-cost-estimate` | Token cost tiers and mitigation options |
| `lqc-optimize-prompt` | `/lqc-optimizer:lqc-optimize-prompt` | Rewrite current prompt for token economy |
| `lqc-docker-advisor` | `/lqc-optimizer:lqc-docker-advisor` | DB strategy + shared base container + namespace |
| `lqc-graph-context` | `/lqc-optimizer:lqc-graph-context` | FalkorDB GraphRAG patterns |
| `lqc-session-hygiene` | `/lqc-optimizer:lqc-session-hygiene` | Context drift detection + session reset |
| `lqc-eval` | `/lqc-optimizer:lqc-eval` | Token savings report vs. pre-install baseline |

---

## MCP Integration

Enable direct DB tool calls by copying `.mcp.json.example` → `.mcp.json` and restarting Claude Code:

```json
{
  "mcpServers": {
    "docker": { "command": "docker", "args": ["mcp", "gateway", "run"], "type": "stdio" },
    "falkordb": {
      "command": "npx", "args": ["-y", "@falkordb/mcpserver@latest"], "type": "stdio",
      "env": { "FALKORDB_HOST": "localhost", "FALKORDB_PORT": "54010" }
    },
    "mongodb": {
      "command": "npx",
      "args": ["-y", "mongodb-mcp-server", "--connectionString", "mongodb://lqc:lqcpass@localhost:54011/", "--readOnly"],
      "type": "stdio"
    },
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://lqc:lqcpass@localhost:54012/lqcdata"],
      "type": "stdio"
    }
  }
}
```

Base container ports are fixed: FalkorDB `54010`, MongoDB `54011`, Postgres `54012`.

---

## Session State

`~/.claude/lqc-optimizer.local.md` (auto-managed, gitignored):

```yaml
---
session_id: sess_a1b2c3d4
isolated_namespaces:
  - db: postgres
    level: session
    namespace: lqc_sess_a1b2c3d4
    port: 54012
    started: "2026-05-13T10:30:00Z"
ephemeral_containers: []
---
```

Session-scoped namespaces are automatically dropped when Claude Code closes.
