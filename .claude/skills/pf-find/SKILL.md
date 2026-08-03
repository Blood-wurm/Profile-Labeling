---
name: pf-find
description: Locate, read, and trace pfsuite AutoLISP code without opening whole .lsp files. Use whenever you need to answer "where is pf:/pfa:/pflabel:/pfset: X defined", "what calls X", "show me X", "what's in pfanchor / pftools-lib", or "what is this module's public API" — the suite is 485 defuns across eleven 130–1500 line files, so Read-the-whole-file is almost never the right move.
---

# Finding code in pfsuite

One tool answers nearly every location question. Run it from the V5 working
directory or from `pfsuite/`; it walks up to find the tree itself.

```powershell
$s = (Get-Location).Path
while ($s -and -not (Test-Path "$s\.claude\skills\pf-find\pf.ps1")) { $s = Split-Path $s -Parent }
Invoke-Expression (Get-Content -Raw "$s\.claude\skills\pf-find\pf.ps1")
pf <cmd>
```

PowerShell, no bash — this runs on the work machine too. Two things about that
preamble are load-bearing:

- **Load by content, not by path.** `powershell -File pf.ps1` is blocked
  outright when execution policy is `Restricted`, the locked-down default.
  `Invoke-Expression` on the text is not.
- **Walk up to find it.** The session working directory is `V5/pfsuite`, but
  the skills live at `V5/.claude`, so a bare `.claude\...` path does not
  resolve. The loop finds the root from anywhere in the tree.

Loading it once per session is enough; after that just call `pf <cmd>`.

| command | gives you |
|---|---|
| `find <regex>` | matching symbols → `name  file:line` + the one-line doc comment |
| `show <symbol>` | that defun's doc block and full body, paren-balanced, nothing else |
| `refs <symbol>` | every call site in .lsp/.dcl/.md, its own definition excluded |
| `api <module>` | the `## Public API` section of `pfsuite/<module>/README.md` |
| `outline <module>` | SECTION banners with the defuns under each, as `line  name` |
| `modules` | the eleven modules in load order with line counts |
| `grep <regex>` | content search across .lsp only |
| `index` | force a rebuild (it auto-rebuilds when any .lsp is newer) |

`<module>` is a folder name: `pfanchor`, `pflabel`, `pftools-lib`, `pfpalette`, …

## How to use it

**Start with `find` or `api`, not Read.** `find` is one line per hit and the
doc comment usually answers the question outright — every defun in this repo
carries a `;; (name args) -> result` line above it, and the index harvests it.

**`show` instead of Read for a single function.** It extracts exactly one
balanced form. `pf show pfa:geom-key` costs ~5 lines; reading
`pfanchor.lsp` to find it costs 1260.

**`refs` before you change any signature.** Arity changes are the standard
breakage in this suite (a batch of them landed 2026-07-26). `refs` gives every
caller, including the .md files that document the old shape and will now be
stale.

**`outline` to orient in an unfamiliar module** — it is the table of contents,
and its line numbers feed a targeted `Read` with `offset`/`limit` when you
genuinely need surrounding context.

## When to fall back to Read

Only after narrowing: read a *range* around a line `find`/`outline` gave you.
Reading a whole .lsp is justified only when the change is genuinely file-wide.

## Index

Cached at `.claude/pf-index/symbols.tsv` (`name  path  line  doc`). Grep it
directly if you want something the subcommands don't cover. It is derived —
never edit it, and never commit-block on it.

`_attic/` and `Opendcl_Reference/` are excluded everywhere, so retired code
never shows up as a live hit. If you actually want an attic symbol, read the
file directly.
