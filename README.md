# PFTools V5 — Bryant Engineering Profile Suite palette

An OpenDCL dockable palette front-end for the PFTools suite. **V5 is
palette-centric: the palette is becoming the single surface for calling
everything.** This folder (renamed `Profile-Labeling-5-Palette` → `pfsuite`,
2026-07-26) is a self-contained fork of V4 with the label commands' engines
extracted; V4 one level up (`..\..\V4`) is the frozen original and is never
touched. The modal dialogs still work and stay working until the palette
provably replaces each one — then they are demoted to fallbacks (for a session
without OpenDCL), not deleted.

---

## 1. Status (2026-07-26)

| | |
|---|---|
| `pfsuite.odcl` | Renamed from `pfsetup.odcl`; path prefix is `pfsuite/`. Registry tab laid out. Commands and Settings tabs empty. |
| LISP wiring | `pfpalette.lsp` loaded last by the loader. `C:PFPALETTE` toggle, `OnInitialize` (columns only), `pfp:refresh` (data fill), tree/meta/linkage selection handlers. |
| Run in CAD | **Yes — milestones 1 and 2 field-tested.** It docks, and the read-only data path populates. The one field failure (tree/labels empty until the palette was moved) was the deferred-paint trap: `OnInitialize` fires before the window is realized. Fixed structurally — see §4a. |
| Engines | `pflabel:run` / `pfi:run` / `pfxl:run` extracted (REFACTOR-PLAN step 1). Called only by their own `C:PF*` so far — no deferred fire yet. |
| Audit | 2026-07-26 full audit; the "Option A" fix batch is applied (§9). |

---

## 2. Structure

### File layout (2026-07-26 restructure: one folder per .lsp)

Every `.lsp` lives in its own subfolder with its own `README.md` beside it —
the narrative contract (load position, dependencies, public API, invariants,
local issues) lives in that README; the `.lsp` header is a pointer. One home
per fact.

```
pfsuite/
├── pftools-load.lsp     ← the entry point (STAYS AT ROOT; *pftools-dir* = this root)
├── pfdialog.dcl         ← shared asset, root (path = *pftools-dir* + name)
├── pfsuite.odcl         ← shared asset, root (same reason)
├── README.md  OPEN-ISSUES.md  TESTING.md  REFACTOR-PLAN.md  …
├── pftools-cfg/   pftools-cfg.lsp  + README.md      1  constants
├── pftools-lib/   pftools-lib.lsp  + README.md      2  pure engine
├── pfdraw/        pfdraw.lsp       + README.md      3  drawing boundary
├── pfanchor/      pfanchor.lsp     + README.md      4  record + registry + pf:run-command
├── pfsettings/    pfsettings.lsp   + README.md      5  user state + shared dialogs
├── pfsetup/       pfsetup.lsp      + README.md      6  C:PFSETUP
├── pflabel/       pflabel.lsp      + README.md      7  C:PFLABEL
├── pfxlabel/      pfxlabel.lsp     + README.md      8  C:PFXLABEL
├── pfinvert/      pfinvert.lsp     + README.md      9  C:PFINVERT
├── pfreport/      pfreport.lsp     + README.md     10  C:PFREPORT
└── pfpalette/     pfpalette.lsp    + README.md     11  C:PFPALETTE
```

Load order: cfg → lib → draw → anchor → settings → setup → label → xlabel →
invert → **report** → palette; a file may only depend on files that load
before it.

**`pfreport` (2026-07-26, untested in CAD)** is the first command that is
SYSTEM-scoped rather than target-scoped, and the first that is read-only on
the drawing: it multi-selects registered profiles and writes a Hydraflow
Storm Sewers `.stm` — a populated hydraulic model, not a plan-view import.
It has no anchor pick, no undo group and no pass ledger. Details and the CAD
gates are in [pfreport/README.md](pfreport/README.md).

### Palette (.odcl) structure

```
pfsuite.odcl                     project  → first path segment
└── pfsPalette        Palette    the docked window; caption is the title
    ├── Tab 1  "Registry"
    ├── Tab 2  "Commands"
    └── Tab 3  "Settings"
```

Control paths are always three segments — `pfsuite/pfsPalette/tvwLines`. There
is no tab segment even though controls belong to tabs; Studio tracks tab
membership internally and the runtime shows and hides them for you.

### Registry tab (built, wired, tested read-only)

| Control | Type | Purpose |
|---|---|---|
| `tvwLines` | TreeView | Two levels, utility Type → Line. The only control that stretches. |
| `metaList` | ListView, Report | `Property` \| `Value` grid for the selected line. |
| `lvwLinkage` | ListView, Report | `Item` \| `File` — five fixed rows, one per binding. |
| `lblProject` / `lblCounts` | Label | Project root + registry tallies, seeded by `pfp:seed-labels`. Form-level, outside `tabMain`. |
| `btnPickCL` … `btnPickDESIGN` | Button ×5 | File pickers, one row. **Not wired** (milestone 3). |
| `btnAnchor` `btnEdit` `btnNew` `btnRemove` `btnZoom` | Button ×5 | Registry verbs, one row. **Not wired** (milestone 3). |
| `btnRefresh` `btnHelp` | Button ×2 | Form-level, bottom, visible on all tabs. **Not wired**; Refresh will call `pfp:refresh`. |
| `tabMain` | TabStrip | Spans the content region. |

### Commands tab (not built)

Decided 2026-07-24. The tab **replaces the modal run dialogs** (`pf_run`,
`pfi_run`, `pfxl_run`) for all three label commands — it does not launch them.
Top to bottom:

| Region | Control | Notes |
|---|---|---|
| Target | TreeView, Type → Line | Same shape as Tab 1's tree, single-select, seeded from the Tab 1 selection but independently changeable. **Capped height**, not a stretcher. |
| Pass | horizontal radio | `Structures` (PFLABEL) / `Inverts` (PFINVERT) / `Crossings` (PFXLABEL). |
| Items | multi-select ListView, Report | The items on the target, with a labeled/outstanding **Status** column. **The stretcher.** Reshapes for Crossings to `Source \| Target Sta \| Source Sta \| Status`. |
| Options | checkbox band | Per-command optional aspects; contents swap with the radio. Fixed reserved band. Confirmed members so far: **"Zoom To"** (the verification parade, §6b) and **"allow relabeling"** (Crossings — replaces the mid-run `pfset:confirm`). Rest TBD (Jake). |
| Verbs | Button row | `Label Selected`, `Label All` / `Label Outstanding`, `Zoom To`. |
| Native | Button row | Native Carlson profile commands (list TBD). Pure launchers — Carlson's own dialog takes over. |

The Status column's data source already exists in every gather-compute
(pflabel's `[LABELED]` mark, pfinvert's `id-status`, pfxlabel's `recon`) — all
reads, all modeless-safe.

**Prove the deferred fire first.** A modeless handler cannot call `command`,
so both our verbs and the Carlson buttons must queue the real command into a
command context. That mechanism gets its own small CAD proof *before* the tab
is built — it is the one piece that can't be reasoned out from the samples.

### Settings tab (not built)

Contents of `pflabel_settings` (prefix/suffix grid, layer, style) plus
suite-level settings (plot scales, per-type materials, std search folders, base
text height). **`Apply` / `Reset` inside this tab only** — it is the one surface
with pending state. No OK/Cancel anywhere on a palette (§5).

---

## 3. Running it

### Prerequisites

OpenDCL Runtime, already installed at
`C:\Program Files (x86)\Common Files\OpenDCL` (`.arx` per AutoCAD release).
Studio is at `C:\Program Files (x86)\OpenDCL Studio`.

### Loading the suite

Set `*pftools-dir*` in `pftools-load.lsp` to THIS folder (forward slashes,
trailing slash — still hardcoded, the known open issue), then `(load)` that
file. It loads the whole suite in dependency order and `pfpalette.lsp` last.
`PFPALETTE` toggles the palette: show if down, close if up.

The `.odcl` and `pfdialog.dcl` paths both derive from `*pftools-dir*` — never
hardcode a second copy.

### API spellings

The shipped samples use hyphens (`dcl-Project-Load`, `dcl-ListView-AddColumns`);
older forum code uses underscores. Both work. This suite uses hyphens.

Event handlers are named by path:

```lisp
(defun c:pfsuite/pfsPalette#OnInitialize ()            ...)
(defun c:pfsuite/pfsPalette/tvwLines#OnSelChanged (Label Key) ...)
```

Working examples ship with Studio in `ENU\Samples\` — `Methods.lsp` for the
TabStrip, `ListView.lsp` and `AllControls.lsp` for ListView columns, `Tree.lsp`
for the TreeView, `Modeless.lsp` for modeless lifecycle.

---

## 4. ListView columns are runtime, not design-time

There is no column editor in Studio. Columns are added in code, once, in
`OnInitialize`. `AddColumns` is **additive** — calling it from a refresh
routine stacks duplicate columns. A blank ListView in the designer is
expected, not broken.

### 4a. Populate AFTER the window exists (field-tested lesson)

`OnInitialize` fires **before the palette window is realized**. Data written
to controls there does not paint — the field symptom was a tree and labels
that stayed empty until the palette was moved or resized. The split that fixes
it, and the rule for all future tabs:

- **`OnInitialize` = columns only** (they must be added exactly once).
- **`pfp:refresh` = all data fill** (registry scan → labels + tree), called by
  `C:PFPALETTE` *after* `dcl-Form-Show` returns.

`pfp:refresh` is also the single entry point for the three refresh signals to
come (§5): `OnDocActivated`, the `:vlr-commandEnded` reactor filtered to `PF*`
names, and `btnRefresh`. Never poll.

---

## 5. OpenDCL constraints that shape the design

**Modeless.** Palette handlers run outside a command context. No `entsel`, no
`getpoint`, no `command`, no undo group. Two categories, never conflated:

| | Runs where | Palette calls it? |
|---|---|---|
| **Reads** — registry scan, ledger reads, gather-compute, Status | modeless handler | Directly — same functions the commands use. Requires them to be *provably write-free* (see the contract below). |
| **Verbs** — Place, Edit, New, Remove, Label | command context only | Never directly. Deferred-fire the `C:PF*` command. |

**The read/write contract (enforced 2026-07-26).** Anything a modeless
handler can reach must not write the drawing — not even "harmlessly":

- `pfa:nod-dict` takes a `create` flag; every read path passes nil, so a
  registry scan on a clean drawing creates nothing (same contract as
  `pfa:ledger-dict`).
- `pf:cl-geom` takes a `write-p` flag; gather paths pass nil (a cache miss
  re-samples, never files). Only PFSETUP registration and PFXLABEL discovery
  — both inside command undo groups — pass T.
- `pflabel:build-lines` is write-free: a re-matched twin is used for the run
  but not filed.

**No OK/Apply/Cancel.** A docked palette never closes and has no commit moment.
Palette buttons are immediate verbs. Settings is the sole exception and gets
`Apply` / `Reset`.

**No layout flow.** Controls never push each other; they overlap freely. Every
edge is a number you set.

**Anchoring is two flags per axis** and the mixed pair is always wrong:

| Behavior | `Use…FromRight` / `Use…FromBottom` pair |
|---|---|
| Fixed size, pinned left/top | `0 / 0` |
| Fixed size, pinned right/bottom | `1 / 1` |
| Stretches with the form | `0 / 1` |

**Set `Min Width` / `Min Height` on the form.** Below the floor, bottom-anchored
controls compute negative coordinates and vanish off the top of the canvas.
This is correct behavior, not a bug — the floor is the fix.

**Record writes from a modeless context** (the file pickers, milestone 3) must
be gated on `(getvar "CMDACTIVE")` = 0, wrapped in an explicit undo mark, and
the palette disabled while a command runs.

---

## 6. The paths into the commands

**(a) Pre-target — small, NOT YET IMPLEMENTED.** All three label commands are
pick-first: they call `pfs:choose-or-place` (`pfsetup.lsp`), which opens the
`pf_pick` modal. A global consumed-and-cleared at the top of that function
(`*pf-preset-target*`) would let the palette name the target without the pick.
Still wanted for the Registry tab's `Zoom To` and any path that lets a modal
open; superseded for Tab 2 by (b).

**(b) The order ticket + headless run path — the real work (Tab 2).** Each
command already splits gather → engine at one alist:

```
rd = ( (mode . "All"|"Sel") (sel . <items>) (lines . <…>) (inlets . <…>)
       (zoom . T|nil) … per-command options … )
```

The modal produces it today; Tab 2 assembles the identical alist and
deferred-fires a thin `C:PF*RUN` that reads it and calls `pfX:run` inside a
real command context. **Options ride IN the ticket** — decided 2026-07-26 for
the "Zoom To" checkbox and the pattern for every option after it. One-shot
globals (`*pf-zoom-to*` still exists as a transitional channel) are fragile
once commands are queued; the ticket is not. PFXLABEL's equivalent is the
`act`/`sel` out of its dialog plus `work` + `recon`.

Engine status: extracted and paren-verified (`pflabel:run`, `pfi:run`,
`pfxl:run`), byte-identical bodies, **regression gate not yet run** — all
three commands must produce identical output from the command line before any
palette wiring (REFACTOR-PLAN).

---

## 7. Milestones

1. ~~**Prove it loads.**~~ **DONE** — docks, resizes, Min floor holds.
2. ~~**Read-only data path.**~~ **DONE** — columns in `OnInitialize`;
   `pfp:refresh` fills tree/labels; selection fills `metaList` + `lvwLinkage`.
   Deferred-paint fix (§4a) landed after field test.
3. **Registry verbs.** The `*pf-preset-target*` graft (§6a), deferred command
   firing, the three refresh signals into `pfp:refresh`, then the file pickers
   with their `CMDACTIVE` guard. Demote `pfs:registry-dialog` to a fallback
   once these work.
4. **Tab 2 (Commands) — the heaviest lift.** First the CAD regression gate on
   the extracted engines, then prove the deferred fire in isolation, then the
   headless path, target tree + radio + item list + Status, the checkbox band,
   the native Carlson row. Options list and Carlson command list TBD (Jake).
5. **Tab 3 (Settings).** `pflabel_settings` contents plus suite-level settings,
   `Apply` / `Reset` local to the tab.

---

## 8. Open

- `*pftools-dir*` is still a hardcoded absolute path in `pftools-load.lsp`.
- Buttons vanished during one resize test with anchoring provably identical to
  buttons that survived. Unresolved — check whether they return on a form
  close/reopen (z-order/repaint) or stay gone (geometry). May be the same
  deferred-paint class as §4a; re-test after that fix.
- Status pane in the Registry tab is **deliberately deferred** — PFCHECK is not
  built, so there is no data to put in it.
- Palette persists across drawings (per-session) while the registry is
  per-drawing. `OnDocActivated` → `pfp:refresh` (milestone 3) is the answer;
  until then, stale data after a drawing switch is expected.
- ~~**Planned restructure (after Option A, before Tab 2).**~~ **DONE
  2026-07-26 (pending CAD verification):** one folder per `.lsp` with its
  README beside it (§2), loader paths updated; the shared `pf:run-command`
  wrapper + per-command Esc ledger flush (audit #9) and the registry-builder
  consolidation (`pfa:entry-cl` + `pflabel:registry-pairs` as the one
  builder, audit #12) landed with it. CAD gates outstanding: load + smoke
  (PFPALETTE populates, PFLABEL reaches its run dialog), the Esc-flush test
  (TESTING.md 8.9), and the builder-parity test (OPEN-ISSUES).

---

## 9. Applied 2026-07-26 (the "Option A" audit batch)

Behavioral contracts changed by the fix batch — what a tester should know:

- **Arity changes:** `pf:cl-geom (clfile write-p)`, `pfa:nod-dict (create)`,
  `pf:zoom-begin (sf)`, `pfset:nod (create)`. All call sites updated.
- **Gather paths are write-free** (§5 contract). Consequence: on a drawing
  whose GEOM/TWIN records were never filed, label runs re-sample the `.cl`
  each run until PFSETUP or discovery files them — slightly slower first runs
  on old drawings, zero silent writes.
- **`pfs:auto` writes inside one undo group** — a single `U` peels an entire
  AUTO registration; Esc mid-scan is cleaned up by the error path.
- **PF-NAME text with an unreadable line name is reported**
  (`SKIPPED, NOT REGISTERED: "<text>"`), never silently dropped — backtick
  names are now loud. The straight-quote convention stands.
- **All 9 whole-database `ssget "_X"` scans are model-space only**
  (`(410 . "Model")`).
- **`distof` mode 2 pinned** on the PFSETUP dialog's numeric tiles (works in
  Architectural/Fractional drawings).
- **Zoom parade:** one frame rule for all three commands (grid base↔top,
  extended by whatever was drawn beyond them, with a `*pf-zoom-min-height*`
  floor); `pf:zoom-resolve` runs inside the ctx guard; the error-path restore
  is CMDACTIVE-gated, echo-silent, and catch-wrapped.
- **Inert cfg tunables are labeled `[INERT]`** in `pftools-cfg.lsp` — the
  vertex-band/misalign/grid-cell knobs do nothing until the segment-membership
  fix is wired. Do not tune them chasing a missing structure.

Deferred by agreement: rule-token matching (waits on the block-library/rules
storage decision), the Zoom-To checkbox wiring (Tab 2), and the LOW-severity
hygiene list (separate session). ~~The Esc-orphan ledger flush and the
registry-builder consolidation~~ landed 2026-07-26 with the restructure
(§8, OPEN-ISSUES) — fixed pending CAD.

---

## 10. Known-open command bugs (unchanged by the palette work)

- **[wrong-output, CRITICAL] PFLABEL silently drops structures** near
  deflection PIs — `cl_location_at_pt` returns nil where no perpendicular
  foot exists. Root-caused; fix is the segment-distance membership the
  `[INERT]` knobs belong to. Full detail in `OPEN-ISSUES.md`.
- Several 2026-07-21 fixes are still tagged **untested in CAD** — the V5 fork
  regression gate (§6b) is the vehicle for closing them.
