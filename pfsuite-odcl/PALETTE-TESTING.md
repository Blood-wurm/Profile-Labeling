# pfsPalette — Shakedown Checklist

Run on a **scratch copy** of a real job. Goal: break it. Every test names its
expected result — anything else is a finding. Work top to bottom; later phases
depend on earlier state.

Scope is the palette only. Command behaviour (PFSETUP / PFLABEL / PFXLABEL /
PFINVERT) is [`../pfsuite-md/TESTING.md`](../pfsuite-md/TESTING.md). Geometry and
control names are [`PALETTE-LAYOUT.md`](PALETTE-LAYOUT.md).

**Bring:** a drawing with a populated registry (≥2 utility types, ≥1 anchored
and ≥1 registered-only line), a **clean drawing that has never seen PFTOOLS**
(§3 needs it), and a second drawing to switch to.

**Gate:** §4 must pass before Phases 2-4 of the wiring plan start. If the
deferred fire doesn't work, no palette verb can ever work and the design needs
rethinking rather than debugging.

---

## 0. Load

- [ ] 0.1 `*pftools-dir*` in `pftools-load.lsp` points at the **deployed**
      folder, not the repo. It ships hardcoded — wrong path and nothing loads.
- [ ] 0.2 `(load ".../pftools-load.lsp")` → banner lists PFSETUP, PFLABEL (PFL),
      PFXLABEL (PFX), PFINVERT (PFI), PFLABELSET, PFPALETTE. No load errors.
- [ ] 0.3 `PFPALETTE` → the palette appears and **docks** left or right.
      `Dockable Sides` is Left + Right only; it must refuse top/bottom.
- [ ] 0.4 `PFPALETTE` again → it closes. The command is a toggle.

**If 0.3 prints "could not load the OpenDCL project":** `pfp:odcl-path` and the
actual `.odcl` location disagree. The file is at `pfsuite-odcl/pfsuite.odcl` and
the function must carry that folder segment.

---

## 1. Studio values (Phase 0)

Read off `pfsPalette` and the tab controls in Studio before testing behaviour.

- [ ] 1.1 `Min Width` ≥ 900 and `Min Height` ≤ `Height` (670). **Shipped
      values were 570 / 700 — both wrong.** `Min Height` above `Height` means
      the design surface never matches the runtime.
- [ ] 1.2 `tarLines`: `Use Top From Bottom` 0 / `Use Bottom From Bottom` **0**
      (capped). `detailsList`: **0 / 1** (the stretcher). Shipped state had
      `tarLines` stretching and the list fixed — backwards.
- [ ] 1.3 Each frame and its radio group carry **identical** anchor flags
      (`frmLabel`/`optLabel`, `frmTools`/`optTools`, `frmOptions`/`optRun`).
      Frames don't move their children.
- [ ] 1.4 Pick buttons read left to right `.cl`, `INV.pro`, `TOP.pro`,
      `EXIST .tin`, `DESIGN .tin` — matching `pfp:fill-linkage`'s row order.
      **Shipped order had DESIGN and EXIST crossed.**
- [ ] 1.5 No two controls share a `(Name)`. Paths are
      `pfsuite/pfsPalette/<name>`, so a duplicate makes one unaddressable.

### 1.6 The resize test (root README §8)

- [ ] 1.6a Drag the palette **as narrow as it will go**. Every button on the
      Registry tab stays visible. Nothing vanishes off the left edge.
- [ ] 1.6b Drag it as **short** as it will go. The footer stays put; the bottom
      button rows stay on-canvas.
- [ ] 1.6c Drag it tall and wide again. Panels grow, buttons keep their size,
      no overlap.

> This is the open §8 finding — "buttons vanished with anchoring provably
> identical to buttons that survived." The theory is that `Min Width` 570 let
> right-anchored controls compute a negative x while left-anchored ones
> survived. **If 1.1 is fixed and 1.6a now passes, §8 is closed.** If it still
> fails at a legal width, the cause is something else and §8 stays open.

---

## 2. Milestone 2 regression (what already works)

Everything here passed a field test once. Re-run it after any Studio change —
these are the tests that catch a rename or a re-anchor breaking live wiring.

- [ ] 2.1 `PFPALETTE` on the populated drawing → `tvwLines` shows utility types
      as parents with lines beneath, and the **first parent is selected**.
- [ ] 2.2 The tree paints **immediately** — no need to move or resize the
      palette first. (The §4a deferred-paint failure: data written in
      `OnInitialize` doesn't paint. Data belongs in `pfp:refresh`.)
- [ ] 2.3 `lblProject` reads `Project: <root>`, or `(none)`.
- [ ] 2.4 `lblCounts` reads `N lines (P anchored, R registered)` and the numbers
      match the drawing.
- [ ] 2.5 Select an **anchored** line → `metaList` fills with 9 rows: Type,
      Line, State=`Anchored`, Datum, Start sta, H plot, V plot, Centerline,
      Material.
- [ ] 2.6 Select a **registered-only** line → 4 rows, State=`Registered`.
- [ ] 2.7 Select a **Type parent** → both panels clear. No stale rows.
- [ ] 2.8 `lvwLinkage` shows five rows in order: `Centerline (.cl)`,
      `Invert _INV .pro`, `Crown _TOP .pro`, `Existing .tin`, `DESIGN_* .tin`.
      Unbound slots read `(not set)`, never blank.
- [ ] 2.9 Vocabulary check: the UI says **Anchored / Registered**. Never
      "placed", never "stub".

### 2.10 Column stacking — probe deliberately

`AddColumns` is **additive**, and `C:PFPALETTE` closes the form rather than
hiding it, so the next open re-runs `OnInitialize`.

- [ ] 2.10 Toggle `PFPALETTE` off and on **three times**. `metaList` still has
      exactly **2** columns (`Property` | `Value`) and `lvwLinkage` exactly 2
      (`Item` | `File`).

> If columns stack to 4 and 6, closing does not destroy the controls, and
> `OnInitialize` cannot be the only guard. Fix is a `*pfp-columns-done*` flag,
> not moving the call.

### 2.11 metaList overflow

- [ ] 2.11 With an anchored line selected, all 9 rows are reachable. Note
      whether the panel **scrolls** — 9 rows at ~24px is ~216px against a
      168px panel. A scrollbar is acceptable; clipped rows with no scrollbar
      is a finding.

---

## 3. The write-free contract

**The single most important palette test.** Root README §5: opening the palette
must not dirty a clean drawing. `pfa:nod-dict` and `pfa:ledger-dict` take
`create` nil on every read path precisely so this holds.

- [ ] 3.1 Open the **clean drawing that has never seen PFTOOLS**. Confirm
      `(getvar "DBMOD")` → `0`.
- [ ] 3.2 Load the suite. `DBMOD` still `0`.
- [ ] 3.3 `PFPALETTE`. Tree is empty, `lblCounts` reads `0 lines`.
      **`DBMOD` still `0`.**
- [ ] 3.4 Click around every control that responds. `DBMOD` still `0`.
- [ ] 3.5 Close the palette, close the drawing. **AutoCAD does not offer to
      save.**

> Any non-zero `DBMOD` means a read path is creating a dictionary. That breaks
> the modeless contract and every handler built on it. Stop and find the
> writer before continuing.

---

## 4. Phase 1 — the deferred fire (the gate)

Load the proof: `(load (strcat *pftools-dir* "pfpalette/pfp-proof.lsp"))`.

**Studio first:** tick `btnHelp` → Events → `Clicked`. Use Studio's generated
handler name — if it differs from `c:pfsuite/pfsPalette/btnHelp#OnClicked`,
rename the defun in the proof to match. A handler with the wrong name never
fires and looks exactly like a broken `SendCommand`.

- [ ] 4.1 `PFPALETTE`, click **Help**. The `=== PHASE 1 ===` banner prints. If
      nothing prints at all, the event isn't ticked or the name is wrong —
      neither is a `SendCommand` failure.
- [ ] 4.2 **[1] PASS** — `(command)` from the modeless handler drew nothing.
      *A FAIL here means the modeless restriction isn't what the design assumes
      and the whole defer approach needs revisiting.*
- [ ] 4.3 **[2] SENT** — `PFPTEST` queued.
- [ ] 4.4 **[3] PASS** — the command knows it arrived from the click.
- [ ] 4.5 **[4] PASS** — a line drew at 0,0 → 120,90.
- [ ] 4.6 **[5] PASS** — `getpoint` prompted and returned. *This is the
      strongest signal: `getpoint` is illegal modeless, so if it prompts, this
      is unambiguously a real command context.*
- [ ] 4.7 The Help button **greyed** during the run and came back enabled.
- [ ] 4.8 Type `U` **once** → the proof line disappears. One undo step peels
      the whole thing. If it takes two, the undo group didn't wrap.
- [ ] 4.9 Start a command (e.g. `LINE`), leave it running, click Help →
      `pfp:defer` **refuses** with "command line busy". It must not stack input
      behind a live command.

**If §4 fails, stop.** Phases 2-4 are all built on this channel.

---

## 5. Lifecycle

Studio: tick `DocActivated` and `EnteringNoDocState` on **`pfsPalette`**
(form level, not a control).

- [ ] 5.1 **L1** — with the palette open, switch to another drawing **that has
      the suite loaded**. `[lifecycle] OnDocActivated` prints and the tree
      repopulates from the new drawing.
- [ ] 5.2 **L1b** — switch to a drawing where the suite was **never loaded**.
      *Expected: nothing fires and the palette keeps showing the previous
      drawing's data.* AutoLISP namespaces are per-document, so the handler
      doesn't exist there. **This is a known limitation, not a bug** — record
      it; the only fix is auto-loading the suite per document.
- [ ] 5.3 **L2** — close all drawings. `OnEnteringNoDocState` prints and the
      palette **closes**. It must not sit on the start screen showing the last
      drawing's registry.
- [ ] 5.4 **L3** — open a drawing. `[L3] PASS` prints and the palette returns.

> **L3 is the real unknown.** A closed form may not receive events at all. If
> L3 fails, `EnteringNoDocState` → Close leaves the palette dead until someone
> types `PFPALETTE` — worse than today's stale data. Fallbacks: `dcl-Form-Hide`
> instead of Close (unattested — needs its own check), or a
> `vlr-docmanager-reactor`, which lives outside the form and always fires.

- [ ] 5.5 Close the palette **deliberately** with `PFPALETTE`, then switch
      drawings. It must **stay closed** — `DocActivated` must not resurrect a
      palette the user dismissed. *(Requires the `Close` event ticked and
      `*pfp-was-open*` cleared in its handler. If that isn't wired yet, expect
      this to fail and record it.)*

---

## 6. Results

| # | Test | Result | Note |
|---|---|---|---|
| 1.1 | Min W/H corrected | | |
| 1.6a | Narrow resize, no vanishing | | closes §8? |
| 2.2 | Paints without moving | | |
| 2.10 | Columns don't stack | | |
| 3.3 | DBMOD stays 0 | | **contract** |
| 4.2 | [1] modeless drew nothing | | |
| 4.6 | [5] getpoint returned | | **the gate** |
| 4.8 | One U peels it | | |
| 5.3 | L2 closes on start screen | | |
| 5.4 | L3 reopens | | **the unknown** |

## 7. Triage

| Symptom | Look at |
|---|---|
| Palette won't load | `pfp:odcl-path` folder segment; `*pftools-dir*` |
| Nothing prints on click | Event not ticked, or handler name mismatch |
| Tree empty until moved | Data written in `OnInitialize` instead of `pfp:refresh` |
| Columns multiply | `AddColumns` called more than once — needs a done-flag |
| Buttons vanish on resize | `Min Width` below the button row's right edge |
| Drawing dirty after opening | A read path passing `create` T — breaks §5 |
| `[5]` fails but `[4]` passes | Command context is partial; `SendCommand` may need a different form |
| L3 fails | Closed forms don't get events — switch to Hide or a reactor |
