# Docker Spinup Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace per-use container spinup with a shared long-lived base container per DB type, isolating each session/request/user via lightweight namespaces (Postgres schemas, FalkorDB graph names, MongoDB databases).

**Architecture:** One `lqc-base-{db}` container runs persistently on a fixed port. Each docker-advisor invocation creates a namespace inside it (< 10ms) instead of starting a new container (2–5s). The user picks an isolation level — session (recommended), request, or user — with session pre-selected so they can press Enter to accept. Session namespaces are dropped by the SessionEnd hook; request namespaces are dropped immediately after the turn; user namespaces persist until manual cleanup.

**Tech Stack:** Bash, Docker Compose v2 (--wait), PostgreSQL schemas, FalkorDB graph names, MongoDB database names, PyYAML, lqc-tokens plugin skill Markdown

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `plugins/lqc-tokens/skills/docker-advisor/references/isolation-patterns.md` | Create | DB-specific create/drop commands + base container port table |
| `plugins/lqc-tokens/skills/docker-advisor/SKILL.md` | Modify | Replace longevity/ephemeral flow (Steps 3–4 + tracking) with isolation level flow |
| `plugins/lqc-tokens/skills/setup/lqc-tokens.local.md.example` | Modify | Add `session_id` + `isolated_namespaces` fields; retire `ephemeral_containers` |
| `plugins/lqc-tokens/hooks/session-end.sh` | Modify | Add namespace cleanup for session-scoped data; keep container-stop for backward compat |
| `plugins/lqc-tokens/skills/eval/eval-workspace/evals/evals.json` | Modify | Add eval 8 for isolation level prompt + namespace creation |
| `plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark-pre-isolation.json` | Create | Pre-optimization baseline (container-per-use) |

---

## Task 1: Create isolation-patterns.md

**Files:**
- Create: `plugins/lqc-tokens/skills/docker-advisor/references/isolation-patterns.md`

- [ ] **Step 1: Write the file**

```markdown
# Isolation Patterns

Shared base containers serve all sessions/requests via isolated namespaces.
No container startup cost after the first use.

## Base Container Config

| DB | Container name | Host port | Internal port | Volume |
|---|---|---|---|---|
| FalkorDB | `lqc-base-falkordb` | 54010 | 6379 | `lqc-base-falkordb-data` |
| MongoDB | `lqc-base-mongodb` | 54011 | 27017 | `lqc-base-mongodb-data` |
| PostgreSQL | `lqc-base-postgres` | 54012 | 5432 | `lqc-base-postgres-data` |

## Namespace ID Format

| Level | Format | Lifecycle |
|---|---|---|
| session | `sess_{8-char-uuid}` | Generated once per session, stored in `lqc-tokens.local.md` as `session_id`. Cleaned by SessionEnd hook. |
| request | `req_{8-char-uuid}` | Generated fresh per prompt. Cleaned immediately after the turn. |
| user | `user_{project-slug}` | Project slug = last segment of `pwd` lowercased, alphanumeric only. Persists until manual cleanup. |

**Namespace name:** `lqc_{id}` — e.g. `lqc_sess_a1b2c3d4`, `lqc_req_ff2e9a01`, `lqc_user_myapp`

## FalkorDB — graph-name isolation

Each namespace is a separate graph (graphs are the isolation unit in FalkorDB).
Graph is created implicitly on first write.

**Namespace graph name:** `lqc_{id}` (e.g. `lqc_sess_a1b2c3d4`)

**Use namespace (MCP path):**
```
mcp__falkordb__query_graph(graphName="lqc_{id}", query="MERGE (n:Entity {name: 'example'})")
mcp__falkordb__query_graph_readonly(graphName="lqc_{id}", query="MATCH (n) RETURN n.name LIMIT 10")
```

**Use namespace (Python path):**
```python
from falkordb import FalkorDB
db = FalkorDB(host='localhost', port=54010)
g = db.select_graph('lqc_{id}')
```

**Drop namespace (for cleanup):**
```bash
docker exec lqc-base-falkordb redis-cli GRAPH.DELETE lqc_{id}
```

**Drop via MCP:**
```
mcp__falkordb__delete_graph(graphName="lqc_{id}", confirmDelete=true)
```

## MongoDB — database-level isolation

Each namespace is a separate MongoDB database.
Database is created on first write.

**Namespace database name:** `lqc_{id}`

**Use namespace (MCP path):**
```
mcp__mongodb__find(collection="lqc_{id}.tickets", filter={}, limit=20)
```
Note: MongoDB MCP tools accept `database.collection` dot notation or configure the server with `--connectionString` pointing to the specific database.

**Use namespace (Python path):**
```python
from pymongo import MongoClient
client = MongoClient('mongodb://lqc:lqcpass@localhost:54011/')
db = client['lqc_{id}']
```

**Drop namespace (for cleanup):**
```bash
docker exec lqc-base-mongodb mongosh --eval "db.getSiblingDB('lqc_{id}').dropDatabase()" --quiet
```

## PostgreSQL — schema-level isolation

Each namespace is a schema within the `lqcdata` database.
All tables created during the session live inside the schema.

**Namespace schema name:** `lqc_{id}`

**Create schema:**
```bash
docker exec lqc-base-postgres psql -U lqc -d lqcdata -c "CREATE SCHEMA IF NOT EXISTS lqc_{id};"
```

**Use namespace (MCP path):**
```
mcp__postgres__query(sql="SET search_path TO lqc_{id}; SELECT * FROM my_table LIMIT 10")
```

**Use namespace (Python path):**
```python
import psycopg2
conn = psycopg2.connect(host='localhost', port=54012, dbname='lqcdata', user='lqc', password='lqcpass')
cur = conn.cursor()
cur.execute("SET search_path TO lqc_{id}")
```

**Drop namespace (for cleanup):**
```bash
docker exec lqc-base-postgres psql -U lqc -d lqcdata -c "DROP SCHEMA IF EXISTS lqc_{id} CASCADE;"
```
```

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/skills/docker-advisor/references/isolation-patterns.md
git commit -m "docs: add isolation-patterns reference (base containers + namespace create/drop)"
```

---

## Task 2: Update lqc-tokens.local.md.example

**Files:**
- Modify: `plugins/lqc-tokens/skills/setup/lqc-tokens.local.md.example`

- [ ] **Step 1: Replace file content**

```markdown
---
session_id: sess_a1b2c3d4
isolated_namespaces:
  - db: falkordb
    level: session
    namespace: lqc_sess_a1b2c3d4
    port: 54010
    started: "2026-05-13T10:30:00Z"
  - db: postgres
    level: request
    namespace: lqc_req_ff2e9a01
    port: 54012
    started: "2026-05-13T10:31:00Z"
ephemeral_containers: []
---

Managed by lqc-tokens plugin. Do not edit manually.
```

Note: `ephemeral_containers` kept (empty) for backward compatibility with existing session-end.sh logic.

- [ ] **Step 2: Commit**

```bash
git add plugins/lqc-tokens/skills/setup/lqc-tokens.local.md.example
git commit -m "feat: add session_id + isolated_namespaces to lqc-tokens.local.md schema"
```

---

## Task 3: Update session-end.sh — add namespace cleanup

**Files:**
- Modify: `plugins/lqc-tokens/hooks/session-end.sh`

- [ ] **Step 1: Replace session-end.sh with the new version**

The new version: (1) drops session-scoped namespaces before doing the existing container teardown, (2) keeps backward-compat container teardown unchanged.

```bash
#!/usr/bin/env bash
# Cleans up session-scoped isolated namespaces and any tracked ephemeral containers.

SETTINGS_FILE="${CLAUDE_WORKSPACE_DIR:-$HOME}/.claude/lqc-tokens.local.md"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  exit 0
fi

# ── 1. Drop session-scoped isolated namespaces ───────────────────────────────

python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re, subprocess, json

path = sys.argv[1]
with open(path) as f:
    raw = f.read()

match = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
if not match:
    sys.exit(0)

pre, fm_text, close, rest = match.groups()

try:
    import yaml
    fm = yaml.safe_load(fm_text) or {}
except ImportError:
    sys.exit(0)

namespaces = fm.get('isolated_namespaces', [])
remaining = []

for ns in namespaces:
    if ns.get('level') != 'session':
        remaining.append(ns)
        continue
    db = ns.get('db', '')
    namespace = ns.get('namespace', '')
    if not namespace:
        continue

    if db == 'falkordb':
        cmd = ['docker', 'exec', 'lqc-base-falkordb', 'redis-cli', 'GRAPH.DELETE', namespace]
    elif db == 'mongodb':
        cmd = ['docker', 'exec', 'lqc-base-mongodb', 'mongosh',
               '--eval', f"db.getSiblingDB('{namespace}').dropDatabase()", '--quiet']
    elif db == 'postgres':
        cmd = ['docker', 'exec', 'lqc-base-postgres', 'psql',
               '-U', 'lqc', '-d', 'lqcdata',
               '-c', f"DROP SCHEMA IF EXISTS {namespace} CASCADE;"]
    else:
        remaining.append(ns)
        continue

    result = subprocess.run(cmd, capture_output=True)
    if result.returncode == 0:
        print(f'lqc-tokens: dropped {db} namespace {namespace}')
    else:
        # container may be stopped already — not an error
        print(f'lqc-tokens: could not drop {namespace} (container may be stopped): {result.stderr.decode().strip()}')

# Rewrite file: clear session_id, keep only non-session namespaces
fm['session_id'] = None
fm['isolated_namespaces'] = remaining
new_fm = yaml.dump(fm, default_flow_style=False, sort_keys=False)
with open(path, 'w') as f:
    f.write(pre + new_fm + close + rest)
PYEOF

# ── 2. Backward-compat: stop tracked ephemeral containers ────────────────────

CONTAINERS=$(grep -E '^\s*- name:\s*lqc-' "$SETTINGS_FILE" | sed 's/[[:space:]]*- name:[[:space:]]*//')

if [[ -z "$CONTAINERS" ]]; then
  exit 0
fi

while IFS= read -r CONTAINER; do
  [[ -z "$CONTAINER" ]] && continue
  if docker inspect "$CONTAINER" &>/dev/null; then
    echo "lqc-tokens: stopping ephemeral container $CONTAINER"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
  fi
done <<< "$CONTAINERS"

python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    raw = f.read()

match = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
if not match:
    sys.exit(0)

pre, fm_text, close, rest = match.groups()

try:
    import yaml
    fm = yaml.safe_load(fm_text) or {}
    fm['ephemeral_containers'] = []
    new_fm = yaml.dump(fm, default_flow_style=False, sort_keys=False)
    with open(path, 'w') as f:
        f.write(pre + new_fm + close + rest)
except ImportError:
    cleared = re.sub(
        r'(ephemeral_containers:\s*\n)((?:[ \t]+.*\n)*)',
        r'\1',
        fm_text
    )
    with open(path, 'w') as f:
        f.write(pre + cleared + close + rest)
PYEOF
```

- [ ] **Step 2: Verify the script is valid bash + python**

```bash
bash -n plugins/lqc-tokens/hooks/session-end.sh
python3 -c "
import sys
# Simulate reading the namespace cleanup block
code = open('plugins/lqc-tokens/hooks/session-end.sh').read()
# Check Python block compiles
import re
blocks = re.findall(r\"python3 - .+?<<'PYEOF'(.+?)PYEOF\", code, re.DOTALL)
for b in blocks:
    compile(b, '<test>', 'exec')
print('OK: bash syntax + python blocks valid')
"
```

Expected: `OK: bash syntax + python blocks valid`

- [ ] **Step 3: Commit**

```bash
git add plugins/lqc-tokens/hooks/session-end.sh
git commit -m "feat: drop session-scoped DB namespaces at session end (postgres schema, falkordb graph, mongodb db)"
```

---

## Task 4: Update docker-advisor/SKILL.md — isolation level flow

**Files:**
- Modify: `plugins/lqc-tokens/skills/docker-advisor/SKILL.md`

This is the core skill change. Replace Step 1 longevity bullet, Step 3 (longevity question), Step 4 (generate artifacts for new container), and the "Ephemeral container tracking" section at the bottom.

- [ ] **Step 1: Replace Step 1 longevity bullet**

In the `### Step 1: Analyze the task` section, change:
```markdown
- **Longevity**: is this data needed after today's session?
```
to:
```markdown
- **Longevity**: session (default), request (single turn), or user (persist across sessions)?
```

- [ ] **Step 2: Replace Step 3 entirely**

Replace the entire `### Step 3: Ask about longevity` section with:

```markdown
### Step 3: Choose isolation level

Present the options with `session` pre-selected (user presses Enter to accept):

> "How long should this data persist?
>
> **[session]** — auto-cleaned when Claude Code closes ✓ **(default — press Enter)**
> **[request]** — deleted after this conversation turn
> **[user]** — persists across all sessions (you clean up manually)"

Based on the answer, generate the isolation ID:

**session:**
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
new_id = 'sess_' + uuid.uuid4().hex[:8]
print(new_id)
EOF
```
Save the printed ID as `ISOLATION_ID`. If it is a new ID (not found in the file), write it to `.claude/lqc-tokens.local.md` under `session_id` (create the file if absent).

**request:**
```bash
python3 -c "import uuid; print('req_' + uuid.uuid4().hex[:8])"
```

**user:**
```bash
python3 -c "import os, re; slug = re.sub(r'[^a-z0-9]', '', os.path.basename(os.getcwd()).lower()); print('user_' + (slug or 'default'))"
```

Set `NAMESPACE=lqc_{ISOLATION_ID}` (e.g. `lqc_sess_a1b2c3d4`).
```

- [ ] **Step 3: Replace Step 4 entirely**

Replace the entire `### Step 4: Generate artifacts` section with:

```markdown
### Step 4: Start base container (if needed) and create namespace

**Check if base container is already running:**
```bash
docker ps --filter "name=lqc-base-{db}" --format "{{.Names}}"
```

**If NOT running:** write `docker-compose.lqc-base.yml` using these fixed values from `references/isolation-patterns.md`:

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

Write to project root as `docker-compose.lqc-base.yml`. Then start:
```bash
docker compose -f docker-compose.lqc-base.yml up -d --wait
```

**Create the namespace** (see `references/isolation-patterns.md` for exact commands per DB):

- FalkorDB: namespace graph created implicitly on first write — no extra step
- MongoDB: database created implicitly on first write — no extra step
- PostgreSQL:
  ```bash
  docker exec lqc-base-postgres psql -U lqc -d lqcdata -c "CREATE SCHEMA IF NOT EXISTS {NAMESPACE};"
  ```
```

- [ ] **Step 4: Replace the "Ephemeral container tracking" section at the bottom**

Replace the entire `## Ephemeral container tracking` section with:

```markdown
## Namespace tracking

After creating a namespace, append to `.claude/lqc-tokens.local.md`:

```yaml
---
session_id: {ISOLATION_ID}     # only for session level; omit for request/user
isolated_namespaces:
  - db: {falkordb|mongodb|postgres}
    level: {session|request|user}
    namespace: {NAMESPACE}
    port: {base-port}
    started: "{ISO-8601-timestamp}"
---
```

If the file doesn't exist, create it with this structure.
If it already exists, merge: update `session_id` if this is a new session ID, append to `isolated_namespaces`.

**Request-scoped cleanup (do immediately after the turn ends):**
Drop the namespace using the commands in `references/isolation-patterns.md`, then remove the entry from `isolated_namespaces`.

**Session-scoped cleanup:** handled automatically by the SessionEnd hook.

**User-scoped cleanup:** tell the user to run the drop command manually when done, or add a `/lqc-tokens:cleanup` invocation.
```

- [ ] **Step 5: Update the MCP reminder text in Step 6**

In each DB's "Also remind user" line, update the port to the fixed base container port:

- FalkorDB: `set FALKORDB_PORT to 54010`
- MongoDB: `replace 27017 with 54011`
- Postgres: `replace 5432 with 54012`

- [ ] **Step 6: Commit**

```bash
git add plugins/lqc-tokens/skills/docker-advisor/SKILL.md
git commit -m "feat: replace ephemeral container spinup with shared base container + isolated namespaces"
```

---

## Task 5: Add baseline snapshot and eval 8

**Files:**
- Create: `plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark-pre-isolation.json`
- Modify: `plugins/lqc-tokens/skills/eval/eval-workspace/evals/evals.json`

- [ ] **Step 1: Create the pre-isolation baseline JSON**

```json
{
  "metadata": {
    "skill_name": "docker-advisor",
    "iteration": "3-pre-isolation",
    "timestamp": "2026-05-13T00:00:00Z",
    "note": "Baseline before docker-spinup-optimization. docker-advisor creates a new container per ephemeral use (2-5s startup per call). Isolation-level flow not yet present."
  },
  "baseline_behavior": {
    "spinup_model": "per-use-ephemeral",
    "step_3_question": "Is this data needed after today?",
    "step_4_action": "writes docker-compose.lqc.yml with new random container name + random port",
    "startup_cost_ms": "2000-5000 (first use per session)",
    "cleanup": "stops and removes container at session end"
  },
  "target_behavior": {
    "spinup_model": "shared-base-container",
    "step_3_question": "Isolation level: session (default) / request / user",
    "step_4_action": "starts lqc-base-{db} once, creates lightweight namespace (<10ms)",
    "startup_cost_ms": "0 (if base container already running)",
    "cleanup": "drops namespace only (container stays alive)"
  }
}
```

- [ ] **Step 2: Add eval 8 to evals.json**

Append after eval 7 in the `evals` array:

```json
{
  "id": 8,
  "name": "docker-advisor-isolation-level-prompt",
  "prompt": "I have a CSV of 10,000 customer records I need to analyze for this conversation. Please set up the database.",
  "context": "No MCP tools available. No base container running (docker ps returns empty). This is a new session with no session_id in lqc-tokens.local.md.",
  "expected_output": "docker-advisor asks the isolation level question with session pre-selected as the default. It starts lqc-base-postgres (tabular CSV → Postgres), writes docker-compose.lqc-base.yml with container_name: lqc-base-postgres and port 54012, creates a schema lqc_sess_{id}, and writes session_id + isolated_namespaces entry to lqc-tokens.local.md. Does NOT ask 'Is this data needed after today?' and does NOT create a random-UUID container.",
  "assertions": [
    {
      "text": "Skill presents isolation level options with session as the recommended/default choice",
      "type": "content_check"
    },
    {
      "text": "Generated compose file uses container_name: lqc-base-postgres and port 54012, NOT a random UUID name or random port",
      "type": "content_check"
    },
    {
      "text": "Skill creates a Postgres schema named lqc_sess_{id} (not a new database or new container)",
      "type": "content_check"
    },
    {
      "text": "Tracking entry written to lqc-tokens.local.md uses isolated_namespaces structure (not ephemeral_containers)",
      "type": "content_check"
    },
    {
      "text": "Old 'Is this data needed after today?' question does NOT appear",
      "type": "absence_check"
    }
  ]
}
```

- [ ] **Step 3: Commit both files**

```bash
git add plugins/lqc-tokens/skills/eval/eval-workspace/iteration-3/benchmark-pre-isolation.json
git add plugins/lqc-tokens/skills/eval/eval-workspace/evals/evals.json
git commit -m "eval: add pre-isolation baseline + eval 8 for isolation-level prompt"
```

---

## Spec Coverage Check

| Spec requirement | Covered by |
|---|---|
| Don't spin up docker for single-prompt use | Task 4: Step 4 uses base container, not new container |
| Use schema/prefix isolation techniques | Task 1: isolation-patterns.md; Task 4: Step 4 |
| Docker kept alive, serves different sessions/requests | Task 4: base container with `restart: unless-stopped` |
| Cleanup isolated data without side effects | Task 3: session-end.sh drops namespace, not container |
| User decides isolation level | Task 4: Step 3 (new question) |
| Recommended option pre-selected (press Enter) | Task 4: Step 3 presents `[session]` as default |
| Isolation levels: user, session, request | Task 1: isolation-patterns.md; Task 4: Step 3 |

## Parallelization note

Tasks 1, 2, 3, 5 touch disjoint files and can run as parallel sub-agents.
Task 4 (SKILL.md) depends on Task 1 (isolation-patterns.md) being written first so the SKILL.md can correctly reference it. Run Task 1 first, then Tasks 2/3/5 in parallel, then Task 4.
