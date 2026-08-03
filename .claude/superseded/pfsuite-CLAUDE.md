# V5 — PFTools AutoLISP/OpenDCL suite

`pfsuite/` is 485 `defun`s across eleven .lsp files (130–1500 lines each),
loaded in a fixed dependency order. There is no compiler and no AutoCAD here.

**Talk it through before writing anything.** Default to discussion: investigate,
read, run the gates, put the proposed approach in the reply — then stop. Do not
create or edit a `.lsp`, `.md`, `.odcl` or `.dcl` until Jake has seen the shape
of it and said go. "Go" / "do it" / "build it" is the signal; a question is not,
and neither is "can you" or "I want a lisp that…". When a request sounds like an
order to code, answer it as a design question first. Nothing written here is
verified until Jake runs it in CAD — there is no compiler and no AutoCAD in this
repo — so code that lands before the design is settled costs a CAD session to
discover it was the wrong shape.

**Do not Read whole .lsp files.** Four skills cover the work.

`pf-find` and `pf-verify` are PowerShell and run on **either** machine. Open
the SKILL.md for the exact loader — it is three lines, and both of its quirks
matter: load by *content* (`powershell -File` is blocked under the work
machine's `Restricted` execution policy) and walk up to find `.claude`
(the working directory is `V5/pfsuite`, the skills are at `V5/.claude`).

- **`pf-find`** — where a symbol is, what calls it, show one defun, a module's
  public API. `pf find|show|refs|api|outline|modules|grep|index`
- **`pf-change`** — prefix→module map, load-order guardrail, the write-free
  palette contract, and which of the project .md files answers a question.
  Read before editing anything or opening a project doc. Wiring an OpenDCL
  control is its own reference (`pfsuite-odcl/OPENDCL-WIRING.md`) — read that
  before touching a handler; none of it is inferable from the code.
- **`pf-verify`** — `pfcheck` runs the static gates (parens, dupes, undefined
  calls, load order, dead code, API drift) in ~5s. Run it after every .lsp
  edit; it also lists the CAD gates only Jake can run.
- **`pf-trim`** — comment bloat: narrative rationale, dated field notes,
  eulogies for deleted code. `sh .claude/skills/pf-trim/trim.sh
  scan|blocks|flag|apply|check` surfaces only the blocks worth editing and
  splices rewrites back without re-quoting the old text. Never Read-then-Edit
  a .lsp to trim it. **Bash only — home machine only.** On the work machine,
  leave comment bloat alone rather than hand-editing it.


Per-module contracts live in `pfsuite/<module>/README.md`, not in this file.
