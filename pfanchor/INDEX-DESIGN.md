# INDEX-DESIGN.md — the membership index

**Status:** design only. Nothing in this document is built.
**Date:** 2026-07-27.
**Supersedes:** the per-line index sketched in [README.md](README.md) §11.

---

## 1. The problem

`PFLABEL` on Storm BC re-derives, from scratch, the membership of every
structure against every line — including work it did on the previous run
five seconds earlier, on an unchanged drawing. Same for `PFINVERT`. The
palette will need the same facts, and `PFREPORT` will need them again.

The facts are stable. The recomputation is not free. Nothing persists them.

---

## 2. The reframe — index the structure, not the line

The obvious storage is **per line**: `INDEX_STORM_BA` → the structures on
BA. That is the natural reading of "when you anchor a line, find all the
structures on that line." It is the wrong way round.

Finding the structures on BA is the cheap half. The expensive half is
determining, for each of them, **what other lines they touch** — that is
what makes a junction and drives the combined ID. Per-line records answer
that only by reading every line's record and inverting the map: the same
all-lines scan, relocated from geometry into I/O.

Store it per structure and the question is already answered:

```lisp
((BA . 412.55) (BC . 0.00))     ; a junction — two lines
((BA . 128.90))                 ; a single
```

**A structure whose set has more than one entry is a junction.** No
cross-line read.

### 2.1 This is not a new computation

`pf:lines-at-point` takes **a point** and returns **the set of lines it
falls on**. Gather already calls it once per inlet; the full-table walk is
its inner loop. The membership pass has always been structure-outer,
lines-inner.

So the index is not new geometry and not a new loop. It is:

> `pf:lines-at-point` already computes exactly the record we want to
> store, and we discard it every run.

The record shape **is** the return shape. Per-line storage would require
inverting the result on write and inverting it back on read, twice, for
nothing.

Consequence: there is no membership code to write. The writer is
`pf:lines-at-point` plus a position stamp. The reader returns the list
`pf:lines-at-point` would have returned. Junction detection, combined IDs,
and ranking are unchanged and cannot tell the difference.

---

## 3. What the index does and does not hold

**The index stores what the geometry knows. It does not store what the
profile knows.**

| In | Out |
|---|---|
| structure ↔ line ↔ station | invert elevations |
| position stamp (drift detection) | cover over pipe |
| `.cl` content id per line | clearance at crossings |
| | wall thickness |

Every item in the right column needs `.pro` or pipe data. That the
scoped-but-unbuilt features (cover, clearance, wall thickness) all land on
the same side is evidence the line is real and not drawn to fit today's
problem.

### 3.1 Why inverts are deliberately excluded

Membership is **stable** — a structure gets placed and stays put; drift
detection exists for the exception, not the rule. Invert elevations come
from `.pro`, which **churns** through design.

Cache the stable thing, recompute the volatile thing. Persisting inverts
would produce a cache that is wrong most of the time, and would drag
`.pro` checksum tracking into the index's staleness surface.

This also matches the existing seam: `.pro` is not in `rd-compute` at all,
it enters downstream in the engine. The index sits **upstream** of that
seam, which is why `PFLABEL`, `PFINVERT` and `PFREPORT` can share it
without any of them caring.

Accepted trade: **the cold build is allowed to be slow.** No spatial hash,
no cold-pass optimisation. Run one pays; run two onward is nearly free.

---

## 4. Record shape

```
per structure entity, xdict "PFINDEX"
  MEMB   →  (x y)                        insertion point as indexed
            ((line-name . station) ...)  the pf:lines-at-point result

NOD "PFTOOLS"
  INDEX_META  →  SCHEMA
                 ((line-name . cl-id) ...)  every line in the registry
```

`cl-id` is `pf:cl-id` — already content-addressed, already used by the
GEOM store.

---

## 5. Staleness

Three events, all cheap to detect, all detectable with things that already
exist.

| Event | Detection | Blast radius |
|---|---|---|
| Structure moved | stored `(x y)` ≠ live insertion point | that structure only |
| Line geometry changed | `cl-id` differs from `INDEX_META` | records naming that line |
| Line added / removed | registry diff vs `INDEX_META` | records naming that line |

A record is trustworthy unless its line set intersects the `INDEX_META`
diff. Clean drawing, no diff → every read is a read.

### 5.1 Drift stops being inferential

The drift echo built 2026-07-27 (`pflabel:orphan-xs`) *infers*: a pass X
ordinate with no structure under it, so something moved. The position
stamp is **direct and named**:

```
STR-14 moved 2.24 ft since indexing
```

Named structure, measured distance, no digest. The orphan-X heuristic
becomes a backstop rather than the mechanism.

### 5.2 Why "anchoring BG must not invalidate BA" is free

Under per-line records that is a rule to be maintained. Under per-structure
records **there is no BA record to invalidate** — BA's structures gain a BG
entry if geometrically warranted, and nothing else changes. The property is
structural, not enforced.

---

## 6. Where it physically lives

| | Per-structure xdict | NOD keyed by handle | One global record |
|---|---|---|---|
| Dies with the entity | ✅ automatic | ❌ orphans | ❌ orphans |
| Copy contamination | self-heals | needs sweep | needs sweep |
| Partial update (one anchor) | ✅ | ✅ | ❌ rewrites all |
| Object count | +2 / structure | +1 / structure | +1 total |
| Implementation cost | highest | medium | lowest |

**Recommendation: per-structure xdict.**

- Same hard-ownership pattern the ledger already uses — "erase the anchor
  and the ledger dies with it." Erase a structure, its membership dies with
  it. No orphan sweep, ever.
- Copy contamination self-heals: a copied manhole sits at a different
  point, so its inherited stamp mismatches and it recomputes. (A copy
  in-place slips through; that case is degenerate and `pfa:copy-p` is the
  existing idiom if it ever matters.)
- The global record is tempting for a first cut but is the one option that
  makes "each subsequent anchor builds it" a whole-file rewrite.

**Write-free contract:** reads must use the `create nil` idiom, exactly as
`pfa:nod-dict` / `pfa:ledger-dict` do. The palette must never create an
xdict. It reads, and it may *report* staleness ("3 structures need
refresh") without dirtying anything.

---

## 7. The load-order blocker dissolves

Previously identified as the obstacle: `pfsetup` is position **6**,
`pflabel` is **7**, so `pfs:auto` cannot call `pflabel:pending` to build an
index at anchor time.

Under this design the writer needs `pf:lines-at-point` (lib, 2),
`pf:cl-geom` (lib, 2), `pfa:twin-get` (anchor, 4) — **no label knowledge at
all.** It sits in **pfanchor at position 4** and `pfsetup` calls it
legally.

The migration shrinks from "move four functions out of pflabel" to
recognising that `pflabel:build-lines` and `pflabel:gather-inlets` were
always registry/selection helpers and belong where the index lives.
Precedent: `pfa:entry-cl` was moved out of pfxlabel into pfanchor
2026-07-26 as "pure registry knowledge, no alias left behind."

---

## 8. Open questions — resolve before building

### 8.1 Crossings may already be done — UNVERIFIED

`X_*` on the anchor's ledger is described as a content-keyed crossing store
with additive merge, preserved elevations and key-drift renaming
(`pfa:xing-list` / `pfa:xing-merge` / `pfa:xing-put-elevs`). If that is as
mature as it reads, **crossings do not need a home in the index** — they
need reading from where they already live.

That would reduce this work from "build an index" to "add a structure store
next to the crossing store that already works."

**Not yet checked against the code.** This is the first thing to verify
when work resumes.

### 8.2 Water has no entity to hang an xdict on

Water structures have no blocks and must be found by endpoint. There is no
block to carry a `PFINDEX` xdict.

But water structures are *derived from the line's own geometry* — they
cannot drift independently, so `cl-id` in `INDEX_META` already covers their
staleness entirely. That argues water membership belongs in a **per-line**
record after all, and the index is genuinely two-shaped.

Related trap already identified: the GEOM record stores **densified**
output (Water_H = 418 points from 11 real PIs), so the true PI set is
**not recoverable from GEOM**. Water structure discovery must re-parse the
`.cl`.

Decide the shape before building, not after.

### 8.3 Write trigger

Anchor-time is settled — `pfsetup` writes on registration/placement.

Open: do `PFLABEL` / `PFINVERT` **top up** what they had to compute on a
miss (they hold an undo group open at write-pass), or do misses stay
uncached until an explicit `PFINDEX` rebuild?

- Top-up is more forgiving — the index fills in through normal use.
- Explicit-only is more predictable — the index changes only when asked.

---

## 9. What exists today

Built 2026-07-27, all still current, none of it the persistent tier:

- **bbox guard** — `pf:verts-bbox` / `pf:in-bbox-p` (pftools-lib). O(1)
  rejection ahead of the corridor test, sound with zero false negatives.
  ~55% rejection on the storm set.
- **checksum memo** — `*pf-cksum-cache*` keyed on path + systime + size
  (pftools-lib). Kills repeated content walks of unchanged `.cl` files.
- **session gather memo** — `*pfl-gather-memo*`, depth 8, keyed on anchor
  handle + passname + primary + inlet signature + line signature + pass
  ordinates (pflabel). Eliminates recomputation *within* a session,
  including across cancelled dialogs.
- **drift echo** — `pflabel:cluster-xs` / `pflabel:orphan-xs`, printed not
  persisted.

**The session memo is the read-side half of this design.** The signature it
keys on is the same information the persistent record must store and
re-validate. It is not wasted work, but it does nothing for the first
gather on a freshly-opened drawing, and nothing for a palette on a cold
drawing.

---

## 10. Build order when work resumes

1. Verify §8.1 — does `X_*` already cover crossings?
2. Decide §8.2 — water shape.
3. Decide §8.3 — write trigger.
4. Move `build-lines` / `gather-inlets` to pfanchor (§7).
5. Write the store: `pfa:memb-put` **W** / `pfa:memb-get` / `pfa:index-meta-*`.
6. Call it from `pfs:auto` and the USER placement path.
7. Point `pflabel:gather-compute` at it, behind the existing session memo.
8. `PFINDEX` rebuild command (also covers the missing GEOM re-file path —
   `pfs:auto` short-circuits already-named lines, so existing drawings keep
   SAMPLED records).
