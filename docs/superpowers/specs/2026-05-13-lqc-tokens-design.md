# lqc-tokens Plugin Design
**Date:** 2026-05-13  
**Status:** Approved  
**Author:** bnaya@liquidity.com

---

## 1. Problem Statement

Claude Code sessions accumulate token costs silently. Users develop bad prompt habits (large pastes without context, vague requests, loading raw file data when a query would do), and there is no feedback loop to correct this. The `lqc-tokens` plugin closes this loop by:

1. Predicting cost before each response and advising on mitigation
2. Detecting bad prompt habits and suggesting leaner alternatives
3. Recommending database-backed context management for data-heavy tasks
4. Teaching graph-based context optimization with FalkorDB
5. Reporting session cost after each response
6. Suggesting session hygiene when context drifts

---

## 2. Plugin Identity

| Field | Value |
|-------|-------|
| Plugin name | `lqc-tokens` |
| Version | `0.1.0` |
| Description | Token cost optimizer: pre-prompt advice, Docker DB advisor, session reporting |

---

## 3. Component Inventory

### Hooks (3)

| Hook event | File | Purpose |
|------------|------|---------|
| `UserPromptSubmit` | `hooks/pre-prompt.md` | Single-pass pre-prompt analysis: cost estimate, anti-pattern detection, data-task detection, context drift check |
| `Stop` | `hooks/post-response.md` | Append session-report link (or token estimate fallback) after each response |
| `SessionEnd` | `hooks/session-end.sh` | Tear down ephemeral Docker containers tracked in `.claude/lqc-tokens.local.md` |

### Skills (6)

| Skill | Trigger | Purpose |
|-------|---------|---------|
| `cost-estimate` | Called from pre-prompt hook; invokable manually | Knowledge base: token cost tiers, mitigation menu |
| `optimize-prompt` | Called from pre-prompt hook when anti-patterns detected; invokable as `/lqc-tokens:optimize-prompt` | Rewrite prompts for token economy |
| `docker-advisor` | Called from pre-prompt hook when data task detected; invokable as `/lqc-tokens:docker-advisor` | LLM-driven DB selection + Docker compose/MCP spin-up |
| `graph-context` | Invokable as `/lqc-tokens:graph-context` | FalkorDB GraphRAG: when to use it, schema design, Cypher patterns |
| `session-hygiene` | Called from pre-prompt hook when context drift detected; invokable as `/lqc-tokens:session-hygiene` | Detect topic drift, suggest new session + context summary |
| `setup` | Invokable as `/lqc-tokens:setup` | Inject lqc-tokens entry into CLAUDE.md; verify Docker; configure MCP |

### MCP (optional)

| Server | Type | Purpose |
|--------|------|---------|
| `docker` | stdio | Docker MCP gateway — enables docker-advisor to actually spin up containers vs. only generating compose files |

---

## 4. Architecture

### 4.1 Pre-prompt hook flow

```
User submits prompt
        │
        ▼
[UserPromptSubmit: hooks/pre-prompt.md]
        │
        ├─ 1. Token estimate
        │     chars(prompt) / 4 ≈ tokens
        │     + heuristic for conversation history length
        │     → LOW (<20K) / MEDIUM (20K–80K) / HIGH (>80K)
        │
        ├─ 2. Anti-pattern scan
        │     • Paste >2KB without framing question → suggest optimize-prompt
        │     • Vague intent ("fix this", "help me") → suggest clarifying prompt
        │     • Redundant re-explanation of prior context → suggest trimming
        │     • Raw file contents that could be queried → suggest docker-advisor
        │
        ├─ 3. Data-task detection
        │     • File paths, bulk data, web scraping intent, "analyze this dataset"
        │     → invoke docker-advisor reasoning inline
        │
        ├─ 4. Context drift detection
        │     • Prompt 10+ in session AND topic appears unrelated to recent 3-5 turns
        │     → invoke session-hygiene reasoning inline
        │
        └─ 5. Output: advisory block (2-4 lines max)
              If LOW and no issues: silent (no output)
              If MEDIUM/HIGH or issues found: show advisory + action suggestions
              Does NOT block prompt — informational only
```

### 4.2 Post-response hook

```
Claude response ends
        │
        ▼
[Stop: hooks/post-response.md]
        │
        ├─ If session-report plugin is installed:
        │     → Append: "📊 Token cost: run `/session-report` for full breakdown"
        │
        └─ If session-report not installed:
              → Append: "📊 Estimated session tokens: ~{N}K"
```

### 4.3 SessionEnd hook

```
Session ends
        │
        ▼
[SessionEnd: hooks/session-end.sh]
        │
        ├─ Read .claude/lqc-tokens.local.md
        ├─ Parse ephemeral container names
        └─ docker stop && docker rm each container
```

---

## 5. Skill Specifications

### 5.1 `cost-estimate`

Knowledge skill. Explains:
- How to estimate context tokens from character count
- What LOW / MEDIUM / HIGH means in cost terms
- Full mitigation menu:
  1. Start a new session (free — resets context)
  2. Use `docker-advisor` to move data out of context
  3. Use `optimize-prompt` to compress the prompt
  4. Use `session-hygiene` to summarize and reset
  5. Use `graph-context` for relationship-heavy data

### 5.2 `optimize-prompt`

Takes the user's current prompt and:
1. Identifies waste: redundancy, vague intent, excessive context re-statement
2. Rewrites using token economy principles: tight intent statement, minimal necessary context, reference-by-path not paste
3. Presents: original (token count) vs. optimized (token count) + explanation of changes

### 5.3 `docker-advisor`

The most complex skill. Process:

1. **Analyze task**: Claude reads the prompt/spec and identifies:
   - Data shape (graph, tabular, document, vector/semantic)
   - Access patterns (lookup by ID, full-text search, relationship traversal, semantic similarity)
   - Query intent (what questions will be asked of this data)
   - Session longevity (ephemeral vs. persistent)

2. **Recommend DB(s)** (LLM-driven, 1-2 DBs):
   - FalkorDB → graph/relationship data, GraphRAG, multi-hop queries
   - MongoDB + Lucene → document store, full-text search
   - PostgreSQL → relational, joins, structured queries
   - Vector DB (e.g., Chroma) → semantic search, embeddings
   - Combinations possible (e.g., FalkorDB + Postgres)

3. **Fetch docs via Context7**: Use Context7 MCP (if available) to fetch current documentation for the recommended DB(s)

4. **Generate artifacts**:
   - `docker-compose.yml` snippet for recommended stack
   - Data-loading script stub (Python or shell)
   - Connection string template for Claude to use in subsequent prompts

5. **Ask persistence question**:
   > "Is this data needed for future sessions beyond today?"
   - **Yes → persistent**: named container (`lqc-<project>-<db>`), fixed port in range 54000–54999 (to avoid collision with common dev ports)
   - **No → ephemeral**: random name (`lqc-<uuid>`), random port; write to `.claude/lqc-tokens.local.md` for SessionEnd cleanup

6. **MCP escalation** (if Docker MCP is available):
   - Run `docker compose up` via MCP tools
   - Verify container health
   - Return live connection string ready for use

### 5.4 `graph-context`

FalkorDB / GraphRAG skill. Covers:

- **When to use graph context** over flat context:
  - Entity relationships that require multi-hop reasoning
  - Knowledge bases with interconnected concepts
  - RAG scenarios where retrieved chunks lack relationship context
  - Data science with graph metrics (centrality, shortest path, community detection)

- **Schema design for Claude**: how to design nodes and edges so Claude can write effective Cypher queries

- **Loading patterns**: ingesting structured data (CSV, JSON) into FalkorDB via Redis-style commands or Python client

- **Query patterns**: example Cypher queries for common Claude tasks (entity lookup, relationship traversal, subgraph extraction)

- **Context delivery**: how to pass FalkorDB query results back to Claude as context (summarized, not raw)

References:
- FalkorDB blog: GraphRAG vs VectorRAG
- FalkorDB graph database guide

### 5.5 `session-hygiene`

Detects and acts on context drift:

1. **Detection heuristics**:
   - Session has 10+ turns
   - Current prompt mentions a different project, technology, or task than what has been discussed in the last 5 turns (as judged by Claude reading the conversation)
   - Total estimated context is HIGH

2. **Action options presented to user**:
   - **Summarize + reset**: Claude writes a context summary to `docs/session-context-YYYY-MM-DD.md`, then instructs user to start new session with `--context docs/session-context-*.md`
   - **Continue anyway**: user overrides, no action taken
   - **Split work**: identify which parts of current prompt are new work vs. context, suggest completing current work in this session and starting fresh for the rest

### 5.6 `setup`

Installation skill invoked via `/lqc-tokens:setup`:

1. Find or create `CLAUDE.md` in project root
2. Check if lqc-tokens entry already present (idempotent)
3. Append the following block if not present:

```markdown
## Token Cost Optimization (lqc-tokens plugin)

- Consider using this plugin proactively, especially when context is growing large or the task involves large datasets.
- When a prompt is predicted to be medium or high cost, consult the `cost-estimate` skill for mitigation options.
- For data-heavy tasks (files, bulk analysis, web data), invoke the `docker-advisor` skill to suggest a database strategy.
- For relationship-heavy or knowledge-graph tasks, invoke the `graph-context` skill.
- When session context drifts or grows stale, invoke the `session-hygiene` skill.
```

4. Run `docker --version` to verify Docker is available
5. Ask if user wants to configure Docker MCP server — if yes, add entry to `.mcp.json`

---

## 6. Settings File

**`.claude/lqc-tokens.local.md`** (gitignored):

```yaml
---
ephemeral_containers:
  - name: lqc-abc123-falkordb
    port: 53421
    started: "2026-05-13T10:30:00Z"
  - name: lqc-def456-postgres
    port: 53422
    started: "2026-05-13T10:30:00Z"
---
```

Used by `SessionEnd` hook to clean up containers. Written by `docker-advisor` when ephemeral containers are created.

---

## 7. MCP Configuration

**`.mcp.json`** (optional, installed by `setup` skill on request):

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

The `docker-advisor` skill gracefully degrades if this is not configured: it generates compose files and instructions instead of spinning up containers directly.

**Context7** (separate MCP server): The `docker-advisor` and `graph-context` skills use Context7 MCP tools (if available) to fetch current DB documentation. Both skills work without Context7 by using built-in knowledge — they just won't have the latest API docs.

---

## 8. Directory Structure

```
lqc-tokens/
├── plugin.json
├── README.md
├── .gitignore                          # .claude/*.local.md
├── .mcp.json.example                   # Docker MCP config template
├── hooks/
│   ├── hooks.json                      # Hook event registrations
│   ├── pre-prompt.md                   # UserPromptSubmit prompt-based hook
│   ├── post-response.md                # Stop prompt-based hook
│   └── session-end.sh                  # SessionEnd shell hook
├── skills/
│   ├── cost-estimate/
│   │   └── SKILL.md
│   ├── optimize-prompt/
│   │   └── SKILL.md
│   ├── docker-advisor/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   │   ├── db-selection-guide.md   # DB choice criteria
│   │   │   └── docker-compose-templates/ # Template compose files per DB
│   │   └── examples/
│   │       └── example-session.md      # Worked example
│   ├── graph-context/
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── falkordb-patterns.md    # Schema + Cypher patterns
│   ├── session-hygiene/
│   │   └── SKILL.md
│   └── setup/
│       └── SKILL.md
```

---

## 9. Security Considerations

- Only official, trusted plugin dependencies: `session-report` (optional), `docker` MCP (optional), Context7 (optional)
- No hardcoded credentials anywhere
- `.claude/lqc-tokens.local.md` is gitignored — contains ephemeral container metadata only, no secrets
- Docker containers use ephemeral/named port ranges to avoid collision; no host networking
- Pre-prompt hook is advisory only — does not intercept, store, or transmit prompt content

---

## 10. Out of Scope (v1)

- Automatic prompt rewriting without user confirmation
- Cost billing integration (no API key management)
- Multi-model cost comparison
- CI/CD pipeline integration
- Shared team session reports
