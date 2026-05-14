# Database Selection Guide

## Quick decision tree

```
Does any file look like an edge table?
  (≤3 columns, first two are both *_id columns referencing the same entity type)
      │
      ├─ YES → FalkorDB (+ PostgreSQL for analytics tables if needed)
      │
      └─ NO → Is the data purely tabular with JOINs but no traversal queries?
                  │
                  ├─ YES → PostgreSQL
                  │
                  └─ Is data nested/document-shaped with variable schema?
                            │
                            ├─ YES → MongoDB
                            └─ NO  → PostgreSQL
```

Multi-DB is allowed. If graph structure is present alongside metric tables, spin up both.

---

## Detecting graph/edge data

**Edge table pattern** — flag if a file has:
- Exactly 2–3 columns total
- First two columns are both `*_id` columns that reference the same entity
  (e.g. `parent_product_id` + `component_product_id`, or `from_company_id` + `to_company_id`)
- Optional third column is a weight or label (`quantity`, `weight`, `cost`, `rel_type`)

Examples that trigger graph selection:
```
parent_product_id, component_product_id, quantity    ← bill of materials / product graph
from_id, to_id, weight                               ← generic edge table
company_id, supplier_id, contract_value              ← supply-chain graph
user_id, follows_id                                  ← social graph
```

**Self-referential / hierarchical pattern** — flag if a file has columns where one is `parent_{X}_id` and another is `{X}_id`. This always implies a recursive tree or DAG.

**Cyclic graph indicator** — when the same entity appears as both source and target across multiple rows of an edge table, you likely have cycles. Always prefer FalkorDB over PostgreSQL's `WITH RECURSIVE` for cyclic traversal.

**When to add PostgreSQL alongside FalkorDB:**
- You have both graph files (edges) AND analytics/metric files (pre-computed aggregates, flat fact tables)
- Load the graph into FalkorDB; load the metric tables into PostgreSQL
- Query each with the right tool, join results in Python if needed

---

## FalkorDB (Graph + Vector)

**Choose when:**
- Any edge table detected (see above)
- Need multi-hop queries ("find all components of product X at any depth")
- Building GraphRAG (retrieve by relationship, not just similarity)
- Need graph algorithms (centrality, community detection, shortest path)
- Data has cyclic or self-referential relationships
- Want combined graph + vector search (FalkorDB supports both)

**Docker image:** `falkordb/falkordb:latest`
**Port (lqc-base):** 54010 (container 6379)
**Query language:** Cypher + FalkorDB extensions
**Python client:** `pip install falkordb`

**MCP server:** `@falkordb/mcpserver` — detected as `mcp__falkordb__*`
**MCP tools:**
- `mcp__falkordb__list_graphs` — list all graphs
- `mcp__falkordb__query_graph_readonly` — read-only Cypher (`graphName`, `query`)
- `mcp__falkordb__query_graph` — read/write Cypher; use CREATE/MERGE for inserts
- `mcp__falkordb__delete_graph` — delete a graph (`graphName`, `confirmDelete: true`)

---

## PostgreSQL

**Choose when:**
- Data is tabular with fixed schema (rows and columns)
- Need JOINs, aggregations, GROUP BY, window functions
- Data comes from CSV/Excel exports with no graph structure
- Queries are SQL-style: filter, sort, aggregate

**Docker image:** `postgres:16-alpine`
**Port (lqc-base):** 54012 (container 5432)
**Query language:** SQL
**Python client:** `pip install psycopg2-binary`

**MCP server:** `@modelcontextprotocol/server-postgres` — detected as `mcp__postgres__*`
**MCP tools:**
- `mcp__postgres__query` — **read-only** SQL queries

Note: For `CREATE TABLE`, `INSERT`, `COPY`, use psycopg2 directly.

---

## MongoDB + Lucene

**Choose when:**
- Data is document-shaped (JSON objects with variable fields)
- Need full-text search over document content
- Schema-flexible: documents vary in shape

**Docker image:** `mongo:7`
**Port (lqc-base):** 54011 (container 27017)
**Query language:** MQL
**Python client:** `pip install pymongo`

**MCP server:** `mongodb-mcp-server` — detected as `mcp__mongodb__*`
**MCP tools:** `find`, `count`, `aggregate`, `collection-schema`

---

## Chroma (Vector / Semantic)

**Choose when:**
- Need semantic similarity search ("find documents similar to X")
- Working with embeddings or RAG without relationship structure

**Docker image:** `chromadb/chroma:latest`
**Port:** 8000
**Python client:** `pip install chromadb`
*(No MCP server — use Python client via Bash.)*

---

## Multi-DB combination patterns

| Data mix | Recommendation |
|---|---|
| Edge table + flat metric tables | FalkorDB (graph) + PostgreSQL (metrics) |
| Knowledge graph + semantic search | FalkorDB (supports both natively) |
| Product catalog + text search | MongoDB |
| Financial data + analytics only | PostgreSQL |
| Document RAG without relationships | Chroma |
| Code dependency analysis | FalkorDB |
| BOM / supply chain / org charts | FalkorDB |
