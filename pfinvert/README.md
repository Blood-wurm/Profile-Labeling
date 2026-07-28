# pfinvert.lsp — C:PFINVERT, invert labels at structures

**Load position:** 9 of 10 (after pfxlabel, before pfpalette).
**May depend on:** pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings,
pfsetup, pflabel (structure walk + shared builders), pfxlabel
(`pfxl:src-files` registry file resolution).
**Depended on by:** pfpalette only transitively (nothing calls pfi:).

## What it owns

THE COMMAND SPLIT (locked): PFLABEL owns top-of-grid text; PFINVERT owns
EVERYTHING AT PIPE ELEVATION. At each structure on the primary line:

- **PRIMARY** — in/out inverts, TEXT ONLY. I.O/I.I are the two ADJACENT
  `_INV.pro` VERTICES that meet at the structure (`pfi:invert-bracket`
  over `pf:pro-verts`): each vertex IS an invert, so the reading is exact.
  The LOWER of the pair is downstream → I.O. A polyline endpoint is a
  terminus → ONE invert. Each row carries its pipe size: `I.O. 755.83 (8")`.
- **LATERALS** — every other registry line the structure sits on: a bare
  pipe block at TRUE elevation on the station X plus an `I.I <elev> (NN")`
  row. Junctions that terminate at the structure are recovered by
  `pfi:endpoint-hits` (endpoint within `*pfi-junction-tol*`).
- **TEXT** — all rows share ONE base Y = lowest invert present minus
  (`*pfi-invert-offset-factor*` × text height); columns fan left/right
  across the station X; justification MR (grows downward). The leftmost
  structure's stack shifts right to clear the elevation-axis labels.

Layer rule, pass ledger, undo: identical to PFLABEL (pass "INVERT";
CLAYER → "INVERT-CLAYER", fire-and-forget). Own run dialog `pfi_run`
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
`pfi:prim-size`, `pfi:process-structure`, `pfi:line-min-sta`,
`pfi:label-all` / `pfi:label-sel`, `pfi:write-pass`, `pfi:rd-*` +
`pfi:run-dialog`.

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

- Every elevation this command draws comes from the bound `_INV.pro`; no
  sampling, no grade tolerance (the exact-vertex bracket).
- Two adjacent vertices ≤ `*pfi-struct-width-max*` apart = ONE structure;
  a lone endpoint a pipe-run from its neighbour = a terminus.
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

- None open — the I.I/I.O bracket rewrite and type-scoping are FIXED
  (pending CAD regression) in [../OPEN-ISSUES.md](../OPEN-ISSUES.md)
  PFINVERT.
