# pfsetup.lsp — C:PFSETUP, two-tier registration

**Load position:** 6 of 10 (after pfsettings, before pflabel).
**May depend on:** pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings.
**Depended on by:** pflabel, pfxlabel, pfinvert (`pfs:choose-or-place`).

## What it owns

Registration in two tiers, plus the registry-manager dialog
(`pfsetup_registry` in pfdialog.dcl) and the on-the-fly placement entry
point the label commands use.

- **AUTO (identity)** — fires when the drawing has no registry. Scans
  PF-NAME text sheet-wide (names only), resolves each to `Type_Name.cl` by
  convention, auto-binds the _INV/_TOP .pro pair, writes NOD stubs, files
  GEOM + TWIN once. No matching .cl, ambiguous match, or a .cl with no
  grid name = REPORTED AND SKIPPED, never guessed.
- **USER (placement)** — promotes stub → anchor, per grid: dialog
  (identity override, scales, file bindings, DATUM typed) → pick
  LOWER-LEFT → pick TOP-RIGHT (EXTENTS ONLY — no scale is measured from
  either pick; stored RELATIVE). Vertical scale = declared H/V. ONE datum
  per grid, anchored at the lower-left. (Settled. Do not revisit.)
- **Edit-mode invalidation:** .pro swap = cheap; scales/extents = redraw;
  .cl same range = regeneration; .cl DIFFERENT range = REFUSED (new
  anchor; PFREMOVE first); identity change = REFUSED.

## Public API

- `pfs:choose-or-place` → anchor | nil — THE registry pick for the label
  commands (pf_pick dialog): a PLACED profile returns its anchor; choosing
  an unplaced one IS consent to place it on the fly. **May write** (a
  placement runs in its own undo group via `*pfs-undo-open*`).
- `C:PFSETUP` — runs under `pf:run-command` (flush nil); body `pfs:cmd`.

Everything else (`pfs:auto`, `pfs:place-one`, `pfs:edit-one`,
`pfs:show-dialog`, `pfs:registry-dialog`, the pick handlers, lookups) is
internal to this command's flow. Writers (`pfs:auto`, `pfs:place-one`,
`pfs:edit-one`) each open ONE undo group per unit — a U peels one grid
(or one whole AUTO scan), not the batch; Esc mid-write is closed by
`pf:run-error` via the `*pfs-undo-open*` flag.

## Invariants

- Name is the identity key — picked files VALIDATE against it, they never
  resolve it. The slots guarantee roles; pairs bind both-or-neither.
- AUTO never guesses: skip cases report loudly in both directions.
- One undo group PER GRID placement; AUTO's whole scan is one group.
- distof mode 2 is pinned on the numeric tiles (Architectural/Fractional
  drawings parse plain decimals).

## Open issues local to this file

- "Place All" fires an unskippable dialog parade; wants a pausable flow —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFSETUP.
- Setup dialogs should be larger — [../OPEN-ISSUES.md](../OPEN-ISSUES.md).
- Feature ask: discover crossings/shared stations at registration —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md).
- Backtick sheet names silently skip in AUTO (parse lives in the lib's
  `pf:parse-sheet-name`) — [../OPEN-ISSUES.md](../OPEN-ISSUES.md)
  "Shared / cross-cutting".
- Session last-browsed dirs overwritten by company-folder routing —
  [../Low_Priority_issues.md](../Low_Priority_issues.md) #7.
