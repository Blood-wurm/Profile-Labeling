# PFTools V4 — Open Issues

Live issue list, separated by tool. Sourced from the 2026-07-20 field-test
session (the raw log lived in `TESTING.md` NOTES) and triaged against the
2026-07-21 pull. Resolved items are recorded in `TESTING.md` ("Resolved since
last pull"), not here.

Severity: **crash** | **wrong-output** | **scope** | **ux** | **perf** |
**feature** | **question**. Wrong-output outranks crash — silently wrong
numbers on a plan sheet are the worst outcome.

---

## PFINVERT

- ~~**[wrong-output — CRITICAL] I.I / I.O are swapped and collapsed.**~~
  **FIXED .** Root cause was the sample-and-detect bracket
  (`pfi:break-scan`): 0.5-ft sampling read the break ~half a step past the true
  vertex (the ~0.05-ft-high bias, ≈ `*pfi-grade-tol*`) and couldn't classify
  one-sided/no-break structures. Replaced with an **exact vertex bracket** —
  `pf:pro-verts` parses the `.pro` file directly (the Road API has no vertex
  accessor, confirmed) and `pfi:invert-bracket` takes the two adjacent vertices
  meeting at the structure: lower = I.O., higher = I.I., a polyline endpoint = a
  single-invert terminus. Also added pipe size to callouts, the
  I.O.|shared|I.I. column order, text-scaled drop, and the leftmost-structure
  shift.  numbers match the `.pro` to the penny; no
  station-domain warning fires. *(field note 258)*
- ~~**[scope] Type-scoping.**~~ **FIXED 2026-07-21** with PFLABEL (shared
  builders). Laterals now come only from same-type lines via the scoped table.

## PFLABEL

- **[wrong-output — CRITICAL, OPEN] Structures silently dropped from a run.**
  On line DF (5 identical `DBI_24x24`) PFLABEL listed and labeled only 3 of 5;
  the loss is **pre-dialog** (`pflabel:pending` → `pf:lines-at-point`) and no
  per-structure skip message fires. Case that stays missing: handle `51FF8`,
  sta 628.846 — offset 0 from the rebuilt `.cl`, interior to the range, plain
  top-level INSERT, rule MATCH. Every naive cause (name filter, offset
  tolerance, station range, corridor, `vl-sort` dedup) ruled out on the live
  drawing. **Root cause (confirmed against the Road API catalog):** membership
  gates on `cl_location_at_pt`, which returns **nil on failure**; a structure
  just outside a deflection PI has no valid perpendicular foot, so the API
  returns nil, `pf:cl-locate-safe`'s terminus-only fallback misses an interior
  point, and the structure is dropped with no output. Tolerance-independent
  (the projection is *absent*, not large) — which is why widening
  `*pf-offset-tol*` 0.2→0.8 did nothing. Compounded by the TWIN pre-filter
  acting as an authoritative silent gate (basename-keyed, no checksum) that can
  veto before the authored test runs. **Fix (planned; scaffold landed):**
  replace projection membership with point-to-**segment** distance
  (`pf:pt-poly-dist`) against a directly-parsed `.cl`; graded radial band
  (`*pf-vertex-band-hi/lo*`); full drop accounting so nothing vanishes without
  a printed reason; TWIN demoted from gate to setup-time misalignment witness.
  Data-independent scaffold in this pull: canonical `.cl` identity (`pf:cl-id`),
  GEOM `KIND` + per-vertex stations, TWIN re-key + `.cl` checksum. Remaining
  work is gated on the `.cl` format probe (Carlson box). **Acceptance:** PFLABEL
  on DF lists and labels all 5 `DBI`, incl. `51FF8` at 628.846.
- ~~**[scope] Cross-utility contamination.**~~ **FIXED 2026-07-21 (untested in
  CAD).** Membership was built from the whole registry (all types), pulling in
  other utilities' structures/blocks. Now the secondary `.cl` set is scoped to
  the primary's utility type in both builders — `pflabel:registry-pairs`
  (covers PFINVERT + both `setup` paths) and the direct build in
  `pflabel:run-dialog` — keyed on `pf:type-of` (filename truth). PFXLABEL is
  deliberately untouched (crossings stay cross-type). Laterals inherit the
  scoping via the filtered line table. **Verify in CAD:** a STORM MH that a
  SANITARY line merely crosses no longer appears in the STORM label; genuine
  same-type junctions still get the combined ID. *(field notes 2, 256, 259)*
- **[ux — verify] Ghost dropdown on open.** Reported glitchy/unprofessional.
  *Likely fixed* by the pick-first refactor (target popup removed from `pf_run`;
  all compute moved before `new_dialog` via `pflabel:rd-compute`) — re-check in
  CAD before closing. *(field note 255)*
- Error parade in cmd line
## PFXLABEL

- Field findings 243, 244, 245, 247 are **resolved** by this pull
  (`"Checking for crossings"` message; zero-count report suppressed;
  `profile z`→`profile_z` — the skipped crossing that dropped its line should
  now label). **Re-test the skipped-source case** (`SANITARY_A @ 5+14.38`) to
  confirm before considering it closed.

## PFSETUP

- **[ux] "Place All" dialog parade.** Place All fires one unskippable dialog
  per profile, one after another, with no way to pause and navigate to the next
  profile. Current per-placement flow (Place → dialog → elevation → extents
  pick → back to main dialog) leaves no way to move to the next profile without
  closing and reopening the manager. Wants a pausable/navigable flow.
  *(field notes 250, 251)*
- **[ux] Dialog box size.** Setup dialogs should be larger. *(field note 252)*
- **[feature] Discover crossings & shared stations at PFSETUP.** Currently
  crossing discovery only runs in PFXLABEL; the ask is to find `.cl` crossings
  and shared stations at registration time. *(field note 240)*

## PFREMOVE

- No open field findings. (Covered by TESTING.md §7 / §5, not yet executed.)

---

## Shared / cross-cutting

- ~~**[scope] Same-type membership** (PFLABEL + PFINVERT).~~ **FIXED
  2026-07-21** — one fix in the shared builders (`pflabel:registry-pairs` +
  `pflabel:run-dialog`) served both, keyed on `pf:type-of`. *(field note 2)*
- ~~**[ux] Anchor block style.** Formatting/appearance of the `PF-GRIDANCHOR`
  block wants a pass. *(field note 253)*~~ **FIXED 2026-07-27 (untested in
  CAD).** `*pfa-block-name*` now points at the hand-authored `PF-ANCHOR`
  block — a small icon snapped to the datum, uniformly scaled `hplot/50`, no
  longer a frame spanning the grid. Extents moved off the scale factors into
  new `WIDTH`/`HEIGHT` attributes (`pfa:extents` reads both storages;
  `*pfa-block-names*` keeps pre-icon `PF-GRIDANCHOR` anchors resolvable).
  Missing ATTDEFs are topped up on the authored block by `pfa:sync-attdefs`.
  Anchors are sent to the back of the draw order on write and re-anchor.
- ~~**[ux] `CMDECHO` never suppressed** (§13.2).~~ **FIXED 2026-07-21 (untested
  in CAD).** Shared `pf:echo-off`/`pf:echo-on` in the lib save the user's
  CMDECHO and zero it for the run; every command's prologue calls `echo-off`,
  every normal epilogue calls `echo-on`, and the error path restores. Kills
  the UNDO/ZOOM/DELAY chatter.
- ~~**[refactor] ×5 error/undo scaffolding** (§13.4 / audit #9).~~
  **FIXED-PENDING-CAD 2026-07-26** with the restructure: `pf:run-command`
  (pfanchor) is now the ONE copy of the prologue/epilogue — *error*
  save/install (`pf:run-error`), save-once `pf:echo-off`/`on` (the
  non-re-entrancy fixed while absorbing), the undo-group flag pattern
  (`pf:undo-begin`/`end`), and the error-path teardown in locked order:
  ledger-flush hook → close group → `pf:zoom-onerror` → restore `*error*`.
  All five commands (PFSETUP / PFLABEL / PFXLABEL / PFINVERT / PFREMOVE)
  converted; `pfa:undo-cleanup` and the per-command `*error*` handlers are
  gone. **Behavior change:** the per-command Esc ledger flush
  (`pflabel:flush-pass` / `pfi:flush-pass` / `pfxl:flush-pass`) puts
  partial-pass entities ON the ledger — see TESTING.md 8.9 for the gate.
- ~~**[wrong-output] Registry-builder divergence** (audit #12).~~
  **FIXED-PENDING-CAD 2026-07-26** with the restructure:
  `pflabel:registry-pairs` is now a thin filter over `pfa:registry` (the one
  merged, copy-excluding, sorted walk) resolved via `pfa:entry-cl` (moved
  from pfxlabel — pure registry knowledge, no alias left behind), self
  dropped by canonical `pf:cl-id`. `pflabel:run-dialog`'s inline build and
  `pfi:run-dialog` both call it — one builder, so PFLABEL and PFINVERT can
  no longer disagree about a junction's combined ID (the old divergence:
  different .cl resolution + `pfa:all-anchors` not excluding copies).
  **CAD gate:** on a drawing with ≥2 same-type lines (one a stub) plus a
  copied anchor, PFLABEL and PFINVERT must list the identical line set, the
  copy in neither, and a junction's combined ID must match between them.
- **[perf] Per-crossing `pfa:find-anchor` full-DB scans** (§13.3). An All-mode
  pass re-scans the whole database per crossing; scan the registry once per
  command and pass it down. *(field note "Performance improvements?")*
- **[crash-guard] Backtick sheet names** still unfixed: `pf:parse-sheet-name`
  closes only on a straight `'`, so `` STORM LINE `DA` `` silently skips in
  AUTO. *(TESTING.md known-open)*
- **[question] `PICKADD`** — does the suite need to save/restore it around
  selection? Flagged, not investigated. *(field note "PICKADD variable
  change?")*

---

## Native Carlson integration

Policy (Jake, 2026-07-21): **make every native Carlson call we can** instead of
hand-entered or hardcoded values.

- ~~Project root~~ **DONE** — `tmpdir$` (`pfset:root-get`); PFROOT retired.
- ~~Plot scales~~ **DONE (verify)** — the setup dialog seeds HPLOT/VPLOT from
  `sv:sm`/`sv:vs` (`pfset:native-scale`); still editable, stored value wins on
  Edit. **Verify in CAD** that `sv:sm`/`sv:vs` actually equal the profile
  grid's H/V (not some unrelated plan scale).
- ~~Settings/temp folder~~ **DONE** — `pfset:dir` prefers `usrdir$`, falls back
  to LOCALAPPDATA/TEMP. (Old settings in `LOCALAPPDATA\PFTools` are orphaned,
  not migrated — harmless; last-used values just repopulate.)
- **[feature] Metric guard (`is metric`).** The suite hardcodes english —
  `pf:pipe-at` does `(TOP−INV)×12` (inches), stations/elevations in feet. A
  metric drawing would be silently wrong. Minimal step: read the metric flag
  and **warn/refuse**; full metric support is a larger feature. **Blocked on
  the exact variable name** — the reference lists "is metric" (a space → not a
  valid symbol); confirm the real symbol in a live session before wiring.
- **[decision] `sv:ts` / `sv:ps` (text / symbol scalers).** Deliberately NOT
  adopted: label size comes from the firm-standard `*pf-text-base-height*` × sf,
  an intentional firm choice, not Carlson's scaler. Keep as a possible
  cross-check only.
- **[future] `psname` (Carlson Support folder).** Candidate home for the
  `PF-PIPE_*` block library `.dwg`/`.dwt` — use when the block library is built
  ([[block-material-library-direction]]).
- **N/A:** `crdfile` (plan-view coordinates, irrelevant to profiles); no native
  crossing-finder / station-formatter / profile-grid-geometry exists (confirmed
  API catalog) — `pf:fmt-station`, `.cl` intersection, top-of-grid probe stay.

## Design decisions / open questions

- **[question] GEOM cache storage location.** Geometry lives in the drawing's
  NOD (per-drawing) keyed by `.cl` identity. If multiple sheet drawings share
  one project data folder, a project-folder **sidecar** cache (trace once per
  project) is a strictly bigger win. **Now unblocked:** the reliable project
  path this needed landed 2026-07-21 (native `tmpdir$`, `pfset:root-get`). Only
  open question left: **one sheet per project, or many sheets sharing one data
  folder?** If many, build the sidecar; if one, the in-DWG NOD cache is already
  right. *(TESTING.md storage-location discussion)*
- ~~**[question] PVI probe.**~~ **RESOLVED 2026-07-22.** The Road API exposes
  **no** vertex accessor — the only profile calls are `profile z` and `profile
  sta range` (confirmed against the live `cf:road_api` catalog). `pfi:invert-
  bracket` now reads exact vertices by **parsing the `.pro` file** (`pf:pro-
  verts`), the suite's one file read, with a `profile_z` cross-check guarding the
  station domain.

## PFANCHOR
- No warning when anchor was moved.
  Moved anchor > PFSETUP > Refresh > PFLABEL > NO Warning
## PFPALETTE

Shakedown results and the full test matrix live in
[`../pfsuite-odcl/PALETTE-TESTING.md`](../pfsuite-odcl/PALETTE-TESTING.md).
Only unresolved items are listed here.

- **Palette persists across drawings — NOT intentional, and the fix is
  blocked.** (Answers the original question.) The palette is owned by the
  OpenDCL ARX runtime, so it outlives any document and sits on the start
  screen showing the last drawing's registry, which native AutoCAD palettes
  do not do. `EnteringNoDocState` → close is the intended answer; field test
  2026-07-27 found it **never fired**, and `DocActivated` threw
  `no function definition: C:PFSUITE/PFSPALETTE#ONDOCACTIVATED`. Read
  together: the event fires into a document where the suite was never loaded,
  and AutoLISP namespaces are per-document. **The blocker is namespace, not
  form state** — neither `dcl-Form-Hide` nor a `vlr-docmanager-reactor` fixes
  a handler that does not exist in the document being activated into.
  Candidate: per-document autoload (`acaddoc.lsp`). **Deferred by decision
  2026-07-27** in favour of Phase 2. Also means stale data after a drawing
  switch persists, and activating into an unloaded drawing throws a *visible
  error* rather than failing quietly.
- **Docked layout is barely tested.** Every resize test in the plan is a
  *floating* test done by dragging edges; docked is the mode this palette is
  designed for (`Dockable Sides` = Left + Right). A docked-only gray box over
  the footer labels is recorded at PALETTE-TESTING §1.7; may already be
  resolved by the label background change.
- **`tvwLines` misaligned**, and leaves a gap above it that grows on stretch —
  likely `Use Top From Bottom` = 1 where PALETTE-LAYOUT §3 specifies 0. **All
  existing anchoring evidence was gathered against a stale in-memory project**
  (see below), so §1.6 must be re-run after the fix regardless.
- **`Min Width` ≥ 900 is load-bearing.** It closes the vanishing-buttons issue
  *by construction* — the form cannot narrow enough to compute a negative x.
  Lowering it re-opens that issue. Cost: a Left/Right-dockable vertical strip
  with a hard 900px floor is a wide strip. Narrowing it means reflowing the
  five fixed-width Registry button rows — a redesign, not scheduled.
- **Duplicate `(Name)` check (test 1.5) still unrun.** `PFPDIAG` proves a name
  *resolves*, not that it is *unique*; a duplicate leaves both resolving with
  one unaddressable, and nothing detects it but reading the Studio tree.
- Runtime files were **version-mismatched** (`OpenDCL.x64.25.arx` 9.3.0.1 vs
  `ENU/Runtime.Res.dll` 9.1.5.2) — matched runtime since installed. Worth a
  check whenever rendering behaves oddly.

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
  with an empty registry** — the function had never been run against zero
  rows. Guarded at `pfanchor.lsp:593`.
- **`(command)` from a modeless handler drew nothing, as designed**, and
  `pfp:defer` lands in a real command context — `getpoint` prompts and
  returns, one `U` peels the work, and the gate refuses against a live
  command. The deferred-fire design is sound.