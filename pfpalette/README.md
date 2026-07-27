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
| `PFPPROBE` `PFPINK` `PFPMOVE` `PFPNUDGE` | One-off hunt tools. Candidates for deletion. |

Helpers behind them: `pfp:callable-p`, `pfp:selfcheck`, `pfp:try`,
`pfp:ask`, `pfp:pause`, `pfp:read-ctrl`.

## Invariants

- Modeless handlers must be provably write-free (root README §5): they
  reach only read paths (`pfa:registry` → `pfa:nod-dict` create nil).
  **Verified in CAD 2026-07-27** — PALETTE-TESTING §3, clean drawing 29→29
  and populated 21→21. Re-run after wiring any new read path.
- Verbs never act directly. `pfp:defer` or nothing.
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
