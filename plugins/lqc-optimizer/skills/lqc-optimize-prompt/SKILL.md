---
name: lqc-optimize-prompt
description: Rewrites the user's current prompt for token economy. Use when the user asks to "optimize my prompt", "make this prompt cheaper", "reduce tokens", or when the pre-prompt hook detects anti-patterns (large paste without framing, vague intent, redundant re-explanation). Also use before any prompt predicted to be MEDIUM or HIGH cost.
argument-hint: "[paste the prompt you want to optimize, or leave blank to use the current prompt]"
allowed-tools: Read
---

# Prompt Optimization for Token Economy

## Process

1. **Read the prompt** (from argument or current conversation context)
2. **Count approximate tokens**: `len(prompt) / 4`
3. **Identify waste** using the anti-pattern checklist below
4. **Rewrite** applying the optimization rules
5. **Present** original vs. optimized with token counts and explanation

## Anti-Pattern Checklist

Check each and flag if present:

| Anti-pattern | Example | Fix |
|---|---|---|
| Raw large paste | "Here is the file: [3KB of code]" | Replace with file path reference |
| Vague intent | "Fix this" / "Help me" | Add specific outcome: "Fix the null pointer exception in `auth.py:42`" |
| Redundant recap | "As I mentioned earlier, we're building X..." | Cut — prior context is already in the conversation |
| Full file contents | Pasting entire file to ask about one function | Reference: "In `src/auth.py`, the `login()` function..." |
| Asking for everything | "Tell me everything about X" | Scope: "Explain only how X handles Y" |
| Multi-question prompt | 5 questions in one message | Split into separate prompts |

## Optimization Rules

- **Replace pastes with paths**: `See contents of /path/to/file.py` instead of pasting
- **Lead with the specific outcome**: "Return only the corrected function signature" not "look at this and tell me what you think"
- **Cut preamble**: Remove "I'm working on a project that..." unless it's genuinely new context
- **One question per prompt**: If multiple questions exist, pick the highest priority one
- **Use line numbers**: "The bug is at `auth.py:142`" is 80% cheaper than pasting the whole file

## Output Format

Present to the user as:

```
Original (~{N} tokens):
──────────────────────
{original prompt}

Optimized (~{M} tokens, {P}% reduction):
──────────────────────────────────────
{rewritten prompt}

Changes:
• {change 1}
• {change 2}
```

Ask the user: "Use the optimized version? (yes/no)"
