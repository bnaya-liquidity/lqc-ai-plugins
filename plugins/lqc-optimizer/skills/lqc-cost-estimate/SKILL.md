---
name: lqc-cost-estimate
description: Explains Claude Code token cost tiers and the full mitigation menu. Use when a prompt is predicted to be medium or high cost, when the user asks "how much will this cost", "why is my context so large", or when the pre-prompt hook flags a cost warning. Also load when advising on reducing session token spend.
argument-hint: "[optional: describe the task you're trying to do]"
allowed-tools: Read, AskUserQuestion
---

# Token Cost Estimation and Mitigation

## Cost Tiers

Estimate tokens by dividing total characters in the conversation by 4.

| Tier | Estimated tokens | Impact |
|------|-----------------|--------|
| LOW | < 20K | Minimal cost, no action needed |
| MEDIUM | 20K–80K | Noticeable cost; consider mitigations |
| HIGH | 80K–200K | Significant cost; mitigation recommended |
| CRITICAL | > 200K | Very high cost; strong action recommended |

## Mitigation Menu

Present these options to the user in order of ease:

### 1. Start a new session (free)
Resets context to zero. Best when the current task is complete and the next prompt is unrelated. Summarize work-in-progress to a file first if needed.

### 2. Compress the current prompt (`/lqc-optimizer:lqc-optimize-prompt`)
Rewrites the prompt to remove redundancy, tighten intent, and replace large pastes with file path references. Typical savings: 30–60% of prompt token count.

### 3. Offload data to a database (`/lqc-optimizer:lqc-docker-advisor`)
For data-heavy tasks: instead of loading raw data into context, spin up a database, load the data once, and query it. Typical savings: 80–95% for data analysis tasks.

### 4. Use graph context for relationship data (`/lqc-optimizer:lqc-graph-context`)
For tasks involving entities, relationships, or knowledge graphs: FalkorDB lets Claude query relationships rather than hold the entire graph in context.

### 5. Reset session with a context summary (`/lqc-optimizer:lqc-session-hygiene`)
Summarizes the current session to a file, then starts fresh pointing at the summary. Best for long sessions with topic drift.

## Asking the user which mitigation to apply

After presenting the cost tier and the relevant mitigations, use AskUserQuestion:

```
question: "Your context is at [{TIER}] (~{N}K tokens). Which mitigation would you like to apply?"
header: "Mitigation"
multiSelect: false
options:
  - label: "Start a new session"
    description: "Free — resets context to zero. Best when the current task is done."
  - label: "Compress the current prompt"
    description: "30–60% savings — rewrites the prompt to remove redundancy."
  - label: "Offload data to a database"
    description: "80–95% savings — for data-heavy analysis tasks."
  - label: "Reset session with a context summary"
    description: "Best for long sessions with topic drift — saves progress, starts fresh."
```

Only include options relevant to the current cost tier and task type. Skip "Offload data" if there is no data-heavy work.

## Reading the session-report

If `session-report` is installed, run `/session-report` to see:
- Per-session token totals
- Cache hit rate (target: > 85%)
- Most expensive prompts
- Subagent token breakdown

A cache hit rate below 85% means you're paying for repeated context. Increasing prompt stability (fewer rewrites, consistent framing) improves cache efficiency.
