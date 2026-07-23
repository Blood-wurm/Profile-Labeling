# PFTools V5 — Bryant Engineering Profile Suite palette

An OpenDCL dockable palette front-end for the PFTools suite. V5 is **additive**:
it does not replace V4. Every V4 command keeps working from the command line
with its existing modal DCL dialogs; the palette becomes the daily driver.

V4 lives one level up (`..\`) and V5 shares its command layer — there is no
copy of the `.lsp` files here. That means the two cannot drift, and the single
graft V5 needs into V4 (`*pf-preset-target*`, §6) lands once.

---

## 1. Status

| | |
|---|---|
| `pfsetup.odcl` | Registry tab laid out. Commands and Settings tabs empty. |
| LISP wiring | **None.** No handlers, no loader, no `PFPALETTE` command. |
| Run in CAD | **Never.** The palette has not been opened in AutoCAD once. |

The project file is still named `pfsetup.odcl`, so the LISP path prefix is
`pfsetup/`. Renaming it to `pfsuite.odcl` changes every control path — do it
before writing handlers or not at all.

---

## 2. Structure

```
pfsetup.odcl                     project  → first path segment
└── pfsPalette        Palette    the docked window; caption is the title
    ├── Tab 1  "Registry"
    ├── Tab 2  "Commands"
    └── Tab 3  "Settings"
```

Control paths are always three segments — `pfsetup/pfsPalette/tvwLines`. There
is no tab segment even though controls belong to tabs; Studio tracks tab
membership internally and the runtime shows and hides them for you.

### Registry tab (built)

| Control | Type | Purpose |
|---|---|---|
| `tvwLines` | TreeView | Two levels, utility Type → Line. The only control that stretches. |
| `metaList` | ListView, Report | `Property` \| `Value` grid for the selected line. |
| `lvwLinkage` | ListView, Report | `Item` \| `File` — five fixed rows, one per binding. |
| `btnPickCL` … `btnPickDESIGN` | Button ×5 | File pickers, one row. |
| `btnAnchor` `btnEdit` `btnNew` `btnRemove` `btnZoom` | Button ×5 | Registry verbs, one row. |
| `btnRefresh` `btnHelp` | Button ×2 | Form-level, bottom, visible on all tabs. |
| `tabMain` | TabStrip | Spans the content region. |

Geometry, form 1000 × 560, 10px margins:

```
tvwLines      Top 90    Height 425      stretch both axes
metaList      Top 525   Height 190      stretch H, bottom-pinned V
lvwLinkage    Top 725   Height 130      stretch H, bottom-pinned V
picker row    Top 865   Height 25       fixed, Left 10/120/230/340/450 × W100
verb row      Top 900   Height 25       fixed, same grid
btnRefresh    Top 965   Left 10         fixed, left-pinned
btnHelp       Top 965                   fixed, right-pinned
```

### Commands tab (not built)

Target is the line selected on the Registry tab — sticky across tabs, echoed in
a header label. A horizontal radio picks `Structures` (PFLABEL) / `Inverts`
(PFINVERT) / `Crossings` (PFXLABEL); a multi-select ListView lists the items
with a labeled/outstanding status column; buttons are `Label Selected`,
`Label All` / `Label Outstanding`, `Zoom To`. Entertaining adding Carlson native
profile commands as well.

The three lists are near-identical in shape — `pf_run`, `pfi_run` and
`pfxl_run` in `..\pfdialog.dcl` are the reference. Crossings widens to
`Source | Target Sta | Source Sta | Status`.

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

### Right now, with no new files

The palette has no loader yet, but it can be opened by hand. At the AutoCAD
command line:

```
_OPENDCL
```

then at the Visual LISP console or as a `(load)`-ed expression:

```lisp
(dcl-Project-Load "C:/path/to/V4/V5/pfsetup.odcl")
(dcl-Form-Show pfsetup/pfsPalette)
```

`dcl-Form-Show` returns immediately — the palette is modeless. Dock it, resize
it, and confirm `Min Width` / `Min Height` hold.

**This is milestone 1 and it should happen before any further design work.**
It proves the runtime version, the project load path, docking behavior, and the
resize floor. V4 went months without executing in CAD and it cost real rework;
do not repeat that here.

### The loader to write

`pfpalette.lsp`, loaded after the V4 suite:

- `(command "_OPENDCL")` with `CMDECHO` suppressed, to ensure the runtime is up
- `dcl-Project-Load` on the `.odcl` resolved relative to `*pftools-dir*`
- `C:PFPALETTE` — a toggle: if `dcl-Form-IsActive`, hide; else show
- Add the load line to `..\pftools-load.lsp` **last**, after `pfinvert.lsp`

Note `*pftools-dir*` in `..\pftools-load.lsp` is a hardcoded absolute path
(`C:/Users/Guest01/...`). It is a known open issue; the palette loader should
derive the `.odcl` path from it rather than hardcoding a second one.

### API spellings

The shipped samples use hyphens (`dcl-Project-Load`, `dcl-ListView-AddColumns`);
older forum code uses underscores (`dcl_TabStrip_GetCurSel`). Both work. Pick
hyphens and stay consistent.

Event handlers are named by path:

```lisp
(defun c:pfsetup/pfsPalette#OnInitialize ()            ...)
(defun c:pfsetup/pfsPalette/btnAnchor#OnClicked ()     ...)
(defun c:pfsetup/pfsPalette/tabMain#OnChanged (nSel)   ...)
```

Working examples ship with Studio in `ENU\Samples\` — `Methods.lsp` for the
TabStrip, `ListView.lsp` and `AllControls.lsp` for ListView columns, `Tree.lsp`
for the TreeView, `Modeless.lsp` for modeless lifecycle.

---

## 4. ListView columns are runtime, not design-time

There is no column editor in Studio. Columns are added in code, once, in
`OnInitialize`:

```lisp
(dcl-ListView-AddColumns pfsetup/pfsPalette/metaList
  '(("Property" 0 110) ("Value" 0 410)))
(dcl-ListView-AddColumns pfsetup/pfsPalette/lvwLinkage
  '(("Item" 0 90) ("File" 0 440)))
```

Each column is `(caption alignment width)`, alignment `0` = left. Rows are
tab-delimited strings via `dcl-ListView-AddString`.

`AddColumns` is **additive** — calling it from a refresh routine stacks
duplicate columns. It belongs in `OnInitialize` and nowhere else.

A blank ListView in the designer is expected, not broken.

---

## 5. OpenDCL constraints that shape the design

**Modeless.** Palette handlers run outside a command context. No `entsel`, no
`getpoint`, no `command`, no undo group. Every V4 verb needs all four, so the
palette must never do work — it selects context and fires the existing `C:PF*`
command deferred. The five commands' internals stay untouched.

**No OK/Apply/Cancel.** A docked palette never closes and has no commit moment;
OK/Cancel is a modal idiom and would raise a question the UI cannot answer.
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

**Record writes from a modeless context** (the file pickers) must be gated on
`(getvar "CMDACTIVE")` = 0, wrapped in an explicit undo mark, and the palette
disabled while a command runs.

**Refresh on three signals only, never poll:** `OnDocActivated` (the registry is
per-drawing, the palette is per-session), a `:vlr-commandEnded` reactor filtered
to `PF*` names, and `btnRefresh`.

---

## 6. The one graft into V4

All three label commands are pick-first — they call `pfs:choose-or-place`
(`..\pfsetup.lsp:679`), which opens the `pf_pick` modal. To pre-target from the
palette, add a global consumed-and-cleared at the top of that function:

```
*pf-preset-target*   set by the palette, read once, cleared
```

Roughly four lines, one function. Command-line invocation stays byte-identical.
Nothing else in V4 changes for milestones 1–3.

---

## 7. Milestones

1. **Prove it loads.** Manual `dcl-Project-Load` + `dcl-Form-Show` in CAD. Dock
   it, resize it, confirm the Min floor. Nothing else.
2. **Read-only data path.** `OnInitialize` columns; populate `tvwLines` from
   `pfa:registry`; selection handler fills `metaList` and `lvwLinkage`. Writes
   nothing to the drawing, so nothing can damage a sheet while it is wrong.
3. **Verbs.** The `*pf-preset-target*` graft, deferred command firing, the three
   refresh signals, then the file pickers with their `CMDACTIVE` guard.
4. **Tabs 2 and 3.**

---

## 8. Open

- Rename `pfsetup.odcl` → `pfsuite.odcl` (changes every control path) — before
  handlers, or never.
- `lblProject` / `lblCounts` have no home yet. They belong **outside** `tabMain`,
  above it, as form-level controls so they render on all three tabs. `tabMain`
  needs to move down ~40 to make room.
- Buttons vanished during one resize test with anchoring that is provably
  identical to buttons that survived. Unresolved — check whether they return on
  a form close/reopen (z-order/repaint) or stay gone (geometry). `tabMain` is
  last in the Control Browser, which usually means topmost.
- Status pane in the Registry tab is **deliberately deferred** — PFCHECK is not
  built, so there is no data to put in it. Do not build UI ahead of its source.
- Does the palette shadow the modal dialogs or replace them? Shadowing costs
  nothing and keeps the command-line path intact. Not yet decided.
