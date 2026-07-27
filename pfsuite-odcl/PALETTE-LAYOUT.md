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
| Min Width | `570` | **defect — see below** |
| Min Height | `700` | **defect — see below** |
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
| `tvwLines` | 0/0 | 0/1 | fixed width, full height |
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
| `lblProject` | Label | Project root. Captioned by `pfp:seed-labels`. | ✅ |
| `lblCounts` | Label | Registry tallies. Captioned by `pfp:seed-labels`. | ✅ |
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
`pflabel:build-lines`, `pflabel:gather-inlets` and `pflabel:pending` are all
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
unverified assumption: that a closed form still receives events.** If it
doesn't, nothing can reopen the palette and it stays dead until someone types
`PFPALETTE`, which is worse than today's stale-data behavior. Test L3 in
`../pfpalette/pfp-proof.lsp` settles it. Fallbacks if it fails: `dcl-Form-Hide`
instead of `Close` (unattested in the samples — needs its own check), or a
`vlr-docmanager-reactor`, which lives outside the form and always fires.

**The handler only exists where the suite is loaded.** AutoLISP namespaces are
per-document, so in a drawing that never ran `pftools-load.lsp` the
`OnDocActivated` function is undefined and nothing fires at all — the palette
keeps showing the previous drawing's data. A `boundp` guard inside the handler
doesn't help with this; only auto-loading the suite per document does.

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

**Decision pending.** "Native" for a docked palette means matching the host, and
the host theme moves: `COLORTHEME` (0 dark / 1 light) is user-switchable at any
time, so a hardcoded scheme is wrong the moment someone flips it.

| Tier | Approach | Cost |
|---|---|---|
| **1 (recommended)** | Set nothing; every control inherits Windows/AutoCAD theming. | Abandons the dark mockup scheme. |
| 2 | A system-color enumeration value on the form and panels. `-24` may already be one. | Only covers what OpenDCL enumerates. |
| 3 | Runtime switch: read `(getvar "COLORTHEME")` in `pfp:refresh` and set colors. | **Requires a runtime color API that is not verified.** |

No color functions appear in the `Opendcl_Reference` samples, which attest only
`dcl_Control_SetCaption` / `SetEnabled` / `SetText` / `SetValue`. If no runtime
color API exists, colors are design-time only and Tier 3 is impossible.

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

**Phase 1 — prove the deferred fire.** A throwaway button calling
`vla-SendCommand` on the active document to run a trivial drawing command.
Verify: real command context, undo group intact, palette survives the round trip,
`CMDACTIVE` gating behaves. **Everything after this is blocked on it** — it's the
one piece that can't be reasoned out from the samples.

**Phase 2 — the ticket channel.** Thin `C:PFLABELRUN` / `C:PFINVERTRUN` /
`C:PFXLABELRUN` reading a global ticket and calling `pfX:run` under
`pf:run-command`. Plus the `*pf-preset-target*` graft into `pfs:choose-or-place`
— consumed and cleared at the top, so the deferred command never opens `pf_pick`.
That global was never implemented (`Low_Priority_issues.md:4`) and
`pfs:choose-or-place` **may write** (an unplaced pick places on the fly), so a
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

**Phase 6 — colors.** Per §8, once the dropdown question is settled.

---

## 10. Invariant — the command line stays independent

**The palette ADDS commands. It never modifies existing ones.** Every command
must keep working from the command line with the palette closed, unloaded, or
absent.

- **Entry points are frozen:** `C:PFSETUP`, `C:PFLABEL`/`PFL`,
  `C:PFXLABEL`/`PFX`, `C:PFINVERT`/`PFI`, `C:PFLABELSET`, `C:PFREMOVE`. The
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

**(a) `metaList` may overflow.** `pfp:meta-rows` emits **9** rows for an anchored
line and 4 for a registered one. At ~24px per row that's ~216px. Check the
panel's Height in Studio — if it's under that, `metaList` scrolls on every
anchored line. Either accept the scroll or grow the panel and push `lvwLinkage`
down.

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
