#!/usr/bin/env bash
# Template-maintenance script: regenerates .claude/settings.json's Read-deny
# rules from .agentignore so Claude Code enforces the same patterns as the
# gitignore-syntax .agentignore without hand-duplicating them.
# Writes through root .claude/settings.json symlink to update template/.claude/settings.json.
#
# Usage:
#   scripts/sync-agent-ignore.sh          # regenerate .claude/settings.json
#   scripts/sync-agent-ignore.sh --check  # verify it's already in sync (no write)
set -euo pipefail

CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "error: required command 'jq' is not installed or not in PATH" >&2
  echo "tip: run inside 'nix-shell' or install jq via your system package manager" >&2
  exit 1
fi

if [[ ! -f .agentignore ]]; then
  echo "error: .agentignore not found in $(pwd)" >&2
  exit 1
fi

deny=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  # Skip empty lines, lines with only whitespace, and comments (including indented)
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  # Strip leading and trailing whitespace
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ "$line" == */ ]]; then
    deny+=("Read(./**/${line%/}/**)")
  else
    deny+=("Read(./**/${line})")
  fi
done < .agentignore

# Handle empty pattern list defensively to generate valid JSON ({deny: []})
# without triggering Bash 3.2 unbound variable errors under set -u
if [[ ${#deny[@]} -eq 0 ]]; then
  generated='{"permissions":{"deny":[]}}'
else
  generated="$(printf '%s\n' "${deny[@]}" | jq -R . | jq -s '{permissions: {deny: .}}')"
fi

case "${1:-}" in
  "")
    mkdir -p .claude
    printf '%s\n' "$generated" > .claude/settings.json
    echo "Regenerated .claude/settings.json from .agentignore"
    ;;
  --check)
    current="$(tr -d '\r' < .claude/settings.json 2>/dev/null || true)"
    if [[ "$current" != "$generated" ]]; then
      echo "error: .claude/settings.json is stale — run 'just sync-agent-ignore' to regenerate" >&2
      exit 1
    fi
    echo ".claude/settings.json is in sync with .agentignore"
    ;;
  -h|--help)
    echo "Usage: $(basename "${BASH_SOURCE[0]}") [--check]"
    exit 0
    ;;
  *)
    echo "error: unrecognized argument '$1'" >&2
    echo "Usage: $(basename "${BASH_SOURCE[0]}") [--check]" >&2
    exit 1
    ;;
esac
