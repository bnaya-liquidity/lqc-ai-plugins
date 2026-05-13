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
- **Longevity**: session (default), request (single turn), or user (persist across sessions)?

### Step 2: Recommend a database

Use the selection guide at `references/db-selection-guide.md`. Recommend 1–2 databases maximum.

### Step 3: Choose isolation level

Present options with `session` pre-selected. The user presses Enter to accept the default:

> "How long should this data persist?
>
> **[session]** — auto-cleaned when Claude Code closes ✓ **(default — press Enter)**
> **[request]** — deleted after this conversation turn
> **[user]** — persists across all sessions (you clean up manually)"

Based on the answer, generate the isolation ID:

**session** — get or create a session ID:
```bash
python3 - <<'EOF'
import re, os, uuid, sys
p = os.path.expanduser('~/.claude/lqc-tokens.local.md')
if os.path.exists(p):
    with open(p) as f:
        m = re.match(r'^---\n(.*?)---', f.read(), re.DOTALL)
    if m:
        try:
            import yaml
            fm = yaml.safe_load(m.group(1)) or {}
            sid = fm.get('session_id')
            if sid: print(sid); sys.exit(0)
        except ImportError:
            pass
print('sess_' + uuid.uuid4().hex[:8])
EOF
```
If this prints a new ID (not found in the file), save it with:
```bash
python3 - "$ISOLATION_ID" <<'EOF'
import sys, re, os
new_id = sys.argv[1]
p = os.path.expanduser('~/.claude/lqc-tokens.local.md')
if os.path.exists(p):
    with open(p) as f:
        raw = f.read()
    m = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
    if m:
        pre, fm_text, close, rest = m.groups()
        try:
            import yaml
            fm = yaml.safe_load(fm_text) or {}
            fm['session_id'] = new_id
            new_fm = yaml.dump(fm, default_flow_style=False, sort_keys=False)
            with open(p, 'w') as f:
                f.write(pre + new_fm + close + rest)
            sys.exit(0)
        except ImportError:
            pass
# File absent or no frontmatter — create minimal file
with open(p, 'w') as f:
    f.write(f'---\nsession_id: {new_id}\nisolated_namespaces: []\nephemeral_containers: []\n---\n\nManaged by lqc-tokens plugin. Do not edit manually.\n')
EOF
```

**request:**
```bash
python3 -c "import uuid; print('req_' + uuid.uuid4().hex[:8])"
```

**user:**
```bash
python3 -c "import os, re; slug = re.sub(r'[^a-z0-9]', '', os.path.basename(os.getcwd()).lower()); print('user_' + (slug or 'default'))"
```

Set `NAMESPACE=lqc_{ISOLATION_ID}` (e.g. `lqc_sess_a1b2c3d4`).

### Step 4: Start base container (if needed) and create namespace

**Check if base container is already running:**
```bash
docker ps --filter "name=lqc-base-{db}" --format "{{.Names}}"
```

**Write `docker-compose.lqc-base.yml`** to the project root (always — content is deterministic and idempotent):

For FalkorDB:
```yaml
services:
  falkordb:
    image: falkordb/falkordb:latest
    container_name: lqc-base-falkordb
    ports:
      - "54010:6379"
    volumes:
      - lqc-base-falkordb-data:/data
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "6379", "ping"]
      interval: 2s
      timeout: 5s
      retries: 10
volumes:
  lqc-base-falkordb-data:
```

For MongoDB:
```yaml
services:
  mongodb:
    image: mongo:7
    container_name: lqc-base-mongodb
    ports:
      - "54011:27017"
    volumes:
      - lqc-base-mongodb-data:/data/db
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
  lqc-base-mongodb-data:
```

For PostgreSQL:
```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: lqc-base-postgres
    ports:
      - "54012:5432"
    volumes:
      - lqc-base-postgres-data:/var/lib/postgresql/data
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
  lqc-base-postgres-data:
```

**If NOT running**, start the base container:
```bash
docker compose -f docker-compose.lqc-base.yml up -d --wait
```
If Docker MCP is not available, output this command for the user to run manually.

**Create the namespace** (skip for FalkorDB and MongoDB — created implicitly on first write):

For PostgreSQL only:
```bash
docker exec lqc-base-postgres psql -U lqc -d lqcdata -c "CREATE SCHEMA IF NOT EXISTS {NAMESPACE};"
```

### Step 5: Query the database

Once the container is healthy, check whether a DB-native MCP server is available.

**If MCP tools are present:** use them — 1 tool call per query vs 3+ with Python.
**If MCP tools are absent:** ask the user if they want to enable them before falling back to Python.

#### FalkorDB

**If `mcp__falkordb__*` tools are available:**

Discover graphs and inspect schema:
```
mcp__falkordb__list_graphs
mcp__falkordb__query_graph_readonly(graphName="{NAMESPACE}", query="CALL db.labels() YIELD label RETURN label")
```

Run read-only Cypher:
```
mcp__falkordb__query_graph_readonly(graphName="{NAMESPACE}", query="MATCH (n) RETURN n.name LIMIT 10")
```

Load data (create nodes and relationships via Cypher):
```
mcp__falkordb__query_graph(graphName="{NAMESPACE}", query="MERGE (n:Entity {id: '1', name: 'example'})")
mcp__falkordb__query_graph(graphName="{NAMESPACE}", query="MATCH (a:Entity {id: '1'}), (b:Entity {id: '2'}) MERGE (a)-[:RELATES_TO]->(b)")
```

**If `mcp__falkordb__*` tools are NOT available — ask the user:**

> "FalkorDB MCP is not enabled. Enabling it cuts query token cost ~70% (1 tool call instead of Python subprocess + parsing).
>
> **Enable now (recommended):**
> 1. Copy `.mcp.json.example` → `.mcp.json` in your project root
> 2. Edit `.mcp.json`: set `FALKORDB_PORT` to `54010` under the `falkordb` server env
> 3. Restart Claude Code to load the MCP server
>
> **Skip for now:** I'll use Python instead — you can enable MCP later for future sessions."

If the user enables MCP and restarts, proceed with MCP tools.
If the user skips, use the Python fallback:
```python
from falkordb import FalkorDB
db = FalkorDB(host='localhost', port=54010)
g = db.select_graph('{NAMESPACE}')
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
> 2. Edit `.mcp.json`: update the MongoDB `--connectionString` arg — replace `27017` with `54011`
> 3. Restart Claude Code to load the MCP server
>
> **Skip for now:** I'll use Python instead."

If the user skips, use the Python fallback:
```python
from pymongo import MongoClient
client = MongoClient('mongodb://lqc:lqcpass@localhost:54011/')
db = client['{NAMESPACE}']
```

#### PostgreSQL

**If `mcp__postgres__*` tools are available:**

Run SQL directly:
```
mcp__postgres__query(sql="SET search_path TO {NAMESPACE}; SELECT * FROM my_table LIMIT 10")
mcp__postgres__query(sql="SET search_path TO {NAMESPACE}; SELECT column_name, data_type FROM information_schema.columns WHERE table_name='my_table'")
```

Note: `mcp__postgres__query` is **read-only**. For `CREATE TABLE`, `INSERT`, or `COPY` operations, use the Python psycopg2 fallback.

**If `mcp__postgres__*` tools are NOT available — ask the user:**

> "Postgres MCP is not enabled. Enabling it lets me run SQL queries directly (read-only) without Python subprocess overhead.
>
> **Enable now (recommended):**
> 1. Copy `.mcp.json.example` → `.mcp.json` in your project root
> 2. Edit `.mcp.json`: update the Postgres connection string — replace `5432` with `54012`
> 3. Restart Claude Code to load the MCP server
>
> **Skip for now:** I'll use Python instead. Note: Python fallback supports writes (INSERT/COPY) too."

If the user skips, use the Python fallback:
```python
import psycopg2
conn = psycopg2.connect(host='localhost', port=54012, dbname='lqcdata', user='lqc', password='lqcpass')
cur = conn.cursor()
cur.execute(f"SET search_path TO {'{NAMESPACE}'}")
```

### Step 6: Provide connection string and next steps

Tell the user the connection string, whether MCP or Python path is active, and how to load their data. Include a data-loading snippet.

## Namespace tracking

After creating a namespace, append to `~/.claude/lqc-tokens.local.md`:

```yaml
---
session_id: {ISOLATION_ID}     # only for session level, omit for request/user
isolated_namespaces:
  - db: {falkordb|mongodb|postgres}
    level: {session|request|user}
    namespace: {NAMESPACE}
    port: {base-port}
    started: "{ISO-8601-timestamp}"
---
```

If the file doesn't exist, create it. If it exists, merge: update `session_id` if new, append to `isolated_namespaces`. Use this snippet:

```bash
python3 - "$NAMESPACE" "$DB" "$ISOLATION_LEVEL" "$BASE_PORT" <<'EOF'
import sys, re, os
from datetime import datetime, timezone

namespace, db, level, port = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = os.path.expanduser('~/.claude/lqc-tokens.local.md')
entry = {'db': db, 'level': level, 'namespace': namespace, 'port': int(port),
         'started': datetime.now(timezone.utc).isoformat()}

if os.path.exists(p):
    with open(p) as f:
        raw = f.read()
    m = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
    if m:
        pre, fm_text, close, rest = m.groups()
        try:
            import yaml
            fm = yaml.safe_load(fm_text) or {}
            if level == 'session' and 'session_id' not in fm:
                # session_id already written in Step 3
                pass
            ns_list = fm.get('isolated_namespaces') or []
            ns_list.append(entry)
            fm['isolated_namespaces'] = ns_list
            new_fm = yaml.dump(fm, default_flow_style=False, sort_keys=False)
            with open(p, 'w') as f:
                f.write(pre + new_fm + close + rest)
            sys.exit(0)
        except ImportError:
            pass

# Fallback or new file
import json
with open(p, 'a') as f:
    f.write(f'\n# namespace: {json.dumps(entry)}\n')
EOF
```

**Request-scoped cleanup (do immediately after the turn ends):**

For FalkorDB:
```bash
docker exec lqc-base-falkordb redis-cli GRAPH.DELETE {NAMESPACE}
```
For MongoDB:
```bash
docker exec lqc-base-mongodb mongosh --eval "db.getSiblingDB('{NAMESPACE}').dropDatabase()" --quiet
```
For PostgreSQL:
```bash
docker exec lqc-base-postgres psql -U lqc -d lqcdata -c "DROP SCHEMA IF EXISTS {NAMESPACE} CASCADE;"
```
Then remove the entry from `isolated_namespaces`.

**Session-scoped cleanup:** handled automatically by the SessionEnd hook.

**User-scoped cleanup:** tell the user to run the drop command manually when done.
