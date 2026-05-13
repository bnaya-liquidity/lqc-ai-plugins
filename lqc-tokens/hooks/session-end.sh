#!/usr/bin/env bash
# Tears down ephemeral Docker containers tracked in .claude/lqc-tokens.local.md

SETTINGS_FILE="${CLAUDE_WORKSPACE_DIR:-$HOME}/.claude/lqc-tokens.local.md"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  exit 0
fi

# Extract container names from YAML frontmatter (lines: "  - name: lqc-<id>")
CONTAINERS=$(grep -E '^\s*- name:\s*lqc-' "$SETTINGS_FILE" | sed 's/[[:space:]]*- name:[[:space:]]*//')

if [[ -z "$CONTAINERS" ]]; then
  exit 0
fi

# Iterate safely over newline-separated container names
while IFS= read -r CONTAINER; do
  # Skip blank lines from grep output
  [[ -z "$CONTAINER" ]] && continue
  if docker inspect "$CONTAINER" &>/dev/null; then
    echo "lqc-tokens: stopping ephemeral container $CONTAINER"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
  fi
done <<< "$CONTAINERS"

# Clear the ephemeral_containers list using PyYAML (handles all sub-keys correctly)
python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    raw = f.read()

# Find YAML frontmatter block between --- markers
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
    # PyYAML not available: fall back to regex that handles full entry blocks
    cleared = re.sub(
        r'(ephemeral_containers:\s*\n)((?:[ \t]+.*\n)*)',
        r'\1',
        fm_text
    )
    with open(path, 'w') as f:
        f.write(pre + cleared + close + rest)
PYEOF
