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

- `C:PFPALETTE` — toggle; runs `pfp:skin` and `pfp:refresh` after Form-Show.
  **Nothing on the open path sizes the form, and nothing should.**
  - **Fix an opening-size complaint in Studio, not here.** `Min Width`/
    `Min Height` are a floor the runtime clamps *up* to, so `dcl-Form-Resize`
    cannot shrink the form. `Min Width` and `Max Width` are both pinned to the
    palette's own width — the intended consequence being that the palette can no
    longer be widened by dragging, floating or docked. Full decode in
    [../pfsuite-odcl/PALETTE-LAYOUT.md](../pfsuite-odcl/PALETTE-LAYOUT.md) §2.
  - **There is no form-size getter** (`dcl-Form-GetWidth` does not exist — it is
    what killed `PFPREAD` run 1), so LISP cannot even see the values it would be
    arguing with. `dcl-Form-Resize` survives in `C:PFPSCALE` only, where a
    deliberate temporary override is the point.
  - `*pfp-design-size*` is `420 × 670`, mirrored from Studio. **`C:PFPSCALE` is
    its only reader**, which is what makes a stale copy survivable — every
    PFPSCALE effect is undone by toggling the palette. Min/Max are not mirrored
    here at all; they are Studio's alone.
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
- `pfp:fill-items row` / `pfp:item-rows row` / `pfp:items-pass` /
  `pfp:rows->lb` / `pfp:rows->lv` — **the Commands tab's `lvwCommand` item list
  (§5c), 2026-07-30, unverified in CAD.** `*pfp-items-mode*` is `'listview`.
  - **It was a List Box for part of 2026-07-30, and is now a List View again.**
    The first CAD run raised four uncatchable modals — `Invalid argument type`,
    `Argument: 0`, one on `dcl-ListView-AddColumns` and three on
    `dcl-ListView-FillList`. Argument 0 is the control and the complaint is its
    **type**; the name resolved fine, so the `null` guard never fired (unlike
    the five `btnPick*` on the same open). `AddColumns` being last in
    `OnInitialize` is why the other three lists kept their columns. Studio's
    Properties tab settled it as a List Box, the fill moved to `pfp:rows->lb`,
    and then **the control was rebuilt in Studio as a real List View under the
    same `(Name)`** — because padded strings could not be made to line up (see
    below). Both renderers stay; the switch is one symbol either way.
  - **Why the padded-string form was abandoned — two independent causes, and
    only one of them is the font.** `pfset:pad` pads but never **truncates**,
    so any block name over 20 characters shoves both later columns right, which
    staggers rows in *any* font. And `pfp:skin` paints the **proportional** "MS
    Shell Dlg" over every control, so even equal-length pads disagree. Fixing
    it in place needed per-cell clipping *and* a per-control monospace
    exception in the skin — a Studio font alone cannot survive, since
    `*pfp-font-name*` overwrites it on every open. Real columns cost less.
  - **What the conversion spends: the selection read-back.** A List Box has
    attested getters (`dcl-ListBox-GetCurSel` / `GetText`, vendor sample); **no
    List View getter is attested anywhere in this suite.** `Label Selected` was
    to read at RUN time through them, and that route is now unproven. Settle it
    with `C:PFPAPI *LIST*` — a symbol-table read that **calls nothing**. Never
    trial-call a guessed getter at the live control: a missing property is the
    uncatchable modal, and this control has already spent one CAD run teaching
    that. If nothing turns up, the List Box is the fallback, which is why
    `pfp:rows->lb` is still here.
  - **Column widths total 370 against a 420 client, and the slack is
    deliberate** — a vertical scroll bar takes ~17px the moment the list is
    longer than the pane, and a horizontal bar appearing under it because the
    columns were sized to the full width is the cheapest ugly thing this panel
    can do. `Status` was 120 before the conversion made the widths real.
  - **Re-read `SelChanged`'s argument list in Studio.** The
    `(ItemIndexOrCount Value)` shape was measured off the **List Box**'s Events
    panel, and that panel is per control *type*. A wrong argument list is as
    silent as an unticked event (OPENDCL-WIRING §3). Delete the generated stub
    body — Studio emits a `dcl-MessageBox` here, a modal on every row click.
  - **`*pfp-items-mode*` is a plain `setq`, not a `boundp` guard.** Under a
    guard, a session that had already loaded the suite would keep its old
    `'listbox` and a re-load would look like it had done nothing — meaning
    `dcl-ListBox-*` calls at a control Studio has just rebuilt as a List View.
    That is a wrong *type*, i.e. the uncatchable modal, arrived at by editing a
    file correctly. It has no runtime setter and nothing to preserve.
  - **No guard could have caught it, and none can.** Nothing in LISP can ask a
    control its type without making a type-specific call at it, and that call
    *is* the fault; `vl-catch-all-apply` does not suppress it and the caller
    aborts regardless. `*pfp-items-mode*` is therefore a switch set from
    Studio, never a probe. OPENDCL-WIRING §1 has the wrong-name vs wrong-type
    signatures.
  - **`pfp:item-rows` is control-neutral** — three strings per row, with
    `pfp:rows->lb` / `pfp:rows->lv` rendering. It first emitted the List View
    shape directly, which welded the data to a control type that turned out to
    be wrong; a second wrong guess now costs one six-line renderer.
  - **A List Box has no columns**, so on that branch the three become one
    `pfset:pad`ded string at the same widths `pflabel:rd-fill` uses, and the
    palette reads like the modal dialog. Left **unclipped** on purpose: if that
    branch is ever live again the same two fixes apply, and a half-fix would
    hide that.
  - **`Clear` then `AddList`** — on the List Box branch: the vendor's own
    idiom, and load-bearing:
    `AddList` appends like `AddColumns`, so a refill without the `Clear`
    stacks the previous target's rows underneath. All four `dcl-ListBox-*`
    names are attested in `Opendcl_Reference` (OPENDCL-WIRING §4), not
    inferred. Kept as hyphen/underscore candidate pairs through
    `pfp:first-callable` because a wrong *function* name is the safe,
    catchable failure class — unlike a wrong type.
  - **`("lvwCommand" . list)` in `*pfp-control-types*`, matching the Studio
    rebuild.** It was `listbox` for part of 2026-07-30, deliberately: `list`
    means List View there and that table's applies-to lists were read off the
    property pages for *that* type, so an unknown type was kept out of
    `*pfp-can-backcolor*` and `*pfp-can-forecolor*` to hold `pfp:type-can` down
    to Font. Now that the control **is** a List View, `list` is the honest
    entry — it grants a Background in `'full` mode and still refuses the
    Foreground a List View does not have. **The table follows Studio, never the
    name:** `lvw` in the `(Name)` is what made this a List View on paper while
    it was a List Box on screen. `detailsList` answers "what is on this line" for all three passes at
  once; this answers "which ones, and where" for the **one** pass selected.
  Structures and Inverts list every structure with its station and whether that
  pass has labeled it; Crossings lists every line that crosses, and where. All
  rows come from one `pfa:target-items` call.
  - **Item is the structure's DRAWN NAME (2026-08-03)** — the combined ID
    PFLABEL puts on the sheet (`AA-1/BB-2`), not the block name it used to
    show. A block name names the drafting symbol, so two structures a hundred
    feet apart read identically and neither matches anything on the sheet.
    Crossings is untouched: the crossing line's name is already the pipe's ID.
  - **Two triggers, and the second is new.** The list depends on the target
    *and* on the radio, so it refills from `tarLines` selection (through
    `pfp:show-commands`) and from `optLabel#OnSelChanged` — which until now
    only remembered its value and painted nothing.
  - **Crossings are LIVE, not ledger-only (2026-07-30).** `pfa:xing-find` runs
    the discovery scan read-only and merges it with what is on record, so a
    line that has never had `PFXLABEL` run still lists its crossings, marked
    `NEW -- not on record`. `MOVED` means on record but the `.cl` now crosses
    elsewhere. This is why an empty Crossings list finally means "nothing
    crosses this line" rather than "nobody has looked".
  - `pfp:item-status` takes **only** the state symbol. It used to take `pass`
    as well, purely to reinterpret a bare boolean for Crossings — the extra
    states made that shape untenable, and removing it was the fix.
  - **`pfp:items-pass` defaults to Structures silently, and that is NOT
    `pfp:opt-item`'s rule.** An unobserved group refuses to *run*, because
    firing the wrong pass writes to the drawing and a wrong guess there does
    not fail loudly. Filling a list is a read: the worst a wrong default does is
    show the wrong list until a radio is clicked, and Structures is the
    `.odcl`'s own first item. Prompting on every tree click would be chatter.
  - **It reports its selection through its EVENT** —
    `lvwCommand#OnSelChanged (ItemIndexOrCount Value)`, index first like an
    Option List, ticked in Studio 2026-07-30 and corroborated by the tutorial's
    own List Box handler (`OpenDCL Tutorial.txt:343`, `(nSelection sSelText)`).
    Two arguments either way, so the arity survived the control turning out to
    be a List Box. `*pfp-item-sel*` remembers what it last reported and is
    cleared by `pfp:fill-items`, because replacing the rows makes a remembered
    index point at whatever now sits in that slot. Record-and-stop, like
    `pfp:opt-remember`; a selection is a noun.
  - **Both argument meanings depend on a Studio property no LISP can read.**
    Single-select: an index and the row text. Multi-select: a **count** and an
    **empty string**. Do not treat `*pfp-item-sel*`'s first element as a row
    index without knowing that property — it may be a tally.
  - **Still display only, and the read-back route is now the open question.**
    `Label Selected` was to read at RUN time rather than trust a remembered
    click — a getter cannot go stale between the click and the run — through
    `dcl-ListBox-GetCurSel` / `GetText`, both attested. **The List View
    conversion took those away**: no List View getter is attested here, so the
    event is the only source again. `C:PFPAPI *LIST*` names whatever exists and
    calls nothing; run it before writing anything that assumes a getter.
    Enumerating *several* selected rows was already unproven — `GetCurSel` is
    singular — so that half is unchanged.
  - Quiet and error-guarded for the same reasons as `pfp:fill-details`, and it
    calls `pf:load-apis` for the same reason too. It names a missing
    `lvwCommand` rather than trusting the call — `FillList` on `nil` does
    nothing and says nothing.
  - **One column set for all three passes** (`Item` / `Station` / `Status`,
    150/110/110). `AddColumns` is additive and runs once at `OnInitialize`, so
    it cannot be re-shaped per radio click — hence the neutral headers, since
    `Item` is a block name under Structures and Inverts and the crossing
    *line*'s name under Crossings.
- `pfp:route-sel` / `pfp:route-sel-do` / `*pfp-last-key*` — **the idempotence
  guard, built 2026-07-30.** Every tree click dispatches `OnSelChanged` twice
  (OPEN-ISSUES; the cause is in the `.odcl` and no handler can stop it), and
  the second re-runs the whole fill. This was designed and *deliberately not
  built* on the grounds that it guards a condition that should not exist —
  correct while the fill was a counts roll-up, wrong once the Commands fill
  started reaching `pfa:xing-scan`, which on a target with no SCOPE cuts every
  registry line against the target. Paying that twice per click is a different
  order of waste from an extra `*Cancel*`.
  - Cleared wherever the **data** behind a key can have changed: `pfp:refresh`
    (both trees are rebuilt, so the key belongs to a tree that no longer
    exists — leaving it set would make the seeding `SelectItem` look like a
    repeat and skip the first fill) and `pfp:order-run` (a pass just wrote).
  - A click on the row already showing is otherwise a genuine no-op.
    `btnRefresh` is the repaint button, and it says so out loud.
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
  - **`btnRefresh` reports, 2026-07-30.** `pfp:refresh` is silent on success by
    design — it is also the palette-open and `DocActivated` path, where a line
    per open is noise — so a working button and an unticked event looked
    identical from the command line, which is how it read as dead. The report
    lives in the **handler**, not in `pfp:refresh`: only the button has a user
    waiting on an acknowledgement. It doubles as the wiring test — a line means
    the Studio tick is on and the path ran; silence means the tick is off, or
    the `(Name)` is wrong (`PFPDIAG` names that one).
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
  - **`btnRemove` — wired 2026-07-30, unverified in CAD.** It needed no third
    graft: `pfrem:cmd` was *split* instead, into a pick half and
    `pfrem:remove-anchor`, which the `'remove` verb calls with the row's
    anchor. A split costs nothing from §10's budget and, unlike a preset
    global, has no stale-value path back into a command-line run. The verb
    **zooms before it confirms**, so the modal opens over a view of what is
    about to die; the modal itself stays exactly as `C:PFREMOVE` shows it —
    deferring moves the dialog into a command context, it does not replace it.
    Guarded to `'ANCHORED` (a Registered stub has no ledger to tear down) and
    to a live `entget` (the panel is only as fresh as the last `pfp:refresh`,
    and a dead ename would die inside `pfa:teardown-counts`).
  - Not wired: the five pick buttons (nowhere to put a result until the
    Edit/New tabs hold a pending record). See PALETTE-LAYOUT §5.
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
    the subset of `pend` whose parallel `status` flag is nil. It should be the
    **default**, because Label All ERASES this pass's output before redrawing
    and on the palette that is one click with no dialog in front of it — but
    that default is a **Studio setting**, not a runtime call. An earlier
    `pfp:cmd-init` nudged `optRun` with `dcl-Control-SetValue` and raised an
    uncatchable modal on every palette open; an Option List has no `Value` to
    write any more than it has one to read.
  - **The run gather is quiet; the run is not (2026-07-30).**
    `pfp:order-gather` reaches `pfa:build-lines` (one `Loaded line …` per
    centerline, 47 on a real project) and `pfa:status-for` (the DRIFT block).
    On the command line that commentary is owed to a user who asked for a
    gather and is watching it work; on the palette it is a wall of text in
    front of the one line they want — `Label All — 4 of 12`. So
    `pfp:run-labels` brackets **the gather call only**; the engine's own output
    after it is untouched. DRIFT is not lost: `detailsList` renders the same
    fact in its own row. Crossings is deliberately **not** quieted — its
    narration comes from `pfxl:discover`, a writer, and that is a different
    question. `*pf-quiet*` gates `pf:progress` and nothing else: every error,
    refusal and finding still prints.
    - The reset here is belt-and-braces, not the only guard: `pf:run-command`
      and `pf:run-error` both clear the flag (pfanchor §6), which is what makes
      a plain `setq` safe instead of another catch-and-reset wrapper.
  - **`optTools` is wired to PFPROINV / PFPROTOP (2026-07-30, unverified in
    CAD)**, and `*pfp-active-group*` decides which group `btnRun` fires.
    - **The flag, not "which radio has a selection."** Both groups always hold
      one — an Option List cannot un-select — so that question can never
      distinguish them. Each `SelChanged` records which group was touched last;
      `optRun` counts as Label, because it is a modifier of the Label ticket and
      the operator who adjusts the mode last should not have to re-arm RUN.
    - **The flag is only as good as the event that sets it, and `optTools`'
      `SelChanged` was never ticked in Studio.** Field report 2026-07-30:
      clicking a Tools item and pressing RUN answered `PFPALETTE: select a line
      first.` That message is printed **only** by `pfp:need-row`, called only
      by `pfp:order-fire`, reached only when `*pfp-active-group*` is not
      `TOOLS` — so the message was itself proof the handler had never fired.
      It read as a bug in the Tools commands because nothing on screen said
      which group RUN was serving. **`pfp:order-fire` now names the armed
      group when it refuses.** The tick is PALETTE-LAYOUT §7's, still Studio's
      to do; `C:PFPCTL` shows whether `optTools` has ever reported.
    - **The greying half of PALETTE-LAYOUT §6 is NOT built.** It is seven
      `SetEnabled` calls describing a decision this variable already makes; add
      it as polish once dispatch is proven. Dispatch first, decoration after.
    - **RUN stays the verb; the radios stay nouns.** An Option List offers no
      `Clicked`, only `SelChanged` — so a "picking the item runs it" design
      cannot re-run the item already selected, and the palette would look broken
      the second time.
    - **The simplest verb here.** No ticket, no row, no state check: it defers a
      bare command name. Both are already `pf:run-command`-wrapped, both open
      with an `entsel` loop (so they can never run modeless), and both resolve
      their own grid from the picked polyline (`pfpro:owner`) — so there is
      nothing the palette knows that they need, and no `tarLines` selection is
      required.
    - **The item captions are unverified** — the `.odcl` is binary and could not
      be read. `*INV*` → PFPROINV and `*TOP*` → PFPROTOP are inferred from what
      the commands cut, which is safe *because matching is by caption, not
      position*: whichever slot Studio has them in, each resolves correctly and
      the two cannot collide. **The third item is deliberately unmapped** —
      PALETTE-LAYOUT §6 calls it `Export .stm`, that predates the recent Studio
      edit, and guessing would fire the wrong command rather than refuse. An
      unmatched caption is named by `pfp:opt-item` with the text it saw; the fix
      is one pattern, not a code change.
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
    - **That recount binds `*pf-quiet*`**, for the reason `pfp:route-sel` does.
      It re-gathers to get post-write counts, and `pfa:build-lines` narrates
      one `Loaded line …` per centerline — 47 on a real project, printed a
      second time straight after the run's own gather said the same 47 (field
      report 2026-07-29). The recount itself is necessary: the numbers changed
      and the gather memo cannot be trusted across a write. It just must not
      narrate. Reset is unconditional and outside the catch.
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
  - **How the radios are read at all is an OpenDCL contract, not a palette
    decision — it lives in
    [`../pfsuite-odcl/OPENDCL-WIRING.md`](../pfsuite-odcl/OPENDCL-WIRING.md)**
    and is not repeated here: event names and argument lists (§3), which
    accessors exist per control type (§4), and why probing one raises an
    uncatchable modal (§1). Read that before touching a handler. The three
    things it settles that this section depends on: an Option List has only
    `SelChanged`; that handler takes `(nIndex sLabel)`, **index first, the
    reverse of the tree's**; and `dcl-Control-GetValue` must **never** be
    called on an Option List.
  - **`pfp:opt-item` reads nothing from the control.** `*pfp-opt-vals*`
    remembers what `SelChanged` last reported, the same way `*pfp-sel*`
    remembers a tree selection. An earlier "try the getter first in case a
    build answers it" put a modal dialog up on every press of RUN.
  - **`*pfp-opt-vals*` starts EMPTY and an unobserved group refuses to run.**
    Seeding it with "0 = Structures, whatever the .odcl shows" would be a guess
    about *which pass to fire* — the one error this tab must never make,
    because it does not fail loudly, it labels the wrong thing. One click on
    the radio is exact.
  - **Dispatch is by CAPTION, not index** (`*pfp-opt-captions*`, wildcard
    patterns) — a caption cannot be read off by one, and a pattern survives the
    `.odcl`'s unreliable captions (`btnClear` reads `CLear`). The index is kept
    as a fallback; `*pfp-opt-base*` is **0**, measured. An unmatched caption is
    named by `PFPCTL` and fixed by adding one pattern, not by changing code.
  - **`chkbxZoom` keeps its getter**, because a Check Box genuinely carries
    `Value`. `pfp:chk-on-p` compares against `0` explicitly: `GetValue` is
    numeric and **`0` is TRUE in AutoLISP**, so the obvious `(if v T nil)`
    reads every box as ON — for `chkbxZoom` that is a zoom parade after every
    run with no way to turn it off.
  - **`optRun`'s default item is a Studio setting.** No runtime setter for an
    Option List is known, and probing for one raises the modal.
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
  `pfp:sel-row`, `pfp:meta-rows`, `pfp:why-rows`, `pfp:linkage-files`,
  `pfp:fill-linkage`, `pfp:file-cell`, `pfp:dash`.
- **`pfp:why-rows` (2026-08-01, DATA-FLOW §3.2):** metaList now shows the
  stored findings sentence under the Checks row — one indented row per
  finding, only for STALE/FAILING passes, via `pfa:status-why` (pure
  ledger read, palette-legal). The Checks roll-up counts **2** passes
  since `STATUS_XING` was retired the same day (§4.1).

### Diagnostics (§6)

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

### Native look (§7)

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

### Help (§10)

`C:PFPHELP` shows the palette's help page: what each tab is, what anchoring
means and stores, what each of the three passes finds, and **every status
word either tab can display**. `btnHelp` calls it through `pfp:defer`.
Helpers: `pfp:help-lines` (the text), `pfp:help-show` (the dialog).

Three decisions worth not re-litigating:

- **A DCL dialog (`pfp_help` in `pfdialog.dcl`), not `pfset:help`.** The text
  runs ~90 lines; `alert` has no scrollbar. `pfp_help` is a `list_box`, so
  length is free and the Settings section can grow when Settings exists.
- **Deferred, though it only reads.** "Verbs defer, reads run inline" is about
  writes; this is about *context*. `start_dialog` needs a command context
  exactly as `getpoint` does — the same reason `btnNew` defers (§8). The
  command-line-busy refusal comes along for free.
- **`C:PFPHELP` is the entry point and the button is a caller**, so it is
  typeable with the palette closed — which is where someone who cannot find
  the palette actually is.

The page is written for a drafter: no function names, no file formats, no
ledger vocabulary. It spells out every status string the UI can show, because
a word on screen the help does not define is worse than no help. **When a
status string changes, the help changes with it** — `pfa:status-label`
(Registry), `pfp:item-status` and `pfp:drift-cell` (Commands) are the three
sources.

`pfp:drift-cell` reads **"2 Incorrect label(s)"** as of 2026-07-30, not "stale
label(s)". The Registry tab already spends `STALE` on a different axis — an
input *file* that changed since the pass ran — and this row is about a *label*
that no longer sits where its structure does. The **row is still titled
`Drift`** (Jake, same date); only the value changed.

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
  [../pfsuite-md/OPEN-ISSUES.md](../pfsuite-md/OPEN-ISSUES.md), PFPALETTE
  "duplicate `(Name)` check"; the `PFPDIAG` mitigation itself is recorded in
  [../pfsuite-md/CLOSED_ISSUES.md](../pfsuite-md/CLOSED_ISSUES.md).
