# HYDRAULICS-DESIGN.md — the Hydraulics tab

**Status:** design only. Nothing in this document is built.
**Date:** 2026-08-02, from a design session with Jake.
**Owns:** the palette surface that authors drainage for `C:PF2SEW`.

Companion docs: [`README.md`](README.md) (what `pf2sew.lsp` owns today),
[`../pf2sew.md`](../pf2sew.md) §6 and §8 step 5 (the drainage ticket this
supersedes for the UI half),
[`../pfsuite-odcl/PALETTE-LAYOUT.md`](../pfsuite-odcl/PALETTE-LAYOUT.md)
(palette structure and the wiring contract this must obey).

---

## 1. Tabs divide by process, not by data

The organising axis for `tabMain`, stated plainly because it decides every
future "which tab does this go on" argument:

| Tab | Process |
|---|---|
| Registry | **anchoring** profiles |
| Commands | **labeling** them |
| Hydraulics | **testing** them |

`Edit` and `New` are Registry-tab buttons — they edit or create registry
entries and belong to anchoring. They are not tab surfaces.

**Settings is not a process.** It configures all three, which is why it sits
alongside them rather than folding into one (§10).

**There is no tab budget.** The form can be resized in Studio if a tab needs
the room; `Min Width` / `Max Width` are a Studio setting, not a constraint on
the design.

---

## 2. Decisions taken

Settled in the 2026-08-02 session. Each closes a fork that was open in
`../pf2sew.md`.

| # | Decision | Consequence |
|---|---|---|
| D1 | **Pipe size and material are always read off `.pro`.** No override store, ever. | Deletes the pipe-key record, the station-range staleness story, and the instance-override tier for size. A stale `.pro` is the drafter's problem: re-cut it. |
| D2 | **Catchment binding is manual.** | No auto-binder. See §4 for why the automatic version is not merely deferred but likely unbuildable. |
| D3 | **Hydrology method is Rational.** | Per structure the drafter authors **C** and **Tc**; area is derived. SCS `ScsCN` stays at its default and is never authored. Closes `../pf2sew.md` §9.6. |
| D4 | **Area is stored as the polyline's handle, never as a number.** | §3. |

### D1's one accepted limit

Material stays **per line**, on the anchor record, as PFSETUP asserts it. A
line whose material changes mid-run has no per-pipe answer;
`*pfsew-opts*`'s `material-default` is the only fallback. This is a known
limit, not an oversight — written here so it is not rediscovered as a bug
during a `.SEW` review.

---

## 3. Area is a handle, not a number

**Binding stores the boundary polyline's handle. Area is recomputed at emit
time.** This is the same rule `pf2sew` already applies twice over: `pfsew:opt`
reads at emit time and never captures at load, and D1 reads pipes off `.pro`
rather than storing them.

What it buys:

- **No staleness machinery.** Edit the boundary, the next export is correct.
  There is no cached number that can disagree with the drawing, so there is no
  "which one is authoritative" question to answer.
- **Provenance is designed in, not bolted on.** `../pf2sew.md` §6 requires an
  answer to "where did this 0.42 ac come from?" **The handle is the answer** —
  that polyline — and the tab can zoom to it. A captured number cannot answer
  it at any price.
- **A deleted boundary is a visible state.** The row reads unbound. A captured
  number would keep exporting after its polyline was erased.

Consequence for the ListView: the Area column is **read-only**. There is no
path by which a drafter types an area, and adding one would forfeit all three
properties above.

---

## 4. Binding is manual, and the automatic version is not a later phase

`../pf2sew.md` §6 assumed an auto-binder — seed outward from the inlet using
`pfa:gather-inlets` / `pfa:lines-at`, cheaper than testing every boundary.
That assumption does not survive contact with how the catchments are drawn.

**The firm draws catchments by hand.** So:

- "Closed polyline on layer X containing the structure" does not identify one
  polyline — two or more routinely fit that description.
- Disambiguating by elevation off the design surface (structure X cannot belong
  to polyline Y because X sits higher) is both expensive and unreliable against
  hand-drawn boundaries.

Containment is therefore not even a dependable **tiebreaker**, which is what an
auto-binder would need it to be. Treat auto-binding as out of scope, not
queued.

**NOTE:** Containment may be a dependable answer. This is a bad assumption.

### The safe half is worth keeping

Containment survives as a **validation**, never as a binder: after a manual
bind, test whether the structure's insertion point falls inside its bound
polyline and flag the row when it does not. That catches a mis-click without
deciding anything — it only ever questions a choice the drafter made, so the
hand-drawn geometry problem cannot make it wrong, only silent.

**NOTE:** Again this reasoning doesn't hold up, Id maybe be ok with auto registry with manual validation to bind. 

---

## 5. The Rational schema hole — BLOCKING

**`<DrainageData>` has no runoff-coefficient attribute.** The full attribute
set, as decoded from `Carlson_References/STORM_CA.sew` and written by
[`pf2sew.lsp:353`](pf2sew.lsp):

```
Type  Area  CatchmentFlow  Tc  ActualTc  Cf  ScsCN  ScsSwampFactor
```

`Cf` is the Rational **frequency adjustment factor**, not C. `ScsCN` is the
SCS branch, which D3 rules out. Rational's **C has nowhere to go.**

The reason this was never caught is that STORM_CA carries `Area="0"` on every
structure — **there is no attested example of a populated drainage record.**
The decode is complete for a file with no drainage authored and unverified for
any other.

Three possibilities, none of them checkable from the tree:

1. C is implied by `Type`, which is always `0` and otherwise unexplained.
2. C lives in an element that appears only once drainage is entered.
3. Carlson expects `CatchmentFlow` directly and C never round-trips.

Riding on the same gap: whether `Area` is **acres or square feet**, what
`Type` selects, and whether `ActualTc` is entered or computed (likely Carlson
applying a minimum Tc to the entered value).

### The artifact that unblocks it

> Open `STORM_CA.sew` in Carlson, hand-author drainage on **one** structure —
> area, C, Tc — save, and diff the `.sew`.

Ten minutes, and it converts the whole hydrology schema from inferred to
attested: all three possibilities above collapse, and the units and `Type`
questions answer themselves in the same diff. Worth doing in the same CAD
session as the `../pf2sew.md` §8 step 4 round trip, since the file is already
open.

**Do not build the tab before this diff exists.** Two of the three authored
fields are C and Tc, and one of them currently has no destination.

---

## 6. Tab roster

Reads top to bottom as *pick a line → author its drainage → export*.
Control names are provisional until they exist in Studio; a name that the
loaded project never defined evaluates to `nil` and fails silently
(`../pfsuite-odcl/OPENDCL-WIRING.md` §1).

| Control | Type | Purpose |
|---|---|---|
| `hydLines` | TreeView | Line picker. Same fill as `tarLines` — `pfp:fill-tree` returns the child-key map per control. |
| `lvwCatch` | ListView (Report) | One row per node from `pfr:build-nodes`. Columns §7. |
| `btnBind` | Button | Deferred. Pick a closed polyline, write the handle to the structure's xdict. |
| `btnUnbind` | Button | Deferred. Clear the binding. |
| `btnZoomArea` | Button | Deferred. Zoom to the bound polyline — the provenance answer, made visible. |
| `btnOptions` | Button | The ~20 `*pfsew-opts*` rows. `pfsew:set-opt` is the waiting write seam. |
| `btnExport` | Button | Deferred → `C:PF2SEW`. |

`AddColumns` is additive and belongs in `#OnInitialize` only; data fill belongs
in the refresh path, after `dcl-Form-Show` returns.

### 6.1 `lvwCatch` columns

| Column | Source | Editable |
|---|---|---|
| Structure | `pfr:struct-id` | no |
| Area | the bound handle, computed at read | **no** — §3 |
| C | per-structure xdict, default from `*pfsew-opts*` | yes |
| Tc | per-structure xdict | yes |
| Bound to | the polyline handle, or "unbound" | no |
| ⚠ | containment check (§4) | no |

C wants a global default in `*pfsew-opts*` with a per-structure override. If
the catchment polylines happened to sit on land-use-specific layers, C could
seed from the layer — but hand-drawn (§4) means that is not dependable enough
to build on.

---

## 7. Storage

**Per structure, extension dictionary, same precedent as
[`../pfanchor/INDEX-DESIGN.md`](../pfanchor/INDEX-DESIGN.md) §4.** Not xdata
(flat, size-limited, needs a registered app), and not attributes (visible and
drafter-editable, which is an advantage until someone edits one and the tool
believes it — and it would require redefining the firm's existing block
library).

```
per structure entity, xdict "PFHYDRO"
  AREA  →  polyline handle           the binding; area computed from it at emit
  C     →  runoff coefficient        Rational
  TC    →  time of concentration     Rational
```

Field names are provisional pending §5 — the diff may rename or add one.

---

## 8. Wiring constraints

From `../pfsuite-odcl/OPENDCL-WIRING.md` §5 and PALETTE-LAYOUT §3. None of
these is inferable from the code; all of them cost a CAD session to rediscover.

- **A modeless handler cannot `entsel`.** Binding picks a polyline, so
  `btnBind` defers. So do unbind, zoom and export.
- **The xdict write is a drawing write.** It happens inside the deferred
  command, under `pf:run-command`, in that body's own undo group — never in the
  handler. `PFPDBMOD` must read flat for every read path on this tab.
- **One dispatcher for the tab**, alongside `C:PFPVERB` (Registry) and
  `C:PFPRUN` (Commands). It keeps `pfsew:` internals private, gives one
  `SendCommand` target, and puts the `CMDACTIVE` gate, the undo mark and the
  refresh in one place.
- **The command line stays independent** (PALETTE-LAYOUT §10). `C:PF2SEW` keeps
  working with the palette closed, unloaded or absent. This tab adds a surface;
  it modifies no existing command.
- **Reads may be inline.** The registry reads this tab needs are the same
  provably write-free paths the other tabs already use.

---

## 9. Not in scope

Recorded so they are not re-proposed:

- Pipe size or material overrides — D1.
- SCS authoring (`ScsCN`, swamp factor) — D3. The keys stay at their defaults.
- Pavement, grate and curb geometry — `*pfsew-opts*` defaults, per
  `README.md`'s "Carlson's own defaults, inert while Area is 0". Once Area is
  **not** 0 this assumption needs re-reading; that is a §5 follow-on.
- Anything coming *back* from Carlson. Still the open question in
  `../pf2sew.md` §8 step 6, and if the answer is yes this is not a tab but an
  import path.

---

## 10. The Settings tab, for the record

Decided in the same session; it has no other home yet. When it is built, its
roster moves to `PALETTE-LAYOUT.md` as a tab section beside §5 and §6, and
this section goes away.

Settings is small, because the investigation found most of the old dialog was
dead. Of the nine prefix/suffix keys in `pflabel:*pflabel-keys*`, **only four
are live** — `sta_pre`, `sta_suf`, `con_suf`, `gl_suf`
([`../pflabel/pflabel.lsp:154`](../pflabel/pflabel.lsp)). The rest are
`is_enabled = false` in the DCL because **`*pf-rule-table*` owns those
prefixes**, per block, which is the per-block editing that was wanted all
along. The rule table has simply never had a UI.

Roster: style list, layer override + `use_clayer` (defaulting PF-ANNO),
`sta_pre`, `sta_suf`, and buttons onto two table editors —
`*pf-rule-table*` and `*pf-materials*`.

Two guardrails, both load-bearing:

- **The rule-table editor must not touch tokens, row order, or the SIZE flag.**
  The table is ORDERED, FIRST MATCH WINS — compounds before singles,
  `("CBI" "MH")` ahead of `("MH")`. A user who adds or reorders a row silently
  mislabels every CBI in the drawing, with no error. Edit the four text columns
  of existing rows; tokens and order stay firm-owned in `pftools-cfg.lsp`.
- **A material added in the editor gets whatever its row says.** This used to
  read "absent from `*pfr-nvalues*` ⇒ silently n = 0.013": that parallel list
  is gone as of 2026-08-04 and n is a column on the material row itself, so
  the editor cannot add a material without one. What it CAN still do is leave
  `DIMS` empty, which is not silent — clearance reports that pipe as
  *unknown* rather than passing it.

Persistence: the settings file is flat `key=value`, and `pfset:read-settings`
splits on the **first** `=` only, so a rule row serialises to one line with no
format change — `rule.3=SMH|CONST.|SANITARY MH||T.R.|`. Application is lazy,
because `pftools-cfg` loads four positions above `pfsettings`: pfsettings
overwrites the global on load and keeps a pristine `*pf-rule-table-default*`
for Revert. That touches **zero** of the six `pf:rule-for` call sites.

Settings edits touch **disk, never the drawing**, so the tab needs no `pfp:defer`
except for the two `getfiled` paths (Load / Save a settings file). Commit model
is explicit **Apply / Revert** — a palette has no OK moment, and Button/Clicked
is the one event class that is certainly safe. `pfp:refresh` must **not** refill
the text boxes, or a stray `btnRefresh` destroys uncommitted typing; the
layer/style lists do refill there, since they follow the document.

**Unmeasured and blocking:** `dcl-Control-SetText` on a Text Box.
`OPENDCL-WIRING.md` §4 attests `GetText` but not the setter. `C:PFPAPI` with
`*TEXT*` answers it from the symbol table without probing a live control.

---

## 11. Sequencing

1. **`../pf2sew.md` §8 step 4** — the `.SEW` round trip in CAD. Gates
   everything; nothing downstream is real until Carlson opens the file.
2. **The §5 diff** — hand-author one structure's drainage and diff. Same CAD
   session. Turns the hydrology schema from inferred to attested.
3. Then this tab.

The Settings tab (§10) depends on none of that and can go first.

Note also `../pfsuite-md/Version 5.1.md` §10 step 0: nine CAD gates from V5 are
still outstanding. This is V5.1 Track E work, correctly last on that list.

---

## 12. Doc debt found while writing this

- **`PALETTE-LAYOUT.md` §1 reads as though `Edit` and `New` are `tabMain`
  surfaces.** They are Registry-tab buttons (§1 above). Fix the wording.
- **`README.md`'s "inert while Area is 0"** stops holding the moment this tab
  ships. Flag it there now rather than discovering it in a Carlson model.
