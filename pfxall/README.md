# pfxall — `C:PFXALL`

Label every crossing on every profile in the drawing, in one pass.

Load position 10 of 15: after `pfxlabel`, before `pfinvert`. Prefix `pfxa:`.

## What it owns

The **sweep**, and nothing else. Every drawing decision — what a crossing
looks like, where the station line goes, what gets ledgered — belongs to
`pfxlabel` and is reached through `pfxl:run` unchanged. This module is the
loop, two filters, and the failure containment around them.

`pfxlabel` was deliberately **not** modified to add this. The batch form is a
different command with a different contract (no dialog, no target memory, no
parade, never asks a question), and folding it into `pfxl:cmd` would have put
a mode flag through a path that already carries the interactive one.

The cost of that choice: `pfxl:run` returns `nil`, so the sweep can total
crossings **attempted**, not labeled. The exact labeled/skipped split for each
profile is in `pfxl:run`'s own `== PFXLABEL: n labeled, n skipped ==` line,
printed per profile as the sweep runs. Giving `pfxl:run` a
`(drawn . skipped)` return would make the roll-up exact and is a one-line
change — it just is not this module's to make.

## The two filters, in order

1. **A readable `.cl`, per profile** (`pfxa:plan`, a pure read). The anchor's
   xform must read and its `.cl` must be `findfile`-present. Anything else is
   dropped whole, named, with its reason.
2. **Already labeled, per crossing** (`pfxa:one`). `pfa:recon` says which
   ledger rows are already drawn on that grid; they come out of the selection.

What survives both draws.

**Neither `.pro` is gated on the target** (2026-08-07). A crossing's elevation
comes from the **source's** `_INV` (`pf:pipe-at` inside `pfxl:label-one`), so a
profile with no `.pro` of its own still receives every crossing whose source has
one — Storm 'A' labels onto Water 'A' even when Water has no `.pro`. The target's
`_INV` feeds only the ledgered `telev`, and `pfxl:run` already degrades to a
printed "crossing elevations will not be stored" rather than refusing; its
`_TOP` is never read on the target side at all (the grid top comes from the drawn
grid, `pf:top-lines`).

The converse is per-crossing, not per-profile, and `pfxl:label-one` already owns
it: a source with no `_INV` bound is skipped by name (`NO INVERT .PRO BOUND`) on
whatever grid it crosses. So the rule is a `.pro`-per-line fact — every crossing
whose source has a `.pro` gets drawn, on whichever grid it belongs to — and
cutting the missing `.pro` later makes the reciprocal label appear on the next
sweep.

## Public API

- `pfxa:plan` — `-> (ok . dropped)`, where `ok` is `((anchor xf label) ...)`
  and `dropped` is `((label . reason) ...)`. Pure read; no discovery, no
  writes, no undo group. Built in full before anything draws, so the run
  reports its own shape before it commits. Drops on the `.cl` only — see
  *The two filters*.
- `pfxa:one anchor xf` — one profile's share: discover, drop the already
  labeled, draw the rest. Returns the count attempted, or `nil` when there was
  nothing new. Caller owns the undo group.
- `pfxa:label xf anchor` — `"STORM 'LINE-A'"`, falling back to
  `"anchor <handle>"` so an unreadable record still gets named in the skip
  list.
- `C:PFXALL` / `C:PFXA` — `pf:run-command "PFXALL" 'pfxl:flush-pass 'pfxa:cmd`.

Internal: `pfxa:cmd`.

## Invariants

- **One undo group per profile, not one per sweep.** `U` undoes one profile.
- **Each profile's work is `vl-catch-all-apply`-wrapped.** An uncaught error
  would reach `pf:run-error`, which flushes and unwinds the one open group —
  under a single sweep-wide group that is every profile already finished.
  Caught per profile, a failure costs that profile and the sweep continues.
  The catch reuses `pfxl:flush-pass` on that path, doing there what it does on
  Esc: ledger the handles that drew before the error, inside the still-open
  group, so nothing lands in the drawing untracked.
- **The file gate runs before any Road API call.** A path on record but absent
  from disk makes Carlson print an uncatchable C++ `unable to open file` pair
  per call, below where `vl-catch-all-apply` reaches. Same rule
  `pf:pro-range` / `pf:pro-verts` already follow, applied a level up.
- **The parade is forced off** — `*pf-zoom-to*` set to `'OFF` per profile and
  consumed by `pf:zoom-resolve` inside `pfxl:run`, the documented override
  seam, so the engine needs no change. Cleared on the way out so a failed
  profile cannot mute the next command's parade.
- **Nothing prompts.** PFXLABEL's relabel confirmation guards the hand-picked
  path only; the sweep never selects an already-labeled row, so it cannot
  reach that question. A sweep that stalls on a modal prompt halfway through a
  sheet is worse than one that skips.
- **Idempotent.** Re-running after an interruption resumes; it cannot draw a
  duplicate.
- `*pfxl-last*` is untouched — a sweep does not hijack the sticky target for
  the next `PFXLABEL`.

## Open issues local to this file

- The roll-up counts crossings **attempted**, not labeled — see *What it owns*.
- `pfa:recon` scans the whole drawing for station lines once per profile, so
  the sweep is O(profiles × drawing). Acceptable at sheet scale; it is the
  first thing to look at if a large sheet drags.
- A profile swept without its own `_INV.pro` ledgers `telev` nil for every
  crossing drawn on it, so clearance and anything else reading target
  elevations has a hole there. `pfxl:run` says so only when a path is on record
  and missing from disk; with no `_INV` on record at all it is silent. A
  plan-side note carried into `pfxa:cmd`'s roll-up would close that — not built.
- **Not verified in CAD.**
