# Prompt Trigger Catalog

Patterns that indicate a data-heavy task requiring docker-advisor.

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
