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
