#!/usr/bin/env sh
# pf.sh -- symbol navigation for the pfsuite AutoLISP tree.
# Answers "where is X / what calls X / show me X" WITHOUT reading whole .lsp files.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)      # .claude/skills/pf-find -> V5
SRC="$ROOT/pfsuite"
IDXDIR="$ROOT/.claude/pf-index"
IDX="$IDXDIR/symbols.tsv"

lsp_files() {
  find "$SRC" -name '*.lsp' 2>/dev/null | grep -v '/Opendcl_Reference/' | sort
}
rel_of() { printf '%s' "${1#"$SRC"/}"; }

# ---------------------------------------------------------------- index ----
build_index() {
  mkdir -p "$IDXDIR"
  : > "$IDX.tmp"
  lsp_files | while IFS= read -r f; do
    rel=${f#"$SRC"/}
    awk -v REL="$rel" '
      # A doc block is the run of ";;" lines directly above the defun.
      # Prefer its signature line ";; (name args) -> result"; else its first line.
      /^;;[^;]/ || /^;;$/ {
        t = $0; sub(/^;+[ \t]*/, "", t)
        if (t != "") { if (sig == "" && t ~ /^\(/) sig = t; if (first == "") first = t }
        next
      }
      /^\(defun/ {
        name = $0
        sub(/^\(defun[ \t]+/, "", name)
        sub(/[ \t()].*$/, "", name)
        d = (sig != "" ? sig : first)
        printf "%s\t%s\t%d\t%s\n", name, REL, NR, d
        sig = ""; first = ""; next
      }
      { sig = ""; first = "" }
    ' "$f" >> "$IDX.tmp"
  done
  sort -f "$IDX.tmp" -o "$IDX.tmp" && mv "$IDX.tmp" "$IDX"
  printf 'indexed %s symbols -> .claude/pf-index/symbols.tsv\n' "$(wc -l < "$IDX" | tr -d ' ')"
}

ensure_index() {
  [ -f "$IDX" ] || { build_index >&2; return; }
  if [ -n "$(lsp_files | while IFS= read -r f; do [ "$f" -nt "$IDX" ] && echo x && break; done)" ]; then
    build_index >&2
  fi
}

# Escape a symbol for use inside an ERE.
esc() { printf '%s' "$1" | sed 's/[].[*^$\\+?(){}|/]/\\&/g'; }

# Print the doc block + paren-balanced body of the defun at FILE:LINE.
extract() {
  awk -v START="$2" '
    NR < START - 12 { next }
    NR < START {
      if ($0 ~ /^;; /) { buf = buf $0 "\n" } else { buf = "" }
      next
    }
    NR == START { printf "%s", buf }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) { if (c == "\\") i++; else if (c == "\"") instr = 0; continue }
        if (c == "\"") { instr = 1; continue }
        if (c == ";") break
        if (c == "(") depth++
        else if (c == ")") { depth--; if (depth == 0) { print; exit } }
      }
      print
    }
  ' "$1"
}

usage() {
  cat <<'EOF'
pf.sh <cmd> -- pfsuite symbol navigation (run from the V5 working dir)

  find <regex>      symbols whose name matches -> name  file:line  one-line doc
  show <symbol>     the doc comment + full body of that defun (exact name)
  refs <symbol>     every call site, definition excluded  (file:line: text)
  api <module>      the "Public API" section of that module's README.md
  outline <module>  SECTION banners with the defuns under each
  modules           module list, load order, line counts
  grep <regex>      content search across .lsp only, with file:line
  index             force a rebuild of the symbol index

module = folder name (pfanchor, pflabel, pftools-lib, ...)
EOF
}

cmd=${1:-help}
[ $# -gt 0 ] && shift

case "$cmd" in
  index) build_index ;;

  find)
    [ $# -ge 1 ] || { echo "usage: pf.sh find <regex>" >&2; exit 2; }
    ensure_index
    awk -F'\t' -v P="$1" 'tolower($1) ~ tolower(P) {
      printf "%-28s %s:%s\n", $1, $2, $3
      if ($4 != "") printf "%-28s   %s\n", "", $4
    }' "$IDX"
    ;;

  show)
    [ $# -ge 1 ] || { echo "usage: pf.sh show <symbol>" >&2; exit 2; }
    ensure_index
    found=0
    while IFS="$(printf '\t')" read -r name rel line _doc; do
      [ "$name" = "$1" ] || continue
      found=1
      printf '===== %s  (%s:%s) =====\n' "$name" "$rel" "$line"
      extract "$SRC/$rel" "$line"
      echo
    done < "$IDX"
    [ "$found" = 1 ] || { echo "no defun named '$1' -- try: pf.sh find $1" >&2; exit 1; }
    ;;

  refs)
    [ $# -ge 1 ] || { echo "usage: pf.sh refs <symbol>" >&2; exit 2; }
    e=$(esc "$1")
    ( cd "$SRC" && grep -rnE "(^|[^A-Za-z0-9:_>-])$e([^A-Za-z0-9:_>-]|$)" \
        --include='*.lsp' --include='*.dcl' --include='*.md' . 2>/dev/null ) \
      | grep -v '/Opendcl_Reference/' \
      | grep -v "(defun[[:space:]]*$1" \
      | sed 's|^\./||'
    ;;

  api)
    [ $# -ge 1 ] || { echo "usage: pf.sh api <module>" >&2; exit 2; }
    f="$SRC/$1/README.md"
    [ -f "$f" ] || { echo "no README at pfsuite/$1/README.md" >&2; exit 1; }
    awk '/^## Public API/ { on = 1 } on && /^## / && !/^## Public API/ { exit } on' "$f"
    ;;

  outline)
    [ $# -ge 1 ] || { echo "usage: pf.sh outline <module>" >&2; exit 2; }
    if [ -f "$SRC/$1/$1.lsp" ]; then f="$SRC/$1/$1.lsp"          # the namesake wins
    else f=$(lsp_files | grep "/$1/" | head -1); fi
    [ -n "$f" ] || { echo "no .lsp under pfsuite/$1/" >&2; exit 1; }
    printf '# %s\n' "$(rel_of "$f")"
    awk '
      /^;;; SECTION/ { s = $0; sub(/^;;;[ \t]*/, "", s); printf "\n%5d  %s\n", NR, s; next }
      /^\(defun/ {
        name = $0; sub(/^\(defun[ \t]+/, "", name); sub(/[ \t()].*$/, "", name)
        printf "%5d      %s\n", NR, name
      }
    ' "$f"
    ;;

  modules)
    awk -F'"' '/\(load \(strcat \*pftools-dir\*/ { print $2 }' "$SRC/pftools-load.lsp" \
      | awk -v S="$SRC" '{
          n = 0; while ((getline l < (S "/" $0)) > 0) n++; close(S "/" $0)
          split($0, p, "/")
          printf "%2d  %-14s %5d lines  %s\n", NR, p[1], n, $0
        }'
    echo "--  (not in load order) pfpalette/pfp-proof.lsp, Diagnostic_Tools/*.lsp"
    ;;

  grep)
    [ $# -ge 1 ] || { echo "usage: pf.sh grep <regex>" >&2; exit 2; }
    ( cd "$SRC" && grep -rnE "$1" --include='*.lsp' . 2>/dev/null ) \
      | grep -v '/Opendcl_Reference/' | sed 's|^\./||'
    ;;

  *) usage ;;
esac
