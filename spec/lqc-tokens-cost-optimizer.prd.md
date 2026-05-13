# goal

create plugin that will optimize the context management and the token cost.
the plug ins should use multiple techniqies to redude cost while keeping the accurency or improve the accurency.
it should takel bad habits and change sub optimal prompt into a better token ecconomy and suppirior context management that in turn can lead to beter performance and supirior accurency.
Whenevet it detect a potencial sub optimal prompt or spec (spec driven) it should interactivly suggest an alternative

## Plugin hooking

The plugin installation should add an entry to claude.md to consider using it on every interaction esspecially when token cost predicted medium or high.

also hook session-report Plugin on each prompt. at the buttom of each output the user should have a link to see the token cost of the prompt and for the entire session up to this point.

## Security

we must use only trusted sources plugins as complimentary plug in to this one

## General Guidance

- Prefer creating a script/code to manipulate data than bootforce scanning
- use optimal tools for a task
- summrize the essence of the data
- avoid duplication

## Techniques

### Assume Docker Engine

the plug in should assume the availability of docker engine on the user machine and
whenever identify a data digestion task like it should interact with the user and suggest an optimal digesting strategy.
it should sugges to create a script/code for loading the data into a database spin up via docker.
according to the task and the query pattern requires by the promp/spec driven, it should sugges what database/databases it should spin up.
and it should ask whether the data is relevant for future session or just for the current session.
if it can relvantfor future session it should create a docker with predefined name and port forwarding (port forwarding is important tp avoid colision with existing dockers) if it only for the session it should have a random port forwarding and random name, and should be taken down at the end of the session.

example for database suggestions:

- FalkorDB as Graph Database, can be usefule for RAG and relationship analysis including graph data sience. it also support embedded index capabilities,
- Mongo DB with luciene: for full text search or key access pattern
- Postgres for relational data
- vector/embedded db of semantic namalysis and indexing
- etc.

the use of DB can improve the contex management by loading less data into the context and answer question using a query patterns, the LLM should understand the quiestions it whant to ask and define the right db and right schema, then load the data and execute the query.
it is very effieict for single prompt and during the session because the data is in the docker and over the session other prompt can still use it with a query pattern.

### Graph context optimization

- summarize when to suggest using Falkor db for context management backbone
  - https://www.falkordb.com/blog/
  - https://www.falkordb.com/blog/graph-database-guide/
  - https://www.falkordb.com/blog/vectorrag-vs-graphrag-technical-challenges-enterprise-ai-march25/

AI Retrieval

GraphRAG
Combine LLMs with domain-specific knowledge graphs to reduce hallucinations and enrich AI responses. Enable natural language queries, traceable retrieval logic, and hidden insight discovery for smarter decision-making and faster AI deployment.

Work with structured and unstructured data
Ontology auto-detection
Built-in agent orchestration

### Summarization

when looking to website data the download data can be index and summarized according to the promp/spec driven intent.
it can use othe skill like Context7 or load the downlo data into DB inside a docker like the previous paragraph mensioned (Assume Docker Engine)

### Best practice suggestion

when seems that the sesstion is getting longer check whether the current prompt seems related to the current context, if it don't have a close relation suggest to start a new session to context management efficiency.

more ideas are wellcome

## Claude Official Plugin

Take a look over the claude official plugin to see more paths for optimization
