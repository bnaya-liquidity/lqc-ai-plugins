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
**Client:** `pip install falkordb` or Redis client

## MongoDB + Lucene

**Choose when:**
- Data is document-shaped (JSON objects with variable fields)
- Need full-text search over document content
- Access pattern is "find documents matching text query"
- Schema-flexible: documents vary in shape

**Docker image:** `mongo:7`
**Default port:** 27017
**Query language:** MQL (MongoDB Query Language)
**Client:** `pip install pymongo`

## PostgreSQL

**Choose when:**
- Data is tabular with fixed schema (rows and columns)
- Need joins, aggregations, GROUP BY
- Data comes from CSV/Excel exports
- Access pattern is SQL-style relational queries

**Docker image:** `postgres:16-alpine`
**Default port:** 5432
**Query language:** SQL
**Client:** `pip install psycopg2-binary`

## Chroma (Vector / Semantic)

**Choose when:**
- Need semantic similarity search ("find documents similar to X")
- Working with embeddings
- RAG without relationship structure
- Text chunks that need nearest-neighbor retrieval

**Docker image:** `chromadb/chroma:latest`
**Default port:** 8000
**Client:** `pip install chromadb`

## Combination patterns

| Scenario | Recommendation |
|---|---|
| Knowledge graph + semantic search | FalkorDB (supports both natively) |
| Product catalog + text search | MongoDB |
| Financial data + analytics | PostgreSQL |
| Document RAG without relationships | Chroma |
| Code dependency analysis | FalkorDB |
