#!/usr/bin/env bash
# intent-guard installer (macOS / Linux)
#
#   - copies SKILL.md        -> $SKILLS_DIR/intent-guard/SKILL.md
#   - writes AGENTS-snippet.md into $AGENTS_FILE
#     (idempotent: replaces an existing marker block; skips only when unchanged)
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

if grep -q '<!-- intent-guard:start -->' "$AGENTS_FILE" && grep -q '<!-- intent-guard:end -->' "$AGENTS_FILE"; then
  TMP="$(mktemp "${TMPDIR:-/tmp}/intent-guard.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  # Match the file's existing line endings so we never leave a mixed-EOL mess.
  if grep -qU $'\r' "$AGENTS_FILE"; then CRLF=1; else CRLF=0; fi
  # Replace the marker block in place. Non-zero exit = markers reversed, duplicated
  # or unclosed; refuse to write rather than risk swallowing the rest of the file.
  if ! awk -v snippet="$ROOT/AGENTS-snippet.md" -v crlf="$CRLF" '
    BEGIN {
      term = (crlf == "1") ? "\r\n" : "\n"
      ORS = term
      while ((getline line < snippet) > 0) {
        sub(/\r$/, "", line)
        snip = snip line term
      }
      close(snippet)
    }
    { sub(/\r$/, "") }
    /<!-- intent-guard:start -->/ {
      if (seen_start || seen_end) exit 2
      printf "%s", snip
      inblock = 1; seen_start = 1; next
    }
    /<!-- intent-guard:end -->/ {
      if (!inblock) exit 2
      inblock = 0; seen_end = 1; next
    }
    !inblock { print }
    END { if (inblock || !seen_start || !seen_end) exit 2 }
  ' "$AGENTS_FILE" > "$TMP"; then
    echo "[error] marker block is reversed, duplicated, or unclosed; '$AGENTS_FILE' left untouched." >&2
    echo "        Fix manually: expect one <!-- intent-guard:start --> followed by one <!-- intent-guard:end -->." >&2
    exit 1
  fi

  if [ ! -s "$TMP" ]; then
    echo "[error] replacement produced an empty file; '$AGENTS_FILE' left untouched." >&2
    exit 1
  fi

  if cmp -s "$TMP" "$AGENTS_FILE"; then
    echo "[skip] marker block already matches; left untouched."
    exit 0
  fi

  BACKUP="$AGENTS_FILE.bak-intent-guard-$(date +%Y%m%d-%H%M%S)"
  cp "$AGENTS_FILE" "$BACKUP"
  cat "$TMP" > "$AGENTS_FILE"
  echo "[ok] replaced resident block -> $AGENTS_FILE"
  echo "[bk] backup: $BACKUP"
  exit 0
fi

if grep -q 'intent-guard' "$AGENTS_FILE"; then
  echo "[warn] '$AGENTS_FILE' mentions 'intent-guard' but has NO complete marker block."
  echo "       Possibly a manual note (e.g. 'do not use intent-guard') or a partial install."
  echo "       Please inspect the file manually; aborting instead of appending a duplicate."
  echo "       Expected markers: <!-- intent-guard:start --> ... <!-- intent-guard:end -->"
  exit 0
fi

BACKUP="$AGENTS_FILE.bak-intent-guard-$(date +%Y%m%d-%H%M%S)"
cp "$AGENTS_FILE" "$BACKUP"
# Append with the file's own EOL so the result stays uniform.
if grep -qU $'\r' "$AGENTS_FILE"; then
  printf '\r\n' >> "$AGENTS_FILE"
  sed 's/\r$//; s/$/\r/' "$ROOT/AGENTS-snippet.md" >> "$AGENTS_FILE"
else
  printf '\n' >> "$AGENTS_FILE"
  cat "$ROOT/AGENTS-snippet.md" >> "$AGENTS_FILE"
fi

echo "[ok] appended resident block -> $AGENTS_FILE"
echo "[bk] backup: $BACKUP"
echo
echo "Rollback:"
echo "  rm -rf '$SKILLS_DIR/intent-guard'"
echo "  cp '$BACKUP' '$AGENTS_FILE'"
