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
(pi_* tiles), standalone so invert-specific fields can grow.

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

## Invariants

- Every elevation this command draws comes from the bound `_INV.pro`; no
  sampling, no grade tolerance (the exact-vertex bracket).
- Two adjacent vertices ≤ `*pfi-struct-width-max*` apart = ONE structure;
  a lone endpoint a pipe-run from its neighbour = a terminus.
- `write-pass` validates the _INV .pro checksum AFTER labeling → STATUS.
- Line table comes from the ONE builder (`pflabel:registry-pairs`), so
  PFINVERT and PFLABEL cannot disagree about a junction's line set.

## Open issues local to this file

- None open — the I.I/I.O bracket rewrite and type-scoping are FIXED
  (pending CAD regression) in [../OPEN-ISSUES.md](../OPEN-ISSUES.md)
  PFINVERT.
