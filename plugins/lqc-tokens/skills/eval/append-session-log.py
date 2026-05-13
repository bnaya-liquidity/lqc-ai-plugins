#!/usr/bin/env python3
"""
Appends one metrics record to ~/.claude/lqc-tokens-log.jsonl.
Called by the Stop hook after each response.

Usage:
  python3 append-session-log.py \
    <session_id> <input_tokens> <output_tokens> <cache_hits> \
    <hook_fired> <suggestion_accepted> \
    [<docker_suggested> <docker_adopted> <db_type>] \
    [<hygiene_fired> <new_session_started>] \
    [<turn_count>]

All args beyond position 4 are optional and default to false/0/unknown.
"""
import sys, json, os
from datetime import datetime, timezone

log_path = os.path.expanduser("~/.claude/lqc-tokens-log.jsonl")

args = sys.argv[1:]
if len(args) < 4:
    sys.exit(0)  # silent: missing args means no data

def bool_arg(pos, default=False):
    if len(args) > pos and args[pos]:
        return args[pos].lower() == "true"
    return default

def int_arg(pos, default=0):
    if len(args) > pos and args[pos]:
        try:
            return int(args[pos])
        except ValueError:
            return default
    return default

def str_arg(pos, default=""):
    if len(args) > pos and args[pos]:
        return args[pos]
    return default

record = {
    "date": datetime.now(timezone.utc).isoformat(),
    "session_id": str_arg(0, "unknown"),
    "input_tokens": int_arg(1),
    "output_tokens": int_arg(2),
    "cache_hits": int_arg(3),
    "hook_fired": bool_arg(4),
    "suggestion_accepted": bool_arg(5),
    # docker-advisor tracking (spec section 10.2 §3)
    "docker_suggested": bool_arg(6),
    "docker_adopted": bool_arg(7),
    "db_type": str_arg(8, ""),
    # session-hygiene tracking (spec section 10.2 §4)
    "hygiene_fired": bool_arg(9),
    "new_session_started": bool_arg(10),
    # session length (spec section 10.2 §2)
    "turn_count": int_arg(11),
}

with open(log_path, "a") as f:
    f.write(json.dumps(record) + "\n")
