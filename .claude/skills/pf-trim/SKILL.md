---
name: pf-trim
description: Trim comment bloat out of pfsuite .lsp files without reading them whole. Use when comments are burying the code — narrative rationale, dated field notes, version history, eulogies for deleted code. Surfaces only the comment blocks worth editing, splices rewrites back without re-quoting the old text, and proves byte-for-byte that no code line moved. Run it instead of Read-then-Edit, which costs 4-5x more for the same result.
---

# Trimming comments in pfsuite

The suite carries ~3,700 lines of multi-line comment prose against ~7,700 lines
of code. Most of it restates the module README. Trimming it by reading files and
hand-editing costs roughly 65k tokens per file; this skill costs a quarter of
that, because you never read the .lsp and never re-type the old text.

    sh .claude/skills/pf-trim/trim.sh <verb>      # from the V5 root

## The loop

    trim.sh scan                      # rank the files
    trim.sh blocks <file>             # emit ONLY the >=3-line comment blocks
    trim.sh flag <file>               # which of those carry archaeology
    trim.sh apply <file> <rewrites>   # splice your new text in
    trim.sh check <file>              # prove no code moved, run the gates

`<file>` is relative to `pfsuite/` — `pfanchor/pfanchor.lsp`.

**Never `Read` the .lsp.** `blocks` gives you the block, its line range, and the
`defun` it documents. That is everything the rewrite needs.

## Writing the rewrites file

One `@start-end` header per block, then the replacement lines. An empty body
deletes the range outright.

    @120-141
    ;; (pfp:defer cmdline) -> T | nil
    ;;   Queue a command from a modeless handler; it runs after the handler
    ;;   unwinds.  Refuses, loudly, when the command line is busy.
    @200-214

Ranges all refer to the numbering from **one** `blocks` run — the splice is
single-pass, so they do not shift as chunks are applied. Skip any block that is
already fine; most one- and two-line comments are.

## What stays

- The file header, and `;;; ====` section rule lines. **Keep the rules** —
  they are cheap and Jake reads by them.
- `;;; SECTION n -- title` lines. `pf-find outline` parses these.
- The one-line signature docstring, `;; (fn args) -> result`. **This is tooling
  input** — `pf-find` indexes the `;;` block above each defun and prefers the
  line starting with `(`. Never drop it, never indent it.
- Trailing `; ...` comments on code lines. They are already succinct; leave them.
- A genuine gotcha, compressed to one or two lines.

## What goes

- Dated field notes: `FIELD-CAUGHT 2026-07-27`, `measured 2026-07-29`.
- Version and milestone history: what a thing *used to* be, what changed when.
- Eulogies for deleted code — a block explaining why something is *not* there.
  If the trap is real, one line saying "do not add X, because Y" is the whole
  of it.
- Restatement of the module README's model or contract.
- Multi-paragraph arguments for a decision already made.

## The plain-language rule

A comment that survives must be actionable by a reader **who was not there**.
State the constraint and what to do about it, in plain words. No aphorisms, no
callbacks to a past debugging session.

This block failed that test:

    ;;; So the rule this leaves behind: A FORM RECT COMPLAINT IS A STUDIO ANSWER.
    ;;; Read Width/Height, Min, and Max together before writing any LISP ...

and became:

    ;;   Do NOT add a resize call here: Studio's Min Width/Height clamp the form
    ;;   up, so dcl-Form-Resize cannot shrink it.  Fix the opening size in Studio.

If a block cannot survive that translation — if what is left is only "we tried X
and it did not work" — it is history, not a gotcha. Delete it.

## Check the docs before deleting, not after

Most cut material is already in `pfsuite/<module>/README.md`, or for the palette
in `pfsuite-odcl/PALETTE-LAYOUT.md`, `PALETTE-TESTING.md`, `OPENDCL-WIRING.md`.
One grep settles it:

    grep -rn "Min Width" --include=*.md .

If the fact is documented, delete the block. If it is not and it is
load-bearing, put the **plain** version in the README first — never copy the
original prose across, or the unreadable text just moves.

## Markdown is a different job

    trim.sh outline <file.md>   # heading map: line range, size, marker count
    trim.sh dupes               # passages repeated across .md files

`apply` works on Markdown too — it splices line ranges and does not care about
syntax. **`check` does not.** Prose has no invariant to prove: the doc IS the
content, so every cut is unbacked judgment. Treat the corpus as four kinds:

- **Records** — `CLOSED_ISSUES`, `TESTING`, `PALETTE-TESTING`, `OPEN-ISSUES`.
  History is the point. **Do not trim** — the dated entries are the content.
- **Contracts** — the module READMEs. Code comments now point *here*, so a cut
  can delete the last copy of a fact. Only remove what `dupes` proves is
  duplicated.
- **Design logs** — `PALETTE-LAYOUT.md`, `pfpalette/README.md`, root
  `README.md`, `INDEX-*.md`. The real target: they accumulate "was X, now Y"
  chains where each dated revision corrects the one above it. Keep the final
  answer and the reference tables; drop the correction chain.
- **Superseded drafts** — reduce to a stub that names the replacement, rather
  than deleting, since other docs link to them.

`dupes` is the only .md cut with a proof behind it: a line in two docs can lose
one copy without losing the fact.

## The safety guarantee

Only full-line comments are ever touched, so the comment-stripped file must be
byte-identical before and after. `blocks` stashes that baseline; `check` diffs
it and then runs the paren and API gates. A `FAIL` from `check` means a code
line moved and the rewrite must be redone — it is not advisory.
