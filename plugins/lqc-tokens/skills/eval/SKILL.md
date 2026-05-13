---
name: eval
description: Generates a token savings report comparing current usage against the pre-install baseline. Use when the user asks "is the plugin saving tokens?", "show me the eval report", "how much have I saved?", "/lqc-tokens:eval", or after 7+ days of plugin use to measure effectiveness. Also use when the user wants to know if the plugin is working, if the hooks are firing, or whether Docker strategy adoption is happening.
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

### 2. Load log and compute all metrics

```bash
python3 - <<'EOF'
import json, os, statistics
from collections import Counter

log_path = os.path.expanduser('~/.claude/lqc-tokens-log.jsonl')
if not os.path.exists(log_path):
    print(json.dumps({'error': 'no log file'}))
    exit(0)

records = [json.loads(l) for l in open(log_path) if l.strip()]
if not records:
    print(json.dumps({'error': 'empty log'}))
    exit(0)

dates = sorted(r.get('date', '') for r in records)
total_input = sum(r.get('input_tokens', 0) for r in records)
total_cache = sum(r.get('cache_hits', 0) for r in records)
total_prompts = len(records)
hooks_fired = sum(1 for r in records if r.get('hook_fired'))
accepted = sum(1 for r in records if r.get('suggestion_accepted'))

# docker-advisor tracking (spec 10.2 §3)
docker_suggested = sum(1 for r in records if r.get('docker_suggested'))
docker_adopted = sum(1 for r in records if r.get('docker_adopted'))
db_type_counts = Counter(r.get('db_type', '') for r in records if r.get('docker_adopted') and r.get('db_type'))

# session-hygiene tracking (spec 10.2 §4)
hygiene_fired = sum(1 for r in records if r.get('hygiene_fired'))
new_sessions = sum(1 for r in records if r.get('new_session_started'))

# session length distribution (spec 10.2 §2)
turn_counts = [r.get('turn_count', 0) for r in records if r.get('turn_count')]
avg_turns = statistics.mean(turn_counts) if turn_counts else 0

print(json.dumps({
    'first_date': dates[0][:10] if dates else 'unknown',
    'last_date': dates[-1][:10] if dates else 'unknown',
    'avg_input_per_session': total_input / max(1, total_prompts),
    'cache_hit_rate': total_cache / max(1, total_input) if total_input > 0 else 0,
    'hook_fire_rate': hooks_fired / max(1, total_prompts),
    'acceptance_rate': accepted / max(1, hooks_fired) if hooks_fired > 0 else 0,
    'session_count': total_prompts,
    'docker_suggested': docker_suggested,
    'docker_adopted': docker_adopted,
    'db_type_counts': dict(db_type_counts),
    'hygiene_fired': hygiene_fired,
    'new_sessions_started': new_sessions,
    'avg_turns': round(avg_turns, 1)
}))
EOF
```

### 3. Format report (spec section 10.3 format)

Compute:
- `token_savings_pct = (baseline_avg - current_avg) / baseline_avg * 100`
- `cache_delta_pp = (current_cache_rate - baseline_cache_rate) * 100`

Build the DB advisor line from `db_type_counts`, e.g.: `4 sessions (3 FalkorDB, 1 Postgres)`.
If `docker_suggested == 0`: show `"not yet triggered"`.

Output **exactly** this format (spec 10.3):

```
lqc-tokens evaluation ({first_date} → {last_date})
────────────────────────────────────────────────
Token savings:   {+/-X}% avg input tokens/session vs. baseline
Cache hit rate:  {+/-X}pp ({baseline_pct}% → {current_pct}%)
Hook acceptance: {X}% of pre-prompt suggestions accepted
DB advisor:      {N} sessions used Docker strategy ({breakdown})
Session hygiene: {N} new sessions started on suggestion
────────────────────────────────────────────────
```

### 4. Add one adaptive recommendation (spec 10.3)

Evaluate conditions in priority order and use the first one that matches:

1. `acceptance_rate < 0.50` → "Hook is too sensitive — try raising the paste trigger from 2KB to 4KB to reduce noise"
2. `docker_suggested > 0 AND docker_adopted / docker_suggested < 0.30` → "Docker strategy suggested {N} times but adopted only {M}% of the time — consider simplifying the docker-advisor output"
3. `hygiene_fired > 0 AND new_sessions / hygiene_fired < 0.20` → "Session hygiene fired {N} times but rarely acted on — consider making the summary export faster"
4. `cache_hit_rate < 0.85 AND cache_delta_pp < 2` → "Cache hit rate stagnant at {X}% — more consistent prompt framing will improve this"
5. `cache_hit_rate < 0.85 AND cache_delta_pp >= 2` → "Cache hit rate improving (+{delta}pp) but still below 85% target — keep going"
6. `token_savings_pct < 10 AND sessions >= 7` → "Limited savings after 7 days — run `/lqc-tokens:docker-advisor` on your next data task for larger impact"
7. otherwise → "Plugin is performing well"

The priority order matters: user-facing friction (hook sensitivity, low adoption) ranks above system metrics (cache rate).
