# pftools-lib.lsp — shared engine (PURE)

**Load position:** 2 of 12 (after pftools-cfg, before pfdraw).
**May depend on:** pftools-cfg. *Runtime-only exception:* `pf:cl-geom` calls
`pfa:geom-get` / `pfa:geom-put` (pfanchor, loads later) — the GEOM cache
seam; resolved at call time, load order unaffected.
**Depended on by:** pfdraw, pfanchor, pfsettings, pfsetup, pflabel,
pfxlabel, pfinvert.

## What it owns

The dependency root (with pfdraw): pure math, transforms, string helpers,
name parsing, **.cl file parsing** and .cl sampling, membership, ranking,
label composition, READ-ONLY drawing queries (ssget/entget/textbox), the
Carlson API wrappers (Road API for stationing from .cl FILES, DTM API for
surface elevation), the command-echo save/restore, and the zoom-to
verification parade.

## Public API

Functions other files call (writers marked; everything else is a pure read).

**Carlson wrappers + echo (§1):**
- `pf:load-apis` — scload tri4/eworks, silent. **Called by `pf:run-command`
  (pfanchor), not by command bodies** — moved there 2026-07-29 after
  `C:PFPVERB` reached a centerline read without it and died on
  `bad function: CF:ROAD_API`. Idempotent; never call it from a body again.
- `pf:echo-off` / `pf:echo-on` — CMDECHO save/restore, SAVE-ONCE: a nested
  call can never clobber the user's saved value. Called by `pf:run-command`
  / `pf:run-error` (pfanchor).
- `pf:cl-range clfile` → `(s0 s1)` | nil.
- `pf:cl-locate-safe clfile pt` → `(sta offset projpt)` | nil — radial
  fallback at termini only. **It does NOT silence Carlson's console output**
  (an older comment claimed it did): a failed `cl_location_at_pt` prints
  `Error: unable to locate point along centerline` from C++, below LISP,
  where `vl-catch-all-apply` cannot reach it. The only defence is not making
  the call — see the corridor pre-filter in `pf:lines-at-point`.
- `pf:pro-z pro sta` / `pf:pro-verts pro` — authored profile reads
  (pro-verts parses the .pro file, the suite's ONE file read; cached).
- `pf:pro-z-verts verts sta` → elevation | nil — the same station→elevation
  question answered off a vertex list already in hand, linear between
  bracketing vertices, nil outside range. **Prefer it whenever one profile is
  sampled at many stations:** `pf:pro-z` is a Road-API call each time, and a
  missing `.pro` makes Carlson print `unable to open file` from C++ per call,
  where `vl-catch-all-apply` cannot reach it. `pf:pro-verts` is silent on a
  missing file, so read once and sample locally. Linear is exact for a pipe
  profile (`.pro` column 3, vertical-curve length, is always 0.0 on a pipe
  run); a profile with real curves must still go through `pf:pro-z`.
- `pf:pro-range pro` → `(s0 s1)` | nil — the profile's station range from
  `profile_sta_range`, cached on path+checksum. A missing file returns nil
  **without calling the API**, so it never triggers Carlson's uncatchable C++
  `unable to open file` pair. Un-quarantined from `_attic` 2026-08-06.
- `pf:pro-outside-p pro sta` → T | nil — T **only** when the range reads AND
  `sta` falls outside it: "there is authored profile here and the pipe does not
  reach this station". An unbound, missing or unreadable `.pro` answers nil,
  because unknown must not read as absent. Exists because `profile_z`
  **extends the end tangent instead of refusing** — that is how a crossing past
  the end of a pipe run used to get a plausible interpolated invert.
  - **It uses `pf:pro-range`, not the vertex list.** It used the vertices for
    half a day and that was a real defect: **`.pro` stationing need not match
    its `.cl`'s** — a profile authored from 0+00 along its own run belongs to a
    line starting at 5+00 — so raw vertex stations read legitimate crossings
    near either end as outside. `pf:pro-verts` only *warns* about that domain
    gap; the API resolves it. There is deliberately **no vertex fallback**: a
    refused call means the range is unknown in the domain that matters, and
    unknown keeps the crossing.
- `pf:pipe-at inv-pro top-pro sta` → `(inv-elev . nominal-size)` | nil — nil
  when `sta` is outside EITHER `.pro`'s range (2026-08-06), so the profile is
  what says where the pipe exists, for every caller (pfxlabel, pfreport, pfqty,
  pfinvert), not just crossings.
- `pf:cl-geom clfile write-p` → `(range . verts)` | nil — THE cached .cl
  seam. **write-p is the read/write contract:** gather paths pass nil (a
  cache miss re-reads, never files); only PFSETUP registration and
  PFXLABEL discovery (inside command undo groups) pass T. **WRITER when
  write-p is T.** On a miss it tries `pf:cl-parse` FIRST and files
  `*pf-geom-exact*`; only a refused parse falls back to the Road-API walk
  and `*pf-geom-sampled*`. It **returns 2-element `(x y)` verts in both
  cases** — the stationed triples go to the store, not to callers, because
  `pf:poly-x` feeds verts to `inters`, which reads a third element as Z.
  Read stations back with `(nth 4 (pfa:geom-get clfile))`.

**The .cl file parser (§1, landed 2026-07-27):**
- `pf:cl-parse clfile` → `((x y sta) ...)` | nil — reads the `.cl` directly:
  drawing coordinates, ascending station, arcs densified at
  `*pfx-sample-step*`. nil means the file is not parseable under the
  documented grammar and the caller must fall back to the walk. Replaces
  ~570–2200 Road-API calls per line with one file read.
- `pf:cl-parse-ok-p clfile verts` → T | nil — verifies a parse against the
  trusted authored reader before anything downstream trusts it (station
  domain vs `cl_sta_range`, coordinate order vs `cl_location_at_sta`). Same
  discipline as `pf:pro-verts`' station cross-check. Names the SWAPPED case
  explicitly, since a mirrored parse is otherwise silent.
- `pf:cl-arc-points cx cy pc pt delta` → intermediate `(x y sta)`, PC/PT
  excluded. Sweep comes from the STATIONING (`arclen / R`), not the file's
  delta; the delta gives only direction, and its magnitude is cross-checked
  and warned about rather than trusted.
- `pf:dms->deg packed` → signed decimal degrees. `.cl` deltas are packed
  `DD.MMSSsss`, **not** decimal degrees.

Format notes live in the section header above `pf:cl-parse` — the four
silent traps (delta-not-station, packed DMS, centre-not-vertex, and
northing/easting vs X/Y) are documented there and confirmed against
`Carlson_References/*.cl`.

**Geometry + membership (§2–3):** `pf:pt-seg-dist`, `pf:pt-poly-dist`,
`pf:in-corridor-p pt verts tol` (**tol nil ⇒ `*pf-corridor*`**; a shape that
only approximates the .cl passes its own wider corridor),
`pf:lines-at-point pt2d cl-table` (the membership test — corridor pre-filter
then `cl_location_at_pt`), `pf:sort-line-infos-alpha`, `pf:rank-on-line`,
`pf:idx-add`.

`cl-table` entries are `(clfile name lo hi verts [corridor-tol])`. The 6th
slot is OPTIONAL — absent means the exact `*pf-corridor*`. **The pre-filter
is the error-parade guard:** every point that gets past it costs a
`cl_location_at_pt`, and a miss prints to the command line from below LISP.
An entry with nil verts turns the filter OFF for that line and tests every
structure in the drawing against it.

**The xform alist (§4):** `pf:make-xform`, `pf:xf-get` / `pf:xf-put`, the
`pf:xf-*` accessors (the ONLY sanctioned way to read one), `pf:xf-sf`,
`pf:scale-factor`, `pf:text-height`, `pf:station->profile-x`,
`pf:elev->profile-y`, `pf:grid-top-y`, and the two inverses `pf:y->elev` /
`pf:profile-x->station` (reads a DRAWN entity's X back as the station it was
drawn at — what lets an orphaned label name its station).

**Strings, naming, layers (§5–7):** `pf:join`, `pf:split`, `pf:trim`,
`pf:subst-token`, `pf:index-of`, `pf:cl-id` (canonical file identity — the
single source for GEOM/TWIN keys and pair dedup), `pf:dedupe-pairs`,
`pf:type-of` / `pf:name-of` / `pf:parse-pro-name` / `pf:tin-role` (the
naming convention), `pf:std-label`, `pf:cross-desc`, `pf:nearest-size`,
`pf:size-blockname`, `pf:size-rowtext`.

**Materials (§7).** `*pf-materials*` is one row per material — `(KEY N DIMS
TYPES)` — and these are its only readers. Four consumers went through three
lists that had to agree by hand until 2026-08-04; they now go through one.

- `pf:mat-for mat` → row | nil — exact key, then the leading token, so
  `"RCP III"` resolves to the `RCP` row. **That fallback is the no-migration
  guarantee:** anchors holding a bare `"RCP"` in FILES code 5 keep resolving
  after class-bearing keys go on the sheet.
- `pf:mat-n mat` → Manning's n, `*pf-nvalue-default*` when unknown. Replaces
  `pfr:nvalue` \ `*pfr-nvalues*`, which both exports called separately.
- `pf:mat-od mat size` / `pf:mat-wall mat size` → inches | **nil**, and nil
  means NOT ON RECORD. The DIMS column is deliberately unpopulated until the
  firm's material list lands. A caller that reads nil as zero or as a pass
  defeats the point — outside-to-outside clearance must report *unknown*.
- `pf:mat-list type` → the keys offered for a utility type, rank 1 first, so
  the head of the list is that type's default. PFSETUP's dropdown.
- Row accessors: `pf:mat-key` / `pf:mat-n-of` / `pf:mat-dims` / `pf:mat-types`.

`pf:sym-layer` / `pf:text-layer` / `pf:align-layer` are **RETIRED** (2026-07-29)
and have no callers: label output no longer derives a layer from the utility
type, it goes to `PF-ANNO` via `pfd:anno-layer`. They are kept, with
`*pfx-layer-suffix*` / `*pfx-text-layer-suffix*`, so a revert to per-type
layers is a one-line change at each call site. pf-verify's dead-code gate names
`pf:text-layer` and `pf:align-layer`; that is expected, not drift. `pf:sym-layer`
stays off the list only because `pf:align-layer`'s fallback branch still calls
it — both are dead in practice.

**Rules + composition (§8–10):** `pf:rule-for`, `pf:rule-size`,
`pf:fmt-station`, `pf:combine-id`, `pf:build-label-rows`, `pf:text-length`,
`pf:strip-trailing-eq`.

**Crossing geometry (§11):** `pf:poly-x-all`, `pf:poly-x`, `pf:pt-near-any`,
`pf:refine-x`, `pf:sta-at`, `pf:sta-at-end-p`, `pf:shared-structure-p`.

- `pf:poly-x-all vertsA vertsB` → `((x y) …)` in A's walk order — **every**
  intersection. **Discovery must use this one.** `pf:poly-x` returns the first
  hit and is now just its `car`, kept for `pf:refine-x`, which re-samples a ±1
  step window around a hit already found.
  - **Why it matters:** two lines crossing twice is ordinary, and one hit per
    pair capped every target at one crossing per other line. It was also
    direction-dependent — the outer walk is the *target's* vertices, so each
    line's list showed a different one of the two and each looked like it was
    missing a crossing the other had. Found 2026-08-06 on a storm/water pair.
  - Hits within `*pfx-sample-step*` (2.0 ft) of one already kept collapse:
    `inters` fires on both segment pairs at a shared vertex, and a shallow
    crossing on sampled geometry registers on several. Two genuine crossings
    that close do not exist.
  - **No early exit**, unavoidably. A pair that never crosses already walked the
    whole product and that is the common case, so only crossing pairs pay.

- `pf:shared-structure-p trng tsta srng ssta` → T when a hit sits within
  `*pfx-terminus-tol*` of a terminus of **either** alignment — a junction
  manhole or a branch tying into a main, not a pipe crossing. `pf:poly-x` is a
  bounded `inters` test and cannot tell the two apart: endpoints that touch lie
  on both segments. **Either, not both** — an end-to-end junction puts both
  lines at a terminus, but a tee puts only the branch there. Callers are
  `pfa:xing-scan` and `pfa:xing-sweep-shared`, and both report their skips by
  name rather than dropping them, which is what makes the "either" side of the
  trade safe.
  - **It is the FIRST of three tests, not the filter.** It reasons about where
    the centerlines stop, so a branch drawn a few feet past the main and two
    mains meeting through a junction box both get past it at any tolerance.
    `pfa:struct-shared-p` (pfanchor) is the broader one; this stays because it
    is free and still catches the tie-in with no structure block drawn.
    `pf:pro-outside-p` sits between them and answers a different question —
    not "is this joint shared" but "is there a pipe here at all".

**Twin matching (§12):** `pf:cl-endpoints`, `pf:cl-twin-handle`,
`pf:twin-verts` (LIVE read via handle — never cached stale).

**Sheet reads (§13):** `pf:parse-sheet-name`, `pf:sheet-type`,
`pf:type-keyword` (token → printed words; `FORCEMAIN` → `FORCE MAIN`. Both
sheet reads go through it, and `pf:sheet-type` takes the LONGEST matching
keyword, never the first in `*pf-types*` — `PROPOSED SANITARY FORCE MAIN 'A'`
contains both keywords and first-hit order would call it sanitary),
`pf:top-lines` (ONE scan per pass) + `pf:top-at` (the top-of-grid probe:
highest PF-GRID-MJR hit — MAX, never min).

**Checksum + hashing (§14):** `pf:checksum-file` (content checksum,
line-ending independent, memoised on `(path, mtime, size)`),
`pf:checksum-strict`, `pf:hash-string`, `pf:hash-num`, `pf:verts-hash`,
`pf:handle`, `pf:timestamp`.

**Two checksum functions, and the difference matters.** `pf:checksum-file`
trusts `(path, mtime, size)`; its own header records the caveat that a file
edited in place preserving both reads stale out of the memo. That is a fair
trade for a CHECK, whose wrong answer dies with the session.
`pf:checksum-strict` always does the content walk and then refreshes the
memo, and it is what the **write** paths call — `pfa:line-stamp` with
`write-p` T, `pfs:place-one`, `pfs:edit-one` — because a wrong checksum
written into a record outlives every reload.

**`pf:verts-hash` replaced bbox + vertex count as the shape fingerprint.**
Drag one interior PI of a drawn centerline parallel to its bounding box and
neither the box nor the count moves, so the shape reads unchanged while the
corridor it defines has shifted — and a structure can fall outside it with
nothing to say so. That is the edit a drafter actually makes.
`pf:hash-num` takes the REMAINDER before `fix`, deliberately: a state-plane
northing times `*pf-hash-scale*` is ~1.8e10, past what `fix` can return, so
the obvious `(fix (* v scale))` overflows on exactly the drawings this firm
works on.

**Zoom parade (§15):** `pf:zoom-resolve default` (consumes the one-shot
`*pf-zoom-to*` override, call ONCE per engine run inside the ctx guard),
`pf:zoom-begin sf`, `pf:zoom-item x ylo yhi` (the command-agnostic seam,
one frame rule for all three commands), `pf:zoom-end`, `pf:zoom-onerror`
(*error*-safe restore: CMDACTIVE-gated, echo-silent, catch-wrapped). View
ops only — never an entity write.

**Console volume:** `pf:progress s` — THE seam for suppressible output.
Prints unless `*pf-quiet*` (pftools-cfg) is bound T, which the palette does
around its tree-click reads because they run the same gather path the label
commands run and it narrates itself. **Progress only.** Errors, refusals, skip
reports and `*error*` output call `prompt` directly and always print — silence
the narration, never the news.

## Invariants

- **A finding never routes through `pf:progress`.** If a message tells the
  user something is WRONG, it is a `prompt`. The palette suppressing its own
  chatter must never be able to suppress a failure — a hidden refusal on a
  modeless click is undiagnosable.
- This file may NEVER know what an anchor is, read a record, or reference a
  dialog. Nothing here writes the drawing (the §15 ZOOM/DELAY calls are
  view ops; `pf:cl-geom` files only through the pfa: seam when write-p).
- `pf:cl-parse` **never guesses**: one unknown row code refuses the whole
  file. The failure mode of guessing (a curve silently read as a chord) is
  wrong-and-quiet; refusing costs only a fallback to the walk.
- Anything returning verts to a CALLER returns 2-element points. Stationed
  triples exist only between the parser and the GEOM store.
- The top-of-grid probe takes the HIGHEST hit (grids have stepped tops);
  never conflate with the dead invert probe.
- `pf:echo-off`/`on` are save-once: only an empty save slot is written.

## Open issues local to this file

- `pf:fmt-station` misformats negative stations and rounds oddly at the
  +99.999 boundary — [../pfsuite-md/OPEN-ISSUES.md](../pfsuite-md/OPEN-ISSUES.md) LOW-5.
- Dead API surface adjudicated 2026-08-01 (DATA-FLOW §5): twelve no-caller
  utilities quarantined to `_attic` (bbox, get-verts and its private
  sample-cl / attach-corridor / find-cl-polyline chain, text-pos, ss->list,
  filter-layer + on-layer-p, remove-nth, name-prefix, fmt-elev,
  parse-line-name, pro-range). KEPT with in-file notes: `pf:tin-*`
  (minimum-coverage checks,
  [../pfsuite-md/Version 5.1.md](../pfsuite-md/Version%205.1.md) §4, LOW-6)
  and `pf:text-layer` / `pf:align-layer` (documented revert path to
  per-type layers).
- Echo non-re-entrancy was fixed 2026-07-26 with the `pf:run-command` wrapper
  (save-once semantics) — pending CAD;
  [../pfsuite-md/CLOSED_ISSUES.md](../pfsuite-md/CLOSED_ISSUES.md).
