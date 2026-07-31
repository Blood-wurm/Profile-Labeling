# pfxlabel.lsp — C:PFXLABEL, pipe-crossing discovery + labeling

**Load position:** 9 of 12 (after pflabel, before pfinvert).
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
  .pro must be BOUND, not its grid ANCHORED. Reciprocal annotation = run
  PFXLABEL with that profile as the target.
- **Discovery:** the target .cl intersected against every OTHER registered
  profile's .cl (anchors AND stubs, via `pfa:entry-cl`). Per source pair a
  SCOPE checksum short-circuit skips unchanged pairs. Merges are additive
  (elevations preserved, never destructive).
- **Shared structures are NOT crossings.** An intersection at a terminus of
  either .cl — a junction manhole, or a branch tying into a main — is rejected
  by `pf:shared-structure-p` inside `pfa:xing-scan` and never filed.
  `pfxl:discover` names each rejection on the command line
  (`Shared structure, not a crossing: <line> at <sta> …`) so it reads as a
  decision rather than a miss. Tolerance: `*pfx-terminus-tol*` (2.0 ft).
  **The filter is forward-only** — it stops new false records; crossings
  already on a ledger from before it landed keep drawing until removed by
  hand. Deliberate, per Jake 2026-07-30: no purge pass.
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
- `pfxl:write-status anchor` **W** — writes `STATUS_XING` after a pass.
  **New 2026-07-27:** PFXLABEL wrote no status at all, so a crossings pass
  left nothing behind saying whether its inputs were sound. Validates the
  TARGET `.cl` against the checksum META recorded at setup — the same
  comparison PFLABEL makes, because a crossing's target station comes off
  the same alignment. Per-SOURCE freshness stays `SCOPE`'s job: it already
  holds a `<base>|<target-cksum>|<source-cksum>` triple per pair and
  short-circuits discovery on it, so copying those here would be a fifth
  copy of a fact that already has an owner.
- `C:PFXLABEL` / `C:PFX` — `pf:run-command "PFXLABEL" 'pfxl:flush-pass
  'pfxl:cmd`.

Internal: `pfxl:discover` (**writer**: merges crossings + rewrites SCOPE,
in-group; `pf:cl-geom` with write-p T files GEOM here), `pfxl:resolve-target`
(session-sticky `*pfxl-last*`), `pfxl:run-dialog`, `pfxl:zoom-to`,
`pfxl:nz`, `pfxl:handle-of`.

### `pfxl:discover` is the filing half only — 2026-07-30

The **scan** moved to `pfa:xing-scan` in pfanchor; what stays here is merging
each hit, rewriting SCOPE, and reporting. Finding a crossing never needed a
write — it is `.cl` geometry through `pf:poly-x`, and `pf:cl-geom`'s `write-p`
is the documented read/write seam — but because the two jobs shared one
function, the palette could only ever show crossings a previous `PFXLABEL` had
already filed. It now runs the **same** scan read-only, so a preview cannot
disagree with what this command then does.

It still passes `write-p` **T**: inside the undo group the GEOM filing is
wanted, and it is what makes the next read-only preview cheap.

The SCOPE string splitter and reader moved with it and now live in pfanchor as
`pfa:split` / `pfa:scope-read` — SCOPE-record knowledge, and pfanchor is four
load positions above this file, so a reader there could never have called
upward. No aliases left behind, and **the old names are deliberately not
written here in code font**: everything in a Public API section is checked
against a real `defun` by `pf-verify`, so naming a deleted symbol makes it a
drift note forever.

## Invariants

- One undo group wraps the whole pass (discovery + labels); Esc is unwound
  by `pf:run-error`, which first lets `pfxl:flush-pass` ledger what drew.
- Erase-by-handle only; handles ledgered as pass "XING".
- Station text goes on **PF-ANNO** as of 2026-07-29, with every other label.
  It used to sit on PF-XING (recon selects LWPOLYLINE only, so text was
  never mistaken for a station line).
- **The station LINE stays on `PF-XING`** — the one piece of label output in
  the suite that does not go to PF-ANNO. That layer is a data channel, not
  styling: `pfa:station-line-tops` finds a crossing's "labeled" mark by
  scanning PF-XING by name. The crossing pipe block and its size/material
  labels moved to PF-ANNO with the station text.
- A crossing pass therefore SPANS two layers while its record holds one
  DXF 8. That field stays `PF-XING` — it is informational (erase is by
  handle, always was) and the station line is what identifies the pass.
- PFXLABEL parades by default (`pf:zoom-resolve T`); a palette override
  wins.

## Open issues local to this file

- The XING pass ledger only appends — dead/duplicate handles accumulate
  across relabels — [../Low_Priority_issues.md](../Low_Priority_issues.md) #8.
- Re-test the skipped-source case (`SANITARY_A @ 5+14.38`) before closing
  field findings 243–247 — [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFXLABEL.
- Per-crossing `pfa:find-anchor` full-DB scans (via `pfxl:src-files`) —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) "Shared / cross-cutting".
