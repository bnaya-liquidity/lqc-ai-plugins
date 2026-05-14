---
name: lqc-docker-advisor
description: Recommends a database strategy for data-heavy tasks and generates Docker setup. Use when the user's prompt contains `@path.csv`, `@path.xlsx`, `@path.json`, `@path.yaml`, or any `@` file reference with a data extension (csv, tsv, xls, xlsx, json, yaml, yml, parquet). Also use when the user wants to "load data into a database", "analyze a large dataset", pastes large data, says "read the following document", asks to query/filter/aggregate data files (e.g. "list the top N", "find all X with Y", "give me the companies and products with the highest"), mentions scraping or downloading web data, needs to process many files, or when the pre-prompt hook detects a data-task pattern. Also use when the user asks which database to use for a given workload.
argument-hint: "[describe your data: shape, size, access patterns, session longevity]"
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# Docker Data Advisor

Offload data tasks to a Docker-hosted database instead of reading files into the context window. Saves 80–95% of context tokens for data-heavy tasks.

**This skill executes the full workflow end-to-end** — it inspects data, chooses a database, gets a single approval, then spins up Docker, loads data, runs the query, and delivers the answer. Minimal user interaction by design.

---

## Progress Protocol (MANDATORY — follow throughout every step)

Before every tool call, output a status block so the user can follow what is happening and why. These blocks must appear as text output (not inside bash), so they render as formatted markdown above the raw tool output.

**Use this visual format consistently:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {EMOJI}  {STEP LABEL}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {content lines}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Emoji key:**
- `🔍` — Inspecting / reading
- `🧭` — Decision / classification  
- `📋` — Plan summary
- `🐳` — Docker container operation
- `🏗️` — Schema / table creation
- `📥` — Loading data
- `⚡` — Running query
- `📊` — Results
- `✅` — Step completed
- `⚠️` — Warning / error

**Rules:**
1. Output the block **before** the tool call, not after
2. Always state **what** is happening AND **why** (the reasoning, not just the action)
3. After a step completes with a notable result, follow up with a one-line `✅` or `⚠️` summary
4. Never skip a block — even for trivial operations like "checking if container is running"
5. Decision blocks (🧭) must include explicit rationale: which signals triggered which choice

---

## Step 0: Detect and announce

Scan the current prompt for data-task signals:
- `@` file references with data extensions: `.csv`, `.tsv`, `.xls`, `.xlsx`, `.json`, `.ndjson`, `.yaml`, `.yml`, `.parquet`
- Bare file paths ending in those extensions
- Analytical verbs combined with data files ("give me the top N", "list", "find all", "aggregate", "filter", "compare", "group by")
- Phrases: "read the following document", "here is the data", "analyze this report", "I scraped"

**If signals detected**, open with:

```
⚡ docker-advisor
──────────────────────────────────────────────
Data task detected. Loading files into context directly would cost
~[N files × avg size ÷ 4] tokens. Offloading to Docker: ~2K tokens (80–95% savings).
──────────────────────────────────────────────
```

**If no signals detected** (skill invoked manually), ask what data the user has before proceeding.

### Session start: existing data safety check

**This check runs ONCE per session, before Step 1, only when a data task is first detected.**

After announcing the data task, run:

```bash
python3 - <<'EOF'
import re, os, subprocess, json

p = os.path.expanduser('~/.claude/lqc-optimizer.local.md')
session_id = None
namespaces = []

if os.path.exists(p):
    with open(p) as f:
        raw = f.read()
    m = re.match(r'^---\n(.*?)---', raw, re.DOTALL)
    if m:
        try:
            import yaml
            fm = yaml.safe_load(m.group(1)) or {}
            session_id = fm.get('session_id')
            namespaces = fm.get('isolated_namespaces') or []
        except ImportError:
            pass

# Check which lqc containers are running
try:
    out = subprocess.check_output(
        ['docker', 'ps', '--filter', 'name=lqc-base', '--format', '{{.Names}}'],
        text=True
    ).strip()
    running = [l for l in out.splitlines() if l]
except Exception:
    running = []

if session_id and running:
    print(json.dumps({'session_id': session_id, 'namespaces': namespaces, 'running': running}))
else:
    print('clean')
EOF
```

**If the output is `clean`** → proceed directly to Step 1, no prompt needed.

**If the output is a JSON object** (existing session + running containers detected), show:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚠️  Existing session data found
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Session   : {session_id}
  Databases : {running containers, comma-separated}
  Namespace : {namespaces[0].namespace if any}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then ask (using AskUserQuestion):

```
question: "Data from a previous session is already loaded. What would you like to do?"
header: "Existing data"
multiSelect: false
options:
  - label: "Reuse existing data"
    description: "Skip loading — query the data already in the database."
  - label: "Clean and start fresh"
    description: "Drop all namespaces, clear session state, reload from scratch."
```

**If "Reuse existing data":** set `NAMESPACE` from the stored session_id, skip Steps 1–7, go directly to Step 2d to classify and run the query.

**If "Clean and start fresh":** run the cleanup script below, then continue from Step 1 normally.

```bash
python3 - <<'EOF'
import re, os, subprocess

p = os.path.expanduser('~/.claude/lqc-optimizer.local.md')
if not os.path.exists(p):
    print("Nothing to clean.")
    exit(0)

with open(p) as f:
    raw = f.read()

session_id = None
namespaces = []
m = re.match(r'^---\n(.*?)---', raw, re.DOTALL)
if m:
    try:
        import yaml
        fm = yaml.safe_load(m.group(1)) or {}
        session_id = fm.get('session_id')
        namespaces = fm.get('isolated_namespaces') or []
    except ImportError:
        pass

# Drop PostgreSQL namespaces
for ns in namespaces:
    if ns.get('db') == 'postgres':
        namespace = ns['namespace']
        port = ns.get('port', 54012)
        try:
            subprocess.run(
                ['docker', 'exec', 'lqc-base-postgres', 'psql', '-U', 'lqc', '-d', 'lqcdata',
                 '-c', f'DROP SCHEMA IF EXISTS "{namespace}" CASCADE;'],
                check=True, capture_output=True
            )
            print(f"Dropped PostgreSQL schema: {namespace}")
        except Exception as e:
            print(f"Warning: could not drop {namespace}: {e}")

# Drop FalkorDB graphs
for ns in namespaces:
    if ns.get('db') == 'falkordb':
        namespace = ns['namespace']
        try:
            subprocess.run(
                ['docker', 'exec', 'lqc-base-falkordb', 'redis-cli', 'GRAPH.DELETE', namespace],
                check=True, capture_output=True
            )
            print(f"Dropped FalkorDB graph: {namespace}")
        except Exception as e:
            print(f"Warning: could not drop {namespace}: {e}")

# Drop MongoDB databases
for ns in namespaces:
    if ns.get('db') == 'mongodb':
        namespace = ns['namespace']
        try:
            subprocess.run(
                ['docker', 'exec', 'lqc-base-mongodb', 'mongosh', '--username', 'lqc',
                 '--password', 'lqcpass', '--eval', f'db.getSiblingDB("{namespace}").dropDatabase()'],
                check=True, capture_output=True
            )
            print(f"Dropped MongoDB database: {namespace}")
        except Exception as e:
            print(f"Warning: could not drop {namespace}: {e}")

# Clear session state from local.md
m2 = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
if m2:
    try:
        import yaml
        pre, fm_text, close, rest = m2.groups()
        fm = yaml.safe_load(fm_text) or {}
        fm.pop('session_id', None)
        fm['isolated_namespaces'] = []
        with open(p, 'w') as f:
            f.write(pre + yaml.dump(fm, default_flow_style=False, sort_keys=False) + close + rest)
        print("Session state cleared.")
    except ImportError:
        pass
EOF
```

After cleanup, output: `✅ All previous session data cleared — starting fresh.`

---

### Follow-up queries in an existing session

If data was already loaded in a prior turn (namespace exists, containers running), re-evaluate the query type before answering:

1. **Check what databases are already running** (`docker ps --filter name=lqc-base`)
2. **Re-classify the new query** using the Step 2d table — the question type may have shifted (e.g. first query was metric ranking → now it's relationship frequency)
3. **If the new query is a graph query but only PostgreSQL is running:**
   - Load the edge/entity tables into FalkorDB now
   - Run the query in Cypher, not SQL
   - Do NOT answer a relationship question with a SQL JOIN on a BOM table just because PostgreSQL is already set up
4. **If FalkorDB is already running**, prefer Cypher for any relationship or pattern question

---

## Step 1: Inspect the data files

**Output before running:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🔍  Inspecting data files
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Reading headers and row counts — no file content enters the context.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

For each data file referenced in the prompt, run these commands:

```bash
head -1 {file_path}    # read column names
wc -l {file_path}      # count rows
```

From the headers and row counts, classify each file:

**Edge table detection** — a file is an edge table (graph structure) if:
- It has ≤ 3 columns total
- Its first two columns are both `*_id` columns that reference the same entity type
  (e.g. `parent_product_id` + `component_product_id`, `from_id` + `to_id`, `company_id` + `supplier_id`)
- The optional third column is a weight or label (`quantity`, `weight`, `cost`, `rel_type`)

**Self-referential / hierarchical detection** — a file is hierarchical if it has both `parent_{X}_id` and `{X}_id` columns, implying a recursive tree or DAG.

**Auto-select databases** using `references/db-selection-guide.md`:

| Files detected | Database choice |
|---|---|
| Any edge table or self-referential file | **FalkorDB** for the graph |
| Flat fact/metric tables with pre-computed aggregates | **PostgreSQL** for analytics |
| Both graph + analytics files | **FalkorDB + PostgreSQL** (multi-DB) |
| Only flat relational tables, no graph | **PostgreSQL** only |
| Nested/variable-schema JSON | **MongoDB** |

**Multi-DB is allowed and preferred** when data has both graph structure and analytics tables. Spin up both containers; load each file into the right database.

**Output after inspecting all files** (before moving to Step 2):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🧭  Database selection decision
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {filename}  →  {db icon} {DB}  — {classification} ({signal that triggered it})
  {filename}  →  {db icon} {DB}  — {classification}
  ...

  {Chosen DB(s)}: {reason in 1–2 sentences. E.g.:
    "bill_of_materials has two *_id columns referencing the same product entity —
     classic adjacency list. FalkorDB handles recursive traversal natively.
     The three analytics tables are flat with pre-computed metrics → PostgreSQL."}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Use these db icons: `⬡` for FalkorDB, `🐘` for PostgreSQL, `🍃` for MongoDB.

---

## Step 2: Build the full execution plan

Before asking for approval, construct the complete plan:

### 2a: Classify each file

For every file:
- Is it an **edge table**? → load into FalkorDB as relationships. **ALWAYS. Never skip.**
- Is it an **entity table** (entities referenced by edge tables)? → load into FalkorDB as nodes
- Is it a **flat analytics/metric table** (pre-computed aggregates, no graph structure)? → load into PostgreSQL

**Hard rule: edge tables are NEVER skipped, even when the current query uses only pre-computed columns.**
Graph data must be loaded into FalkorDB upfront because:
1. Follow-up queries will ask about relationships — re-loading wastes time and confuses the user
2. The question type can change mid-session (aggregation → traversal → pattern frequency)
3. An edge table that "isn't needed now" is almost always needed within 2–3 follow-ups

If the current query can be answered from pre-computed columns alone, answer it via PostgreSQL AND load the edge table into FalkorDB in parallel — mark it as "loaded for follow-up" in the execution plan.

### 2b: Infer column types (for PostgreSQL tables)

Use this rule on each column name (case-insensitive):
- Ends with `_id`, `_count`, `_depth`, `_price`, `_cost`, `_percent`, `_quantity`, `quantity`, `_amount`, `_rate`, `_score`, `_size` → `NUMERIC`
- Otherwise → `TEXT`

### 2c: Plan FalkorDB loading (for graph files)

For each entity table going into FalkorDB, map columns to node properties.
For each edge table, identify:
- Source node label + ID column (e.g. `parent_product_id` → `Product` node)
- Target node label + ID column (e.g. `component_product_id` → `Product` node)
- Relationship type (derive from filename: `bill_of_materials` → `CONTAINS`)
- Edge property column (e.g. `quantity`)

### 2d: Build the answer query

Classify the user's question into one of these query types, then pick the right tool:

| Question type | Signal phrases | Right tool | Example query |
|---|---|---|---|
| Pre-computed metric ranking | "top N", "highest", "most X", column already exists in analytics table | SQL | `ORDER BY col DESC LIMIT N` |
| Multi-hop traversal | "all components of X", "find dependencies", "trace the chain", "at any depth" | Cypher | `MATCH (p)-[:REL*]->(c)` |
| Shortest / any path | "path between", "how are X and Y connected", "degrees of separation" | Cypher | `shortestPath((a)-[*]-(b))` |
| **Relationship frequency / pattern** | **"most common combination", "most frequent pair", "which X and Y appear together most", "most used component", "which relationship is most common"** | **Cypher** | **`MATCH (a)-[r]->(b) RETURN a.prop, b.prop, COUNT(*) ORDER BY COUNT(*) DESC`** |
| Degree / centrality | "most connected", "used in the most products", "which node has most edges" | Cypher | `MATCH (n)<-[r]-() RETURN n, COUNT(r) ORDER BY COUNT(r) DESC` |
| Graph + metric join | question needs both relationship structure AND pre-computed scores | Cypher + SQL joined in Python | run both, merge on id |

**Key signal:** any question about which *pair*, *combination*, or *relationship* is most common is a graph pattern frequency query — even if it could be answered with SQL GROUP BY on a joined BOM table. FalkorDB's Cypher is the idiomatic choice because the question is fundamentally about the graph structure.

---

## Step 3: Single approval gate

Show the complete plan in one block:

```
⚡ Execution Plan
──────────────────────────────────────────────
Databases: {e.g. FalkorDB (graph) + PostgreSQL (analytics)}
           Session-scoped — you'll be asked at exit whether to keep or clear

Files → databases:
  {filename1} → FalkorDB  (nodes: {label}, {N} entities)
  {filename2} → FalkorDB  (edges: CONTAINS, {N} relationships)
  {filename3} → PostgreSQL  (table: {table}, {N} rows)
  ...

Query:
  {the full Cypher or SQL query, nicely formatted}
  {if multi-DB: show both the graph query and the metrics query}

Token savings: reading files into context ≈ {M}K tokens
               Docker path ≈ 2K tokens
──────────────────────────────────────────────
```

Then ask once:

```
question: "Proceed with this plan?"
header: "Confirm"
multiSelect: false
options:
  - label: "Yes, proceed"
    description: "Spin up Docker, load data, run the query, show results."
  - label: "Adjust the plan first"
    description: "Tell me what to change before I start."
  - label: "Cancel"
    description: "Skip — I'll handle this another way."
```

If the user chooses "Adjust", update the plan based on their feedback, show the revised plan, and ask again.

If the user chooses "Cancel", stop.

---

## Step 4: Generate namespace

**Output before running:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🐳  Setting up session namespace
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Generating a session-scoped ID. All data will be isolated under this
  namespace and you'll be asked at session exit whether to keep or clear it.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Get or create a session-scoped ID:

```bash
python3 - <<'EOF'
import re, os, uuid, sys
p = os.path.expanduser('~/.claude/lqc-optimizer.local.md')
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

If this prints a new ID, save it:

```bash
python3 - "$ISOLATION_ID" <<'EOF'
import sys, re, os
new_id = sys.argv[1]
p = os.path.expanduser('~/.claude/lqc-optimizer.local.md')
content = None
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
with open(p, 'w') as f:
    f.write(f'---\nsession_id: {new_id}\nisolated_namespaces: []\n---\n\nManaged by lqc-optimizer. Do not edit manually.\n')
EOF
```

Set `NAMESPACE=lqc_{ISOLATION_ID}` (e.g. `lqc_sess_a1b2c3d4`).

---

## Step 5: Start the database container

### 5a: Write docker-compose file

Write `docker-compose.lqc-base.yml` to the project root (idempotent — safe to overwrite):

**For PostgreSQL:**
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

**For FalkorDB:**
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

**For MongoDB:**
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

### 5b: Start the container

**Output before checking/starting each container:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🐳  Starting {DB} container
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Container : lqc-base-{db}
  Image     : {image}
  Port      : {host_port} → {container_port}
  Namespace : {NAMESPACE}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

```bash
docker ps --filter "name=lqc-base-{db}" --format "{{.Names}}"
```

If not running:
```bash
docker compose -f docker-compose.lqc-base.yml up -d --wait
```

After the container starts, output:
```
✅  lqc-base-{db} is healthy — ready to receive data
```

If Docker is not running, output a `⚠️` block explaining the issue and stop — do not proceed.

---

## Step 6: Create schema and tables (PostgreSQL)

**Output before running:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🏗️  Creating schema and tables
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Schema : {NAMESPACE}

  {table1}  ({N} cols)
    {col}: NUMERIC  {col}: TEXT  ...

  {table2}  ({N} cols)
    {col}: NUMERIC  ...

  Type inference: columns ending in _id/_count/_price/etc → NUMERIC, rest → TEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 6a: Create the schema (namespace)

```bash
docker exec lqc-base-postgres psql -U lqc -d lqcdata \
  -c "CREATE SCHEMA IF NOT EXISTS {NAMESPACE};"
```

### 6b: Create tables

Use a Python script to infer column types from the CSV headers and create the tables:

```bash
python3 << 'PYEOF'
import csv, psycopg2, os

NAMESPACE = "{NAMESPACE}"
files = {
    "{table1}": "{absolute_path_to_file1}",
    "{table2}": "{absolute_path_to_file2}",
    # ... one entry per file
}

NUMERIC_SUFFIXES = (
    '_id', '_count', '_depth', '_price', '_cost', '_percent',
    '_quantity', 'quantity', '_amount', '_rate', '_score', '_size'
)

def infer_type(col):
    col_lower = col.lower()
    if any(col_lower.endswith(s) for s in NUMERIC_SUFFIXES):
        return 'NUMERIC'
    return 'TEXT'

conn = psycopg2.connect(host='localhost', port=54012, dbname='lqcdata', user='lqc', password='lqcpass')
cur = conn.cursor()

for table, path in files.items():
    with open(path) as f:
        headers = next(csv.reader(f))
    col_defs = ', '.join(f'"{h}" {infer_type(h)}' for h in headers)
    cur.execute(f'DROP TABLE IF EXISTS {NAMESPACE}."{table}";')
    cur.execute(f'CREATE TABLE {NAMESPACE}."{table}" ({col_defs});')
    print(f"Created {NAMESPACE}.{table} ({len(headers)} columns)")

conn.commit()
conn.close()
PYEOF
```

If `psycopg2` is not installed:
```bash
pip install psycopg2-binary -q
```

---

## Step 7: Load data

**Output before loading each file:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📥  Loading data  ({X} of {total} files)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {filename}  →  {NAMESPACE}.{table}  (~{N} rows)
  Method: docker exec -i psql COPY (streams from host fs, zero context cost)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

After all files load, output:
```
✅  All files loaded
    {table1}: {N} rows  |  {table2}: {N} rows  |  {table3}: {N} rows  ...
```

For each CSV file, stream it directly into PostgreSQL using `docker exec -i` with stdin redirect. This avoids reading the file into Python memory:

```bash
docker exec -i lqc-base-postgres \
  psql -U lqc -d lqcdata \
  -c "\COPY {NAMESPACE}.\"{table_name}\" FROM STDIN WITH (FORMAT CSV, HEADER true)" \
  < "{absolute_file_path}"
```

Run this command for every file. After loading all files, verify row counts:

```bash
python3 << 'PYEOF'
import psycopg2
conn = psycopg2.connect(host='localhost', port=54012, dbname='lqcdata', user='lqc', password='lqcpass')
cur = conn.cursor()
for table in ["{table1}", "{table2}"]:  # all loaded tables
    cur.execute(f'SELECT count(*) FROM {"{NAMESPACE}"}."{table}"')
    print(f"{table}: {cur.fetchone()[0]} rows")
conn.close()
PYEOF
```

---

## Step 8: Execute the query and deliver the answer

**Output before running:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚡  Running query
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  {SQL or Cypher query, syntax-highlighted in a code block}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Run the query built in Step 2d:

```bash
python3 << 'PYEOF'
import psycopg2

conn = psycopg2.connect(host='localhost', port=54012, dbname='lqcdata', user='lqc', password='lqcpass')
cur = conn.cursor()

sql = """
SET search_path TO {NAMESPACE};

{THE FULL SQL QUERY FROM STEP 2c}
"""

cur.execute(sql)
rows = cur.fetchall()
cols = [d[0] for d in cur.description]
conn.close()

# Print formatted table
widths = [max(len(str(c)), max((len(str(r[i])) for r in rows), default=0)) for i, c in enumerate(cols)]
header = ' | '.join(str(c).ljust(w) for c, w in zip(cols, widths))
divider = '-+-'.join('-' * w for w in widths)
print(header)
print(divider)
for row in rows:
    print(' | '.join(str(v).ljust(w) for v, w in zip(row, widths)))
print(f"\n({len(rows)} rows)")
PYEOF
```

After showing the raw results, output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📊  Answer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
Then summarize the answer in plain language directly addressing the user's original question.
Close with:
```
  Data remains loaded in {DB(s)} under namespace {NAMESPACE}.
  You'll be asked at session exit whether to keep or clear it.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Step 9: Namespace tracking

After loading data, record the namespace in `~/.claude/lqc-optimizer.local.md`:

```bash
python3 - "{NAMESPACE}" "postgres" "session" "54012" <<'EOF'
import sys, re, os
from datetime import datetime, timezone

namespace, db, level, port = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = os.path.expanduser('~/.claude/lqc-optimizer.local.md')
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
            ns_list = fm.get('isolated_namespaces') or []
            if not any(n.get('namespace') == namespace for n in ns_list):
                ns_list.append(entry)
            fm['isolated_namespaces'] = ns_list
            with open(p, 'w') as f:
                f.write(pre + yaml.dump(fm, default_flow_style=False, sort_keys=False) + close + rest)
            sys.exit(0)
        except ImportError:
            pass

import json
with open(p, 'a') as f:
    f.write(f'\n# namespace: {json.dumps(entry)}\n')
EOF
```

The data stays available for the rest of this session. The SessionEnd hook will clean it up automatically.

---

## Handling FalkorDB (graph data)

**Output before loading nodes:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  📥  Loading graph into FalkorDB
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Graph     : {NAMESPACE}
  Nodes     : {entity_file}  →  :{Label}  ({N} nodes)
  Edges     : {edge_file}    →  [:{REL_TYPE}]  ({N} relationships)
  Strategy  : MERGE on id — safe to re-run (idempotent)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If the selected database is FalkorDB, use Python to load data:

```bash
pip install falkordb -q
python3 << 'PYEOF'
from falkordb import FalkorDB
db = FalkorDB(host='localhost', port=54010)
g = db.select_graph('{NAMESPACE}')

# Load nodes (example for a node CSV with id, name, type columns)
import csv
with open('{file_path}') as f:
    for row in csv.DictReader(f):
        g.query(
            "MERGE (n:Entity {id: $id}) SET n.name = $name, n.type = $type",
            {'id': row['id'], 'name': row['name'], 'type': row['type']}
        )

# Load edges (example for an edge CSV with from_id, to_id, rel_type)
with open('{edge_file_path}') as f:
    for row in csv.DictReader(f):
        g.query(
            "MATCH (a:Entity {id: $from_id}), (b:Entity {id: $to_id}) MERGE (a)-[:RELATES_TO]->(b)",
            {'from_id': row['from_id'], 'to_id': row['to_id']}
        )
print("Graph loaded")
PYEOF
```

Then query with Cypher:

```bash
python3 << 'PYEOF'
from falkordb import FalkorDB
db = FalkorDB(host='localhost', port=54010)
g = db.select_graph('{NAMESPACE}')
result = g.query("{THE CYPHER QUERY}")
for row in result.result_set:
    print(row)
PYEOF
```

---

## Error handling

- **Docker not found or not running**: tell the user to start Docker Desktop and retry.
- **Port already in use** (54012, 54011, 54010): check with `docker ps -a`, stop the conflicting container, or offer to use a different port.
- **psycopg2 install fails**: try `pip3 install psycopg2-binary --break-system-packages` (needed on macOS with system Python) or `pip install --user psycopg2-binary`.
- **COPY fails with type error**: the file may have non-numeric values in a column inferred as NUMERIC. Drop and recreate the table with that column as TEXT, then reload.
- **File path issues**: always use absolute paths. If the user gave a relative path, resolve it with `pwd` first.
