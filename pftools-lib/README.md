# pftools-lib.lsp — shared engine (PURE)

**Load position:** 2 of 10 (after pftools-cfg, before pfdraw).
**May depend on:** pftools-cfg. *Runtime-only exception:* `pf:cl-geom` calls
`pfa:geom-get` / `pfa:geom-put` (pfanchor, loads later) — the GEOM cache
seam; resolved at call time, load order unaffected.
**Depended on by:** pfdraw, pfanchor, pfsettings, pfsetup, pflabel,
pfxlabel, pfinvert.

## What it owns

The dependency root (with pfdraw): pure math, transforms, string helpers,
name parsing, .cl sampling, membership, ranking, label composition,
READ-ONLY drawing queries (ssget/entget/textbox), the Carlson API wrappers
(Road API for stationing from .cl FILES, DTM API for surface elevation),
the command-echo save/restore, and the zoom-to verification parade.

## Public API

Functions other files call (writers marked; everything else is a pure read).

**Carlson wrappers + echo (§1):**
- `pf:load-apis` — scload tri4/eworks, silent.
- `pf:echo-off` / `pf:echo-on` — CMDECHO save/restore, SAVE-ONCE: a nested
  call can never clobber the user's saved value. Called by `pf:run-command`
  / `pf:run-error` (pfanchor).
- `pf:cl-range clfile` → `(s0 s1)` | nil.
- `pf:cl-locate-safe clfile pt` → `(sta offset projpt)` | nil — silences
  Carlson console spam; radial fallback at termini only.
- `pf:pro-z pro sta` / `pf:pro-verts pro` — authored profile reads
  (pro-verts parses the .pro file, the suite's ONE file read; cached).
- `pf:pipe-at inv-pro top-pro sta` → `(inv-elev . nominal-size)` | nil.
- `pf:cl-geom clfile write-p` → `(range . verts)` | nil — THE cached .cl
  seam. **write-p is the read/write contract:** gather paths pass nil (a
  cache miss re-samples, never files); only PFSETUP registration and
  PFXLABEL discovery (inside command undo groups) pass T. **WRITER when
  write-p is T.**

**Geometry + membership (§2–3):** `pf:pt-seg-dist`, `pf:pt-poly-dist`,
`pf:in-corridor-p`, `pf:lines-at-point pt2d cl-table` (the membership test —
corridor pre-filter then `cl_location_at_pt`), `pf:sort-line-infos-alpha`,
`pf:rank-on-line`, `pf:idx-add`.

**The xform alist (§4):** `pf:make-xform`, `pf:xf-get` / `pf:xf-put`, the
`pf:xf-*` accessors (the ONLY sanctioned way to read one), `pf:xf-sf`,
`pf:scale-factor`, `pf:text-height`, `pf:station->profile-x`,
`pf:elev->profile-y`, `pf:grid-top-y`.

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

**Checksum + misc (§14):** `pf:checksum-file` (content checksum, line-ending
independent), `pf:handle`, `pf:timestamp`.

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
