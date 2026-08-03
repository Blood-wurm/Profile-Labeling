# Version 5.1 — scope

**Status: scoping. Nothing here is designed and nothing is built.** Drafted
2026-07-31 from Jake's forward-looking list, checked against the tree the same
day. V5 is ~95% complete by Jake's own read, with real bugs still open —
this document describes the cycle *after* those close, not a reason to start
early.

Live V5 work is [`OPEN-ISSUES.md`](OPEN-ISSUES.md); resolved work and the
outstanding CAD gates are [`CLOSED_ISSUES.md`](CLOSED_ISSUES.md).

---

## 1. The list, as filed

1. Fix water labeling
2. Quantities
3. Pipe clearance
4. Minimum coverage and other checks
5. Other utility types (gas, electric, forcemain)
6. Hydraflow report (`pfreport`) and/or `pf2sew`
7. A drawing report listing the label status of all lines — **and a rename**:
   this becomes `pfreport`, the existing Hydraflow tool becomes `pf2hf`
8. A Hydraulics tab for `pf2sew`, if it can be got off the ground

## 2. The same list, regrouped

Eight items, but not eight pieces of work. They collapse into four tracks plus
a rename:

| Track | Absorbs | Why they are one thing |
|---|---|---|
| **A — Rename** | 7 (half) | Mechanical, blocks nothing but is blocked *by* nothing. Cheapest first. |
| **B — Pressure utilities** | 1, 5, and the coverage half of 4 | Water, gas, forcemain and electric are all non-gravity. One data-model change, three symptoms. |
| **C — `PFCHECK` + `pfreport`** | 3, 4, 7 (half) | Clearance, coverage and label status are all *validation over the registry*. One engine, one report surface. |
| **D — Quantities** | 2 | A fourth consumer of the same registry-row seam as `pf2hf` / `pf2sew` / `pfreport`. |
| **E — `pf2sew` depth** | 6, 8 | Gated on CAD proving the `.SEW` export round-trips. |

## 3. Track A — the rename

`pf2hf` / `pf2sew` / `pfreport` is a better taxonomy than what exists: the
`pf2*` names are **exports to a foreign tool**, `pfreport` is **what the drawing
says about itself**. That distinction reads correctly at a glance; the current
naming does not.

**Cost.** `pfreport/pfreport.lsp` is 57 `pfr:` defuns. The rename touches:

- every `pfr:` symbol → `pfhf:` (or whatever prefix wins) — the whole file
- folder `pfreport/` → `pf2hf/`, plus its `README.md`
- `pftools-load.lsp` load-order entry
- `C:PFREPORT` / `C:PFR` command names and aliases
- palette wiring: the Commands tree entry, `*pfp-controls*` if named, the order
  ticket's command token
- `pf-verify`'s API-drift check will flag the README until it is updated in the
  same pass

**Sequencing note.** It is mechanical and the static gates catch the misses, but
it rewrites every line of the file. It must land **before** anything new is
built on it — doing it afterwards means rebasing new work through a whole-file
rename. It should be its own pass, its own CAD smoke test, and nothing else in
the same change.

**Prefix decision needed.** `pfr:` is freed for the new drawing report only if
the Hydraflow tool takes something else. `pfhf:` is the obvious candidate.
Note `pf2sew.md:24` currently reserves `pfh:` for a tool that shipped as
`pfsew:` — settle the whole prefix table in this one pass rather than twice
(see §9).

## 4. Track B — pressure utilities

**This is the spine of the cycle.** Items 1, 5 and half of 4 are one change.

Everything in V5 assumes **gravity**: `_INV` / `_TOP` profile roles
(`*pf-pro-roles*`), invert-rises-through-structure checks, adverse-slope
warnings, structure drops, `pf:pipe-at` deriving size from `(TOP − INV) × 12`.

Water is *already listed* as a supported type — `*pf-types*` has it,
`*pf-materials*` gives it `DI` / `PVC` / `COPPER`, and there are label and
crossing templates for it (`pftools-cfg.lsp:118-152`). So it looks supported.
But a pressure main has no invert story: it has a **top of pipe and a cover
depth**, not an invert and a slope, and it has no structures in the gravity
sense — valves and fittings, not manholes with in/out inverts.

**Working hypothesis:** "water labeling is broken" *is* that mismatch surfacing,
not a template bug. If that is right:

- Gas, forcemain and electric are nearly free once the pressure model exists.
  They are the same shape as water, differing only in material lists, label text,
  and whether a size/material is even known.
- **Minimum coverage becomes expressible.** It is a pressure-utility check —
  depth of cover below finished grade — and it needs the surface. The existing
  `DESIGN_` / existing `.tin` bindings are already collected, checksummed and
  stored, and currently consumed by nothing (`pf:tin-load` / `pf:tin-z` are dead
  per LOW-6). **This track is what makes them live.** That is a strong signal the
  original design anticipated exactly this.
- Forcemain is the interesting edge: it is sanitary by system and pressure by
  behaviour. Decide early whether it is a `*pf-types*` entry or a *flag* on
  SANITARY, because that choice propagates into every scoping test.

**This track cannot start until the water question in §8 is answered.** The
answer decides whether it is a config edit or a model change — the difference
between a day and several weeks.

## 5. Track C — `PFCHECK` and the new `pfreport`

Clearance, coverage and label status are all validation over the registry, and
the suite already has most of the parts scattered:

- A **finding grammar** — `pfr:fatal` / `pfr:warn` / `pfr:report` — but it lives
  inside the Hydraflow export, and `pfr:validate` is gravity/storm-specific.
- A **name and a promise**: `PFCHECK` is announced in the loader banner
  (`pftools-load.lsp:54`, "Coming this cycle") and has never been built.
- A **queued first rule**: the reciprocal `X_` continuity check, already designed
  in OPEN-ISSUES under Design decisions, already assigned to `PFCHECK`, and
  needing no new storage.

**The move:** lift the finding grammar out of the exporter into `PFCHECK` as a
standalone engine that no export owns, and make the new `pfreport` its report
surface. Then every one of these is a rule, not a feature:

- label status per line (item 7)
- pipe clearance at crossings (item 3)
- minimum coverage (item 4, after Track B)
- reciprocal `X_` continuity (already scoped)
- `pf2hf`'s existing gravity validation, called through the same vocabulary

One place to add a rule, one place it is reported. Without this, item 3 and item
4 each grow their own private warning path and the third copy of "warn about this
line" gets written before the cycle ends.

**Scope risk — clearance.** Vertical separation *at crossings* is a bounded
problem: the crossing set already exists, both elevations are already on record,
subtract and compare. **Horizontal parallel separation** (the 10 ft water/sewer
rule) is a different problem — alignment-against-alignment over a range, not a
point comparison — and it is the single item on this list most likely to become
the biggest. Answer §8 before committing to it.

## 6. Track D — quantities

`pfr:run`, `pfsew:run` and a future quantities engine all consume the identical
input: a list of `pfa:registry` rows. Both existing engines document themselves
as "consumes a list of `pfa:registry` rows and does everything. Pure read." At
three consumers, a shared row→line-view layer stops being speculative —
`pf2sew` has already grown half of one in `pfsew:node-*`.

Quantities needs **scope before design**. Three questions with very different
price tags:

- **What is counted?** Pipe LF by size / material / type and structure counts by
  type is the small version. Trench and excavation volumes, bedding, or surface
  restoration is a much larger one and needs typical sections.
- **Where does it land?** A table drawn in the drawing, a CSV, or a palette tab.
  A drawn table means `pfdraw` work and a ledger story (it is an entity the suite
  now owns, so `PFREMOVE` has an opinion).
- **Does it need to reconcile with anything?** If quantities have to tie to a bid
  form, the categories are dictated externally and that is the real spec.

Cheap once Track C exists (same seam, same row view), expensive before it.

## 7. Track E — `pf2sew` depth and the Hydraulics tab

Correctly last, and gated on two things that are not code:

1. **CAD has to prove the `.SEW` round-trips** — that Carlson opens the file and
   the network reads correctly. Everything downstream is speculative until then.
2. **The unanswered design question from `pf2sew.md`:** does anything ever need
   to come *back* from Carlson? If yes, this is not a tab — it is an import path,
   and it reshapes the module. Answer it before drawing any tab.

The options seam (`pfsew:opt` / `pfsew:opt-num` / `pfsew:set-opt`) was built for
exactly this and is the right place for a hydraulics page to attach.

## 8. Questions that block work

Ordered by how much they change:

1. **What exactly goes wrong with water labeling today?** Wrong template or
   layer in the output, or the invert machinery refusing to produce a sensible
   label at all? This decides whether Track B is a config fix or a model change,
   and Track B is what items 4 and 5 sit on.
2. **Clearance — vertical at crossings only, or horizontal parallel separation
   too?** Vertical is bounded. Horizontal is a new geometry problem and could
   outweigh everything else in the cycle.
3. **Gas and electric — do they carry size and material the way water does?**
   Electric duct bank and unknown-depth gas may only ever need a crossing
   callout, not a full profile label. If so they are much cheaper than water and
   should be scoped separately from it.
4. **Forcemain — its own `*pf-types*` entry, or a pressure flag on SANITARY?**
   Affects every same-type scoping test in the suite.
5. **Quantities — what is counted, and where does the output land?** (§6.)

## 9. Doc debt found while scoping

Not V5.1 features; cheap to fix and they will mislead if left.

- **`pfsuite-md/pf2hydro.md` and `pfsuite/pf2sew.md` are the same design doc.**
  Two homes for one fact, against the suite's own rule. Retire one.
- **`pf2sew.md:24` still reserves the prefix `pfh:`** for a tool that shipped as
  `pfsew:`. Fold this into the Track A prefix pass.
- **`pf-change`'s routing table pointed at `pfsuite-md/REFACTOR-PLAN.md`, which
  does not exist**, and at the retired `Low_Priority_issues.md`. Corrected
  2026-07-31 with this split; re-check the table whenever a doc moves.
- **`pfanchor/INDEX-PLAN.md` is not in the routing table** alongside
  `INDEX-DESIGN.md` / `INDEX-VALUES.md`.

## 10. Proposed order

0. **Close out V5** — the open PFLABEL dropped-structures bug, and the nine CAD
   gates in CLOSED_ISSUES.md. Do not build V5.1 on an unverified V5.
1. **Track A** — the `pfreport` → `pf2hf` rename. Mechanical, own pass, own
   smoke test.
2. **Track B** — the pressure-utility model. Fixes water, unlocks gas /
   forcemain / electric, makes the `.tin` bindings live.
3. **Track C** — `PFCHECK` plus the new `pfreport`: label status, clearance,
   coverage, reciprocal continuity.
4. **Track D** — quantities, on the shared row-view seam.
5. **Track E** — `pf2sew` hydraulics, after CAD proves the export.

Steps 1 and 2 are independent; either can go first. Step 3 depends on 2. Step 4
is cheap after 3 and expensive before it.
