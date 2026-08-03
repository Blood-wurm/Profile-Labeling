# PFTools V5 — Closed Issues

Resolved items, moved out of `OPEN-ISSUES.md` on 2026-07-31 so that file holds
only live work. **Kept, not deleted** — several of these cost a full CAD session
to diagnose, and the reasoning is what stops them being re-derived. Nothing here
needs action except the CAD gates listed below.

Two states are recorded and they are **not** the same:

- **CLOSED** — fixed and confirmed.
- **FIXED — CAD GATE OPEN** — the fix is written and the static gates pass, but
  nothing in this repo is verified until Jake runs it in CAD. The acceptance
  test is stated with the item.

---

## Outstanding CAD gates

Every item below in the FIXED — CAD GATE OPEN state, in one list. This is the
V5 close-out checklist; V5.1 should not start on top of an unverified V5.

| # | Item | Gate |
|---|---|---|
| 1 | PFINVERT direction (07-29) | On the 'B' profile: head reads `I.O. 770.74`; downstream shared structure reads `I.O. <continuing> │ I.I. 765.00` in that order; five distinct stacks; console reports "N merged into shared structures". |
| 2 | PFLABEL cross-utility scoping (07-21) | A STORM MH that a SANITARY line merely crosses no longer appears in the STORM label; genuine same-type junctions still get the combined ID. |  
**CLOSED** 
| 3 | PFXLABEL skipped-source crossing (07-21) | Re-test `SANITARY_A @ 5+14.38` — the crossing that dropped its line must now label. |
| 4 | `CF:ROAD_API` load site (07-29) | In a **fresh** drawing with no prior PFTools command, the palette's Anchor button completes a placement; so do PFREMOVE and PFPVERB's other verbs. | 
**CLOSED**
| 5 | Anchor block style (07-27) | `PF-ANCHOR` icon snaps to the datum, scales `hplot/50`, sits at the back of the draw order; pre-icon `PF-GRIDANCHOR` anchors still resolve. | 
**CLOSED**
| 6 | `CMDECHO` suppression (07-21) | No UNDO/ZOOM/DELAY chatter during a run; the user's `CMDECHO` is restored after, including on the error path. |
| 7 | ×5 error/undo consolidation (07-26) | All five commands run under `pf:run-command`; Esc mid-pass puts partial-pass entities ON the ledger — TESTING.md §8.9. |
| 8 | Registry-builder consolidation (07-26) | On a drawing with ≥2 same-type lines (one a stub) plus a copied anchor: PFLABEL and PFINVERT list the identical line set, the copy in neither, and a junction's combined ID matches between them. | 
**CLOSED**
| 9 | Native plot scales (07-21) | `sv:sm` / `sv:vs` actually equal the profile grid's H/V, not some unrelated plan scale. | 
**CLOSED**
| 10 | Index repair at registration (08-01) | PFSETUP a new line on a project with existing structures: console reports "Index: N structure(s) newly indexed"; `PFINDEX` Report shows no **absent** records afterward; registering several lines in a row stays roughly flat per line. |
| 11 | Palette latency, measure first (08-01) | `PFINDEX` Build on a real project, then a Commands-tab click: compare `PFPDIAG` latency before/after; `PFINDEX` Verify reports zero disagreements — "same labels, faster". Decides whether anything beyond wiring is needed (DATA-FLOW §6) and whether `*pfa-gather-memo*` still earns its keep. |
| 12 | STATUS_XING retirement (08-01) | Checks cell reads out of **2** (e.g. "STALE (LABEL)"); PFXLABEL still prints its freshness verdict; `PFPDBMOD` shows no STATUS_XING write during a crossings pass; PFSETUP register/edit still resets what it should. |
| 13 | Findings rows in the palette (08-01) | Edit the `.cl` after a PFLABEL pass: Registry tab shows `STALE (LABEL)` **plus an indented LABEL row quoting the stored finding sentence**; a PASSING line shows no extra rows. |
| 14 | PFREPORT memo reuse (08-01) | PFREPORT over a multi-line project writes a byte-identical `.stm` to the pre-change output, faster on 10+ lines. |
| 15 | Quarantine regression sweep (08-01) | Full TESTING.md smoke pass loads clean — nothing references the 20 `_attic` symbols at runtime (`pf:sample-cl`/`pf:attach-corridor`/`pf:find-cl-polyline` chain included). |

---

## DATA-FLOW consolidation — executed 2026-08-01

The audit's findings (`DATA-FLOW.md` §3–§6, drafted 07-31) were actioned in
one sweep. Every item below is **FIXED — CAD GATE OPEN** against gates 10–15
above; the reasoning stays in DATA-FLOW.md §4–§6.

- **PFINDEX wired into registration** — new `pfa:index-repair` (pfanchor §8)
  called by `pfs:place-one` / `pfs:edit-one` inside their undo group.
  Absent-only writes; stale left for the engine top-up or `PFINDEX` Build,
  which keeps registration linear (gate #10). `*pf-index-on*` in
  pftools-cfg remains the field rollback.
- **STATUS_XING retired** — `pfxl:write-status` became `pfxl:report-status`
  (prints, stores nothing); `pfa:status-roll` walks LABEL+INVERT and
  reports of 2; PFSETUP resets only LABEL/INVERT (gate #12). The record
  duplicated STATUS_LABEL exactly — same inputs, same code, provably never
  disagreed (DATA-FLOW §4.1).
- **Stored findings finally read** — new `pfa:status-why` + `pfp:why-rows`:
  metaList shows the stored explanation under a STALE/FAILING Checks cell
  (gate #13). Closes DATA-FLOW §3.2 with "surface it", per Jake's approval
  of the plan.
- **PFREPORT memo bypass fixed** — `pfr:` now calls `pfa:pend-for` instead
  of raw `pfa:pending`, ending the 47-walks-per-run pattern (gate #14,
  DATA-FLOW §4.2).
- **Dead code quarantined, not deleted** — 20 defuns to
  `pfsuite/_attic/_attic.lsp` (never loaded; `pfcheck.sh` now skips
  `/_attic/`): the 16 adjudicated no-callers plus a 4-symbol cascade
  (`pf:sample-cl`, `pf:attach-corridor`, `pf:find-cl-polyline`,
  `pf:on-layer-p`) whose only callers left in the same sweep. 8 deliberate
  KEEPs remain on the gate, each with an in-file note. Two README entries
  documenting never-built functions were reworded. Deviation from the §5
  table: `pf:text-layer` / `pf:align-layer` were listed for quarantine but
  carry an in-code banner keeping them as the revert path to per-type
  layers — the banner won.
- **Crossing elevations kept** — `pfa:xr-telev`/`-selev` now carry the
  PFCHECK pointer comment §3.1 asked for.
- Still open, moved to OPEN-ISSUES: the `GEOM_*` per-vertex-station orphan
  (§3.3, Jake's call) and whether the palette gets its own Index control.

---

## PFINVERT

- **[wrong-output — CRITICAL] Direction was wrong at every terminus and at every
  shared structure.** **FIXED 2026-07-29 — CAD GATE OPEN (#1).** Field report:
  five structures on line 'B', console said all five labeled, two labels on the
  sheet, and the uppermost structure read `I.I.` where `I.O.` belongs. Six
  defects, one theme — direction was assumed where it should have been derived:
  **CLOSED**
  1. **Terminus classification inverted** (`pfi:invert-bracket`). The interior
     pair rule (lower = outgoing) was carried over to single-vertex ends, where
     it does not hold: the vertex is the end of a whole pipe, not one side of a
     structure. Now the HIGH end of the run is the upstream head (pipe leaves →
     I.O) and the LOW end the downstream terminus (pipe arrives → I.I). Compared
     against the far END of the profile, so it does not care which way the line
     is stationed.
  2. **Shared lines were all labeled `I.I.`** and sampled with `pf:pipe-at`.
     They now bracket their own `_INV.pro` (`pfi:lateral-info` returns
     `(clfile (role elev size) ...)`), so a line that leaves reads I.O and a
     pass-through yields both rows. Sampling also died at the `.pro`'s
     station-range boundary — exactly where a junction sits — and the row
     silently vanished.
  3. **Columns were positional, not role-based.** `I.O. │ shared │ I.I.` only
     held when the primary owned an I.O.; at a downstream terminus the left
     column sat empty and two `I.I.` rows printed at a structure with a pipe
     visibly running out of it. Row 0 now goes to whatever LEAVES.
  4. **`pfi:nearest-vert` had no distance guard** — it returned the closest
     vertex at any distance, so a structure with no vertex in the `.pro`
     silently inherited its neighbour's invert to the penny. Past
     `*pfi-struct-width-max*` it is now a printed skip.
  5. **Junction station came from the drawn twin's vertex order**
     (`pfi:endpoint-hits`), which is drafting direction, not stationing — a line
     drawn against its stationing was read at its far end. The twin is now a
     proximity pre-filter only; the station comes from `pf:cl-endpoints`,
     station-ordered by construction.
  6. **Shared structures drafted as two blocks drew two identical stacks** at
     one station X and one base Y, superimposed — the "5 structures, 2 labels"
     symptom. `pfi:merge-nodes` merges within `*pfr-node-tol*`, `pfi:node-hits`
     unions the blocks' memberships so no line is dropped.

- **[wrong-output — CRITICAL] I.I / I.O were swapped and collapsed.**
  **CLOSED.** Root cause was the sample-and-detect bracket (`pfi:break-scan`):
  0.5-ft sampling read the break ~half a step past the true vertex (the
  ~0.05-ft-high bias, ≈ `*pfi-grade-tol*`) and couldn't classify
  one-sided/no-break structures. Replaced with an **exact vertex bracket** —
  `pf:pro-verts` parses the `.pro` file directly (the Road API has no vertex
  accessor, confirmed) and `pfi:invert-bracket` takes the two adjacent vertices
  meeting at the structure: lower = I.O., higher = I.I., a polyline endpoint = a
  single-invert terminus. Also added pipe size to callouts, the I.O.│shared│I.I.
  column order, text-scaled drop, and the leftmost-structure shift. Numbers
  match the `.pro` to the penny; no station-domain warning fires. *(field note
  258)*

- **[scope] Type-scoping.** **CLOSED 2026-07-21** with PFLABEL (shared
  builders). Laterals now come only from same-type lines via the scoped table.

## PFLABEL

- **[scope] Cross-utility contamination.** **FIXED 2026-07-21 — CAD GATE OPEN
  (#2).** Membership was built from the whole registry (all types), pulling in
  other utilities' structures/blocks. Now the secondary `.cl` set is scoped to
  the primary's utility type in both builders — `pflabel:registry-pairs` (covers
  PFINVERT + both `setup` paths) and the direct build in `pflabel:run-dialog` —
  keyed on `pf:type-of` (filename truth). PFXLABEL is deliberately untouched
  (crossings stay cross-type). Laterals inherit the scoping via the filtered
  line table. *(field notes 2, 256, 259)*

## PFXLABEL

- **Field findings 243, 244, 245, 247.** **FIXED 2026-07-21 — CAD GATE OPEN
  (#3).** `"Checking for crossings"` message added; zero-count report
  suppressed; `profile z` → `profile_z`, which is what dropped the skipped
  crossing's line.

## PFSETUP

- **[ux] "Place All" dialog parade.** **CLOSED 2026-07-28 — REMOVED, not
  fixed.** Every grid needs its own scales, datum and two corner picks, so a
  batch could never be anything but a parade; there was no pausable flow to
  design. Anchor All is gone from the registry dialog (`reg_all`, `pfs:rd-all`,
  the `'place-all` verb). Anchor one profile at a time, from the dialog or the
  palette. *(field notes 250, 251)*

---

## Shared / cross-cutting

- **[crash — palette] `bad function: CF:ROAD_API` from `C:PFPVERB`.**
  **FIXED 2026-07-29 — CAD GATE OPEN (#4).** `pf:load-apis` (the `scload` of
  tri4/eworks that defines `cf:road_api`) was the first line of each command
  BODY. Six of the nine entry points had it; `pfp:verb-run`, `pfrem:cmd` and the
  `pfp-proof` harness did not. The palette's anchor verb calls `pfs:place-one`
  **directly** rather than `pfs:cmd`, so btnAnchor prompted for scales and datum
  and then died on the first centerline read — in any session where no
  command-line PFTools command had run yet. It read as working since the verb
  channel shipped (PALETTE-LAYOUT 2026-07-28) because testing a palette button
  almost always follows a command-line run that already loaded the API. **Fix:**
  `pf:load-apis` moved into `pf:run-command`'s prologue, after `pf:echo-off` so
  the load chatter is suppressed; all six body-level calls removed. Same
  consolidation as the ×5 error scaffolding below, and the same root cause it
  was meant to end — what every entry point needs belongs to the ONE wrapper.

- **[scope] Same-type membership** (PFLABEL + PFINVERT). **CLOSED 2026-07-21** —
  one fix in the shared builders (`pflabel:registry-pairs` +
  `pflabel:run-dialog`) served both, keyed on `pf:type-of`. *(field note 2)*

- **[ux] Anchor block style.** **FIXED 2026-07-27 — CAD GATE OPEN (#5).**
  `*pfa-block-name*` now points at the hand-authored `PF-ANCHOR` block — a small
  icon snapped to the datum, uniformly scaled `hplot/50`, no longer a frame
  spanning the grid. Extents moved off the scale factors into new
  `WIDTH`/`HEIGHT` attributes (`pfa:extents` reads both storages;
  `*pfa-block-names*` keeps pre-icon `PF-GRIDANCHOR` anchors resolvable). Missing
  ATTDEFs are topped up on the authored block by `pfa:sync-attdefs`. Anchors are
  sent to the back of the draw order on write and re-anchor. *(field note 253)*

- **[ux] `CMDECHO` never suppressed** (§13.2). **FIXED 2026-07-21 — CAD GATE
  OPEN (#6).** Shared `pf:echo-off` / `pf:echo-on` in the lib save the user's
  CMDECHO and zero it for the run; every command's prologue calls `echo-off`,
  every normal epilogue calls `echo-on`, and the error path restores. Kills the
  UNDO/ZOOM/DELAY chatter.

- **[refactor] ×5 error/undo scaffolding** (§13.4 / audit #9). **FIXED
  2026-07-26 — CAD GATE OPEN (#7).** `pf:run-command` (pfanchor) is now the ONE
  copy of the prologue/epilogue — `*error*` save/install (`pf:run-error`),
  save-once `pf:echo-off`/`on` (the non-re-entrancy fixed while absorbing), the
  undo-group flag pattern (`pf:undo-begin`/`end`), and the error-path teardown
  in locked order: ledger-flush hook → close group → `pf:zoom-onerror` → restore
  `*error*`. All five commands (PFSETUP / PFLABEL / PFXLABEL / PFINVERT /
  PFREMOVE) converted; `pfa:undo-cleanup` and the per-command `*error*` handlers
  are gone. **Behaviour change:** the per-command Esc ledger flush
  (`pflabel:flush-pass` / `pfi:flush-pass` / `pfxl:flush-pass`) puts partial-pass
  entities ON the ledger — see TESTING.md §8.9 for the gate.

- **[wrong-output] Registry-builder divergence** (audit #12). **FIXED
  2026-07-26 — CAD GATE OPEN (#8).** `pflabel:registry-pairs` is now a thin
  filter over `pfa:registry` (the one merged, copy-excluding, sorted walk)
  resolved via `pfa:entry-cl` (moved from pfxlabel — pure registry knowledge, no
  alias left behind), self dropped by canonical `pf:cl-id`. `pflabel:run-dialog`'s
  inline build and `pfi:run-dialog` both call it — one builder, so PFLABEL and
  PFINVERT can no longer disagree about a junction's combined ID (the old
  divergence: different `.cl` resolution + `pfa:all-anchors` not excluding
  copies).

- **[latent] `pf:echo-off` / `pf:echo-on` were not re-entrant**
  (old LOW-6). **CLOSED 2026-07-26** — absorbed into `pf:run-command` as
  save-once: `pf:echo-off` only captures `CMDECHO` when `*pf-echo-save*` is nil,
  so a nested call can no longer lose the user's original value. This was raised
  in priority on 2026-07-27 specifically because the deferred-fire work would
  create the first nesting path; it was fixed before that path landed.
  `pfp:ensure` and `C:PFPRELOAD` still hand-roll their own local save/restore
  around `(command "_OPENDCL")` — correct in isolation, and now the only two
  copies of the pattern left. See LOW-1 in OPEN-ISSUES.md.

---

## Native Carlson integration

Policy (Jake, 2026-07-21): **make every native Carlson call we can** instead of
hand-entered or hardcoded values.

- **Project root.** **CLOSED** — `tmpdir$` (`pfset:root-get`); PFROOT retired.
- **Plot scales.** **DONE 2026-07-21 — CAD GATE OPEN (#9).** The setup dialog
  seeds HPLOT/VPLOT from `sv:sm` / `sv:vs` (`pfset:native-scale`); still
  editable, stored value wins on Edit.
- **Settings/temp folder.** **CLOSED** — `pfset:dir` prefers `usrdir$`, falls
  back to LOCALAPPDATA/TEMP. (Old settings in `LOCALAPPDATA\PFTools` are
  orphaned, not migrated — harmless; last-used values just repopulate.)

## Design decisions

- **[question] PVI probe.** **RESOLVED 2026-07-22.** The Road API exposes **no**
  vertex accessor — the only profile calls are `profile z` and `profile sta
  range` (confirmed against the live `cf:road_api` catalog). `pfi:invert-bracket`
  now reads exact vertices by **parsing the `.pro` file** (`pf:pro-verts`), the
  suite's one file read, with a `profile_z` cross-check guarding the station
  domain.

---

## PFPALETTE

- **`lvwCommand` is not a List View.** **RESOLVED 2026-07-30, same day.** It
  *was* a **List Box**, and was then **rebuilt in Studio as a real List View**
  under the same `(Name)` later that day, because padded-string columns could not
  be made to line up: `pfset:pad` pads but never **truncates**, so any item over
  20 characters staggers the row in *any* font, and `pfp:skin` paints the
  proportional "MS Shell Dlg" over everything. `*pfp-items-mode*` is
  `'listview`. Recorded because the diagnosis is reusable:
  - Four uncatchable modals on one open, `Invalid argument type / Argument: 0`,
    once on `dcl-ListView-AddColumns` and three times on
    `dcl-ListView-FillList`. **Argument 0 is the control and the complaint is its
    type** — the name resolved, so every `null` guard passed.
  - **Wrong name and wrong type are opposite failures.** Wrong name → symbol
    `nil` → silent no-op, guardable. Wrong type → symbol bound → modal, and it
    **aborts the caller** (`OnInitialize` died). No guard exists or can: asking a
    control its type needs a type-specific call, which is the fault.
  - **`AddColumns` was last in `OnInitialize`**, so the other three lists kept
    their columns. Keep the least-certain control last there.
  - **What this did NOT close** is now tracked separately in OPEN-ISSUES.md
    under PFPALETTE — no attested List View getter, and the `SelChanged`
    argument list needs re-reading in Studio after the type conversion.

- **Duplicated work on doubled tree dispatch.** **BUILT 2026-07-30**
  (`*pfp-last-key*` / `pfp:route-sel`). An idempotence guard had been designed
  and deliberately *not* built, on the grounds that it guards a condition that
  should not exist. The workload changed the answer: the Commands fill now also
  reaches `pfa:xing-scan`, which on a target with no SCOPE cuts every registry
  line against the target (`pf:poly-x`, O(n × m) per pair). Paying that twice per
  click is a different order of waste from an extra `*Cancel*`. **The doubled
  dispatch itself is still open** — see OPEN-ISSUES.md; only the duplicated
  *work* is gone.

- **Runtime files were version-mismatched** (`OpenDCL.x64.25.arx` 9.3.0.1 vs
  `ENU/Runtime.Res.dll` 9.1.5.2). **CLOSED** — matched runtime since installed.
  Worth re-checking whenever rendering behaves oddly.

### Resolved 2026-07-27 — recorded because each cost real time

- **Studio edits silently not reaching the runtime.** `dcl-Project-Load` does
  nothing if the project is already loaded unless `ForceReload` is `T`, and
  `*pfp-loaded*` is a session-long global. Fixed by `C:PFPRELOAD`. **Tell:** a
  runtime-set caption survives a palette toggle. This invalidated several
  measurements before it was spotted.
- **Blank footer labels** (`lblProject` / `lblCounts`) — colour plus the stale
  cache above. `Foreground Color` was already correct at -19; `-24` is
  **Transparent**, not a theme value. `pfp:seed-labels` was correct throughout.
- **`pfa:registry` printed a `Usage: (acad_strlsort …)` banner on any drawing
  with an empty registry** — the function had never been run against zero rows.
  Guarded at `pfanchor.lsp:593`.
- **`(command)` from a modeless handler drew nothing, as designed**, and
  `pfp:defer` lands in a real command context — `getpoint` prompts and returns,
  one `U` peels the work, and the gate refuses against a live command. The
  deferred-fire design is sound.

---

## Hygiene / drift (from the retired `Low_Priority_issues.md`)

- **README was substantially stale.** **RESOLVED 2026-07-27** — root README
  §1/§5/§7/§8, `pfpalette/README.md`, `pfanchor/README.md` and `OPEN-ISSUES.md`
  all updated after the palette shakedown. The follow-on nit (the issues file
  still titled "V4") was closed 2026-07-31 with this split.

- **`.odcl` control names are unverifiable statically.** **MITIGATED
  2026-07-27** — `C:PFPDIAG` (pfpalette.lsp §6) resolves all 29 control names at
  runtime and lists any that are missing, so the binary is no longer opaque to
  review. Two caveats kept this from being fully closed: (a) it must be run with
  the palette **OPEN**, because `dcl-Form-Close` destroys the child controls and
  every symbol reverts to nil — closed, it reports 0 of 29; (b) it proves a name
  RESOLVES, not that it is UNIQUE. Caveat (b) survives as an open item (duplicate
  `(Name)` check, PFPALETTE section of OPEN-ISSUES.md). The suspicion that
  `lblProject`/`lblCounts` were the failures was wrong — they resolve; their
  blankness was colour plus a stale project cache.

- **The extracted engines had no consumer.** **RESOLVED 2026-07-30** — and not
  the way it was written up. The expected answer was a set of thin `C:PF*RUN`
  commands; none were built and none are needed. The palette became the
  consumer directly: `pfp:order-fire` → `pfp:run-labels` calls `pflabel:run`,
  `pfi:run` and `pfxl:run` off the order ticket, through `pfp:defer`. The
  refactor is no longer inert. **Do not add `C:PF*RUN` commands** on the strength
  of the old note — the channel they were meant to provide exists.
