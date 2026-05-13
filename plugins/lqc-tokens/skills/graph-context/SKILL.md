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

## Querying

**If `mcp__falkordb__*` tools are in scope:** proceed with the MCP path below.
**If not:** ask the user whether to enable MCP before falling back to Python.

> "FalkorDB MCP is not enabled. Enabling it cuts query token cost ~70% (1 tool call instead of Python subprocess + parsing).
>
> **Enable now (recommended):**
> 1. Copy `.mcp.json.example` → `.mcp.json` in your project root
> 2. Set `FALKORDB_PORT` to your container's assigned port under the `falkordb` server env
> 3. Restart Claude Code
>
> **Skip for now:** I'll use the Python client instead."

### MCP path (preferred)

When `mcp__falkordb__*` tools are in scope, query FalkorDB directly without spawning Python:

**1. Discover available graphs:**
```
mcp__falkordb__list_graphs
```

**2. Inspect schema via Cypher:**
```
mcp__falkordb__query_graph_readonly(graphName="<graph-name>", query="CALL db.labels() YIELD label RETURN label")
mcp__falkordb__query_graph_readonly(graphName="<graph-name>", query="CALL db.relationshipTypes() YIELD relationshipType RETURN relationshipType")
```

**3. Run read-only queries:**
```
mcp__falkordb__query_graph_readonly(graphName="<graph-name>", query="MATCH (s:Service {name: 'auth-service'})-[:DEPENDS_ON*1..3]->(dep) RETURN DISTINCT dep.name")
```

**4. Load data / write (create nodes and relationships via Cypher):**
```
mcp__falkordb__query_graph(graphName="<graph-name>", query="MERGE (n:Service {name: 'auth-service'}) SET n.language = 'go', n.team = 'platform'")
mcp__falkordb__query_graph(graphName="<graph-name>", query="MATCH (a:Service {name: 'auth-service'}), (b:Service {name: 'postgres'}) MERGE (a)-[:DEPENDS_ON]->(b)")
```

Embed values directly in the query string — the tool does not accept a separate `params` argument.

**Connection:** The MCP server reads `FALKORDB_HOST` and `FALKORDB_PORT` from its env. Copy `.mcp.json.example` → `.mcp.json` and set `FALKORDB_PORT` to the port assigned by docker-advisor.

### Python fallback (if user skips MCP setup)

```python
from falkordb import FalkorDB

db = FalkorDB(host='localhost', port=6379)  # replace HOST_PORT with assigned port, e.g. 54001
g = db.select_graph('<graph-name>')

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
