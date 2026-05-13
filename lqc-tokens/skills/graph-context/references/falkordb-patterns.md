# FalkorDB Cypher Pattern Library

## Basic queries

```cypher
-- All nodes of a label
MATCH (n:Label) RETURN n

-- Node by property
MATCH (n:Label {name: $name}) RETURN n

-- All edges of a type
MATCH ()-[r:EDGE_TYPE]->() RETURN r

-- Node with all its neighbors
MATCH (n:Label {name: $name})-[r]->(neighbor) RETURN type(r), neighbor.name
```

## Traversal

```cypher
-- Direct children
MATCH (n {name: $name})-[:CHILD_OF]->(child) RETURN child.name

-- All descendants (variable depth)
MATCH (n {name: $name})-[:CHILD_OF*]->(desc) RETURN DISTINCT desc.name

-- Bounded traversal (1 to 3 hops)
MATCH (n {name: $name})-[*1..3]->(related) RETURN DISTINCT related.name

-- Shortest path
MATCH p=shortestPath((a {name: $from})-[*]->(b {name: $to})) RETURN p

-- All shortest paths
MATCH p=allShortestPaths((a {name: $from})-[*]->(b {name: $to})) RETURN p
```

## Aggregation

```cypher
-- Count by type
MATCH (n:Label) RETURN n.type, count(*) AS cnt ORDER BY cnt DESC

-- Top N by degree
MATCH (n:Label)-[r]->() RETURN n.name, count(r) AS degree ORDER BY degree DESC LIMIT 10

-- Group and collect
MATCH (n:Label)-[:MEMBER_OF]->(group) RETURN group.name, collect(n.name) AS members
```

## Write operations

```cypher
-- Create node
CREATE (n:Label {name: $name, prop: $value})

-- Merge (upsert)
MERGE (n:Label {name: $name}) ON CREATE SET n.created = timestamp() ON MATCH SET n.updated = timestamp()

-- Create edge
MATCH (a:Label {name: $from}), (b:Label {name: $to}) CREATE (a)-[:EDGE_TYPE]->(b)

-- Delete node and its edges
MATCH (n:Label {name: $name}) DETACH DELETE n
```

## Vector search (FalkorDB-specific)

```cypher
-- Create vector index
CREATE VECTOR INDEX FOR (n:Document) ON (n.embedding) OPTIONS {dimension: 1536, similarityFunction: 'cosine'}

-- Vector similarity search
MATCH (n:Document) WHERE vector.similarity.cosine(n.embedding, $query_embedding) > 0.8 RETURN n.text LIMIT 10
```
