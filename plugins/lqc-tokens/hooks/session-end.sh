#!/usr/bin/env bash
# Cleans up session-scoped isolated namespaces and any tracked ephemeral containers.

SETTINGS_FILE="${CLAUDE_WORKSPACE_DIR:-$HOME}/.claude/lqc-tokens.local.md"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  exit 0
fi

# ── 1. Drop session-scoped isolated namespaces ───────────────────────────────

python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re, subprocess

path = sys.argv[1]
with open(path) as f:
    raw = f.read()

match = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
if not match:
    sys.exit(0)

pre, fm_text, close, rest = match.groups()

try:
    import yaml
except ImportError:
    print('lqc-tokens: PyYAML not available — namespace cleanup skipped. Install pyyaml to enable.')
    sys.exit(1)

fm = yaml.safe_load(fm_text) or {}
namespaces = fm.get('isolated_namespaces', [])
remaining = []

for ns in namespaces:
    if ns.get('level') != 'session':
        remaining.append(ns)
        continue
    db = ns.get('db', '')
    namespace = ns.get('namespace', '')
    if not namespace:
        continue

    if db == 'falkordb':
        # Check existence first — GRAPH.DELETE on a non-existent graph returns an error
        check = subprocess.run(
            ['docker', 'exec', 'lqc-base-falkordb', 'redis-cli', 'GRAPH.LIST'],
            capture_output=True, text=True
        )
        if namespace not in check.stdout:
            print(f'lqc-tokens: {db} namespace {namespace} already gone, skipping')
            continue  # already dropped — don't add to remaining
        cmd = ['docker', 'exec', 'lqc-base-falkordb', 'redis-cli', 'GRAPH.DELETE', namespace]
    elif db == 'mongodb':
        cmd = ['docker', 'exec', 'lqc-base-mongodb', 'mongosh',
               '--eval', f"db.getSiblingDB('{namespace}').dropDatabase()", '--quiet']
    elif db == 'postgres':
        cmd = ['docker', 'exec', 'lqc-base-postgres', 'psql',
               '-U', 'lqc', '-d', 'lqcdata',
               '-c', f"DROP SCHEMA IF EXISTS {namespace} CASCADE;"]
    else:
        remaining.append(ns)
        continue

    result = subprocess.run(cmd, capture_output=True, text=True)
    stderr = result.stderr.strip()
    container_gone = 'No such container' in stderr or 'Error response from daemon' in stderr

    if result.returncode == 0:
        print(f'lqc-tokens: dropped {db} namespace {namespace}')
        # success — don't add to remaining
    elif container_gone:
        print(f'lqc-tokens: base container not running, skipping {namespace}')
        # container stopped — namespace is inaccessible anyway, remove from tracking
    else:
        print(f'lqc-tokens: WARNING: failed to drop {namespace}: {stderr}')
        remaining.append(ns)  # keep in tracking for next session-end attempt

# Rewrite file: clear session_id, keep only non-session namespaces (+ any failed drops)
fm.pop('session_id', None)
fm['isolated_namespaces'] = remaining
new_fm = yaml.dump(fm, default_flow_style=False, sort_keys=False)
with open(path, 'w') as f:
    f.write(pre + new_fm + close + rest)
PYEOF

# ── 2. Backward-compat: stop tracked ephemeral containers ────────────────────

CONTAINERS=$(grep -E '^\s*- name:\s*lqc-' "$SETTINGS_FILE" | sed 's/[[:space:]]*- name:[[:space:]]*//')

if [[ -z "$CONTAINERS" ]]; then
  exit 0
fi

while IFS= read -r CONTAINER; do
  [[ -z "$CONTAINER" ]] && continue
  if docker inspect "$CONTAINER" &>/dev/null; then
    echo "lqc-tokens: stopping ephemeral container $CONTAINER"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
  fi
done <<< "$CONTAINERS"

python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    raw = f.read()

match = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
if not match:
    sys.exit(0)

pre, fm_text, close, rest = match.groups()

try:
    import yaml
    fm = yaml.safe_load(fm_text) or {}
    fm['ephemeral_containers'] = []
    new_fm = yaml.dump(fm, default_flow_style=False, sort_keys=False)
    with open(path, 'w') as f:
        f.write(pre + new_fm + close + rest)
except ImportError:
    cleared = re.sub(
        r'(ephemeral_containers:\s*\n)((?:[ \t]+.*\n)*)',
        r'\1',
        fm_text
    )
    with open(path, 'w') as f:
        f.write(pre + cleared + close + rest)
PYEOF
