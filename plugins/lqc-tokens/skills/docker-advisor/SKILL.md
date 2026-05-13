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

Once the container is healthy, check whether a DB-native MCP server is available.

**If MCP tools are present:** use them — 1 tool call per query vs 3+ with Python.
**If MCP tools are absent:** ask the user if they want to enable them before falling back to Python.

#### FalkorDB

**If `mcp__falkordb__*` tools are available:**

Discover graphs and inspect schema:
```
mcp__falkordb__list_graphs
mcp__falkordb__query_graph_readonly(graphName="<graph-name>", query="CALL db.labels() YIELD label RETURN label")
```

Run read-only Cypher:
```
mcp__falkordb__query_graph_readonly(graphName="<graph-name>", query="MATCH (n) RETURN n.name LIMIT 10")
```

Load data (create nodes and relationships via Cypher):
```
mcp__falkordb__query_graph(graphName="<graph-name>", query="MERGE (n:Entity {id: '1', name: 'example'})")
mcp__falkordb__query_graph(graphName="<graph-name>", query="MATCH (a:Entity {id: '1'}), (b:Entity {id: '2'}) MERGE (a)-[:RELATES_TO]->(b)")
```

**If `mcp__falkordb__*` tools are NOT available — ask the user:**

> "FalkorDB MCP is not enabled. Enabling it cuts query token cost ~70% (1 tool call instead of Python subprocess + parsing).
>
> **Enable now (recommended):**
> 1. Copy `.mcp.json.example` → `.mcp.json` in your project root
> 2. Edit `.mcp.json`: set `FALKORDB_PORT` to `{HOST_PORT}` under the `falkordb` server env
> 3. Restart Claude Code to load the MCP server
>
> **Skip for now:** I'll use Python instead — you can enable MCP later for future sessions."

If the user enables MCP and restarts, proceed with MCP tools.
If the user skips, use the Python fallback:
```python
from falkordb import FalkorDB
db = FalkorDB(host='localhost', port=HOST_PORT)  # replace HOST_PORT with assigned port, e.g. 54001
g = db.select_graph('<graph-name>')
result = g.query("MATCH (n:Entity) RETURN n.name LIMIT 10")
```

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

**If `mcp__mongodb__*` tools are NOT available — ask the user:**

> "MongoDB MCP is not enabled. Enabling it cuts query token cost ~70% (direct tool calls instead of Python subprocess).
>
> **Enable now (recommended):**
> 1. Copy `.mcp.json.example` → `.mcp.json` in your project root
> 2. Edit `.mcp.json`: update the MongoDB `--connectionString` arg — replace `27017` with `{HOST_PORT}`
> 3. Restart Claude Code to load the MCP server
>
> **Skip for now:** I'll use Python instead."

If the user skips, use the Python fallback:
```python
from pymongo import MongoClient
client = MongoClient('mongodb://lqc:lqcpass@localhost:HOST_PORT/')  # replace HOST_PORT with assigned port
db = client['lqcdata']
```

#### PostgreSQL

**If `mcp__postgres__*` tools are available:**

Run SQL directly:
```
mcp__postgres__query(sql="SELECT * FROM my_table LIMIT 10")
mcp__postgres__query(sql="SELECT column_name, data_type FROM information_schema.columns WHERE table_name='my_table'")
```

Note: `mcp__postgres__query` is **read-only**. For `CREATE TABLE`, `INSERT`, or `COPY` operations, use the Python psycopg2 fallback.

**If `mcp__postgres__*` tools are NOT available — ask the user:**

> "Postgres MCP is not enabled. Enabling it lets me run SQL queries directly (read-only) without Python subprocess overhead.
>
> **Enable now (recommended):**
> 1. Copy `.mcp.json.example` → `.mcp.json` in your project root
> 2. Edit `.mcp.json`: update the Postgres connection string — replace `5432` with `{HOST_PORT}`
> 3. Restart Claude Code to load the MCP server
>
> **Skip for now:** I'll use Python instead. Note: Python fallback supports writes (INSERT/COPY) too."

If the user skips, use the Python fallback:
```python
import psycopg2
conn = psycopg2.connect(host='localhost', port=HOST_PORT, dbname='lqcdata', user='lqc', password='lqcpass')  # replace HOST_PORT with assigned port
```

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
