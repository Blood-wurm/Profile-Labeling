#!/usr/bin/env sh
# trim.sh -- comment-trimming workbench for the pfsuite AutoLISP tree.
# Surfaces ONLY the comment blocks worth editing, splices rewrites back in
# without re-quoting the old text, and proves no code line moved.
# The keep/cut rule lives in SKILL.md. Run every verb from the V5 root.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
SRC="$ROOT/pfsuite"
BASE="$ROOT/.claude/pf-index/trim-base"

MIN=${PF_TRIM_MIN:-3}          # a "block" is this many non-rule comment lines

# Archaeology markers: high-precision signals that a block is a field note,
# a version history, or a eulogy for deleted code rather than a contract.
MARKERS='20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]|[Ff][Ii][Ee][Ll][Dd][- ][Cc][Aa][Uu][Gg][Hh][Tt]|field report|field-tested|[Dd][Ee][Ll][Ee][Tt][Ee][Dd] [0-9]|used to |an earlier version|[Tt]he first version|no longer |[Ss][Ee][Tt][Tt][Ll][Ee][Dd] |[Mm][Ee][Aa][Ss][Uu][Rr][Ee][Dd] |for part of|round trip|milestone|[Ww]as [0-9]'

usage() {
  cat <<'EOF'
pf-trim -- trim comment bloat without reading whole .lsp files

  scan                      every .lsp ranked by comment-block weight
  outline <file.md>         heading map of a doc: line range + size + markers
  dupes                     passages repeated across .md files (the safe cuts)
  blocks <file> [--flagged] emit the >=3-line comment blocks, tagged @start-end
                            (also stashes the code baseline for `check`)
  flag <file>               only the blocks carrying archaeology markers,
                            as an ID list to approve for deletion
  apply <file> <rewrites>   splice rewrites in; @start-end headers, empty
                            body = delete the range
  check <file>              prove no code line moved, then run the gates
  save <file>               stash the code baseline by hand

<file> is relative to pfsuite/ (e.g. pfanchor/pfanchor.lsp).
EOF
  exit 1
}

# Code-only view: trailing comments stripped, string literals kept, blanks
# dropped. Same string-literal handling as pfcheck.sh's no_comments.
strip_code() {
  awk '{
    out = ""; n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      if (instr) { out = out c; if (c == "\\") { i++; out = out substr($0, i, 1) } else if (c == "\"") instr = 0; continue }
      if (c == "\"") { instr = 1; out = out c; continue }
      if (c == ";") break
      out = out c
    }
    gsub(/[ \t]+$/, "", out)
    if (out != "") print out
  }' "$1"
}

resolve() {
  f="$SRC/$1"
  [ -f "$f" ] || { echo "no such file: $1 (relative to pfsuite/)" >&2; exit 1; }
  printf '%s' "$f"
}

baseline_path() { printf '%s/%s.txt' "$BASE" "$(echo "$1" | tr '/' '_')"; }

do_save() {
  mkdir -p "$BASE"
  strip_code "$(resolve "$1")" > "$(baseline_path "$1")"
  echo "baseline saved: $(wc -l < "$(baseline_path "$1")" | tr -d ' ') code lines"
}

# ---- outline (Markdown) --------------------------------------------------
# Heading map of a doc: each section's line range, size, and how many lines in
# it carry archaeology markers. Feed the ranges straight to `apply`.
# NOTE there is no `check` for Markdown -- prose has no invariant to prove.
# The doc IS the content, so every cut is judgment. Only delete a passage you
# have confirmed lives somewhere else (see `dupes`).
do_outline() {
  f="$SRC/$1"
  [ -f "$f" ] || { f=$1; [ -f "$f" ] || { echo "no such file: $1" >&2; exit 1; }; }
  echo "# $1  --  $(wc -l < "$f" | tr -d ' ') lines"
  printf '%8s %6s %5s  %s\n' range lines mark heading
  awk -v MARK="$MARKERS" '
    /^#{1,6} / {
      if (h != "") printf "%4d-%-4d %5d %5d  %s%s\n", s, NR-1, NR-s, m, ind, h
      h = $0; s = NR; m = 0
      lvl = length($0) - length(substr($0, match($0, /[^#]/)))
      ind = substr("                ", 1, 2 * (lvl - 1))
      sub(/^#+[ ]*/, "", h)
      next
    }
    { if ($0 ~ MARK) m++ }
    END { if (h != "") printf "%4d-%-4d %5d %5d  %s%s\n", s, NR, NR-s+1, m, ind, h }
  ' "$f"
}

# ---- dupes ---------------------------------------------------------------
# Passages repeated across .md files. THE ONLY .md cut with a proof behind it:
# a line that exists in two docs can lose one copy without losing the fact.
do_dupes() {
  find "$SRC" -name '*.md' -not -path '*/.claude/*' | sort | while IFS= read -r f; do
    awk -v F="${f#"$SRC"/}" '{ s = tolower($0)
      gsub(/[`*_#>|-]/, "", s); gsub(/[ \t]+/, " ", s); gsub(/^ | $/, "", s)
      if (split(s, w, " ") >= 10) print s "\t" F }' "$f"
  done | sort | awk -F'\t' '
    { if ($1 == prev) { files = files "," $2; n++ }
      else { if (n > 1) print n "\t" files; prev = $1; files = $2; n = 1 } }
    END { if (n > 1) print n "\t" files }' \
  | sort | uniq -c | sort -rn | awk '{ printf "%5d shared lines: %s\n", $1, $3 }'
}

# ---- scan ----------------------------------------------------------------
do_scan() {
  printf '%-30s %6s %7s %7s  %s\n' file code blocks lines pct
  find "$SRC" -name '*.lsp' 2>/dev/null \
    | grep -v '/Opendcl_Reference/' | grep -v '/_attic/' | sort \
    | while IFS= read -r f; do
        awk -v REL="${f#"$SRC"/}" '
          { s = $0; gsub(/^[ \t]+/, "", s)
            if (s ~ /^;/) {
              if (s !~ /^;+[ ]*[-=]{5,}/) { n++ }
              next
            }
            if (n >= MINB) { blocks++; lines += n }
            n = 0
            if (s != "") code++
          }
          END { if (n >= MINB) { blocks++; lines += n }
                pct = (code > 0 ? int(100 * lines / code) : 0)
                printf "%-30s %6d %7d %7d  %d%%\n", REL, code, blocks, lines, pct }
        ' MINB="$MIN" "$f"
      done
}

# ---- blocks / flag -------------------------------------------------------
# Emits each qualifying run of comment lines with its line range and the
# defun it documents. Rule lines (;;;=====) are printed inside a block but
# never counted toward the threshold -- they are KEEP-BY-DEFAULT decoration.
emit_blocks() {
  awk -v MINB="$MIN" -v ONLYFLAG="$2" -v MARK="$MARKERS" -v IDONLY="${3:-0}" '
    function flush(   i, body) {
      if (nn >= MINB) {
        hit = 0
        for (i = 1; i <= cnt; i++) if (buf[i] ~ MARK) hit = 1
        if (!ONLYFLAG || hit) {
          id++
          if (IDONLY) {
            printf "%3d  @%d-%d  %s\n", id, start, start + cnt - 1, substr(firsttext, 1, 68)
          } else {
            printf "\n@%d-%d%s\n", start, start + cnt - 1, (hit ? "  [FLAGGED]" : "")
            for (i = 1; i <= cnt; i++) print buf[i]
          }
        }
      }
      cnt = 0; nn = 0; firsttext = ""
    }
    { s = $0; gsub(/^[ \t]+/, "", s)
      if (s ~ /^;/) {
        if (!cnt) start = FNR
        buf[++cnt] = $0
        if (s !~ /^;+[ ]*[-=]{5,}/) {
          nn++
          if (firsttext == "") { t = s; sub(/^;+[ \t]*/, "", t); firsttext = t }
        }
        next
      }
      if (cnt) {
        # name the defun this block sits on, when there is one
        if (!IDONLY && nn >= MINB && $0 ~ /^\(defun/) {
          d = $0; sub(/^\(defun[ \t]+/, "", d); sub(/[ \t()].*$/, "", d)
          pend = d
        }
      }
      flush()
      if (pend != "") { printf "    ^ documents (defun %s)\n", pend; pend = "" }
    }
    END { flush() }
  ' "$1"
}

do_blocks() {
  f=$(resolve "$1")
  only=0
  [ "${2:-}" = "--flagged" ] && only=1
  do_save "$1" >/dev/null
  mkdir -p "$BASE"
  strip_code "$f" > "$(baseline_path "$1")"
  echo "# $1  --  $(wc -l < "$f" | tr -d ' ') lines, baseline stashed"
  echo "# rewrite these as @start-end chunks; empty body deletes the range."
  emit_blocks "$f" "$only" 0
}

do_flag() {
  f=$(resolve "$1")
  echo "# $1 -- blocks carrying archaeology markers"
  echo "# approve deletion by ID, or rewrite via \`blocks\`."
  emit_blocks "$f" 1 1
}

# ---- apply ---------------------------------------------------------------
# Rewrites file: "@start-end" header, then the replacement lines. An empty
# body deletes the range. Ranges come from one `blocks` run, so they all
# refer to the SAME original numbering -- the splice is single-pass and
# order-independent.
do_apply() {
  f=$(resolve "$1")
  rw=$2
  [ -f "$rw" ] || { echo "no such rewrites file: $rw" >&2; exit 1; }
  tmp="${TMPDIR:-/tmp}/pftrim.$$"
  awk '
    FNR == NR {
      if ($0 ~ /^@[0-9]+-[0-9]+[ \t]*$/) {
        split(substr($0, 2), r, "-")
        cur = r[1] + 0; endof[cur] = r[2] + 0; seen[cur] = 1; ntext[cur] = 0
      } else if (cur) {
        text[cur, ++ntext[cur]] = $0
      }
      next
    }
    {
      if (skipto) { if (FNR <= skipto) next; skipto = 0 }
      if (seen[FNR]) {
        for (i = 1; i <= ntext[FNR]; i++) print text[FNR, i]
        skipto = endof[FNR]
        next
      }
      print
    }
  ' "$rw" "$f" > "$tmp" || { rm -f "$tmp"; exit 1; }
  mv "$tmp" "$f"
  echo "applied: $1 is now $(wc -l < "$f" | tr -d ' ') lines"
}

# ---- check ---------------------------------------------------------------
do_check() {
  f=$(resolve "$1")
  b=$(baseline_path "$1")
  [ -f "$b" ] || { echo "no baseline for $1 -- run \`blocks\` or \`save\` first" >&2; exit 1; }
  now="${TMPDIR:-/tmp}/pftrim-now.$$"
  strip_code "$f" > "$now"
  if diff -q "$b" "$now" >/dev/null 2>&1; then
    echo "  ok   code byte-identical ($(wc -l < "$now" | tr -d ' ') lines)"
    rm -f "$now"
  else
    echo "  FAIL code changed -- comments only, this must never happen:"
    diff "$b" "$now" | head -20
    rm -f "$now"
    exit 1
  fi
  sh "$ROOT/.claude/skills/pf-verify/pfcheck.sh" parens
  sh "$ROOT/.claude/skills/pf-verify/pfcheck.sh" api
}

cmd=${1:-}
case "$cmd" in
  scan)    do_scan ;;
  outline) [ $# -ge 2 ] || usage; do_outline "$2" ;;
  dupes)   do_dupes ;;
  blocks) [ $# -ge 2 ] || usage; do_blocks "$2" "${3:-}" ;;
  flag)   [ $# -ge 2 ] || usage; do_flag "$2" ;;
  apply)  [ $# -ge 3 ] || usage; do_apply "$2" "$3" ;;
  check)  [ $# -ge 2 ] || usage; do_check "$2" ;;
  save)   [ $# -ge 2 ] || usage; do_save "$2" ;;
  *)      usage ;;
esac
