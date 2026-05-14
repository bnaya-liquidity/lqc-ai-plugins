---
name: lqc-session-hygiene
description: Detects context drift and guides session reset. Use when the session has grown long (10+ turns), when the user switches topics or says "on a different topic", "separate question", "now let's switch to", or when the pre-prompt hook flags context drift. Also use when the user asks "should I start a new session?" or "is my context too large?".
argument-hint: "[optional: describe what you're working on now vs. what you were working on before]"
allowed-tools: Read, Write, AskUserQuestion
---

# Session Hygiene

Long sessions with topic drift waste tokens. The cost of old unrelated context compounds with every new prompt.

## Detection heuristics

Context drift is likely when:
1. The session has 10 or more turns
2. The current prompt topic is different from the last 3–5 turns (different project, technology, or task)
3. Total estimated tokens are MEDIUM or HIGH

## Action options

Use AskUserQuestion to present options:

```
question: "Your session is large (~{N}K tokens). How would you like to proceed?"
header: "Session"
multiSelect: false
options:
  - label: "Summarize and reset (recommended)"
    description: "Save progress to docs/session-context-{date}.md, then start a fresh session pointing at the summary."
  - label: "Continue in current session"
    description: "No action taken — stay in this context and accept the cost."
  - label: "Split the work"
    description: "Finish the current task here; defer unrelated new work to a fresh session."
```

### Option: Summarize and reset

1. Write a context summary to `docs/session-context-{YYYY-MM-DD}.md`:

```markdown
# Session Context — {date}

## Work completed
- [bullet: what was done]
- [bullet: what decisions were made]

## Key files modified
- `path/to/file.py` — [what changed and why]

## Open threads
- [anything not yet finished]

## Next steps
- [what to work on next session]
```

2. Tell the user:
   > "Context saved to `docs/session-context-{date}.md`. Start a new Claude Code session and open that file to continue."

### Option: Continue in current session

No action taken. Add a note: "Continuing in current session — context is at ~{N}K tokens."

### Option: Split the work

Identify which parts of the current prompt are continuation of prior work vs. new work:
- **Finish current work first** in this session
- **Write new work** to a TODO in `docs/session-context-{date}.md`
- Start fresh session for the new work

## Frequency guidance

Offer session-hygiene check when:
- Turn count ≥ 15 (regardless of topic)
- Turn count ≥ 10 AND topic switch detected
- User pastes a long prompt that appears unrelated to recent conversation
