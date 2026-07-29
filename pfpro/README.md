# pfpro.lsp — C:PFPROINV / C:PFPROTOP, .pro from a profile polyline

**Load position:** 7 of 12 (after pfsetup, before pflabel).
**May depend on:** pftools-cfg, pftools-lib, pfanchor, pfsettings.
**Depended on by:** nothing. Nothing in the suite calls into this module.

## What it owns

Cutting a Carlson `.pro` from a polyline a drafter drew in a profile grid, and
binding the result to that grid's anchor. One command per role — `PFPROINV`
writes the `_INV.pro`, `PFPROTOP` the `_TOP.pro` — both thin wrappers on
`pfpro:run`, whose only argument is the role.

**One pick, no dialog.** The native Carlson command asks for H/V scale, start
station, start elevation, a datum pick and then the polyline. Every one of
those numbers is already on the anchor (`STA0`, `DATUM`, `HPLOT`, `VPLOT`, and
the insert point *is* the datum at the lower-left), so this command asks for the
polyline and nothing else. `pf:profile-x->station` and `pf:y->elev` are the
exact inverses of the transform PFLABEL draws with, which is the whole point: a
`.pro` cut here **cannot** disagree with the grid its labels are drawn against.
No Carlson command is driven, no dialog is scripted — the file is composed and
written directly.

**Which grid** resolves from the pick itself (`pfpro:owner`): the anchor nearest
the polyline's **leftmost endpoint**. No bounding box, no containment test, and
`pfa:extents` is never consulted — so a legacy anchor with no `WIDTH` recorded
resolves like any other, and there is never a second prompt. Zero candidates is
a refusal, never a guess.

**Naming comes from the `.cl` basename**, with the **TYPE segment upcased**:
`Storm_BA.cl` → `STORM_BA_INV.pro`. `*pf-types*` are `STORM` / `SANITARY` /
`WATER` and a `.pro` carries the type that way even when the alignment on disk
is spelled mixed-case. The NAME segment is taken verbatim, so a line keeps
whatever the alignment file already calls it.

Building from the `.cl` rather than inventing a name is what makes the role
suffix match `*pf-pro-roles*` by construction — which is what
`pf:parse-pro-name` and PFSETUP's AUTO binding depend on. An anchor with no
`.cl` bound is refused, because there is nothing to name the output from.

Casing is cosmetic to every consumer, in both directions: `pfs:pro-lookup`
compares `strcase`-to-`strcase`, so AUTO/Refresh pair the file whatever the
spelling, and `pf:parse-pro-name` upcases before it splits off the role.

**The firm-standard folder always wins** (settled 2026-07-29). `pfpro:dest-dir`
is `pfset:get-company-dir "pro"` and nothing else — it deliberately does *not*
follow an already-bound sibling `.pro`, because a sibling bound once from a
non-standard location would quietly pull every later cut out of the project
template. `getfiled` (pre-filled) is the last resort when there is no project
root and no session directory.

## The `.pro` format

Verified byte-for-byte against a Carlson-written file (2026-07-29), not
inferred:

```
115.5906,749.2500,0.0     sta , elev , vertical-curve length
...                       4 decimals on both; col 3 is 0.0 for a pipe run
0,0,0                     terminator -- BARE zeros, not 0.0000
1                         trailer, then EOF
```

No header row. This is the same grammar `pf:pro-verts` reads, so anything
written here round-trips through the suite's own reader. `rtos` mode 2 is passed
explicitly so an Architectural/Fractional drawing cannot corrupt the output —
the same reason PFSETUP pins `distof` mode 2.

**Stations written are ABSOLUTE `.cl` stations**, not offsets from the grid's
start. A grid starting at station 100 carries a pipe whose first vertex is
115.5906; the 100 is the X-origin of the screen mapping (`pf:xf-sta0`), not a
base to subtract.

## Public API

- `C:PFPROINV` / `C:PFPROTOP` — run under `pf:run-command` (flush nil), bodies
  `pfpro:cmd-inv` / `pfpro:cmd-top`.

Everything else (`pfpro:verts`, `pfpro:owner`, `pfpro:map-verts`,
`pfpro:orient`, `pfpro:check-range`, `pfpro:filename`, `pfpro:dest-dir`,
`pfpro:write`, `pfpro:bind`, `pfpro:run`) is internal to this command's flow.
No other module calls in, and nothing here is palette-safe: the flow is `entsel`
first, so it can only ever run from a command context.

## Invariants

- **Every vertex written is an invert.** PFINVERT brackets structures on
  adjacent pairs (`*pfi-struct-width-max*`), so a curve of any kind — bulge,
  curve-fit, spline-fit — is REFUSED rather than densified. Densifying would
  fabricate structures that PFINVERT and PFREPORT then find and label. Closed
  polylines, meshes, and any polyline with a non-`+Z` extrusion are refused for
  the same "it is not a profile" reason.
- **Order is never sorted into place.** A polyline drawn right-to-left is
  normal and is reversed whole; one that genuinely backtracks is a drafting
  fault and is refused by name. Sorting would launder the fault into a
  plausible `.pro`. Two vertices at one station (a vertical segment) get their
  own message — a structure drop is the short run between a vertex PAIR, which
  is what the reference file shows.
- **Nearest-anchor resolution carries two guards**, neither of which costs a
  prompt:
  - **The insert must be at or below-left of the left endpoint.** The insert
    *is* the grid's lower-left `(leftx, basey)`, and a profile always draws up
    and to the right of it. Without this, stacked grids — the normal sheet
    layout — steal each other's polylines: a pipe drawn high in its own grid is
    nearer to the insert of the grid ABOVE it than to its own. Deleting the two
    `<=` tests gives pure nearest-insert.
  - **COPIES are excluded** (`pfa:copy-p`), because `pfa:all-anchors` does not
    filter them — only `pfa:find-anchor` does. A copy sits elsewhere in the
    drawing and would win outright for a polyline drawn inside it, and
    `pfa:files-put` would bind into a cloned ledger nothing else resolves. A
    polyline whose nearest grid is a copy gets its own refusal naming PFREMOVE.
- **`pfpro:check-range` guards a wrong `STA0`.** Mapped stations disjoint from
  `pf:cl-range` = refusal; partially outside = warning, written anyway. This is
  stricter than the label engines on purpose: a wrong `STA0` only misplaces
  labels, which are redrawable, but here it bakes wrong stations onto disk that
  PFINVERT and PFREPORT read back as truth.
- **The file write is not the drawing write.** The undo group opens only around
  `pfpro:bind`, after the file is already on disk. One U reverses the binding,
  never the file — and the completion message says so.
- **The undo flag is borrowed, not new.** `pfpro:run` uses `*pfs-undo-open*`.
  `pf:group-open-p` checks a FIXED list of flags, so a sixth flag of our own
  would be invisible to `pf:run-error` and an Esc would leak an open group.
  PFPRO and PFSETUP cannot run at once. Same call, same reason, as PFINDEX.
- **No cache to clear after a rewrite.** `pf:checksum-file` re-keys on
  systime+size and `*pf-proverts-cache*` re-keys on the checksum, so both
  self-invalidate when an already-bound path is overwritten.
- `pfpro:bind` fills ONE slot of the FILES record and preserves the other four
  (the sibling `.pro`, the TIN pair, the material) — same shape as PFSETUP's
  late `.pro` binding.

## Open issues local to this file

- **Untested in CAD as of 2026-07-29.** Written against a single reference
  `.pro` and the reader's grammar; no round trip through Carlson has been run.
  The specific things a CAD session must settle: does Carlson's profile reader
  accept our file (load it in the native profile editor), does the `0,0,0` /
  `1` trailer pair matter, and does a `.pro` we wrote read back through
  `pf:pro-verts` with vertices matching the polyline that made it.
- **Heavy `POLYLINE` support is untested.** `pfpro:verts` walks `VERTEX`
  entities for old-style polylines, but every profile drawn in this office is
  an `LWPOLYLINE`. The branch exists so a legacy drawing does not hard-refuse;
  it has never been exercised.
- **No TOP-from-INV derivation.** `PFPROTOP` needs its own drawn polyline; it
  cannot offset an existing `_INV.pro` by a pipe OD. That is the obvious next
  feature and is deliberately not built — the pipe size lives on the anchor
  (`*pf-materials*` / the FILES material slot) but per-run size changes do not,
  so an offset would be wrong at every size transition.
