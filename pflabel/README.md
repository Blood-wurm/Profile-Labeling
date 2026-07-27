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
- `pflabel:build-lines pairs` → line table
  `(clfile name lo hi verts corridor-tol)*` — write-free: `pf:cl-geom`
  read-only, a re-matched twin is used but never filed. **Verts fall back
  three deep:** drawn twin → re-matched twin → the `.cl`'s own shape from
  `(cdr geom)` at `*pf-corridor-sampled*`. Shipping nil verts turned the
  membership pre-filter OFF for that line, which is what produced the
  `unable to locate point along centerline` parade — registered-only lines
  never have a twin, and they are exactly what `registry-pairs` adds.
- `pflabel:gather-inlets` → rule-matching INSERTs (model space only).
- `pflabel:pending inlets lines primary` → sorted `(sta ename blkname)*`.
- `pflabel:gather-compute anchor passname primary lines inlets` →
  `(pend status orphans)` | nil — **THE one gather-compute, shared with
  PFINVERT.** Both commands ask the same question of the same data and only
  the pass name differed; `.pro` never entered here (PFINVERT's profile work
  is downstream in its engine). Dialog-blind and pure-read, so it is
  callable from a modeless palette handler. The dialog FILLS stay local to
  each command, because tile names belong to their own DCL dialog.
- `pflabel:line-loaded-p name lines`, `pflabel:pass-xs anchor passname`,
  `pflabel:labeled-x-p x xs eps`, `pflabel:index-stations`.
- `pflabel:cluster-xs xs eps` → one representative X per eps-cluster. A
  label STACK is many entities at one X (rows + station line), so counting
  pass entities directly would report one moved structure as five.
- `pflabel:orphan-xs pend xs eps xf` → pass X ordinates with no structure —
  **the drift detector**, and the reverse of the `[LABELED]` test. See
  Invariants.
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
- **`label-all` consumes the ticket, it does not rescan.** `rd-all` files
  `rd-pend` under `'sel` for mode All exactly as `rd-sel` does for Sel;
  rebuilding it was a second full inlet × line membership scan. It falls
  back to a rebuild only if handed an All ticket with no `'sel`.
- **The drift echo is PRINTED, never persisted.** STATUS means "correct as
  of the last pass" and drift accumulates BETWEEN passes, so a stored flag
  would read clean one command after it stopped being true. The live view
  owns "correct right now".

### Drift detection — no stored positions

A pass entity whose X matches no CURRENT structure station is a label with
nothing under it: the structure moved or was erased after being labeled.
**The drawn labels are the record of where the structures were** — the sheet
is the baseline, which is also the thing that is actually wrong when they
disagree. No position field, no anchor-time snapshot.

It degrades honestly: a moved structure reads *Outstanding* at its new
station **and** leaves an orphan at its old one. Two signals, one event.

The remedy is to **re-run the label pass**, not to re-anchor — a moved
structure implicates neither the anchor, the grid, the scales, nor the
`.cl`, and those have their own detectors (`pfa:corner-check`,
`pfa:probe-corner`, the `.cl` checksum). All-mode already erases-by-handle
and replaces, so a re-run is the exact fix.

## Open issues local to this file

- **[wrong-output, CRITICAL, OPEN]** structures silently dropped near
  deflection PIs (`cl_location_at_pt` nil, no perpendicular foot) — root
  cause + planned segment-membership fix in
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFLABEL. **Unblocked 2026-07-27:**
  the fix was gated on the `.cl` format probe, and `pf:cl-parse` now reads
  exact vertices with authoritative per-vertex stations. Membership still
  gates on `cl_location_at_pt`, so the bug stands until `pf:pt-poly-dist`
  membership replaces it — the parser removed the blocker, not the bug.
- **Per-run cost.** The gather still rebuilds the line table and re-derives
  membership every run. `index-stations` and `process-structure` remain two
  full inlet × line passes (`label-all`'s third was removed). A bounding-box
  guard in front of `pf:pt-poly-dist` and a persistent index are designed
  but not built — see the root README.
- Ghost dropdown on open — likely fixed by pick-first; verify in CAD
  ([../OPEN-ISSUES.md](../OPEN-ISSUES.md)).
