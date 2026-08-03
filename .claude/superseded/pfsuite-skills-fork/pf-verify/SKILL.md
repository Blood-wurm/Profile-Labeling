---
name: pf-verify
description: Run the pfsuite static gates after editing any .lsp — paren balance, duplicate defuns, calls with no defun, load-order forward references, dead code, and README Public-API drift. Use after every LISP edit and before reporting a change complete, instead of re-reading files to convince yourself it is sound. Also lists the CAD gates that only Jake can run.
---

# Verifying a pfsuite change

## Static gates — run these yourself

```
bash .claude/skills/pf-verify/pfcheck.sh            # all, ~6s
bash .claude/skills/pf-verify/pfcheck.sh parens     # or: dupes undefined order dead api
```

Exit 0 = pass. Six checks, string- and comment-aware so prose never trips them:

1. **paren balance** — per file, reporting the line the outermost unclosed
   form opens at. This is the failure mode of hand-edited AutoLISP and there
   is no compiler to catch it.
2. **duplicate defuns** — the same name defined twice; the second silently wins.
3. **called but never defined** — any `pf*:` symbol invoked with no defun
   anywhere. Catches typos and half-finished renames.
4. **load-order guardrail** — a file may only use symbols owned by files above
   it in `pftools-load.lsp`. Four sanctioned exceptions are baselined in
   `.claude/pf-index/order-baseline.txt`; the gate reports only *new* ones.
5. **dead code** — defined but referenced nowhere in .lsp code, action-string
   callbacks, .dcl or .odcl. Advisory (25 today; this is the repo's tracked
   LOW item — `pfsuite-md/OPEN-ISSUES.md` LOW-6).
6. **README API drift** — a symbol documented in a module README's
   `## Public API` with no defun behind it.

Only 1–4 fail the run. 5 and 6 print notes.

## Reading the results

A gate that goes red on something pre-existing and sanctioned is a gate that
gets ignored. If a new forward reference is deliberate, **document it in the
module README first** (the existing four all say "resolved at call time"),
then append the exact line to the baseline. Never baseline silently.

If you changed a signature, `pf.sh refs <symbol>` (skill `pf-find`) is part of
verification, not part of exploration — the static gates check that callers
exist, not that they pass the right number of arguments.

## CAD gates — Jake runs these, you cannot

There is no AutoCAD here. Never claim a change is verified on the strength of
the static gates alone; say what passed statically and name the CAD gate still
outstanding. The standing ones:

- **load + banner** — `pftools-load.lsp` clean, banner prints.
- **`PFPRELOAD` after any `.odcl` save.** `dcl-Project-Load` does nothing when
  the project is already loaded unless `ForceReload` is `T`, and `*pfp-loaded*`
  is session-long. Skipping this makes correct fixes look like failures — it
  cost a full session on 2026-07-27.
- **write-free contract** — `PFPDBMOD` delta across a palette session must be
  zero (clean 29→29, populated 21→21).
- **deferred fire** — a palette-queued command must prompt, and one `U` must
  peel the work.
- **Esc ledger flush** — `pfsuite-md/TESTING.md` §8.9, both directions, across
  PFLABEL / PFINVERT / PFXLABEL.

Procedures live in `pfsuite-md/TESTING.md` and `pfsuite-odcl/PALETTE-TESTING.md`.
Cite the section number rather than restating the steps.
