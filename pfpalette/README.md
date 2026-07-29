# pfpalette.lsp — V5 OpenDCL palette front-end

**Load position:** 12 of 12 (last; may depend on every file above it).
**May depend on:** everything — reads the registry through pfanchor's
`pfa:` API and the project root through pfsettings' `pfset:` API.
**Depended on by:** nothing (the top of the stack).

## What it owns

The OpenDCL dockable palette (project `pfsuite.odcl`, prefix `pfsuite/`,
control paths `pfsuite/pfsPalette/<control>`). Milestone 2 — READ-ONLY:
every `#On…` handler runs in a MODELESS context (no entsel / getpoint /
command / undo group, ever) and only READS the drawing. New palette code
carries a `pfp:` prefix. `C:PFPALETTE` toggles: show if down, close if up.

The field-tested split (root README §4a): `OnInitialize` = COLUMNS ONLY
(AddColumns is additive — once, ever); `pfp:refresh` = ALL data fill,
called after `dcl-Form-Show` returns (OnInitialize fires before the window
is realized, so data written there doesn't paint).

**Milestone 2 is field-verified as of 2026-07-27** (PALETTE-TESTING run 1):
tree paints immediately, columns survive three toggles, linkage rows read
`(not set)`, metaList's 9 rows fit without scrolling, footer labels
populate. **Both gates are open** — §4 deferred fire and §3 write-free —
so Phase 2 (the ticket channel) is unblocked.

## Public API

Nothing here is called by other files; the surface is the commands, the
handlers, the refresh entry point, and the defer channel:

- `C:PFPALETTE` — toggle; runs `pfp:refresh` after Form-Show.
- `C:PFPRELOAD` — **run after EVERY Studio save.** See Invariants.
- `pfp:refresh` — THE one data-fill entry point (registry scan → labels +
  **both** trees), error-guarded, modeless-legal (pure reads). Also the single
  entry for the three refresh signals to come: `OnDocActivated`, the PF*
  command-ended reactor, `btnRefresh`.
- `pfp:fill-tree ctrl reg` → **map** — takes the control and RETURNS the
  child-key map (2026-07-29) instead of writing a global. Two trees now render
  the same registry — `tvwLines` (Registry) and `tarLines` (Commands) — and
  child keys are per-control, so one shared `*pfp-tree-map*` would have made
  `pfp:sel-row` answer with the other tree's row. Each caller owns its map:
  `*pfp-tree-map*` and `*pfp-tar-map*`. `pfp:sel-row key map` takes the map
  for the same reason.
- `pfp:fill-details row` / `pfp:detail-rows row` — **the Commands tab's
  detailsList (§5b), added 2026-07-29, unverified in CAD.** A per-target
  SUMMARY, not an item list: pick a target, see what is on it, *then* choose
  the command. Every number comes from one `pfa:target-counts` call, so all
  three passes are on screen before the radio is touched. Three row shapes,
  because 0 and "unknowable" are different answers — no row, STUB (registered
  but not anchored: no xform, no ledger, no pass entities), ANCHORED.
  **Error-guarded, unlike §5's fill** — that one reads attributes and
  dictionaries and cannot realistically throw; this one reaches file I/O and
  the Road API, and an escaping error inside a modeless handler is worth not
  having. `*pfp-tar-sel*` holds the Commands selection for `btnRun`,
  independent of Registry's `*pfp-sel*`.
  - **It calls `pf:load-apis` first, and must.** `pf:run-command` loads the
    Carlson APIs at every command prologue, but **a modeless fill never goes
    through that wrapper** — so in a session where no PFTools command had run
    yet, clicking a line died with `bad function: CF:ROAD_API` (field report
    2026-07-29). `pfa:target-counts` reaches `cl_location_at_pt`. Exactly the
    failure pfanchor §6 records for `btnAnchor`, and it hid for the same
    reason: testing the palette almost always follows a command-line run that
    already `scload`ed `eworks`. Legal from a handler — `pf:load-apis` is two
    catch-wrapped `scload` calls, no `(command)`, no prompt, no drawing write,
    and idempotent. It lives **here** rather than in `pfp:route-sel` because
    all three callers of this fill need it: the handler, `pfp:refresh`, and
    `C:PFPDETAIL`.
- `pfp:defer` / `pfp:cmd-idle-p` — **the defer channel (§2). PROVEN
  2026-07-27.** Every palette verb goes through `pfp:defer` and nothing
  else. Promoted out of `pfp-proof.lsp` after PALETTE-TESTING §4 passed
  [1]–[5]: `getpoint` prompted and returned from the deferred command, the
  work landed in one undo group, and the gate refused against a live
  `PLINE`. `pfp:cmd-idle-p` checks `CMDACTIVE` **and** `CMDNAMES` — a
  dialog or grip edit can leave CMDNAMES populated with CMDACTIVE at 0.
- `C:PFPVERB` / `*pfp-verb*` / `pfp:fire` — **the verb channel (§8), added
  2026-07-28, unverified in CAD.** A button records `(verb . reg-row)` and
  queues ONE command; `C:PFPVERB` picks it up in a real command context and
  runs it under `pf:run-command`. One dispatcher, not five commands, so the
  CMDACTIVE gate, the ticket discipline and the post-run refresh live in one
  place. The ticket is **read and cleared in one `setq`**, and `pfp:fire`
  drops it again if `pfp:defer` refuses — a ticket left behind would fire on
  the next verb against a stale row.
  - Wired: `btnAnchor` `btnEdit` `btnNew` `btnZoom` (deferred), `btnRefresh`
    (inline — the one verb that is a pure read).
  - **The preset is what suppresses the modal**, and only Anchor sends one.
    `pfp:row->res` builds a record from what the registry row already holds
    and **omits `hs` / `vs` / `datum` on purpose** — a record missing them is
    exactly what makes `pfs:complete-res` prompt at the command line. Set
    `*pfs-preset-res*` immediately before the call that consumes it;
    `pfp:verb-run` also nils it afterwards, because a preset that escaped
    would reach the next *command-line* PFSETUP.
  - **Edit and New open the modal, by decision.** Anchor is promptable
    because everything it needs is on the row and only three numbers are
    missing. Edit exists to change what is BOUND — material, the _INV/_TOP
    pair, the two surfaces — and a file picker with role validation has no
    prompt-shaped equivalent. Do not "finish" Edit by making it prompt.
  - **`btnNew` is the break-out-to-a-modal path**: `pfs:place-one` with no
    preset opens the DCL dialog. It still has to be deferred — `start_dialog`
    needs a command context exactly as much as `getpoint` does.
  - Not wired: `btnRemove` (needs a third graft into `pfrem:cmd`, which
    picks its own target) and the five pick buttons (nowhere to put a result
    until the Edit/New tabs hold a pending record). See PALETTE-LAYOUT §5.
- `C:PFPRUN` / `*pfp-order*` / `pfp:order-fire` — **the Commands tab's run
  channel (§9), added 2026-07-29, unverified in CAD.** Twin of the verb
  channel: `btnRun` records `((cmd . LABEL|INVERT|XING) (row …) (mode …)
  (zoom …))` and queues ONE command; `C:PFPRUN` picks it up under
  `pf:run-command`, choosing the flush symbol per engine
  (`pflabel:flush-pass` / `pfi:flush-pass` / `pfxl:flush-pass`). Ticket read
  and cleared in one `setq`; dropped again if `pfp:defer` refuses.
  - **The gather is in the dispatcher, not the handler** (`pfp:order-gather`,
    `pflabel:run-dialog`'s build minus the dialog). PALETTE-LAYOUT §6 put it
    in the click handler, which forced a Crossings special case —
    `pfxl:discover` is a writer and can never run modeless. In a command
    context Crossings stops being special, and the numbers are read at RUN
    time rather than at click time.
  - **No `*pf-preset-target*` graft.** The dispatcher calls `pflabel:run` /
    `pfi:run` / `pfxl:run` directly with the anchor off the registry row, so
    it never enters `pflabel:cmd` and never reaches `pfs:choose-or-place` —
    the function that graft existed to bypass. A Registered row is refused
    outright instead (`pfp:need-row 'ANCHORED`). PALETTE-LAYOUT §10 permits
    that graft; this path does not need it, so it stays unspent.
  - **Outstanding needed no engine edit.** Both engines read the same `'sel`
    key (`pflabel.lsp:481`/`499`); `mode` only decides whether the previous
    pass is erased first. So Outstanding is `"Sel"` over `pfp:outstanding`,
    the subset of `pend` whose parallel `status` flag is nil. It is the
    **default** (`pfp:cmd-init` nudges `optRun` to item 1) because Label All
    ERASES this pass's output before redrawing, and on the palette that is one
    click with no dialog in front of it.
  - `Label Selected` is **refused**, not coerced — `detailsList` is a summary,
    so there is no item list to select from, and quietly running a different
    pass than the one picked is worse than sending the user to the modal.
    Crossings ignores `optRun` entirely: `pfxl:run` has no mode and its own
    All already means "every crossing not yet labeled".
  - `chkbxZoom` rides the existing one-shot `*pf-zoom-to*` channel rather than
    the ticket. `pf:zoom-resolve` already reads AND clears it per engine run,
    which is the discipline the ticket would have to reimplement; routing it
    through `rd` means editing all three engines. PALETTE-LAYOUT §6 wants that
    eventually — it is a clean separate change.
  - **Ends with `pfp:fill-details`, NOT `pfp:refresh`.** A labeling pass
    cannot change the registry, so rebuilding both trees would be wasted work
    *and* would clear `*pfp-tar-sel*`, blanking the panel the operator reads
    their result from. Registry-changing verbs (§8) still take the full
    refresh. Do not "fix" this by making both call `pfp:refresh`.
  - **Reading a value control is `dcl_Control_GetValue` — GENERIC, not
    per-class.** Settled by `PFPCTL` 2026-07-29 after all eight per-class
    guesses (`dcl-OptionList-*`, `dcl-CheckBox-*`) came back "no such
    function". There is no such family; `Opendcl_Reference/AUBlockTool_Final.lsp`
    reads four Slider Bars with `dcl_Control_GetValue` (:33-36) and writes them
    back with `SetValue` (:139). Hyphens are the spelling this build answers
    to; the underscore form is kept as the attested fallback.
    `pfp:first-callable` stays because a guessed name called bare raises an
    OpenDCL error inside a modeless handler — PALETTE-TESTING §2 records
    `dcl-Control-GetText` doing that *modally*, which locks the palette.
  - **NEVER call `dcl-Control-GetValue` on an Option List.** It raises the
    modal *"Property &lt;Value&gt; not found"* **and returns `nil` to LISP** — that
    combination is why it looked safe. The first `PFPCTL` printed six tidy
    nils and had put six dialogs on screen first. `PFPCTL` no longer probes
    them, and `pfp:opt-item` reads nothing from the control at all; an earlier
    "try the getter first in case a build answers it" put a dialog up on every
    press of RUN. A Check Box *does* carry `Value` (`chkbxZoom` → `0`
    unticked, no dialog), so `*pfp-chk-getters*` stays.
  - **Option Lists are read from their EVENT.** The vendor idiom is the answer:
    `AUBlockTool_Final.lsp:101` reads a Check Box as
    `(defun c:…_chkScaleRand_OnClicked (nValue /) (if (= nValue 0) …))` —
    OpenDCL **passes the value into the handler**. So `*pfp-opt-vals*`
    remembers what each group last reported, the same way `*pfp-sel*` remembers
    a tree selection. Handlers are defined for both `#OnClicked` and
    `#OnSelChanged` because which one an Option List raises is not attested;
    an unticked one costs nothing.
  - **`*pfp-opt-vals*` starts EMPTY and an unobserved group refuses to run.**
    Seeding it with "0 = Structures, whatever the .odcl shows" would be a guess
    about *which pass to fire* — the one error this tab must never make,
    because it does not fail loudly, it labels the wrong thing. One click on
    the radio is exact. `*pfp-opt-base*` (0 vs 1) is settled by the first
    observed event.
  - **`vl-catch-all-apply` does NOT suppress an OpenDCL argument error.** It is
    raised by the ARX as a **modal dialog** before LISP sees a return value, so
    wrapping a probe in a catch does not make it safe. `pfp:cmd-init` tried to
    nudge `optRun` with `dcl-Control-SetValue` and popped *"Property &lt;Value&gt;
    not found"* on every palette open (field report 2026-07-29). Getters
    degrade quietly to `nil`; **setters do not degrade at all.** Nothing here
    writes a control value, and `optRun`'s default item is a **Studio setting**,
    not a runtime call. Discover with `C:PFPAPI` — a symbol-table read, no call
    — rather than trial-calling anything against a live control.
  - **Nothing that prompts is safe while the palette is open.** `C:PFPAPI`'s
    first version asked for a filter with `getstring` and was cancelled
    mid-read by a palette click: a modeless form interrupts a command-line
    read, and `Function cancelled` is what that looks like from outside. It
    takes no input now; `pfp:api-names "*TREE*"` covers ad-hoc queries.
  - **`C:PFPAPI` ends the guessing.** `(atoms-family 0)` filtered to `DCL*` is
    the whole registered API, so "what is this accessor called" is one command
    instead of a candidate list and a CAD round-trip. Four rounds of guessing
    bought it.
  - **`pfp:chk-on-p` compares against 0 explicitly.** `GetValue` is numeric, so
    an unticked box answers `0` — and `0` is TRUE in AutoLISP. Written the
    obvious `(if v T nil)` way, every check box reads as ON, which for
    `chkbxZoom` means a zoom parade after every run with no way to turn it off.
  - Not wired: `optTools` (no Carlson command names yet), so `frmTools` /
    `optTools` are greyed by `pfp:cmd-init` and Label is permanently the
    active group — PALETTE-LAYOUT §6's Label/Tools state machine does not
    exist yet.
- `pfp:route-sel` binds **`*pf-quiet*`** T around both fills (2026-07-29).
  The fill paths run the same gather code the commands run, and that code
  narrates itself — `pfa:build-lines` emits one "Loaded line …" per line in
  the gather set, `pfa:status-for` a 4-line DRIFT block, and
  `pfa:target-counts` calls the latter twice. Fine for a command, unusable on
  every click. **Progress only is suppressed**; errors, refusals and
  `*error*` output print regardless (`pf:progress`, pftools-lib).
  - The reset is **outside** the fills and runs even on a throw, via
    `vl-catch-all-apply`. A skipped reset would leave `*pf-quiet*` T for the
    session and mute every command — a worse bug than the noise, and silent.
- `*pfp-sel*` — the tree selection, recorded by `tvwLines#OnSelChanged` (a
  plain `setq`; remembering a selection touches nothing) and **cleared by
  `pfp:refresh`**, because a rebuilt tree makes the old row meaningless: its
  state may have flipped from Registered to Anchored, or its anchor may be
  gone. That clear is what stops a second Anchor firing on a placed row.
- `pfp:odcl-path` — `*pftools-dir*` + `pfsuite.odcl` (the ONE path lives
  in pftools-load; never hardcode a second copy).
- `pfp:caption` — guarded `SetCaption` that NAMES a missing control instead
  of failing silently. Use it for every caption write.
- `pfp:skin` — THE one formatting entry point, the mirror of `pfp:refresh`
  for look rather than data (§7). Applies font, form background and
  colours, each only where the control's **type** documents the property —
  see the capability table below. Runs from `C:PFPALETTE` after
  `dcl-Form-Show`, silent unless a setter failed. **Must run on every
  open** — Close destroys the controls, so runtime formatting never
  persists. UI-only, so modeless-legal.
- `C:PFPTHEME` — re-skin now, verbosely, with a readback. The manual
  substitute for a `COLORTHEME` sysvar reactor, which is the documented
  next step and deliberately not installed.
- `C:PFPSCALE` — geometry probe: scale every rect and the form so a
  candidate size can be *looked at*, then typed into Studio. **X and Y are
  independent** — X drives Left+Width, Y drives Top+Height — because a
  native palette is a narrow *tall* strip and no uniform factor expresses
  that. Take the default on the second prompt for uniform. Fonts follow
  `(min fx fy)`; glyphs don't stretch on one axis. Studio still owns the
  geometry; a palette toggle is the undo.
- Handlers: `c:pfsuite/pfsPalette#OnInitialize` (columns only),
  `c:pfsuite/pfsPalette/tvwLines#OnSelChanged` (fills metaList +
  lvwLinkage).
- Internal: `pfp:ensure`, `pfp:seed-labels`, `pfp:fill-tree`,
  `pfp:sel-row`, `pfp:meta-rows`, `pfp:linkage-files`, `pfp:fill-linkage`,
  `pfp:file-cell`, `pfp:dash`.

### Diagnostics (§6) — built during the 2026-07-27 shakedown

| Command | Use |
|---|---|
| `PFPRELOAD` | Re-read the `.odcl` after a Studio save. **Not optional.** |
| `PFPDIAG` | Resolve every control name; lists misses. Run with the palette **OPEN**. |
| `PFPREAD` | Dump runtime caption / visible / enabled / rect per control. |
| `PFPDBMOD` | Write-free contract as a **delta**: mark, act, compare. |
| `PFPPROBE` `PFPMOVE` `PFPNUDGE` | One-off hunt tools. Candidates for deletion. |

`PFPINK` was **deleted 2026-07-27** — it read `GetForeColor`/`GetBackColor`
off `btnHelp`, a Text Button that supports neither, so every run raised four
uncatchable modal dialogs. §7's `pfp:type-can` is the general fix; `PFPTHEME`
is the replacement probe. The question it existed to answer is closed: the
labels carried `Foreground Color` -24 and `Font Size` 0.

Helpers behind them: `pfp:callable-p`, `pfp:selfcheck`, `pfp:try`,
`pfp:ask`, `pfp:pause`, `pfp:read-ctrl`.

### Native look (§7) — added 2026-07-27

| Command | Use |
|---|---|
| `PFPTHEME` | Re-skin after a `COLORTHEME` flip or a scheme edit. Reports what landed. |
| `PFPSCALE` | Try X and Y size factors on the live form. Toggle the palette to undo. |

Tunables are plain `setq` at the head of §7, so re-loading the suite
restores the defaults: `*pfp-skin-mode*` (`'font` default | `'full` |
`'off` — how much to paint), `*pfp-skin-scheme*` (`'sys` default |
`'theme` — which colours), the three scheme tables, `*pfp-font-name*` /
`*pfp-font-size*`, and the capability tables `*pfp-control-types*` /
`*pfp-can-backcolor*` / `*pfp-can-forecolor*` / `*pfp-font-mode-colour*` /
`*pfp-data-types*`. Helpers: `pfp:colour`, `pfp:scheme`, `pfp:type-can`,
`pfp:may`, `pfp:skin-one`, `pfp:tally`, `pfp:peek`, `pfp:num`,
`pfp:capture`, `pfp:scale-to`, `pfp:font-at`, `pfp:move-one`.

### A property may only be called where the vendor documents it

A missing property raises a modal dialog below LISP that no catch can
suppress, so `pfp:type-can` gates **reads as well as writes** — a getter is
a property accessor too. Read the applies-to list off the property
reference page; never infer one control's properties from a similar
control's.

| | Background | Foreground | Font + Font Size |
|---|---|---|---|
| Label, Option List, Check Box | ✅ | ✅ | ✅ |
| List View | ✅ | ❌ | ✅ |
| Tree, Frame, Tab Strip, Text Button | ❌ | ❌ | ✅ |
| Palette (the form) | ✅ | ❌ | — |

**A dark scheme cannot be completed, and it is a vendor limit.** Tree has
no colour property at all and List View has no foreground, so a dark pass
leaves `tvwLines`/`tarLines` light and puts black text on the three dark
List Views. Dark comes from the **Windows** theme, which those common
controls follow themselves. Hence `'font` mode as the default: font
everywhere, form background, Label colours, nothing that can misfire.

Two further reasons `'full` is opt-in: List View takes a background but no
foreground, and Check Box / Frame / Option Button / Tab Strip / Text Button
carry `Use Visual Style`, which the vendor says **may override** background
and foreground — so a colour set there may silently do nothing, and
disabling the style to force it looks less native, not more.

Colours are passed as `(R G B)` lists or negative logical values — both are
documented `Color` forms, so nothing bit-packs a colour. The packed form's
byte order is undocumented.

**The RGB values are starting points, not a spec** — Autodesk publishes
none for palette chrome. Eyedropper a docked native palette and correct
the rows; the tables are the only place they live.

## Invariants

- Modeless handlers must be provably write-free (root README §5): they
  reach only read paths (`pfa:registry` → `pfa:nod-dict` create nil).
  **Verified in CAD 2026-07-27** — PALETTE-TESTING §3, clean drawing 29→29
  and populated 21→21. Re-run after wiring any new read path.
- Verbs never act directly. `pfp:defer` or nothing — and since §8, `pfp:fire`
  is the only caller a button uses, so the ticket and the gate stay together.
- **A refused verb must SAY so.** `pfp:need-sel` reports "select a line
  first" / "already Anchored — use Edit" rather than returning quietly: a
  button that does nothing and prints nothing is indistinguishable from a
  mistyped control name, which is this palette's worst failure mode.
- Look is re-applied, never assumed. Every `dcl-*` write to a control is a
  no-op once the form closes, so `pfp:skin` belongs beside `pfp:refresh` on
  every open — and nothing may treat a runtime colour, font or rect as
  state that persists.
- UI vocabulary is "Anchored" / "Registered" — never "placed" / "stub".
- Columns are added exactly once, in OnInitialize; data never fills there.
- **Geometry is Studio's, entirely.** No runtime code positions or sizes a
  control. A `#OnSize` layout pass was written and removed on 2026-07-28 —
  the rows are anchored and sized in Studio instead. See
  [PALETTE-LAYOUT §3](../pfsuite-odcl/PALETTE-LAYOUT.md) for what anchoring
  can and cannot express, so the same ground isn't re-covered.

### OpenDCL behaviours that cost a day each — do not rediscover

- **`dcl-Project-Load` does nothing if the project is already loaded**
  unless the optional **`ForceReload`** argument is `T`. `pfp:ensure`
  passes one argument and guards on `*pfp-loaded*`, a session-long global,
  so **Studio edits never reach the runtime** until `PFPRELOAD` or an
  AutoCAD restart. Tell: a runtime-set caption survives a palette toggle.
- **Control symbols exist only while the form is open.** `dcl-Form-Close`
  destroys the children and every `pfsuite/pfsPalette/<name>` reverts to
  nil; the FORM symbol survives. This is *why* columns don't stack across
  toggles — each open rebuilds from nothing — so **do not add a
  `*pfp-columns-done*` flag**; it would suppress the rebuild the second
  open needs.
- **An undefined control symbol is nil, and `dcl-*` on nil neither acts nor
  errors.** The hardest failure mode here to spot. `pfp:caption` guards it;
  `PFPDIAG` finds it.
- **A handler only runs if its event is TICKED in Studio** (control → Events).
  A correctly named `defun` for an unticked event is never called — no error,
  no output, indistinguishable from a mistyped name, and **`PFPDIAG` cannot
  see it** because the control itself resolves fine. Ticking is a `.odcl`
  edit, so it needs `PFPRELOAD` like any other. Test which one you have with
  `(pfp:fire 'zoom *pfp-sel*)` from the command line: if that works and the
  button does not, the event is unticked.
- **`vl-catch-all-apply` does NOT trap a bad FUNCTION**, only a bad
  argument — an unbound symbol in the function position aborts the whole
  command. Test `(eval (read name))` for nil first (`pfp:callable-p`).
- **A missing PROPERTY raises a MODAL OpenDCL dialog** below LISP, which no
  catch can suppress. Never probe speculative property names; check the
  control's reference page instead.
- **Labels:** `Caption`, not `Text` (no `Text` property at all). No `Use
  Visual Style`, so `Foreground Color` is authoritative. Colour `-24` is
  **Transparent**, not a theme value — the full negative system-colour
  enumeration is in [PALETTE-LAYOUT §8](../pfsuite-odcl/PALETTE-LAYOUT.md).

## Open issues local to this file

- **§5 lifecycle is OPEN and deferred by decision (2026-07-27).**
  `OnEnteringNoDocState` did not fire (palette persisted on the start
  screen) and `OnDocActivated` threw `no function definition` — the event
  fires into documents where the suite was never loaded, and AutoLISP
  namespaces are per-document. **The blocker is namespace, not form
  state**, so neither `dcl-Form-Hide` nor a `vlr-docmanager-reactor` fixes
  it; per-document autoload (`acaddoc.lsp`) is the candidate. Until then
  stale data after a drawing switch, and start-screen persistence, are
  known rough edges. The two handlers in `pfp-proof.lsp` §4 are
  exercise-only — **do not ship them as the fix.**
- ~~Buttons vanished during one resize test~~ — closed **by construction**:
  `Min Width` ≥ 900 means the form cannot narrow enough to compute a
  negative x. Consistent with the theory, not a test of it. **The 900px
  floor is now load-bearing.**
- .odcl control names are unverifiable statically — **mitigated** by
  `PFPDIAG` (names resolve), though it cannot detect a *duplicate* name.
  [../Low_Priority_issues.md](../Low_Priority_issues.md) #3.
