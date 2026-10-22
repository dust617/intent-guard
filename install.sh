#!/usr/bin/env bash
# intent-guard installer (macOS / Linux)
#
#   - copies SKILL.md        -> $SKILLS_DIR/intent-guard/SKILL.md
#   - appends AGENTS-snippet.md -> $AGENTS_FILE   (idempotent)
#   - backs up $AGENTS_FILE before modifying
#
# Override targets:
#   AGENTS_SKILLS_DIR=/some/dir  AGENTS_FILE=/repo/AGENTS.md  bash install.sh

set -euo pipefail

SKILLS_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
AGENTS_FILE="${AGENTS_FILE:-$HOME/.dsh/AGENTS.md}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -f "$ROOT/SKILL.md" ]          || { echo "SKILL.md not found next to installer" >&2; exit 1; }
[ -f "$ROOT/AGENTS-snippet.md" ] || { echo "AGENTS-snippet.md not found next to installer" >&2; exit 1; }

# --- 1. skill body ---------------------------------------------------------
mkdir -p "$SKILLS_DIR/intent-guard"
cp "$ROOT/SKILL.md" "$SKILLS_DIR/intent-guard/SKILL.md"
echo "[ok] skill  -> $SKILLS_DIR/intent-guard/SKILL.md"

# --- 2. resident block -----------------------------------------------------
if [ ! -f "$AGENTS_FILE" ]; then
  mkdir -p "$(dirname "$AGENTS_FILE")"
  cp "$ROOT/AGENTS-snippet.md" "$AGENTS_FILE"
  echo "[ok] created $AGENTS_FILE"
  exit 0
fi

if grep -q 'intent-guard' "$AGENTS_FILE"; then
  echo "[skip] '$AGENTS_FILE' already mentions intent-guard; left untouched."
  exit 0
fi

BACKUP="$AGENTS_FILE.bak-intent-guard-$(date +%Y%m%d-%H%M%S)"
cp "$AGENTS_FILE" "$BACKUP"
{ printf '\n'; cat "$ROOT/AGENTS-snippet.md"; } >> "$AGENTS_FILE"

echo "[ok] appended resident block -> $AGENTS_FILE"
echo "[bk] backup: $BACKUP"
echo
echo "Rollback:"
echo "  rm -rf '$SKILLS_DIR/intent-guard'"
echo "  cp '$BACKUP' '$AGENTS_FILE'"
