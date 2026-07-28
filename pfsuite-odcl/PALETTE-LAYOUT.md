# PALETTE-LAYOUT.md — pfsPalette structure, anchoring, and wiring contract

**Studio owns the geometry. This file owns everything Studio can't hold.**

The `.odcl` is compressed binary — it can't be diffed or reviewed, so control
*names*, what each control is *for*, how it's *anchored*, and which ones are
*wired* live here. Exact rects do not: they're in Studio's Properties panel,
which is authoritative and always current. Don't mirror them here; they'll drift
and the copy will lose.

Companion docs: [`../pfpalette/README.md`](../pfpalette/README.md) (what the
code owns), root [`../README.md`](../README.md) §2 (milestone status) and §5
(the OpenDCL constraints this applies).

---

## 1. Structure

```
pfsuite.odcl                          project → first path segment
└── pfsPalette                        Palette — form level
    ├── tabMain      TabStrip         the container
    │   ├── Registry                  tab surface
    │   ├── Commands                  tab surface
    │   └── Settings                  tab surface (empty)
    ├── btnRefresh   btnHelp          footer, right
    └── lblProject   lblCounts        footer, left
```

The three tabs are **child surfaces of `tabMain`**, each with its own control
list in Studio's browser. Selecting a tab in the tree shows only that tab's
controls — the form-level five are visible only with `pfsPalette` selected.

**Control paths are always three segments** — `pfsuite/pfsPalette/tvwLines`.
There is no tab segment even though controls belong to tabs; Studio tracks tab
membership internally and the runtime shows and hides them. The footer controls
use the same three-segment form, which is why `pfp:seed-labels` addressing
`pfsuite/pfsPalette/lblProject` works from any tab.

Handlers are named by path:

```lisp
(defun c:pfsuite/pfsPalette#OnInitialize ()                    ...)
(defun c:pfsuite/pfsPalette/tvwLines#OnSelChanged (Label Key)  ...)
```

### A wrong `(Name)` fails silently — check it, don't trust it

An OpenDCL control symbol that the loaded project never defined evaluates to
**nil**: AutoLISP returns nil for an unbound symbol instead of erroring. Every
`dcl-Control-*` call on nil then does nothing and reports nothing. A renamed or
mistyped control therefore produces **no error, no message, and no behaviour** —
the hardest failure mode in this whole design to spot, and the one that cost the
2026-07-27 run its two footer labels (PALETTE-TESTING 2.3/2.4).

**`C:PFPDIAG`** (`../pfpalette/pfpalette.lsp` §6) resolves every name in the
roster below and lists the misses. Run it after any Studio rename, and before
wiring anything new — the `.odcl` is binary and can't be diffed, so this command
is the only review the names get.

### Control symbols exist only while the form is open

**Field-tested 2026-07-27: `PFPDIAG` closed → 0 of 29; open → 29 of 29.**

`dcl-Form-Close` **destroys the child controls**, and every control symbol
reverts to nil. The **form** symbol survives — that is why `C:PFPALETTE` can
call `dcl-Form-IsActive` on a closed palette — but nothing beneath it does.

This is not a curiosity; it is load-bearing in three places:

- **It is why columns don't stack** (PALETTE-TESTING 2.10). The worry was that
  `AddColumns` being additive would give 4 and 6 columns after three toggles.
  It gives 2 and 2 because Close destroys the controls and `OnInitialize`
  rebuilds them from nothing. **The `*pfp-columns-done*` flag the test proposed
  as the fix is not needed** — and would in fact be wrong, since it would
  suppress the rebuild the second open requires.
- **Any control write while closed is a silent no-op.** Not an error — nil in,
  nothing out. `pfp:caption` guards this for captions; anything new that touches
  a control must assume the form may be gone.
- **It shapes §7's lifecycle problem.** A `pfp:refresh` driven from
  `DocActivated` after `EnteringNoDocState` closed the form would quietly do
  nothing at all, because every control it writes to is nil.

`PFPDIAG` now refuses to run against a closed palette rather than reporting all
29 MISSING, which is the exact wrong answer.

The project file lives at `pfsuite-odcl/pfsuite.odcl`; `pfp:odcl-path` in
`pfpalette.lsp` carries the folder segment. It and `pfset:dcl-file` are the only
two path builders in the suite — both derive from `*pftools-dir*`, which is set
once in `pftools-load.lsp`. Never hardcode a second copy.

### Two coordinate spaces

| Space | Size | What uses it |
|---|---|---|
| Form client | **900 × 670** | `tabMain`, `btnRefresh`, `btnHelp`, `lblProject`, `lblCounts` |
| `tabMain` client | **896 × 606** | everything on Registry, Commands, Settings |

Derived from `tarLines`: Left 10 + Width 876 + Right From Right 10 = 896; Top 40
+ Height 205 + Bottom From Bottom 361 = 606, cross-checked by Top From Bottom
566. Tab children start at Top≈40 because the tab header eats the first ~30px of
`tabMain`. The form's remaining 64px of height is the footer band plus margins.

---

## 2. Form properties

| Property | Value | |
|---|---|---|
| Width × Height | `900 × 670` | design size |
| Min Width | ~~`570`~~ → ≥ `900` | fixed (confirmed by 1.6a); now load-bearing — see below |
| Min Height | ~~`700`~~ → ≤ `670` | **unconfirmed** — 1.1 was never signed off; read the actual value in Studio |
| Max Width / Max Height | `0` / `0` | no ceiling |
| Allow Resizing | True | |
| Dockable Sides | `0 - Left + Right` | never docks top/bottom — this palette lives as a vertical strip, so height varies constantly and width rarely |
| Event Invoke | `0 - Synchronous` | |
| Background Color | `-24` | OpenDCL enumerated value, not a hex (§7) |
| Title Bar Text | `Bryant Engineering Profile Suite` | |

### The Min Width / Min Height defect

**`Min Height` (700) exceeds `Height` (670).** The runtime floor is taller than
the design size, so what you lay out in Studio is 30px off from anything the
runtime renders, and every bottom-anchored control sits low at minimum size.

**`Min Width` (570) is too narrow for the Registry button rows.** Those are five
fixed-width buttons ending near x=889. At 570 the last three are past the right
edge, and any anchored right computes a negative x on the way down and vanishes
off the *left* side.

The two values also look transposed. **Fix: `Min Width` ≥ 900, `Min Height`
≤ 670.**

> **Live candidate for root README §8** — "buttons vanished during one resize
> test with anchoring provably identical to buttons that survived," unresolved.
> A 570px floor makes that reproducible: the survivors were left-anchored, the
> casualties right-anchored, and nothing about the flags looks different until
> the form is narrow enough for the difference to bite. Confirm or rule out
> before spending more time on §8.
>
> **2026-07-27 — §8 closed BY CONSTRUCTION.** With `Min Width` ≥ 900 the form
> cannot narrow at all, so nothing can compute a negative x and the resize test
> passes trivially (PALETTE-TESTING 1.6a). Consistent with the theory; not a
> test of it. **The 900px floor is now load-bearing — lowering it re-opens §8.**
>
> **The cost:** `Dockable Sides` is Left + Right because this palette is meant
> to be a vertical strip, and a strip with a hard 900px floor is a wide one.
> The floor is forced by the five fixed-width Registry button rows (§3 — no
> layout flow, so a fixed row can't redistribute). A genuinely narrow palette
> needs those rows reflowed: icon buttons, two stacked rows, or a toolbar.
> That is a redesign, deliberately not scheduled.

---

## 3. Anchoring

Each axis has two "Use" flags selecting **which edge each side is measured
from**:

- `Use Left From Right` = 0 → left edge uses `Left`; = 1 → uses `Left From Right`
- `Use Right From Right` = 1 → right edge uses `Right From Right`; = 0 → right
  edge rides on `Left + Width`

Vertical is identical with `Use Top From Bottom` / `Use Bottom From Bottom`.

| Pair | Meaning | Behavior |
|---|---|---|
| `0 / 0` | both edges from the left | fixed size, pinned left |
| `1 / 1` | both edges from the right | fixed size, pinned right |
| `0 / 1` | left from left, right from right | **stretches** |
| `1 / 0` | left from right, right from left | inverted — the mixed pair is always wrong |

### Form level

| Control | H | V | |
|---|---|---|---|
| `tabMain` | 0/1 | 0/1 | stretches both — every `0/1` below depends on this |
| `lblProject` `lblCounts` | 0/0 | 1/1 | bottom-left |
| `btnRefresh` `btnHelp` | 1/1 | 1/1 | bottom-right |

### Registry tab

| Control | H | V | |
|---|---|---|---|
| `tvwLines` | 0/0 | 0/1 | fixed width, full height — **shipped state disagrees, see below** |
| `metaList` | 0/1 | 0/0 | width tracks, height fixed at top |
| `lvwLinkage` | 0/1 | 0/1 | the stretcher |
| `btnPickCL` … `btnPickEXIST` | 0/0 | 1/1 | bottom-pinned row |
| `btnAnchor` … `btnZoom` | 0/0 | 1/1 | bottom-pinned row |

### Commands tab

| Control | H | V | |
|---|---|---|---|
| `tarLines` | 0/1 | **0/0** | width tracks, height capped |
| `frmLabel` + `optLabel` | 0/0 | 0/0 | fixed, top-left |
| `frmTools` + `optTools` | 0/0 | 0/0 | fixed, top-left |
| `detailsList` | 0/1 | 0/1 | the stretcher |
| `frmOptions` + `optRun` | 0/0 | 1/1 | bottom-left |
| `chkbxZoom` | 0/0 | 1/1 | bottom |
| `btnClear` `btnRun` | 1/1 | 1/1 | bottom-right |

### `tvwLines` — open finding, 2026-07-27

Two symptoms from the field test, one likely cause:

- **1.1** — `tvwLines` is not aligned with the controls beside it.
- **1.6c** — growing the palette taller leaves **a gap above `tvwLines`** that
  widens as it stretches.

A top edge that drifts downward as the form grows is what `Use Top From Bottom`
= 1 does: the top is being measured from the bottom edge. That makes the shipped
pair `1/1` (fixed height, pinned bottom) where this table specifies **`0/1`**
(top fixed, bottom tracks — full height). Check `Use Top From Bottom` on
`tvwLines` first; it should be **0**.

Worth confirming rather than assuming — `Top` itself may simply be set below
the panel top, which produces a constant gap instead of a growing one. **A gap
that grows on stretch is the anchor; a gap that stays put is the rect.**

### Three rules behind those tables

**Frames don't carry their children.** OpenDCL positions every control in the
tab's coordinate space; a frame is decoration plus radio grouping, not a parent.
Set `frmLabel` and `optLabel` to *identical* flags or the group detaches from its
box on the first resize. Same for `frmTools`/`optTools` and
`frmOptions`/`optRun`.

**Exactly one stretcher per vertical stack.** Registry's right column is
`metaList` (fixed) → `lvwLinkage` (stretches) → two bottom-pinned rows. Commands
is `tarLines` (fixed) → `detailsList` (stretches) → bottom band. Two stretchers
in one stack overlap.

**Button rows pin left; `btnClear`/`btnRun` pin right.** Not inconsistent — the
Registry rows span the full panel width, so gluing their left edge to
`metaList`'s left edge preserves the column structure, while `btnClear`/`btnRun`
is a two-button cluster already hugging the right edge. OpenDCL has no layout
flow, so a fixed-width row can't redistribute; pinning one side is the only
choice and the gap opens on the other. It only appears on a *widen*, which is
why `Min Width` must be ≥ 900.

---

## 4. Form-level controls

| Control | Type | Purpose | Wired |
|---|---|---|---|
| `tabMain` | TabStrip | Container for the three tab surfaces. | n/a |
| `lblProject` | Label | Project root. Captioned by `pfp:seed-labels`. | ⚠️ wired, **blank at runtime** |
| `lblCounts` | Label | Registry tallies. Captioned by `pfp:seed-labels`. | ⚠️ wired, **blank at runtime** |
| `btnRefresh` | Button | Calls `pfp:refresh` — **direct call, no defer** (pure read). | ❌ |
| `btnHelp` | Button | TBD. | ❌ |

---

## 5. Registry tab

| Control | Type | Purpose | Wired |
|---|---|---|---|
| `tvwLines` | TreeView | Type → Line. Filled by `pfp:fill-tree`; `#OnSelChanged` drives both panels. | ✅ |
| `metaList` | ListView (Report) | `Property` \| `Value`. Filled by `pfp:meta-rows`. | ✅ |
| `lvwLinkage` | ListView (Report) | `Item` \| `File`, five fixed rows. Filled by `pfp:fill-linkage`. | ✅ |
| `btnPickCL` | Button | `.cl` | ❌ |
| `btnPickINV` | Button | `INV.pro` | ❌ |
| `btnPickTOP` | Button | `TOP.pro` | ❌ |
| `btnPickDESIGN` | Button | `DESIGN .tin` | ❌ |
| `btnPickEXIST` | Button | `EXIST .tin` | ❌ |
| `btnAnchor` `btnEdit` `btnNew` `btnRemove` `btnZoom` | Button ×5 | Registry verbs. | ❌ |

### Pick-button order vs. linkage-row order — fix before wiring

`pfp:fill-linkage` emits rows in this order:

| # | Linkage row | Pick button at that position |
|---|---|---|
| 1 | `Centerline (.cl)` | `btnPickCL` ✅ |
| 2 | `Invert _INV .pro` | `btnPickINV` ✅ |
| 3 | `Crown _TOP .pro` | `btnPickTOP` ✅ |
| 4 | `Existing .tin` | `btnPickDESIGN` ❌ |
| 5 | `DESIGN_* .tin` | `btnPickEXIST` ❌ |

**Slots 4 and 5 are crossed.** Swap them so each button sits under the row it
feeds.

### Verbs are deferred-fire only

A modeless handler cannot call `command`, `entsel`, or `getpoint` (root README
§5). Every verb and every pick writes or prompts, so none may act directly. The
read side is different and already proven: `tvwLines#OnSelChanged` calls the same
registry reads the commands use, because those paths are provably write-free
(`pfa:nod-dict` with `create` nil).

---

## 6. Commands tab

| Control | Type | Purpose | Wired |
|---|---|---|---|
| `tarLines` | TreeView | Target line. Capped height, not a stretcher. | ❌ |
| `frmLabel` | Frame | Groups `optLabel`. | n/a |
| `optLabel` | RadioGroup | `Structures` / `Inverts` / `Crossings` → PFLABEL / PFINVERT / PFXLABEL. | ❌ |
| `frmTools` | Frame | Groups `optTools`. | n/a |
| `optTools` | RadioGroup | `Quick Profile` / `Profile from 2dPL` / `Export .stm` — native Carlson. | ❌ |
| `frmOptions` | Frame | Groups `optRun`. | n/a |
| `optRun` | RadioGroup | `Label All` / `Label Outstanding` / `Label Selected` → ticket `mode`. | ❌ |
| `detailsList` | ListView (Report) | Items on the target with a `Status` column. The stretcher. | ❌ |
| `chkbxZoom` | CheckBox | `Zoom To` → ticket `(zoom . T\|nil)`. | ❌ |
| `btnClear` | Button | Clears the selection. Caption reads `CLear` — typo. | ❌ |
| `btnRun` | Button | Fires the selected command. | ❌ |

`optLabel`, `optTools` and `optRun` are each **one** control holding three items.

### Dispatch model

**The radio selection decides what `RUN` fires**, and selecting in either
`optLabel` or `optTools` **greys out everything that doesn't pertain to it**.
`RUN` reads the active-group flag — not "which radio has a selection," because a
radio group can never un-select and both groups stay filled underneath.

| Control | Label active | Tools active |
|---|---|---|
| `optLabel` / `frmLabel` | enabled | **grey** |
| `optTools` / `frmTools` | **grey** | enabled |
| `tarLines` | enabled | **enabled** |
| `detailsList` | enabled | **grey** |
| `optRun` / `frmOptions` | enabled | **grey** |
| `chkbxZoom` | enabled | **grey** |
| `btnClear` | enabled | **grey** |
| `btnRun` | enabled | enabled |

`tarLines` stays live in both states (decided) — a native tool can act on the
selected line. Everything else greys under Tools because those are pure
launchers: Carlson's own dialog takes over and no `rd` ticket is assembled.

**Initial state:** default to Label active with Tools greyed. `Structures` is
already the selected item, so no third "nothing chosen yet" state is needed.

**Disabling a frame may not cascade** to its children — set both the frame and
its group control explicitly until tested otherwise. The API is
`dcl-Control-SetEnabled` (attested as `dcl_Control_SetEnabled` in the
`AUBlockTool` sample). Enable/disable touches only the UI, never the drawing, so
these handlers are modeless-safe.

### The order ticket

The engines already split gather → run at one alist (`pflabel.lsp:293-306`,
`pfinvert.lsp:490-503`):

```
rd = ( (mode . "All"|"Sel") (sel . <items>) (lines . <…>) (inlets . <…>)
       (zoom . T|nil) … per-command options … )
```

| Input | Feeds |
|---|---|
| radio selection | *which* command to fire |
| `tarLines` | the target line |
| `detailsList` selection | `(sel . <items>)` |
| `optRun` | `(mode . "All"\|"Sel")` |
| `chkbxZoom` | `(zoom . T\|nil)` |

Options ride **in the ticket**, never in one-shot globals (root README §6b).
`*pf-zoom-to*` is transitional and gets deleted when `chkbxZoom` is wired.

`Label Outstanding` is a third `optRun` item; whether it becomes a third `mode`
value or `"All"` plus an outstanding-only filter is still open.

### Crossings gather — decided

`pfxl:discover` is a **writer** (merges crossings, rewrites SCOPE, files GEOM
with `write-p` T), so it can never run from a modeless handler. For the Crossings
pass, `detailsList` shows **already-merged crossings only** via `pfa:xing-list` +
`pfa:recon` — both pure reads. Discovery happens on RUN, inside the command
context, and the list repopulates on the next refresh.

Structures and Inverts have no such constraint: `pflabel:registry-pairs`,
`pfa:build-lines`, `pfa:gather-inlets` and `pflabel:pending` are all
write-free by contract.

### Still missing

- **`Status` column** on `detailsList` — runtime `AddColumns`, once, in
  `OnInitialize`. Data source exists in every gather-compute (pflabel's
  `[LABELED]`, pfinvert's `id-status`, pfxlabel's `recon`), all reads.
- **`allow relabeling`** for Crossings — replaces the mid-run `pfset:confirm`.
- **Crossings reshape** — `detailsList` becomes `Source | Target Sta | Source Sta
  | Status`.

---

## 7. Events and lifecycle

Available on `pfsPalette` (Studio → Events):

```
Close · DocActivated · EnteringNoDocState · Help · Initialize
MouseEntered · MouseMovedOff · Move · Size · Timer
```

Currently ticked: **Close, Initialize, Size**. Only `OnInitialize` has a handler
in `pfpalette.lsp` — either confirm a ticked event with no `defun` is harmless,
or untick `Close` and `Size` until they're implemented.

| Event | Use | Why |
|---|---|---|
| `Initialize` | columns only, once | Fires **before the window is realized** — data written here doesn't paint (root README §4a). |
| `DocActivated` | → `pfp:refresh` | The drawing-switch refresh signal. Native — no `vlr-docmanager-reactor` needed. |
| `EnteringNoDocState` | → close the palette | The start-screen fix. |

### Start-screen persistence

The palette is owned by the OpenDCL ARX runtime, so it outlives any document and
appears on the start screen showing the last drawing's registry — which native
AutoCAD palettes do **not** do. `EnteringNoDocState` is the native answer.

Closing alone leaves it shut when a drawing reopens, which still isn't native
behavior. The intended fix — set `*pfp-was-open*` on the `EnteringNoDocState`
close and have `DocActivated` re-show if the flag is set — **rests on an
unverified assumption: that a closed form still receives events.**

> **2026-07-27 — tested, and the assumption was never reached.** L2 failed (the
> palette persisted on the start screen, `EnteringNoDocState` printed nothing)
> and L3 threw `no function definition:
> C:PFSUITE/PFSPALETTE#ONDOCACTIVATED`. Together those say the event **did**
> fire on the incoming document and the **handler wasn't there to receive it**.
>
> **The blocker is namespace, not form state** — which rules out both fallbacks
> this section used to list. Neither `dcl-Form-Hide` nor a
> `vlr-docmanager-reactor` fixes a handler that doesn't exist in the document
> being activated into. Only per-document autoload does.
>
> **Deferred by decision**; Phase 2 goes first now that the gate has passed.
> Start-screen persistence stands as a known rough edge. Details:
> [`PALETTE-TESTING.md`](PALETTE-TESTING.md) §5.

**The handler only exists where the suite is loaded.** AutoLISP namespaces are
per-document, so in a drawing that never ran `pftools-load.lsp` the
`OnDocActivated` function is undefined. **This is not silent** — the field test
showed OpenDCL fires the event anyway and the missing `defun` surfaces as an
error, so the cost is a visible error dialog, not merely stale data. A `boundp`
guard inside the handler can't help: the handler itself is what's missing. Only
auto-loading the suite per document (`acaddoc.lsp`) fixes it.

**Guard `DocActivated` with `(boundp '*pftools-dir*)`.** `*pftools-dir*` is a
plain `setq` in the document namespace, so it exists only in drawings where
`pftools-load.lsp` has been run. Activating into a drawing that never loaded the
suite gives a visible palette with no LISP behind it, and an unguarded refresh
errors.

### Refresh signals

All four funnel into the one `pfp:refresh`. Never poll.

`C:PFPALETTE` (after `dcl-Form-Show`) · `DocActivated` · the `:vlr-commandEnded`
reactor filtered to `PF*` · `btnRefresh`

---

## 8. Colors

> ## 2026-07-27 — RESOLVED FROM THE VENDOR DOCS, AND IT WAS A BUG
>
> The blank footer labels (PALETTE-TESTING 2.3/2.4) were a **colour** fault all
> along, and this section's "decision pending" is what left the door open.
>
> **1. `-24` is not a theme colour. It is `Transparent`.** The negative range is
> a documented system-colour enumeration:
>
> | | | | | | |
> |---|---|---|---|---|---|
> | -1 scroll bar | -5 menu | -9 **window text** | -13 app workspace | -17 button shadow | -21 button highlight |
> | -2 desktop | -6 window | -10 caption text | -14 highlight | -18 grayed text | -22 ACAD model bg |
> | -3 active caption | -7 window frame | -11 active border | -15 highlighted text | -19 **button text** | -23 ACAD layout bg |
> | -4 inactive caption | -8 menu text | -12 inactive border | -16 **button face** | -20 inactive caption | -24 **transparent** |
>
> **2. A Label has nothing that can override its `Foreground Color`.** The
> [Label control
> reference](https://www.opendcl.com/HelpFiles/ENU/Reference/Control/Label.htm)
> lists: `Background Color`, `Foreground Color`, `Border Style`,
> `Justification`, `Font` / `Font Bold` / `Font Italic` / `Font Size` /
> `Font Strikeout` / `Font Underline`, `Visible`, `Enabled`, geometry,
> tooltips. **No `Use Visual Style`** — confirmed absent in Studio on both
> labels — and no `Transparent` flag. So `Foreground Color` is authoritative,
> and a `Foreground Color` of **-24 is transparent text**: invisible docked,
> floating, at any size, under any theme. -24 is easy to set on the wrong
> property believing it means "default", and the form legitimately carries it
> as a *background*. `Font Size` 0 gives the same visible result by a different
> route.
>
> The gray box is the same enumeration from the other side — a
> transparent-*background* control mis-composites when docked and paints as an
> opaque rectangle.
>
> **The fix, on `lblProject` and `lblCounts`:** `Foreground Color` = **-19**
> (button text, so it still tracks the host theme) and a real `Font Size`. If
> the gray box survives, `Background Color` = **-16** (button face) rather than
> transparent.
>
> **This retires Tier 3's blocker.** A runtime colour API exists *and* a full
> system-colour enumeration exists, so tracking `COLORTHEME` at runtime is now
> a choice rather than an impossibility. Tier 1 "set nothing and inherit"
> remains the simplest, but note it is not the current state: something has
> already been set on these labels, and that is the bug.
>
> **An earlier revision of this note prescribed `Use Visual Style` = False**,
> taken from a forum thread about the 8.0.0.13 label-foreground regression
> without checking that Labels expose the property. They do not.

> ## 2026-07-27 — DECIDED FROM THE PROPERTY REFERENCE: mostly Tier 1, and not by choice
>
> Built as `pfpalette.lsp` **§7** (`pfp:skin`, `C:PFPTHEME`). The deciding
> facts are the **applies-to lists on the property pages**, which neither tier
> above had been checked against:
>
> | | Background | Foreground | Font + Font Size |
> |---|---|---|---|
> | Label, Option List, Check Box | ✅ | ✅ | ✅ |
> | List View | ✅ | ❌ | ✅ |
> | Tree, Frame, Tab Strip, Text Button | ❌ | ❌ | ✅ |
> | Palette (the form) | ✅ | ❌ | — |
>
> **A dark scheme is not reachable.** Tree exposes no colour property of any
> kind and List View exposes no foreground, so a dark pass would leave
> `tvwLines` and `tarLines` light while giving the three List Views a dark
> background under black text. **Dark has to come from the Windows theme**,
> which the Tree and List common controls follow on their own. Tier 3 is
> therefore not the answer, and the earlier revision of this note — which
> recorded it as decided — was wrong.
>
> **What §7 does by default (`'font` mode):** one font across all 29 controls
> (Font + Font Size is the one property pair every type accepts), the form
> background, and Label colours. Nothing there can misfire. `'full` adds
> Option List, Check Box and List View backgrounds and is opt-in, because
> those types carry `Use Visual Style` and the vendor says a visual style
> **may override** background and foreground — a colour set there may silently
> do nothing, and switching the style off to force it looks less native.
>
> **Font names and the size sign, corrected.** The properties are `Font` (face
> name, String) and `Font Size` — accessors `dcl-Control-SetFont` /
> `dcl-Control-SetFontSize`. There is no `FontName` and no `FontHeight` —
> `PFPINK` called both, and is deleted. **Negative sizes are
> in screen pixels, positive in points** (1/72") computed from screen
> resolution and display size — so positive is the DPI-aware form. Default
> face is `MS Shell Dlg`, OpenDCL's own default and the standard dialog font
> in every localized Windows.
>
> **No colour is bit-packed.** A `Color` may be a negative logical value *or*
> a list of three 0–255 integers, both documented. §7 passes the list form,
> so the packed form's undocumented byte order never arises. An earlier
> revision of this note asserted BGR from the "255 (red)" comment in the
> since-deleted `PFPINK` — an inference from a diagnostic that had never been
> run, and exactly the kind of guess the list form makes unnecessary.
>
> **The one rule to carry forward:** a property may only be called on a
> control whose type the vendor documents it for, **reads included** — a
> getter is a property accessor, so `GetForeColor` on a List View raises the
> same uncatchable modal dialog the setter would. `pfp:type-can` is that gate.
> The first §7 draft invented a chrome/data split instead of reading the
> lists, and would have hit a missing property 13 times.
>
> **The RGB tables are starting points, not a spec.** Eyedropper a docked
> Properties palette — Autodesk publishes no RGB for palette chrome, and the
> one documented dark value (33,40,48) is the *drawing area*.
>
> **Theme flips while open are manual.** `C:PFPTHEME` re-skins. A
> `vlr-sysvar-reactor` on `COLORTHEME` would automate it, deliberately not
> installed — a reactor outlives the palette, and §10 admits exactly one.
>
> **Runtime formatting never persists.** Close destroys the controls, so
> `pfp:skin` runs on every open from `C:PFPALETTE`. The skin therefore
> *masks* the blank-footer-label bug rather than curing it: a real
> `Foreground Color` and `Font Size` still belong in Studio, because a session
> with mode `'off` gets transparent text back.

**Superseded — kept for the reasoning.** "Native" for a docked palette means
matching the host, and the host theme moves: `COLORTHEME` (0 dark / 1 light) is
user-switchable at any time, so a hardcoded scheme is wrong the moment someone
flips it.

| Tier | Approach | Cost |
|---|---|---|
| **1 (recommended)** | Set nothing; every control inherits Windows/AutoCAD theming. | Abandons the dark mockup scheme. |
| 2 | A system-color enumeration value on the form and panels. `-24` may already be one. | Only covers what OpenDCL enumerates. |
| 3 | Runtime switch: read `(getvar "COLORTHEME")` in `pfp:refresh` and set colors. | **Requires a runtime color API that is not verified.** |

No color functions appear in the `Opendcl_Reference` samples, which attest only
`dcl_Control_SetCaption` / `SetEnabled` / `SetText` / `SetValue`. If no runtime
color API exists, colors are design-time only and Tier 3 is impossible.

> **2026-07-27 — a runtime color API EXISTS. Tier 3 is possible.**
> `PFPPROBE` called `dcl-Control-SetForeColor` against a live control and it
> returned without error, as did `dcl-Control-SetVisible` and
> `dcl-Control-SetText`. The samples simply never exercised them; absence from
> `Opendcl_Reference` was never evidence of absence from the API.
>
> This removes the blocker on Tier 3 — read `(getvar "COLORTHEME")` and set
> colors at runtime, so the palette tracks the host when the user flips theme.
> It does **not** decide the question: Tier 1 (inherit everything) is still the
> only option that is consistent across tab strips, buttons, frames and radios,
> which are Windows-themed no matter what the form says. What changed is that
> Tier 3 is now a *choice* rather than an impossibility.
>
> Found incidentally while chasing the blank footer labels, which is worth
> noting on its own: the probe commands in `../pfpalette/pfpalette.lsp` §6 are
> the cheapest way to settle any "does this API exist" question in this file.
> Verify before recording another constraint as unattested.

Tier 1 is also the only option consistent across *all* controls — the tab strip,
buttons, frames and radios are Windows-themed regardless.

**One check settles it:** open the Background Color dropdown in Studio. The named
entries reveal whether OpenDCL offers system/AutoCAD-tracking colors, and what
`-24` actually is.

The mockup's target scheme (dark `#2B2B2B` / `#232323` panels / `#4A9EEA`
accent, light `#F0F0F0` / `#FFFFFF` panels) is preserved in this file's history
if Tier 3 turns out to be available.

---

## 9. Wiring plan

**Phase 0 — unblock.** `pfp:odcl-path` folder segment ✅ done. Then in Studio:
`Min Width`/`Min Height` (§2), `tarLines` vertical anchor → `0/0` and
`detailsList` → `0/1` (§3), pick-button 4/5 swap (§5). Then the **engine
regression gate** — all three commands from the command line producing identical
output (REFACTOR-PLAN). Skipping it means every engine bug surfaces as "the
palette broke it."

**Phase 1 — prove the deferred fire. ✅ PASSED 2026-07-27.** A throwaway button
calling `vla-SendCommand` on the active document to run a trivial drawing
command. All four checks held: real command context (`getpoint` prompted *and*
returned — the strongest signal available), undo group intact (one `U` peeled
it), palette survived the round trip (Help greyed and came back), and
`CMDACTIVE` gating refused against a live `PLINE`.

`pfp:cmd-idle-p` and `pfp:defer` now live in `../pfpalette/pfpalette.lsp`
**SECTION 2** and are the only channel any verb may use. They were *removed*
from `pfp-proof.lsp` rather than copied — two definitions of the gate would let
the proof pass against code the palette doesn't run.

**Phase 2 — the ticket channel.** Thin `C:PFLABELRUN` / `C:PFINVERTRUN` /
`C:PFXLABELRUN` reading a global ticket and calling `pfX:run` under
`pf:run-command`. Plus the `*pf-preset-target*` graft into `pfs:choose-or-place`
— consumed and cleared at the top, so the deferred command never opens `pf_pick`.
That global was never implemented (`Low_Priority_issues.md:4`) and
`pfs:choose-or-place` **may write** (a registered pick anchors on the fly), so a
palette-initiated path must not be able to trigger a placement.

**Phase 3 — Registry verbs.**

| Button | Path |
|---|---|
| `btnRefresh` | direct call to `pfp:refresh` — the only verb that doesn't defer |
| `btnZoom` | deferred |
| `btnAnchor` `btnEdit` `btnNew` `btnRemove` | deferred via the dispatcher |
| `btnPick*` ×5 | `getfiled`, then a gated write |

**Decision: one dispatcher command, `C:PFPVERB`, reading a `*pfp-verb*` ticket.**
Rationale: keeps `pfs:place-one` / `pfs:edit-one` private instead of promoting
pfsetup internals to public API; gives one `SendCommand` target instead of five;
and puts the `CMDACTIVE` gate, the undo mark, and the palette-disable in a single
place rather than repeating them per button.

**Phase 4 — Commands tab.** `detailsList` columns in `OnInitialize`; `tarLines`
fill (parameterize `pfp:fill-tree` to take a control); the enable/disable state
machine (§6); per-pass gather; `btnRun` → ticket → `SendCommand`; `btnClear`;
the Crossings reshape.

**Phase 5 — lifecycle.** `DocActivated` and `EnteringNoDocState` per §7.

**Phase 6 — colors. ✅ BUILT 2026-07-27, UNVERIFIED IN CAD.** `pfp:skin` +
`C:PFPTHEME` per §8; `C:PFPSCALE` for the size question. The property names,
the applies-to lists, the `Color` forms and the font-size sign are all settled
from the vendor reference. What still needs one CAD run: whether `'font` mode
paints the two footer labels (the strongest single signal — Label supports both
colours and a real size, so it is the control the whole design rests on),
whether the geometry setters exist, and what the eyedropper says the RGB rows
should be if `'theme` is ever wanted for the light side.

---

## 10. Invariant — the command line stays independent

**The palette ADDS commands. It never modifies existing ones.** Every command
must keep working from the command line with the palette closed, unloaded, or
absent.

- **Entry points are frozen:** `C:PFSETUP`, `C:PFLABEL`/`PFL`,
  `C:PFXLABEL`/`PFX`, `C:PFINVERT`/`PFI`, `C:PFLABELSET`, `C:PFREMOVE`,
  `C:PFINDEX` (added 2026-07-27 — additional, replaces nothing). The
  `C:PF*RUN` commands (Phase 2) and `C:PFPVERB` (Phase 3) are *additional*
  names alongside them, not replacements.
- **Modals stay working** until the palette provably replaces each one, then are
  demoted to fallbacks for a session without OpenDCL — never deleted.
- **Exactly one shared-code edit is permitted:** the `*pf-preset-target*` graft
  into `pfs:choose-or-place`. With the global nil — every command-line run —
  behaviour must be byte-identical to today's modal pick.
- **`*pf-preset-target*` must be read and cleared in the SAME `setq`**, copying
  `pf:zoom-resolve` (`pftools-lib.lsp:1030-1034`). Otherwise a palette run that
  dies on Esc or a busy command line leaks a stale target into the next
  *command-line* run, which then silently labels the wrong profile instead of
  prompting. This is the single most likely way the palette breaks the
  commands.
- **Deleting `*pf-zoom-to*`** (when `chkbxZoom` moves into the ticket) is safe:
  it is always nil on a command-line run, so `pf:zoom-resolve` just returns its
  `default` — nil for PFLABEL/PFINVERT, T for PFXLABEL, same as today.
- **No reactor rewrites command behaviour.** The only one planned is
  `:vlr-commandEnded` filtered to `PF*` → `pfp:refresh`, which reads the
  registry and never touches the command.

**The engine regression gate is what proves this, and it has never been run.**
The engines were extracted before any palette work; if command-line output
changed, it changed already. Run it in Phase 0 — otherwise the first engine bug
found after Phase 2 gets blamed on the palette.

---

## 11. Divergences from `pfpalette.lsp`

**(a) `metaList` may overflow — RESOLVED, no action.** `pfp:meta-rows` emits
**9** rows for an anchored line and 4 for a registered one, estimated at ~216px
against a 168px panel. The field test (PALETTE-TESTING 2.11) found all 9 rows
visible with **no scrollbar and room to spare** — the ~24px row estimate was too
tall. Nothing to grow, nothing to accept.

**(b) Pick buttons 4 and 5 are crossed** — §5.

**(c) Column widths may not fill the panels.** `OnInitialize` sets `metaList` to
110 + 410 = 520 and `lvwLinkage` to 90 + 440 = 530. Compare against the actual
panel widths; anything left over is dead space that grows when the panel
stretches.

Columns live in `c:pfsuite/pfsPalette#OnInitialize` and nowhere else —
`AddColumns` is additive, so a width change is an edit to that one call, never a
second call from a refresh path.

**(d) UI vocabulary is "Anchored" / "Registered"** — never "placed" / "stub",
whatever the internal symbols say.
