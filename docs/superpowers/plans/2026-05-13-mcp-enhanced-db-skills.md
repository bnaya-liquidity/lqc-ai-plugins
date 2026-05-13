# MCP-Enhanced DB Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enhance the `docker-advisor` and `graph-context` skills to prefer MCP tool calls over Python subprocess execution when MCP servers for FalkorDB, MongoDB, or Postgres are available, reducing token cost and latency.

**Architecture:** Each DB type gets a conditional MCP path in the skill — when `mcp__falkordb__*`, `mcp__mongodb__*`, or `mcp__postgres__*` tools are in scope, Claude queries the database directly as a structured tool call rather than generating + executing a Python script. Falls back to existing Python path when MCP is absent. A pre-improvement eval snapshot is saved as the baseline; post-improvement evals measure the delta.

**Tech Stack:** Claude Code plugin skills (Markdown), Docker Compose YAML, `@falkordb/mcpserver`, `mongodb-mcp-server`, `@modelcontextprotocol/server-postgres` (npm packages, all stdio transport)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark-pre.json` | Create | Pre-improvement eval baseline |
| `plugins/lqc-tokens/.mcp.json.example` | Modify | Add FalkorDB + MongoDB + Postgres MCP configs |
| `plugins/lqc-tokens/skills/docker-advisor/SKILL.md` | Modify | Add MCP detection + usage path for all 3 DBs |
| `plugins/lqc-tokens/skills/graph-context/SKILL.md` | Modify | Use `graph_structure` + `query_graph_readonly` when FalkorDB MCP available |
| `plugins/lqc-tokens/skills/docker-advisor/references/db-selection-guide.md` | Modify | Add MCP tool names for each DB |
| `plugins/lqc-tokens/skills/docker-advisor/references/docker-compose-templates/falkordb.yml` | Modify | Add healthcheck |
| `plugins/lqc-tokens/skills/docker-advisor/references/docker-compose-templates/mongodb.yml` | Modify | Add healthcheck |
| `plugins/lqc-tokens/skills/docker-advisor/references/docker-compose-templates/postgres.yml` | Modify | Add healthcheck |
| `plugins/lqc-tokens/skills/eval/eval-workspace/evals/evals.json` | Modify | Add 3 new MCP-aware eval cases (one per DB) |
| `plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark.json` | Create | Post-improvement eval results |

---

## Task 1: Capture pre-improvement eval baseline

**Files:**
- Create: `plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark-pre.json`

- [ ] **Step 1: Write the baseline JSON capturing current iteration-2 scores**

```json
{
  "metadata": {
    "skill_name": "eval + docker-advisor",
    "skill_path": "plugins/lqc-tokens/skills",
    "iteration": "3-pre",
    "note": "Snapshot before MCP integration. Evals 1-4 all pass at 100% (iteration-2 confirmed). This file is the correctness+token baseline for measuring MCP improvement impact.",
    "timestamp": "2026-05-13T00:00:00Z",
    "evals_run": [1, 2, 3, 4],
    "runs_per_configuration": 1
  },
  "baseline_scores": {
    "eval_1_eval-report-from-realistic-log": { "pass_rate": 1.0, "tokens": 24960, "time_seconds": 51.2 },
    "eval_2_pre-prompt-hook-large-data-paste": { "pass_rate": 1.0, "tokens": null, "time_seconds": null },
    "eval_3_pre-prompt-hook-vague-prompt": { "pass_rate": 1.0, "tokens": null, "time_seconds": null },
    "eval_4_pre-prompt-hook-well-formed-prompt-stays-silent": { "pass_rate": 1.0, "tokens": null, "time_seconds": null }
  },
  "notes": [
    "MCP tools absent: docker-advisor falls back to Python subprocess for all DB operations.",
    "graph-context skill uses Python falkordb client via Bash tool.",
    "Target: MCP paths should preserve 100% pass rate and reduce token cost via direct tool calls."
  ]
}
```

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark-pre.json
git commit -m "eval: save pre-MCP iteration-3 baseline snapshot"
```

---

## Task 2: Update .mcp.json.example with DB MCP servers

**Files:**
- Modify: `plugins/lqc-tokens/.mcp.json.example`

- [ ] **Step 1: Replace the file content**

```json
{
  "mcpServers": {
    "docker": {
      "command": "docker",
      "args": ["mcp", "gateway", "run"],
      "type": "stdio"
    },
    "falkordb": {
      "command": "npx",
      "args": ["-y", "@falkordb/mcpserver@latest"],
      "type": "stdio",
      "env": {
        "FALKORDB_HOST": "localhost",
        "FALKORDB_PORT": "6379",
        "FALKORDB_USERNAME": "",
        "FALKORDB_PASSWORD": "",
        "FALKORDB_DEFAULT_READONLY": "true"
      }
    },
    "mongodb": {
      "command": "npx",
      "args": [
        "-y",
        "mongodb-mcp-server",
        "--connectionString",
        "mongodb://lqc:lqcpass@localhost:27017/lqcdata",
        "--readOnly"
      ],
      "type": "stdio"
    },
    "postgres": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-postgres",
        "postgresql://lqc:lqcpass@localhost:5432/lqcdata"
      ],
      "type": "stdio"
    }
  }
}
```

> Note: Users copy `.mcp.json.example` to `.mcp.json` and adjust ports/passwords to match their running containers. The `docker-advisor` skill emits a reminder to do this in Step 6.

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/.mcp.json.example
git commit -m "feat: add FalkorDB, MongoDB, Postgres MCP configs to .mcp.json.example"
```

---

## Task 3: Update db-selection-guide.md with MCP tool names

**Files:**
- Modify: `plugins/lqc-tokens/skills/docker-advisor/references/db-selection-guide.md`

- [ ] **Step 1: Add an MCP tools column to each DB section**

Replace the existing content of `db-selection-guide.md` with:

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
**Client (Python fallback):** `pip install falkordb`

**MCP server:** `@falkordb/mcpserver` — detected as `mcp__falkordb__*`
**MCP tools available:**
- `mcp__falkordb__list_graphs` — list all graphs
- `mcp__falkordb__graph_structure` — inspect schema (node labels, relationship types, properties)
- `mcp__falkordb__query_graph_readonly` — run read-only OpenCypher queries
- `mcp__falkordb__query_graph` — run read-write OpenCypher queries
- `mcp__falkordb__create_nodes` — insert nodes
- `mcp__falkordb__create_relationships` — insert edges

## MongoDB + Lucene

**Choose when:**
- Data is document-shaped (JSON objects with variable fields)
- Need full-text search over document content
- Access pattern is "find documents matching text query"
- Schema-flexible: documents vary in shape

**Docker image:** `mongo:7`
**Default port:** 27017
**Query language:** MQL (MongoDB Query Language)
**Client (Python fallback):** `pip install pymongo`

**MCP server:** `mongodb-mcp-server` — detected as `mcp__mongodb__*`
**MCP tools available:**
- `mcp__mongodb__find` — query documents with filter/projection/sort/limit
- `mcp__mongodb__count` — count documents matching a filter
- `mcp__mongodb__aggregate` — run aggregation pipelines
- `mcp__mongodb__collection-schema` — inspect collection schema

## PostgreSQL

**Choose when:**
- Data is tabular with fixed schema (rows and columns)
- Need joins, aggregations, GROUP BY
- Data comes from CSV/Excel exports
- Access pattern is SQL-style relational queries

**Docker image:** `postgres:16-alpine`
**Default port:** 5432
**Query language:** SQL
**Client (Python fallback):** `pip install psycopg2-binary`

**MCP server:** `@modelcontextprotocol/server-postgres` — detected as `mcp__postgres__*`
**MCP tools available:**
- `mcp__postgres__query` — execute read-only SQL queries and return results

## Chroma (Vector / Semantic)

**Choose when:**
- Need semantic similarity search ("find documents similar to X")
- Working with embeddings
- RAG without relationship structure
- Text chunks that need nearest-neighbor retrieval

**Docker image:** `chromadb/chroma:latest`
**Default port:** 8000
**Client:** `pip install chromadb`

*(No MCP server available for Chroma yet — use Python client via Bash.)*

## Combination patterns

| Scenario | Recommendation |
|---|---|
| Knowledge graph + semantic search | FalkorDB (supports both natively) |
| Product catalog + text search | MongoDB |
| Financial data + analytics | PostgreSQL |
| Document RAG without relationships | Chroma |
| Code dependency analysis | FalkorDB |
```

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/skills/docker-advisor/references/db-selection-guide.md
git commit -m "docs: add MCP tool names to db-selection-guide for all three DB types"
```

---

## Task 4: Update docker-compose templates with healthchecks

**Files:**
- Modify: `plugins/lqc-tokens/skills/docker-advisor/references/docker-compose-templates/falkordb.yml`
- Modify: `plugins/lqc-tokens/skills/docker-advisor/references/docker-compose-templates/mongodb.yml`
- Modify: `plugins/lqc-tokens/skills/docker-advisor/references/docker-compose-templates/postgres.yml`

Healthchecks let `docker compose up -d --wait` block until the DB is actually ready, so Claude can query immediately after the command without a manual retry loop.

- [ ] **Step 1: Update falkordb.yml**

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
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "6379", "ping"]
      interval: 2s
      timeout: 5s
      retries: 10

volumes:
  VOLUME_NAME:
```

- [ ] **Step 2: Update mongodb.yml**

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
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 2s
      timeout: 5s
      retries: 15

volumes:
  VOLUME_NAME:
```

- [ ] **Step 3: Update postgres.yml**

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
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U lqc -d lqcdata"]
      interval: 2s
      timeout: 5s
      retries: 10

volumes:
  VOLUME_NAME:
```

- [ ] **Step 4: Commit**

```bash
git add plugins/lqc-tokens/skills/docker-advisor/references/docker-compose-templates/
git commit -m "feat: add healthchecks to all docker-compose DB templates"
```

---

## Task 5: Update docker-advisor/SKILL.md — add MCP paths for all three DBs

**Files:**
- Modify: `plugins/lqc-tokens/skills/docker-advisor/SKILL.md`

This is the core task. The change adds a **Step 5b (MCP path)** that precedes the existing Python fallback path, and updates Step 5 and 6 to route appropriately.

- [ ] **Step 1: Replace the full SKILL.md content**

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

### Step 3: Ask about longevity

> "Is this data needed for future sessions beyond today?"

- **Yes → persistent container**:
  - Name: `lqc-{project-slug}-{db}` (e.g. `lqc-myapp-falkordb`)
  - Port: deterministic from range 54000–54999 (pick the lowest unused port via `ss -tlnp | grep 540` or `lsof -i :540[0-9][0-9]`)
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

### Step 5: Start the container

**If `mcp__docker__*` tools are in the tool list:**
1. Run `docker compose -f docker-compose.lqc.yml up -d --wait`
2. The `--wait` flag blocks until the healthcheck passes — no manual polling needed
3. Return the connection string

**Otherwise (no Docker MCP):**
- Output the manual command and tell the user to run it, then continue:
  ```bash
  docker compose -f docker-compose.lqc.yml up -d --wait
  ```

### Step 6: Query the database

Once the container is healthy, check whether a DB-native MCP server is available. Use the MCP path when present — it avoids Python process overhead and keeps queries in-context as structured tool calls.

#### FalkorDB

**If `mcp__falkordb__*` tools are available:**

Inspect graph structure with:
```
mcp__falkordb__list_graphs → to see existing graphs
mcp__falkordb__graph_structure(graph="<graph-name>") → to inspect schema
```

Run read-only Cypher:
```
mcp__falkordb__query_graph_readonly(graph="<graph-name>", query="MATCH (n) RETURN n.name LIMIT 10")
```

Insert nodes/edges:
```
mcp__falkordb__create_nodes(graph="<graph-name>", labels=["Entity"], properties=[{"id": "1", "name": "..."}])
mcp__falkordb__create_relationships(graph="<graph-name>", type="RELATES_TO", src_node={...}, dest_node={...})
```

**Fallback (no FalkorDB MCP):** Use Python client:
```python
from falkordb import FalkorDB
db = FalkorDB(host='localhost', port=HOST_PORT)
g = db.select_graph('myproject')
result = g.query("MATCH (n:Entity) RETURN n.name LIMIT 10")
```

**Also remind user:** copy `.mcp.json.example` → `.mcp.json` and set `FALKORDB_PORT` to the assigned port so the MCP server connects to the correct container.

#### MongoDB

**If `mcp__mongodb__*` tools are available:**

Inspect schema:
```
mcp__mongodb__collection-schema(collection="<collection>")
```

Query documents:
```
mcp__mongodb__find(collection="<collection>", filter={"field": "value"}, limit=20)
mcp__mongodb__count(collection="<collection>", filter={})
mcp__mongodb__aggregate(collection="<collection>", pipeline=[{"$group": {"_id": "$field", "count": {"$sum": 1}}}])
```

**Fallback (no MongoDB MCP):**
```python
from pymongo import MongoClient
client = MongoClient('mongodb://lqc:lqcpass@localhost:HOST_PORT/')
db = client['lqcdata']
```

**Also remind user:** copy `.mcp.json.example` → `.mcp.json` and update the `--connectionString` port.

#### PostgreSQL

**If `mcp__postgres__*` tools are available:**

Run SQL directly:
```
mcp__postgres__query(sql="SELECT * FROM my_table LIMIT 10")
mcp__postgres__query(sql="SELECT column_name, data_type FROM information_schema.columns WHERE table_name='my_table'")
```

**Fallback (no Postgres MCP):**
```python
import psycopg2
conn = psycopg2.connect(host='localhost', port=HOST_PORT, dbname='lqcdata', user='lqc', password='lqcpass')
```

**Also remind user:** copy `.mcp.json.example` → `.mcp.json` and update the connection string port.

### Step 7: Provide connection string and next steps

Tell the user the connection string, whether MCP or Python path is active, and how to load their data. Include a data-loading snippet.

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

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/skills/docker-advisor/SKILL.md
git commit -m "feat: add MCP-native query paths for FalkorDB, MongoDB, Postgres in docker-advisor"
```

---

## Task 6: Update graph-context/SKILL.md — use FalkorDB MCP when available

**Files:**
- Modify: `plugins/lqc-tokens/skills/graph-context/SKILL.md`

- [ ] **Step 1: Replace the full SKILL.md content**

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

For isolated setup without port conflicts, use host port 16379 (avoids collision with local Redis on 6379):

```bash
docker run -d --name falkordb -p 16379:6379 \
  --health-cmd "redis-cli -p 6379 ping" \
  --health-interval 2s --health-retries 10 \
  falkordb/falkordb:latest
```

If you used `docker-advisor` to set up FalkorDB, use the port it assigned instead.

## Querying — MCP path (preferred)

When `mcp__falkordb__*` tools are in scope, query FalkorDB directly without spawning Python:

**1. Inspect the graph schema:**
```
mcp__falkordb__graph_structure(graph="<graph-name>")
```
Returns node labels, relationship types, and property keys — use this to write queries without loading data into context first.

**2. Run read-only Cypher:**
```
mcp__falkordb__query_graph_readonly(graph="<graph-name>", query="MATCH (s:Service {name: $name})-[:DEPENDS_ON*1..3]->(dep) RETURN DISTINCT dep.name", params={"name": "auth-service"})
```

**3. Run read-write queries (for loading/mutations):**
```
mcp__falkordb__query_graph(graph="<graph-name>", query="MERGE (n:Service {name: $name}) SET n.language = $lang", params={"name": "auth-service", "lang": "go"})
```

**Connection:** The MCP server reads `FALKORDB_HOST` and `FALKORDB_PORT` from its env. Set these in `.mcp.json` to match the docker-advisor-assigned port.

## Querying — Python fallback (when MCP not available)

```python
from falkordb import FalkorDB

db = FalkorDB(host='localhost', port=6379)  # use docker-advisor port if different
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
FalkorDB graph is running at localhost:16379, graph name: 'services'.
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

## Passing query results to Claude

Run the query, format results as a compact table or list, include only that in the prompt:

```python
result = g.query("MATCH (s:Service)-[:DEPENDS_ON]->(d) RETURN s.name, d.name")
context = "\n".join(f"{r[0]} depends on: {r[1]}" for r in result.result_set)
```

This gives Claude precise, structured context at minimal token cost.
```

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/skills/graph-context/SKILL.md
git commit -m "feat: add FalkorDB MCP query path to graph-context skill"
```

---

## Task 7: Add MCP-aware evals to evals.json

**Files:**
- Modify: `plugins/lqc-tokens/skills/eval/eval-workspace/evals/evals.json`

Three new evals verify that the MCP detection logic works correctly for each DB type.

- [ ] **Step 1: Append 3 new eval objects to the `evals` array in evals.json**

Add after the existing eval with `"id": 4`:

```json
{
  "id": 5,
  "name": "docker-advisor-falkordb-mcp-path",
  "prompt": "I need to analyze a social network dataset. I have 50,000 users and 2 million friendship connections in a CSV. I need to find influencers, communities, and the shortest path between any two users. Please set up the database.",
  "context": "mcp__falkordb__list_graphs, mcp__falkordb__graph_structure, mcp__falkordb__query_graph_readonly, mcp__falkordb__create_nodes, mcp__falkordb__create_relationships tools are available in the tool list. Docker MCP tools are NOT available.",
  "expected_output": "docker-advisor recommends FalkorDB, generates docker-compose.lqc.yml with healthcheck, outputs manual docker compose command (no Docker MCP), then provides MCP-based query examples using mcp__falkordb__query_graph_readonly — NOT Python subprocess code. Also reminds user to update .mcp.json FALKORDB_PORT.",
  "assertions": [
    {
      "text": "Skill recommends FalkorDB given the graph-shaped social network data",
      "type": "content_check"
    },
    {
      "text": "Generated docker-compose.lqc.yml includes a healthcheck block",
      "type": "content_check"
    },
    {
      "text": "Query examples reference mcp__falkordb__query_graph_readonly, NOT a Python subprocess or Bash command",
      "type": "content_check"
    },
    {
      "text": "Skill reminds user to update .mcp.json with the assigned FALKORDB_PORT",
      "type": "content_check"
    }
  ]
},
{
  "id": 6,
  "name": "docker-advisor-mongodb-mcp-path",
  "prompt": "I have a collection of 30,000 support tickets as JSON. Each ticket has different fields depending on the product. I need to search them by keyword and count by category.",
  "context": "mcp__mongodb__find, mcp__mongodb__count, mcp__mongodb__aggregate, mcp__mongodb__collection-schema tools are available. Docker MCP tools are NOT available.",
  "expected_output": "docker-advisor recommends MongoDB, generates docker-compose.lqc.yml with healthcheck, provides manual docker compose command, then shows query examples using mcp__mongodb__find and mcp__mongodb__aggregate — NOT pymongo Python code. Reminds user to update .mcp.json connection string port.",
  "assertions": [
    {
      "text": "Skill recommends MongoDB given the variable-schema JSON document data",
      "type": "content_check"
    },
    {
      "text": "Generated docker-compose.lqc.yml includes a healthcheck block",
      "type": "content_check"
    },
    {
      "text": "Query examples reference mcp__mongodb__find or mcp__mongodb__aggregate, NOT pymongo subprocess",
      "type": "content_check"
    },
    {
      "text": "Skill reminds user to update .mcp.json MongoDB connection string",
      "type": "content_check"
    }
  ]
},
{
  "id": 7,
  "name": "docker-advisor-postgres-mcp-path",
  "prompt": "I have Q1 sales data in a CSV: 500,000 rows with date, region, product, units, revenue, cost columns. I need to GROUP BY region and product and find top 10 by margin.",
  "context": "mcp__postgres__query tool is available. Docker MCP tools are NOT available.",
  "expected_output": "docker-advisor recommends PostgreSQL, generates docker-compose.lqc.yml with healthcheck, provides manual docker compose command, then shows query examples using mcp__postgres__query with SQL — NOT psycopg2 Python code. Reminds user to update .mcp.json Postgres connection string port.",
  "assertions": [
    {
      "text": "Skill recommends PostgreSQL given the tabular CSV data with SQL-style access patterns",
      "type": "content_check"
    },
    {
      "text": "Generated docker-compose.lqc.yml includes a healthcheck block",
      "type": "content_check"
    },
    {
      "text": "Query examples reference mcp__postgres__query with SQL, NOT psycopg2 or subprocess",
      "type": "content_check"
    },
    {
      "text": "Skill reminds user to update .mcp.json Postgres connection string",
      "type": "content_check"
    }
  ]
}
```

> The full `evals.json` must have the top-level `evals` array contain all 7 objects (IDs 1–7).

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/skills/eval/eval-workspace/evals/evals.json
git commit -m "eval: add evals 5-7 for MCP-aware docker-advisor paths (FalkorDB, MongoDB, Postgres)"
```

---

## Task 8: Run evals and save iteration-3 results

**Files:**
- Create: `plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark.json`

This task is executed by running `/lqc-tokens:eval` with the skill-creator:skill-creator skill against evals 5, 6, and 7 (the three new MCP-aware evals). Evals 1–4 are unchanged and inherited from iteration-2.

- [ ] **Step 1: Run evals 5, 6, 7 using the skill-creator eval runner**

```bash
# Invoke from within a Claude Code session:
# /skill-creator:skill-creator
# → "Run evals 5, 6, 7 from plugins/lqc-tokens/skills/eval/eval-workspace/evals/evals.json
#    against the updated docker-advisor/SKILL.md. Save results to
#    plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/"
```

- [ ] **Step 2: Write the benchmark.json template** (to be filled by eval runner)

```json
{
  "metadata": {
    "skill_name": "docker-advisor",
    "skill_path": "plugins/lqc-tokens/skills/docker-advisor",
    "executor_model": "claude-sonnet-4-6",
    "analyzer_model": "claude-sonnet-4-6",
    "timestamp": "FILL_IN",
    "iteration": 3,
    "evals_run": [5, 6, 7],
    "note": "Tests MCP detection paths for FalkorDB, MongoDB, Postgres. Evals 1-4 inherited from iteration-2 at 100%."
  },
  "runs": [],
  "run_summary": {},
  "delta_from_baseline": {
    "note": "Compare token cost of MCP path vs Python path using eval metadata token counts"
  }
}
```

- [ ] **Step 3: Commit results after eval runner populates benchmark.json**

```bash
git add plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/
git commit -m "eval: save iteration-3 benchmark results for MCP-aware docker-advisor"
```

---

## Spec coverage check

| Spec requirement | Covered by |
|---|---|
| Save the evals baseline | Task 1 (pre-MCP snapshot) |
| Improve FalkorDB DB skill using MCP | Tasks 3, 4, 5, 6 |
| Improve MongoDB DB skill using MCP | Tasks 3, 4, 5 |
| Improve Postgres DB skill using MCP | Tasks 3, 4, 5 |
| Validate each DB type | Tasks 7, 8 (evals 5, 6, 7) |
| Can be parallel via sub-agent | Tasks 3–6 are per-file; Tasks 5–6 can be dispatched to 3 parallel sub-agents (one per DB + one for docker-compose templates) |

## Parallelization note

Tasks 3–6 can be run as **3 parallel sub-agents** since each touches disjoint files:
- **Sub-agent A (FalkorDB):** Task 6 (graph-context/SKILL.md) + FalkorDB section of Task 3 (db-selection-guide) + falkordb.yml in Task 4
- **Sub-agent B (MongoDB):** MongoDB section of Task 3 + mongodb.yml in Task 4
- **Sub-agent C (Postgres):** Postgres section of Task 3 + postgres.yml in Task 4
- **Main thread:** Task 5 (docker-advisor/SKILL.md, integrates all three — must run after sub-agents complete)
