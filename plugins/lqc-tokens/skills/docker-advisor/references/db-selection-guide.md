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
- `mcp__falkordb__list_graphs` — list all graph names in this FalkorDB instance
- `mcp__falkordb__query_graph_readonly` — run read-only OpenCypher queries (`graphName`, `query`)
- `mcp__falkordb__query_graph` — run read/write OpenCypher queries (`graphName`, `query`); use Cypher CREATE/MERGE for inserts
- `mcp__falkordb__delete_graph` — delete a graph (`graphName`, `confirmDelete: true`)

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

Note: `mcp__postgres__query` is **read-only**. For `CREATE TABLE`, `INSERT`, or `COPY` operations, use the Python psycopg2 fallback.

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
