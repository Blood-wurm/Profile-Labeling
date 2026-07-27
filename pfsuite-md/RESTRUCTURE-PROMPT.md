# PROMPT — V5 file-structure change (one folder per .lsp)

> Paste this into a fresh session opened at the `pfsuite` folder. It carries
> every decision already made; do not re-litigate them. Written 2026-07-26,
> right after the "Option A" audit batch landed (README §9).

---

## The task

Restructure this folder so that **every `.lsp` lives in its own subfolder with
its own `README.md` beside it**, then land the two structural refactors that
were deliberately deferred to ride along with the move: the shared
`pf:run-command` wrapper (audit #9) and the registry-builder consolidation
(audit #12). Work in three phases, each with its own verification gate. Do not
start a later phase until the earlier one verifies.

**Constraints that hold through all phases:**

- V4 one level up is frozen. Never touched.
- Command-line behavior of `PFSETUP` / `PFLABEL` / `PFINVERT` / `PFXLABEL` /
  `PFREMOVE` / `PFPALETTE` stays identical except where a phase explicitly
  changes it (the Esc-flush in Phase 2 is the only behavior change).
- No function renames beyond the ONE move specified in Phase 3.
- The read/write contract (root README §5) is law: nothing reachable from a
  modeless handler may write the drawing.
- The dependency guardrail is law: a file may only depend on files that load
  before it.

---

## Phase 1 — the move (pure, content-identical)

### Target tree

```
pfsuite/
├── pftools-load.lsp          ← STAYS AT ROOT (the entry point)
├── pfdialog.dcl              ← STAYS AT ROOT (shared asset, path = *pftools-dir* + name)
├── pfsuite.odcl              ← STAYS AT ROOT (same reason)
├── README.md                 ← root orientation doc (stays)
├── OPEN-ISSUES.md  TESTING.md  REFACTOR-PLAN.md
├── RESTRUCTURE-PROMPT.md  Low_Priority_issues.md
├── Dialog examples/          ← unchanged
├── Opendcl_Reference/        ← unchanged
├── pftools-cfg/
│   ├── pftools-cfg.lsp
│   └── README.md
├── pftools-lib/
│   ├── pftools-lib.lsp
│   └── README.md
├── pfdraw/
│   ├── pfdraw.lsp
│   └── README.md
├── pfanchor/
│   ├── pfanchor.lsp
│   └── README.md
├── pfsettings/
│   ├── pfsettings.lsp
│   └── README.md
├── pfsetup/
│   ├── pfsetup.lsp
│   └── README.md
├── pflabel/
│   ├── pflabel.lsp
│   └── README.md
├── pfxlabel/
│   ├── pfxlabel.lsp
│   └── README.md
├── pfinvert/
│   ├── pfinvert.lsp
│   └── README.md
└── pfpalette/
    ├── pfpalette.lsp
    └── README.md
```

Decisions embedded there (already made — keep them):

- **`pftools-load.lsp` stays at root.** It is the entry point and the one
  thing a user `(load)`s; `*pftools-dir*` keeps meaning "the pfsuite root".
- **`pfdialog.dcl` and `pfsuite.odcl` stay at root.** They are cross-file
  shared assets; `pfset:dcl-file` and `pfp:odcl-path` derive their paths from
  `*pftools-dir*` and stay byte-identical because of this choice.

### Code changes in Phase 1 (the complete list)

`pftools-load.lsp` load lines only — each gains one path segment:

```lisp
(load (strcat *pftools-dir* "pftools-cfg/pftools-cfg.lsp"))
(load (strcat *pftools-dir* "pftools-lib/pftools-lib.lsp"))
(load (strcat *pftools-dir* "pfdraw/pfdraw.lsp"))
(load (strcat *pftools-dir* "pfanchor/pfanchor.lsp"))
(load (strcat *pftools-dir* "pfsettings/pfsettings.lsp"))
(load (strcat *pftools-dir* "pfsetup/pfsetup.lsp"))
(load (strcat *pftools-dir* "pflabel/pflabel.lsp"))
(load (strcat *pftools-dir* "pfxlabel/pfxlabel.lsp"))
(load (strcat *pftools-dir* "pfinvert/pfinvert.lsp"))
(load (strcat *pftools-dir* "pfpalette/pfpalette.lsp"))
```

Load order is unchanged: cfg → lib → draw → anchor → settings → setup →
label → xlabel → invert → palette.

Nothing else. Grep for `*pftools-dir*` consumers before declaring done —
today they are exactly `pfset:dcl-file` (pfsettings) and `pfp:odcl-path`
(pfpalette), both root-relative and both unaffected by the choice above. If
you find a third, stop and account for it.

### Per-file README — template and drift rule

Each subfolder README follows this shape:

```markdown
# pfanchor.lsp — record + registry

**Load position:** 4 of 10 (after pfdraw, before pfsettings).
**May depend on:** pftools-cfg, pftools-lib, pfdraw.
**Depended on by:** pfsettings, pfsetup, pflabel, pfxlabel, pfinvert, pfpalette.

## What it owns
(the file's job in 3–6 lines)

## Public API
(the functions other files call — name, one-line contract each.
 Mark pure reads vs writers explicitly: writers require a caller-held
 undo group; reads must be modeless-safe.)

## Invariants
(the file's load-bearing rules — e.g. "erase happens BY HANDLE only",
 "pfa:nod-dict create nil never writes")

## Open issues local to this file
(pulled from OPEN-ISSUES.md / Low_Priority_issues.md where they name
 this file; link, don't copy)
```

**The drift rule:** the narrative contract lives in the README; the `.lsp`
header shrinks to identity + load-order + "see README.md beside this file".
One home per fact. Seed each README from the current `.lsp` header banner
(they are good — move, don't rewrite) plus the "Public API" section, which is
new work: derive it by grepping which `pfX:`/`pfa:`/`pfset:` functions other
files actually call.

### Phase 1 verification gate

1. Static: re-run the paren/symbol audit across the new paths (all files
   balanced; every prefixed call resolves; the audit script just takes the
   new file paths as arguments).
2. Load in CAD from the new layout: full loader banner prints, no load error.
3. `PFPALETTE` opens and populates; `PFLABEL` reaches its run dialog on a
   test drawing. (Full engine regression is Phase-independent — see
   REFACTOR-PLAN — but these two smoke-checks prove the path plumbing.)
4. Update the work-machine path tail in `pftools-load.lsp` if the deploy
   folder name changes again.

---

## Phase 2 — `pf:run-command` wrapper + Esc ledger flush (audit #9)

**Why now:** the wrapper was deferred FROM the audit TO this restructure so
the prologue/epilogue scaffold is written once, not three times and then
moved. It also becomes the fourth caller's home when Tab 2's deferred
`C:PF*RUN` commands land.

**Where it lives:** `pfanchor/pfanchor.lsp`, beside `pfa:undo-cleanup` (all
commands already depend on pfanchor; no load-order change). Replace
`pfa:undo-cleanup`'s transitional role rather than stacking on it.

**What it owns** (today's per-command copies to absorb — currently
quadruplicated across pflabel/pfinvert/pfxlabel/pfsetup + pfremove):

1. save + install the command's `*error*` handler
2. `pf:echo-off` / `pf:echo-on` (fix the non-re-entrancy while absorbing it:
   save-once semantics so a nested call can't clobber the user's CMDECHO)
3. `_.UNDO _Begin` / `_End` + the per-command `*pfX-undo-open*` flag
4. **on the error path, IN THIS ORDER:** ledger-flush hook → close undo
   group → `pf:zoom-onerror` → restore `*error*`
5. the ledger-flush hook itself is per-command (`pflabel:flush-pass` etc.,
   pattern below) — the wrapper takes it as an argument and calls it only
   when the undo group is open

Flush pattern per command (approved in the audit session):

```lisp
;; engine: publish the running ctx, clear it on normal exit
(setq *pflabel-run-ctx* ctx)
...
(pflabel:write-pass ctx)
(setq *pflabel-run-ctx* nil)

;; flush: write the ledger for whatever got drawn before the Esc,
;; INSIDE the still-open group (entmakex/dictadd are *error*-legal)
(defun pflabel:flush-pass ()
  (if (and *pflabel-undo-open* *pflabel-run-ctx*)
    (progn (pflabel:write-pass *pflabel-run-ctx*)
           (setq *pflabel-run-ctx* nil)))
  (princ))
```

PFXLABEL additionally needs `newh` promoted from a `pfxl:run` local to a
run-scoped global so its flush can ledger partial crossing handles.

**Behavior change to announce in TESTING.md:** after an Esc mid-run, drawn
entities are now ON the pass ledger — `pfa:erase-pass`, PFREMOVE, and recon
see them. Before this, they were orphans unless the user pressed `U`.

**Phase 2 gate:** Esc a PFLABEL run mid-parade (turn the zoom parade on to
widen the window); confirm (a) one `U` still peels everything, (b) without
`U`, a re-run's `[LABELED]` marks and `pfa:erase-pass` account for the
partial pass. Repeat for PFXLABEL.

---

## Phase 3 — registry-builder consolidation (audit #12)

**The decided target:** `pfa:registry` + entry-cl resolution is the single
source for "what lines exist"; `pflabel:registry-pairs` becomes a thin filter
over it. Kills the PFLABEL/PFINVERT divergence (different .cl resolution, and
`pfa:all-anchors` not excluding copies) that can make the top label and the
invert label disagree about a junction's combined ID on the same structure.

**The one function move this requires:** `pfxl:entry-cl` currently lives in
pfxlabel, which loads AFTER pflabel — pflabel calling it would violate the
depend-only-upward guardrail. It is pure registry knowledge (registry row →
.cl path), so **move it to pfanchor as `pfa:entry-cl`**, next to
`pfa:registry`. Update the callers (pfxlabel's discovery + pflabel's
run-dialog); leave no alias behind — three call sites, rename them.

**Then:**

- `pflabel:registry-pairs` = walk `(pfa:registry)`, drop self, keep
  `pf:type-of` matches, resolve via `pfa:entry-cl`. Anchors and stubs come
  out of the one merged, copy-excluding, sorted walk.
- `pflabel:run-dialog`'s inline pairs build and `pfi:run-dialog`'s build both
  call the same `pflabel:registry-pairs`. One builder, three consumers.

**Phase 3 gate:** on a drawing with ≥2 same-type lines (at least one a stub)
plus a copied anchor, PFLABEL and PFINVERT must list the identical line set,
and the copy must appear in neither. Compare a junction structure's combined
ID between the two commands — must match.

---

## Out of scope (do not drift into these)

- **Tab 2 / deferred fire / `C:PF*RUN`** — next milestone, after this.
- **Zoom-To checkbox wiring** (audit #13) — Tab 2 work; the `(zoom . T|nil)`
  ticket key is the agreed mechanism; `*pf-zoom-to*` global dies then.
- **Rule-token matching** (audit #7) — blocked on the block-library/rules
  storage decision.
- **`pfs:registry-dialog` demotion to fallback** — milestone 3, once the
  palette has verbs.
- **The LOW list** (`Low_Priority_issues.md`) — separate session.
- **The CAD engine regression gate** (REFACTOR-PLAN: three commands,
  command line, output identical to `..\..\V5` parent) — run it whenever CAD
  time exists; ideally before Phase 2 changes behavior, but it does not block
  Phase 1.

## Done means

- Tree matches the target exactly; loader loads it in CAD.
- Ten per-file READMEs seeded per the template; `.lsp` headers shrunk to
  pointers.
- `pf:run-command` is the only copy of the prologue/epilogue; Esc-flush
  verified both ways.
- One registry builder; Phase 3 gate passes.
- Root README's §2/§8 updated to the new tree; OPEN-ISSUES entries for #9 and
  the builder divergence marked fixed-pending-CAD.
