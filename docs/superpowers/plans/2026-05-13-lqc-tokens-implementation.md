# lqc-tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Plugin tooling note:** Use `/plugin-dev:create-plugin` to scaffold the plugin structure in Task 1. Use `/skill-creator` to review and refine each SKILL.md after it is drafted (Tasks 6–12).

**Goal:** Build the `lqc-tokens` Claude Code plugin — a token cost optimizer that warns before expensive prompts, rewrites bad habits, advises on Docker-backed context offloading, and reports session cost after each response.

**Architecture:** Three prompt/command hooks intercept each prompt and session lifecycle. Six skills contain the reasoning logic and are invoked by hooks or directly by the user. An eval skill measures token savings over time against a captured baseline.

**Tech Stack:** Claude Code plugin system (hooks.json, SKILL.md), Bash (SessionEnd hook, eval log), Python 3 (baseline capture, log append), Docker CLI (container management), optional Docker MCP gateway, optional Context7 MCP (DB docs), optional session-report plugin.

---

## Task 1: Plugin Scaffold

**Files:**
- Create: `lqc-tokens/plugin.json`
- Create: `lqc-tokens/CHANGELOG.md`
- Create: `lqc-tokens/README.md`
- Create: `lqc-tokens/.gitignore`
- Create: `lqc-tokens/hooks/` (empty dir placeholder)
- Create: `lqc-tokens/skills/` (empty dir placeholder)

- [ ] **Step 1: Create directory structure**

```bash
cd /Users/bnaya/Documents/Code/LQ/lqc-ai-plugins
mkdir -p lqc-tokens/hooks
mkdir -p lqc-tokens/skills/cost-estimate
mkdir -p lqc-tokens/skills/optimize-prompt
mkdir -p lqc-tokens/skills/docker-advisor/references/docker-compose-templates
mkdir -p lqc-tokens/skills/docker-advisor/examples
mkdir -p lqc-tokens/skills/graph-context/references
mkdir -p lqc-tokens/skills/session-hygiene
mkdir -p lqc-tokens/skills/setup
mkdir -p lqc-tokens/skills/eval
```

- [ ] **Step 2: Write plugin.json**

```json
{
  "name": "lqc-tokens",
  "version": "0.1.0",
  "description": "Token cost optimizer: pre-prompt advisory, Docker DB advisor, GraphRAG context, session reporting.",
  "author": {
    "name": "Liquidity",
    "email": "bnaya@liquidity.com"
  }
}
```
Save to `lqc-tokens/plugin.json`.

- [ ] **Step 3: Write CHANGELOG.md**

```markdown
# Changelog

## 0.1.0 — 2026-05-13

### Added
- UserPromptSubmit hook: pre-prompt cost estimate + anti-pattern advisory
- Stop hook: post-response session-report link
- SessionEnd hook: ephemeral Docker container cleanup
- Skill: cost-estimate — token cost tiers and mitigation menu
- Skill: optimize-prompt — prompt rewriting for token economy
- Skill: docker-advisor — LLM-driven DB selection + Docker compose generation
- Skill: graph-context — FalkorDB GraphRAG patterns and schema design
- Skill: session-hygiene — context drift detection and session reset guidance
- Skill: setup — CLAUDE.md injection + Docker MCP configuration
- Skill: eval — token savings measurement vs. baseline
```
Save to `lqc-tokens/CHANGELOG.md`.

- [ ] **Step 4: Write .gitignore**

```
.claude/*.local.md
.mcp.json
```
Save to `lqc-tokens/.gitignore`.

- [ ] **Step 5: Write README.md**

```markdown
# lqc-tokens

Token cost optimizer plugin for Claude Code. Reduces context waste through pre-prompt advisory hooks, database-backed context offloading, and session cost reporting.

## Installation

Copy this directory to your project's `.claude-plugin/` or install via the Claude Code plugin marketplace.

Run setup after installing:
```
/lqc-tokens:setup
```

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
```
Save to `lqc-tokens/README.md`.

- [ ] **Step 6: Write .mcp.json.example**

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
Save to `lqc-tokens/.mcp.json.example`.

- [ ] **Step 7: Verify structure**

```bash
find lqc-tokens -not -path '*/.git/*' | sort
```

Expected output includes: `lqc-tokens/plugin.json`, `lqc-tokens/CHANGELOG.md`, `lqc-tokens/README.md`, `lqc-tokens/.gitignore`, `lqc-tokens/.mcp.json.example`, all skill dirs and hooks dir.

- [ ] **Step 8: Commit**

```bash
git add lqc-tokens/
git commit -m "feat: scaffold lqc-tokens plugin structure"
```

---

## Task 2: Hook Registration (hooks.json)

**Files:**
- Create: `lqc-tokens/hooks/hooks.json`

- [ ] **Step 1: Write hooks.json**

The `UserPromptSubmit` and `Stop` hooks use `type: "prompt"` with an inline `prompt` string. Because the prompt content is long, generate the JSON using a script that reads the .md files:

```bash
python3 - <<'EOF'
import json

pre = open('lqc-tokens/hooks/pre-prompt.md').read().strip()
post = open('lqc-tokens/hooks/post-response.md').read().strip()

hooks = {
  "description": "lqc-tokens: pre-prompt cost advisory, post-response session link, ephemeral container cleanup",
  "hooks": {
    "UserPromptSubmit": [{"matcher": "*", "hooks": [{"type": "prompt", "prompt": pre}]}],
    "Stop": [{"matcher": "*", "hooks": [{"type": "prompt", "prompt": post}]}],
    "SessionEnd": [{"matcher": "*", "hooks": [{"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-end.sh\""}]}]
  }
}

with open('lqc-tokens/hooks/hooks.json', 'w') as f:
    json.dump(hooks, f, indent=2)
print("hooks.json written")
EOF
```

**Important:** Run this script AFTER Task 3 and Task 4 (pre-prompt.md and post-response.md must exist first). If running tasks out of order, write hooks.json with placeholder prompt strings and re-run this script after the .md files are written.

- [ ] **Step 2: Validate JSON**

```bash
python3 -c "import json; json.load(open('lqc-tokens/hooks/hooks.json')); print('hooks.json valid')"
```

Expected: `hooks.json valid`

- [ ] **Step 3: Commit**

```bash
git add lqc-tokens/hooks/hooks.json
git commit -m "feat: register UserPromptSubmit, Stop, SessionEnd hooks"
```

---

## Task 3: Pre-Prompt Hook (UserPromptSubmit)

**Files:**
- Create: `lqc-tokens/hooks/pre-prompt.md`

- [ ] **Step 1: Write pre-prompt.md**

```markdown
You are the lqc-tokens pre-prompt advisor. Before Claude processes the user's prompt, run ALL of the following checks and produce a single advisory block if any check triggers. If no check triggers, output nothing (stay silent).

## Check 1: Token estimate

Estimate the current prompt's token cost using this heuristic:
- Count characters in the user's current message
- Divide by 4 to approximate tokens
- Add 2000 tokens per prior conversation turn as a rough history estimate

Classify:
- LOW: < 20,000 tokens → silent (no output for this check alone)
- MEDIUM: 20,000–80,000 tokens → flag
- HIGH: > 80,000 tokens → flag with urgency

## Check 2: Anti-pattern scan

Flag if ANY of the following are true:
- The prompt contains a raw paste > 2,000 characters without a framing question (e.g. "here is the file:" followed by raw content)
- The prompt says only "fix this", "help me", "improve this", or similar with no specific intent
- The prompt re-explains context already established in recent turns (redundant recap)
- The prompt contains raw file contents that could instead be accessed via a file path

## Check 3: Data-task detection

Flag if the prompt contains ANY of these patterns:
- "read the following document", "here is the file", "I'm pasting the contents of", "analyze this report"
- "refer to this CSV", "refer to this Excel", "here is the data export", "loaded from a database", "exported from", "here are the records"
- "I scraped", "downloaded this from", "here is the webpage content", "fetch and analyze this site"
- "go through all the files in", "process every record in", "for each item in this list", "scan the entire codebase for"

## Check 4: Context drift

Flag if BOTH are true:
- This appears to be turn 10 or later in the session (infer from conversation length)
- The current prompt mentions a different project, technology, or task than what has been discussed in the last 5 turns

## Advisory output format

If one or more checks triggered, output ONLY this block (no other text before or after):

```
⚡ lqc-tokens advisory
──────────────────────────────────────────────
[List each triggered check as one line, e.g.:]
• HIGH token cost predicted (~95K tokens) — consider /lqc-tokens:cost-estimate for mitigation
• Large paste detected — /lqc-tokens:optimize-prompt can reduce this by referencing paths instead
• Data-heavy task detected — /lqc-tokens:docker-advisor can offload this data to a DB
• Context drift — /lqc-tokens:session-hygiene to summarize + reset
──────────────────────────────────────────────
```

If no checks triggered: output nothing. Do not explain that you ran checks.
```
Save to `lqc-tokens/hooks/pre-prompt.md`.

- [ ] **Step 2: Manual smoke test**

Start a Claude Code session with the plugin loaded. Submit this prompt:
```
read the following document and summarize it: [paste 3KB of Lorem ipsum]
```
Expected: advisory block fires with "Large paste detected" and "Data-heavy task detected".

Submit a short prompt like "what time is it?".
Expected: no advisory output.

- [ ] **Step 3: Commit**

```bash
git add lqc-tokens/hooks/pre-prompt.md
git commit -m "feat: add UserPromptSubmit pre-prompt advisory hook"
```

---

## Task 4: Post-Response Hook (Stop)

**Files:**
- Create: `lqc-tokens/hooks/post-response.md`

- [ ] **Step 1: Write post-response.md**

```markdown
You are the lqc-tokens post-response reporter. After every Claude response, append exactly one line to the response output.

Determine which case applies:

**Case A — session-report plugin is available:**
The session-report plugin is available if the skill `session-report` is listed in the active skills. In this case append:

```
📊 Session cost: run `/session-report` for full token breakdown
```

**Case B — session-report plugin is NOT available:**
Estimate total session tokens: sum the character count of all messages in the conversation so far, divide by 4. Append:

```
📊 Estimated session tokens: ~{N}K (install session-report plugin for exact breakdown)
```

Where `{N}` is the estimate rounded to the nearest thousand, expressed as an integer (e.g. `~42K`).

Output ONLY the one appended line. Do not add any other commentary.
```
Save to `lqc-tokens/hooks/post-response.md`.

- [ ] **Step 2: Manual smoke test**

With plugin loaded, send any prompt. Verify the last line of every response is the 📊 cost line.

- [ ] **Step 3: Commit**

```bash
git add lqc-tokens/hooks/post-response.md
git commit -m "feat: add Stop hook for post-response session cost link"
```

---

## Task 5: SessionEnd Hook + Settings Schema

**Files:**
- Create: `lqc-tokens/hooks/session-end.sh`

- [ ] **Step 1: Write session-end.sh**

```bash
#!/usr/bin/env bash
# Tears down ephemeral Docker containers tracked in .claude/lqc-tokens.local.md

SETTINGS_FILE="${CLAUDE_WORKSPACE_DIR:-$HOME}/.claude/lqc-tokens.local.md"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  exit 0
fi

# Extract container names from YAML frontmatter lines like:
#   - name: lqc-abc123-falkordb
CONTAINERS=$(grep -E '^\s*- name:\s*lqc-' "$SETTINGS_FILE" | sed 's/.*name:\s*//')

if [[ -z "$CONTAINERS" ]]; then
  exit 0
fi

for CONTAINER in $CONTAINERS; do
  if docker inspect "$CONTAINER" &>/dev/null; then
    echo "lqc-tokens: stopping ephemeral container $CONTAINER"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
  fi
done

# Clear the ephemeral container list from the settings file
# Keep the file but reset the ephemeral_containers list
python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Replace ephemeral_containers block with empty list
content = re.sub(
    r'(ephemeral_containers:\s*\n)((?:\s+- .*\n)*)',
    r'\1',
    content
)

with open(path, 'w') as f:
    f.write(content)
PYEOF
```
Save to `lqc-tokens/hooks/session-end.sh`.

- [ ] **Step 2: Make executable**

```bash
chmod +x lqc-tokens/hooks/session-end.sh
```

- [ ] **Step 3: Write settings file template (as documentation)**

Create `lqc-tokens/skills/setup/lqc-tokens.local.md.example`:
```markdown
---
ephemeral_containers:
  - name: lqc-abc123-falkordb
    port: 6380
    started: "2026-05-13T10:30:00Z"
  - name: lqc-def456-postgres
    port: 54001
    started: "2026-05-13T10:30:00Z"
---

Managed by lqc-tokens plugin. Do not edit manually.
```

- [ ] **Step 4: Validate shell script syntax**

```bash
bash -n lqc-tokens/hooks/session-end.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 5: Commit**

```bash
git add lqc-tokens/hooks/session-end.sh lqc-tokens/skills/setup/lqc-tokens.local.md.example
git commit -m "feat: add SessionEnd hook for ephemeral Docker container cleanup"
```

---

## Task 6: Skill — cost-estimate

**Files:**
- Create: `lqc-tokens/skills/cost-estimate/SKILL.md`

> After writing, invoke `/skill-creator` to review and refine the trigger description.

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: cost-estimate
description: Explains Claude Code token cost tiers and the full mitigation menu. Use when a prompt is predicted to be medium or high cost, when the user asks "how much will this cost", "why is my context so large", or when the pre-prompt hook flags a cost warning. Also load when advising on reducing session token spend.
argument-hint: "[optional: describe the task you're trying to do]"
allowed-tools: Read
---

# Token Cost Estimation and Mitigation

## Cost Tiers

Estimate tokens by dividing total characters in the conversation by 4.

| Tier | Estimated tokens | Impact |
|------|-----------------|--------|
| LOW | < 20K | Minimal cost, no action needed |
| MEDIUM | 20K–80K | Noticeable cost; consider mitigations |
| HIGH | 80K–200K | Significant cost; mitigation recommended |
| CRITICAL | > 200K | Very high cost; strong action recommended |

## Mitigation Menu

Present these options to the user in order of ease:

### 1. Start a new session (free)
Resets context to zero. Best when the current task is complete and the next prompt is unrelated. Summarize work-in-progress to a file first if needed.

### 2. Compress the current prompt (`/lqc-tokens:optimize-prompt`)
Rewrites the prompt to remove redundancy, tighten intent, and replace large pastes with file path references. Typical savings: 30–60% of prompt token count.

### 3. Offload data to a database (`/lqc-tokens:docker-advisor`)
For data-heavy tasks: instead of loading raw data into context, spin up a database, load the data once, and query it. Typical savings: 80–95% for data analysis tasks.

### 4. Use graph context for relationship data (`/lqc-tokens:graph-context`)
For tasks involving entities, relationships, or knowledge graphs: FalkorDB lets Claude query relationships rather than hold the entire graph in context.

### 5. Reset session with a context summary (`/lqc-tokens:session-hygiene`)
Summarizes the current session to a file, then starts fresh pointing at the summary. Best for long sessions with topic drift.

## Reading the session-report

If `session-report` is installed, run `/session-report` to see:
- Per-session token totals
- Cache hit rate (target: > 85%)
- Most expensive prompts
- Subagent token breakdown

A cache hit rate below 85% means you're paying for repeated context. Increasing prompt stability (fewer rewrites, consistent framing) improves cache efficiency.
```

- [ ] **Step 2: Verify YAML frontmatter is valid**

```bash
python3 -c "
import re, sys
content = open('lqc-tokens/skills/cost-estimate/SKILL.md').read()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
print('frontmatter OK' if match else 'ERROR: no frontmatter')
"
```

Expected: `frontmatter OK`

- [ ] **Step 3: Commit**

```bash
git add lqc-tokens/skills/cost-estimate/SKILL.md
git commit -m "feat: add cost-estimate skill"
```

---

## Task 7: Skill — optimize-prompt

**Files:**
- Create: `lqc-tokens/skills/optimize-prompt/SKILL.md`

> After writing, invoke `/skill-creator` to review and refine the trigger description.

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: optimize-prompt
description: Rewrites the user's current prompt for token economy. Use when the user asks to "optimize my prompt", "make this prompt cheaper", "reduce tokens", or when the pre-prompt hook detects anti-patterns (large paste without framing, vague intent, redundant re-explanation). Also use before any prompt predicted to be MEDIUM or HIGH cost.
argument-hint: "[paste the prompt you want to optimize, or leave blank to use the current prompt]"
allowed-tools: Read
---

# Prompt Optimization for Token Economy

## Process

1. **Read the prompt** (from argument or current conversation context)
2. **Count approximate tokens**: `len(prompt) / 4`
3. **Identify waste** using the anti-pattern checklist below
4. **Rewrite** applying the optimization rules
5. **Present** original vs. optimized with token counts and explanation

## Anti-Pattern Checklist

Check each and flag if present:

| Anti-pattern | Example | Fix |
|---|---|---|
| Raw large paste | "Here is the file: [3KB of code]" | Replace with file path reference |
| Vague intent | "Fix this" / "Help me" | Add specific outcome: "Fix the null pointer exception in `auth.py:42`" |
| Redundant recap | "As I mentioned earlier, we're building X..." | Cut — prior context is already in the conversation |
| Full file contents | Pasting entire file to ask about one function | Reference: "In `src/auth.py`, the `login()` function..." |
| Asking for everything | "Tell me everything about X" | Scope: "Explain only how X handles Y" |
| Multi-question prompt | 5 questions in one message | Split into separate prompts |

## Optimization Rules

- **Replace pastes with paths**: `See contents of /path/to/file.py` instead of pasting
- **Lead with the specific outcome**: "Return only the corrected function signature" not "look at this and tell me what you think"
- **Cut preamble**: Remove "I'm working on a project that..." unless it's genuinely new context
- **One question per prompt**: If multiple questions exist, pick the highest priority one
- **Use line numbers**: "The bug is at `auth.py:142`" is 80% cheaper than pasting the whole file

## Output Format

Present to the user as:

```
Original (~{N} tokens):
──────────────────────
{original prompt}

Optimized (~{M} tokens, {P}% reduction):
──────────────────────────────────────
{rewritten prompt}

Changes:
• {change 1}
• {change 2}
```

Ask the user: "Use the optimized version? (yes/no)"
```

- [ ] **Step 2: Validate frontmatter**

```bash
python3 -c "
import re
content = open('lqc-tokens/skills/optimize-prompt/SKILL.md').read()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
print('frontmatter OK' if match else 'ERROR: no frontmatter')
"
```

Expected: `frontmatter OK`

- [ ] **Step 3: Commit**

```bash
git add lqc-tokens/skills/optimize-prompt/SKILL.md
git commit -m "feat: add optimize-prompt skill"
```

---

## Task 8: Skill — docker-advisor + References

**Files:**
- Create: `lqc-tokens/skills/docker-advisor/SKILL.md`
- Create: `lqc-tokens/skills/docker-advisor/references/db-selection-guide.md`
- Create: `lqc-tokens/skills/docker-advisor/references/trigger-catalog.md`
- Create: `lqc-tokens/skills/docker-advisor/references/docker-compose-templates/falkordb.yml`
- Create: `lqc-tokens/skills/docker-advisor/references/docker-compose-templates/mongodb.yml`
- Create: `lqc-tokens/skills/docker-advisor/references/docker-compose-templates/postgres.yml`
- Create: `lqc-tokens/skills/docker-advisor/references/docker-compose-templates/chroma.yml`
- Create: `lqc-tokens/skills/docker-advisor/examples/example-session.md`

> After writing, invoke `/skill-creator` to review and refine the trigger description.

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: docker-advisor
description: Recommends a database strategy for data-heavy tasks and generates Docker setup. Use when the user wants to "load data into a database", "analyze a large dataset", refers to CSV or Excel files, pastes large data, says "read the following document", mentions scraping or downloading web data, needs to process many files, or when the pre-prompt hook detects a data-task pattern. Also use when the user asks which database to use for a given workload.
argument-hint: "[describe your data: shape, size, access patterns, session longevity]"
allowed-tools: Read, Write, Bash
---

# Docker Data Advisor

When a task involves loading, analyzing, or querying data that would otherwise fill the context window, offload it to a database running in Docker. This reduces context cost by 80–95% for data tasks.

## Process

### Step 1: Analyze the task

Read the user's prompt and identify:
- **Data shape**: graph/relational/document/vector/tabular
- **Access patterns**: lookup by ID? full-text search? relationship traversal? semantic similarity?
- **Query intent**: what questions will Claude ask of this data?
- **Data size**: how many rows/nodes/documents?
- **Longevity**: is this data needed after today's session?

### Step 2: Recommend a database

Use the selection guide at `references/db-selection-guide.md`. Recommend 1–2 databases maximum.

If Context7 MCP tools are available (`mcp__context7__*`), fetch the latest docs for the recommended DB before proceeding.

### Step 3: Ask about longevity

> "Is this data needed for future sessions beyond today?"

- **Yes → persistent container**:
  - Name: `lqc-{project-slug}-{db}` (e.g. `lqc-myapp-falkordb`)
  - Port: deterministic from range 54000–54999 (pick the lowest unused port in that range via `ss -tlnp | grep 540` or `lsof -i :540[0-9][0-9]`)
  - Container survives session end

- **No → ephemeral container**:
  - Name: `lqc-{8-char-uuid}` (generate with `python3 -c "import uuid; print(uuid.uuid4().hex[:8])"`)
  - Port: random high port (`shuf -i 40000-49999 -n 1`)
  - Write to `.claude/lqc-tokens.local.md` for SessionEnd cleanup

### Step 4: Generate artifacts

Copy the appropriate template from `references/docker-compose-templates/` and fill in:
- Container name
- Port mapping
- Volume name (for persistent) or anonymous volume (for ephemeral)

Write the composed file to the user's project root as `docker-compose.lqc.yml`.

Also provide a data-loading script stub (Python or shell, based on data source).

### Step 5: Start the container (if Docker MCP available)

If `mcp__docker__*` tools are in the tool list:
1. Run `docker compose -f docker-compose.lqc.yml up -d`
2. Wait for container health (retry up to 5 times with 2s delay)
3. Return the connection string

If Docker MCP is not available:
- Output the manual steps:
  ```bash
  docker compose -f docker-compose.lqc.yml up -d
  ```
- Tell the user to run this and then continue

### Step 6: Provide connection string and next steps

Tell Claude (and the user) the connection string and the schema to use for the task. Include a data-loading command the user can run.

## Ephemeral container tracking

After creating an ephemeral container, append to `.claude/lqc-tokens.local.md`:

```yaml
---
ephemeral_containers:
  - name: {container-name}
    port: {port}
    started: "{ISO-8601-timestamp}"
---
```

If the file doesn't exist, create it with this structure.
If it already exists, add the new entry to the `ephemeral_containers` list.
```

- [ ] **Step 2: Write db-selection-guide.md**

```markdown
# Database Selection Guide

## FalkorDB (Graph + Vector)

**Choose when:**
- Data has entities with relationships (people → companies, code → dependencies, concepts → concepts)
- Need multi-hop queries ("find all users connected to X within 2 hops")
- Building GraphRAG (retrieve by relationship, not just similarity)
- Need graph algorithms (centrality, community detection, shortest path)
- Want combined graph + vector search (FalkorDB supports both)

**Docker image:** `falkordb/falkordb:latest`
**Default port:** 6379 (Redis-compatible)
**Query language:** Cypher + FalkorDB extensions
**Client:** `pip install falkordb` or Redis client

## MongoDB + Lucene

**Choose when:**
- Data is document-shaped (JSON objects with variable fields)
- Need full-text search over document content
- Access pattern is "find documents matching text query"
- Schema-flexible: documents vary in shape

**Docker image:** `mongo:7`
**Default port:** 27017
**Query language:** MQL (MongoDB Query Language)
**Client:** `pip install pymongo`

## PostgreSQL

**Choose when:**
- Data is tabular with fixed schema (rows and columns)
- Need joins, aggregations, GROUP BY
- Data comes from CSV/Excel exports
- Access pattern is SQL-style relational queries

**Docker image:** `postgres:16-alpine`
**Default port:** 5432
**Query language:** SQL
**Client:** `pip install psycopg2-binary`

## Chroma (Vector / Semantic)

**Choose when:**
- Need semantic similarity search ("find documents similar to X")
- Working with embeddings
- RAG without relationship structure
- Text chunks that need nearest-neighbor retrieval

**Docker image:** `chromadb/chroma:latest`
**Default port:** 8000
**Client:** `pip install chromadb`

## Combination patterns

| Scenario | Recommendation |
|---|---|
| Knowledge graph + semantic search | FalkorDB (supports both natively) |
| Product catalog + text search | MongoDB |
| Financial data + analytics | PostgreSQL |
| Document RAG without relationships | Chroma |
| Code dependency analysis | FalkorDB |
```

- [ ] **Step 3: Write trigger-catalog.md**

```markdown
# Prompt Trigger Catalog

Patterns that indicate a data-heavy task requiring docker-advisor.

## Document / file ingestion
- "read the following document(s)"
- "here is the file" / "here are the files"
- "I'm attaching / I'm pasting the contents of"
- "analyze this report" / "review this document"
- "the following is the full text of"
- "read through all of these"

## Tabular / spreadsheet data
- "refer to this CSV" / "refer to this Excel" / "refer to this spreadsheet"
- "here is the data export"
- "I have a table with N rows"
- "the data looks like: [column headers]"
- "loaded from a database" / "pulled from BigQuery" / "exported from Salesforce"
- "here are the records"

## Web / scraped data
- "I scraped / downloaded this from"
- "here is the webpage content"
- "pull data from this URL"
- "fetch and analyze this site"
- "summarize the following web page"

## Bulk / multi-file
- "go through all the files in"
- "process every record in"
- "for each item in this list"
- "scan the entire codebase for"
- "read all logs from"

## Relationship / graph (→ also suggest graph-context)
- "map the relationships between"
- "find all connections from X to Y"
- "who is connected to / depends on"
- "trace the dependency chain"
- "build a knowledge graph of"
- "find paths between"
```

- [ ] **Step 4: Write docker-compose templates**

`references/docker-compose-templates/falkordb.yml`:
```yaml
services:
  falkordb:
    image: falkordb/falkordb:latest
    container_name: CONTAINER_NAME
    ports:
      - "HOST_PORT:6379"
    volumes:
      - VOLUME_NAME:/data
    restart: unless-stopped

volumes:
  VOLUME_NAME:
```

`references/docker-compose-templates/mongodb.yml`:
```yaml
services:
  mongodb:
    image: mongo:7
    container_name: CONTAINER_NAME
    ports:
      - "HOST_PORT:27017"
    volumes:
      - VOLUME_NAME:/data/db
    environment:
      MONGO_INITDB_ROOT_USERNAME: lqc
      MONGO_INITDB_ROOT_PASSWORD: lqcpass
    restart: unless-stopped

volumes:
  VOLUME_NAME:
```

`references/docker-compose-templates/postgres.yml`:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: CONTAINER_NAME
    ports:
      - "HOST_PORT:5432"
    volumes:
      - VOLUME_NAME:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: lqcdata
      POSTGRES_USER: lqc
      POSTGRES_PASSWORD: lqcpass
    restart: unless-stopped

volumes:
  VOLUME_NAME:
```

`references/docker-compose-templates/chroma.yml`:
```yaml
services:
  chroma:
    image: chromadb/chroma:latest
    container_name: CONTAINER_NAME
    ports:
      - "HOST_PORT:8000"
    volumes:
      - VOLUME_NAME:/chroma/chroma
    restart: unless-stopped

volumes:
  VOLUME_NAME:
```

- [ ] **Step 5: Write example session**

`examples/example-session.md`:
```markdown
# Example: Analyzing a CSV dataset with PostgreSQL

**User prompt:** "I have a sales CSV with 50,000 rows. I want to find total revenue by region and top 10 products."

## docker-advisor analysis

**Data shape:** tabular (CSV, fixed columns)
**Access patterns:** aggregation (SUM, GROUP BY), ranking (ORDER BY, LIMIT)
**Recommended DB:** PostgreSQL
**Longevity:** asked user → "just for today" → ephemeral

## Generated docker-compose.lqc.yml

```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: lqc-a1b2c3d4
    ports:
      - "47832:5432"
    volumes:
      - lqc-a1b2c3d4-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: lqcdata
      POSTGRES_USER: lqc
      POSTGRES_PASSWORD: lqcpass

volumes:
  lqc-a1b2c3d4-data:
```

## Data loading stub

```python
import pandas as pd
from sqlalchemy import create_engine

df = pd.read_csv('sales.csv')
engine = create_engine('postgresql://lqc:lqcpass@localhost:47832/lqcdata')
df.to_sql('sales', engine, if_exists='replace', index=False)
print(f"Loaded {len(df)} rows")
```

## Claude now queries instead of loading context

```sql
-- Revenue by region
SELECT region, SUM(revenue) AS total_revenue
FROM sales
GROUP BY region
ORDER BY total_revenue DESC;

-- Top 10 products
SELECT product, SUM(revenue) AS total_revenue
FROM sales
GROUP BY product
ORDER BY total_revenue DESC
LIMIT 10;
```

**Context cost:** ~500 tokens (query results) vs ~40,000 tokens (full CSV in context) = 98% reduction
```

- [ ] **Step 6: Validate all YAML files**

```bash
python3 -c "
import yaml, glob
for f in glob.glob('lqc-tokens/skills/docker-advisor/references/docker-compose-templates/*.yml'):
    yaml.safe_load(open(f))
    print(f'OK: {f}')
"
```

Expected: `OK:` for each of the 4 files.

- [ ] **Step 7: Commit**

```bash
git add lqc-tokens/skills/docker-advisor/
git commit -m "feat: add docker-advisor skill with DB selection guide and compose templates"
```

---

## Task 9: Skill — graph-context

**Files:**
- Create: `lqc-tokens/skills/graph-context/SKILL.md`
- Create: `lqc-tokens/skills/graph-context/references/falkordb-patterns.md`

> After writing, invoke `/skill-creator` to review and refine the trigger description.

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: graph-context
description: Guides using FalkorDB for GraphRAG context management. Use when the user asks about "graph database", "knowledge graph", "FalkorDB", "GraphRAG", "relationship analysis", "entity connections", "dependency mapping", or when the task involves entities with relationships that would require many context tokens to represent as flat text.
argument-hint: "[describe your entities and the relationships between them]"
allowed-tools: Read, Bash
---

# FalkorDB Graph Context Optimization

Use FalkorDB when your task involves entities with relationships. Instead of loading relationship data into context as flat text (expensive), load it into FalkorDB once and let Claude query it with Cypher (cheap).

## When graph context beats flat context

| Scenario | Flat context cost | Graph context cost |
|---|---|---|
| "Find all services that depend on auth-service" | Load entire dependency graph (~50K tokens) | One Cypher query (~200 tokens) |
| "Who are the top influencers in this network?" | Load full adjacency list | `MATCH (n) RETURN n ORDER BY n.pagerank DESC LIMIT 10` |
| "What concepts are related to X within 2 hops?" | Load full knowledge base | `MATCH (a {name:'X'})-[*..2]-(b) RETURN b.name` |

**Rule of thumb:** If the data has more than ~200 relationships, graph context is cheaper than flat context.

## Setup (if not done via docker-advisor)

```bash
docker run -d --name falkordb -p 6379:6379 falkordb/falkordb:latest
pip install falkordb
```

## Schema design for Claude

Design your schema so Claude can write queries without reading the data first.

**Good schema** (self-documenting node/edge names):
```cypher
CREATE (:Service {name: 'auth-service', language: 'go', team: 'platform'})
CREATE (:Service {name: 'api-gateway', language: 'node'})
CREATE (:Service {name: 'auth-service'})-[:DEPENDS_ON]->(:Service {name: 'postgres'})
```

**How to tell Claude the schema** (put this in the prompt, not the data):
```
FalkorDB graph is running at localhost:6379, graph name: 'services'.
Nodes: Service {name, language, team}, Database {name, type}
Edges: DEPENDS_ON, CALLS, OWNS
```

## Common Cypher patterns

See `references/falkordb-patterns.md` for the full pattern library. Key patterns:

```cypher
-- Find all nodes of a type
MATCH (n:Service) RETURN n.name, n.team

-- Find direct neighbors
MATCH (s:Service {name: $name})-[:DEPENDS_ON]->(dep) RETURN dep.name

-- Multi-hop traversal (up to 3 hops)
MATCH (s:Service {name: $name})-[:DEPENDS_ON*1..3]->(dep) RETURN DISTINCT dep.name

-- Find shortest path
MATCH p=shortestPath((a:Service {name: $from})-[*]->(b:Service {name: $to})) RETURN p

-- Count relationships
MATCH (s:Service)-[r:DEPENDS_ON]->() RETURN s.name, count(r) AS dep_count ORDER BY dep_count DESC
```

## Loading data into FalkorDB

```python
from falkordb import FalkorDB

db = FalkorDB(host='localhost', port=6379)
g = db.select_graph('myproject')

# Load from a list of dicts
for row in data:
    g.query(
        "MERGE (n:Entity {id: $id}) SET n.name = $name, n.type = $type",
        {'id': row['id'], 'name': row['name'], 'type': row['type']}
    )

# Load relationships
for edge in edges:
    g.query(
        "MATCH (a:Entity {id: $from}), (b:Entity {id: $to}) MERGE (a)-[:RELATES_TO]->(b)",
        {'from': edge['from'], 'to': edge['to']}
    )
```

## Passing query results to Claude

Run the query, format results as a compact table or list, and include only that in the prompt:

```python
result = g.query("MATCH (s:Service)-[:DEPENDS_ON]->(d) RETURN s.name, d.name")
# Format as: "auth-service depends on: postgres, redis\napi-gateway depends on: auth-service"
context = "\n".join(f"{r[0]} depends on: {r[1]}" for r in result.result_set)
```

This gives Claude precise, structured context at minimal token cost.
```

- [ ] **Step 2: Write falkordb-patterns.md**

```markdown
# FalkorDB Cypher Pattern Library

## Basic queries

```cypher
-- All nodes of a label
MATCH (n:Label) RETURN n

-- Node by property
MATCH (n:Label {name: $name}) RETURN n

-- All edges of a type
MATCH ()-[r:EDGE_TYPE]->() RETURN r

-- Node with all its neighbors
MATCH (n:Label {name: $name})-[r]->(neighbor) RETURN type(r), neighbor.name
```

## Traversal

```cypher
-- Direct children
MATCH (n {name: $name})-[:CHILD_OF]->(child) RETURN child.name

-- All descendants (variable depth)
MATCH (n {name: $name})-[:CHILD_OF*]->(desc) RETURN DISTINCT desc.name

-- Bounded traversal (1 to 3 hops)
MATCH (n {name: $name})-[*1..3]->(related) RETURN DISTINCT related.name

-- Shortest path
MATCH p=shortestPath((a {name: $from})-[*]->(b {name: $to})) RETURN p

-- All shortest paths
MATCH p=allShortestPaths((a {name: $from})-[*]->(b {name: $to})) RETURN p
```

## Aggregation

```cypher
-- Count by type
MATCH (n:Label) RETURN n.type, count(*) AS cnt ORDER BY cnt DESC

-- Top N by degree
MATCH (n:Label)-[r]->() RETURN n.name, count(r) AS degree ORDER BY degree DESC LIMIT 10

-- Group and collect
MATCH (n:Label)-[:MEMBER_OF]->(group) RETURN group.name, collect(n.name) AS members
```

## Write operations

```cypher
-- Create node
CREATE (n:Label {name: $name, prop: $value})

-- Merge (upsert)
MERGE (n:Label {name: $name}) ON CREATE SET n.created = timestamp() ON MATCH SET n.updated = timestamp()

-- Create edge
MATCH (a:Label {name: $from}), (b:Label {name: $to}) CREATE (a)-[:EDGE_TYPE]->(b)

-- Delete node and its edges
MATCH (n:Label {name: $name}) DETACH DELETE n
```

## Vector search (FalkorDB-specific)

```cypher
-- Create vector index
CREATE VECTOR INDEX FOR (n:Document) ON (n.embedding) OPTIONS {dimension: 1536, similarityFunction: 'cosine'}

-- Vector similarity search
MATCH (n:Document) WHERE vector.similarity.cosine(n.embedding, $query_embedding) > 0.8 RETURN n.text LIMIT 10
```
```

- [ ] **Step 3: Validate frontmatter**

```bash
python3 -c "
import re
content = open('lqc-tokens/skills/graph-context/SKILL.md').read()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
print('frontmatter OK' if match else 'ERROR: no frontmatter')
"
```

Expected: `frontmatter OK`

- [ ] **Step 4: Commit**

```bash
git add lqc-tokens/skills/graph-context/
git commit -m "feat: add graph-context skill with FalkorDB Cypher pattern library"
```

---

## Task 10: Skill — session-hygiene

**Files:**
- Create: `lqc-tokens/skills/session-hygiene/SKILL.md`

> After writing, invoke `/skill-creator` to review and refine the trigger description.

- [ ] **Step 1: Write SKILL.md**

```markdown
---
name: session-hygiene
description: Detects context drift and guides session reset. Use when the session has grown long (10+ turns), when the user switches topics or says "on a different topic", "separate question", "now let's switch to", or when the pre-prompt hook flags context drift. Also use when the user asks "should I start a new session?" or "is my context too large?".
argument-hint: "[optional: describe what you're working on now vs. what you were working on before]"
allowed-tools: Read, Write
---

# Session Hygiene

Long sessions with topic drift waste tokens. The cost of old unrelated context compounds with every new prompt.

## Detection heuristics

Context drift is likely when:
1. The session has 10 or more turns
2. The current prompt topic is different from the last 3–5 turns (different project, technology, or task)
3. Total estimated tokens are MEDIUM or HIGH

## Action options

Present these three options to the user:

### Option A: Summarize and reset (recommended for topic drift)

1. Write a context summary to `docs/session-context-{YYYY-MM-DD}.md`:

```markdown
# Session Context — {date}

## Work completed
- [bullet: what was done]
- [bullet: what decisions were made]

## Key files modified
- `path/to/file.py` — [what changed and why]

## Open threads
- [anything not yet finished]

## Next steps
- [what to work on next session]
```

2. Tell the user:
   > "Context saved to `docs/session-context-{date}.md`. Start a new Claude Code session and open that file to continue."

### Option B: Continue in current session

User overrides. No action taken. Add a note: "Continuing in current session — context is at ~{N}K tokens."

### Option C: Split the work

Identify which parts of the current prompt are continuation of prior work vs. new work:
- **Finish current work first** in this session
- **Write new work** to a TODO in `docs/session-context-{date}.md`
- Start fresh session for the new work

## Frequency guidance

Offer session-hygiene check when:
- Turn count ≥ 15 (regardless of topic)
- Turn count ≥ 10 AND topic switch detected
- User pastes a long prompt that appears unrelated to recent conversation
```

- [ ] **Step 2: Validate frontmatter**

```bash
python3 -c "
import re
content = open('lqc-tokens/skills/session-hygiene/SKILL.md').read()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
print('frontmatter OK' if match else 'ERROR: no frontmatter')
"
```

- [ ] **Step 3: Commit**

```bash
git add lqc-tokens/skills/session-hygiene/SKILL.md
git commit -m "feat: add session-hygiene skill"
```

---

## Task 11: Skill — setup

**Files:**
- Create: `lqc-tokens/skills/setup/SKILL.md`

> After writing, invoke `/skill-creator` to review and refine the trigger description.

- [ ] **Step 1: Write SKILL.md**

```markdown
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

If upgrading, find and replace the existing `## Token Cost Optimization` block. If fresh install, append to the end of the file.

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
1. Read `.mcp.json` from project root (or create it if it doesn't exist)
2. Add the docker server entry if not already present:
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
3. Confirm: "Docker MCP configured. Restart Claude Code for it to take effect."

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
```

- [ ] **Step 2: Validate frontmatter**

```bash
python3 -c "
import re
content = open('lqc-tokens/skills/setup/SKILL.md').read()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
print('frontmatter OK' if match else 'ERROR: no frontmatter')
"
```

- [ ] **Step 3: Commit**

```bash
git add lqc-tokens/skills/setup/SKILL.md
git commit -m "feat: add setup skill with CLAUDE.md injection and baseline capture"
```

---

## Task 12: Skill — eval

**Files:**
- Create: `lqc-tokens/skills/eval/SKILL.md`
- Create: `lqc-tokens/skills/eval/append-session-log.py`

> After writing, invoke `/skill-creator` to review and refine the trigger description.

- [ ] **Step 1: Write append-session-log.py**

This script is called by the Stop hook to record per-session metrics. Since it runs from the Stop hook, it reads the session-report analyzer output.

```python
#!/usr/bin/env python3
"""
Appends one metrics record to ~/.claude/lqc-tokens-log.jsonl.
Called by the Stop hook after each response.
Usage: python3 append-session-log.py <session_id> <input_tokens> <output_tokens> <cache_hits> <hook_fired> <suggestion_accepted>
"""
import sys, json, os
from datetime import datetime, timezone

log_path = os.path.expanduser("~/.claude/lqc-tokens-log.jsonl")

args = sys.argv[1:]
if len(args) < 4:
    sys.exit(0)  # silent: missing args means no data

record = {
    "date": datetime.now(timezone.utc).isoformat(),
    "session_id": args[0] if len(args) > 0 else "unknown",
    "input_tokens": int(args[1]) if len(args) > 1 else 0,
    "output_tokens": int(args[2]) if len(args) > 2 else 0,
    "cache_hits": int(args[3]) if len(args) > 3 else 0,
    "hook_fired": args[4].lower() == "true" if len(args) > 4 else False,
    "suggestion_accepted": args[5].lower() == "true" if len(args) > 5 else False,
}

with open(log_path, "a") as f:
    f.write(json.dumps(record) + "\n")
```
Save to `lqc-tokens/skills/eval/append-session-log.py`.

- [ ] **Step 2: Write SKILL.md**

```markdown
---
name: eval
description: Generates a token savings report comparing current usage against the pre-install baseline. Use when the user asks "is the plugin saving tokens?", "show me the eval report", "how much have I saved?", "/lqc-tokens:eval", or after 7+ days of plugin use to measure effectiveness.
allowed-tools: Read, Bash
---

# lqc-tokens Evaluation Report

## Prerequisites

- Baseline file: `~/.claude/lqc-tokens-baseline.json` (captured by `/lqc-tokens:setup`)
- Log file: `~/.claude/lqc-tokens-log.jsonl` (appended by Stop hook)

If baseline is missing: tell user to run `/lqc-tokens:setup` first.
If log has fewer than 3 entries: tell user "Not enough data yet — use the plugin for at least 3 sessions."

## Compute metrics

### 1. Load baseline

```bash
python3 -c "
import json
b = json.load(open(open('$HOME/.claude/lqc-tokens-baseline.json')))
overall = b.get('overall', {})
print(json.dumps({
    'avg_input_per_session': overall.get('input_tokens', {}).get('total', 0) / max(1, overall.get('session_count', 1)),
    'cache_hit_rate': overall.get('cache_hit_rate', 0),
    'session_count': overall.get('session_count', 1)
}))
"
```

### 2. Load log

```bash
python3 - <<'EOF'
import json, os, statistics

log_path = os.path.expanduser('~/.claude/lqc-tokens-log.jsonl')
records = [json.loads(l) for l in open(log_path) if l.strip()]

total_input = sum(r['input_tokens'] for r in records)
total_cache = sum(r['cache_hits'] for r in records)
total_prompts = len(records)
hooks_fired = sum(1 for r in records if r.get('hook_fired'))
accepted = sum(1 for r in records if r.get('suggestion_accepted'))

print(json.dumps({
    'avg_input_per_session': total_input / max(1, total_prompts),
    'cache_hit_rate': total_cache / max(1, total_input) if total_input > 0 else 0,
    'hook_fire_rate': hooks_fired / max(1, total_prompts),
    'acceptance_rate': accepted / max(1, hooks_fired) if hooks_fired > 0 else 0,
    'session_count': total_prompts
}))
EOF
```

### 3. Compute deltas and format report

Compute:
- `token_savings_pct = (baseline_avg - current_avg) / baseline_avg * 100`
- `cache_delta_pp = current_cache_rate - baseline_cache_rate` (in percentage points)

Format and output:

```
lqc-tokens evaluation
─────────────────────────────────────────────────────
Period:         {first log date} → {today}
Sessions logged: {N}

Token savings:   {+/-X}% avg input tokens/session vs. baseline
Cache hit rate:  {+/-X}pp ({baseline}% → {current}%)
Hook fire rate:  {X}% of prompts triggered advisory
Acceptance rate: {X}% of suggestions accepted by user
─────────────────────────────────────────────────────
```

Add one recommendation line based on the data:
- If acceptance rate < 50%: "Advisory threshold may be too sensitive — consider raising the paste size trigger from 2KB to 4KB"
- If cache hit rate < 85%: "Cache hit rate below target — more consistent prompt framing will improve this"
- If token savings < 10% after 7 days: "Limited savings detected — run `/lqc-tokens:docker-advisor` on your next data task for larger impact"
- Otherwise: "Plugin is performing well"
```

- [ ] **Step 3: Test append-session-log.py**

```bash
cd lqc-tokens/skills/eval
python3 append-session-log.py "test-session-001" 5000 1200 3800 true true
python3 -c "
import json
lines = open('$HOME/.claude/lqc-tokens-log.jsonl').readlines()
last = json.loads(lines[-1])
assert last['session_id'] == 'test-session-001'
assert last['input_tokens'] == 5000
assert last['suggestion_accepted'] == True
print('append-session-log.py OK')
"
```

Expected: `append-session-log.py OK`

- [ ] **Step 4: Clean up test record**

```bash
python3 -c "
import json
log = open('$HOME/.claude/lqc-tokens-log.jsonl').readlines()
filtered = [l for l in log if 'test-session-001' not in l]
open('$HOME/.claude/lqc-tokens-log.jsonl', 'w').writelines(filtered)
print('test record removed')
"
```

- [ ] **Step 5: Validate frontmatter**

```bash
python3 -c "
import re
content = open('lqc-tokens/skills/eval/SKILL.md').read()
match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
print('frontmatter OK' if match else 'ERROR: no frontmatter')
"
```

- [ ] **Step 6: Commit**

```bash
git add lqc-tokens/skills/eval/
git commit -m "feat: add eval skill and session log appender"
```

---

## Task 13: Plugin Validation

- [ ] **Step 1: Validate all SKILL.md frontmatter in one pass**

```bash
python3 - <<'EOF'
import re, glob, sys
errors = []
for path in glob.glob('lqc-tokens/skills/*/SKILL.md'):
    content = open(path).read()
    m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not m:
        errors.append(f"MISSING frontmatter: {path}")
        continue
    fm = m.group(1)
    for field in ['name:', 'description:']:
        if field not in fm:
            errors.append(f"MISSING {field} in {path}")

if errors:
    print('\n'.join(errors))
    sys.exit(1)
else:
    print(f"All {len(list(glob.glob('lqc-tokens/skills/*/SKILL.md')))} skills have valid frontmatter")
EOF
```

Expected: `All 6 skills have valid frontmatter`

- [ ] **Step 2: Validate hooks.json**

```bash
python3 -c "
import json
h = json.load(open('lqc-tokens/hooks/hooks.json'))
events = list(h['hooks'].keys())
assert 'UserPromptSubmit' in events
assert 'Stop' in events
assert 'SessionEnd' in events
print('hooks.json valid, events:', events)
"
```

Expected: `hooks.json valid, events: ['UserPromptSubmit', 'Stop', 'SessionEnd']`

- [ ] **Step 3: Validate shell script**

```bash
bash -n lqc-tokens/hooks/session-end.sh && shellcheck lqc-tokens/hooks/session-end.sh || echo "shellcheck not installed, skipping"
```

Expected: no errors from `bash -n`.

- [ ] **Step 4: Validate YAML compose templates**

```bash
python3 -c "
import yaml, glob
for f in glob.glob('lqc-tokens/skills/docker-advisor/references/docker-compose-templates/*.yml'):
    yaml.safe_load(open(f).read())
    print(f'OK: {f}')
print('All compose templates valid')
"
```

Expected: 4 OK lines.

- [ ] **Step 5: Run plugin-validator agent**

```
/plugin-dev:plugin-validator
```

Review output and fix any critical errors.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat: complete lqc-tokens v0.1.0 plugin"
```

---

## Task 14: Integration Test

- [ ] **Step 1: Install plugin locally**

```bash
# Copy to project's .claude-plugin for local testing
mkdir -p .claude-plugin
cp -r lqc-tokens .claude-plugin/
```

- [ ] **Step 2: Run setup skill**

In a Claude Code session: `/lqc-tokens:setup`

Verify:
- CLAUDE.md updated with `lqc-tokens v0.1.0` block
- Docker version shown
- No errors

- [ ] **Step 3: Test pre-prompt hook fires on data trigger**

Submit this prompt:
```
read the following CSV and tell me the top 5 rows: id,name,value\n1,Alice,100\n...
```

Expected: advisory block appears before Claude's response.

- [ ] **Step 4: Test pre-prompt hook is silent for simple prompts**

Submit: `what is 2+2?`

Expected: no advisory block. Response ends with the 📊 cost line only.

- [ ] **Step 5: Test Stop hook**

Every response should end with the 📊 token cost line. Verify.

- [ ] **Step 6: Test docker-advisor skill**

Submit: `/lqc-tokens:docker-advisor I have a 50K row CSV of sales data`

Expected: DB recommendation (PostgreSQL), docker-compose.lqc.yml generated, persistence question asked.

- [ ] **Step 7: Test eval skill (with mock baseline)**

```bash
# Create mock baseline
python3 -c "
import json
mock = {'overall': {'input_tokens': {'total': 500000}, 'session_count': 10, 'cache_hit_rate': 0.65}}
open('$HOME/.claude/lqc-tokens-baseline.json', 'w').write(json.dumps(mock))
print('mock baseline created')
"
# Add 3 mock log entries
python3 lqc-tokens/skills/eval/append-session-log.py "s1" 35000 8000 28000 true true
python3 lqc-tokens/skills/eval/append-session-log.py "s2" 28000 6000 24000 false false
python3 lqc-tokens/skills/eval/append-session-log.py "s3" 22000 5000 19000 true true
```

Then run `/lqc-tokens:eval` and verify a formatted report appears.

- [ ] **Step 8: Clean up mock data**

```bash
python3 -c "
import json, os
log = open(os.path.expanduser('~/.claude/lqc-tokens-log.jsonl')).readlines()
filtered = [l for l in log if not any(x in l for x in ['\"s1\"','\"s2\"','\"s3\"'])]
open(os.path.expanduser('~/.claude/lqc-tokens-log.jsonl'), 'w').writelines(filtered)
os.remove(os.path.expanduser('~/.claude/lqc-tokens-baseline.json'))
print('mock data cleaned up')
"
```

- [ ] **Step 9: Final commit**

```bash
git add -A
git commit -m "test: add integration test results and clean up mock data"
```
