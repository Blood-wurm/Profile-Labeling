#!/usr/bin/env sh
# pfcheck.sh -- static gates for the pfsuite AutoLISP tree.
# Everything here is checkable WITHOUT AutoCAD. Run it instead of re-reading
# files to convince yourself an edit is sound. CAD gates are in SKILL.md.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
SRC="$ROOT/pfsuite"
TMP="${TMPDIR:-/tmp}/pfcheck.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
only=${1:-all}

lsp_files() { find "$SRC" -name '*.lsp' 2>/dev/null | grep -v '/Opendcl_Reference/' | grep -v '/_attic/' | sort; }
rel() { printf '%s' "${1#"$SRC"/}"; }

# Strip string literals and ; comments so checks never trip on prose.
code_only() {
  awk '{
    out = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (instr) { if (c == "\\") i++; else if (c == "\"") instr = 0; continue }
      if (c == "\"") { instr = 1; out = out " "; continue }
      if (c == ";") break
      out = out c
    }
    print out
  }' "$1"
}

# Strip ; comments but KEEP string literals -- DCL callbacks are wired as
# strings, e.g. (action_tile "accept" "(pfs:ok)"), and those are real calls.
no_comments() {
  awk '{
    out = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (instr) { out = out c; if (c == "\\") { i++; out = out substr($0, i, 1) } else if (c == "\"") instr = 0; continue }
      if (c == "\"") { instr = 1; out = out c; continue }
      if (c == ";") break
      out = out c
    }
    print out
  }' "$1"
}

say() { printf '\n== %s ==\n' "$1"; }
bad() { FAIL=1; printf '  FAIL %s\n' "$1"; }
ok()  { printf '  ok   %s\n' "$1"; }

# ---- shared tables -------------------------------------------------------
# defs.tsv: symbol \t relpath \t line
lsp_files | while IFS= read -r f; do
  awk -v REL="$(rel "$f")" '/^\(defun/ {
    n = $0; sub(/^\(defun[ \t]+/, "", n); sub(/[ \t()].*$/, "", n)
    printf "%s\t%s\t%d\n", n, REL, NR
  }' "$f"
done > "$TMP/defs.tsv"

# uses.tsv: symbol \t relpath   (code references only; a defun's own header
# line is NOT a use of itself, or nothing would ever look dead)
lsp_files | while IFS= read -r f; do
  code_only "$f" | sed 's/^(defun[[:space:]][[:space:]]*[^[:space:]()]*//' \
    | grep -oE '\bpf[a-z]*:[A-Za-z0-9>_-]+' | sort -u \
    | awk -v REL="$(rel "$f")" '{ printf "%s\t%s\n", tolower($1), REL }'
done > "$TMP/uses.tsv"

cut -f1 "$TMP/defs.tsv" | tr 'A-Z' 'a-z' | sort -u > "$TMP/defined.txt"

# reached.txt: uses.tsv PLUS names called from .dcl/.odcl action strings and
# OpenDCL event wiring -- those are real callers the .lsp grep cannot see.
{ cut -f1 "$TMP/uses.tsv"
  lsp_files | while IFS= read -r f; do
    no_comments "$f" | sed 's/^(defun[[:space:]][[:space:]]*[^[:space:]()]*//' \
      | grep -oE '\bpf[a-z]*:[A-Za-z0-9>_-]+' | tr 'A-Z' 'a-z'
  done
  find "$SRC" \( -name '*.dcl' -o -name '*.odcl' \) 2>/dev/null \
    | grep -v '/Opendcl_Reference/' \
    | while IFS= read -r d; do
        grep -aoE '\bpf[a-z]*:[A-Za-z0-9>_-]+' "$d" 2>/dev/null | tr 'A-Z' 'a-z'
      done
} | sort -u > "$TMP/reached.txt"

# order.tsv: relpath \t load index
awk -F'"' '/\(load \(strcat \*pftools-dir\*/ { printf "%s\t%d\n", $2, NR }' \
  "$SRC/pftools-load.lsp" > "$TMP/order.tsv"

# ---- 1. paren balance ----------------------------------------------------
if [ "$only" = all ] || [ "$only" = parens ]; then
say "paren balance"
lsp_files | while IFS= read -r f; do
  awk -v F="$(rel "$f")" '
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) { if (c == "\\") i++; else if (c == "\"") instr = 0; continue }
        if (c == "\"") { instr = 1; continue }
        if (c == ";") break
        if (c == "(") { depth++; if (depth == 1) top = NR }
        else if (c == ")") {
          depth--
          if (depth < 0) { printf "  FAIL %s:%d  unmatched )\n", F, NR; reported = 1; exit }
        }
      }
    }
    END {
      if (reported)       { }
      else if (instr)     printf "  FAIL %s  unterminated string\n", F
      else if (depth > 0) printf "  FAIL %s  %d unclosed ( -- outermost form opens at line %d\n", F, depth, top
      else                printf "  ok   %s\n", F
    }
  ' "$f"
done > "$TMP/paren.out"
cat "$TMP/paren.out"
grep -q '^  FAIL' "$TMP/paren.out" && FAIL=1
fi

# ---- 2. duplicate defuns -------------------------------------------------
if [ "$only" = all ] || [ "$only" = dupes ]; then
say "duplicate defuns"
dupes=$(cut -f1 "$TMP/defs.tsv" | sort -f | uniq -di)
if [ -n "$dupes" ]; then
  for d in $dupes; do bad "$d defined more than once:"; grep -i "^$d	" "$TMP/defs.tsv" | awk -F'\t' '{printf "         %s:%s\n", $2, $3}'; done
else ok "no symbol defined twice"; fi
fi

# ---- 3. called but never defined ----------------------------------------
if [ "$only" = all ] || [ "$only" = undefined ]; then
say "called but never defined"
cut -f1 "$TMP/uses.tsv" | sort -u > "$TMP/used.txt"
miss=$(comm -23 "$TMP/used.txt" "$TMP/defined.txt")
if [ -n "$miss" ]; then
  for m in $miss; do
    bad "$m -- no defun; called from: $(awk -F'\t' -v M="$m" '$1==M {printf "%s ", $2}' "$TMP/uses.tsv")"
  done
else ok "every pf* symbol called has a defun"; fi
fi

# ---- 4. load-order violations -------------------------------------------
if [ "$only" = all ] || [ "$only" = order ]; then
say "load-order guardrail (a file may only use symbols from files above it)"
BASE="$ROOT/.claude/pf-index/order-baseline.txt"
[ -f "$BASE" ] || { mkdir -p "$(dirname "$BASE")" && : > "$BASE"; }
awk -F'\t' '
  FNR == NR { ord[$1] = $2; next }
  FILENAME ~ /defs.tsv$/ { owner[tolower($1)] = $2; next }
  {
    sym = $1; user = $2
    o = owner[sym]
    if (o == "" || o == user) next
    if (!(user in ord) || !(o in ord)) next      # unloaded helpers: skip
    if (ord[o] > ord[user]) printf "%s uses %s (owned by %s, loads later)\n", user, sym, o
  }
' "$TMP/order.tsv" "$TMP/defs.tsv" "$TMP/uses.tsv" | sort > "$TMP/ord.out"
comm -23 "$TMP/ord.out" "$BASE" > "$TMP/ord.new"
comm -12 "$TMP/ord.out" "$BASE" > "$TMP/ord.known"
if [ -s "$TMP/ord.new" ]; then
  sed 's/^/  FAIL /' "$TMP/ord.new"; FAIL=1
  echo "  (sanctioned? document it in the module README, then append the line to"
  echo "   .claude/pf-index/order-baseline.txt -- do NOT baseline it silently)"
else
  ok "no NEW forward reference ($(wc -l < "$TMP/ord.known" | tr -d ' ') baselined, all documented as resolved-at-call-time)"
fi
fi

# ---- 5. defined but never referenced ------------------------------------
if [ "$only" = all ] || [ "$only" = dead ]; then
say "defined but never referenced in .lsp code, .dcl or .odcl (dead-code candidates)"
awk -F'\t' '
  FNR == NR { used[$1] = 1; next }
  {
    low = tolower($1)
    if (low ~ /^c:/) next                       # commands + OpenDCL handlers
    if (low in used) next
    printf "  note %-28s %s:%s\n", $1, $2, $3; n++
  }
  END {
    if (n == 0) print "  ok   none"
    else printf "  (%d -- advisory, not a failure: reachable only by name land here)\n", n
  }
' "$TMP/reached.txt" "$TMP/defs.tsv"
fi

# ---- 6. README Public API drift -----------------------------------------
if [ "$only" = all ] || [ "$only" = api ]; then
say "README 'Public API' entries with no matching defun"
set -- "$SRC"/*/README.md
if [ ! -f "$1" ]; then ok "no module READMEs"; else
awk '
  FNR == NR { def[$0] = 1; next }
  FNR == 1  { on = 0; split(FILENAME, p, "/"); mod = p[length(p) - 1] }
  /^## Public API/ { on = 1; next }
  on && /^## /     { on = 0 }
  on {
    s = $0
    while (match(s, /`pf[a-z]*:[A-Za-z0-9>_-]+/)) {
      t = substr(s, RSTART + 1, RLENGTH - 1); s = substr(s, RSTART + RLENGTH)
      if (t ~ /-$/) continue                     # `pfa:xr-*` family shorthand
      if (!(tolower(t) in def) && !(mod "|" t in seen)) {
        seen[mod "|" t] = 1
        printf "  note %s/README.md documents %s -- no defun\n", mod, t; n++
      }
    }
  }
  END { if (n == 0) print "  ok   every documented symbol exists" }
' "$TMP/defined.txt" "$@"
fi
fi

printf '\n'
if [ "$FAIL" = 0 ]; then echo "STATIC GATES: PASS"; else echo "STATIC GATES: FAIL"; fi
exit "$FAIL"
