# pfxlabel.lsp — C:PFXLABEL, pipe-crossing discovery + labeling

**Load position:** 8 of 10 (after pflabel, before pfinvert).
**May depend on:** pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings,
pfsetup (loads after pflabel but calls nothing in it).
**Depended on by:** pfinvert (`pfxl:src-files`).

## What it owns

ONE command, TARGET-DIRECTED — the v3 trio (PFXFIND / PFXLABEL / PFXGRID)
collapsed: discovery auto-runs here, grid registration is PFSETUP's job.
Dialog: `pfxl_run`.

- **TARGET-ONLY draw.** A run labels ONLY the target grid; the crossing
  pipe is drawn from the SOURCE profile's authored .pro (never a probe of
  any drawn grid). A source contributes as a pure file reference — its
  .pro must be BOUND, not its grid PLACED. Reciprocal annotation = run
  PFXLABEL with that profile as the target.
- **Discovery:** the target .cl intersected against every OTHER registered
  profile's .cl (anchors AND stubs, via `pfa:entry-cl`). Per source pair a
  SCOPE checksum short-circuit skips unchanged pairs. Merges are additive
  (elevations preserved, never destructive).
- **Completeness:** a crossing is "labeled" when its station line stands
  on the target grid at the per-station top (`pf:top-at`) — recon in
  pfanchor SECTION 5. Label Outstanding draws every unlabeled row; Label
  Selected relabels only after a deliberate confirm (duplicates).
- Invert + size are READ from .pro via the Road API (invert = flowline;
  size = nearest nominal to (TOP−INV)×12); material is the SOURCE
  profile's → `NN" <MATERIAL>`.

## Public API

- `pfxl:src-files type name` → `(inv-pro top-pro material)` | nil — anchor
  first (carries material), then stub. Pure read; also pfinvert's lateral
  resolver.
- `pfxl:run anchor xf sel` — the ENGINE: draws the resolved selection on
  the sheet. Caller owns the undo group (the command opens it around
  discovery + dialog + engine). Accumulates handles in the run-scoped
  global `*pfxl-run-newh*` (not a local — promoted so the Esc flush can
  ledger a partial pass), appends them to the XING pass on normal exit.
- `pfxl:flush-pass` — Esc ledger flush (the `pf:run-command` hook):
  appends the partial pass's handles to the XING ledger inside the
  still-open group.
- `C:PFXLABEL` / `C:PFX` — `pf:run-command "PFXLABEL" 'pfxl:flush-pass
  'pfxl:cmd`.

Internal: `pfxl:discover` (**writer**: merges crossings + rewrites SCOPE,
in-group; `pf:cl-geom` with write-p T files GEOM here), `pfxl:resolve-target`
(session-sticky `*pfxl-last*`), `pfxl:run-dialog`, `pfxl:zoom-to`,
`pfxl:scope-read`, `pfxl:split`, `pfxl:nz`, `pfxl:handle-of`.

## Invariants

- One undo group wraps the whole pass (discovery + labels); Esc is unwound
  by `pf:run-error`, which first lets `pfxl:flush-pass` ledger what drew.
- Erase-by-handle only; handles ledgered as pass "XING".
- Station text goes ON PF-XING (recon selects LWPOLYLINE only, so text is
  never mistaken for a station line).
- PFXLABEL parades by default (`pf:zoom-resolve T`); a palette override
  wins.

## Open issues local to this file

- The XING pass ledger only appends — dead/duplicate handles accumulate
  across relabels — [../Low_Priority_issues.md](../Low_Priority_issues.md) #8.
- Re-test the skipped-source case (`SANITARY_A @ 5+14.38`) before closing
  field findings 243–247 — [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFXLABEL.
- Per-crossing `pfa:find-anchor` full-DB scans (via `pfxl:src-files`) —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) "Shared / cross-cutting".
