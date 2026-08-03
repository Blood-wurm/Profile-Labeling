# PFTools V5 — Open Issues

Live issue list, separated by tool. Originally sourced from the 2026-07-20
field-test session (the raw log lived in `TESTING.md` NOTES) and triaged against
the 2026-07-21 pull.

**Resolved items live in [`CLOSED_ISSUES.md`](CLOSED_ISSUES.md)** as of
2026-07-31 — including everything fixed-but-not-yet-verified, whose **CAD gates
are listed in one table at the top of that file**. That table is the V5
close-out checklist. The former `Low_Priority_issues.md` is merged into the
"Low priority" section at the bottom of this file; its numbered items are now
`LOW-1`…`LOW-8` and links should use those IDs, not line numbers.

Severity: **crash** | **wrong-output** | **scope** | **ux** | **perf** |
**feature** | **question**. Wrong-output outranks crash — silently wrong numbers
on a plan sheet are the worst outcome.

Forward scope (the next cycle, not this list) is
[`Version 5.1.md`](Version%205.1.md).

---

## PFINVERT

- No open field findings. 

## PFLABEL

- **[wrong-output — CRITICAL] Structures silently dropped from a run.** On line
  DF (5 identical `DBI_24x24`) PFLABEL listed and labeled only 3 of 5; the loss
  is **pre-dialog** (`pflabel:pending` → `pf:lines-at-point`) and no
  per-structure skip message fires. Case that stays missing: handle `51FF8`, sta
  628.846 — offset 0 from the rebuilt `.cl`, interior to the range, plain
  top-level INSERT, rule MATCH. Every naive cause (name filter, offset
  tolerance, station range, corridor, `vl-sort` dedup) ruled out on the live
  drawing. **Root cause (confirmed against the Road API catalog):** membership
  gates on `cl_location_at_pt`, which returns **nil on failure**; a structure
  just outside a deflection PI has no valid perpendicular foot, so the API
  returns nil, `pf:cl-locate-safe`'s terminus-only fallback misses an interior
  point, and the structure is dropped with no output. Tolerance-independent (the
  projection is *absent*, not large) — which is why widening `*pf-offset-tol*`
  0.2→0.8 did nothing. Compounded by the TWIN pre-filter acting as an
  authoritative silent gate (basename-keyed, no checksum) that can veto before
  the authored test runs. **Fix (planned; scaffold landed):** replace projection
  membership with point-to-**segment** distance (`pf:pt-poly-dist`) against a
  directly-parsed `.cl`; graded radial band (`*pf-vertex-band-hi/lo*`); full drop
  accounting so nothing vanishes without a printed reason; TWIN demoted from gate
  to setup-time misalignment witness. Data-independent scaffold already in:
  canonical `.cl` identity (`pf:cl-id`), GEOM `KIND` + per-vertex stations, TWIN
  re-key + `.cl` checksum. Remaining work is gated on the `.cl` format probe
  (Carlson box). **Acceptance:** PFLABEL on DF lists and labels all 5 `DBI`,
  incl. `51FF8` at 628.846.
  
- **[ux] Error parade in the command line.** Terse as filed; needs a repro case
  before it can be worked. Partly addressed by the 2026-07-27 `.cl` parser work
  (root README §11) — confirm what remains.

## PFXLABEL

- **[verify] Skipped-source crossing.** Findings 243/244/245/247 are fixed
  (CLOSED_ISSUES.md); the one unconfirmed case is `SANITARY_A @ 5+14.38`.
  Re-test before considering the group closed. This is CAD gate #3.

## PFSETUP

- **[ux] Dialog box size.** Setup dialogs should be larger. *(field note 252)*
- **[feature] Discover crossings & shared stations at PFSETUP.** Currently
  crossing discovery only runs in PFXLABEL; the ask is to find `.cl` crossings
  and shared stations at registration time. *(field note 240)*

## PFREMOVE

- No open field findings. (Covered by TESTING.md §7 / §5, not yet executed.)

## PFANCHOR

- **[ux] No warning when the anchor has been moved.** Repro: move anchor →
  PFSETUP → Refresh → PFLABEL → no warning. The suite carries on against a datum
  that no longer matches the grid.

---

## Shared / cross-cutting

- **[perf] Per-crossing `pfa:find-anchor` full-DB scans** (§13.3). An All-mode
  pass re-scans the whole database per crossing; scan the registry once per
  command and pass it down. *(field note "Performance improvements?")*
- **[crash-guard] Backtick sheet names.** `pf:parse-sheet-name` closes only on a
  straight `'`, so `` STORM LINE `DA` `` silently skips in AUTO.
  *(TESTING.md known-open)*
- **[question] `PICKADD`** — does the suite need to save/restore it around
  selection? Flagged, not investigated. *(field note "PICKADD variable change?")*

---

## Native Carlson integration

Policy (Jake, 2026-07-21): **make every native Carlson call we can** instead of
hand-entered or hardcoded values. The three calls already adopted are in
CLOSED_ISSUES.md.

- **[feature] Metric guard (`is metric`).** The suite hardcodes english —
  `pf:pipe-at` does `(TOP−INV)×12` (inches), stations/elevations in feet. A
  metric drawing would be silently wrong. Minimal step: read the metric flag and
  **warn/refuse**; full metric support is a larger feature. **Blocked on the
  exact variable name** — the reference lists "is metric" (a space → not a valid
  symbol); confirm the real symbol in a live session before wiring.
- **[decision] `sv:ts` / `sv:ps` (text / symbol scalers).** Deliberately NOT
  adopted: label size comes from the firm-standard `*pf-text-base-height*` × sf,
  an intentional firm choice, not Carlson's scaler. Keep as a possible
  cross-check only.
- **[future] `psname` (Carlson Support folder).** Candidate home for the
  `PF-PIPE_*` block library `.dwg`/`.dwt` — use when the block library is built.
- **N/A:** `crdfile` (plan-view coordinates, irrelevant to profiles); no native
  crossing-finder / station-formatter / profile-grid-geometry exists (confirmed
  API catalog) — `pf:fmt-station`, `.cl` intersection and the top-of-grid probe
  stay ours.

---

## Design decisions / open questions

- **[question] EXACT per-vertex stations in `GEOM_*` — stored, never read**
  (DATA-FLOW §3.3, the audit's one remaining orphan). The z-slot stations
  are the whole justification for parsing the `.cl` instead of walking the
  Road API, yet no caller reads `(nth 4 (pfa:geom-get …))` and nothing in
  `Version 5.1.md` names a consumer. Jake's call: name one (PFCHECK
  clearance is the natural candidate) or stop filing them at parse time.

- **[question] A palette control for indexing** (DATA-FLOW §6, 2026-08-01).
  Registration now repairs the index and `C:PFINDEX` Build remains the
  explicit full rebuild. btnRefresh stays a pure read on purpose — indexing
  from the palette would have to queue `PFINDEX` through `pfp:defer`, and a
  reflexively-clicked control should not inherit a drawing write. If a
  dedicated "Index" button is wanted, it needs a control added in OpenDCL
  Studio (Jake) plus a one-line handler; decide after the latency gate
  (CLOSED_ISSUES gate #11) says whether the repair path already suffices.

- **[question] GEOM cache storage location.** Geometry lives in the drawing's
  NOD (per-drawing) keyed by `.cl` identity. If multiple sheet drawings share one
  project data folder, a project-folder **sidecar** cache (trace once per
  project) is a strictly bigger win. **Unblocked:** the reliable project path
  this needed landed 2026-07-21 (native `tmpdir$`, `pfset:root-get`). Only open
  question left: **one sheet per project, or many sheets sharing one data
  folder?** If many, build the sidecar; if one, the in-DWG NOD cache is already
  right. *(TESTING.md storage-location discussion)*

- **[decided — do not re-open] A crossing is written to the OWNING anchor's
  record, and only that one.** Each anchor's ledger holds `X_*` records for the
  crossings on *its* line, keyed by source basename. The same physical
  intersection therefore appears in both lines' ledgers, from each line's own
  point of view.
  - **This is deliberate, not duplication to be normalised away.** Re-raised
    2026-07-30 as "one fact stored twice, move it to a NOD store keyed by `.cl`
    pair, like `GEOM_*`" — **rejected, as it had been before.** The anchor hard-
    owns its record: that is what makes `PFREMOVE` a clean teardown (the ledger
    dies with the entity that carries it), what keeps one line's data from
    outliving the line, and what stops a registration having to write into every
    other anchor's record. A shared store trades all three for a deduplication
    nobody needs.
  - The two views are also **not** identical rows: each stores the crossing from
    its own side — its own station as target, the other's as source, and the
    elevations in the matching order. Neither is derivable from the other without
    knowing both `.pro` bindings.

- **[idea] Reciprocal continuity check across anchors' `X_` records.** Because
  each anchor records its own view, the two views of one crossing are a natural
  cross-check: if line A's ledger says it crosses B, then B's ledger — where B is
  itself anchored — should carry the reciprocal, at the same `(x y)` and with the
  elevations swapped (A's target elevation is B's source elevation).
  - **What a mismatch catches**, none of which any single-anchor read can see:
    one side discovered before a `.cl` changed and never re-run; a stale `.pro`
    binding on one side only; a crossing recorded on one line and missing
    entirely on the other.
  - **Home: `PFCHECK`** — announced in the loader banner (`pftools-load.lsp:54`,
    "Coming this cycle"), not yet built. It is a whole-drawing consistency
    question, which is exactly that command's job, and it wants no new storage:
    both halves are already on record. **PFCHECK is scoped for V5.1** — see
    [`Version 5.1.md`](Version%205.1.md) §4.
  - Note the live scan (`pfa:xing-find`, 2026-07-30) does **not** cover this: it
    recomputes geometry for one target, so it would find a missing reciprocal
    only as a `NEW` row on the other line, and it says nothing about elevations
    at all.

---

## PFPALETTE

Shakedown results and the full test matrix live in
[`../pfsuite-odcl/PALETTE-TESTING.md`](../pfsuite-odcl/PALETTE-TESTING.md).
Wiring a control is [`../pfsuite-odcl/OPENDCL-WIRING.md`](../pfsuite-odcl/OPENDCL-WIRING.md).
Only unresolved items are listed here.

- **[ux] Every tree click fires `OnSelChanged` TWICE, and each dispatch prints
  `*Cancel*`.** Parked 2026-07-29 — diagnosed, not fixed. Do not re-derive any
  of this:
  - **Measured** with `PFPTAR` trace on: one click on the Registry tree produces
    **two** `TVW#OnSelChanged` dispatches carrying the **same** `Label`, both
    routing correctly (`tree-map: YES`, `tar-map: no`). So the routing is right
    and the *dispatch* is doubled, not the work.
  - `*Cancel*` is emitted by **OpenDCL**, once per dispatch into LISP, before our
    handler runs. Nothing written in a handler can prevent it.
  - **RULED OUT — do not retry.** `CMDECHO 0`: no effect. `MENUECHO 3`: silences
    the trace but **not** the cancels, and it is **disqualified as a fix
    regardless** — it suppresses `prompt` output from modeless handlers, which is
    precisely the error and refusal messages that must always print. Our read
    path: traced end to end (`pfa:read-attribs`, `pfa:meta-get`, `pfa:files-get`,
    `pfa:status-roll`, `pfp:file-cell`) — pure entget and dictionary reads, no
    `command`, no Road API.
  - **Leading theory:** the Commands tree was duplicated from `tvwLines` in
    Studio and kept the source's event binding, so the project holds two
    registrations naming `tvwLines#OnSelChanged` and OpenDCL invokes the handler
    once per registration. Consistent with the 07-29 finding that the Commands
    tree dispatches under `tvwLines`. **Still doubled as of 2026-07-29** — the
    theory is unconfirmed and the Studio checks tried so far have not cleared it.
  - The duplicated *work* was killed 2026-07-30 (`pfp:route-sel`, see
    CLOSED_ISSUES.md). The cancels themselves are unaffected — still one per
    dispatch, still not fixable from LISP.

- **[blocker] No List View getter is attested anywhere in this suite.** After
  `lvwCommand` was rebuilt as a real List View (CLOSED_ISSUES.md), the
  `Label Selected` read-back that `dcl-ListBox-GetCurSel` / `GetText` would have
  provided is unproven. Two parts:
  - Settle it with `C:PFPAPI *LIST*`, which calls nothing, **before** assuming a
    getter exists.
  - The harder half is **enumerating several selected rows**. `GetCurSel` is
    singular and the `SelChanged` event reports only a count on a multi-select
    list. This is what gates `Label Selected`.
  - **Re-read the `SelChanged` argument list in Studio after the type
    conversion.** `(ItemIndexOrCount Value)` was measured off the **List Box**'s
    Events panel, and that panel is per control *type*. A wrong argument list is
    as silent as an unticked event.

- **[ux] `optTools`' `SelChanged` is not ticked in Studio** (PALETTE-LAYOUT §7
  has carried it as an action since 2026-07-30). Symptom, and it does not look
  like the cause: clicking a Tools item and pressing RUN answers `PFPALETTE:
  select a line first.` That string is printed only by `pfp:need-row`, called
  only by `pfp:order-fire`, reached only when `*pfp-active-group*` is not
  `TOOLS` — so the message is proof `optTools#OnSelChanged` never fired, and it
  reads as a fault in PFPROINV/PFPROTOP instead. `pfp:order-fire` now names the
  armed group when it refuses. **Fix is one tick plus `PFPRELOAD`**; `C:PFPCTL`
  confirms whether `optTools` has ever reported.

- **[roster drift] The five pick buttons do not exist on the current `.odcl`.**
  Open prints `control is nil -- btnPickCL / INV / TOP / DESIGN / EXIST`
  (2026-07-29), five lines every time, because `*pfp-controls*` and
  PALETTE-LAYOUT §5 still list them. Open question: deleted with the Edit/New tab
  work, or renamed onto those tabs? Roster and §5 stay wrong until answered.

- **[guard missing] `dcl-Form-SetBackColor` does not exist in this OpenDCL
  build.** Reported on every open. §7's `'font` skin mode therefore cannot paint
  the form background. Gate the call behind `pfp:callable-p` like the other
  probes.

- **[deferred by decision] Palette persists across drawings — NOT intentional,
  and the fix is blocked.** The palette is owned by the OpenDCL ARX runtime, so
  it outlives any document and sits on the start screen showing the last
  drawing's registry, which native AutoCAD palettes do not do.
  `EnteringNoDocState` → close is the intended answer; field test 2026-07-27
  found it **never fired**, and `DocActivated` threw `no function definition:
  C:PFSUITE/PFSPALETTE#ONDOCACTIVATED`. Read together: the event fires into a
  document where the suite was never loaded, and AutoLISP namespaces are
  per-document. **The blocker is namespace, not form state** — neither
  `dcl-Form-Hide` nor a `vlr-docmanager-reactor` fixes a handler that does not
  exist in the document being activated into. Candidate: per-document autoload
  (`acaddoc.lsp`). **Deferred 2026-07-27** in favour of Phase 2. Also means stale
  data after a drawing switch persists, and activating into an unloaded drawing
  throws a *visible error* rather than failing quietly.

- **[untested] Docked layout is barely tested.** Every resize test in the plan is
  a *floating* test done by dragging edges; docked is the mode this palette is
  designed for (`Dockable Sides` = Left + Right). A docked-only gray box over the
  footer labels is recorded at PALETTE-TESTING §1.7; may already be resolved by
  the label background change.

- **[layout] `tvwLines` misaligned**, and leaves a gap above it that grows on
  stretch — likely `Use Top From Bottom` = 1 where PALETTE-LAYOUT §3 specifies 0.
  **All existing anchoring evidence was gathered against a stale in-memory
  project**, so §1.6 must be re-run after the fix regardless.

- **[constraint] `Min Width` ≥ 900 is load-bearing.** It closes the
  vanishing-buttons issue *by construction* — the form cannot narrow enough to
  compute a negative x. Lowering it re-opens that issue. Cost: a Left/Right-
  dockable vertical strip with a hard 900px floor is a wide strip. Narrowing it
  means reflowing the five fixed-width Registry button rows — a redesign, not
  scheduled.

- **[unrun] Duplicate `(Name)` check (test 1.5).** `PFPDIAG` proves a name
  *resolves*, not that it is *unique*; a duplicate leaves both resolving with one
  unaddressable, and nothing detects it but reading the Studio tree. This is the
  surviving half of the old LOW "`.odcl` names unverifiable" item.

---

## Low priority — hygiene and drift

Merged from `Low_Priority_issues.md` 2026-07-31. **Cite these by ID.** Resolved
LOW items moved to CLOSED_ISSUES.md.

- **LOW-1 — two hand-rolled `CMDECHO` save/restores remain.** `pfp:ensure`
  (pfpalette.lsp:27) and `C:PFPRELOAD` (:103) save and restore `CMDECHO` by hand
  around `(command "_OPENDCL")` rather than using `pf:echo-off` / `pf:echo-on`.
  Correct in isolation and no longer a re-entrancy hazard now that `pf:echo-off`
  saves once — but they are the last two copies of a pattern the suite otherwise
  consolidated.
- **LOW-2 — `*pf-preset-target*` (README §6a) was never implemented.** No
  occurrence anywhere. Either build it or strike it from §6a.
- **LOW-3 — session directory memory is clobbered.** `pfsetup.lsp:92`, `:111`,
  `:129` overwrite `*pfset-dir-cl/pro/tin*` with the company folder on every
  pick, so the "last-browsed directory" feature in pfsettings §3 never takes
  effect.
- **LOW-4 — the XING pass ledger only appends** (`pfxlabel.lsp:367-372`); dead
  and duplicate handles accumulate across relabels.
- **LOW-5 — `pf:fmt-station` edge cases** (`pftools-lib.lsp:605-607`): produces
  `0+-50.00` for negative stations (documented caveat) and `0+100.00` for
  99.999 (rounding at the boundary).
- **LOW-6 — dead API surface. ADJUDICATED 2026-08-01** (DATA-FLOW §5): the
  no-caller symbols were quarantined to `pfsuite/_attic/_attic.lsp` (never
  loaded; the gates skip it). What remains on the dead-code gate is
  deliberate scaffolding, each with an in-file KEEP note: the `pf:tin-*`
  set (`.tin` coverage checks, V5.1 §4), `pfa:xr-telev`/`-selev` (PFCHECK
  clearance, V5.1 §5), `pfsew:set-opt` (hydraulics options seam, V5.1 §7),
  `pf:text-layer`/`pf:align-layer` (documented revert path to per-type
  layers). Nothing here is undecided any more; revive from `_attic` if a
  consumer ever lands.
- **LOW-7 — `*pftools-dir*` is hardcoded to the deployment machine's path.**
  Known open issue, not a bug to fix in passing; it becomes real the first time
  the suite is installed on a second machine.
- **LOW-8 — `pfsuite-md/pf2hydro.md` duplicates `pfsuite/pf2sew.md`.** Same
  design doc, two homes, and the built module shipped as `pfsew:` while
  `pf2sew.md:24` still reserves the prefix `pfh:`. Retire one and correct the
  prefix line. See [`Version 5.1.md`](Version%205.1.md) §9.
