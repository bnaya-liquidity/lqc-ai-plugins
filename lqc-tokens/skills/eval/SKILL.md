---
name: eval
description: Generates a token savings report comparing current usage against the pre-install baseline. Use when the user asks "is the plugin saving tokens?", "show me the eval report", "how much have I saved?", "/lqc-tokens:eval", or after 7+ days of plugin use to measure effectiveness.
allowed-tools: Read, Bash
---

# lqc-tokens Evaluation Report

## Prerequisites

- Baseline file: `~/.claude/lqc-tokens-baseline.json` (captured by `/lqc-tokens:setup`)
- Log file: `~/.claude/lqc-tokens-log.jsonl` (appended by Stop hook)

If baseline is missing: tell user to run `/lqc-tokens:setup` first.
If log has fewer than 3 entries: tell user "Not enough data yet — use the plugin for at least 3 sessions."

## Compute metrics

### 1. Load baseline

```bash
python3 -c "
import json, os
b = json.load(open(os.path.expanduser('~/.claude/lqc-tokens-baseline.json')))
overall = b.get('overall', {})
import json
print(json.dumps({
    'avg_input_per_session': overall.get('input_tokens', {}).get('total', 0) / max(1, overall.get('session_count', 1)),
    'cache_hit_rate': overall.get('cache_hit_rate', 0),
    'session_count': overall.get('session_count', 1)
}))
"
```

### 2. Load log

```bash
python3 - <<'EOF'
import json, os, statistics

log_path = os.path.expanduser('~/.claude/lqc-tokens-log.jsonl')
if not os.path.exists(log_path):
    print(json.dumps({'error': 'no log file'}))
    exit(0)

records = [json.loads(l) for l in open(log_path) if l.strip()]

total_input = sum(r['input_tokens'] for r in records)
total_cache = sum(r['cache_hits'] for r in records)
total_prompts = len(records)
hooks_fired = sum(1 for r in records if r.get('hook_fired'))
accepted = sum(1 for r in records if r.get('suggestion_accepted'))

print(json.dumps({
    'avg_input_per_session': total_input / max(1, total_prompts),
    'cache_hit_rate': total_cache / max(1, total_input) if total_input > 0 else 0,
    'hook_fire_rate': hooks_fired / max(1, total_prompts),
    'acceptance_rate': accepted / max(1, hooks_fired) if hooks_fired > 0 else 0,
    'session_count': total_prompts
}))
EOF
```

### 3. Format report

Compute:
- `token_savings_pct = (baseline_avg - current_avg) / baseline_avg * 100`
- `cache_delta_pp = current_cache_rate - baseline_cache_rate` (in percentage points)

Output:

```
lqc-tokens evaluation
─────────────────────────────────────────────────────
Period:          {first log date} → {today}
Sessions logged: {N}

Token savings:   {+/-X}% avg input tokens/session vs. baseline
Cache hit rate:  {+/-X}pp ({baseline}% → {current}%)
Hook fire rate:  {X}% of prompts triggered advisory
Acceptance rate: {X}% of suggestions accepted by user
─────────────────────────────────────────────────────
```

Add one recommendation line:
- If acceptance rate < 50%: "Advisory threshold may be too sensitive — consider raising the paste size trigger from 2KB to 4KB"
- If cache hit rate < 85%: "Cache hit rate below target — more consistent prompt framing will improve this"
- If token savings < 10% after 7 days: "Limited savings detected — run `/lqc-tokens:docker-advisor` on your next data task for larger impact"
- Otherwise: "Plugin is performing well"
