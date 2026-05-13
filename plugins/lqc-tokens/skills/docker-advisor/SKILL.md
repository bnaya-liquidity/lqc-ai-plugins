---
name: docker-advisor
description: Recommends a database strategy for data-heavy tasks and generates Docker setup. Use when the user wants to "load data into a database", "analyze a large dataset", refers to CSV or Excel files, pastes large data, says "read the following document", mentions scraping or downloading web data, needs to process many files, or when the pre-prompt hook detects a data-task pattern. Also use when the user asks which database to use for a given workload.
argument-hint: "[describe your data: shape, size, access patterns, session longevity]"
allowed-tools: Read, Write, Bash
---

# Docker Data Advisor

When a task involves loading, analyzing, or querying data that would otherwise fill the context window, offload it to a database running in Docker. This reduces context cost by 80–95% for data tasks.

## Process

### Step 1: Analyze the task

Read the user's prompt and identify:
- **Data shape**: graph/relational/document/vector/tabular
- **Access patterns**: lookup by ID? full-text search? relationship traversal? semantic similarity?
- **Query intent**: what questions will Claude ask of this data?
- **Data size**: how many rows/nodes/documents?
- **Longevity**: is this data needed after today's session?

### Step 2: Recommend a database

Use the selection guide at `references/db-selection-guide.md`. Recommend 1–2 databases maximum.

If Context7 MCP tools are available (`mcp__context7__*`), fetch the latest docs for the recommended DB before proceeding.

### Step 3: Ask about longevity

> "Is this data needed for future sessions beyond today?"

- **Yes → persistent container**:
  - Name: `lqc-{project-slug}-{db}` (e.g. `lqc-myapp-falkordb`)
  - Port: deterministic from range 54000–54999 (pick the lowest unused port in that range via `ss -tlnp | grep 540` or `lsof -i :540[0-9][0-9]`)
  - Container survives session end

- **No → ephemeral container**:
  - Name: `lqc-{8-char-uuid}` (generate with `python3 -c "import uuid; print(uuid.uuid4().hex[:8])"`)
  - Port: random high port (`shuf -i 40000-49999 -n 1`)
  - Write to `.claude/lqc-tokens.local.md` for SessionEnd cleanup

### Step 4: Generate artifacts

Copy the appropriate template from `references/docker-compose-templates/` and fill in:
- Container name
- Port mapping
- Volume name (for persistent) or anonymous volume (for ephemeral)

Write the composed file to the user's project root as `docker-compose.lqc.yml`.

Also provide a data-loading script stub (Python or shell, based on data source).

### Step 5: Start the container (if Docker MCP available)

If `mcp__docker__*` tools are in the tool list:
1. Run `docker compose -f docker-compose.lqc.yml up -d`
2. Wait for container health (retry up to 5 times with 2s delay)
3. Return the connection string

If Docker MCP is not available:
- Output the manual steps:
  ```bash
  docker compose -f docker-compose.lqc.yml up -d
  ```
- Tell the user to run this and then continue

### Step 6: Provide connection string and next steps

Tell Claude (and the user) the connection string and the schema to use for the task. Include a data-loading command the user can run.

## Ephemeral container tracking

After creating an ephemeral container, append to `.claude/lqc-tokens.local.md`:

```yaml
---
ephemeral_containers:
  - name: {container-name}
    port: {port}
    started: "{ISO-8601-timestamp}"
---
```

If the file doesn't exist, create it with this structure.
If it already exists, add the new entry to the `ephemeral_containers` list.
