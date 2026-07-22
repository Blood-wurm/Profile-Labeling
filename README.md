# PFTools V4 — Profile-Labeling Toolset

AutoLISP/DCL tools for annotating utility **profile drawings** in Carlson Civil
on AutoCAD Map 3D. The suite labels drainage/utility structures and pipe
crossings on storm, sanitary, and water profiles to the firm's drafting
standard — the geometric work Carlson's native profile commands don't cover.

> **How to read this.** §1–§3 are plain-language (for explaining to Andy).
> §4 onward is the engineer's reference: commands, the workflow call-trace,
> the data model, and the file map.

---

## 1. What it does (plain language)

A profile sheet shows a utility line in section — horizontal axis is **station**
(distance along the line), vertical axis is **elevation**. Every structure and
every pipe crossing needs a label at the right station carrying the right ID,
elevation, and (for crossings) pipe size and material.

The numbers behind each label aren't in the drawing — they have to be computed
from the alignment geometry (`.cl` files), the design profiles (`.pro` files),
and the crossing geometry (where two lines actually intersect in plan). PFTools
computes them from Carlson's own data and draws the labels.

It produces:

- **Structure labels** at the top of the grid — station(s), combined structure
  ID, and a ground-line elevation row the drafter fills in.
- **Crossing discovery** — finds every point where another registered line
  crosses the profiled line, reading the exact station on each.
- **Crossing labels** — draws each crossing pipe at its true invert on the
  target grid, with size, material, and the standard line label.
- **A live completion record** — the drawing itself tracks what's labeled
  and what's outstanding, per profile (reported on every run).

The shift in V4: a profile's grid and crossings become **drawing-resident
state**. Register a grid once; every command afterward reads it, and the
drawing itself remembers what's been labeled and what's left.

## 2. The V4 pivots (what changed from v3)

| Area | v3 | V4 |
|---|---|---|
| **Registration** | Grid re-picked every run | **Register once** (an *anchor block*), every command reads it |
| **Two tiers** | — | **AUTO** names every profile on the sheet (stubs); **USER** places each grid (anchors) |
| **Crossing inverts** | Vertical **bore probe** of the drawn grid | **Read from the source `.pro`** via the Road API (`profile_z`) — the probe is *dead* |
| **Crossing draw** | Both grids | **Target grid only**; a source needs its `.pro` *bound*, not its grid *placed*. Reciprocal annotation = run again with that profile as target |
| **Material** | — | Asserted per-type in PFSETUP, stored on the anchor, read into the crossing label (`NN" <MAT>`) |
| **Commands** | `PFXFIND` + `PFXLABEL` + `PFXGRID` trio | Collapsed to **one** `PFXLABEL` (discovery auto-runs) |
| **Only surviving probe** | invert + top | **Top-of-grid probe only** (highest `PF-GRID-MJR` hit; grid tops step) |

## 3. Why build this vs. Carlson native

Automate only where there's genuine geometric work the drafter can't reasonably
do by hand: membership logic, station math on curved alignments, crossing
geometry, and invert reading off authored profiles. That bar is why an invert
label wrapping two manual picks stayed **shelved** in v3 — and why `PFINVERT`
now earns the build: it reads the *authored* `.pro` (not a probe), brackets
in/out at the grade breaks, and pulls lateral inverts from the registry.

---

## 4. Command reference

| Command | Alias | File | What it does |
|---|---|---|---|
| `PFSETUP` | — | `pfsetup.lsp` | Register/edit grids. **AUTO** names every profile on the sheet; **USER** places each grid. |
| `PFLABEL` | `PFL` | `pflabel.lsp` | Label structures at the top of a registered grid. Reads the anchor — no per-run dialogs for geometry. |
| `PFXLABEL` | `PFX` | `pfxlabel.lsp` | Discover + label pipe crossings on the target grid. One / All-outstanding. |
| `PFINVERT` | `PFI` | `pfinvert.lsp` | Label every invert at each structure — primary I.I/I.O from the `_INV.pro` grade breaks, laterals from the registry. |
| `PFREMOVE` | — | `pfanchor.lsp` | Tear down one profile's record — anchor + ledger + every handle-tracked entity. Untracked work is never touched. |
| `PFLABELSET` | — | `pflabel.lsp` | Open the label settings dialog standalone (prefix/suffix, layer, style). |
| `PFCHECK` | — | *(planned)* | Record-integrity check. Announced by the loader, not yet built. |

### 4.1 `PFSETUP` — two-tier registration

Registration splits in two. **Identity is enough to discover; placement is
required only to draw.**

**AUTO (identity, sheet-wide, never guesses)** — fires automatically the first
time a drawing has no registry:

```
pfs:auto
 ├─ pfs:scan-sheet-names      scan PF-NAME text  → (type . name) pairs
 ├─ pfs:cl-lookup             resolve Type_Name.cl in the alignments folder
 ├─ pfs:pro-lookup            auto-bind the _INV / _TOP .pro pair
 ├─ pfa:stub-put              write an identity-only STUB to the NOD dict
 ├─ pf:cl-geom                sample the .cl ONCE and file its shape (GEOM cache)
 └─ pfa:twin-put              match the DRAWN centerline once, file its handle (TWIN)
```

The `pf:cl-geom` step is the V4 speed pivot: `.cl` geometry is traced **once
at registration** and filed (see §7 GEOM). Label commands then READ the shape
instead of re-tracing every line every run — the per-run Road-API sampling is
gone. Alongside it, `pfa:twin-put` matches the `.cl`'s **drawn** centerline by
endpoint pair and files its handle (see §7 TWIN) — the membership pre-filter
reads that drawn line's live verts (exact PIs) instead of the sampled corridor.
Placement (`pfs:place-one`) warms both caches for a directly-placed profile.

**Project root is native (no PFROOT).** The project data folder comes straight
from Carlson — `pfset:root-get` reads `tmpdir$` (the active project's data
folder) live, so there's nothing to declare or store per drawing. Only when
there's no active Carlson project does a one-shot browse seed a **session**
fallback (lost on close). The old `PFROOT` command and its per-drawing NOD
record are retired.

**Folder routing (firm standard).** Registration and the setup dialog's file
picks don't browse one flat root: `pfset:get-company-dir` takes that native
root and **searches up** from it (0–`*pfset-std-search-depth*` parent levels)
for each firm-standard subfolder — `.cl` → `Alignments`, `.pro` →
`…\CivilSurvey`, `.tin` → `Surfaces` (see §8). The search-up self-calibrates to
wherever `tmpdir$` lands (no fixed level assumption). A missing standard folder
falls back to the last-used directory, then to the root itself.

**Other native reads.** The suite prefers Carlson's own values over hand entry
wherever it can: the setup dialog **seeds the plot scales** from `sv:sm` /
`sv:vs` (`pfset:native-scale` — still editable; the stored value wins on Edit),
and the settings/temp folder is **Carlson's `usrdir$`** (`pfset:dir`, falling
back to `LOCALAPPDATA`/`TEMP`). Deliberately *not* adopted: `sv:ts`/`sv:ps`
text/symbol scalers (label size is the firm-standard `*pf-text-base-height*`,
not Carlson's scaler). Still open: a metric guard off the english/metric flag
(the suite currently hardcodes english).

No matching `.cl`, an ambiguous match, or a `.cl` with no sheet name is
**reported and skipped** — never guessed. The reverse direction (a `.cl` with
no grid name on the sheet) is noted too.

**USER (placement)** — promotes a stub to an anchor, per grid:

```
pfs:place-one
 ├─ pfs:show-dialog           identity override, scales, .cl/.pro/.tin slots,
 │                            material, DATUM (typed here — Carlson-style)
 ├─ pfs:pick-extents          pick LOWER-LEFT (datum line) then TOP-RIGHT (extents)
 ├─ pfs:build-xform → pfa:write-anchor    write the PF-GRIDANCHOR block
 ├─ pfa:meta-put / pfs:bind-files         .cl + .pro/.tin bindings + checksums
 └─ pfa:stub-del              delete the promoted stub
```

The registry menu is the `pfsetup_registry` **dialog** (Place / Place All /
Edit / New / Refresh); the two extent picks are the only command-line steps
left in the whole suite's setup flow.

**One datum per grid, anchored at the lower-left; run steps don't matter.**
(Settled — do not revisit.) Extents are stored **relative** (as the block's
X/Y insert scale), so a window-move of grid + anchor carries both corners.
**Vertical scale = declared H/V; per-station top = the probe.** Undo is one
group **per grid** — `U` peels one grid, not the batch.

Edit mode invalidation:

| Change | Result |
|---|---|
| `.pro` swap | cheap — record updated, derived output stale |
| scales / extents | everything redraws |
| `.cl`, same station range | full regeneration |
| `.cl`, different range | **REFUSED** — that's a new anchor; `PFREMOVE` first |
| identity (type / name) | **REFUSED** — `PFREMOVE` + fresh placement |

### 4.2 `PFLABEL` — structure labels

The V4 run is **pick-first** (PFXLABEL parity, `pf_run`): `PFLABEL` →
`pfs:choose-or-place` picks the target from the registry (`pf_pick` list) →
**run dialog** for that ONE target (multi-select structure list, `[LABELED]`
marked from the pass ledger) → *Label Selected* / *Label All*. There is **no
target popup in the dialog** — the target is resolved before it opens, and
choosing an unplaced profile at the pick *is* consent to place it (two corner
picks, on the fly). Everything the old dialogs gathered lives in the anchor
record. The dialog does all its Road-API / recon work **before** `new_dialog`
(`pflabel:rd-compute`); the init block only paints — this cured the
ghost-dropdown freeze. (Wrong target → Cancel and rerun.)

- **Secondary `.cl` set = the registry, SAME UTILITY TYPE only** (anchors
  *and* stubs). A STORM profile's junctions are other STORM lines; a different
  type sharing a station is a *crossing* (PFXLABEL's job), not a combined-ID
  contributor. Membership is plan-view station math, so **identity alone
  qualifies a same-type line** — the moment AUTO names the sheet, every
  junction's combined ID (`AA-1/BB-2`) is complete, placed or not. This closes
  v3's silently-shorter-ID gap while keeping other utilities out of the label.
- **Membership pre-filter = the drawn "twin" line's live verts.** Before the
  authored `cl_location_at_pt` test, structures are cheaply pre-filtered
  against the `.cl`'s *drawn* centerline (its exact PIs, read live by the filed
  TWIN handle — no sampled corner-cut). `pflabel:build-lines` self-heals a
  missing/purged twin by re-matching once; if none is found the pre-filter
  simply drops and the authored test governs alone.
- **Label Y = the top-of-grid probe** at each structure's station (grids have
  stepped tops). A station with no `PF-GRID-MJR` hit is skipped and reported.
- **Layer** = derived `<TYPE>-TEXT_P`, handle-tracked, erase-and-replace on an
  `All` re-run. The *"Use current layer"* toggle draws on `CLAYER` instead:
  not tracked, not erased, but the pass is still recorded (timestamp + layer,
  no handles) so the record can tell "labeled off-scope" from "never labeled".

Composition (validated near-100% in v3, unchanged):

- **Station rows** — primary line first, remaining lines alphabetical.
- **Combined ID** — alphabetical by line name (stable across profiles).
- **Const rows** — `*pf-rule-table*` (cfg), ordered first-match.
- **Elevation** — `<G.L.|T.G.|T.R.> XXX.XX` **placeholder** the drafter fills
  (PFLABEL does **not** sample the TIN today; the `.tin` binding is for the
  planned invert/QA work). `HDWL` drops the elevation row.

### 4.3 `PFXLABEL` — crossing discovery + labeling

One target-directed command. Discovery auto-runs, then you label.

```
c:PFXLABEL
 ├─ pfxl:resolve-target       session-last (silent if still placed) else registry picker
 ├─ pfxl:discover             target .cl × every OTHER registered .cl
 │    ├─ pf:cl-geom / pf:poly-x         cached .cl shapes × plan intersection (sampled once at registration; arcs followed)
 │    ├─ pf:refine-x                    re-sample ~0.1 ft near a hit
 │    ├─ pf:sta-at                      read both stations off the Road API
 │    └─ pfa:xing-merge                 additive merge into the ledger (elevations preserved)
 ├─ pfa:xing-list / pfa:recon           working list + per-crossing LABELED/OUTSTANDING
 ├─ pfxl:run-dialog                     the crossings DIALOG (pfxl_run): list + status,
 │                                      Label Outstanding / Label Selected / Change Target
 └─ pfxl:label-one  (per selected crossing)
      ├─ pfxl:src-files                 source's INV/TOP .pro + material
      ├─ pf:pipe-at → pf:pro-z          invert (flowline z) + size (nearest nominal to (TOP−INV)×12)
      ├─ pf:top-at                      grid top at this station (probe miss → skip)
      ├─ pfd:station-line / pfd:text    station line (PF-XING) + vertical station text
      ├─ pfd:insert-pipe                the crossing pipe at its true invert on the TARGET grid
      ├─ pfd:label-pipe                 NN" <MATERIAL> + standard line label
      └─ pfa:xing-put-elevs             persist target + source inverts to the ledger
```

- **Discovery is additive** — never destructive. A per-source **checksum
  short-circuit** skips pairs whose two `.cl` files are unchanged since the
  last scan.
- **Label Outstanding** draws only **OUTSTANDING** crossings; relabeling a
  `[LABELED]` selection asks first (`pf_confirm` — duplicates are always a
  deliberate Yes).
- A source that isn't registered, has no INV `.pro` bound, or whose invert is
  unreadable is **skipped and reported** on the command line, per crossing
  and in the pass summary.
- The whole pass is one undo group. (The v4.0 per-profile crossings *table*
  is retired — it only displayed what the ledger + reconciliation already
  track; the LABELED/OUTSTANDING list in the crossings dialog is the
  surface now.)
- **Verification zoom** (`*pfx-zoom-pause*`): each drawn crossing is framed
  and paused on (`ZOOM Window` + `DELAY`), then the pre-run view is restored
  after the pass. Set the pause to `0` to disable. Every view change routes
  through `pfxl:zoom-corners` — `ZOOM _Center` miscomputes in this Carlson/Map
  build ("No Center found for specified point"), so a center+height is
  converted to window corners at the current viewport aspect.

### 4.4 `PFINVERT` — invert labels at structures

**The command split: `PFLABEL` owns top-of-grid text; `PFINVERT` owns
everything at pipe elevation.** Same anchor-driven, **pick-first** run shape
(`pfs:choose-or-place`, then a structure list), but through its **own**
dialog — `pfi_run` (tile keys `pi_*`, handlers `pfi:rd-*`), a separate
definition from `pf_run` so invert-specific fields can grow without
disturbing PFLABEL. Compute-before-`new_dialog`, same as PFLABEL. The
`_INV.pro` binding is **fatal** when missing — every elevation comes from
it.

```
c:PFINVERT
 ├─ pfi:setup                  anchor record + registry line table (pflabel's walk)
 └─ pfi:process-structure  (per structure on the primary)
      ├─ pf:pro-verts              exact .pro vertices (file-parsed, cached)
      ├─ pfi:invert-bracket        I.O/I.I from the two adjacent .pro VERTICES
      ├─ pfi:endpoint-hits         same-type lines TERMINATING here (end junctions)
      ├─ pfi:lateral-info          each other line here: registry .pro → invert + size
      ├─ pfd:draw-label-stack 'MR  the invert COLUMN (hangs below base Y)
      └─ pfd:insert-pipe           bare lateral pipe block at TRUE elevation
```

- **Primary = text only** (`I.O. <elev> (NN")` / `I.I. <elev> (NN")`) — its pipe
  is already the `.pro` linework on the grid. **Laterals = bare block at true
  elevation + `I.I. <elev> (NN")` row** (non-present pipes; line identity is
  already on the structure's top label). No leader line.
- **Junctions at a line's end:** the on-line membership tolerances are tuned for
  *pass-through* hits, so a lateral that **terminates** at a structure (its own
  endpoint — common at the primary's downstream structure) slips past them.
  `pfi:endpoint-hits` recovers those: any same-type registered line whose
  endpoint lands within `*pfi-junction-tol*` (2 ft) of the structure is added as
  a shared lateral, read at that line's range-end.
- **Vertex bracket, exact numbers:** the `.pro` is authored from the polyline
  endpoints, so each vertex **is** an invert. `pfi:invert-bracket` reads the two
  adjacent vertices meeting at the structure (via `pf:pro-verts`, the suite's
  one file read — the Road API exposes no vertex accessor). The *lower* of the
  pair is downstream → `I.O.`, the higher → `I.I.` A polyline **endpoint** is a
  terminus (one invert): the lower profile end → single `I.O.`, the higher →
  single `I.I.` No sampling, so no 0.05-ft bias and no swap.
- **The column rule (collision-proof):** all text rows share **one base Y** =
  lowest invert present − (`*pfi-invert-offset-factor*` × text height; 16 units
  at H:50), fanning across the station X: **I.O. downstream-left, shared lateral
  I.I.(s) centred, primary I.I. upstream-right**. Columns, not true-elevation
  rows — a 0.10' drop can never overlap two callouts. The **leftmost** structure
  shifts its stack right to clear the elevation-axis labels. Blocks sit at true
  elevation and may stack; text never does.
- **Layer / pass / undo — identical to `PFLABEL`:** derived `<TYPE>-TEXT_P`
  handle-tracked (PASS `INVERT`, `All` replaces by handle) vs the
  *"Use current layer"* toggle (PASS `INVERT-CLAYER`, fire-and-forget).
  STATUS is written after the pass from the `_INV.pro` checksum.

### 4.5 `PFREMOVE` — teardown

```
pfa:teardown
 ├─ pfa:erase-pass (per PASS_*)   erase every handle-tracked entity, by handle
 └─ entdel anchor                 the ledger dies with it (hard-owned ext-dict)
```

Removes the tool's **memory** of a profile plus the entities it can name by
handle. **Untracked work — CLAYER passes, hand-drawn linework — is never
touched.** A **copied** anchor is detected (its ledger points at the original's
entities) and offered a copy-safe purge that erases only the block. One `U`
reverses it.

---

## 5. Load order & file map

The loader (`pftools-load.lsp`) loads by **full path** in strict dependency
order. Each file may only depend on files above it — the V4 guardrail:

```
pftools-cfg.lsp    ← FIRST. Every tunable in the suite. Constants only, no code.
      │
pftools-lib.lsp    ← PURE engine. Never knows what an anchor/dialog is.
      │              Carlson API wrappers, geometry, membership, transforms,
      │              label composition, .cl sampling, top-of-grid probe, checksums.
      │
pfdraw.lsp         ← Drawing boundary. The ONLY file that entmakes label output.
      │              Returns enames so callers can ledger handles. Erases nothing.
      │
pfanchor.lsp       ← Record + registry. Anchor block, stub registry, ledger
      │              (ext-dict), reconciliation.  C:PFREMOVE
      │
pfsettings.lsp     ← User state: settings file, session dirs, native project
      │              root (tmpdir$), shared dialog pickers, layer/style lookups.
      │
pfsetup.lsp        ← C:PFSETUP  (AUTO names, USER places)
      │
pflabel.lsp        ← C:PFLABEL / C:PFL / C:PFLABELSET
      │
pfxlabel.lsp       ← C:PFXLABEL / C:PFX
      │
pfinvert.lsp       ← C:PFINVERT / C:PFI  (reuses pflabel's walk + pfxlabel's
                     registry resolution, so it loads last)
```

**Retired (kept in `_v3\` for reference only):**

| File | Fate |
|---|---|
| `pfdialog.lsp` | Split into `pfsettings.lsp` + per-command dialog wiring |
| `pfcross.lsp` | Superseded by `pfxlabel.lsp` (target-only, `.pro`-driven inverts; the vertical bore probe is gone) |

> `pfdialog.dcl` is still live — reworked 2026-07-19 to the native-Carlson
> style contract. It holds `pfsetup_registry` (the PFSETUP menu),
> `pfsetup_main`, `pf_run` (PFLABEL), `pfi_run` (PFINVERT — its own definition,
> `pi_*` tiles), `pfxl_run` (crossings), `pflabel_settings`, and the shared
> `pf_pick` / `pf_name` / `pf_scan` / `pf_confirm` dialogs. The command line
> keeps only screen picks.

Config split — **keep these apart:**

- `pftools-cfg.lsp` = the **firm's** constants (templates, maps, sizes, layers).
  Edited by hand, rarely.
- `pfsettings.lsp` = the **user's** persisted state (last-used paths, dialog
  values, project root). Written by the tools.

---

## 6. End-to-end workflow (call-trace per file)

A typical sheet, first pass. Each phase lists the files that fire and the
Carlson API "tool calls" (Road = `EWORKS.ARX`, DTM = `TRI4.ARX`) they make.

| # | Phase | Files → key calls | Carlson API |
|---|---|---|---|
| 0 | **Load** | `pftools-load.lsp` loads all 9 in order | — |
| 1 | **Project root** | `pfsettings.lsp`: `pfset:root-get` reads Carlson `tmpdir$` live (browse-to-session-fallback only if no active project) | — |
| 2 | **AUTO register** | `pfsetup.lsp`: `pfs:auto` → `pfs:scan-sheet-names`, `pfs:cl-lookup`, `pfs:pro-lookup` → `pfanchor.lsp`: `pfa:stub-put` → `pf:cl-geom` (file .cl shape) + `pfa:twin-put` (file drawn twin handle) | Road `cl_sta_range` + `cl_location_at_sta` (**one-time sample**, then cached) |
| 3 | **USER place** | `pfsetup.lsp`: `pfs:registry-dialog` → `pfs:place-one` → `pfs:show-dialog` (datum typed here), `pfs:pick-extents` → `pfanchor.lsp`: `pfa:write-anchor`, `pfa:files-put`, `pfa:stub-del` | Road `cl_sta_range` |
| 4 | **Structure labels** | `pflabel.lsp`: `c:PFLABEL` → `pfs:choose-or-place` (pick target) → `pflabel:run-dialog` builds the line table (reused by `pflabel:setup`) → `pflabel:setup` (`pfa:anchor->xform`, `pflabel:build-lines`→`pf:cl-geom` + `pf:twin-verts`, `pflabel:gather-inlets`) → `pflabel:process-structure` → `pfdraw.lsp`: `pfd:draw-label-stack`, `pfd:station-line` → `pflabel:write-pass` (`pfa:pass-put`, `pfa:status-put`) | membership pre-filter = drawn twin verts (no API); Road `cl_location_at_pt` (authored test); geometry from **cache**; top-of-grid probe (`inters`, no API) |
| 5 | **Crossings** | `pfxlabel.lsp`: `c:PFXLABEL` → `pfxl:discover` (`pf:cl-geom`, `pf:poly-x`, `pf:refine-x`, `pf:sta-at`, `pfa:xing-merge`) → `pfxl:label-one` (`pf:pipe-at`, `pf:top-at`) → `pfdraw.lsp`: `pfd:insert-pipe`, `pfd:label-pipe` | geometry from **cache**; Road `cl_location_at_pt` (station), **`profile_z`** (invert/top); `cl_location_at_sta` only on refine/cache-miss |
| 6 | **Inverts** | `pfinvert.lsp`: `c:PFINVERT` → `pfs:choose-or-place` → `pfi:run-dialog` → `pfi:setup` (pflabel's line table + inlets) → `pfi:process-structure` (`pf:pro-verts`, `pfi:invert-bracket`, `pfi:lateral-info`) → `pfdraw.lsp`: `pfd:draw-label-stack 'MR`, `pfd:insert-pipe` → `pfi:write-pass` | Road `cl_location_at_pt` (membership), **`.pro` file parse** (`pf:pro-verts`, exact vertices), `profile_z` (sizes + laterals) |
| 7 | **Re-run** | Same commands; `All` mode replaces prior passes **by handle**; discovery short-circuits unchanged `.cl` pairs; geometry served from the GEOM cache | Road (unchanged pairs skipped; no re-sampling unless a `.cl` changed) |
| 8 | **Teardown** | `pfanchor.lsp`: `c:PFREMOVE` → `pfa:teardown` (`pfa:erase-pass`, `entdel`) | — |

Per-file responsibility during a run:

| File | Role in the workflow | Writes to drawing? |
|---|---|---|
| `pftools-cfg.lsp` | Supplies every tunable read by the rest | no |
| `pftools-lib.lsp` | All math, geometry, membership, `.cl`/`.pro` reads, probe, composition | no (read-only queries only) |
| `pfdraw.lsp` | Entmakes labels/pipes/lines; returns enames | **yes** (creates only, never erases) |
| `pfanchor.lsp` | Anchor + stub + ledger; erase-by-handle; reconciliation | **yes** |
| `pfsettings.lsp` | Settings file / session dirs / NOD root; dialog pickers | NOD only |
| `pfsetup.lsp` | Orchestrates registration; owns the setup dialog | via `pfanchor`/`pfdraw` |
| `pflabel.lsp` | Orchestrates structure labeling | via `pfdraw`/`pfanchor` |
| `pfxlabel.lsp` | Orchestrates discovery + crossing labeling | via `pfdraw`/`pfanchor` |
| `pfinvert.lsp` | Orchestrates invert labeling (grade-break bracket + laterals) | via `pfdraw`/`pfanchor` |

---

## 7. The data model

Three record kinds, all keyed by **line name + utility type**:

```
STUB    (NOD "PFTOOLS", key STUB_<TYPE>_<NAME>)
        Identity only: .cl path + auto-resolved _INV/_TOP .pro. NO placement.
        AUTO writes it; a stub can DISCOVER but not DRAW. Placement promotes it.

GEOM    (NOD "PFTOOLS", key GEOM_<BASENAME>)  — the .cl geometry cache
        Content-addressed .cl shape: (1 .cl)(300 checksum)(40/41 sta range)
        (10 …verts). Filed ONCE at registration; label commands READ it in
        place of re-sampling the line every run. A reader re-checksums and
        re-samples on mismatch (self-heals a .cl edited on disk). Keyed by
        .cl IDENTITY, not the record — so promotion moves nothing, and one
        entry serves every command that references that line. (Drawing-wide
        today; a project-folder sidecar shared across sheets is under review.)

TWIN    (NOD "PFTOOLS", key TWIN_<BASENAME>)  — drawn-centerline binding
        (1 . handle) only. The .cl's DRAWN plan centerline, matched ONCE at
        registration by endpoint pair (`pf:cl-twin-handle`) and filed as a
        bare handle. The membership pre-filter reads its LIVE verts each run
        (`pf:twin-verts` → exact PIs, no sampled corner-cut); a moved/redrawn
        twin reads as-drawn, never cached stale. Nothing to invalidate — a
        purged handle resolves to nil and the reader re-matches or drops the
        pre-filter (the authored `cl_location_at_pt` test still governs).
        Keyed by .cl IDENTITY, like GEOM, so promotion moves nothing.

ANCHOR  (PF-GRIDANCHOR block, one per PLACED profile)
        Insertion point = grid lower-left (datum + origin). Extents RELATIVE
        (X-scale = width, Y-scale = height to the top-right pick).
        Attributes: LINE / UTIL / STA0 / DATUM / HPLOT / VPLOT.

LEDGER  (ext-dict "PFXLEDGER", hard-owned by the anchor — schema 3)
        META    (1 .cl)(301 .cl checksum)(302 self-handle → copy detect)
        FILES   (1 INV.pro)(2 TOP.pro)(3 tin)(4 DESIGN.tin)(5 material)(300/301 cksums)
        STATUS  (70 state 0/1/2/3)(1 timestamp)(300… findings)
        SCOPE   (1 timestamp)(300… candidate files) — discovery short-circuit
        PASS_*  (1 ts)(8 layer)(70 clayer?)(300… handles) — the erase-by-handle ledger
        X_*     one per crossing, CONTENT-KEYED: (1 sfile)(2 sbase)(10 xy)
                (40 tsta)(41 ssta)(42 telev)(43 selev)
```

**Derived, never stored:** whether a crossing (or structure) is *labeled* is
re-read from the drawing on every touch (`pfa:recon`) — a stored "done" flag a
drafter's edit could invalidate would lie. A crossing reads *labeled* when its
station line stands at the exact station X **and** its top vertex sits at the
per-station grid top (`pf:top-at`). Completeness is measured on the **target
grid only**.

**Safety contract:** reads are pure; writes happen only inside a caller-opened
undo group; **no layer-scoped erases** — erase is **by handle** only; all state
hangs off the anchor (erase it and the ledger dies with it); no reactors, no
background execution. Worst case for a corrupt ledger is "lose one profile's
memory," never the drawing.

---

## 8. File-naming convention (identity keys)

The whole registry rides on filename convention within the project data folders
(rooted at the native project folder, Carlson `tmpdir$`; see the folder table
below):

| File | Pattern | Role |
|---|---|---|
| Centerline | `Type_Name.cl` | station geometry (e.g. `Storm_DA.cl`) |
| Invert profile | `Type_Name_INV.pro` | flowline elevation (crossing invert) |
| Top profile | `Type_Name_TOP.pro` | pipe crown → size = nearest nominal to `(TOP−INV)×12` |
| Surface (existing) | `*.tin` | future invert/QA work |
| Surface (proposed) | `DESIGN_*.tin` | exactly one must carry the `DESIGN_` prefix |
| Sheet identity text | `PF-NAME` layer, `STORM LINE 'DA'` | AUTO parses type + name |

Types: `STORM`, `SANITARY`, `WATER`. A `.pro` with neither `_INV` nor `_TOP`
is an error the setup dialog rejects.

**Where the files live (firm-standard folders).** `pfset:get-company-dir`
takes the native root (`tmpdir$`) and **searches up** from it (via
`pfset:find-std-dir`, up to `*pfset-std-search-depth*` parent levels) for each
type's standard subfolder — file picks and AUTO lookups open there, not a flat
root:

| Type | Standard subfolder (`*pfset-std-subfolders*`) |
|---|---|
| `.cl` | `02_ProjectData\Alignments` |
| `.pro` | `05_Drawings\DrawingData\CivilSurvey` |
| `.tin` | `02_ProjectData\Surfaces` |

The search-up means no fixed assumption about how deep `tmpdir$` sits. The
routing is best-effort: a standard folder that doesn't exist falls back to the
session's last-used directory for that type, then to the root itself. The map
lives in **`pftools-cfg.lsp`** (`*pfset-std-subfolders*`) — retarget it there
if the firm's project template changes.

---

## 9. Layer conventions

| Layer | Owner | Behavior |
|---|---|---|
| `PF-GRID-MJR` | Carlson | The **top-of-grid probe** layer (highest hit = top). Also the AUTO scan's neighbor. |
| `PF-GRID-MNR`, `PF-HBOX` | Carlson | Grid frame; used by the anchor corner sanity probe. |
| `PF-NAME` | Carlson | Grid identity text — AUTO reads it. |
| `PF-ANCHOR` | tool | `PF-GRIDANCHOR` blocks. Created **no-plot**, visible in model space. |
| `PF-XING` | tool | Crossing station lines **and** their vertical station text — recon scans it for `LWPOLYLINE` only, so text on it is ignored (erase is by handle). |
| `PF-TEMP` | tool | Reserved (legacy invert-tick concept). As built, `PFINVERT` is handle-tracked on `<TYPE>-TEXT_P` instead. |
| `<TYPE>_P` / `<TYPE>-TEXT_P` | derived | Crossing pipe block + its text, by utility type. |
| `ALIGN-<TYPE>_P` | derived | Per-type alignment layer. |

---

## 10. Configuration (all in `pftools-cfg.lsp`)

Every tunable lives in one file. The load-bearing groups:

- **Membership** — `*pf-offset-tol*` (0.15 ft on-line), `*pf-corridor*`
  (0.2 ft pre-filter).
- **Text geometry** — `*pf-text-base-height*` 1.60 at the `*pf-ref-hplot*` 20
  reference scale; everything scales by `sf = hplot / ref`.
- **Structure rules** — `*pf-rule-table*`, **ordered, first-match** (compounds
  before singles; `SMH`/`DMH` before `MH`).
- **Materials per type** — `*pf-materials*` (placeholder lists — edit to the
  firm's real materials; keys must match the types).
- **Sampling** — `*pfx-sample-step*` 2 ft walk, `*pfx-refine-step*` 0.1 ft
  near a hit. The walk runs **once at registration** (`pf:cl-geom`) and is
  cached (GEOM, §7); label commands read the cache, so this step is not paid
  per run. A long alignment at 2 ft is also what drives GEOM vert count — the
  open lever if xrecord size ever bites is a coarser cached step (refine still
  pins precision live on changed pairs).
- **Pipe rendering** — `PF-PIPE_<NN>` block family; circle placeholder when a
  block is missing; `*pfx-zoom-pause*` verification pause (0 disables).
- **Invert bracket (`PFINVERT`)** — `*pfi-invert-offset-factor*` 4.0 (× text
  height column drop → 16 units at H:50), `*pfi-struct-width-max*` 15 ft (max
  gap for two vertices to be one structure), `*pfi-first-shift-clearance*` 12
  (× sf, leftmost-stack clearance from the elevation axis).
- **Project data folders** — `*pfset-std-subfolders*` (firm-standard `.cl` /
  `.pro` / `.tin` subfolders, searched up from the native `tmpdir$` root) and
  `*pfset-std-search-depth*` (how many parent levels to search). Retarget these
  if the firm's project template changes (§4.1, §8).

---

## 11. Operating notes & known limitations

- **Keep `.cl` / `.pro` files current.** Stale files are the usual cause of
  wrong results — regenerate from Carlson before suspecting the tool. The
  `.cl` checksum in `STATUS` flags a `.cl` that changed since setup.
- **Structures must be snapped to their centerlines** — membership uses a tight
  offset tolerance.
- **Don't `ATTSYNC` / `BATTMAN` the anchor** — its attribute positions are
  placed absolutely; syncing scatters them (harmless to data, ugly).
- **A *stretched* grid moves its anchor** rather than stretching it. The corner
  check catches the drift and Edit re-picks in place, ledger preserved.
- **Negative stations** aren't supported by the crossing content key.
- **Crossing draw is target-only** — a source line's own grid is annotated by
  running `PFXLABEL` with that profile as the target.
- **`PFINVERT` is built but not yet run in a live drawing** — statically
  verified only; validate I.I/I.O against a known drop manhole first. Its
  grade-break scan is sample-and-detect; if the Road API turns out to expose
  `.pro` PVIs directly, swap `pfi:invert-bracket`'s body only.
- **English units only (no metric guard yet).** Pipe size is `(TOP−INV)×12`
  inches; stations/elevations are feet. A metric drawing would be silently
  wrong — a guard off Carlson's english/metric flag is an open item
  (`OPEN-ISSUES.md`, "Native Carlson integration").
- **`PFINVERT` I.I/I.O bracket is a known live bug** — in field testing the
  in/out inverts came back swapped/collapsed and ~0.05 ft high; the fix needs a
  real `_INV.pro` to diagnose (see `OPEN-ISSUES.md`). Don't trust `PFINVERT`
  output until that's closed.
- **`PFCHECK` is announced by the loader but not built yet.**

---

## 12. Status & roadmap

**Structure + crossing labeling** carries forward v3's near-100% validation
against a completed job; the V4 rewrite moves inverts onto authored `.pro`
files (the fragile bore probe is retired) and makes the grid a registered,
drawing-resident record.

Shipped 2026-07-21 (post-pull; statically verified, **not yet CAD-tested**):

- **Native Carlson integration** — project root from `tmpdir$` (PFROOT
  retired), setup dialog seeds plot scales from `sv:sm`/`sv:vs`, settings folder
  from `usrdir$`, firm subfolders searched up from the native root (§4.1, §8).
- **Cross-utility scoping** — PFLABEL/PFINVERT membership scoped to the
  primary's utility type; PFXLABEL crossings stay cross-type (§4.2).
- **`CMDECHO` suppression** — shared `pf:echo-off`/`pf:echo-on`, restored on
  normal and error exit (§13.2).
- **Still open, critical:** the `PFINVERT` I.I/I.O bracket bug (needs a real
  `_INV.pro`); metric guard; PFSETUP Place-All flow. Tracked in `OPEN-ISSUES.md`.

Shipped prior cycle:

- **Pick-first labeling + PFINVERT's own dialog** — PFLABEL and PFINVERT now
  resolve the target through `pfs:choose-or-place` *before* the dialog opens
  (no target popup); PFINVERT moved to its own `pfi_run` definition (§4.2,
  §4.4). All heavy work runs before `new_dialog` (`rd-compute`), curing the
  ghost-dropdown freeze.
- **Drawn-centerline ("twin") membership pre-filter** — filed once at
  registration (`TWIN`, §7), read live; exact PIs replace the sampled corridor.
- **Firm-standard folder routing** — `.cl`/`.pro`/`.tin` picks and AUTO
  lookups route to standard project subfolders via `pfset:get-company-dir`
  (§8); the `[util]` label token replaces the hardcoded `STORM` in `sta_suf`.
- **`ZOOM _Window` everywhere** — `ZOOM _Center` miscomputes in this
  Carlson/Map build; all view changes route through `pfxl:zoom-corners` (§4.3).
- **`PFINVERT`** — invert labels at structures: primary I.I/I.O from the
  `_INV.pro` grade breaks, laterals from the registry, all text in one column
  below the lowest invert (§4.4). *Awaiting first live-drawing validation.*
- **Crossings table retired** — it only displayed what the ledger +
  reconciliation already track (§4.3); the command-line completion list is
  the surface now. Removing its `thandle` plumbing also fixed a latent
  wrong-arity `pfa:meta-put` call that would have crashed **every fresh
  anchor placement** (see §13.5).
- **Pre-shakedown hardening** — `pf:poly-x` cdr-walked (was effectively
  cubic); shared `pfa:undo-cleanup` so Esc can never leak an undo group,
  even from a nested on-the-fly placement; PFXLABEL restores the pre-run
  view on Esc; PFREMOVE gained the standard error handler.

Planned:

1. **`PFCHECK`** — record-integrity / status surface (checksums, copy
   detection, stale-crossing cleanup).
2. **Vertical-clearance QA** — both inverts are already read at every crossing;
   one subtraction turns the completion report into a clearance-conflict
   surface (or brings the table back as a QA-only view).
3. **Water-profile support** — appurtenances on laterals need lateral-aware
   membership, not the storm/sewer "structure on the line" test.
4. **Unified launcher** — one entry point routing between the flows (routing,
   not merged fields).
5. **Prefix/suffix parity** for crossing labels (currently hardcoded per-type
   templates).

---

## 13. Honest assessment — debt & native-feel gaps

A candid self-review (2026-07-19). The architecture — layering discipline,
the record model, the safety contract — is the strong half. The weaknesses
are all the same weakness: **designed by the engine, for the engine; the
drafter-facing skin was an afterthought.**

### 13.1 The UX is a text-mode menu wearing an AutoCAD costume
**(LARGELY RESOLVED — 2026-07-19 dialog rework)**

- ~~Numbered text menus everywhere~~ — **fixed**: `pfa:choose-anchor` and
  `pfs:choose-or-place` are `pf_pick` list dialogs; PFSETUP's
  `[All-unplaced/Edit/Refresh/New] <1-N>` REPL is the `pfsetup_registry`
  dialog; PFLABEL runs through `pf_run` and PFINVERT through its own `pfi_run`
  (both now **pick-first** — `pfs:choose-or-place` resolves the target, then
  the dialog lists that one target's structures; the target popup is gone);
  PFXLABEL's crossing pick is `pfxl_run`. The mixed
  `(initget 6 "All Target")(getint …)` idiom died with the menus.
  Command line keeps only screen picks; the datum moved into
  `pfsetup_main`; Yes/No confirms are `pf_confirm` (No = Enter = Esc).
- **PFXLABEL's Change Target is still a dead end** — it clears the session
  target and ends the run (rerun offers the picker). Native commands would
  re-open on the new target right there. *(Still open — needs a loop
  around discovery + dialog.)*
- ~~Dead tiles ship in the live dialog~~ — **fixed**: `con_pre` / `gl_pre`
  are greyed (`is_enabled = false`) pending the per-type editor.
- *(Deferred by choice)*: the "Screen Pick" hide-dialog button for
  plan-picking structures — waiting for a real dup-name case to force it.
- **The dialog layer itself has never opened in CAD** — layout findings
  (tile widths, proportional-font column drift in the list "grids") are
  expected on first contact; see `TESTING.md` 0.4.

### 13.2 `CMDECHO` suppression — **RESOLVED (2026-07-21)**

~~Not one command sets `CMDECHO 0`.~~ Shared `pf:echo-off` / `pf:echo-on`
(pftools-lib) save the user's `CMDECHO` and zero it for the run. Every
command's prologue calls `echo-off`; every normal epilogue calls `echo-on`;
`pfa:undo-cleanup` restores it on the error path (so Esc can't leave echo off).
The UNDO/`ZOOM`/`DELAY` chatter is gone. (The ×5 error/undo scaffolding of
§13.4 is still un-shared — but CMDECHO no longer needs to be part of that
eventual `pf:run-command` wrapper.)

### 13.3 Performance smells (will surface on real drawings)

- **`pfa:find-anchor` is a full-database `ssget "_X"` + attribute read of
  every anchor — and `pfxl:src-files` calls it per crossing.** An All-mode
  pass over 20 crossings does 20+ full scans; PFSETUP's AUTO loop repeats
  the pattern per sheet name. The registry should be scanned **once per
  command** and passed down — exactly the discipline `pf:top-lines` already
  enforces for the top probe. *(Still open.)*
- ~~`pf:poly-x` walks vertices with `nth`~~ — **fixed**: cdr-walked, same
  scan order and first-hit result, ~1000× fewer operations on sampled
  alignments.

### 13.4 Duplicated scaffolding

Five commands carry near-identical `*error*` handler + undo-open global +
save/restore ceremony (`pflabel:` / `pfxl:` / `pfs:` / `pfinvert:` /
`pfrem:*error*`). The undo-close half is now shared (`pfa:undo-cleanup`
closes ANY open pf group, fixing the nested-placement leak), but the
handler/install/restore scaffolding is still ×5. One shared
`pf:run-command` wrapper (installs handler, opens undo, sets CMDECHO,
guarantees cleanup) collapses it and gives a single place to fix UX for
every command at once. **Highest-leverage refactor in the codebase.**

### 13.5 Validation debt — the actual biggest risk

The near-100% validation the roadmap cites belongs to **v3's composition
engine**. V4's registry flow — PFSETUP, the anchor path, the PFXLABEL
rewrite, PFINVERT, the zoom-pause — has grown far faster than the validated
surface. Code this careful will *mostly* work, but "mostly" in a tool that
erases entities by handle deserves a deliberate **shakedown session on a
scratch drawing**: scripted SETUP → LABEL → XLABEL → INVERT → REMOVE → `U`
before it touches a real job. (`TESTING.md` is that checklist.)

Proof this risk is real: a wrong-arity `pfa:meta-put` call sat in
`pfa:write-anchor` — **every fresh anchor placement would have crashed on
first contact**. It was written, code-reviewed, and pushed; static review
missed it in a 6,600-line diff, and only the table-removal refactor
surfaced it. Static verification is not validation.

### 13.6 Small corrections

- `pf:get-verts` / `pf:sample-cl` were kept as "reserved for PFINVERT" — but
  PFINVERT as built samples the `.pro` (elevation), not the `.cl` (plan).
  The reservation is stale; they are dead unless something else wants
  plan-vertex sampling.
- `pfs:pick-extents` takes raw `getpoint` clicks against a loose 0.5
  tolerance while fighting running osnaps. The native move is to *exploit*
  osnap — force `_int` so the pick snaps to the actual grid corner: tighter
  data and more native feel at once.
- The anchor's visible attributes (fixed 0.8 height, absolute placement)
  look wrong at other plot scales and invite the ATTSYNC accident §11 warns
  about. The block stays visible (settled); the *attributes* could be
  invisible (ATTDEF flag bit 1) with PFCHECK surfacing the values instead.

### 13.7 The next three sessions, if debt led

1. **`pf:run-command` wrapper** — CMDECHO + error + undo in one place
   (fixes 13.2 + 13.4).
2. **The scheduled dialog-rework session, expanded** — PFSETUP-as-dialog and
   every numbered text menu killed (fixes 13.1).
3. **Shakedown protocol** on a scratch drawing (fixes 13.5).

> The engine deserves the polish. Today it is a precision instrument with a
> command-line interface from 1994 bolted on — and the instrument is good
> enough that the bolt-ons are what people will judge it by.



Notes:

Future dialog run PFT (working name) dialog gives you choices of each main command.
Format achor block style and output
Dialog/Docked "Propoerties" style modeless window ala road network command.
Structure block with pflabel
~~Ask Andy about folder setting (then we can lose pfroot)~~ — DONE 2026-07-21: went native on Carlson `tmpdir$`; PFROOT retired. (Firm subfolder map in cfg still wants Andy's confirmation.)
Workflow/prompts for initial registration and un registered profiles.
PFINVERT and PFCHECK
