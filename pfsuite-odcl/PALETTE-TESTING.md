# pfsPalette — Shakedown Checklist

> # ⚠ AFTER EVERY STUDIO SAVE, RUN `PFPRELOAD`
>
> `dcl-Project-Load` **"does nothing if the project is already loaded, unless
> the optional ForceReload argument is T"** (vendor docs). `pfp:ensure` passes
> one argument and guards on `*pfp-loaded*`, a session-long global. So once the
> project is in memory, **saving in Studio changes nothing** — every
> `PFPALETTE` keeps showing the version loaded first, until AutoCAD restarts.
>
> **This silently invalidated measurements on 2026-07-27.** A `Background
> Color` edit had no effect; `btnHelp` still displayed `<<PROBE-A>>`, a caption
> written at runtime by a probe; and `PFPREAD` reported `lblProject` at
> 41,632 199x30 while Studio showed 16,635 250x25. That last one was recorded
> as a possible runtime-vs-design anchoring fault. It was not. It was two
> different versions of the same file.
>
> **Any result gathered after a Studio save without `PFPRELOAD` is void.**
> Re-run it. This applies retroactively to everything in §1.7.

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

> **§4 PASSED 2026-07-27 — the gate is open.** `[1]`–`[5]` all clean, including
> `getpoint` prompting and returning. `pfp:cmd-idle-p` and `pfp:defer` have been
> promoted out of `pfp-proof.lsp` into `pfpalette.lsp` §2 and are now the one
> channel every palette verb uses. Run-1 results and what to do next: **§6**.

---

## 0. Load

- [x] 0.1 `*pftools-dir*` in `pftools-load.lsp` points at the **deployed**
      folder, not the repo. It ships hardcoded — wrong path and nothing loads.
- [x] 0.2 `(load ".../pftools-load.lsp")` → banner lists PFSETUP, PFLABEL (PFL),
      PFXLABEL (PFX), PFINVERT (PFI), PFLABELSET, PFPALETTE. No load errors.
- [xpfpal] 0.3 `PFPALETTE` → the palette appears and **docks** left or right.
      `Dockable Sides` is Left + Right only; it must refuse top/bottom.
- [x] 0.4 `PFPALETTE` again → it closes. The command is a toggle.
- [ ] 0.5 **Runtime file versions match.** NEW 2026-07-27 — they currently do
      **not**:

      runtime/OpenDCL.x64.25.arx   9.3.0.1
      runtime/ENU/Runtime.Res.dll  9.1.5.2

      The resource DLL is two minor versions behind the ARX that loads it, and
      `Runtime.Res.dll` is where control rendering resources live. Found while
      checking the runtime against the 8.0.0.13 label-colour regression, not
      by any test in this plan. Reinstall a matched OpenDCL runtime and re-run
      §1.7. Check with:

      `Get-ChildItem runtime\*.arx, runtime\ENU\*.dll | % { $_.Name, $_.VersionInfo.FileVersion }`

**If 0.3 prints "could not load the OpenDCL project":** `pfp:odcl-path` and the
actual `.odcl` location disagree. The file is at `pfsuite-odcl/pfsuite.odcl` and
the function must carry that folder segment.

---

## 1. Studio values (Phase 0)

Read off `pfsPalette` and the tab controls in Studio before testing behaviour.

- [ ] 1.1 `Min Width` ≥ 900 and `Min Height` ≤ `Height` (670). **Shipped
      values were 570 / 700 — both wrong.** `Min Height` above `Height` means
      the design surface never matches the runtime.
	  tvwLines is not aligned.
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

> **Every test in 1.6 is a FLOATING test.** They are performed by dragging the
> window's edges, which is the undocked path. **`Dockable Sides` is Left +
> Right and docked is the mode this palette is designed to live in — and
> docked layout is tested nowhere.** 0.3 checks only *that* it docks, never
> what the layout does once it has. See 1.7.

### 1.7 The docked layout test — NEW, 2026-07-27

Added because the blank-label hunt turned out to be a docking fault, after
name, rect, and setter checks all came back clean.

**Symptom:** docked, a **gray box** sits roughly where `lblProject` and
`lblCounts` belong. Drag the palette out of the dock and the box goes away.

> **2026-07-27 — these are TWO faults, and the box is the lesser one.**
> Floating: the box is gone and there is **still no text**. So the labels
> render no glyphs in *either* state, and the gray box is a separate
> docked-only overlay. It is **one rectangle** spanning both labels, not two —
> so it is something covering them (prime suspect: `tabMain`'s lower edge when
> docked), not the labels drawing their own backgrounds.
>
> **Fault 1 — the labels never paint text. This is the real bug.** Ruled out
> so far: name (`PFPDIAG` 29/29), rect (correct in Studio *and* at runtime),
> parent (form-level, confirmed in Studio), visibility (`Visible T`),
> enablement (`Enabled T`), caption (`lblCounts` held live registry counts),
> setter (`SetCaption` visibly repaints `btnHelp`), vertical clipping
> (`btnHelp` sits *lower* at y 650–675 and paints). What is left is
> **fore colour matching the background**, or a **broken font** — neither ever
> checked. ~~Run `PFPINK`, **floating**.~~
>
> **Answered from the vendor docs instead, and `PFPINK` is deleted.** It was
> both: `Foreground Color` -24 (Transparent) and `Font Size` 0. `PFPINK`
> would have read `GetForeColor`/`GetBackColor` off `btnHelp` — a Text Button
> that supports neither — raising four uncatchable modal dialogs to answer a
> question the [Label reference
> page](https://www.opendcl.com/HelpFiles/ENU/Reference/Control/Label.htm)
> settles for free. Replacement probe: `PFPTHEME`, whose reads are gated by
> `pfp:type-can`.
>
> The earlier `SetForeColor` probe does **not** count: it was run docked,
> underneath the gray box, where nothing could have shown regardless. It
> proved the call returns `ok` and nothing more.
>
> **Fault 2 — the docked gray box.** Cosmetic next to fault 1.
>
> ---
>
> ## ✅ RESOLVED 2026-07-27 — labels paint. Two causes, one of them procedural.
>
> **The blocker was the stale project cache**, not any single property. Studio
> edits were never reaching the runtime (see the banner at the top of this
> file), so every fix attempted during the hunt was tested against the version
> of the `.odcl` loaded at the start of the session. `PFPRELOAD` + the colour
> change together produced working labels.
>
> **Still worth settling, cheaply:** which of the two actually mattered.
> Set `Background Color` back to **-24** on `lblProject` only, `PFPRELOAD`,
> and look. If it still paints, transparent backgrounds are fine and the whole
> cause was staleness — which matters for §8, because it decides whether -24 is
> usable at all. If it goes blank again, -24 is genuinely unusable for Labels
> on a palette and **-16 is the standing rule**. Two minutes, and it converts a
> guess in the record into a fact.
>
> The `Foreground Color` = -19 finding stands either way: it was already -19
> and correct, which is what ruled colour-on-colour out as the sole cause.
>
> ## The investigation, kept for the retro
>
> **Both faults are colour.** Stop testing geometry.
>
> **`-24` is `Transparent`**, not a theme colour — it is the last entry in
> OpenDCL's negative system-colour enumeration, and PALETTE-LAYOUT §8 carried
> it as an undecoded value for the whole project.
>
> **A `Foreground Color` of -24 is transparent text: invisible docked,
> floating, at every size, on every theme.** That matches every observation.
> -24 is easy to set on the wrong property believing it means "default", and
> the form legitimately carries it as a *background*.
>
> The gray box is the same enumeration from the other side — a
> transparent-*background* control that fails to composite when docked paints
> as an opaque rectangle.
>
> **CORRECTION — Label controls have no `Use Visual Style`.** An earlier
> revision of this note prescribed setting it False, from a forum thread about
> the 8.0.0.13 foreground regression. The [Label control
> reference](https://www.opendcl.com/HelpFiles/ENU/Reference/Control/Label.htm)
> lists no such property: a Label has `Background Color`, `Foreground Color`,
> `Border Style`, `Justification`, the `Font*` family, `Visible`, `Enabled`,
> geometry and tooltips. **Nothing overrides a Label's `Foreground Color`,
> which makes that property authoritative — and therefore the prime suspect.**
> Confirmed in the field: the option does not appear on either label.
>
> **CHECK, in Studio, on `lblProject` + `lblCounts`:**
>
> | Property | Bad value | Why it produces exactly this |
> |---|---|---|
> | `Foreground Color` | **-24** | Transparent text. Invisible everywhere |
> | `Foreground Color` | same as background | Invisible without being transparent |
> | `Font Size` | **0** | Background paints, no glyphs |
> | `Background Color` | -24 | Mis-composites when docked → the gray box |
>
> **FIX:** `Foreground Color` = **-19** (Windows button text — theme-tracking),
> `Font Size` to a real value. If the gray box survives, `Background Color` =
> **-16** (button face) rather than transparent.
>
> **No code change.** `pfp:seed-labels` was correct throughout; `lblCounts`
> was holding live registry counts the whole time.
>
> **Lesson for the retro:** name, rect, parent, visibility, enablement, caption,
> setter, clipping and z-order were all probed across five rounds. The vendor's
> own Tips page names this failure mode in two sentences. **Search the docs
> before building the fifth diagnostic.**

That is state-dependent, and nothing static is: not a `(Name)` (`PFPDIAG` says
29/29), not a Studio rect (checked, correct), not a setter (`PFPPROBE` says all
five return `ok`, and the same `SetCaption` visibly repaints `btnHelp`). **A
gray box is not an absent control — it is one that did not paint, or one
covered by something else.**

- [ ] 1.7a Dock the palette left. Run `PFPREAD`. Keep the dump.
- [ ] 1.7b Drag it out to float. Run `PFPREAD` again. **Diff the two.** The
      difference between them is the bug.
- [ ] 1.7c Do the labels paint their text when **floating**? If yes, the
      captions were always landing and this is purely a docked-state fault.
- [ ] 1.7d Docked, with the box visible, run `PFPNUDGE`. Note which step (if
      any) makes `<<NUDGE>>` appear.
- [ ] 1.7e Dock **right** as well as left, and re-check. Both sides ship.

| Evidence | Reading |
|---|---|
| A `PFPNUDGE` step paints the text | **Repaint fault.** That step is the fix |
| `[1] SetEnabled nil/T` is the step that works | The deleted `pfp:repaint` enable-toggle hack was load-bearing **for docking** and was removed on floating-window evidence only |
| No nudge works, but `tabMain`'s rect overlaps the labels' | **Coverage.** `tabMain` extends into the footer band when docked |
| Rects differ docked vs floating | Anchoring resolves differently when docked — the same family as 1.1 / 1.6c |
| Rects identical, captions read back correct, still blank | Neither; escalate — the control is being drawn and discarded |

### 1.7f `PFPREAD` run 1, docked — 2026-07-27

```
lblProject  Caption "<<PROBE-B>>"                        Visible T  Enabled T   41,632  199x30
lblCounts   Caption "66 lines  (4 anchored, 62 registered)"  Visible T  Enabled T  240,630  320x30
btnHelp     Caption "<<PROBE-A>>"                        Visible T  Enabled nil 845,650   70x25
```

**Two results, and the first one closes a test.**

**The data path works and always did.** `lblCounts` holds real registry counts.
Registry read → tally → string build → `SetCaption` is end-to-end correct.
**2.4 was never a wiring failure**, and 2.3 isn't either — `pfp:seed-labels`
needs no change. This is a *rendering* fault, full stop.

**The labels are below their parent's floor.** `btnHelp` reaches x=915 / y=675 —
past the 900 × 670 design size — and paints, so the docked client is bigger
than the design surface and the labels at y≈630 are comfortably inside *it*.
But `tabMain`'s client is documented **896 × 606**, and both labels sit at
`Top` ≈ 630. **In `tabMain`'s coordinate space they are past the bottom edge of
their own parent, and clipped.** `Left 41` fits the same reading: an odd value
against the 10px margin `tabMain` and `tarLines` share, unremarkable as an
inset inside a tab surface.

So the leading cause is **wrong parent, not wrong rect** — the labels belong to
a tab surface rather than the form. `btnHelp` at `Top 650` survives because it
is genuinely form-level, where 650 is legal.

- [ ] 1.7f **In Studio, expand the browser tree.** Are `lblProject` and
      `lblCounts` listed under **`pfsPalette`**, or under Registry / Commands /
      Settings? PALETTE-LAYOUT §1 warns the form-level controls are visible
      only with `pfsPalette` selected — easy to add a control to the wrong
      surface without noticing.
- [ ] 1.7g `PFPMOVE` — relocates `lblProject` to (60,120), legal in either
      coordinate space. If it appears, it was clipped where it lives.

**Two incidentals.** `dcl-Control-GetText` raised a **modal** OpenDCL error
dialog (`Property <Text> not found`) that `vl-catch-all-apply` could not
suppress — those are raised below LISP. It confirms these are Labels
(`Caption`, no `Text`), so `SetCaption` was correct throughout; `GetText` and
`SetText` are out of the probes now. And `btnHelp` reads `Enabled nil` — left
disabled by a Phase 1 proof run that was cancelled at the `getpoint`. Clear it
with `PFPTESTRESET`.

- [x] 1.6a Drag the palette **as narrow as it will go**. Every button on the
      Registry tab stays visible. Nothing vanishes off the left edge.
	  Minimum size is the full width so it doesn't really shrink.
- [x] 1.6b Drag it as **short** as it will go. The footer stays put; the bottom
      button rows stay on-canvas.
- [x] 1.6c Drag it tall and wide again. Panels grow, buttons keep their size,
      no overlap.
	  tvwLines leaves space above as it is stretched.

> This is the open §8 finding — "buttons vanished with anchoring provably
> identical to buttons that survived." The theory is that `Min Width` 570 let
> right-anchored controls compute a negative x while left-anchored ones
> survived. **If 1.1 is fixed and 1.6a now passes, §8 is closed.** If it still
> fails at a legal width, the cause is something else and §8 stays open.
>
> **2026-07-27 — §8 is closed BY CONSTRUCTION, not disproven.** 1.6a passed,
> but the note explains why: with `Min Width` ≥ 900 the form cannot narrow at
> all, so no control can ever compute a negative x. That is consistent with
> the theory and does not test it. Nothing more is owed here — but it means
> the 900px floor is now load-bearing, and anyone who lowers it re-opens §8.
>
> **This has a cost worth naming.** `Dockable Sides` is Left + Right because
> the palette is meant to live as a vertical strip, and a strip with a hard
> 900px floor is a wide one. The floor is forced by the five fixed-width
> Registry button rows (PALETTE-LAYOUT §3: OpenDCL has no layout flow, so a
> fixed-width row cannot redistribute). Making the palette genuinely narrow
> means reflowing those rows — icon buttons, two stacked rows, or a toolbar —
> which is a redesign, not a defect. Log it; don't fix it mid-shakedown.

---

## 2. Milestone 2 regression (what already works)

Everything here passed a field test once. Re-run it after any Studio change —
these are the tests that catch a rename or a re-anchor breaking live wiring.

- [x] 2.1 `PFPALETTE` on the populated drawing → `tvwLines` shows utility types
      as parents with lines beneath, and the **first parent is selected**.
- [x] 2.2 The tree paints **immediately** — no need to move or resize the
      palette first. (The §4a deferred-paint failure: data written in
      `OnInitialize` doesn't paint. Data belongs in `pfp:refresh`.)
- [x] 2.3 `lblProject` reads `Project: <root>`, or `(none)`.
      Blank on the first run; **PASS after `PFPRELOAD`.**
- [x] 2.4 `lblCounts` reads `N lines (P anchored, R registered)` and the numbers
      match the drawing. **PASS after `PFPRELOAD`.**

> **Both labels blank, silently, is diagnostic.** `pfp:seed-labels` runs
> *before* `pfp:fill-tree` inside one `vl-catch-all-apply`, and the tree filled
> (2.1, 2.2 passed) — so `seed-labels` completed without throwing. A caption
> built by `(strcat "Project: " …)` can never be the empty string. So the
> caption was computed and never reached the control, and nothing errored.
>
> That is the signature of a **`(Name)` mismatch**: an OpenDCL control symbol
> the loaded project never defined evaluates to **nil** — AutoLISP returns nil
> for an unbound symbol rather than erroring — and `dcl-Control-SetCaption` on
> nil does nothing and reports nothing. It is the one failure mode that leaves
> no trace at runtime, which is why 1.5 (no duplicate/missing names) is not
> optional.
>
> **`PFPDIAG` RAN — AND THE NAMES ARE FINE.** With the palette open, **29 of
> 29 controls resolve**, `lblProject` and `lblCounts` among them. `pfp:refresh`
> is called *after* `dcl-Form-Show` returns (the 2.2 fix), so both are live
> controls at the moment `SetCaption` reaches them.
>
> **So the caption lands on a real control and you still can't see it. The
> cause is geometry, not naming.** Look at each label's `Width` and `Left` in
> Studio — a label auto-sized to a placeholder, or left at an empty design-time
> caption, ends up a few pixels wide and clips its text to nothing. Useful
> control: `btnHelp` sits in the same footer band and is provably visible (you
> clicked it throughout §4), so the band and its anchoring are sound and the
> fault is each label's own rect.
>
> **Studio checked 2026-07-27: `Left`, `Width`, `Height` and the anchor flags
> are all correct.** So the name is right, the rect is right, the caption is
> computed and accepted — and nothing shows. Everything findable by reading
> properties has been read.
>
> **Run `PFPPROBE`** (`pfpalette.lsp` §6, palette open). It drives the controls
> directly and reports which API calls exist and succeed; `btnHelp` is the
> control, being provably visible and provably caption-bearing. Then read the
> palette against this:
>
> | What you see | What it means |
> |---|---|
> | `[A]` changes the Help button, `[B]` shows nothing | `SetCaption` works here — the fault is specific to the labels |
> | `[A]` also does nothing | `SetCaption` is wrong for this build; every caption in the suite is suspect |
> | `[C]` shows text where `[B]` didn't | **not Labels** — they're text-bearing controls needing `SetText`. Fix `pfp:caption` |
> | text appears only after `[D]` | `Visible` is unchecked in Studio |
> | text appears only after `[E]` | fore colour matches the background — §8 colours, not a wiring fault |
> | `[C]`/`[D]`/`[E]` report `FAILED -- no function definition` | that API doesn't exist under that name; rules the branch out, nothing more |
> | nothing at all changes | duplicate `(Name)` — 1.5. Both symbols resolve, one is unaddressable |
>
> `[E]` deserves suspicion on priors: PALETTE-LAYOUT §8 has colours **undecided**,
> the form carries background `-24`, and a dark mockup scheme was targeted.
> Dark text on a dark footer is invisible with every property looking correct.
>
> Still open regardless: `PFPDIAG` proves a name **resolves**, not that it is
> **unique**. A duplicate `(Name)` leaves both resolving while one is
> unaddressable — that is 1.5, and it is still unrun.
>
> `pfp:caption` now reports a nil control by name instead of swallowing it, so
> whatever the cause here, this class of failure cannot recur silently.
- [x] 2.5 Select an **anchored** line → `metaList` fills with 9 rows: Type,
      Line, State=`Anchored`, Datum, Start sta, H plot, V plot, Centerline,
      Material.
- [x] 2.6 Select a **registered-only** line → 4 rows, State=`Registered`.
- [ ] 2.7 Select a **Type parent** → both panels clear. No stale rows.
- [x] 2.8 `lvwLinkage` shows five rows in order: `Centerline (.cl)`,
      `Invert _INV .pro`, `Crown _TOP .pro`, `Existing .tin`, `DESIGN_* .tin`.
      Unbound slots read `(not set)`, never blank.
- [x] 2.9 Vocabulary check: the UI says **Anchored / Registered**. Never
      "placed", never "stub".

### 2.10 Column stacking — probe deliberately

`AddColumns` is **additive**, and `C:PFPALETTE` closes the form rather than
hiding it, so the next open re-runs `OnInitialize`.

- [x] 2.10 Toggle `PFPALETTE` off and on **three times**. `metaList` still has
      exactly **2** columns (`Property` | `Value`) and `lvwLinkage` exactly 2
      (`Item` | `File`).

> If columns stack to 4 and 6, closing does not destroy the controls, and
> `OnInitialize` cannot be the only guard. Fix is a `*pfp-columns-done*` flag,
> not moving the call.
>
> **2026-07-27 — passed, and now explained.** `PFPDIAG` reads **0 of 29**
> controls with the palette closed and **29 of 29** open: `dcl-Form-Close`
> destroys the children outright. So each open genuinely rebuilds from nothing
> and `AddColumns` starts fresh — the additive behaviour never gets a chance to
> accumulate. **Do not add `*pfp-columns-done*`.** It would suppress the
> rebuild that the second open actually needs, turning a passing test into
> columnless list panels.

### 2.11 metaList overflow

- [x] 2.11 With an anchored line selected, all 9 rows are reachable. Note
      whether the panel **scrolls** — 9 rows at ~24px is ~216px against a
      168px panel. A scrollbar is acceptable; clipped rows with no scrollbar
      is a finding.
	  No need for scroll information fits easily.

---

## 3. The write-free contract

**The single most important palette test, and it has never actually run.** Root
README §5: opening the palette must not dirty a clean drawing. `pfa:nod-dict`
and `pfa:ledger-dict` take `create` nil on every read path precisely so this
holds.

> **2026-07-27 — this section was rewritten because its precondition was
> wrong.** The original 3.1 demanded `(getvar "DBMOD")` → `0` on a freshly
> opened drawing; the field test read **5**, and everything below it stalled.
> That is not a finding. `DBMOD` 5 is `1` (database modified) + `4` (variable
> modified), and opening a drawing can set both on its own before any LISP
> loads. **`DBMOD` 0 is not reachable in general, and the contract never
> depended on it** — what §5 requires is that the palette *changes nothing*.
> So the test is now a **delta**: mark, act, compare. `C:PFPDBMOD` keeps the
> bookkeeping — the first call marks, every later call reports `old -> new`
> and whether it moved.

- [ ] 3.1 Open the drawing that has never seen PFTOOLS. Load the suite, then
      `PFPDBMOD` → prints `mark set at N`. **Any N is fine.** N is the
      baseline, not a result.
- [ ] 3.2 `PFPALETTE`. Tree is empty, `lblCounts` reads `0 lines`.
      `PFPDBMOD` → **UNCHANGED**.
- [ ] 3.3 Click every control that responds — both tabs, tree nodes, both list
      panels. `PFPDBMOD` → **UNCHANGED**.
- [ ] 3.4 Toggle the palette off and on twice more. `PFPDBMOD` →
      **UNCHANGED**.
- [ ] 3.5 Close the palette, close the drawing. **AutoCAD does not offer to
      save** — *unless it would have anyway*. If the baseline N was non-zero
      the save prompt is expected and proves nothing in either direction.
      3.2–3.4 are the real test.

> A **CHANGED** on 3.2, 3.3 or 3.4 means a read path is creating a dictionary.
> That breaks the modeless contract and every handler built on it. Stop and
> find the writer before continuing.
>
> Visit **both tabs** during 3.3. Only the Registry read paths are proven
> write-free today; Phase 4 adds gather calls to the Commands tab that are
> not — `pfxl:discover` in particular is a writer (PALETTE-LAYOUT §6).

### 3.6 Run 1, clean drawing — 2026-07-27

```
PFPDBMOD  -> mark set at 29
PFPALETTE -> Usage: (acad_strlsort <list of strings>)      <-- BUG, fixed
PFPDBMOD  -> 29 -> 29   UNCHANGED -- write-free.
```

**PASS, and it found a bug on the way.**

**`UNCHANGED` proves the guard that matters most.** Opening the palette on a
drawing with no PFTOOLS data ran `pfa:all-anchors` and `pfa:stub-list`, and
`pfa:stub-list` reaches `pfa:nod-dict` with `create` nil. It returned nil
**without creating the NOD dictionary** — which is the exact failure the whole
contract exists to prevent, and the one that would have dirtied a drawing the
user only looked at.

**But it proves less than the section asks for.** With an empty registry the
tree had nothing to select, so `tvwLines#OnSelChanged` never fired and none of
`pfa:read-attribs`, `pfa:meta-get`, `pfa:files-get` or `pfa:ledger-dict` ran.
`pfa:ledger-dict` has its own `create` flag and is **still unproven**.

- [x] 3.7 **Repeat 3.1–3.4 on the populated drawing**, selecting several
      anchored *and* registered lines so both panels fill. That is the only way
      to exercise the ledger and anchor reads. A non-zero baseline is expected
      and fine — the delta is the test.

### 3.8 Run 2, populated drawing — 2026-07-27  ✅ §3 CLOSED

```
PFPDBMOD  -> mark set at 21
PFPALETTE -> (no acad_strlsort banner -- the 3.6 guard holds)
             clicked through the tree and both panels
PFPDBMOD  -> 21 -> 21   UNCHANGED -- write-free.
```

**The write-free contract is proven on both a clean and a populated drawing.**
Between the two runs the palette exercised `pfa:all-anchors`,
`pfa:read-attribs`, `pfa:stub-list`, `pfa:nod-dict` with `create` nil, and —
via `tvwLines#OnSelChanged` on real rows — `pfa:meta-get`, `pfa:files-get` and
`pfa:ledger-dict`, also with `create` nil. Nothing wrote.

> **Scope of the claim.** This covers the **Registry tab read paths as they
> exist today**. It is not a standing guarantee. Phase 4 adds gather calls to
> the Commands tab that are *not* write-free — `pfxl:discover` merges
> crossings, rewrites SCOPE and files GEOM with `write-p` T (PALETTE-LAYOUT
> §6). **Re-run §3 after every new read path is wired**, which is why the
> section is a `PFPDBMOD` delta rather than a one-time sign-off.

**Both gates are now open.** §4 (deferred fire) and §3 (write-free) were the
two things Phases 2–4 could not be built on top of without. Phase 2 may start.

**BUG FOUND — `pfa:registry` on an empty registry.** `acad_strlsort` rejects
nil with a usage banner, so a clean drawing printed a spurious command-line
error on every palette open. Guarded at
[`pfanchor.lsp:593`](../pfanchor/pfanchor.lsp#L593); non-empty behaviour
unchanged. **Nobody had ever run the registry against zero rows** — the palette
was only opened on populated drawings, which is precisely the blind spot §3
exists to cover. It also means the drawing was never in danger: the write-free
result stands, this was noise, not a write.

---

## 4. Phase 1 — the deferred fire (the gate)

Load the proof: `(load (strcat *pftools-dir* "pfpalette/pfp-proof.lsp"))`.

**Studio first:** tick `btnHelp` → Events → `Clicked`. Use Studio's generated
handler name — if it differs from `c:pfsuite/pfsPalette/btnHelp#OnClicked`,
rename the defun in the proof to match. A handler with the wrong name never
fires and looks exactly like a broken `SendCommand`.

- [x] 4.1 `PFPALETTE`, click **Help**. The `=== PHASE 1 ===` banner prints. If
      nothing prints at all, the event isn't ticked or the name is wrong —
      neither is a `SendCommand` failure.
- [x] 4.2 **[1] PASS** — `(command)` from the modeless handler drew nothing.
      *A FAIL here means the modeless restriction isn't what the design assumes
      and the whole defer approach needs revisiting.*
- [x] 4.3 **[2] SENT** — `PFPTEST` queued.
- [x] 4.4 **[3] PASS** — the command knows it arrived from the click.
- [x] 4.5 **[4] PASS** — a line drew at 0,0 → 120,90.
- [x] 4.6 **[5] PASS** — `getpoint` prompted and returned. *This is the
      strongest signal: `getpoint` is illegal modeless, so if it prompts, this
      is unambiguously a real command context.*
	  === PHASE 1 deferred-fire proof ===
[handler] CMDACTIVE=0  CMDNAMES=""
  [1] PASS  (command) from the handler drew nothing, as expected.
Command: *Cancel*
Command: PFPTEST
[command] CMDACTIVE=0  CMDNAMES=""
  [3] PASS  arrived from the palette click, not the keyboard.
  [4] PASS  (command) drew inside one undo group -- type U once to verify.
  [5] Pick any point to prove interactive input:
  [5] PASS  getpoint returned -- real command context confirmed.
=== end of proof ===
Command:
  [2] SENT  PFPTEST queued -- watch for its report below.
PFPTEST
[command] CMDACTIVE=0  CMDNAMES=""
  [3] ----  run directly (no palette click) -- context test only.
  [4] PASS  (command) drew inside one undo group -- type U once to verify.
  [5] Pick any point to prove interactive input: *Cancel*
- [x] 4.7 The Help button **greyed** during the run and came back enabled.
- [x] 4.8 Type `U` **once** → the proof line disappears. One undo step peels
      the whole thing. If it takes two, the undo group didn't wrap.
- [x] 4.9 Start a command (e.g. `LINE`), leave it running, click Help →
      `pfp:defer` **refuses** with "command line busy". It must not stack input
      behind a live command.
=== PHASE 1 deferred-fire proof ===
[handler] CMDACTIVE=1  CMDNAMES="PLINE"
  [1] PASS  (command) from the handler drew nothing, as expected.
PFPALETTE: command line busy (PLINE) -- finish it and try again.
  [2] FAIL  pfp:defer refused (command line busy).*Cancel*
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
      drawing's data.* **WORSE THAN DOCUMENTED, 2026-07-27** — it does not fail
      silently. See the status note below.
- [ ] 5.3 **L2** — close all drawings. `OnEnteringNoDocState` prints and the
      palette **closes**. It must not sit on the start screen showing the last
      drawing's registry.
      **FAIL — the palette persisted on the start screen and nothing printed.**
- [ ] 5.4 **L3** — open a drawing. `[L3] PASS` prints and the palette returns.
      **ERROR** — `no function definition:
      C:PFSUITE/PFSPALETTE#ONDOCACTIVATED :error#2`

> **STATUS 2026-07-27: §5 is OPEN, and the failure is not the one this section
> was written to test.**
>
> The question was whether a *closed form* receives events. The test never got
> to ask it. Read 5.3 and 5.4 together: L3's error says the event **did** fire
> on the incoming document and the **handler was not there to receive it**.
> AutoLISP namespaces are per-document, so these `defun`s exist only in
> drawings where `pftools-load.lsp` ran.
>
> **So the blocker is namespace, not form state.** That reframes the fallbacks
> the old note listed: neither `dcl-Form-Hide` nor a `vlr-docmanager-reactor`
> fixes a handler that does not exist in the document being activated into. The
> candidate fix is **per-document autoload (`acaddoc.lsp`)**, which addresses
> 5.2, 5.3 and 5.4 together.
>
> It also downgrades 5.2 from "known limitation" to a real defect: activating
> into an unloaded drawing throws a **visible error**, it does not quietly keep
> stale data.
>
> **DEFERRED by decision 2026-07-27.** Phase 1 has passed, so Phase 2 (the
> ticket channel) goes first. Until §5 is taken up, the two lifecycle handlers
> in `pfp-proof.lsp` §4 are exercise-only — **do not ship them as the fix.**
> The palette's start-screen persistence stands as a known rough edge.

- [ ] 5.5 Close the palette **deliberately** with `PFPALETTE`, then switch
      drawings. It must **stay closed** — `DocActivated` must not resurrect a
      palette the user dismissed. *(Requires the `Close` event ticked and
      `*pfp-was-open*` cleared in its handler. If that isn't wired yet, expect
      this to fail and record it.)*

---

## 6. Results — run 1, 2026-07-27

**The gate passed.** §4 is clean end to end, which was the one thing that could
not be reasoned out from the samples. Phases 2–4 are unblocked and the defer
channel has been promoted into `pfpalette.lsp` §2.

| # | Test | Result | Note |
|---|---|---|---|
| 1.1 | Min W/H corrected | ⚠️ | `tvwLines` misaligned |
| 1.6a | Narrow resize, no vanishing | ✅ | §8 closed **by construction** — form can't narrow |
| 1.6c | Grow tall/wide, no overlap | ⚠️ | `tvwLines` leaves a gap above on stretch |
| 2.2 | Paints without moving | ✅ | |
| 2.3/2.4 | Footer labels populate | ✅ | blank until `PFPRELOAD` — Studio edits were never reaching the runtime |
| 2.10 | Columns don't stack | ✅ | 3 toggles, still 2 + 2 — Close destroys the controls |
| 2.11 | metaList overflow | ✅ | 9 rows fit, no scrollbar — closes LAYOUT §11(a) |
| 3.x | Write-free contract | ✅ | **contract** — clean 29→29, populated 21→21. Found + fixed the `acad_strlsort` empty-registry bug |
| 4.2 | [1] modeless drew nothing | ✅ | |
| 4.6 | [5] getpoint returned | ✅ | **the gate** |
| 4.8 | One U peels it | ✅ | |
| 4.9 | Refuses behind a live command | ✅ | refused against `PLINE` |
| 5.3 | L2 closes on start screen | ❌ | persisted; nothing printed |
| 5.4 | L3 reopens | ❌ | `no function definition` — namespace, not form state |

### Next run, in order

1. ~~`PFPDIAG`~~ — done, 29 of 29 (run it with the palette **open**; closed
   reads 0 of 29, see 2.10).
2. ~~Footer labels~~ — **fixed.** `PFPRELOAD`.
3. ~~**§3 with `PFPDBMOD`**~~ — **CLOSED.** Clean 29→29, populated 21→21.
   Re-run it after any new read path is wired.
4. **Studio: `tvwLines`** vertical anchor (1.1, 1.6c) — then `PFPRELOAD` and
   re-run 1.6, which is the only anchoring evidence not taken against a stale
   project.
5. **1.7** — the docked gray box. May already be gone with the background
   change; confirm.
6. **2.7** — Type-parent selection clearing both panels; still unrun.
7. **0.5** — runtime file versions now matched; tick it off if confirmed.

§5 is deferred by decision — see the status note there.

## 7. Triage

| Symptom | Look at |
|---|---|
| Palette won't load | `pfp:odcl-path` folder segment; `*pftools-dir*` |
| **A Studio change has no effect** | `PFPRELOAD`. `dcl-Project-Load` no-ops when already loaded without `ForceReload` T — the in-memory project wins until AutoCAD restarts |
| **A runtime caption survives a palette toggle** | Same cause: you are looking at the cached project, not the file |
| Nothing prints on click | Event not ticked, or handler name mismatch |
| Tree empty until moved | Data written in `OnInitialize` instead of `pfp:refresh` |
| Columns multiply | `AddColumns` called more than once — needs a done-flag |
| Buttons vanish on resize | `Min Width` below the button row's right edge |
| Drawing dirty after opening | A read path passing `create` T — breaks §5 |
| `[5]` fails but `[4]` passes | Command context is partial; `SendCommand` may need a different form |
| **A control does nothing, silently** | **`PFPDIAG`.** An undefined control symbol is nil, and the `dcl-*` call on nil neither acts nor errors — the single hardest failure mode to spot |
| **`bad function: DCL-… :error#2`** | `vl-catch-all-apply` does **not** trap a bad *function* — only a bad *argument*. An unbound symbol in the function position fails before the catch engages and aborts the whole command. Test `(eval (read name))` for nil **first** (`pfp:callable-p`) |
| **A missing PROPERTY, e.g. `<Text> not found`** | Modal OpenDCL dialog, raised below LISP — uncatchable. Don't probe speculative property names |
| **A Label's text is invisible** | `Foreground Color` -24 is **Transparent**; `Font Size` 0 draws no glyphs. Labels have no `Use Visual Style` — `Foreground Color` is authoritative. Set -19 |
| **A control paints as a plain gray box** | `Back Color` -24 is **Transparent**, which mis-composites when docked. Use -16 (button face) |
| **Anything colour-related at all** | The negative range is a system-colour enumeration, not arbitrary. Table in PALETTE-LAYOUT §8 |
| **Caption never appears** | Same: `(Name)` mismatch. `pfp:caption` now names the miss |
| **`no function definition: C:PFSUITE/…`** | The handler doesn't exist in *that document's* namespace — per-document autoload, §5 |
| L3 fails | ~~Closed forms don't get events~~ — **not the cause**; it's the namespace. See §5 |
