# pflabel.lsp — C:PFLABEL, top-of-grid structure labels

**Load position:** 7 of 10 (after pfsetup, before pfxlabel).
**May depend on:** pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings,
pfsetup.
**Depended on by:** pfinvert (shared builders + the settings dialog).

## What it owns

The V4 pivot: the command reads the ANCHOR — everything the old dialogs
gathered per run lives in the record PFSETUP wrote. Pick-first
(`pfs:choose-or-place`), then the run dialog (`pf_run`) lists ONE target's
structures with `[LABELED]` recon marks; the engine (`pflabel:run`) draws
label stacks at the TOP-OF-GRID PROBE per station (grids have stepped
tops — a station with no PF-GRID-MJR hit is skipped and reported). Also
owns the PFLABELSET settings dialog (`pflabel_settings`) whose I/O lives in
pfsettings.

- **Secondary .cl set = THE REGISTRY** (anchors AND stubs), same-utility-
  type only, via the ONE builder `pflabel:registry-pairs` (audit #12).
- **Layer rule:** derived `<TYPE>-TEXT_P`, handle-tracked, erase-and-
  replace on an All re-run; "Use current layer" draws on CLAYER untracked
  (pass recorded with timestamp + layer, no handles).
- **Label composition** (validated near-100%): STA rows primary first then
  alphabetical; combined ID alphabetical; const rows from
  `*pf-rule-table*`; elevation placeholder rows (HDWL drops it).

## Public API

Shared with pfinvert (all pure reads — gather-path purity: callable before
any undo group, one day from a modeless handler):

- `pflabel:registry-pairs primary-cl` → `(path . name)*` — THE registry
  builder: thin filter over `pfa:registry` (one merged, copy-excluding,
  sorted walk), resolved via `pfa:entry-cl`, self dropped by `pf:cl-id`,
  same-type only. Consumers: both setups, both run dialogs.
- `pflabel:build-lines pairs` → line table `(clfile name lo hi verts)*` —
  write-free: `pf:cl-geom` read-only, a re-matched twin is used but never
  filed.
- `pflabel:gather-inlets` → rule-matching INSERTs (model space only).
- `pflabel:pending inlets lines primary` → sorted `(sta ename blkname)*`.
- `pflabel:line-loaded-p name lines`, `pflabel:pass-xs anchor passname`,
  `pflabel:labeled-x-p x xs eps`, `pflabel:index-stations`.
- `pflabel:show-dialog` — the PFLABELSET dialog (pfinvert's run dialog
  opens it via its `pi_set` action_tile).

Engine + wrapper hooks:

- `pflabel:run anchor rd` — the ENGINE: consumes the order ticket
  (mode/lines/inlets/sel), **writer** (its own undo group via
  `pf:undo-begin '*pflabel-undo-open*`); publishes `*pflabel-run-ctx*` for
  the Esc flush and clears it on normal exit.
- `pflabel:flush-pass` — Esc ledger flush (the `pf:run-command` hook):
  writes the pass for whatever got drawn before the Esc, inside the
  still-open group.
- `C:PFLABEL` / `C:PFL` — `pf:run-command "PFLABEL" 'pflabel:flush-pass
  'pflabel:cmd`. `C:PFLABELSET`.

## Invariants

- Gather-path purity: nothing reachable from the run dialog / setup writes
  the drawing (root README §5 contract).
- Label Y = the top-of-grid probe at each structure's station, never the
  stored nominal top.
- All-mode + derived layer REPLACES this command's previous tracked pass
  by handle; Sel appends; CLAYER output is never erased or counted.
- `write-pass` validates the .cl checksum AFTER labeling and writes STATUS
  — labeling can never be older than its check.

## Open issues local to this file

- **[wrong-output, CRITICAL, OPEN]** structures silently dropped near
  deflection PIs (`cl_location_at_pt` nil, no perpendicular foot) — root
  cause + planned segment-membership fix in
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFLABEL.
- Ghost dropdown on open — likely fixed by pick-first; verify in CAD
  ([../OPEN-ISSUES.md](../OPEN-ISSUES.md)).
