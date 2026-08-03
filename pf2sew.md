# pf2sew — PFTools line data → Carlson Hydrology `.SEW`

**Status: design settled, nothing built.** Drafted 2026-07-29 from one real
sample (`TEST_StormProfiles.sew`, Carlson Software 2025, 84 structures / 83
pipes) plus the Hydrology Module chapter of the Carlson 2026 manual. Revised
2026-07-31 against a second, cleaner sample — the `Carlson_References/STORM_CA`
trio, where one `.cl`, one `_INV`/`_TOP` `.pro` pair and one `.sew` describe the
same stormline. The build in §8 is written off that trio.

## 1. What this is, and what it is not

A tool that takes line data PFTools already gathers and writes a Carlson
Hydrology `.SEW`, **so drainage models can be iterated for design.**

It is **not** an extension of `pfreport`. PFREPORT writes a one-way Hydraflow
`.stm` report and deliberately zeroes hydrology, because a plausible-looking
drainage area would silently mislead someone reading a model they did not
build. That reasoning does not apply here: this tool exists to carry drainage
areas, and **authoring hydrology is its job.** There is no policy being
reversed.

Consequences of being its own tool:

- Own module, own folder, own README. Prefix **`pfh:`** — verified free
  2026-07-31; no `pfh:` symbol exists anywhere in the suite.
- It is a design loop, not a report. Expect re-export after drafting changes,
  and consider whether results ever need to come *back* from Carlson. That
  question is open and it shapes everything.
- Load position is after whatever gather code it consumes. Commands run under
  `pf:run-command`; the gather stays write-free.

## 2. The format, decoded from the sample

**VERIFIED — safe to build on:**

- **Four concatenated fragments, no XML declaration, no single root:**
  `<SewerSettings>`, `<SewerNetwork>` (containing `<SewerStructures>` then
  `<SewerPipes>`), `<Graph>`. A plain text writer is sufficient — no XML
  library. **It must stay fragments**; wrapping it in a root element is likely
  to break Carlson's reader.
- **Node-based.** Connectivity is `DownstreamStructureID` /
  `UpstreamStructureID` naming structures directly. No line numbers, no
  bearings, no deflection angles. Pipe 1 is at the outfall; inverts rise going
  upstream.
- **Length and slope are never stored — Carlson derives both.** Length is the
  2D centre-to-centre distance between the two structures' `<Center X/Y>`.
  Verified: drop ÷ centre-distance = exactly `0.001` on all 83 pipes, spread
  `3.9e-16`.
- **Inverts are stored explicitly**, per pipe, as
  `<Elevation Downstream=… Upstream=…/>`. Nothing extrapolates them.
- **Structure `<Elevation Base>` must be written explicitly.** In the first
  sample only 4 of 166 structure-ends agreed with the pipe invert meeting there,
  and 82 of 84 structures sat at a default `-4` while the pipe chain carried
  real values. The STORM_CA trio corrects the reading: in a freshly authored
  file **all 8 structure-ends agree exactly** — `Base` is byte-identical to the
  pipe `<Elevation>` end that meets it. So Carlson *writes* the two in sync and
  does not *keep* them in sync through later edits. Either way we write both.
- **Pipe-to-pipe invert continuity at shared structures was exact** (0 of 82
  mismatches), so a drop structure is expressible as an intentional
  discontinuity there, plus `<Elevation JunctionDrop>` on the structure.
- **`Rise` is in INCHES** (sample reads `12` for 12″ pipe). The `÷ 12` the
  Hydraflow path needs simply does not apply.
- **Materials are decoupled from hydraulics.** `Material="RCP III"` is a free
  string; `ManningsValue` is its own attribute on the same element. Carlson is
  not looking n up from the name at read time.
- **Structures and inlets are named library entries with geometry inline** —
  `<SwrStruct ID="Box1">`, `<HydroInlet ID="Combo-Grade">`. Because the
  geometry rides beside the ID, the file is self-describing.

**ASSUMED — flip-one-line risk, confirm on first round trip:**

- Carlson's 17-significant-digit doubles (`846202.78000000003`) are a writer
  artifact, not a requirement. Clean 2-decimal numbers should parse identically.
- `Shape="0"` is circular. `SwrStruct Type="1"` is box. `HydroInlet Type="3"`
  is combination (inferred from the sample's `ID="Combo-Grade"`).

**UNKNOWN — blocks nothing, but decides the shape:**

- **`<Libraries/>` is empty in the sample.** Highest-value unknown in the whole
  format. If it can be populated, Bryant's standards ship *inside the file* and
  the export stops depending on the target machine's Carlson configuration. If
  Carlson only ever writes it empty, every ID and symbol name must match what is
  already installed, and name-matching becomes the main integration risk.
- `Symbol="INLET3"` is a **block name** and almost certainly must exist locally
  or the plan-view draw fails.
- `NetworkType="0"`, `Unit="0"`, `HydroMethod="0"`, `ComputationMethod="0"` —
  domains unknown.
- Whether the absent `<Bypass ID="0"/>` on the outfall structure alone is
  deliberate (every other structure has one) or incidental.

### The sample is contaminated as evidence

45 of its 83 pipes have structure boxes that **physically overlap** their
neighbours — the structures sit exactly on the source polyline's vertices with a
default 6×4 box. So "centre-to-centre" and "vertex-to-vertex" are the same
distance in that file, and the clean `0.001` result describes *the routine that
wrote it*, not Carlson's convention. **There were no real structures in it.**
Do not cite it as proof of a centre-based model.

### Second sample: the STORM_CA trio (2026-07-31)

`Carlson_References/` holds one stormline in three formats — `Storm_CA.cl`,
`STORM_CA_INV.pro` / `STORM_CA_TOP.pro`, and `STORM_CA.sew`. Jake built the
`.sew` through Carlson's own dialog off the `.cl` plus a surface, so it is a
**Carlson-authored file with a default in every hydraulic slot** — which is
exactly what makes it a good format witness.

**It carries none of the `.pro`'s design, and that is expected.** Every
hydraulic number in it is a Carlson default:

- All five `<Center X/Y>` match the five `.cl` vertices exactly. `.cl` field
  order is `0,station,L,NORTHING,EASTING`, terminated by `0,0,L,0,0`; the `.sew`
  reads `X=`easting `Y=`northing — the pair is swapped relative to the `.cl`
  *file text*. **This is not a swap the writer performs.** `pf:cl-parse` and
  `cl_location_at_sta` both already return drawing coordinates
  (x = easting, y = northing), so a node's `xy` goes straight into `X`/`Y`.
  Swapping it would put every structure on the wrong side of the state plane.
- The invert chain is synthetic. `Base` starts at `-4.000` on the upstream
  structure and rises downstream at exactly `0.001` ft/ft against
  centre-to-centre distance on all four pipes (197.28→0.19728, 31.23→0.03123,
  271.49→0.27149, 40.00→0.04000): Carlson's default 4 ft depth and 0.10 %
  default slope, seeded at a structure with no surface under it (`Rim="0"`).
- `Rise="12"`, `Material="PVC"`, `Width="4"` throughout.

Meanwhile the `_INV.pro` holds the real design — 743.00 / 743.50→744.00 /
747.2308 / 747.7308 / 749.00, at 1.888 %, 1.203 %, 1.715 % and 1.00003 %, with a
genuine 0.5 ft drop inside the second structure. **This file is not evidence
that Carlson reads anything PFTools writes.** It is a picture of the manual
keying the export exists to remove.

**What it settles:**

- **`Elevation` attributes are absolute elevations, not depths below rim.** The
  `0.001` arithmetic only closes in elevation space; the values merely *look*
  like depths because the seed structure took `Rim="0"`.
- **`Base` == the meeting pipe end**, exactly, at authoring time (§2 above).
- **`_TOP.pro` − `_INV.pro` gives pipe rise directly** — 2.00 ft at the outfall
  end, 1.50 ft on the rest, i.e. a 24″ pipe then three 18″. `<Pipe Rise>` is
  inches, so that is a ×12 and nothing else.
- **Structures can be bound to a `.cl` by station and offset.**
  `<ReferenceCLFile Name="$PROJECTPATH\…\Storm_CA.cl"/>` alongside
  `<ReferenceLocation Station Elevation Offset/>` — and `$PROJECTPATH` is a
  project-relative macro Carlson expands. Only the headwall carried the file
  reference here (the rest were placed by picking), but the mechanism exists and
  is worth understanding before we commit to writing raw coordinates only.
- **Four library tokens are known-good on the target install:**
  `SwrStruct ID="MH1"` (Type 2, `<Manhole>`), `SwrStruct ID="Outfall-Funnel"`
  (Type 0, `<Funnel>`), `HydroInlet ID="Combo-Grade"` (Type 3), and the plan
  symbol block `INLET3`. A starting vocabulary the first sample did not give us.

**What it does not settle:**

- The centre-to-centre `0.001` result is *again* not proof of a centre-based
  model — default 4 ft structures sit on the `.cl` vertices, so centre and
  vertex coincide here too. §3's experiment still stands.
- `<Bypass ID>` is inconsistent: CA-3→`CSMH1` and CA-4→`CSMH2` each name the
  next structure downstream, but CA-5 reads `"0"` and CA-1/CA-2 carry no
  `<Bypass>` at all. Either the dialog sets it only where asked, or it means
  something other than "next downstream". **Do not infer a rule from this.**

**The decomposition maps the way we need it to.** Our own rule — `pfr:groups`,
vertices ≤ `*pfi-struct-width-max*` (15 ft) apart are one structure, a terminal
singleton is a structure — yields **5 structures and 4 pipes** on
`STORM_CA_INV.pro`: the same count, order and connectivity as the `.sew`. The
headwall at Sta 112.48 and the upstream inlet at Sta 570.68 both come through.

The `.pro` stations do not land on the `.cl` vertices at the two ends (112.48 vs
100, 570.68 vs 640). **This does not matter.** Carlson put a structure on every
polyline vertex because that is how its dialog builds a network from a polyline;
PFTools locates structures from the drafted profile. The `.pro` is authoritative
for us, and the `.cl` supplies only the plan point at a given station.

**One caveat, on `Width`.** The `.pro` structure gaps here are 2.5417, 2.5417 and
2.0834 ft against the `.sew`'s default `Width="4"`. That gap is a *drafted
profile-view* width, not necessarily the structure's true plan dimension. Until
the drafting convention is confirmed (§9.9), `Width` comes from config per type,
not from the `.pro`.

## 3. The open question: what Carlson considers "the pipe"

The manual is the better evidence:

> "actual pipe dimension **that removes the width of the structure and goes from
> the structure edges**"

So the pipe physically runs edge to edge, and the native measure is
centre-to-centre with the real extent reached by *subtraction*. Both bases are
offered as **label** options, for length and for slope, plus a third knob
(`Label Slope With Rounded Pipe Length`). Slope and length are display values
with three settings — never stored data.

**Why both options exist:** centre-to-centre and actual-pipe slope are identical
when a pipe runs one straight grade through a structure. They diverge only when
the in- and out-inverts at a structure differ. Centre-to-centre then smears the
structure's internal drop into the pipe's apparent grade; "actual" isolates the
true pipe grade. That implies `<Elevation Downstream/Upstream>` are meant as the
**pipe's own two end elevations** — which is exactly what a `.pro` vertex pair
is.

### The experiment that closes it — 5 minutes, no PFTools

Build a two-structure network by hand in Carlson. Real 6 ft × 4 ft boxes, centres
66 ft apart. Type inverts `123.15` and `123.45`. Read the length and slope labels
under the "actual" setting:

| Carlson reports | meaning | what pf2sew writes |
|---|---|---|
| 60 ft, **0.500%** | typed inverts are **edge** inverts | `.pro` vertices verbatim |
| 60 ft, **0.550%** | typed inverts are **centre** inverts | project vertices out to centres |

**Feasibility is not in doubt either way.** The entire ambiguity is one
half-structure-width per pipe end: it moves a slope *label* a few percent and an
invert ~0.015 ft. It does not touch connectivity, size, material, n-value, rim,
or the structure of the capacity calculation.

## 4. Decision taken: write the `.pro` inverts verbatim

Traceability outranks display fidelity. If the sheet says 123.45 at a structure
and the `.SEW` says 123.435, nobody can distinguish that from a typo, and the
export stops being diffable against the drawing.

- Pipe `<Elevation Downstream/Upstream>` ← the `.pro` vertex inverts, unmodified.
- Structure `<Elevation Base>` ← the pipe end that meets it (written explicitly;
  see §2).
- `JunctionDrop` ← the in/out difference where a drop exists.
- Let Carlson derive length. **The slope-vs-sheet mismatch is a Carlson labeling
  setting, not our problem to compensate for** — set the mains to "actual pipe
  slope" and it reproduces the sheet.

Centre-projection was considered and rejected: it perturbs the authored datum to
make a derived label read nicer, and it has no defined slope to project along at
the outfall or at a drop.

**Still to confirm:** the centre-vs-actual toggle is documented in the manual's
*Lateral* Labels section. Verify the mains have the same option in `swrsetup`. If
mains are centre-only, the ~5% understated slope returns as a documented caveat
rather than a fixable setting.

## 5. Structure and material mapping

[`*pf-rule-table*`](../pftools-cfg/pftools-cfg.lsp#L101-L110) is already the type
system — 8 rows, keyed on block-name tokens, first match wins, and already
load-bearing for sheet labels. It maps onto Carlson's inlet types on the same
axis:

| PFTools rule | our label type | Carlson slot |
|---|---|---|
| `CBI`+`MH` | DRAINAGE MH w/ curb inlet casting | combination — `<Curb>` + `<Grate>` |
| `DBI`+`MH` | DRAINAGE MH w/ square grate casting | grate — `<Grate>` |
| `CBI` | CURB BOX INLET | curb throat — `<Curb>` |
| `DBI` | DROP BOX INLET | grate — `<Grate>` |
| `DMH`/`MH`/`SMH` | DRAINAGE MH / MANHOLE / SANITARY MH | junction only, no capture |
| `HDWL` | HDWL | outfall — `<OutfallTailwater>` |

**Payoff:** structure type in the model and structure label on the sheet come
from *one table*. Change the rule and both move — the same property
`pf:combine-id` gives structure IDs.

### The block library ↔ Carlson library (decided 2026-07-31)

**Decision: one table maps a PFTools block-name token to a Carlson library
entry, and the two libraries are built to match — in whichever direction is
cheaper per field.** Carlson's structure and inlet libraries are editable, so
this is a naming exercise, not a modelling one.

The two directions resolve differently:

- **IDs — bend Carlson to us.** `SwrStruct ID` and `HydroInlet ID` are free
  strings naming library entries. Author entries in Carlson named after our rule
  tokens and the mapping is identity, with no lookup to drift. This is the
  cheaper half and it keeps Bryant's standards in one place.
- **`Symbol` — point Carlson at Bryant's existing blocks.** `Symbol="INLET3"` is
  a plan-view block that must resolve in the drawing Carlson draws into. If the
  field accepts an arbitrary block name, aim it at the blocks Bryant already
  inserts and **no new blocks are needed at all**. Confirm that first (§9.8); if
  Carlson only accepts entries from its own symbol library, we author matching
  blocks under Carlson's names instead.

**Where the table lives: a new `*pfh-type-map*` in `pftools-cfg`, keyed on the
same token lists as `*pf-rule-table*` — not new columns on `*pf-rule-table*`
itself.** That table is load-bearing for every sheet label PFLABEL draws;
widening it to carry export data puts hydrology concerns inside the drafting
path. A parallel table keyed on the same first-match token list gives the same
"change the rule and both move" property with none of the blast radius.

Each row supplies: `SwrStruct ID` + `Type` + geometry element (`<Manhole>` /
`<Box>` / `<Funnel>`), `HydroInlet ID` + `Type` (or none, for a junction-only
manhole), the `Symbol` block name, and the firm-standard height / `Thick`
constants named as missing below.

### Gaps on our side

- **`*pf-materials*` are placeholders.** The config says so outright. Bare
  `RCP`/`HDPE`/`PVC`/`DI`/`COPPER`; `*pfr-nvalues*` adds `CMP`, which
  `*pf-materials*` cannot even produce. Needs Bryant's real list regardless of
  Carlson.
- **No material class.** Carlson says `RCP III`; we say `RCP`. Either the class
  goes on the sheet (`12" RCP III` — a **drafting-visible** change, since labels
  print `NN" <MATERIAL>`) or the sheet stays coarse and we map to a class at
  export. **Jake's call.**
- **No structure `Height` / `Thick`.** Width comes from real data (the measured
  vertex-pair gap); height and wall thickness would be firm-standard constants
  per type. New config, not new drafting.

## 6. Drainage area — the open piece

- Area off a closed LWPOLYLINE is trivial and exact.
- **Binding each catchment to a structure is the real work.** pfanchor already
  has the machinery for this shape of problem: `pfa:gather-inlets` finds the
  inlet INSERTs, `pfa:lines-at` is the read seam. Seeding outward from the inlet
  is likely cheaper than testing every boundary.
- Carlson wants a cluster, not one number:
  `<DrainageData Area CatchmentFlow Tc ActualTc Cf ScsCN ScsSwampFactor/>` plus
  `<Pavement LonSlope CrossSlope ManningsN/>`. **Which fields matter depends on
  `HydroMethod`** — Rational needs C and Tc, SCS needs a curve number. That fork
  decides what a drafter has to author, so settle it early.
- Provenance: since the tool now asserts hydrology, "where did this 0.42 ac come
  from?" needs an answer designed in, not bolted on.

## 7. The architectural cost — smaller than first estimated

The line data this tool needs (profile decomposition into
structure/pipe/structure, the node graph, the rim reads) lives *inside*
`pfreport` as `pfr:groups`, `pfr:node-of`, `pfr:build-nodes`, `pfr:rim-at`,
`pfr:struct-id`. A second consumer means hoisting those into shared engine code —
the extraction ticketed in §8 step 1 below.

**This section originally called that "larger than the emitter." It is not.**
`pfr:line-pipes` already builds a `nodes` list — **one `pfr:node-of` record per
structure group**, carrying station, `.cl` plan xy, rim and structure ID — and
only then walks adjacent pairs into pipes. That node record is a
`<SewerStructure>` in all but serialization; the link-based flattening the
`.stm` needs is confined to `pfr:record`. The gather is already node-shaped,
which is the shape `.SEW` wants. Hoisting it is a move, not a rewrite.

## 8. The build

**Module** — `pfsuite/pf2sew/pf2sew.lsp` + its own `README.md`, prefix
**`pfsew:`**. **Load position 12 of 13**, between `pfreport` and `pfpalette` in
`pftools-load.lsp`.

**Command** — `C:PF2SEW`, run as `(pf:run-command "PF2SEW" nil 'pfsew:cmd)`.
Read-only on the drawing exactly like PFREPORT: no undo group, no pass ledger,
no STATUS write, no Esc flush hook. The `.sew` on disk is the only write.
SYSTEM-scoped multi-select over the registry, dialog `pfsew_run` modelled on
`pfrpt_run`.

### Step 1 — the gather — DEFERRED, and why

**Written as: hoist `pfr:groups`, `pfr:node-of`, `pfr:build-nodes`, `pfr:ds-idx`,
`pfr:order`, `pfr:rim-at`, `pfr:struct-id` into `pf:` engine code first.**

**Built as: PF2SEW calls them where they are.** Load order permits it — pfreport
is above pf2sew — and the model they build is already the shape `.SEW` wants.

The reason is sequencing, not taste. **Neither PFREPORT nor PF2SEW has run in
CAD.** Refactoring the shared gather before either is verified means a CAD
failure could be the export, the gather, or the move, and there is no way to tell
which. Hoisting after both pass is strictly cheaper to debug and changes nothing
about the end state.

**This section is the ticket.** `REFACTOR-PLAN.md` was deleted in the
restructure and its contents were never relocated, so there is no separate
document to consult — the scope is the seven `pfr:` functions named above, and
the precondition is a passing CAD gate on both `PFREPORT` and `PF2SEW`.

The one change made to `pfreport` is **additive and inert on the `.stm` path**:
`pfr:node-of` now carries `'blk`, the structure's block name — which
`pfr:struct-at` was already returning and throwing away — and the node table grew
a sixth element for it with a `pfr:nd-blk` accessor. `pfr:record` reads neither.
PF2SEW needs it to key `*pfsew-type-map*`; re-resolving the block independently
would have put the same fact in two places.

### Step 2 — `*pfsew-type-map*` + `*pfsew-opts*` in `pftools-cfg` — BUILT

The table from §5, plus the tunables table. Config only, no logic.

**Every row resolves to one of the four confirmed-present library entries**
(`MH1`, `Outfall-Funnel`, `Combo-Grade`, `INLET3`) rather than to invented
Carlson-style names: a file that opens beats a file naming a library entry
Carlson does not have. The rows are correct in *shape* and provisional in
*content* until the library enumeration (§9.4) lands. The block library is built
to match in that same pass.

`*pfsew-opts*` is a flat `(KEY VALUE LABEL)` table read at emit time through
`pfsew:opt` — **not thirty named globals**, because the planned home for these is
a settings page or a `pfpalette` tab, and a data-driven table is one `foreach`
away from a tile per row. `pfsew:set-opt` is the write seam that page will use.
Reading at emit time means a changed value takes effect on the next export with
no reload.

### Step 3 — the writer — BUILT

Four concatenated fragments, plain text, **no XML library and no wrapping root
element**. Consumes the hoisted node/pipe model:

| element | source |
|---|---|
| `<Center X/Y>` | node `xy` off the `.cl`, written as-is — already easting-first |
| `<Elevation Base>` | the pipe end meeting that node, written explicitly |
| `<Elevation Rim>` | node rim; an unfilled placeholder exports 0 **with a named warning**, never a fabricated number — PFREPORT's rule, kept |
| `JunctionDrop` | the in/out difference where a node's two inverts differ |
| pipe `<Elevation Downstream/Upstream>` | the `.pro` vertices, verbatim (§4) |
| `<Pipe Rise>` | (`_TOP` − `_INV`) × 12, inches |
| `Material`, `ManningsValue` | the record's material; n from `*pfr-nvalues*` |
| `SwrStruct` / `HydroInlet` / `Symbol` / `Width` | `*pfh-type-map*` |
| `Down/UpstreamStructureID` | the graph builder, unchanged |
| `<Graph>` | one `<LINE>` per pipe, from the two centres |
| `<DrainageData>`, `<Pavement>`, grate + curb coefficients | **Carlson defaults** — STORM_CA proves the model opens and computes with them |

Hydrology stays at defaults here, deliberately: a `.sew` that opens, draws and
computes capacity off real inverts is the whole first-release value, and a
fabricated drainage area is the one thing PFREPORT refuses to write.

### Step 4 — the round trip (Jake, in CAD)

The first honest test. It also answers three §9 unknowns for free:

1. Export STORM_CA. It opens in Carlson without complaint.
2. Inverts, rises, materials and rims match the sheet.
3. The 1.00003 % pipe reads 1.00 % under "actual pipe slope" (§3, §4).
4. The 0.5 ft drop at structure 2 survives — confirms the `Base` /
   `JunctionDrop` convention (§9.7).
5. Capacity computes.

### Step 5 — hydrology

Only after step 4 passes. Rational vs SCS (§9.6) decides what a drafter has to
author; catchment→structure binding is the real work, and pfanchor's
`pfa:gather-inlets` / `pfa:lines-at` are the seam. Provenance designed in, not
bolted on.

### Step 6 — iteration ergonomics

Re-export after drafting changes, and the still-open question of whether results
ever need to come *back* from Carlson.

## 9. Only Jake can get these

1. **The pipe-definition experiment** (§3). Decides one line of arithmetic; now
   folded into the step 4 round trip rather than blocking it.
2. **Whether `<Libraries/>` can be populated**, or Carlson only ever writes it
   empty. Decides whether the export is self-contained or name-matched.
3. **The `swrsetup` prompt/dialog sequence** for writing a `.SEW` — specifically
   whether it ever asks for length or slope, or only inverts. *Partly answered:*
   the STORM_CA dialog run asked for neither, and defaulted both.
4. **Library enumeration** — material strings, structure IDs, inlet IDs, the
   `Type` enum domains, available symbol block names. *Partly answered:* `MH1`,
   `Outfall-Funnel`, `Combo-Grade` and `INLET3` are confirmed present.
5. **Whether mains have the centre-to-centre / actual toggle** (§4).
6. **Rational vs SCS** (§6).
7. **The `Base` / `JunctionDrop` convention at a drop** — one structure has one
   `Base` slot but two inverts. Presumed `Base` = outgoing (downstream) invert
   with the difference in `JunctionDrop`, but the sign is a guess. Type a drop
   into a two-structure network and read back what Carlson writes.
8. **Whether `Symbol` accepts an arbitrary block name**, or only entries from
   Carlson's own symbol library (§5). Decides whether the block library is new
   work or a naming pass.
9. **Whether drafted `.pro` structure gaps are true plan widths.** STORM_CA's
   are 2.08–2.54 ft, which is narrow for a real inlet. If they are schematic,
   `Width` must come from config per type and never from the `.pro`.

## 10. Cautions

- **Carlson has its own plan-view annotation engine.** `Draw Sewer Network–Plan
  View` labels the network, and labels auto-redraw when network data changes,
  snapping back to original positions unless moved with `Move Sewer Label`.
  That is plan view, so it should not collide with PFLABEL's profile work — but
  handing Bryant a `.SEW` hands them a second labeling engine.
- **`ha2csnet` (Import Haestad Network) is a precedent worth reading.** Carlson
  already imports a foreign ASCII sewer format; the manual notes Haestad files
  carry 14 fields and *no coordinates*, so Carlson fabricates a pseudo-layout.
  We would supply real survey coordinates off the `.cl`. Before hand-writing
  `.SEW`, check the Network → Sewer Network Utilities menu for other importers —
  **writing 14 fields against a documented spec may beat matching an
  undocumented XML dialect**, if the field set is sufficient.
- Nothing in this document has been run in CAD.
