# pfxlabel.lsp — C:PFXLABEL, pipe-crossing discovery + labeling

**Load position:** 9 of 12 (after pflabel, before pfinvert).
**May depend on:** pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings,
pfsetup (loads after pflabel but calls nothing in it).
**Depended on by:** nothing (`pfxl:src-files` moved to pfanchor 2026-08-06 as
`pfa:src-files`; pfinvert, pfqty and pfreport call it there now).

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
  profile's .cl (anchors AND stubs, via `pfa:entry-cl`), taking **every**
  intersection per pair — a line that crosses another twice yields two
  crossings (`pf:poly-x-all`, 2026-08-06). Per source pair a SCOPE checksum
  short-circuit skips unchanged pairs. Merges are additive (elevations
  preserved, never destructive).
- **Not every intersection is a crossing.** Three tests inside
  `pfa:xing-scan`, any of which rejects a hit: `pf:shared-structure-p` (an
  intersection at a terminus of either .cl), `pf:pro-outside-p` (the station is
  outside the SOURCE `_INV.pro`'s own range) and `pfa:struct-shared-p` (a
  structure block at the hit that lies on BOTH .cl files).
  Of the two shared-structure tests **the second is the one that catches most
  of them** — the terminus test only sees a tie-in whose centerline stops at
  the joint, and a branch drawn past the main or two mains meeting through a
  junction box stop nowhere near it. Tolerance is not the fix for those; the
  structure test measures the physical fact instead.
  **The .pro range test (2026-08-06) is a different kind of fact:** a .cl runs
  the whole alignment, a pipe exists only over its profile, so two centerlines
  that cross past the end of the pipe run cross no pipe. It matters because
  `profile_z` extends the end tangent rather than refusing, which is exactly
  how such a hit used to get a plausible interpolated invert and a label.
  Source side only — a label past the last structure on the TARGET grid is
  allowed, deliberately; the target arm is one more `pf:pro-outside-p` call in
  the scan if that changes.
  `pfxl:discover` names each rejection on the command line
  (`Skipped -- shared structure, not a crossing: <line> at <sta> …`,
  `Skipped -- no pipe on the source at that station: …`) so it reads as a
  decision rather than a miss. Tolerances: `*pfx-terminus-tol*` (2.0 ft) and
  `*pfx-struct-tol*` (5.0 ft); the range test has no tolerance — the profile's
  own `profile_sta_range` is the answer. **Not its vertex stations**: a `.pro`
  need not be stationed like its `.cl`, and reading the range off the file
  dropped real crossings on every line where the two differ.
  **The filters gate only what gets FILED**, which was the whole story until
  2026-08-03 and is why tie-ins kept showing: the dialog and the palette read
  the LEDGER, so anything filed by an earlier run stood regardless, and no
  rescan could retract it since the SCOPE short-circuit never re-cuts an
  unchanged pair. Filed records are now re-tested on **both** sides through
  `pfa:xing-shared-split` — `pfa:xing-find` and `pfa:target-counts` drop
  rejected rows from what they show, and `pfxl:discover` runs
  `pfa:xing-sweep-shared` first to delete them for good, naming each with the
  grounds the split gives it (`Removed -- <why>: …`). This reverses the
  "no purge pass" decision of 2026-07-30. **Already-drawn labels are not
  touched** — a swept record leaves its entities in the drawing, by
  instruction; recon will show them as orphans.
- **Completeness:** a crossing is "labeled" when its station line stands
  on the target grid at the per-station top (`pf:top-at`) — recon in
  pfanchor SECTION 5. Label Outstanding draws every unlabeled row; Label
  Selected relabels only after a deliberate confirm (duplicates).
- Invert + size are READ from .pro via the Road API (invert = flowline;
  size = nearest nominal to (TOP−INV)×12); material is the SOURCE
  profile's → `NN" <MATERIAL>`.

## Public API

- `pfxl:run anchor xf sel` — the ENGINE: draws the resolved selection on
  the sheet. Caller owns the undo group (the command opens it around
  discovery + dialog + engine). Accumulates handles in the run-scoped
  global `*pfxl-run-newh*` (not a local — promoted so the Esc flush can
  ledger a partial pass), appends them to the XING pass on normal exit.
  Reads the TARGET's own `_INV.pro` **once** for the pass (`pf:pro-verts`)
  and samples each crossing's `telev` off those vertices with
  `pf:pro-z-verts`. It was one `pf:pro-z` per crossing until 2026-08-06,
  which meant a target whose registered `.pro` is missing printed a pair of
  Carlson C++ `unable to open file` lines per labeled crossing — uncatchable
  from LISP. Now the file is read once, silently, and an unreadable one
  reports a single line and stores no elevations; the labels still draw.
- `pfxl:flush-pass` — Esc ledger flush (the `pf:run-command` hook):
  appends the partial pass's handles to the XING ledger inside the
  still-open group.
- `pfxl:report-status anchor` — PRINTS the freshness verdict after a
  pass; stores nothing. Was write-status until 2026-08-01, when
  `STATUS_XING` was retired (DATA-FLOW §4.1): it validated the TARGET
  `.cl` against META `(301)` through the same code as `STATUS_LABEL` —
  identical inputs, identical verdict, so the record could never disagree
  with LABEL's and the Checks roll-up counted one question twice.
  Per-SOURCE freshness stays `SCOPE`'s job: it holds a
  `<base>|<target-cksum>|<source-cksum>|<source-pro-cksum>` record per pair
  and short-circuits discovery on it. The fourth field arrived 2026-08-06 with
  the .pro range filter — on `.cl` checksums alone, extending a pipe run would
  never bring its crossing back, because an unchanged pair is never re-cut.
- `C:PFXLABEL` / `C:PFX` — `pf:run-command "PFXLABEL" 'pfxl:flush-pass
  'pfxl:cmd`.

Internal: `pfxl:discover` (**writer**: merges crossings + rewrites SCOPE,
in-group; `pf:cl-geom` with write-p T files GEOM here), `pfxl:resolve-target`
(session-sticky `*pfxl-last*`), `pfxl:run-dialog`, `pfxl:zoom-to`,
`pfxl:handle-of`.

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
- **The whole pass writes to PF-ANNO**, station LINE included as of
  2026-08-06. `PF-XING` is retired; nothing reads it. Station text moved on
  2026-07-29, the pipe block and its size/material labels with it.
- Recon separates a CROSSING station line from a STRUCTURE one by geometry,
  never by layer: `pfa:station-line-tops` returns each line's top vertex, and
  `pfa:top-labeled-p` keeps only those matching the grid-top probe within
  `*pfa-recon-eps*` (1e-4). A structure line's top vertex is its text-stack
  top, a full text height higher, so the two cannot collide.
- The intended long-term marker is an **XDATA tag on the line**, which would
  drop the layer out of the test entirely. Not built.
- PFXLABEL parades by default (`pf:zoom-resolve T`); a palette override
  wins.

## Open issues local to this file

- The XING pass ledger only appends — dead/duplicate handles accumulate
  across relabels — [../Low_Priority_issues.md](../Low_Priority_issues.md) #8.
- Re-test the skipped-source case (`SANITARY_A @ 5+14.38`) before closing
  field findings 243–247 — [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFXLABEL.
- Per-crossing `pfa:find-anchor` full-DB scans (via `pfa:src-files`) —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) "Shared / cross-cutting". The scan now
  resolves it once per source LINE in its pre-pass, and the ledger re-test
  caches it per source, so the remaining per-crossing cost is `pfxl:label-one`'s.
