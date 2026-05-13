#!/usr/bin/env python3
"""
Appends one metrics record to ~/.claude/lqc-tokens-log.jsonl.
Called by the Stop hook after each response.
Usage: python3 append-session-log.py <session_id> <input_tokens> <output_tokens> <cache_hits> <hook_fired> <suggestion_accepted>
"""
import sys, json, os
from datetime import datetime, timezone

log_path = os.path.expanduser("~/.claude/lqc-tokens-log.jsonl")

args = sys.argv[1:]
if len(args) < 4:
    sys.exit(0)  # silent: missing args means no data

record = {
    "date": datetime.now(timezone.utc).isoformat(),
    "session_id": args[0] if len(args) > 0 else "unknown",
    "input_tokens": int(args[1]) if len(args) > 1 else 0,
    "output_tokens": int(args[2]) if len(args) > 2 else 0,
    "cache_hits": int(args[3]) if len(args) > 3 else 0,
    "hook_fired": args[4].lower() == "true" if len(args) > 4 else False,
    "suggestion_accepted": args[5].lower() == "true" if len(args) > 5 else False,
}

with open(log_path, "a") as f:
    f.write(json.dumps(record) + "\n")
