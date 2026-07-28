# pftools-lib.lsp — shared engine (PURE)

**Load position:** 2 of 10 (after pftools-cfg, before pfdraw).
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
- `pf:load-apis` — scload tri4/eworks, silent.
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
- `pf:pipe-at inv-pro top-pro sta` → `(inv-elev . nominal-size)` | nil.
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
naming convention), `pf:sym-layer` / `pf:text-layer`, `pf:std-label`,
`pf:cross-desc`, `pf:nearest-size`, `pf:size-blockname`, `pf:size-rowtext`.

**Rules + composition (§8–10):** `pf:rule-for`, `pf:rule-size`,
`pf:fmt-station`, `pf:combine-id`, `pf:build-label-rows`, `pf:text-length`,
`pf:strip-trailing-eq`.

**Crossing geometry (§11):** `pf:poly-x`, `pf:refine-x`, `pf:sta-at`.

**Twin matching (§12):** `pf:cl-endpoints`, `pf:cl-twin-handle`,
`pf:twin-verts` (LIVE read via handle — never cached stale).

**Sheet reads (§13):** `pf:parse-sheet-name`, `pf:sheet-type`,
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

## Invariants

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
  +99.999 boundary — [../Low_Priority_issues.md](../Low_Priority_issues.md) #9.
- Dead API surface (`pf:tin-*`, `pf:bbox`, `pf:get-verts`, …) —
  [../Low_Priority_issues.md](../Low_Priority_issues.md) #10.
- Echo non-re-entrancy (#6 on that list) was fixed 2026-07-26 with the
  `pf:run-command` wrapper (save-once semantics) — pending CAD.
