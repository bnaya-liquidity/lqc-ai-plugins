# Prompt Trigger Catalog

Patterns that indicate a data-heavy task requiring docker-advisor.

## @ file reference syntax (highest priority — always triggers)

Any `@` followed by a path ending in a data extension triggers immediately:
- `@path/to/file.csv` / `@path/to/file.tsv`
- `@path/to/file.xls` / `@path/to/file.xlsx`
- `@path/to/file.json` / `@path/to/file.ndjson`
- `@path/to/file.yaml` / `@path/to/file.yml`
- `@path/to/file.parquet`
- Two or more `@` file references in the same prompt (multi-file analysis)

## Data query / aggregation language

Flag when the prompt contains an analytical query verb AND a data file reference or dataset word:
- Verbs: "give me the top N", "list the top", "find all", "which X has the most/least", "compare", "group by", "aggregate", "rank", "filter", "sort by", "count"
- Combined with: file reference (`.csv` etc.), or words like "dataset", "rows", "records", "entries", "columns", "table"
- Example: "give me the names of the companies with the highest accumulated parts" + CSV references

## Document / file ingestion
- "read the following document(s)"
- "here is the file" / "here are the files"
- "I'm attaching / I'm pasting the contents of"
- "analyze this report" / "review this document"
- "the following is the full text of"
- "read through all of these"

## Tabular / spreadsheet data
- "refer to this CSV" / "refer to this Excel" / "refer to this spreadsheet"
- "here is the data export"
- "I have a table with N rows"
- "the data looks like: [column headers]"
- "loaded from a database" / "pulled from BigQuery" / "exported from Salesforce"
- "here are the records"

## Web / scraped data
- "I scraped / downloaded this from"
- "here is the webpage content"
- "pull data from this URL"
- "fetch and analyze this site"
- "summarize the following web page"

## Bulk / multi-file
- "go through all the files in"
- "process every record in"
- "for each item in this list"
- "scan the entire codebase for"
- "read all logs from"

## Relationship / graph (→ also suggest graph-context)
- "map the relationships between"
- "find all connections from X to Y"
- "who is connected to / depends on"
- "trace the dependency chain"
- "build a knowledge graph of"
- "find paths between"

## Relationship frequency / pattern (→ FalkorDB, not PostgreSQL)

These signal a **graph pattern frequency** query — use Cypher, not SQL GROUP BY:
- "most common combination" / "most common pair"
- "most frequent relationship" / "most frequent connection"
- "which X and Y appear together most"
- "most used component" / "most used sub-product" / "most used material"
- "which relationship is most common"
- "which [thing] is used in the most [other things]"
- "what combination occurs most often"
