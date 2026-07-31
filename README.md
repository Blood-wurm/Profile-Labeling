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

## 1. Status (2026-07-29)

> **The Commands tab fires.** `PFPRUN` labelled two structures on `BB` from the
> palette — ticket → `pfp:defer` → `pf:run-command` → `pflabel:run`, one undo
> group, `Status: PASSING`. That closes milestone 4 and makes the palette the
> first surface that can *run* a pass, not just read one.
>
> Getting there cost eight CAD round trips, almost all on OpenDCL control
> wiring rather than on the suite. Every fact bought is written down in
> [`pfsuite-odcl/OPENDCL-WIRING.md`](pfsuite-odcl/OPENDCL-WIRING.md) — read it
> before wiring the Settings tab, or it will cost the same again.
>
> Still open on the tab: `optTools` greyed (no Carlson command names),
> `Label Selected` refused by design, and **Crossings and Inverts have not been
> fired from the palette yet** — only Structures has.

### Status as of 2026-07-27

| | |
|---|---|
| `pfsuite.odcl` | Renamed from `pfsetup.odcl`; path prefix is `pfsuite/`. Registry tab laid out. Commands and Settings tabs empty. |
| LISP wiring | `pfpalette.lsp` loaded last by the loader. `C:PFPALETTE` toggle, `C:PFPRELOAD`, `OnInitialize` (columns only), `pfp:refresh` (data fill), tree/meta/linkage selection handlers, the `pfp:defer` channel, and the §6 diagnostics. |
| Run in CAD | **Yes — milestone 2 shaken down 2026-07-27.** Tree paints immediately, columns survive repeat toggles, footer labels populate, metaList fits without scrolling. |
| **Gate: deferred fire** | ✅ **PASSED 2026-07-27.** `getpoint` prompted and returned from a palette-queued command, one `U` peeled the work, and the gate refused against a live `PLINE`. `pfp:cmd-idle-p` + `pfp:defer` now live in `pfpalette.lsp` §2. |
| **Gate: write-free** | ✅ **PASSED 2026-07-27.** Clean drawing 29→29, populated 21→21 (`PFPDBMOD` delta). §5's contract is verified in CAD, not just by inspection. |
| Engines | `pflabel:run` / `pfi:run` / `pfxl:run` extracted (REFACTOR-PLAN step 1). Called only by their own `C:PF*` so far — no deferred fire yet. |
| Audit | 2026-07-26 full audit; the "Option A" fix batch is applied (§9). |

**Both gates that blocked Phases 2–4 are open.** Remaining before Phase 2 is
Studio geometry (`tvwLines` anchoring) and the CAD regression gate on the
extracted engines. Full results: [`pfsuite-odcl/PALETTE-TESTING.md`](pfsuite-odcl/PALETTE-TESTING.md) §6.

> ### ⚠ After any Studio save, run `PFPRELOAD`
> `dcl-Project-Load` **does nothing if the project is already loaded** unless
> its optional `ForceReload` argument is `T`, and `*pfp-loaded*` is a
> session-long global. Without `PFPRELOAD`, `.odcl` edits never reach the
> runtime and correct fixes look like failures. This cost a full debugging
> session on 2026-07-27.

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
├── pfpro/         pfpro.lsp        + README.md      7  C:PFPROINV / C:PFPROTOP
├── pflabel/       pflabel.lsp      + README.md      8  C:PFLABEL
├── pfxlabel/      pfxlabel.lsp     + README.md      9  C:PFXLABEL
├── pfinvert/      pfinvert.lsp     + README.md     10  C:PFINVERT
├── pfreport/      pfreport.lsp     + README.md     11  C:PFREPORT
└── pfpalette/     pfpalette.lsp    + README.md     12  C:PFPALETTE
```

Load order: cfg → lib → draw → anchor → settings → setup → **pro** → label →
xlabel → invert → report → palette; a file may only depend on files that load
before it.

**`pfpro` (2026-07-29, untested in CAD)** is the only command that WRITES a
`.pro` — everywhere else in the suite a profile is authored data that is read
and never drawn. It cuts `Type_Name_INV.pro` / `_TOP.pro` from a polyline the
drafter drew in a profile grid, using the anchor's own transform inverted
(`pf:profile-x->station`, `pf:y->elev`), so the file cannot disagree with the
grid its labels are drawn against. One polyline pick, no dialog: `STA0`,
`DATUM`, `HPLOT` and `VPLOT` come off the anchor, and the anchor itself
resolves from where the polyline sits. Nothing in the suite calls into it.
Details and the CAD gates are in [pfpro/README.md](pfpro/README.md).

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
| `btnRefresh` `btnHelp` | Button ×2 | Form-level, bottom, visible on all tabs. Refresh calls `pfp:refresh` inline; Help defers `PFPHELP`. Both wired, **unverified in CAD**. |
| `tabMain` | TabStrip | Spans the content region. |

### Commands tab (built and firing in CAD, 2026-07-29)

**It runs.** `PFPRUN` labelled two structures on line `BB` from the palette,
under `pf:run-command`, one undo group, `Status: PASSING`. Contract and the
four decisions that departed from the original design:
[`pfpalette/README.md`](pfpalette/README.md) §9. Control-level wiring:
[`pfsuite-odcl/OPENDCL-WIRING.md`](pfsuite-odcl/OPENDCL-WIRING.md).

Working: `tarLines` → `detailsList` summary, `optLabel` (Structures / Inverts /
Crossings), `optRun` (`Label All`, `Label Outstanding`), `chkbxZoom`, `btnRun`,
`btnClear`. Not wired: `optTools` (greyed — the three Carlson command names are
unknown) and `Label Selected` (refused — `detailsList` is a summary, so there
is nothing to select from; the modal keeps that job).

The table below is the **2026-07-24 design**, kept for the reasoning. Two rows
were overtaken by what got built — see the note after it.

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

> **Two rows above were overtaken by the build (2026-07-29).**
>
> **Items is a per-target SUMMARY, not an item list.** `detailsList` shows all
> three passes' counts at once — structures on the line, structure labels
> "8 labeled, 4 outstanding", invert labels, crossings on record, drift — so
> the numbers are on screen *before* the radio is touched. An item list for one
> pass cannot do that. The consequence is `Label Selected`, which had nothing
> left to select from and is refused.
>
> **Options is one checkbox, not a swapping band.** Only `Zoom To` exists.
> "allow relabeling" is unreachable from the palette: Crossings takes
> `pfxl:run`'s All branch, which filters already-labeled crossings out rather
> than offering to duplicate them.

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

**The read/write contract (enforced 2026-07-26, VERIFIED IN CAD
2026-07-27).** Anything a modeless handler can reach must not write the
drawing — not even "harmlessly":

- `pfa:nod-dict` takes a `create` flag; every read path passes nil, so a
  registry scan on a clean drawing creates nothing (same contract as
  `pfa:ledger-dict`).
- `pf:cl-geom` takes a `write-p` flag; gather paths pass nil (a cache miss
  re-reads, never files). Only PFSETUP registration and PFXLABEL discovery
  — both inside command undo groups — pass T.
- `pfa:build-lines` is write-free: a re-matched twin is used for the run
  but not filed.
- `pflabel:gather-compute` — the one gather-compute, shared by PFLABEL and
  PFINVERT — is dialog-blind and pure-read, so the Commands tab can call it
  directly for both `Structures` and `Inverts`. It already returns the
  orphan list `detailsList`'s Status column needs.

**`write-p` is the general seam, not a `pf:cl-geom` quirk.** Any persistent
cache follows it: **commands write, everything reads.** Modeless *can*
technically write the NOD — `dictadd` and xrecord writes are database calls,
not command calls — but a cache write would move `DBMOD` and prompt to save
a drawing the user only looked at, which is the contract above. So a cache
is filed from inside an existing undo group and read from anywhere.

**Why it matters, concretely:** a modeless handler has no undo group, so a
write from one is a change the user cannot reverse — and a registry scan that
created its dictionary would mark a drawing modified that the user only
*looked at*, producing a save prompt on a file they never edited.

**Measured as a delta, not an absolute.** `C:PFPDBMOD` marks `DBMOD`, you
drive the palette, it compares. `DBMOD` 0 is not reachable in general —
opening a drawing can set it before any LISP loads — and the contract never
depended on the absolute value. Results 2026-07-27: clean drawing 29→29,
populated 21→21, covering `pfa:all-anchors`, `pfa:read-attribs`,
`pfa:stub-list`, `pfa:meta-get`, `pfa:files-get`, and both dict guards.

**This is not a one-time sign-off.** Phase 4 adds Commands-tab gathers that
are *not* write-free — `pfxl:discover` merges crossings, rewrites SCOPE and
files GEOM with `write-p` T, so it can only run inside a command context.
**Re-run the delta after wiring any new read path.**

**The deferred fire is proven (2026-07-27).** `pfp:defer` queues a command via
`vla-SendCommand`; it lands in a real command context (`getpoint` prompts and
returns), inside one undo group, and refuses when `pfp:cmd-idle-p` says the
command line is busy. Every verb goes through it and nothing else.

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
This is correct behavior, not a bug — the floor is the fix. **`Min Width` ≥ 900
is now load-bearing** (§8) — lowering it re-opens the vanishing-buttons issue.

**Runtime quirks that are not design problems** (full list in
[pfpalette/README.md](pfpalette/README.md)):

- `dcl-Project-Load` no-ops when the project is already loaded unless
  `ForceReload` is `T` — use `C:PFPRELOAD` after every Studio save.
- Control symbols exist **only while the form is open**; `dcl-Form-Close`
  destroys the children. That is why `AddColumns` can't stack across toggles.
- An undefined control symbol is **nil**, and a `dcl-*` call on nil neither
  acts nor errors. `C:PFPDIAG` finds these; `pfp:caption` reports them.
- `vl-catch-all-apply` does not trap a bad *function*, only a bad *argument*.
- Colour `-24` is **Transparent**, not a theme value. The negative range is a
  documented system-colour enumeration — table in PALETTE-LAYOUT §8.

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
2. ~~**Read-only data path.**~~ **DONE, and shaken down 2026-07-27** — columns
   in `OnInitialize`; `pfp:refresh` fills tree/labels; selection fills
   `metaList` + `lvwLinkage`. Deferred-paint fix (§4a) landed after field test.
   Full results in [`pfsuite-odcl/PALETTE-TESTING.md`](pfsuite-odcl/PALETTE-TESTING.md).
2b. ~~**The two gates.**~~ **BOTH PASSED 2026-07-27.** Deferred fire
   (PALETTE-TESTING §4) and the write-free contract (§3). These were the two
   things nothing else could be built on; everything below is now unblocked.
3. **Registry verbs.** The `*pf-preset-target*` graft (§6a), deferred command
   firing via `pfp:defer` (**channel now shipped in `pfpalette.lsp` §2**), the
   three refresh signals into `pfp:refresh`, then the file pickers with their
   `CMDACTIVE` guard. Demote `pfs:registry-dialog` to a fallback once these
   work. **Decided:** one dispatcher command `C:PFPVERB` reading a `*pfp-verb*`
   ticket, rather than five `SendCommand` targets — it keeps `pfs:place-one` /
   `pfs:edit-one` private and puts the gate, the undo mark and the
   palette-disable in one place.
4. ~~**Tab 2 (Commands) — the heaviest lift.**~~ **FIRING IN CAD 2026-07-29.**
   `*pfp-order*` + `C:PFPRUN` (pfpalette §9): ticket → `pfp:defer` →
   `pf:run-command` → `pflabel:run`. Structures / `Label All` labelled two
   structures on `BB`, one undo group, `Status: PASSING`.
   - **Phase 2 folded into this**, not built separately — one dispatcher
     (`C:PFPRUN`) rather than three thin `C:PF*RUN`, for the reason Phase 3
     collapsed five verb commands into `C:PFPVERB`. The `*pf-preset-target*`
     graft it specified proved **unnecessary**: the dispatcher calls the
     engines directly and never reaches `pfs:choose-or-place`. That permitted
     graft stays unspent.
   - **The gather moved into the dispatcher**, which removed the Crossings
     special case — `pfxl:discover` is a writer, and in a command context that
     stops mattering.
   - **`Label Outstanding` cost no engine edit** — both engines read the same
     `'sel` key, and `mode` only decides whether the previous pass is erased.
   - Left: `optTools` (Carlson command names TBD, Jake), `Label Selected`
     (refused — the summary shape has nothing to select from), and **firing
     Inverts and Crossings from the palette, neither yet tried.**
   - **§5's write-free delta must still be re-run** — the Commands tab's
     gathers were not in the drawing when `PFPDBMOD` last measured.
5. **Tab 3 (Settings).** `pflabel_settings` contents plus suite-level settings,
   `Apply` / `Reset` local to the tab.

---

## 8. Open

- `*pftools-dir*` is still a hardcoded absolute path in `pftools-load.lsp`.
- ~~Buttons vanished during one resize test~~ — **CLOSED BY CONSTRUCTION
  2026-07-27.** With `Min Width` ≥ 900 the form cannot narrow far enough for a
  right-anchored control to compute a negative x, so the resize test passes
  trivially. Consistent with the theory; not a test of it. **The 900px floor
  is now load-bearing.** The cost: `Dockable Sides` is Left + Right because
  this palette is meant to be a vertical strip, and a strip with a hard 900px
  floor is a wide one. Narrowing it means reflowing the five fixed-width
  Registry button rows — a redesign, deliberately not scheduled.
- Status pane in the Registry tab is **deliberately deferred** — PFCHECK is not
  built, so there is no data to put in it.
- **Lifecycle (§5 of PALETTE-TESTING) is OPEN and deferred by decision.**
  `OnEnteringNoDocState` never fired — the palette persisted on the start
  screen — and `OnDocActivated` threw `no function definition`. Read together:
  the event fires into a document where the suite was never loaded, and
  AutoLISP namespaces are per-document. **The blocker is namespace, not form
  state**, which rules out both previously-listed fallbacks (`dcl-Form-Hide`,
  `vlr-docmanager-reactor`) — neither fixes a handler that doesn't exist in
  the document being activated into. Candidate fix: per-document autoload
  (`acaddoc.lsp`). Until then, stale data after a drawing switch **and**
  start-screen persistence are known rough edges.
- **Docked layout is barely tested.** Every resize test in the plan is a
  *floating* test performed by dragging edges; docked is the mode this palette
  is designed for. A docked-only gray box over the footer labels is recorded
  at PALETTE-TESTING §1.7 and may already be resolved.
- `tvwLines` is misaligned and leaves a growing gap above it on stretch —
  likely `Use Top From Bottom` = 1 where the spec says 0. **All existing
  anchoring evidence was gathered against a stale in-memory project**, so §1.6
  needs re-running after the fix regardless.
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
- **Refresh picks up late `.pro` files** — a line registered before its
  profiles were cut no longer stays unbound forever. The scan re-checks known
  lines in both stores (stub and anchored profile) and fills EMPTY `_INV`/`_TOP`
  slots only; an existing binding is never overwritten or re-pointed, so
  Refresh stays safe to hit at any time and Edit remains the only way to
  change a binding that already exists.
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
  **Unblocked 2026-07-27** by `pf:cl-parse` (§11) — still open.
- Several 2026-07-21 fixes are still tagged **untested in CAD** — the V5 fork
  regression gate (§6b) is the vehicle for closing them.

---

## 11. Applied 2026-07-27 — the `.cl` parser and the error parade

All of this is **untested in CAD** except where noted.

### The error parade

`PFLABEL` printed `Error: unable to locate point along centerline` in bulk.
That message comes from EWORKS' `cl_location_at_pt`, printed from C++ **below
LISP**, where `pf:cl-locate-safe`'s `vl-catch-all-apply` cannot suppress it —
the same class as the uncatchable OpenDCL property dialog in
PALETTE-TESTING §1.7f. The fix is never to make the call.

`pf:lines-at-point`'s corridor pre-filter **failed open**: no verts meant
every structure in the drawing got tested against that line. And
`pfa:build-lines` was discarding the shape `pf:cl-geom` already handed it
in `(cdr geom)`, hunting instead for a drawn twin that registered-only lines
never have — which is exactly what `registry-pairs` adds. Fixed, plus a new
`*pf-corridor-sampled*` for approximate shapes. **Confirmed in CAD: 47 lines,
zero errors.**

### `pf:cl-parse` — the `.cl` format probe is closed

`.cl` is plain CSV, verified against `Carlson_References/*.cl`:
`code, station, flag, northing, easting`, terminator `0,0,L,0,0`, flags
`L` / `PC` / `R` / `PT`. Arcs are an `R` row carrying the **centre point** and
a delta packed **DD.MMSSsss** — not a station, not decimal degrees, not a
vertex. The file is northing/easting; the drawing is X=easting.

Stations are measured along the arc, so a curve's station delta *is* its arc
length — which fixes the sweep without trusting the delta. Arcs are densified
at `*pfx-sample-step*`; worst-case sag on the sample set is 0.0044 ft against
a 0.2 ft corridor. GEOM `KIND` now writes `*pf-geom-exact*`; a refused parse
falls back to the Road-API walk unchanged.

Cost: Water_H is **1,260 `cl_location_at_sta` calls to walk, one file read to
parse**. Verified in CAD — lines `H` and `A` load with ranges matching their
files exactly, and one file (`Water_E`) refused and fell back cleanly.

**There is no re-file path.** `pfs:auto` short-circuits already-named lines,
so existing drawings keep their SAMPLED records until a `.cl` changes on
disk. A `PFRECACHE`-style command is designed, not built.

### Drift detection

A pass entity whose X matches no current structure is a label with nothing
under it. **The drawn labels are the record of where the structures were** —
no stored positions. Printed at gather (`DRIFT:` block, alongside the corner
and `.cl` warnings) and shown in each run dialog's `error` tile. Never
persisted: STATUS means "correct as of the last pass", drift accumulates
between passes.

### One gather-compute

`pfi:rd-compute` was a line-for-line copy of `pflabel:rd-compute` and had
already silently missed the drift echo. Both now bind
`pflabel:gather-compute`; the fills stay local because tile names belong to
their own dialog. Third time this divergence has cost the suite, after the
registry builder and same-type membership.

Also removed: `pflabel:label-all`'s rebuild of a structure list the ticket
already carried — one of three full membership scans per run.

### Designed, not built

- **Bounding-box guard** in front of `pf:pt-poly-dist`. Rejects
  point-vs-line pairs in O(1) with *zero* false negatives (a point within `c`
  of a polyline is necessarily inside its box grown by `c` — deflections
  affect how much it saves, never what it decides). Measured 55% rejection on
  a deliberately pessimistic four-long-alignment sample; better on a real
  registry, where 21 of 47 storm lines are 60-ft stubs. `*pf-grid-cell*` is
  the inert knob it belongs to.
- **Cheap staleness probe** — `vl-file-systime` + size instead of 47
  full-file `pf:checksum-file` reads per run.
- **A persistent membership index** keyed by inlet signature
  (`handle, x, y` digest) plus tolerance provenance, filed per line as raw
  facts with junctions derived at read — so anchoring a new line never
  invalidates an existing one. Written by commands, read by gather and by the
  palette. Serves `pfreport` too: `pfr:struct-id` already recomputes the
  identical `pf:lines-at-point` + `pf:rank-on-line` composition.
