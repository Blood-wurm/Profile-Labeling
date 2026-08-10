# pfanchor.lsp — record + registry

**Load position:** 4 of 12 (after pfdraw, before pfsettings).
**May depend on:** pftools-cfg, pftools-lib, pfdraw. *Runtime-only
exceptions:* `pfa:choose-anchor` uses `pfset:pick-index`, and PFREMOVE and
PFADOPT use `pfset:confirm` (pfsettings, loads later) — resolved at call time.
**Depended on by:** pfsettings, pfsetup, pflabel, pfxlabel, pfinvert,
pfpalette (+ pftools-lib's `pf:cl-geom` reads the GEOM store back through
`pfa:geom-get`/`put`).

## What it owns

The V4 model: the anchor IS the grid record; crossings are one field among
many. PFSETUP creates the record; every other command reads/updates it.
Also home to the shared command wrapper (`pf:run-command`, audit #9),
C:PFREMOVE (teardown), C:PFINDEX + the membership index (§4b), and C:PFADOPT
(§9, adopting anchors pasted in from another drawing).

- **STUB** — AUTO registration writes identity-only stubs to the DRAWING
  dictionary (NOD "PFTOOLS", keys `STUB_<TYPE>_<NAME>`): profile exists,
  maps to its .cl (+ auto-resolved .pro pair), NO placement. USER
  registration promotes stub → anchor and deletes the stub. Identity alone
  is enough to DISCOVER; placement is required only to DRAW.
- **ANCHOR** — one PF-ANCHOR block per ANCHORED profile, keyed LINE+UTIL.
  Insertion point = grid lower-left (datum + lower-left = transform
  origin). EXTENTS ARE RELATIVE: the WIDTH / HEIGHT attributes hold offsets
  from the insertion point to the top-right pick — never an absolute corner
  (a window-move carries both). The stored top means "top at max station"
  ONLY; per-station top-Y comes from the top-of-grid probe (`pf:top-at`),
  because grid tops STEP.
  Attributes = LINE / UTIL / STA0 / DATUM / HPLOT / VPLOT / WIDTH / HEIGHT,
  all INVISIBLE (`*pfa-att-flags*` = 1). This was `(70 . 8)` — PRESET, a
  different bit — for a long time, which left all eight rendering under the
  datum. `pfa:reanchor` heals the flag on anchors written before the fix.
  ATTDISP ON still forces them visible; that is the debug escape.
- **ANCHOR BLOCK** — hand-authored, a small fixed ICON snapped to the datum,
  drawn at the size it should read on an H:50 sheet
  (`*pfa-icon-ref-hplot*`). The insert scale is `hplot/50` applied
  **uniformly** (X=Y=Z, `pfa:icon-scale`), which holds a constant plotted
  size and keeps the icon undistorted. `pfa:ensure-anchor-block` tops up any
  missing ATTDEFs on the authored definition (`pfa:sync-attdefs`, additive
  and invisible only) and entmakes a small placeholder icon under the same
  name only in a drawing with no PF-ANCHOR definition. Every anchor is sent
  to the BACK of the draw order on write and on re-anchor
  (`pfa:send-to-back`) — it is a backdrop marker and must never cover grid,
  profile, or labels.
- **PRE-ICON ANCHORS** — before the icon swap the block SPANNED the grid and
  the extents were the insert's X/Y scale factors. Those anchors are
  inserted as `PF-GRIDANCHOR`, which is why `*pfa-block-names*` (the ssget
  filter) lists both names — otherwise they would go invisible to every
  lookup. `pfa:extents` is the single reader: WIDTH/HEIGHT when present,
  else the legacy scale factors behind the `xs > 2.0` sentinel. The
  ABSENCE of a WIDTH attribute is the discriminator, since scale alone
  cannot tell the two apart (at H:200 a current anchor's X-scale is 4.0).
  `pfa:reanchor` writes back to whichever storage the anchor already uses —
  stamping the icon scale onto a pre-icon anchor would shrink its recorded
  grid to a few feet.
- **LEDGER** — extension dictionary **"PFLEDGER"**, hard-owned by whichever
  entity carries it. `pfa:ledger-dict` is owner-agnostic and always was —
  nothing in it ever looked at the anchor.
  - *on an ANCHOR*, schema 3 xrecords: `META` (.cl path + checksum +
    self-handle for copy detection), `FILES` (.pro/.tin bindings +
    checksums + material), `STATUS_<PASS>`, `SCOPE`, `PASS_*` (the
    erase-by-handle ledger; CLAYER passes record timestamp + layer but NO
    handles), `X_*` (content-keyed crossing records).
  - *on a STRUCTURE block*, one xrecord: `MEMB` (§4b).

  **Renamed from `PFXLEDGER` 2026-07-27.** The old name was the fossil of
  the one tool that happened to need a record first: four of the six key
  families on an anchor have nothing to do with crossings, and structures
  are now a second owner. `*pfa-dict-legacy*` is still READ, and
  `pfa:ledger-dict` **renames the entry on the first write**, so the
  fallback drains instead of being carried forever. A read must never
  rename — the palette reads with `create` nil and may never touch the
  database, so the rename is gated on `create`.
- **MEMB (§4b)** — the membership index: `(10 x y)` insertion point as
  indexed, `(302)` roster stamp, then `(300 name)(40 station)` pairs in
  `pf:lines-at-point` order. See §4b's header for why the stamp covers the
  whole roster rather than one line at a time (short version: a record lists
  HITS, so nothing in it can say which lines were tested and missed).
  `STATUS_<PASS>` — one verdict per tool, split from the single shared
  `STATUS` on the same date. Three commands used to write one record about
  three different files, so whichever ran last erased the others.
- **NOD "PFTOOLS"** — drawing-wide store: STUB_*, GEOM_* (cached .cl
  geometry, content-addressed by `pf:cl-id`), TWIN_* (drawn-centerline
  handle per .cl). GEOM carries a `KIND` (`(70)`): **EXACT** = parsed `.cl`
  vertices, `(10 x y sta)` z-slot holding the authoritative per-vertex
  station; **SAMPLED** = Road-API station walk, z-slot 0.0. Both have
  writers as of 2026-07-27 and a drawing can hold both kinds at once —
  `pfa:geom-get` returns the stationed verts as its 5th element, which is
  the only way to read stations back (`pf:cl-geom` hands callers 2D points).
- **DERIVED** — labeled/outstanding is NEVER stored; re-read from the
  drawing on every touch (SECTION 5 recon).

## Public API

Pure reads unless marked; **writers require a caller-held undo group**.
Reads are modeless-safe (the palette contract): `pfa:nod-dict` /
`pfa:ledger-dict` with `create` nil NEVER write. **Verified in CAD
2026-07-27** — `PFPDBMOD` delta across a full palette session, clean drawing
29→29 and populated 21→21 (PALETTE-TESTING §3).

**Registry + resolution:**
- `pfa:registry` → sorted `(type name state ename stub)` rows — THE
  registry: anchors + stubs, copy-excluding, one merged sorted walk.
  **An EMPTY registry is legal and must stay silent.** `acad_strlsort`
  rejects nil with a `Usage:` banner, so the sort is guarded on `out`
  ([`pfanchor.lsp:593`](pfanchor.lsp#L593), fixed 2026-07-27). Before that,
  every palette open on a drawing with no PFTOOLS data printed a spurious
  command-line error — the function had never been run against zero rows,
  because the palette was only ever opened on populated drawings. Non-empty
  behaviour is unchanged.
- `pfa:entry-cl r` → .cl path | nil — THE registry-row → .cl resolution
  (moved from pfxlabel 2026-07-26; consumers: pfxl:discover,
  pflabel:registry-pairs).
- `pfa:src-files type name` → `(inv-pro top-pro material)` | nil — anchor
  first (it carries material), then stub. Pure read; `""` reads as nil through
  `pfa:nz`. **Was pfxl:src-files, moved here 2026-08-06** for the reason
  `pfa:entry-cl` was: `pfa:xing-scan` needs a source line's `_INV.pro` to tell a
  crossing from a bare alignment intersection, and position 4 cannot call up to
  position 9. Consumers: pfxlabel, pfinvert, pfqty, pfreport. No alias left
  behind.
- `pfa:find-anchor line util` / `pfa:all-anchors` — DB scans (copies never
  resolve in find-anchor).
- `pfa:anchor->xform anchor` → xform alist | nil (record keys merged in).
- `pfa:read-attribs` / `pfa:att` / `pfa:anchor-title`.

**Record writes (PFSETUP's side):** `pfa:write-anchor` **W**,
`pfa:reanchor` **W**, `pfa:meta-put` **W**, `pfa:files-put` **W**,
`pfa:status-put` **W**, `pfa:status-reset` **W**, `pfa:scope-put` **W**,
`pfa:stub-put` **W**, `pfa:stub-del` **W**, `pfa:twin-put` **W**,
`pfa:geom-put` **W**.

**The gather (§4c — moved down from pflabel 2026-07-29).** All pure reads,
all modeless-safe. Completes the migration begun 2026-07-27 with
`pfa:build-lines` / `pfa:gather-inlets`: every one of these was
membership-and-ledger knowledge sitting in the labeling module by history, and
none of them called anything in pflabel. The forcing reason is the palette —
pfpalette at position 11 needs per-target counts, and this file at 4 could not
serve them while the gather lived at 7. Now the three label commands, pfreport
and the palette all resolve membership through one path.

- `pfa:registry-pairs primary-cl` → `(path . name)*` — THE registry builder:
  thin filter over `pfa:registry`, resolved via `pfa:entry-cl`, self dropped
  by `pf:cl-id`, same-type only.
- `pfa:line-table anchor` → `(primary lines)` | nil — THE target → line-set
  resolution, one home. Four call sites used to build this by hand.
- `pfa:index-stations inlets lines` → `(name . sorted-stations)*` — the
  RANKING input, moved down from pflabel 2026-08-03. **The primary-line paths
  do not call it**; `pfa:pending` folds the same index out of the walk it was
  already making. This standalone version is for callers with a line table but
  no single primary (pfreport, pf2sew).
- `pfa:id-for-hits hits index` → `"AA-1/BB-2"` | `""` — **THE DRAWN NAME**,
  the combined ID that goes on the sheet. One copy of a composition that had
  been hand-rolled three times; `pflabel:process-structure`,
  `pflabel:rd-fill`, `pfa:target-items` and `pfr:struct-id` all call it, so
  the palette, the run dialog list, the `.stm` export and the text actually
  drawn cannot drift apart.
- `pfa:pending inlets lines primary` → `((sta ename blkname hits)* index)` —
  **two products, one walk**, since 2026-08-03. Each row carries its own hits
  at position 3 so the name can be derived later with no second `lines-at`;
  nothing else reads position 3 of a pending row (`pfi:merge-nodes` rebuilds
  the list and puts the mates there).
- `pfa:gather-for primary lines inlets` → `(pend index)`, memoised — **the
  expensive half**, and the only thing `*pfa-gather-memo*` holds. Keyed on
  exactly what `pending` reads: primary, inlet signature, line signature.
  **Not** keyed on anchor or pass name; `pending` consults neither. Split out
  so ONE `inlets × lines` walk serves MANY passes, which is what the Commands
  tab needs showing Structure and Invert counts side by side.
  - `pfa:pend-for` and `pfa:index-for` are the two halves of that one entry,
    so a caller holding `pend` pays nothing for the index. The index does not
    depend on `primary`; the key does only because `pend` does.
  - **The memo is cleared on load, not `boundp`-guarded** — the stored value
    shape changed on 2026-08-03 (`pend` → `(pend index)`), and an entry left
    by the previous load would be read with the wrong accessor.
- `pfa:status-for anchor passname pend xform` → `(status orphans)` — **the
  cheap half**: a handle walk plus arithmetic. Deliberately not memoised —
  status describes what is DRAWN RIGHT NOW. Because the pass ordinates left
  the memo key, **drawing a label no longer discards the expensive walk** it
  never invalidated.
- `pfa:gather-compute anchor passname primary lines inlets` →
  `(pend status orphans)` | nil — **THE one gather-compute**, shared by PFLABEL
  and PFINVERT, now composed from the two above. Signature and return shape
  unchanged across the move, so `rd-compute` / `pfi:rd-compute` needed no edit
  beyond the rename.
- `pfa:target-counts anchor` → alist | nil — **the per-target roll-up the
  palette's Commands tab reads.** Keys: `primary lines structures label-done
  label-out invert-done invert-out crossings xing-done xing-out drift`. Worked
  out on read and never stored, for the same reason `pfa:status-roll` is.
  Crossings are ledger-only by construction (`pfxl:discover` is a writer), so
  `crossings` means "on record", and 0 means "none discovered yet" rather than
  "none exist". **Through `pfa:xing-shared-split`, not the raw ledger** — the
  count and the `lvwCommand` list are read side by side and `pfa:xing-find`
  re-tests its rows, so a raw count here would say 2 beside a list of 1. Its
  `inlets` are handed to the split, so this costs no second `ssget`.
- `pfa:line-systems rows` → `((row ...) ...)` — **the registry rows grouped into
  hydraulic systems**, so PF2SEW lists systems instead of making the user pair
  profiles by hand. Two lines join when a structure sits on both — the same
  multi-line hit `pfa:id-for-hits` turns into "AA-1/BB-2" — union-found over one
  `pfa:gather-inlets` walk against one `pfa:build-lines` table. Decided on
  MEMBERSHIP (`pfa:lines-at`, the corridor), never node coincidence:
  `*pfr-node-tol*` is 2.0 ft and far too loose to say two lines meet. **One
  utility type per system** — a casting shared by storm and sanitary joins
  neither and appears in both, which is right, they are two models. A line
  sharing nothing is a system of one and is still returned, so every row in
  comes back out. Pure read, palette-safe. Helpers: `pfa:sets-meet-p`,
  `pfa:merge-into` (groups stay pairwise disjoint, which is what makes the
  single merge pass sufficient).
- `pfa:xing-scan anchor write-p` → `(found newscope skips)` | nil — **the
  crossing DISCOVERY scan, split out of `pfxl:discover` 2026-07-30.** `found` is
  `((entry status existing-key) …)`; `newscope` feeds `pfa:scope-put`; `skips`
  is `((sbase tsta ssta why) …)`, `why` being the operator-facing phrase for
  whichever test rejected the hit.
  - **Every intersection per source pair, not the first** (2026-08-06). The
    walk is `pf:poly-x-all`; each hit gets its own station resolution, refine,
    filters and ledger key. Before this a target could show at most one
    crossing per other line, and *which* one depended on the walk direction, so
    two lines crossing twice disagreed about which crossing existed. The ledger
    already keyed on source **and** target station, so nothing there changed.
  - **Non-crossings are filtered HERE**, by **three** tests. It belongs
    in the scan and not in `pfxl:discover` for the same reason the split exists
    at all: a filter in the command alone would leave the palette previewing
    tie-ins that running Crossings then refuses to file.
    - `pf:shared-structure-p` — an intersection at a terminus of either `.cl`.
      Runs first because it is arithmetic on two numbers already in hand.
    - `pf:pro-outside-p` — the hit's SOURCE station lies outside that line's
      `_INV.pro`. **A `.cl` runs the whole alignment; a pipe exists only over
      its own profile**, so two centerlines crossing past the end of the pipe
      run cross no pipe. Added 2026-08-06: `profile_z` extends the end tangent
      rather than refusing, so such a hit used to be labeled with an invert
      interpolated off a pipe that is not there. The `.pro` path and checksum
      are resolved once per source line in the pre-pass, and the range behind
      `pf:pro-outside-p` is cached on path+checksum, so this runs ahead of the
      structure test — one cached API call beats an `ssget`. **The range is
      `profile_sta_range`, not the `.pro`'s vertex stations**: those two are not
      the same domain when a profile is authored from 0+00 along its own run,
      and the vertex version dropped legitimate crossings for it.
      **Source side only, by decision** — a label past the last structure on
      the target grid is harmless for now; adding the target arm is one more
      `pf:pro-outside-p` call against the anchor's own `_INV`.
    - `pfa:struct-shared-p` — a structure block at the hit, on **both** lines.
      **This is the one that catches most of them.** The terminus test reads
      where the centerlines stop, which only answers the tidy tie-in; a branch
      drawn a few feet past the main, or two mains meeting through a junction
      box mid-run, terminate nowhere near the joint, and widening
      `*pfx-terminus-tol*` cannot reach either case because it is measuring the
      wrong thing.
    - The gather is **lazy and once per scan** — `pfa:gather-inlets` fires on
      the first pair that both intersects and survives the terminus test, so a
      scan where every pair short-circuits on checksums never pays the `ssget`.
  - `skips` is **returned, not discarded** — `pfxl:discover` names each one on
    the command line, so a rejected crossing is distinguishable from a missed
    one and `*pfx-terminus-tol*` can be argued with.
  - **`write-p` threads straight to `pf:cl-geom` and decides nothing else.**
    `nil` makes this a pure read, legal from a modeless handler; `T` is
    discovery's own scan and files the GEOM cache. **Nothing here writes the
    ledger either way** — classification is a read, merging is the caller's.
  - **It lives here, not in pfxlabel**, for two reasons: load order (pfanchor
    is position 4, pfxlabel 9, so `pfa:target-items` could never call upward),
    and ownership — pfanchor already holds `xing-key`/`classify`/`merge`/`list`
    and SCOPE, while every geometry helper is down in pftools-lib.
  - **The checksum short-circuit is what makes a preview affordable.** A pair
    whose two `.cl` checksums **and the source's `_INV.pro` checksum** match
    SCOPE was already cut by the last discovery, so **all** its hits are in the
    ledger.
    The `.pro` joined that test when its range became a filter — on `.cl`
    alone, extending a pipe run would never bring its crossing back. `pf:poly-x` is O(n × m) segment
    tests per pair. Steady state costs almost nothing; only new or changed
    lines are re-cut — exactly the set worth showing.
  - **The memo covers the cold case.** A never-discovered target has no SCOPE,
    so nothing short-circuits and every pair is cut on every click. Keyed on
    anchor + every checksum + the SCOPE record, which fully determine the
    answer. Same pattern as `pfa:pend-for`; shares `pfa:memo-get`/`put`.
    **Read-only scans only** — discovery bypasses it, because a hit would skip
    the `pf:cl-geom` filing that passing `T` is *for*.
- `pfa:struct-shared-p xy tbl inlets` → T | nil — pure read. T when a structure
  block sits within `*pfx-struct-tol*` (5.0 ft) of `xy` **and lies on both**
  lines of `tbl`. **The "both" is the whole safety margin**: a water line
  crossing *under* a storm manhole is a genuine crossing, and that manhole is
  on the storm `.cl` only; a junction manhole is on both. "On" is
  `pf:lines-at-point`'s `*pf-offset-tol*` (0.15 ft) — the same seam pflabel
  uses to assign a structure to a line, so the two passes cannot disagree about
  a joint. `tbl` holds exactly two lines, so a second hit *is* both.
- `pfa:xing-line-tbl tcl tname tgeom scl sname sgeom` → 2-row cl-table | nil —
  the pair being intersected, in `pf:lines-at-point`'s shape. **Not
  `pfa:build-lines`**: that one publishes `*pfa-roster*` and hunts drawn twins,
  both wrong from a palette click, and the sampled verts are already in hand.
  Corridor is `*pf-corridor-sampled*`. A missing range yields nil rather than a
  row with nil bounds, which `pf:lines-at-point` would compare arithmetically.
- `pfa:xing-shared-split anchor entries write-p inlets` →
  `(keep ((entry . why) …))` — **the one place a FILED record is re-tested**,
  and it exists because the read and the write have to give the same answer.
  Rejects carry their grounds because only this knows which test fired. The scan's filters gate only what
  gets *filed*; "on record" is a claim made by whatever run filed it, under
  whatever filters existed then, and is not the same claim as "is a crossing".
  Both readers (`pfa:xing-find`, `pfa:target-counts`) and the writer
  (`pfa:xing-sweep-shared`) partition through this, so they cannot drift.
  - Runs **all three** tests in the scan's order. Terminus alone would leave
    exactly the records that motivated the structure test, and neither
    shared-structure test sees a hit past the end of the source's pipe.
  - **No intersection is recomputed** — the record carries both stations
    (groups 40, 41) and the intersection point (group 10), so this is one
    `pf:cl-geom` per **distinct source**, not per record, and GEOM cache hits
    make those near-free. The same per-source cell carries the `_INV.pro` path:
    `pfa:src-files` runs a full-DB `pfa:find-anchor` scan, which is exactly
    what a per-record resolution would pay.
  - **`write-p` threads to `pf:cl-geom` and decides nothing else**, same seam as
    the scan: the palette passes nil, the sweep passes T inside its undo group.
    Nothing here writes the ledger either way — rejecting is the caller's.
  - **`inlets` is an in-parameter** so a caller already holding the gather
    spends one `ssget` instead of two; `pfa:target-counts` hands its over. nil
    means "gather your own". A drawing with no structures re-gathers on each
    call and gets nil again — one wasted `ssget`, right answer, and not worth a
    third state to avoid.
  - **Empty `entries` costs nothing** — the gather is skipped, so a target with
    no crossings on record pays nothing for this on a click.
  - **Unreadable geometry rejects nothing** — `pf:sta-at-end-p` answers nil on
    a nil range, `pfa:xing-line-tbl` refuses to build a row without one, and
    `pf:pro-outside-p` answers nil on a `.pro` that is unbound, missing or
    whose range the API refuses, so a stale path leaves survivors rather than
    silently eating real crossings. Unknown must never read as absent.
- `pfa:xing-sweep-shared anchor` → `((sbase tsta ssta why) …)` — **makes the split
  permanent.** A WRITER; never call it from a modeless handler. `pfa:xing-find`
  drops a rejected row from what it *shows*, but the record is still on the
  ledger, and a rescan cannot retract it either: the checksum short-circuit
  skips any pair whose two `.cl` are unchanged, so the pair is never re-cut.
  Only this deletes. Returns the scan's `skips` shape so `pfxl:discover` reports
  both through one path; called there **before** the scan, and its result stands
  whether or not the scan then runs.
- `pfa:xing-find anchor` → `(T . ((entry state) …))` | nil — pure read. Merges
  what is on record with what the scan finds on the ground, so the palette can
  show a crossing **before** it has been discovered. **Ledger rows go through
  `pfa:xing-shared-split` first** — otherwise a tie-in filed by an older run
  shows as a crossing until PFXLABEL is next run, which is the preview/command
  disagreement the scan split was built to end. `state` is `LABELED` /
  `OUTSTANDING` / `NEW` / `MOVED`. A `MOVED` hit drops the stale ledger row
  rather than showing it twice; `UPDATED` is not added separately — same
  crossing, same key, and the ledger row carries the surveyed elevations.
- `pfa:xing-classify dict e` → `(status existing-key | nil)` — pure read, the
  whole of `pfa:xing-merge`'s decision and none of its filing, so the preview
  and the writer cannot drift. Takes the **dict**, so the caller decides
  whether it was opened with `create` T; a nil dict answers `NEW`.
- `pfa:split`, `pfa:scope-read` — moved down from pfxlabel 2026-07-30 with the
  scan, for the reason `pfa:entry-cl` was: pure record knowledge that a reader
  four load positions above it now needs. `pfa:scope-read` returns
  `(sbase target-cksum source-cksum source-pro-cksum)` per source line; a short
  record is **dropped, not padded** — that costs one full rescan on the first
  run after an upgrade and then self-heals, while padding would claim a `.pro`
  had been checked when it never was.
  - **Records are stored behind `*pfx-scan-schema*`** and one from another
    schema is dropped whole. This is the escape hatch for the short-circuit:
    a change to what the scan *answers* — a new filter, a different hit set —
    is otherwise invisible on an unchanged drawing, because the pair is never
    re-cut and the stale answer stands forever. **Bump the constant in the same
    edit as any such change**; it costs one full rescan per target.
- `pfa:target-items anchor pass` → `(T . ((item station state) …))` | nil —
  **the item-level twin of `target-counts`**, for the palette's `lvwCommand`
  list. `pass` is `"LABEL"` \ `"INVERT"` \ `"XING"`. Counts answer *how much*;
  this answers *which, and where* — the same question `pflabel:rd-fill`'s list
  answers, minus the dialog.
  - **One shape for all three passes**, because the control showing it has one
    set of columns. `station` is always on the target. Elevations
    (`pfa:xr-telev` / `-selev`) are deliberately excluded — no room for them at
    the 420px form width.
  - **`item` is the DRAWN NAME as of 2026-08-03**, via `pfa:id-for-hits` —
    the combined ID PFLABEL puts on the sheet, not the block name, which names
    the drafting symbol rather than the structure. It comes off each pend row's
    own hits, so the Item column costs no membership work on a radio click.
    `XING` is unchanged and still reports the *crossing line's* name, which is
    already the pipe's own ID.
  - **`state` is a SYMBOL, not a boolean** — `LABELED` / `OUTSTANDING`, plus
    `NEW` / `MOVED` for `XING`. It was a bare `T`/`nil` that meant something
    slightly different per pass, which is what made adding the two crossing
    states awkward; one vocabulary means the renderer never switches on `pass`.
  - **`(T . rows)`, not bare rows.** `nil` and `'()` are the same object, so a
    bare list cannot separate "no `.cl` bound" from "read fine, nothing on this
    line", and those need different words on screen. Same idiom, same reason as
    `pfa:memb-get`.
  - Shares `pfa:pend-for`'s memo with `target-counts`, so the second call in
    one palette click is a memo hit, not a second inlets × lines walk.
  - **`XING` is LIVE as of 2026-07-30**, via `pfa:xing-find` — not ledger-only.
    An empty Crossings list now means the `.cl` genuinely crosses nothing, not
    that nobody has looked yet.
- `pfa:line-loaded-p`, `pfa:pass-xs` → `(all-xs sta-xs)`, `pfa:labeled-x-p`,
  `pfa:cluster-xs`, `pfa:orphan-xs` (the drift detector — **station lines only
  as of 2026-08-03**; the text columns straddle the station by up to 4h against
  a 1.5h eps, so feeding it every pass entity reported drift on every line),
  `pfa:inlet-sig`, `pfa:lines-sig`, `pfa:memo-get`, `pfa:memo-put`,
  `pfa:count-t`.

**Record reads:** `pfa:meta-get`, `pfa:files-get`, `pfa:status-get pass`,
`pfa:status-label`, `pfa:status-check`, `pfa:status-roll`,
`pfa:status-rank`, `pfa:status-why anchor pass` (findings strings when
STALE/FAILING — the palette's "why" rows), `pfa:status-key`,
`pfa:scope-get`, `pfa:stub-get`, `pfa:stub-list`, `pfa:twin-get`,
`pfa:geom-get`, `pfa:nod-dict create`. (The twin-cksum reader was
quarantined to `_attic` 2026-08-01 — its witness step was never built.)

**STATUS is two records plus a live roll-up.** `STATUS_LABEL` covers the
`.cl`, `STATUS_INVERT` the `_INV .pro`. `STATUS_XING` was retired
2026-08-01 (DATA-FLOW §4.1): it stored the same target-`.cl`-vs-META
verdict as `STATUS_LABEL` through the same code, so it could never
disagree and the roll-up counted one question twice; per-source checksums
stay in `SCOPE`, which is not copied. Old XING records are simply no
longer read. The roll-up is `pfa:status-roll`, **worked out on read and
never stored**, because nothing would update a saved summary when a
record beneath it moved. Worst state wins, so one failing input cannot
read green. `pfa:status-get` falls back to the pre-split `STATUS` record
so an anchor written before 2026-07-27 still reports something.
**What is stored is the input's checksum at pass time**; done-out-of-total
counts are NOT — a saved count reads 12-of-12 forever after someone erases
a label, so the live gather owns that number.

**Membership index (§4b):** `pfa:build-lines pairs` → line table (moved from
pflabel; publishes `*pfa-roster*`), `pfa:gather-inlets` → rule-matching
model-space INSERTs (also moved), `pfa:line-stamp` / `pfa:roster-stamp` /
`pfa:roster-set`, `pfa:memb-put` **W**, `pfa:memb-get` → `(T . hits)` | nil,
`pfa:memb-sync` **W** (the engine top-up; no-op when current,
catch-wrapped), `pfa:lines-at ent pt lines` — **THE READ SEAM**, and
`pfa:index-lines` / `pfa:index-build` **W** / `pfa:index-scan` /
`pfa:index-verify` behind `C:PFINDEX`.

**`pfa:index-repair` W (2026-08-01, DATA-FLOW §6):** PFSETUP's registration
tail. Writes a `MEMB` record only where **no record exists at all** and
counts the rest — `(written skipped current stale)`, nil when the index is
off. STALE records are deliberately left for the engine top-up or an
explicit `PFINDEX Build`: repairing absent-only keeps registering n lines
roughly linear, where a rebuild per registration would be O(n²) (the roster
stamp folds the whole line table, so every registration invalidates every
record). Caller holds an open undo group.

`pfa:memb-get` returns a **cons**, not a bare list: a structure genuinely on
no line has an empty hit list, and nil and `'()` are the same object in
AutoLISP — returning the list bare would make "no record" and "on nothing"
indistinguishable, so every off-line structure would re-derive forever.

The whole index obeys `*pf-index-on*`. With it nil, `pfa:memb-get` always
reports a miss and every caller falls back to `pf:lines-at-point` exactly as
before the index existed. **That is the field rollback** — records already
in the drawing are left alone and resume being used when it goes back on.

**Copy detection:** `pfa:copy-p` (self-handle stamp vs live handle),
`pfa:purge-copy` **W** (erase the block only — NEVER walk cloned handles).

**Pass ledger:** `pfa:pass-put` **W**, `pfa:pass-get`, `pfa:pass-handles`,
`pfa:pass-names`, `pfa:erase-pass` **W** (erase-by-handle, live handles
only, then drops the record).

**Crossings (§5):** `pfa:xr-*` accessors (the 10-list working entry),
`pfa:xing-key`, `pfa:xing-list`, `pfa:xing-merge` **W** (additive;
elevations preserved; key drift renames), `pfa:xing-put-elevs` **W**,
`pfa:recon xform work` (read-only labeled? map), `pfa:station-line-tops`,
`pfa:collect-300`.

**Picking (§6):** `pfa:pick-anchor msg` (entsel loop), `pfa:choose-anchor`
(list dialog).

**The command wrapper (§6, audit #9):**
- `pf:run-command name flush work` — THE shared prologue/epilogue: *error*
  save/install, echo-off/on, **`pf:load-apis`**, error-path teardown.
  `flush` = the command's Esc ledger-flush hook (quoted symbol | nil);
  `work` = the command body.
  API loading joined the prologue 2026-07-29: it had been the first line of
  each command BODY, and six of the nine entry points remembered it —
  `C:PFPVERB` did not, so the palette's anchor button died on
  `bad function: CF:ROAD_API` in any session that had not already run a
  command-line PFTools command. A command body must never call
  `pf:load-apis` itself; the wrapper owns it.
- `pf:run-error msg` — the one *error* handler. Error-path order (locked):
  ledger-flush hook → close undo group → `pf:zoom-onerror` → restore
  `*error*`.
- `pf:undo-begin` / `pf:undo-end flag-sym` — the per-command undo-group +
  flag pattern. `pf:group-open-p` — any pf group open?

**Teardown (§7):** `pfa:teardown-counts`, `pfa:teardown` **W**;
`pfrem:remove-anchor anchor` **W** — confirm + tear down ONE anchor the caller
already has (copy-safe purge offered for copies); opens the undo group and owns
the `*pfrem-undo-open*` reset. `pfrem:cmd` is now only *find a target, then call
it*, and `C:PFREMOVE` is unchanged by the split. The palette's `btnRemove`
(2026-07-30) calls `pfrem:remove-anchor` directly with the selected row's
anchor — a split, **not** a graft, so no palette-only global reaches this file
and command-line behaviour is byte-identical (PALETTE-LAYOUT §10).

**`C:PFINDEX` (§8)** — `[Build/Verify/Report] <Report>`.
- **Build** **W** rewrites every structure's record. Nothing in normal use
  walks every structure — the engine top-up only refreshes what it labeled —
  so a never-indexed drawing, or one where a line was just added, needs
  this. The cold build is *allowed* to be slow.
- **Verify** computes membership BOTH ways and names the disagreements.
  Every other acceptance test for the index is "same labels, faster", and
  nothing else compares the two answers; this is the only thing that turns a
  quiet wrong answer into a visible one. Empty output is the evidence.
- **Report** (default) — current / stale / not-indexed counts plus the live
  roster stamp. Pure read.

**`C:PFADOPT` (§9)** — take ownership of anchors pasted in from another
drawing, so a new file inherits its bindings instead of being re-anchored line
by line.

A pasted anchor keeps its ledger (the extension dictionary is hard-owned by the
block) but gets a fresh handle, so META's 302 stamp no longer matches and
`pfa:copy-p` reads T — after which `pfa:registry` drops it and
`pfa:find-anchor` will not resolve it. That guard cannot tell a duplicate grid
in *this* drawing from an import, so PFADOPT makes the distinction it cannot.

- `pfa:adopt-keep` — the whitelist, `("META" "FILES")`. One home: `pfa:adopt`
  drops by it and the confirm text describes it, so the two cannot drift.
- `pfa:adopt-test anchor` → `OK` | `NOTCOPY` | `SHADOWED`. Pure read.
  `SHADOWED` means a live non-copy anchor here already holds that UTIL+LINE;
  the test is one `pfa:find-anchor` call, which already excludes copies.
- `pfa:adopt-cl-ok anchor` — does META's .cl resolve on this machine? META
  stores an **absolute** path, so a drawing adopted into a different project
  folder binds to files that are not there. Reported, never refused —
  re-binding is two clicks in PFSETUP (edit), and refusing would send the user
  back to re-anchoring.
- `pfa:adopt anchor` **W** → records dropped. Deletes every ledger key outside
  the whitelist, then `pfa:stamp-self` re-points 302 at the block's own handle.
  Caller holds the undo group and must have run `pfa:adopt-test` first.
- `pfadopt:candidates`, `pfadopt:cmd`, `C:PFADOPT` — works on **every** copy in
  the drawing, not a pick-one loop: the reason to copy anchors at all is that
  there are dozens. Full verdict prints to the command line before one confirm.

**Why the drop is mandatory:** `STATUS_*`, `PASS_*` and `X_*` record entity
handles, and handles are per-drawing. Carried across they name unrelated
objects in the new file, where teardown erases by handle. Whitelist rather than
blacklist so a record type added later is dropped by default. Crossings and the
membership index are rebuilt by PFXLABEL and PFINDEX afterwards, which is why
nothing here tries to preserve them.

`*pfadopt-undo-open*` is the sixth flag in `pf:group-open-p` and in
`pf:run-error`'s reset — a write command whose flag is missing from both leaks
an open undo group on Esc.

## Invariants

- Reads are pure. Writes happen only inside caller-opened undo groups.
- **The gather path's narration is suppressible; its findings are not.**
  `pfa:build-lines`' per-line "Loaded line …" and `pfa:status-for`'s DRIFT
  block go through `pf:progress`, because the palette runs this same path on
  every tree click (`pfa:target-counts` alone calls `status-for` twice). The
  "could not read a station range" error beside them stays a `prompt` and
  always prints. New output here picks a side deliberately.
- **A command never inherits a mute.** `pf:run-command` clears `*pf-quiet*` in
  its prologue and `pf:run-error` clears it on the error path, alongside
  `pf:echo-on` and for the same reason: whatever the console state was borrowed
  for, the wrapper hands it back. Callers that bind the flag (the palette's
  read fills, and its run gather in `pfp:run-labels`) still reset it
  themselves — but a throw can skip that reset, and the resulting failure is
  session-long, silent, and mutes *every* command. This makes the flag safe to
  bind from anywhere without each caller having to be perfect.
- NO layer-scoped erases. Erase happens BY HANDLE only.
- All state hangs off the anchor block; erase the anchor and the ledger
  dies with it (hard owner). No reactors, no background execution.
- `pfa:nod-dict` / `pfa:ledger-dict` with create nil never write — the
  palette-safety seam: opening the palette must not dirty a clean drawing.
- The Esc flush runs INSIDE the still-open undo group (entmakex/dictadd are
  *error*-legal), so one U still peels the whole run.
- CAVEATS: do NOT run ATTSYNC/BATTMAN on PF-ANCHOR (attribute positions
  are absolute). Negative stations are not supported by the crossing
  content key.

## Open issues local to this file

- Per-crossing `pfa:find-anchor` full-DB scans (perf) —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) "Shared / cross-cutting".
- Anchor block style wants a formatting pass —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md).
- Unused exports adjudicated 2026-08-01 (DATA-FLOW §5): `pfa:twin-cksum`,
  `pfa:xr-tfile`, `pfa:xr-tbase` quarantined to `_attic`; `pfa:xr-telev` /
  `pfa:xr-selev` KEPT for PFCHECK (pipe clearance, Version 5.1 §5).
