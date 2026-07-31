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

**Do not Read whole .lsp files.** Three skills cover the work:

- **`pf-find`** — where a symbol is, what calls it, show one defun, a module's
  public API. `bash .claude/skills/pf-find/pf.sh find|show|refs|api|outline`
- **`pf-change`** — prefix→module map, load-order guardrail, the write-free
  palette contract, and which of the sixteen .md files answers a question.
  Read before editing anything or opening a project doc. Wiring an OpenDCL
  control is its own reference (`pfsuite-odcl/OPENDCL-WIRING.md`) — read that
  before touching a handler; none of it is inferable from the code.
- **`pf-verify`** — `bash .claude/skills/pf-verify/pfcheck.sh` runs the static
  gates (parens, dupes, undefined calls, load order, dead code, API drift) in
  ~6s. Run it after every .lsp edit; it also lists the CAD gates only Jake can
  run.

Per-module contracts live in `pfsuite/<module>/README.md`, not in this file.
