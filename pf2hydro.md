# pf2hydro — PFTools line data → Carlson Hydrology `.SEW`

**Status: design outline, nothing built.** Drafted 2026-07-29 from one real
sample (`TEST_StormProfiles.sew`, Carlson Software 2025, 84 structures / 83
pipes) plus the Hydrology Module chapter of the Carlson 2026 manual.

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

- Own module, own folder, own README. Proposed prefix **`pfh:`** — verify it is
  free with `pf.sh find` before committing to it.
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
- **Structure `<Elevation Base>` is NOT kept in sync with the pipes.** Only 4 of
  166 structure-ends agreed with the pipe invert meeting there; 82 of 84
  structures sat at a default `-4` while the pipe chain carried real values.
  **We must write `Base` explicitly** rather than trusting Carlson to follow.
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

| Carlson reports | meaning | what pf2hydro writes |
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

## 7. The real architectural cost

Not the writer — the **gather**. The line data this tool needs (profile
decomposition into structure/pipe/structure, the node graph, the rim reads)
currently lives *inside* `pfreport` as `pfr:groups`, `pfr:build-nodes`,
`pfr:rim-at`, `pfr:struct-id`. A second consumer means hoisting those into shared
engine code — the extraction already ticketed in
[REFACTOR-PLAN.md](REFACTOR-PLAN.md). **Scope that before writing any `.SEW`
code; it is larger than the emitter.**

## 8. Rough phasing

1. **Settle the unknowns Jake owns** (§9). None require code.
2. **Extract the gather** out of `pfreport` into shared engine functions, with
   PFREPORT still passing its own gates afterward.
3. **Writer skeleton** — the four fragments, structures and pipes with real
   inverts/rims/sizes/materials, hydrology at Carlson's defaults. Opens in
   Carlson, computes capacity, drainage blank.
4. **Type mapping** from `*pf-rule-table*` to inlet/structure types + symbols.
5. **Drainage area** authoring and catchment→structure binding.
6. **Iteration ergonomics** — re-export, and the open question of reading results
   back.

## 9. Only Jake can get these

1. **The pipe-definition experiment** (§3). Highest priority; decides one line of
   arithmetic.
2. **Whether `<Libraries/>` can be populated**, or Carlson only ever writes it
   empty. Decides whether the export is self-contained or name-matched.
3. **The `swrsetup` prompt/dialog sequence** for writing a `.SEW` — specifically
   whether it ever asks for length or slope, or only inverts.
4. **Library enumeration** — material strings, structure IDs (is `Box1` stock?),
   inlet IDs, the `Type` enum domains, available symbol block names.
5. **Whether mains have the centre-to-centre / actual toggle** (§4).
6. **Rational vs SCS** (§6).

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
