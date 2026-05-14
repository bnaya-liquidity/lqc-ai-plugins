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
| session | `sess_{8-char-uuid}` | Generated once per session, stored in `.claude/lqc-optimizer.local.md` as `session_id`. Cleaned by SessionEnd hook. |
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
mcp__mongodb__find(collection="tickets", filter={}, limit=20)
mcp__mongodb__aggregate(collection="tickets", pipeline=[{"$group": {"_id": "$category", "count": {"$sum": 1}}}])
```
Note: For namespace isolation with MCP, configure the server `--connectionString` to include the namespace database: `mongodb://lqc:lqcpass@localhost:54011/lqc_{id}`. Restart Claude Code with the updated `.mcp.json` after creating the namespace. For Python path, select the database directly — no restart needed.

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
