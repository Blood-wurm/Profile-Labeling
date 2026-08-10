# pfinvert.lsp — C:PFINVERT, invert labels at structures

**Load position:** 10 of 12 (after pfxlabel, before pfreport).
**May depend on:** pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings,
pfsetup, pflabel (structure walk + shared builders). No longer depends on
pfxlabel: `src-files` moved to pfanchor 2026-08-06.
**Depended on by:** pfpalette only transitively (nothing calls pfi:).

## What it owns

THE COMMAND SPLIT (locked): PFLABEL owns top-of-grid text; PFINVERT owns
EVERYTHING AT PIPE ELEVATION. At each structure on the primary line:

- **PRIMARY** — in/out inverts, TEXT ONLY. I.O/I.I are the two ADJACENT
  `_INV.pro` VERTICES that meet at the structure (`pfi:invert-bracket`
  over `pf:pro-verts`): each vertex IS an invert, so the reading is exact.
  Of that pair the LOWER is the pipe LEAVING → I.O. A polyline endpoint is a
  terminus → ONE invert, and there the pair rule does NOT apply: the high end
  of the run is the upstream head (its pipe leaves → I.O), the low end is the
  downstream terminus (its pipe arrives → I.I). Each row carries its pipe
  size: `I.O. 755.83 (8")`.
- **LATERALS** — every other registry line the structure sits on: a bare
  pipe block at TRUE elevation on the station X plus its own invert row(s).
  A shared line is BRACKETED against its own `_INV.pro` exactly as the
  primary is, so its direction is derived: one that terminates here yields
  one row (I.I arriving, I.O leaving), one that passes through yields both.
  Junctions that terminate at the structure are recovered by
  `pfi:endpoint-hits` (endpoint within `*pfi-junction-tol*`), whose station
  comes from `pf:cl-endpoints` — station-ordered — never from the drawn
  twin's vertex order, which is drafting direction.
- **TEXT** — all rows share ONE base Y = lowest invert present minus
  (`*pfi-invert-offset-factor*` × text height); columns fan left/right
  across the station X; justification MR (grows downward). The leftmost
  structure's stack shifts right to clear the elevation-axis labels.
  **Spacing is UNIFORM and the fan is CENTRED on the station X** — every
  centre-to-centre gap is `*pfi-row-gap-factor*` × height (2.0, its own
  constant), and the stack spans station X ± `halfw`, so an odd row count
  puts the middle row exactly on the station. Both come from two arguments
  to the shared `pfd:draw-label-stack`, which is NOT modified: `offset` =
  half a gap (making the straddle equal every other gap) and `lineX` slid
  left by half the fan's width. PFLABEL keeps its lopsided stack and wider
  straddle deliberately — `pfd:station-line` runs up through that gap and
  needs the room. `*pf-offset-factor*` and `*pf-gap-rest-factor*` play no
  part in PFINVERT's horizontal layout; tune `*pfi-row-gap-factor*` alone.
  COLUMN ORDER IS BY ROLE, not by arrival: the row that LEAVES the structure
  takes row 0 (left of the station line) whoever owns it — at a downstream
  terminus that is the continuing shared line, not the primary — shared rows
  go centre, and the primary's arriving I.I goes far right.
- **ONE STACK PER NODE.** A shared structure drafted as two or more blocks,
  one per line, is merged by `pfi:merge-nodes` when the stations match within
  `*pfr-node-tol*`. The node draws once; the blocks' line memberships are
  unioned by `pfi:node-hits` so every line at the node gets its row exactly
  once, and every block gets its membership record topped up.

Layer rule, pass ledger, undo: identical to PFLABEL (pass "INVERT";
CLAYER → "INVERT-CLAYER", fire-and-forget) — label stacks on `PF-ANNO` via
`pfd:anno-layer` unless "Use current layer" is on. The lateral pipe BLOCKS go
to PF-ANNO too as of 2026-07-29; they were on the derived `<TYPE>_P`
symbol layer before. Own run dialog `pfi_run`
(pi_* tiles) — but only the DIALOG is local. The gather-compute is
`pflabel:gather-compute`, the one copy: `pfi:rd-compute` was a line-for-line
duplicate of `pflabel:rd-compute` until 2026-07-27, and the duplicate had
already silently missed the drift echo. **No `.pro` is read on the gather
path** — the profile work is all downstream in the engine.

## Public API

Nothing in this file is called by another file. Wrapper hooks and command:

- `pfi:run anchor rd` — the ENGINE (twin of `pflabel:run`): consumes the
  order ticket, **writer** (own undo group via `'*pfinvert-undo-open*`);
  publishes `*pfinvert-run-ctx*` for the Esc flush, clears it on normal
  exit.
- `pfi:flush-pass` — Esc ledger flush (the `pf:run-command` hook).
- `C:PFINVERT` / `C:PFI` — `pf:run-command "PFINVERT" 'pfi:flush-pass
  'pfi:cmd`.

Internal: `pfi:setup` (record checks; the _INV .pro is FATAL when
missing), `pfi:invert-bracket` / `pfi:nearest-vert` (the exact-vertex
bracket), `pfi:lateral-info`, `pfi:endpoint-hits`, `pfi:inv-row`,
`pfi:size-at`, `pfi:node-hits`, `pfi:merge-nodes` / `pfi:merge-note`,
`pfi:process-structure`, `pfi:line-min-sta`,
`pfi:label-all` / `pfi:label-sel`, `pfi:write-pass`, `pfi:rd-*` +
`pfi:run-dialog`.

**Signature changes 2026-07-29.** `pfi:process-structure` takes
`(block-ename mates context)` — mates are the other blocks of a merged node.
`pfi:lateral-info` returns `(clfile (role elev size) ...)` instead of
`(elev size clfile)`; role is `'IO` | `'II`. The old prim-size helper became
`pfi:size-at` (it serves shared lines too). All four are file-local.

**The ticket carries the work, 2026-07-27.** `pfi:rd-sel` / `pfi:rd-all`
now file the gather's full station-sorted pending list under `'pend`
alongside `'sel`, and `pfi:run` threads both into the context.
`pfi:label-all` reads `'sel` instead of rebuilding it, and
`pfi:line-min-sta` takes `(caar pend)` instead of walking every inlet to
find one number it was standing next to. That is **two full inlet × line
membership scans removed from every PFINVERT run** — each point in them
costing a `cl_location_at_pt`. PFLABEL received this fix long ago; PFINVERT
never did, which is the same divergence class as the registry-builder and
same-type-membership bugs in OPEN-ISSUES. Both old paths survive only for a
caller handing over a ticket with no `'sel` / no `'pend`.

**STATUS is per-tool.** `pfi:write-pass` writes `STATUS_INVERT` and
validates the `_INV .pro` alone. It used to write the single shared
`STATUS`, so running PFINVERT after PFLABEL silently erased everything
known about the `.cl`.

## Invariants

- Every elevation this command draws comes from the bound `_INV.pro` — or,
  for a shared line, from ITS `_INV.pro`; no sampling, no grade tolerance
  (the exact-vertex bracket, now on both sides of a junction).
- Two adjacent vertices ≤ `*pfi-struct-width-max*` apart = ONE structure;
  a lone endpoint a pipe-run from its neighbour = a terminus.
- A structure whose NEAREST vertex is more than `*pfi-struct-width-max*` away
  has no invert in that `.pro` and is skipped with a printed reason. It must
  never inherit a neighbour's elevation — that failure is silent and prints a
  wrong number to the penny.
- `write-pass` validates the _INV .pro checksum AFTER labeling → STATUS.
- Line table comes from the ONE builder (`pflabel:registry-pairs`), so
  PFINVERT and PFLABEL cannot disagree about a junction's line set.
- The gather-compute is likewise ONE copy (`pflabel:gather-compute`), so the
  two cannot disagree about which structures are on a line or which already
  carry a pass. Invert-specific compute, if it ever arrives, composes on top
  of the shared call rather than forking it again — this divergence has
  already cost the suite three times (registry builder, same-type
  membership, drift echo).
- `pfi:rd-fill` shows the drift count in the `error` tile; the full DRIFT
  block prints from the shared gather.

## Open issues local to this file

- The I.I/I.O bracket rewrite and type-scoping are FIXED (pending CAD
  regression) in [../OPEN-ISSUES.md](../OPEN-ISSUES.md) PFINVERT.
- **FIXED-PENDING-CAD 2026-07-29** — terminus direction, shared-line
  direction, role-based columns, the vertex distance guard, the junction
  station, and shared-node merging. See the PFINVERT section of
  [../pfsuite-md/OPEN-ISSUES.md](../pfsuite-md/OPEN-ISSUES.md).
