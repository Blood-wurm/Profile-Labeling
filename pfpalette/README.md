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

## Public API

Nothing here is called by other files; the surface is the command, the
handlers, and the refresh entry point:

- `C:PFPALETTE` — toggle; runs `pfp:refresh` after Form-Show.
- `pfp:refresh` — THE one data-fill entry point (registry scan → labels +
  tree), error-guarded, modeless-legal (pure reads). Also the single entry
  for the three refresh signals to come: `OnDocActivated`, the PF*
  command-ended reactor, `btnRefresh`.
- `pfp:odcl-path` — `*pftools-dir*` + `pfsuite.odcl` (the ONE path lives
  in pftools-load; never hardcode a second copy).
- Handlers: `c:pfsuite/pfsPalette#OnInitialize` (columns only),
  `c:pfsuite/pfsPalette/tvwLines#OnSelChanged` (fills metaList +
  lvwLinkage).
- Internal: `pfp:ensure`, `pfp:seed-labels`, `pfp:fill-tree`,
  `pfp:sel-row`, `pfp:meta-rows`, `pfp:linkage-files`, `pfp:fill-linkage`,
  `pfp:file-cell`, `pfp:dash`.

## Invariants

- Modeless handlers must be provably write-free (root README §5): they
  reach only read paths (`pfa:registry` → `pfa:nod-dict` create nil).
- UI vocabulary is "Anchored" / "Registered" — never "placed" / "stub".
- Columns are added exactly once, in OnInitialize; data never fills there.

## Open issues local to this file

- Palette persists across drawings while the registry is per-drawing —
  stale data after a drawing switch until `OnDocActivated` → `pfp:refresh`
  lands (milestone 3) — [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFPALETTE,
  root README §8.
- Buttons vanished during one resize test (unresolved; may be the §4a
  deferred-paint class) — root README §8.
- .odcl control names are unverifiable statically —
  [../Low_Priority_issues.md](../Low_Priority_issues.md) #3.
