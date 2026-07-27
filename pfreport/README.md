# pfreport.lsp — C:PFREPORT, Hydraflow Storm Sewers `.stm` export

**Load position:** 10 of 11 (after pfinvert, before pfpalette).
**May depend on:** pftools-cfg, pftools-lib, pfanchor, pfsettings, pflabel
(line table, structure walk, station index), pfxlabel (`pfxl:src-files`).
Does **not** depend on pfdraw or pfsetup — it draws nothing and registers
nothing.
**Depended on by:** nothing. Nothing calls `pfr:`.

## What it owns

Writing a populated **Hydraflow Storm Sewers 2003 `.stm`** file from the
profiles PFTools already holds, so the engineer opens a working hydraulic
model instead of keying inverts, rims, sizes, lengths and slopes by hand.

**Why `.stm` and not DXF.** Hydraflow's DXF import populates plan view only —
every hydraulic value stays manual entry. That automates the easy half. The
hydraulic half is exactly what PFTools has as authored data, so this export
*replaces* the DXF step; plan coordinates come along free off the `.cl`.

Two things make this command unlike the other four:

- **It is SYSTEM-scoped.** No anchor pick, no `pfs:choose-or-place`. The user
  multi-selects a SET of registered profiles and the export builds one network
  out of them. It cannot reuse the target-directed pattern.
- **It is READ-ONLY on the drawing.** The `.stm` on disk is the only write, so
  there is no undo group, no pass ledger, no STATUS update, and no Esc flush
  hook (`pf:run-command "PFREPORT" nil 'pfr:cmd`).

## The model

The `.stm` is **link-based, not node-based**: each record is a pipe carrying
both of its ends (invert dn/up, rim dn/up, length, slope, Rise/Span in feet).
Structures are implied at shared endpoints; the structure ID rides as
`Inlet ID`. Connectivity is `Downstream Line No.`; 0 is the outfall.

PFTools' `_INV.pro` already encodes that shape. Reading it the way PFINVERT
does — every vertex IS an invert, adjacent vertices ≤ `*pfi-struct-width-max*`
apart are ONE structure — the profile decomposes into *structure, pipe,
structure, pipe*. `pfr:groups` does the whole walk in one pass; the groups are
the structures and the gaps between them are the exported lines.

| `.stm` field | Source |
|---|---|
| `X,Y Coord Dn` / `Up` | Road API `cl_location_at_sta` on the `.cl` |
| `Invert Elev Dn` / `Up` | the two `_INV.pro` vertices the pipe spans |
| `Line Length`, `Line Slope` | derived from those stations + inverts |
| `Rise`, `Span` | `pf:pipe-at` at the pipe MIDPOINT ÷ 12 |
| `Ground / Rim Elev Dn` / `Up` | the drafter-filled `T.R.` / `T.G.` / `G.L.` TEXT PFLABEL drew |
| `N-Value` | the record's material through `*pfr-nvalues*` |
| `Inlet ID` | `pf:combine-id` — byte-identical to PFLABEL's sheet label |
| `Line No.` / `Downstream Line No.` | the graph builder (§ below) |
| `Bearing`, `Deflection Angle` | plan geometry (decoded below) |
| hydrology, grate + gutter geometry | **zeroed**, never fabricated |

## Decisions

- **Target version 2003** — the firm's install; no compatibility risk.
- **Membership is user-selected** from the registry. Matches current practice,
  avoids auto-detecting network boundaries, and inherits registry validation.
  **Stubs cannot be picked** — a registered line has no grid, so it has no rim
  elevations to read. `pfr:candidates` names every exclusion on the command
  line.
- **Connectivity is X,Y coincidence** (`*pfr-node-tol*`, 2 ft), matched at each
  structure's CENTRE station. Immune to the drop-structure problem that
  defeats elevation matching.
- **Direction is `.cl` stationing** — `*pfr-sta-upstream*`, consistent across
  projects, so direction is free. A wrong value cannot fail silently: every
  pipe on the line reads adverse and `pfr:validate` says so by name.
- **Elevation is validation, never derivation.** Invert continuity confirms
  the match; a coincident pair whose inverts disagree by other than a designed
  drop is reported as a drawing error.
- **Hydrology zeroed, not fabricated.** A zero drainage area is visibly
  unentered in Hydraflow; a plausible one is not.
- **Rainfall is not PFTools data.** The trailer carries the reference file's
  NAMED curve (`*pfr-idf-name*`) so the `.stm` opens and so the engineer can
  see which curve is loaded in Hydraflow's Rainfall tab. The export prints a
  warning naming it every run. Nothing computed depends on it while hydrology
  is zeroed.

### Two corrections to the original plan, from `_Sampl.txt`

- **Coordinates are real survey coordinates**, not a local system — the
  sample carries 1804860, 831939.1 against stated lengths in feet. There is
  no translation to a local origin and no offset to retain.
- **Multi-select is not a new dialog primitive.** `pf_run`, `pfi_run`,
  `pfxl_run` and `pf_scan` are already `multiple_select = true` list boxes.
  `pfrpt_run` is modelled on `pf_run`; nothing new was needed, and this
  command is therefore not the trigger for lifting shared dialog code into
  `pfui:`.

### Decoded from the sample, not documented anywhere

- **Number grammar** — ~7 significant digits, trailing zeros dropped, and the
  leading zero of a magnitude < 1 dropped: `-.3674316`, `.016`, `59.98177`.
  `pfr:num` reproduces it, so an export diffs cleanly against a
  Hydraflow-written file.
- **`Bearing`** = the NEGATED azimuth CCW from +X, normalised to **[0,360)**.
  Sample line 5 is what pins the branch: it reads `-215.8961`, not the
  `+144.4` a (-180,180] convention would give.
- **`Deflection Angle`** = `Bearing(this) − Bearing(downstream line)`, and the
  bearing itself at the outfall.
- **`Downstream Inlet No.`** equals `Downstream Line No.` — inlet *N* sits at
  the upstream end of line *N*, so the inlet at a pipe's downstream end is the
  downstream line's own.

## The graph builder

Selection bounds the search; it does not supply order. `Line No.` /
`Downstream Line No.` are derived:

1. Every pipe endpoint resolves to a node by plan coincidence
   (`pfr:build-nodes`); a node shared by two lines is ONE table entry.
2. Pipe *P* drains into the pipe whose UP node is *P*'s DN node
   (`pfr:ds-idx`); none means outfall.
3. **Exactly one outfall, or the export stops** and names each offending line
   with its station and structure ID. Two pipes leaving one structure, and any
   pipe that never reaches the outfall, stop it the same way.
4. Numbering is breadth-first from the outfall, so `Downstream Line No.` is
   always lower than its own `Line No.` — the shape Hydraflow itself writes.

Three independent signals with only one load-bearing: plan coincidence builds
the graph, stationing gives direction, invert continuity proves both.

## Public API

Nothing here is called by another file. Command + engine:

- `C:PFREPORT` / `C:PFR` — `pf:run-command "PFREPORT" nil 'pfr:cmd`.
- `pfr:run sel` — the ENGINE: consumes a list of `pfa:registry` rows and does
  everything. Pure read; the `.stm` is the only write.
- `pfr:run-dialog rows` — `pfrpt_run` (rp_* tiles).

Internal, by section: findings (`pfr:fatal` / `pfr:warn` / `pfr:report`),
number grammar (`pfr:num`, `pfr:trim-num`, `pfr:kv*`), record accessors
(`pfr:g` / `pfr:p`, `pfr:nd-*`), plan geometry (`pfr:xy`, `pfr:bearing`),
decomposition (`pfr:groups`, `pfr:grp-*`), drawing reads (`pfr:elev-texts`,
`pfr:band-texts`, `pfr:rim-at`, `pfr:struct-id`, `pfr:struct-at`), per-line
build (`pfr:node-of`, `pfr:line-pipes`), graph (`pfr:build-nodes`,
`pfr:ds-idx`, `pfr:order`, `pfr:bearings`), validation (`pfr:validate`),
emit (`pfr:record`, `pfr:write`).

## Invariants

- Nothing here writes the drawing. No `entmake`, no `command`, no undo group
  — the read/write contract of the root README §5, satisfied by construction.
- Pipe ends are the `.pro` VERTEX stations (face to face), so length, inverts
  and slope stay mutually consistent with the authored profile. Node identity
  is the structure's CENTRE station — never the vertices, which sit half a
  structure away on each side. Consequence: adjacent lines' plan endpoints
  differ by half a structure at a shared node; connectivity is explicit in
  `Downstream Line No.`, so nothing depends on them coinciding.
- Pipe identity is `idx`, never list identity — every stamp returns a new list.
- Field ORDER in a record is load-bearing: it is `_Sampl.txt`'s, record for
  record.
- A rim row still reading `*pf-elev-placeholder*` is UNFILLED. It exports as 0
  with a named warning, never as a number nobody typed.
- Drop structures survive the round trip: adjacent pipes carry different
  elevations at a shared node, exactly as the `.pro` encodes it.

## Shared gather (2026-07-27)

`pfr:line-table` funnels through `pflabel:build-lines` — so PFREPORT inherits
the corridor-pre-filter fix and `pf:cl-parse`'s exact vertices without
changing a line. Note `pfr:line-table` **unions across utility types** where
PFLABEL is single-type, so a mixed selection reads several line sets.

`pfr:struct-id` recomputes exactly what PFLABEL computes —
`pf:lines-at-point` + `pf:rank-on-line` over the index, then
`pf:combine-id`. That is deliberate (the `.stm`'s Inlet ID and the sheet
label must be the same string by construction), but it means PFREPORT is a
first-class consumer of the persistent membership index designed in the root
README §11, not an afterthought to it.

## Open issues local to this file

- **UNTESTED IN CAD.** Nothing here has been run. The gates, in order:
  1. Loads clean and `PFREPORT` opens its dialog.
  2. `pfr:num` against the sample — every literal in `_Sampl.txt` should
     round-trip.
  3. A single-line export, opened in Hydraflow: inverts, lengths, sizes and
     rims match the sheet.
  4. A trunk-plus-branch export: `Downstream Line No.` matches the drawing.
  5. A deliberately broken pick (two disconnected lines) must abort with both
     names.
- **`Line Slope` units are an inference.** The sample carries 0 for every line
  (Hydraflow had not computed them), so percent-vs-ft/ft comes from the Storm
  Sewers UI, not from evidence. `*pfr-slope-percent*` is the one-line flip if
  a round trip disagrees.
- **`*pfr-sta-upstream*` is set to the firm's assumed convention** and has not
  been confirmed against a real project. Wrong = every pipe adverse = a named
  fatal, so it cannot corrupt an export; it can only stop one.
- **`Junction Loss Coeff`** is written as a constant. The header turns
  Hydraflow's auto-compute ON, so the value is inert — confirm on the first
  round trip.
- Rim reads inherit PFLABEL's **CRITICAL** open bug: a structure PFLABEL
  silently dropped near a deflection PI has no elevation row to read, so its
  rim exports as 0 with a warning. See [../OPEN-ISSUES.md](../OPEN-ISSUES.md).
- The rim scan reads **any** model-space TEXT starting with a rule prefix, not
  just PFLABEL's tracked pass. Deliberate — it also picks up hand-typed rows —
  but it means stray text in the grid band can be claimed. The
  nearest-structure test in `pfr:rim-at` is the only guard.
