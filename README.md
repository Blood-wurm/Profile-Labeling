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
- **A per-profile crossings table** that doubles as a completion record.

The shift in V4: a profile's grid and crossings become **drawing-resident
state**. Register a grid once; every command afterward reads it, and the
drawing itself remembers what's been labeled and what's left.

## 2. The V4 pivots (what changed from v3)

| Area | v3 | V4 |
|---|---|---|
| **Registration** | Grid re-picked every run | **Register once** (an *anchor block*), every command reads it |
| **Two tiers** | — | **AUTO** names every profile on the sheet (stubs); **USER** places each grid (anchors) |
| **Crossing inverts** | Vertical **bore probe** of the drawn grid | **Read from the source `.pro`** via the Road API (`profile z`) — the probe is *dead* |
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
| `PFROOT` | — | `pfsettings.lsp` | Show / set the drawing's project-data-root folder. |
| `PFCHECK` | — | *(planned)* | Record-integrity check. Announced by the loader, not yet built. |

### 4.1 `PFSETUP` — two-tier registration

Registration splits in two. **Identity is enough to discover; placement is
required only to draw.**

**AUTO (identity, sheet-wide, never guesses)** — fires automatically the first
time a drawing has no registry:

```
pfs:auto
 ├─ pfs:scan-sheet-names      scan PF-NAME text  → (type . name) pairs
 ├─ pfs:cl-lookup             resolve Type_Name.cl in the project root
 ├─ pfs:pro-lookup            auto-bind the _INV / _TOP .pro pair
 └─ pfa:stub-put              write an identity-only STUB to the NOD dict
```

No matching `.cl`, an ambiguous match, or a `.cl` with no sheet name is
**reported and skipped** — never guessed. The reverse direction (a `.cl` with
no grid name on the sheet) is noted too.

**USER (placement)** — promotes a stub to an anchor, per grid:

```
pfs:place-one
 ├─ pfs:show-dialog           identity override, scales, .cl/.pro/.tin, material
 ├─ pfs:pick-extents          pick LOWER-LEFT (datum line) then TOP-RIGHT (extents)
 ├─ pfs:ask-datum             type the datum elevation (the one value a pick can't give)
 ├─ pfs:build-xform → pfa:write-anchor    write the PF-GRIDANCHOR block
 ├─ pfa:meta-put / pfs:bind-files         .cl + .pro/.tin bindings + checksums
 └─ pfa:stub-del              delete the promoted stub
```

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

The V4 run collapses to: `PFLABEL` → pick the anchor → `[All/Pick]` → run.
Everything the old dialogs gathered lives in the anchor record.

- **Secondary `.cl` set = the registry** (anchors *and* stubs). Membership is
  plan-view station math, so **identity alone qualifies a line** — the moment
  AUTO names the sheet, every junction's combined ID (`AA-1/BB-2`) is complete,
  placed or not. This closes v3's silently-shorter-ID gap.
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
 │    ├─ pf:cl-verts / pf:poly-x        sampled-walk plan intersection (arcs followed)
 │    ├─ pf:refine-x                    re-sample ~0.1 ft near a hit
 │    ├─ pf:sta-at                      read both stations off the Road API
 │    └─ pfa:xing-merge                 additive merge into the ledger (elevations preserved)
 ├─ pfa:xing-list / pfa:recon           working list + per-crossing LABELED/OUTSTANDING
 ├─ pfxl:print                          numbered list + status
 ├─ [pick] All / <1-N> / Target
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
- **All** mode labels only **OUTSTANDING** crossings; single-pick warns before
  it would draw duplicates.
- A source that isn't registered, has no INV `.pro` bound, or whose invert is
  unreadable is **skipped and reported** — on the command line *and* in the
  table's STATUS column.
- After the pass, `pfa:rebuild-table` regenerates the crossings table (replaced
  by handle). The whole pass is one undo group.
- **Verification zoom** (`*pfx-zoom-pause*`): each drawn crossing is framed
  and paused on (`ZOOM Center` + `DELAY`), then the pre-run view is restored
  after the pass. Set the pause to `0` to disable.

### 4.4 `PFINVERT` — invert labels at structures

**The command split: `PFLABEL` owns top-of-grid text; `PFINVERT` owns
everything at pipe elevation.** Same anchor-driven run shape:
`PFINVERT` → pick the anchor → `[All/Pick]` → run. The `_INV.pro` binding is
**fatal** when missing — every elevation comes from it.

```
c:PFINVERT
 ├─ pfi:setup                  anchor record + registry line table (pflabel's walk)
 └─ pfi:process-structure  (per structure on the primary)
      ├─ pfi:invert-bracket        I.I/I.O at the .pro GRADE BREAKS each side
      ├─ pfi:lateral-info          each other line here: registry .pro → invert + size
      ├─ pfd:draw-label-stack 'MR  the invert COLUMN (hangs below base Y)
      └─ pfd:insert-pipe           bare lateral pipe block at TRUE elevation
```

- **Primary = text only** (`I.I <elev>` / `I.O <elev>`) — its pipe is already
  the `.pro` linework on the grid. **Laterals = bare block at true elevation
  + bare `I.I <elev>` row** (non-present pipes; line identity is already on
  the structure's top label). No leader line.
- **Grade-break bracket, not a fixed offset:** walking the `_INV.pro` outward
  from the station, the first grade break each side is the structure edge —
  the bracket **auto-widens with structure size**. The *lower* invert of the
  pair is downstream (self-determining) → `I.O`. A flat run (no drop) reads
  the station itself; both rows still drawn.
- **The column rule (collision-proof):** all text rows share **one base Y** =
  lowest invert present − `*pfi-invert-offset*` (fixed model units, **not**
  scaled by `sf`), fanning left/right across the station X by the same
  straddle rule as the top stack. Columns, not true-elevation rows — a 0.10'
  drop can never overlap two callouts. Blocks sit at true elevation and may
  stack; text never does.
- **Layer / pass / undo — identical to `PFLABEL`:** derived `<TYPE>-TEXT_P`
  handle-tracked (PASS `INVERT`, `All` replaces by handle) vs the
  *"Use current layer"* toggle (PASS `INVERT-CLAYER`, fire-and-forget).
  STATUS is written after the pass from the `_INV.pro` checksum.

### 4.5 `PFREMOVE` — teardown

```
pfa:teardown
 ├─ pfa:erase-pass (per PASS_*)   erase every handle-tracked entity, by handle
 ├─ erase table instance (by handle) + block definition
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
      │              (ext-dict), reconciliation, crossings table.  C:PFREMOVE
      │
pfsettings.lsp     ← User state: settings file, session dirs, NOD (project root),
      │              shared dialog pickers, layer/style lookups.  C:PFROOT
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

> `pfdialog.dcl` is still live — it holds `pfsetup_main`, `pflabel_settings`,
> and the shared `pf_pick` / `pf_name` / `pf_scan` dialogs.

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
| 1 | **Project root** | `pfsettings.lsp`: `pfset:root-set` (first `PFSETUP` or `PFROOT`) writes it to the NOD | — |
| 2 | **AUTO register** | `pfsetup.lsp`: `pfs:auto` → `pfs:scan-sheet-names`, `pfs:cl-lookup`, `pfs:pro-lookup` → `pfanchor.lsp`: `pfa:stub-put` | Road `cl_sta_range` (validate ranges) |
| 3 | **USER place** | `pfsetup.lsp`: `pfs:place-one` → `pfs:show-dialog`, `pfs:pick-extents`, `pfs:ask-datum` → `pfanchor.lsp`: `pfa:write-anchor`, `pfa:files-put`, `pfa:stub-del` | Road `cl_sta_range` |
| 4 | **Structure labels** | `pflabel.lsp`: `c:PFLABEL` → `pflabel:setup` (`pfa:anchor->xform`, `pflabel:registry-pairs`, `pflabel:build-lines`, `pflabel:gather-inlets`) → `pflabel:process-structure` → `pfdraw.lsp`: `pfd:draw-label-stack`, `pfd:station-line` → `pflabel:write-pass` (`pfa:pass-put`, `pfa:status-put`) | Road `cl_location_at_pt` (membership), top-of-grid probe (`inters`, no API) |
| 5 | **Crossings** | `pfxlabel.lsp`: `c:PFXLABEL` → `pfxl:discover` (`pf:cl-verts`, `pf:poly-x`, `pf:refine-x`, `pf:sta-at`, `pfa:xing-merge`) → `pfxl:label-one` (`pf:pipe-at`, `pf:top-at`) → `pfdraw.lsp`: `pfd:insert-pipe`, `pfd:label-pipe` → `pfa:rebuild-table` | Road `cl_location_at_sta` (walk), `cl_location_at_pt` (station), **`profile z`** (invert/top) |
| 6 | **Inverts** | `pfinvert.lsp`: `c:PFINVERT` → `pfi:setup` (pflabel's line table + inlets) → `pfi:process-structure` (`pfi:invert-bracket`, `pfi:lateral-info`) → `pfdraw.lsp`: `pfd:draw-label-stack 'MR`, `pfd:insert-pipe` → `pfi:write-pass` | Road `cl_location_at_pt` (membership), **`profile z`** (bracket walk + laterals) |
| 7 | **Re-run** | Same commands; `All` mode replaces prior passes **by handle**; discovery short-circuits unchanged `.cl` pairs | Road (unchanged pairs skipped) |
| 8 | **Teardown** | `pfanchor.lsp`: `c:PFREMOVE` → `pfa:teardown` (`pfa:erase-pass`, `entdel`) | — |

Per-file responsibility during a run:

| File | Role in the workflow | Writes to drawing? |
|---|---|---|
| `pftools-cfg.lsp` | Supplies every tunable read by the rest | no |
| `pftools-lib.lsp` | All math, geometry, membership, `.cl`/`.pro` reads, probe, composition | no (read-only queries only) |
| `pfdraw.lsp` | Entmakes labels/pipes/lines/table rows; returns enames | **yes** (creates only, never erases) |
| `pfanchor.lsp` | Anchor + stub + ledger + table; erase-by-handle; reconciliation | **yes** |
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

ANCHOR  (PF-GRIDANCHOR block, one per PLACED profile)
        Insertion point = grid lower-left (datum + origin). Extents RELATIVE
        (X-scale = width, Y-scale = height to the top-right pick).
        Attributes: LINE / UTIL / STA0 / DATUM / HPLOT / VPLOT.

LEDGER  (ext-dict "PFXLEDGER", hard-owned by the anchor — schema 3)
        META    (1 .cl)(300 table handle)(301 .cl checksum)(302 self-handle → copy detect)
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

The whole registry rides on filename convention in the project data root:

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

---

## 9. Layer conventions

| Layer | Owner | Behavior |
|---|---|---|
| `PF-GRID-MJR` | Carlson | The **top-of-grid probe** layer (highest hit = top). Also the AUTO scan's neighbor. |
| `PF-GRID-MNR`, `PF-HBOX` | Carlson | Grid frame; used by the anchor corner sanity probe. |
| `PF-NAME` | Carlson | Grid identity text — AUTO reads it. |
| `PF-ANCHOR` | tool | `PF-GRIDANCHOR` blocks. Created **no-plot**, visible in model space. |
| `PF-XING` | tool | Crossing station lines — the layer reconciliation scans (by handle for erase). |
| `PF-XING-TEXT` | tool | Vertical crossing station text. |
| `PF-TEMP` | tool | Reserved (legacy invert-tick concept). As built, `PFINVERT` is handle-tracked on `<TYPE>-TEXT_P` instead. |
| `PF-TABLE` | tool | Crossings-table blocks. Erased **by handle only**, never layer-cleared. |
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
  near a hit.
- **Pipe rendering** — `PF-PIPE_<NN>` block family; circle placeholder when a
  block is missing; `*pfx-zoom-pause*` verification pause (0 disables).
- **Invert bracket (`PFINVERT`)** — `*pfi-invert-offset*` 5.0 (fixed, un-scaled
  column drop), `*pfi-scan-window*` 25 ft, `*pfi-scan-step*` 0.5 ft,
  `*pfi-grade-tol*` 0.05 Δslope (what reads as a structure edge).

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
- **`PFCHECK` is announced by the loader but not built yet.**

---

## 12. Status & roadmap

**Structure + crossing labeling** carries forward v3's near-100% validation
against a completed job; the V4 rewrite moves inverts onto authored `.pro`
files (the fragile bore probe is retired) and makes the grid a registered,
drawing-resident record.

Shipped this cycle:

- **`PFINVERT`** — invert labels at structures: primary I.I/I.O from the
  `_INV.pro` grade breaks, laterals from the registry, all text in one column
  below the lowest invert (§4.4). *Awaiting first live-drawing validation.*

Planned:

1. **`PFCHECK`** — record-integrity / status surface (checksums, copy
   detection, stale-crossing cleanup).
2. **Vertical-clearance QA** — both inverts are already read at every crossing;
   one subtraction turns the crossings table into a clearance-conflict surface.
3. **Water-profile support** — appurtenances on laterals need lateral-aware
   membership, not the storm/sewer "structure on the line" test.
4. **Unified launcher** — one entry point routing between the flows (routing,
   not merged fields).
5. **Prefix/suffix parity** for crossing labels (currently hardcoded per-type
   templates).



Notes:

Future dialog run PFT (working name) dialog gives you choices of each main command.
Format achor block style and output
Structure block with pflabel
Ask Andy about folder setting (then we can lose pfroot)
Workflow/prompts for initial registration and un registered profiles.
PFINVERT and PFCHECK
