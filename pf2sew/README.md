# pf2sew.lsp — C:PF2SEW, Carlson Hydrology `.SEW` export

**Load position:** 12 of 13 (after pfreport, before pfpalette).
**May depend on:** pftools-cfg, pftools-lib, pfanchor, pfsettings, pflabel,
pfxlabel, **pfreport** (the gather — see below).
**Depended on by:** nothing. Nothing calls `pfsew:`.

## What it owns

Writing a **Carlson Hydrology `.SEW`** from the profiles PFTools already holds,
so a drainage model can be *iterated for design* instead of keyed in by hand.

The format decoding, the decisions, and the evidence behind them live in
[../pf2sew.md](../pf2sew.md). This file is the contract; that one is the record
of why.

**Why this is not part of pfreport.** PFREPORT writes a one-way Hydraflow `.stm`
and deliberately zeroes hydrology. This is a design loop, not a report, and it
targets a different program with a different model — node-based, not link-based.
Two commands, one gather.

## The relationship with pfreport

**PF2SEW calls PFREPORT's gather directly.** `pfr:line-pipes`, `pfr:build-nodes`,
`pfr:order`, `pfr:validate`, `pfr:line-table`, `pfr:candidates`, `pfr:row` and
the `pfr:g` / `pfr:nd-*` accessors are used as-is. Load order permits it —
pfreport is above this file — and the node/pipe model they build is already the
shape `.SEW` wants.

**This is a deliberate deviation from the plan in `../pf2sew.md` §8 step 1**,
which called for hoisting that gather into `pf:` engine code *first*. The hoist
is still the right end state and stays ticketed in
[../pf2sew.md](../pf2sew.md) §8 step 1. It was not done
first because **neither PFREPORT nor PF2SEW has run in CAD**, and refactoring the
shared gather before either one is verified would put two unproven things in
flight at once — a failure in CAD could then be the export, the gather, or the
move. Doing it after both pass is strictly cheaper to debug.

The one change made to `pfreport` for this command is **additive and inert on
the `.stm` path**: `pfr:node-of` now carries `'blk` (the structure's block name,
already sitting in `pfr:struct-at`'s return), and the node table grew a sixth
element for it with a `pfr:nd-blk` accessor. `pfr:record` never reads either.

## The model

The `.SEW` is **node-based**: structures are first-class and connectivity is
`DownstreamStructureID` / `UpstreamStructureID` naming them. **Length and slope
are never stored — Carlson derives both** from the structure centres.

| `.sew` field | Source |
|---|---|
| `<Center X/Y>` | node `xy` — `cl_location_at_sta` on the `.cl` at the structure's CENTRE station |
| `<Center Z>`, `<Elevation Rim>` | the drafter-filled `T.R.` / `T.G.` / `G.L.` TEXT PFLABEL drew |
| `<Elevation Base>` | the outgoing pipe invert at that structure; the arriving one at the outfall |
| `<Elevation JunctionDrop>` | arriving − leaving invert, where they differ by more than `*pfr-invert-tol*` |
| pipe `<Elevation Downstream/Upstream>` | the two `_INV.pro` vertices the pipe spans, **verbatim** |
| `<Pipe Rise>` | `pf:pipe-at` at the pipe midpoint — **inches, no division** |
| `Material`, `ManningsValue` | the record's material; n through `*pfr-nvalues*` |
| `Name` | `pf:combine-id` — byte-identical to PFLABEL's sheet label |
| `Desc` | the `*pf-rule-table*` TYPE string — the sheet's own words |
| `SwrStruct` / `HydroInlet` / `Symbol` / `Width` | `*pfsew-type-map*`, keyed on the block name |
| `SewerNodeID` | synthetic, `CSMH<n>`, numbered outfall-first |
| `Down/UpstreamStructureID`, `<Graph>` | the graph builder (`pfr:build-nodes` → `pfr:order`) |
| drainage area, catchment flow, Tc | **0** — never fabricated |
| Cf, CN, swamp factor, pavement, grate + curb geometry | **Carlson's own defaults**, inert while Area is 0 |

### Why hydrology is defaulted, not zeroed

PFREPORT zeroes hydrology because a plausible-looking drainage area would
mislead someone reading a model they did not build. The same reasoning applies
to **area** here, and area exports as 0 — visibly unentered in Carlson.

It does *not* apply to the coefficients around it. `Cf`, `ScsCN`, the grate weir
coefficient and so on are Carlson's own defaults for an un-entered structure;
they are inert while `Area` is 0, and writing them is what lets the file open and
compute capacity at all. Verified against `Carlson_References/STORM_CA.sew`,
which is exactly such a file.

Authoring real drainage areas is a later phase (`../pf2sew.md` §8 step 5) and is
this tool's job when it comes — unlike PFREPORT, there is no policy against it.

## Tunables

**Everything a drafter might want to change is in `*pfsew-opts*` in
`pftools-cfg.lsp`**, a flat `(KEY VALUE LABEL)` table read at emit time through
`pfsew:opt`. Not thirty named globals, and not constants in this file.

That shape is the point: **the planned home for these is a settings page or a
`pfpalette` tab**, and a data-driven table is one `foreach` away from a tile per
row. `pfsew:set-opt` is the write seam that page will use — it is currently
called by nothing, deliberately, and `pf-verify` lists it as a dead-code
candidate for that reason.

Reading at emit time (never captured at load) means a changed value takes effect
on the next export with no reload.

**When that tab is built** it must respect the palette write-free contract: the
options table is in-memory state, so reading it is safe from a modeless handler,
but persisting it (to NOD or a profile) is a write and belongs behind
`pfp:defer`. Values are strings and go into XML attributes verbatim — a tile
that collects a number must still store it as text.

## `*pfsew-type-map*`

A **parallel** table to `*pf-rule-table*`, keyed on the same token lists through
the same `pf:rule-for` matcher — not extra columns on `*pf-rule-table*` itself.
That table is load-bearing for every sheet label PFLABEL draws; export concerns
do not belong in the drafting path, and a row added here can never change a
label. Both still move together when a rule changes, which is the property that
mattered.

**Every row currently resolves to one of the four library entries confirmed
present on the target install** (`MH1`, `Outfall-Funnel`, `Combo-Grade`,
`INLET3`, all read out of `Carlson_References/STORM_CA.sew`). That is on purpose:
a file that opens beats a file naming a library entry Carlson does not have. The
rows are correct in *shape* and provisional in *content* — refining them needs
the library enumeration listed below.

## Public API

Nothing here is called by another file. Command + engine:

- `C:PF2SEW` — `pf:run-command "PF2SEW" nil 'pfsew:cmd`.
- `pfsew:run sel` — the ENGINE: consumes a list of `pfa:registry` rows and does
  everything. Pure read; the `.sew` is the only write.
- `pfsew:run-dialog rows` — `pfsew_run` (`sw_*` tiles).
- `pfsew:opt key` / `pfsew:opt-num key` / `pfsew:set-opt key val` — the options
  seam, for a future settings page or palette tab.

Internal, by section: options (§1), library mapping (`pfsew:type-for`,
`pfsew:desc-for`, `pfsew:tm-*`), XML grammar (`pfsew:num`, `pfsew:xy`,
`pfsew:elev`, `pfsew:esc`, `pfsew:att`, `pfsew:atts`, `pfsew:pad`), the node view
(`pfsew:node-id`, `pfsew:node-invs`, `pfsew:node-base`, `pfsew:node-drop`,
`pfsew:node-order`, `pfsew:system-of`, `pfsew:name-of`), emit
(`pfsew:settings`, `pfsew:hydro-inlet`, `pfsew:structure`, `pfsew:pipe`,
`pfsew:graph`), the writer (`pfsew:write`), and the run
(`pfsew:default-path`, `pfsew:untyped`, `pfsew:cmd`).

## Invariants

- Nothing here writes the drawing. No `entmake`, no `command`, no undo group —
  satisfied by construction, same as PFREPORT.
- **Four concatenated fragments, no XML declaration, no single root element.**
  `<SewerSettings>`, `<SewerNetwork>`, `<Graph>` are siblings at top level.
  Wrapping them in a root is expected to break Carlson's reader.
- **`Rise` is INCHES.** `pf:pipe-at` already returns nominal inches, so there is
  no `÷ 12` here. The Hydraflow path's division does not apply.
- **Length and slope are never written.** Carlson derives them from the centres.
  A slope that disagrees with the sheet is a Carlson *labelling* setting — set
  the mains to "actual pipe slope".
- Pipe inverts are the `.pro` vertices unmodified. Traceability outranks display
  fidelity; see `../pf2sew.md` §4.
- Every attribute value passes through `pfsew:esc`. Structure IDs derive from
  drawing text, so an unescaped `&` is a real failure mode, not a theoretical
  one.
- A rim still reading `*pf-elev-placeholder*` is UNFILLED: it exports as 0 with a
  named warning, never as a number nobody typed. Inherited from `pfr:rim-at`.
- Drop structures survive: adjacent pipes carry different elevations at a shared
  node, `Base` takes the outgoing one, `JunctionDrop` takes the difference.

## Open issues local to this file

- **UNTESTED IN CAD.** Nothing here has been run. The gates, in order:
  1. Loads clean; `PF2SEW` opens its dialog.
  2. A single-line export of `Carlson_References/STORM_CA` opens in Carlson
     without complaint.
  3. Inverts, rises, materials and rims match the sheet: 743.00 / 743.50→744.00
     / 747.2308 / 747.7308 / 749.00, a 24″ pipe then three 18″.
  4. The 1.00003 % pipe reads 1.00 % under "actual pipe slope".
  5. The 0.5 ft drop at the second structure survives the round trip — this is
     the `Base` / `JunctionDrop` convention check.
  6. Capacity computes.
  7. A trunk-plus-branch export: connectivity matches the drawing.
  8. A deliberately broken pick (two disconnected lines) aborts with both names.
- **The `Base` / `JunctionDrop` sign is an inference.** `Base` carries the
  outgoing invert and `JunctionDrop` the positive arriving − leaving difference.
  If Carlson reads the sign the other way, it is one negation in
  `pfsew:node-drop`. Gate 5 settles it.
- **`*pfsew-type-map*` content is provisional.** Needs the real Carlson library
  enumeration: material strings, structure IDs, inlet IDs, `Type` enum domains,
  and available symbol block names. Shape is right; names are the four known-good
  ones repeated.
- **Whether `Symbol` accepts an arbitrary block name** decides whether the block
  library is new work or a naming pass. See `../pf2sew.md` §9.8.
- **`Width` comes from `*pfsew-type-map*`, not from the `.pro`.** The drafted
  vertex gap is a profile-view width and may not be the true plan dimension —
  STORM_CA's are 2.08–2.54 ft, narrow for a real inlet. If Bryant draws them to
  true width, `Width` should switch to the measured gap.
- **`<Libraries/>` is written empty**, as Carlson writes it. If it can be
  populated, the export becomes self-contained and stops depending on the target
  machine's configuration. Highest-value unknown in the format.
- Rim reads inherit PFLABEL's **CRITICAL** open bug: a structure PFLABEL silently
  dropped near a deflection PI has no elevation row, so its rim exports as 0 with
  a warning. See [../pfsuite-md/OPEN-ISSUES.md](../pfsuite-md/OPEN-ISSUES.md).
- **Carlson has its own plan-view annotation engine.** Handing over a `.SEW`
  hands over a second labelling engine; its labels auto-redraw when network data
  changes. That is plan view, so it should not collide with PFLABEL's profile
  work.
