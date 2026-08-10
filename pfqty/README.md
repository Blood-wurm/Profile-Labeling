# pfqty.lsp — C:PFQTY, material quantities takeoff

**Load position:** 13 of 14 (after pf2sew, before pfpalette).
**May depend on:** pftools-cfg, pftools-lib, pfanchor, pfsettings, pflabel
(line table, structure walk, station index), pfreport (the gather).
`pfa:src-files` is pfanchor's as of 2026-08-06, so pfxlabel is no longer a
dependency. Does **not** depend on pfdraw, pfsetup or pf2sew — it
draws nothing and registers nothing, and nothing depends on it.

## What it owns

A **quantities takeoff** of everything PFTools already holds: pipe LF grouped
by utility type, size and material, and structure counts grouped by type and
size. The output is a plain `.txt` — the bid-item half of the sheet, written
from the same authored profiles the labels are drawn from, so the schedule and
the drawing cannot disagree.

Like PFREPORT it is **SYSTEM-scoped** (multi-select from the registry, no
anchor pick) and **READ-ONLY on the drawing** — the `.txt` is the only write,
so no undo group, no pass ledger, no STATUS update.

## The model

None of the data is new. `pfr:groups` already decomposes an `_INV.pro` into
*structure, pipe, structure, pipe*; a pipe already carries its two stations,
its material and its size; `pf:rule-for` already classifies a structure's block
into a type. PFQTY is a third emitter over that gather — it aggregates instead
of writing a hydraulic model.

| quantity | source |
|---|---|
| pipe LF | the two `_INV.pro` vertex stations bracketing the gap |
| pipe size | `pf:pipe-at` at the pipe MIDPOINT |
| pipe material | the anchor's `FILES` code 5, via `pfa:src-files` |
| structure type / size | `pfq:struct-info` — attribute, then `*pf-rule-table*` |
| structure count | one per node table entry |

## Decisions

- **Length is OUT TO OUT of the structures.** A pipe spans from the outside
  wall of one structure to the outside wall of the next, which is exactly the
  two `.pro` vertices bracketing the gap. Structures therefore contribute no
  LF, which is what makes the per-line subtotals add up to the grand total
  with no adjustment for shared junctions. It is the along-alignment length
  (the station difference), not the slope distance — the same figure PFREPORT
  writes as `Line Length`. Centre-to-centre was considered and rejected
  (Jake, 2026-08-04).

- **Size changes only AT a structure**, asserted by Jake 2026-08-04. That makes
  the midpoint sample the segment's *true* size rather than an approximation,
  so there is no splitting and no tolerance to tune. The two quarter-point
  samples cost two more cached `.pro` reads and turn the assertion into a
  checked one: disagreement is a named warning, and the length is still taken
  off at the midpoint size.

- **Structure type and size resolve ATTRIBUTE FIRST** (`pfq:struct-info`).
  Nothing in the drawing carries `*pfq-attr-type*` / `*pfq-attr-size*` today,
  so every lookup falls through to `*pf-rule-table*` — but the day the blocks
  are retagged or hard-coded with those attributes, the report reads them with
  no code change. This is the reason it is a function and not an inline
  `(pf:rule-type (pf:rule-for ...))`.

- **Nothing is defaulted.** An unbound material reads `UNSPECIFIED`, not the
  per-type default PF2SEW falls back to; a pipe with no `_TOP` reads `UNKNOWN`;
  a structure group with no block within a structure width reads
  `UNIDENTIFIED`. A quantity sheet is the wrong place to discover an
  assumption — a gap in the record has to show up on the sheet.

- **The findings ride IN the file.** The `.txt` is the deliverable; a note that
  only reached the command line is a note nobody keeps.

- **Every value read out of a drawing record goes through `pfq:str`** before it
  reaches `strcase`, `strcat` or `/=` — all three hard-error on a non-string in
  AutoLISP rather than returning nil, and a first CAD run aborted with
  `bad argument type: stringp T` from exactly that (2026-08-04). Guarded at the
  four read boundaries: the material, the `.cl` path, the block name, and an
  attribute value. A record holding something unexpected has to show up on the
  sheet as UNSPECIFIED / UNKNOWN / UNIDENTIFIED, never stop the takeoff.

## Three differences from PFREPORT

All the same point — a takeoff is not a hydraulic model:

1. **No graph.** No outfall rule, no ordering, no connectivity validation. Four
   disconnected lines are a legitimate takeoff, so `pfr:order` / `pfr:validate`
   are not on this path at all.
2. **Stubs count.** `pfr:candidates` excludes them because a stub has no grid
   and therefore no rim elevations to read. Quantities read no rims, so
   `pfq:candidates` requires only an `_INV.pro` on disk. The dialog's Grid
   column says which is which.
3. **No rim reads.** Which also keeps this command clear of PFLABEL's
   dropped-structure bug — there is no elevation row to be missing.

A missing or unreadable `.cl` is a **warning** here, not the fatal it is in
PFREPORT: lengths and structure stations both come off the `_INV.pro`, so the
only thing lost is the plan coincidence that merges a junction shared with
another selected line. That is a possible double count of one structure, named
on the command line — not a wrong quantity.

## Reuse, and the one duplication

Reused from pfreport as-is: `pfr:groups` / `pfr:grp-*`, `pfr:struct-at`,
`pfr:struct-id`, `pfr:xy`, `pfr:node-index`, `pfr:g` / `pfr:p` /
`pfr:set-nth`, `pfr:line-table`, and the whole findings machinery
(`pfr:fatal` / `pfr:warn` / `pfr:report`, `*pfr-fatal*` / `*pfr-warn*`).

**Not** reused: `pfr:node-of` and `pfr:line-pipes`, which read rims.
`pfq:node-of` and `pfq:line-pipes` are those two minus the rim, and that is the
one real duplication in this file. Adding a skip-rims argument to pfreport
would have been an arity change across two CAD-untested commands; a global flag
that changes another module's behaviour is worse. When the gather hoist in
[../pf2sew.md](../pf2sew.md) §8 step 1 happens, all three collapse into one
`pf:` engine walk — a third consumer is the argument for finally doing it.

## Public API

Nothing here is called by another file. Command + engine:

- `C:PFQTY` / `C:PFQ` — `pf:run-command "PFQTY" nil 'pfq:cmd`.
- `pfq:run sel` — the ENGINE: consumes a list of `pfa:registry` rows and does
  everything. Pure read; the `.txt` is the only write.
- `pfq:run-dialog rows` — `pfqty_run` (qt_* tiles).

Internal, by section: the seam (`pfq:attr`, `pfq:struct-info`), gather
(`pfq:node-of`, `pfq:line-pipes`), node table (`pfq:build-nodes`,
`pfq:nd-*`), tallies (`pfq:bump`, `pfq:pipe-tally`, `pfq:struct-tally`,
`pfq:sort-rows`, `pfq:*-sortkey`, `pfq:total-*`, `pfq:row-*`), rendering
(`pfq:pipe-block`, `pfq:struct-block`, `pfq:by-line`, `pfq:compose`,
`pfq:write`, `pfq:lf`, `pfq:lpad`, `pfq:now`, `pfq:*-size-text`,
`pfq:line-nodes`, `pfq:shared-count`), selection (`pfq:candidates`,
`pfq:row`, `pfq:rd-*`, `pfq:default-path`).

## Invariants

- Nothing here writes the drawing. No `entmake`, no `command`, no undo group.
- **Every sort key and every report cell is built with `pfq:text`**, not bare
  `strcat`. Sort keys and cells are DERIVED strings over data read from four
  records through three modules; `strcat` / `/=` hard-error on a non-string,
  and `vl-princ-to-string` accepts anything. A value nobody expected prints
  itself in its column instead of killing a finished report — the report
  becomes its own diagnosis, which is strictly better than a guard that
  silently swallows it.
- **One structure can never kill the takeoff.** Both identity reads in
  `pfq:node-of` go through `pfq:safe`, the same catch-wrap and the same reason
  as `pfa:memb-sync`: the structure still counts (the `.pro` says it is there),
  it counts as UNIDENTIFIED, and the warning carries the station, the block
  name and AutoLISP's own message. The diagnosis arrives in the deliverable —
  a report that names the bad record costs nobody a CAD session, and a command
  that aborts and needs a command-line probe costs one.
- **A structure is counted exactly once**, whatever number of selected lines it
  serves. The node table's `lines` column is the whole mechanism: a shared
  junction is *listed* under every line it serves in the BY LINE section, and
  tallied once in the totals. The per-line block says so in a footnote.
- Structures contribute no length, so the BY LINE subtotals sum to the grand
  total exactly. If they ever do not, the node merge is wrong.
- The pipe key carries the utility type — 12" RCP on a storm line and 12" RCP
  on a sanitary line are two bid items. The structure key does **not**: a
  structure is shared by plan coincidence, and a junction between a storm and
  a sanitary line is still one structure.
- Node identity is the structure BLOCK, falling back to plan coincidence within
  `*pfr-node-tol*` at the CENTRE station only where there is no block — the same
  rule the `.stm` graph uses, so a junction the export merges is a junction this
  counts once.
- **`xy` stays at index 0 and the structure block at index 6.** `pfr:node-index`
  reads a table entry through `pfr:nd-xy` `(nth 0)` and `pfr:nd-ent` `(nth 6)`.
  Those two shared columns are the whole reason this table can borrow pfreport's
  matcher instead of carrying a second copy of it.
- The node table index is taken AT INSERT, never re-looked-up. A node with
  neither a plan coordinate nor a block can never match `pfr:node-index`, so
  re-searching would stamp
  a nil index.

## Open issues local to this file

- **UNTESTED IN CAD.** Nothing here has been run. The gates, in order:
  1. Loads clean and `PFQTY` opens its dialog with stubs listed.
  2. A single-line takeoff: LF per size matches a hand scale of the profile,
     and the structure count matches the sheet.
  3. A trunk-plus-branch takeoff sharing one junction: the structure appears
     under both lines, the totals count it once, and the per-line LF subtotals
     sum to the grand total.
  4. A line with no `_TOP` bound: every pipe reads UNKNOWN and nothing aborts.
  5. A deliberately disconnected pick: completes normally — this is the
     difference from PFREPORT that most needs proving.
- **`pfq:attr` is untested against a real attributed block.** No block in the
  drawing carries the tags today, so the whole seam currently exercises only
  its `nil` path.
- Structure **size is nil for every rule-table type except HDWL**, which parses
  one out of its block name. Until the blocks carry a SIZE attribute the
  Size column reads `-` for every manhole and inlet — that is the known gap
  this design is shaped around, not a defect.
- `*pfq-lf-decimals*` is 1. Whether the firm wants LF rounded up to whole feet
  per bid item is a question for the first real sheet.
