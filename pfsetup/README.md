# pfsetup.lsp — C:PFSETUP, two-tier registration

**Load position:** 6 of 12 (after pfsettings, before pfpro).
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
- **Late .pro binding (Refresh)** — the same scan re-checks lines it
  already knows, in both stores: a registered stub (`pfa:stub-put`) and an
  anchored profile's FILES record (`pfa:files-put`, checksum computed on the
  fly, TIN pair + material preserved). Covers the normal case where the
  `.cl` lands first and the _INV/_TOP pair is cut later. **Fill-empty
  only** — an occupied slot is never overwritten or re-pointed, so
  Refresh cannot undo a deliberate binding; that stays Edit's job.
- **USER (placement)** — promotes stub → anchor, per grid: a **record**
  (identity override, scales, file bindings, datum) → pick LOWER-LEFT →
  pick TOP-RIGHT (EXTENTS ONLY — no scale is measured from either pick;
  stored RELATIVE). Vertical scale = declared H/V. ONE datum per grid,
  anchored at the lower-left. (Settled. Do not revisit.)
  - **The modal is one way to build the record, not the flow itself.**
    `pfs:show-dialog` fills a record and decides nothing; the seed chain
    (`pfs:seed-hs/vs/datum`), the refusal cascade (`pfs:validate`) and the
    session memory (`pfs:remember`) live outside it, so a record built any
    other way gets identical treatment. A caller that supplies
    `*pfs-preset-res*` skips the modal entirely.
  - **Anything the record is missing is PROMPTED**, in `pfs:complete-res`,
    before the picks: scales (`getreal`, `initget 6`) then datum. A preset
    carries no numbers by design — H, V and datum are typed at the command
    line, where the two picks already are.
- **Anchor All was removed 2026-07-28.** Per-grid scales, datum and picks
  made a batch a dialog parade with no pausable flow to design. One at a
  time. See [../pfsuite-md/OPEN-ISSUES.md](../pfsuite-md/OPEN-ISSUES.md).
- **Edit-mode invalidation:** .pro swap = cheap; scales/extents = redraw;
  .cl same range = regeneration; .cl DIFFERENT range = REFUSED (new
  anchor; PFREMOVE first); identity change = REFUSED.

## Public API

- `pfs:choose-or-place` → anchor | nil — THE registry pick for the label
  commands (pf_pick dialog): an ANCHORED profile returns its anchor; choosing
  a registered one IS consent to anchor it on the fly. **May write** (a
  placement runs in its own undo group via `*pfs-undo-open*`).
- `C:PFSETUP` — runs under `pf:run-command` (flush nil); body `pfs:cmd`.
- `*pfs-preset-res*` — **the record channel, and the second permitted graft
  into a command-line path** ([PALETTE-LAYOUT §10](../pfsuite-odcl/PALETTE-LAYOUT.md)).
  A caller sets it to a placement record; `pfs:place-one` / `pfs:edit-one`
  consume it INSTEAD of opening the modal. Nil on every command-line run,
  and behaviour with it nil is unchanged. A preset is validated by
  `pfs:validate` before anything is prompted or picked, so a bad record is
  refused before it costs the user a keystroke.

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
  drawings parse plain decimals). The command-line prompts use `getreal`,
  which is unit-free, so the same intent holds without the parse.
- **`*pfs-preset-res*` is read and cleared in ONE `setq`**, copying
  `pf:zoom-resolve`. A preset that outlived a failed run would place the
  next *command-line* record with someone else's input, silently — the
  failure mode §10 names as the likeliest way the palette breaks a command.
- **`pfs:validate` is the only refusal cascade.** Its two numeric clauses
  are checked only when their key is present: a record that omits them is
  declaring they will be prompted, where `initget` enforces the same rule.
  Nothing may re-implement a check that lives there.
- **Session memory is `pfs:remember`'s, not the dialog's.** Scales,
  per-type material and last datum update at the point input is confirmed,
  before the picks — so a record abandoned at the picks still leaves its
  scales as the next default, exactly as the modal always did.

## Open issues local to this file

- **No GEOM re-file path (2026-07-27).** `pfs:auto` short-circuits any line
  that is already placed or already named, so `(pf:cl-geom m T)` is never
  reached for an existing registry entry. GEOM is filed **once**, at first
  registration or at placement — which means a drawing registered before
  `pf:cl-parse` landed keeps its SAMPLED records (and its Road-API-walked
  vertices) until a `.cl` changes on disk or a new anchor is placed.
  Re-running PFSETUP does **not** upgrade them. A `PFRECACHE`-style command
  that walks the registry and re-files inside one undo group is designed but
  not built — see root README §11.
- Setup dialogs should be larger — [../OPEN-ISSUES.md](../OPEN-ISSUES.md).
- Feature ask: discover crossings/shared stations at registration —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md).
- Backtick sheet names silently skip in AUTO (parse lives in the lib's
  `pf:parse-sheet-name`) — [../OPEN-ISSUES.md](../OPEN-ISSUES.md)
  "Shared / cross-cutting".
- Session last-browsed dirs overwritten by company-folder routing —
  [../Low_Priority_issues.md](../Low_Priority_issues.md) #7.
