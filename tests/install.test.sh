#!/usr/bin/env bash
# Regression tests for install.sh (and the shared marker-block contract).
#
#   bash tests/install.test.sh
#
# No dependencies beyond bash + coreutils. Runs entirely in a temp dir and
# never touches your real AGENTS.md.
#
# Why this file exists: an earlier awk rewrite could silently delete everything
# after the start marker when the markers were reversed, while still printing
# "[ok] replaced". That failure mode is invisible without a test.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
A="$WORK/a.md"

ok()  { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
run() { AGENTS_SKILLS_DIR="$WORK/skills" AGENTS_FILE="$1" bash "$REPO/install.sh" 2>&1; }
has() { grep -q "$2" "$1" 2>/dev/null; }
count() { tr -cd "$2" < "$1" | wc -c | tr -d ' '; }
# Assert the file keeps a single, uniform line ending style.
uniform_eol() {
  local file="$1" cr lf
  cr="$(count "$file" '\r')"
  lf="$(count "$file" '\n')"
  if [ "$cr" = "0" ] || [ "$cr" = "$lf" ]; then ok "$2 (cr=$cr lf=$lf)"; else bad "$2 (cr=$cr lf=$lf)"; fi
}

echo "[1] fresh install"
rm -f "$A"
OUT="$(run "$A")"
[ -f "$A" ]                                       && ok "creates file"   || bad "creates file"
has "$A" 'intent-guard:start'                     && ok "start marker"   || bad "start marker"
has "$WORK/skills/intent-guard/SKILL.md" '沿用复核' && ok "installs skill" || bad "installs skill"
case "$OUT" in *"[ok] created"*) ok "reports created";; *) bad "reports created";; esac

echo "[2] rerun is idempotent"
BEFORE="$(cat "$A")"
OUT="$(run "$A")"
case "$OUT" in *"[skip]"*) ok "skips when unchanged";; *) bad "skips when unchanged";; esac
[ "$(cat "$A")" = "$BEFORE" ] && ok "content unchanged" || bad "content unchanged"

echo "[3] stale block replaced, surroundings preserved"
printf '# head\n<!-- intent-guard:start -->\n- OLD LINE\n<!-- intent-guard:end -->\n# tail\n' > "$A"
OUT="$(run "$A")"
case "$OUT" in *"[ok] replaced"*) ok "reports replace";; *) bad "reports replace";; esac
has "$A" 'OLD LINE' && bad "old line gone" || ok "old line gone"
has "$A" '^# head'  && ok "head preserved" || bad "head preserved"
has "$A" '^# tail'  && ok "tail preserved" || bad "tail preserved"
ls "$A".bak-intent-guard-* >/dev/null 2>&1 && ok "backup created" || bad "backup created"

echo "[4] rerun after replace is a no-op"
OUT="$(run "$A")"
case "$OUT" in *"[skip]"*) ok "idempotent after replace";; *) bad "idempotent after replace";; esac

echo "[5] partial mention aborts, file untouched"
printf 'note: do not use intent-guard here\n' > "$A"
KEEP="$(cat "$A")"
OUT="$(run "$A")"
case "$OUT" in *"[warn]"*) ok "warns";; *) bad "warns";; esac
[ "$(cat "$A")" = "$KEEP" ] && ok "file untouched" || bad "file untouched"

echo "[6] reversed markers: refuse, no data loss"
printf '# HEAD\n<!-- intent-guard:end -->\n# MID\n<!-- intent-guard:start -->\n# TAIL-MUST-SURVIVE\n' > "$A"
KEEP="$(cat "$A")"
OUT="$(run "$A")"
case "$OUT" in *"[error]"*) ok "reports error";; *) bad "reports error";; esac
[ "$(cat "$A")" = "$KEEP" ] && ok "file untouched" || bad "file untouched"
has "$A" 'TAIL-MUST-SURVIVE' && ok "tail survived" || bad "tail survived"

echo "[7] duplicate start marker: refuse"
printf '<!-- intent-guard:start -->\na\n<!-- intent-guard:start -->\nb\n<!-- intent-guard:end -->\n# TAIL2\n' > "$A"
KEEP="$(cat "$A")"
OUT="$(run "$A")"
case "$OUT" in *"[error]"*) ok "reports error";; *) bad "reports error";; esac
[ "$(cat "$A")" = "$KEEP" ] && ok "file untouched" || bad "file untouched"

echo "[8] duplicate end marker: refuse"
printf '<!-- intent-guard:start -->\na\n<!-- intent-guard:end -->\n<!-- intent-guard:end -->\n# TAIL3\n' > "$A"
KEEP="$(cat "$A")"
OUT="$(run "$A")"
case "$OUT" in *"[error]"*) ok "reports error";; *) bad "reports error";; esac
[ "$(cat "$A")" = "$KEEP" ] && ok "file untouched" || bad "file untouched"

echo "[9] unclosed start: warn, untouched"
printf '# head\n<!-- intent-guard:start -->\nno end here\n# TAIL4\n' > "$A"
KEEP="$(cat "$A")"
OUT="$(run "$A")"
case "$OUT" in *"[warn]"*) ok "warns";; *) bad "warns";; esac
[ "$(cat "$A")" = "$KEEP" ] && ok "file untouched" || bad "file untouched"

echo "[10] no python3 dependency"
grep -q 'python' "$REPO/install.sh" && bad "no python3 reference" || ok "no python3 reference"

echo "[11] CRLF file stays uniformly CRLF"
printf '# head\r\n<!-- intent-guard:start -->\r\nold\r\n<!-- intent-guard:end -->\r\n# tail\r\n' > "$A"
run "$A" >/dev/null
uniform_eol "$A" "uniform CRLF after replace"

echo "[12] LF file stays uniformly LF"
printf '# head\n<!-- intent-guard:start -->\nold\n<!-- intent-guard:end -->\n# tail\n' > "$A"
run "$A" >/dev/null
uniform_eol "$A" "uniform LF after replace"

echo "[13] append path keeps the file's EOL"
printf '# head\r\n' > "$A"
run "$A" >/dev/null
has "$A" 'intent-guard:start' && ok "appended block" || bad "appended block"
uniform_eol "$A" "uniform CRLF after append"

echo
echo "TOTAL pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
