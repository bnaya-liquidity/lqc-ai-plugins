---
name: lqc-supervizer
description: Main coordinator for lqc-optimizer. Use when ANY of the following apply: the prompt references data files (@path.csv, @path.xlsx, @path.json, @path.yaml, @path.parquet, etc.); the user pastes large data or says "read the following document", "here is the file", "analyze this report", "here are the records", "I scraped", "fetch and analyze this site"; the user asks to query/filter/aggregate/rank/compare datasets ("give me the top N", "find all", "group by", "list the top"); the prompt is predicted to be MEDIUM or HIGH token cost (large context, long conversation); the prompt is vague ("fix this", "help me", "improve this") with no specific intent; the session has 10+ turns or has drifted to a new topic; the user asks about knowledge graphs, entity relationships, or dependency mapping; the pre-prompt hook fires an advisory; the user asks "how much will this cost", "is my context too large?", "should I start a new session?", or "which database should I use?". Routes to the right lqc-optimizer sub-skill.
argument-hint: "[describe what you're trying to do or paste the advisory message]"
allowed-tools: Read
---

# lqc-supervizer — Token Cost Coordinator

You are the main entry point for lqc-optimizer. Your job is to quickly assess the situation, identify which signal(s) fired, and route to the right sub-skill. Do not do the sub-skill's work yourself — hand off immediately.

## Step 1: Detect active signals

Scan the current prompt and conversation for these signals:

| Signal | Indicator |
|--------|-----------|
| **DATA** | `@path.csv/xlsx/json/yaml/parquet`, bare data file paths, "here is the data", "analyze this report", "I scraped", analytical verbs + dataset words |
| **COST** | Estimated tokens > 20K (characters ÷ 4 + 2K/turn), or user asking about cost |
| **PASTE** | Raw paste > 2,000 characters without a clear framing question, or file contents that could be a path reference |
| **GRAPH** | "knowledge graph", "entity relationships", "dependency mapping", "FalkorDB", "GraphRAG", "find connections", "trace dependencies" |
| **DRIFT** | Turn 10+ and current topic differs from last 5 turns, or user says "on a different topic" / "separate question" |
| **VAGUE** | Prompt is only "fix this", "help me", "improve this", or similarly underspecified |

## Step 2: Output a brief triage block

Always show this before routing — it makes the advisory actionable:

```
⚡ lqc-supervizer
──────────────────────────────────────────────
Signals detected: [DATA] [COST] [PASTE] [GRAPH] [DRIFT] [VAGUE]  ← only list those that fired
Routing to: /lqc-optimizer:<skill>
──────────────────────────────────────────────
```

## Step 3: Route to the appropriate skill

Use this priority order when multiple signals fire:

1. **DATA** → invoke `/lqc-optimizer:lqc-docker-advisor`
   - Data files, bulk analysis, web scraping, large tabular/document pastes
   - _Why first_: data tasks have the highest token savings potential (80–95%)

2. **GRAPH** → invoke `/lqc-optimizer:lqc-graph-context`
   - Only if the data is relational/graph-structured (entities + relationships)
   - _Note_: if both DATA and GRAPH fire, use `lqc-docker-advisor` with FalkorDB recommendation

3. **PASTE** + **VAGUE** → invoke `/lqc-optimizer:lqc-optimize-prompt`
   - Prompt needs rewriting before proceeding
   - _Why_: fixes the root cause (bad prompt) before spending tokens on it

4. **COST** (without DATA/GRAPH/PASTE) → invoke `/lqc-optimizer:lqc-cost-estimate`
   - Session is large but no data task — present the full mitigation menu

5. **DRIFT** → invoke `/lqc-optimizer:lqc-session-hygiene`
   - Long session with topic change — guide a context reset

6. **No signals** (skill invoked manually) → ask the user:
   > "What are you trying to do? I can help with: data offloading, prompt optimization, cost estimation, graph context, or session hygiene."

## Routing rules

- **Invoke the sub-skill** using the Skill tool — do not reproduce its content inline.
- If the user already provided enough context (e.g. pasted data, described the task), pass it through to the sub-skill so it doesn't have to ask again.
- If multiple signals fire at equal priority, pick the one with the highest token savings impact (DATA > GRAPH > PASTE > COST > DRIFT).
- Always tell the user which skill you are routing to and why in one sentence before invoking it.
