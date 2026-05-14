#!/usr/bin/env bash
# Session-end cleanup for lqc-optimizer.
# If session-scoped namespaces were loaded, asks the user whether to keep or clear them.
# Falls back to listing the data silently if stdin is not a TTY (e.g. window close).

SETTINGS_FILE="${CLAUDE_WORKSPACE_DIR:-$HOME}/.claude/lqc-optimizer.local.md"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  exit 0
fi

# ── 1. Check whether there are session-scoped namespaces to handle ────────────

SESSION_NS=$(python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re
try:
    import yaml
except ImportError:
    sys.exit(0)

path = sys.argv[1]
with open(path) as f:
    raw = f.read()

m = re.match(r'^---\n(.*?)---', raw, re.DOTALL)
if not m:
    sys.exit(0)

fm = yaml.safe_load(m.group(1)) or {}
session_ns = [ns for ns in fm.get('isolated_namespaces', []) if ns.get('level') == 'session']
if not session_ns:
    sys.exit(0)

for ns in session_ns:
    print(f"{ns.get('db', '?')}|{ns.get('namespace', '?')}|{ns.get('port', '?')}")
PYEOF
)

if [[ -z "$SESSION_NS" ]]; then
  # No session-scoped data — run backward-compat container cleanup and exit
  _run_container_cleanup() { :; }
  # (container cleanup section below still runs)
else
  # ── 2. Show what's loaded and ask the user ──────────────────────────────────

  echo ""
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║  lqc-optimizer: session data is still loaded         ║"
  echo "╠══════════════════════════════════════════════════════╣"

  while IFS='|' read -r db ns port; do
    printf "║  %-10s  %-30s  port %-5s  ║\n" "$db" "$ns" "$port"
  done <<< "$SESSION_NS"

  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  KEEP=true

  if [ -t 0 ]; then
    # stdin is a TTY — we can ask interactively
    read -r -t 20 -p "  Keep this data for next session? [Y/n] (auto-keeps in 20s): " answer
    echo ""
    case "$answer" in
      [nN]|[nN][oO])
        KEEP=false
        ;;
      *)
        KEEP=true
        ;;
    esac
  else
    # Not a TTY (window closed, non-interactive exit) — keep data, print info
    echo "  [lqc-optimizer] Non-interactive exit — data kept."
    echo "  To clear manually, run:"
    while IFS='|' read -r db ns port; do
      case "$db" in
        postgres)
          echo "    docker exec lqc-base-postgres psql -U lqc -d lqcdata -c \"DROP SCHEMA IF EXISTS $ns CASCADE;\""
          ;;
        falkordb)
          echo "    docker exec lqc-base-falkordb redis-cli GRAPH.DELETE $ns"
          ;;
        mongodb)
          echo "    docker exec lqc-base-mongodb mongosh --eval \"db.getSiblingDB('$ns').dropDatabase()\" --quiet"
          ;;
      esac
    done <<< "$SESSION_NS"
    echo ""
    exit 0
  fi

  if [[ "$KEEP" == "true" ]]; then
    echo "  [lqc-optimizer] Data kept. Connection info:"
    while IFS='|' read -r db ns port; do
      case "$db" in
        postgres)
          echo "    PostgreSQL: localhost:$port  db=lqcdata  schema=$ns  user=lqc  pass=lqcpass"
          ;;
        falkordb)
          echo "    FalkorDB:   localhost:$port  graph=$ns"
          ;;
        mongodb)
          echo "    MongoDB:    mongodb://lqc:lqcpass@localhost:$port/$ns"
          ;;
      esac
    done <<< "$SESSION_NS"
    echo "  To clear later: docker exec lqc-base-{db} ..."
    echo ""
    # Remove session_id from tracking but preserve namespace entries as 'user' level
    python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re
try:
    import yaml
except ImportError:
    sys.exit(0)

path = sys.argv[1]
with open(path) as f:
    raw = f.read()

m = re.match(r'^(---\n)(.*?)(---\n?)(.*)', raw, re.DOTALL)
if not m:
    sys.exit(0)

pre, fm_text, close, rest = m.groups()
fm = yaml.safe_load(fm_text) or {}
fm.pop('session_id', None)
# Promote kept session namespaces to 'user' level so they survive future sessions
ns_list = fm.get('isolated_namespaces', [])
for ns in ns_list:
    if ns.get('level') == 'session':
        ns['level'] = 'user'
fm['isolated_namespaces'] = ns_list
with open(path, 'w') as f:
    f.write(pre + yaml.dump(fm, default_flow_style=False, sort_keys=False) + close + rest)
PYEOF
    exit 0
  fi

  # User chose to clear — fall through to the drop logic below
  echo "  [lqc-optimizer] Clearing session data..."
fi

# ── 3. Drop session-scoped namespaces ─────────────────────────────────────────

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
    print('lqc-optimizer: PyYAML not available — namespace cleanup skipped. Install pyyaml to enable.')
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
        check = subprocess.run(
            ['docker', 'exec', 'lqc-base-falkordb', 'redis-cli', 'GRAPH.LIST'],
            capture_output=True, text=True
        )
        if namespace not in check.stdout:
            print(f'lqc-optimizer: {namespace} already gone')
            continue
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
        print(f'lqc-optimizer: dropped {db} namespace {namespace}')
    elif container_gone:
        print(f'lqc-optimizer: container not running, skipping {namespace}')
    else:
        print(f'lqc-optimizer: WARNING: failed to drop {namespace}: {stderr}')
        remaining.append(ns)

fm.pop('session_id', None)
fm['isolated_namespaces'] = remaining
new_fm = yaml.dump(fm, default_flow_style=False, sort_keys=False)
with open(path, 'w') as f:
    f.write(pre + new_fm + close + rest)
PYEOF

# ── 4. Backward-compat: stop tracked ephemeral containers ─────────────────────

CONTAINERS=$(grep -E '^\s*- name:\s*lqc-' "$SETTINGS_FILE" 2>/dev/null | sed 's/[[:space:]]*- name:[[:space:]]*//')

if [[ -z "$CONTAINERS" ]]; then
  exit 0
fi

while IFS= read -r CONTAINER; do
  [[ -z "$CONTAINER" ]] && continue
  if docker inspect "$CONTAINER" &>/dev/null; then
    echo "lqc-optimizer: stopping ephemeral container $CONTAINER"
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
    with open(path, 'w') as f:
        f.write(pre + yaml.dump(fm, default_flow_style=False, sort_keys=False) + close + rest)
except ImportError:
    cleared = re.sub(r'(ephemeral_containers:\s*\n)((?:[ \t]+.*\n)*)', r'\1', fm_text)
    with open(path, 'w') as f:
        f.write(pre + cleared + close + rest)
PYEOF
