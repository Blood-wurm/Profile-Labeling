# pfpalette.lsp — V5 OpenDCL palette front-end

**Load position:** 10 of 10 (last; may depend on every file above it).
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
  tree), error-guarded, modeless-legal (pure reads). Also the single entry
  for the three refresh signals to come: `OnDocActivated`, the PF*
  command-ended reactor, `btnRefresh`.
- `pfp:defer` / `pfp:cmd-idle-p` — **the defer channel (§2). PROVEN
  2026-07-27.** Every palette verb goes through `pfp:defer` and nothing
  else. Promoted out of `pfp-proof.lsp` after PALETTE-TESTING §4 passed
  [1]–[5]: `getpoint` prompted and returned from the deferred command, the
  work landed in one undo group, and the gate refused against a live
  `PLINE`. `pfp:cmd-idle-p` checks `CMDACTIVE` **and** `CMDNAMES` — a
  dialog or grip edit can leave CMDNAMES populated with CMDACTIVE at 0.
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
- Verbs never act directly. `pfp:defer` or nothing.
- Look is re-applied, never assumed. Every `dcl-*` write to a control is a
  no-op once the form closes, so `pfp:skin` belongs beside `pfp:refresh` on
  every open — and nothing may treat a runtime colour, font or rect as
  state that persists.
- UI vocabulary is "Anchored" / "Registered" — never "placed" / "stub".
- Columns are added exactly once, in OnInitialize; data never fills there.

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
