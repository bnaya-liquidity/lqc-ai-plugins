# Token Savings Report

**Report generated:** 2026-05-13  
**Baseline captured:** 2026-04-29  
**Log period:** 2026-04-30 to 2026-05-13 (14 sessions)

---

## Summary

The 14 sessions in the log period show a significant improvement in cache hit rate compared to the baseline (+11.5 percentage points), resulting in an estimated **280,197 tokens saved** through caching alone. Average input tokens per session dropped by ~14,286 tokens (-32%) relative to the baseline, suggesting more efficient prompt construction or better context reuse across the period.

---

## Cache Performance

| Metric | Baseline | Log Period | Delta |
|--------|----------|------------|-------|
| Session count | 7 | 14 | +7 |
| Total input tokens | 315,000 | 430,000 | +115,000 |
| Avg input tokens / session | 45,000 | 30,714 | -14,286 (-32%) |
| Avg cache hit rate | 61.0% | 72.5% | +11.5 pp |
| Total cache hits | — | 311,330 | — |
| Estimated tokens saved (cache) | — | 280,197 | — |

> Cache savings are estimated at 90% of cache-hit tokens (reflecting Claude's ~0.1x cache-read pricing relative to full input pricing).

---

## Per-Session Cache Hit Rates

| Session | Date | Input Tokens | Cache Hits | Hit Rate |
|---------|------|-------------|------------|----------|
| s01 | 2026-04-30 | 32,000 | 22,400 | 70.0% |
| s02 | 2026-05-01 | 28,000 | 20,440 | 73.0% |
| s03 | 2026-05-02 | 35,000 | 24,500 | 70.0% |
| s04 | 2026-05-03 | 31,000 | 22,630 | 73.0% |
| s05 | 2026-05-04 | 29,000 | 21,170 | 73.0% |
| s06 | 2026-05-05 | 33,000 | 23,430 | 71.0% |
| s07 | 2026-05-06 | 30,000 | 21,900 | 73.0% |
| s08 | 2026-05-07 | 34,000 | 23,800 | 70.0% |
| s09 | 2026-05-08 | 27,000 | 20,250 | 75.0% |
| s10 | 2026-05-09 | 31,000 | 22,630 | 73.0% |
| s11 | 2026-05-10 | 29,000 | 21,750 | 75.0% |
| s12 | 2026-05-11 | 33,000 | 24,090 | 73.0% |
| s13 | 2026-05-12 | 30,000 | 21,900 | 73.0% |
| s14 | 2026-05-13 | 28,000 | 20,440 | 73.0% |
| **Total** | | **430,000** | **311,330** | **72.5% avg** |

Cache hit rates are consistently in the 70-75% band across all sessions, well above the 61% baseline. No session fell below 70%.

---

## Hook & Suggestion Behavior

| Metric | Count | Rate |
|--------|-------|------|
| Sessions with hook fired | 11 / 14 | 78.6% |
| Sessions with suggestion accepted | 9 / 11 | 81.8% |
| Docker setup suggested | 2 | — |
| Docker setup adopted | 2 | 100% |
| Hygiene hook fired | 1 | — |
| New session started (by hygiene) | 1 | — |

Hook suggestions were accepted at a high rate (81.8%), indicating the suggestions are well-targeted. Docker adoption was 100% when suggested (both FalkorDB and Postgres sessions). The hygiene hook fired once (s08, 15 turns) and triggered a session reset, consistent with expected behavior for long sessions.

---

## Output Token Summary

| Metric | Value |
|--------|-------|
| Total output tokens | 58,300 |
| Avg output tokens / session | 4,164 |
| Avg turns / session | 8.6 |
| Avg output tokens / turn | ~485 |

---

## Key Findings

1. **Cache hit rate improved by +11.5 pp** over the baseline (72.5% vs 61.0%). This is the most significant efficiency gain and reduces effective token costs substantially.

2. **Average session input dropped 32%** (30,714 vs 45,000 tokens/session), suggesting improved context hygiene and/or more focused prompting.

3. **Hook suggestions are effective**: 81.8% acceptance rate across 11 sessions where a hook fired. Zero rejected docker suggestions.

4. **Hygiene mechanism is rare but functional**: Only 1 of 14 sessions triggered the hygiene hook (the highest turn-count session at 15 turns), and it correctly initiated a new session.

5. **No outlier sessions**: All sessions fall within a tight cache hit rate range (70-75%), suggesting consistent plugin behavior rather than occasional spikes.

---

## Estimated Cost Impact

Assuming a nominal input token price of $3.00 / 1M tokens and cache-read price of $0.30 / 1M tokens:

- **Without caching**: 430,000 tokens x $3.00/1M = **$1.29**
- **With caching** (311,330 cache hits at $0.30, remainder at $3.00):
  - Cache hits: 311,330 x $0.30/1M = $0.093
  - Non-cached: 118,670 x $3.00/1M = $0.356
  - **Total: $0.449**
- **Estimated savings: ~$0.84 (65% cost reduction)**

Over the 14-session log period vs a hypothetical 0% cache scenario, the observed cache performance delivers substantial cost efficiency.
