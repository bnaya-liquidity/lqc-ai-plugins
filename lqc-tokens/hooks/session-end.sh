#!/usr/bin/env bash
# Tears down ephemeral Docker containers tracked in .claude/lqc-tokens.local.md

SETTINGS_FILE="${CLAUDE_WORKSPACE_DIR:-$HOME}/.claude/lqc-tokens.local.md"

if [[ ! -f "$SETTINGS_FILE" ]]; then
  exit 0
fi

# Extract container names from YAML frontmatter lines like:
#   - name: lqc-abc123-falkordb
CONTAINERS=$(grep -E '^\s*- name:\s*lqc-' "$SETTINGS_FILE" | sed 's/.*name:\s*//')

if [[ -z "$CONTAINERS" ]]; then
  exit 0
fi

for CONTAINER in $CONTAINERS; do
  if docker inspect "$CONTAINER" &>/dev/null; then
    echo "lqc-tokens: stopping ephemeral container $CONTAINER"
    docker stop "$CONTAINER" && docker rm "$CONTAINER"
  fi
done

# Clear the ephemeral container list from the settings file
# Keep the file but reset the ephemeral_containers list
python3 - "$SETTINGS_FILE" <<'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    content = f.read()

# Replace ephemeral_containers block with empty list
content = re.sub(
    r'(ephemeral_containers:\s*\n)((?:\s+- .*\n)*)',
    r'\1',
    content
)

with open(path, 'w') as f:
    f.write(content)
PYEOF
