# pfanchor.lsp — record + registry

**Load position:** 4 of 12 (after pfdraw, before pfsettings).
**May depend on:** pftools-cfg, pftools-lib, pfdraw. *Runtime-only
exceptions:* `pfa:choose-anchor` uses `pfset:pick-index` and PFREMOVE uses
`pfset:confirm` (pfsettings, loads later) — resolved at call time.
**Depended on by:** pfsettings, pfsetup, pflabel, pfxlabel, pfinvert,
pfpalette (+ pftools-lib's `pf:cl-geom` reads the GEOM store back through
`pfa:geom-get`/`put`).

## What it owns

The V4 model: the anchor IS the grid record; crossings are one field among
many. PFSETUP creates the record; every other command reads/updates it.
Also home to the shared command wrapper (`pf:run-command`, audit #9),
C:PFREMOVE (teardown), and C:PFINDEX + the membership index (§4b).

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
- `pfa:pending inlets lines primary` → sorted `(sta ename blkname)*`.
- `pfa:pend-for primary lines inlets` → the same, memoised — **the expensive
  half**, and the only thing `*pfa-gather-memo*` holds. Keyed on exactly what
  `pending` reads: primary, inlet signature, line signature. **Not** keyed on
  anchor or pass name; `pending` consults neither. Split out so ONE
  `inlets × lines` walk serves MANY passes, which is what the Commands tab
  needs showing Structure and Invert counts side by side.
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
  "none exist".
- `pfa:line-loaded-p`, `pfa:pass-xs`, `pfa:labeled-x-p`, `pfa:cluster-xs`,
  `pfa:orphan-xs` (the drift detector), `pfa:inlet-sig`, `pfa:lines-sig`,
  `pfa:memo-get`, `pfa:memo-put`, `pfa:count-t`.

**Record reads:** `pfa:meta-get`, `pfa:files-get`, `pfa:status-get pass`,
`pfa:status-label`, `pfa:status-check`, `pfa:status-roll`,
`pfa:status-rank`, `pfa:status-key`, `pfa:scope-get`, `pfa:stub-get`,
`pfa:stub-list`, `pfa:twin-get`, `pfa:twin-cksum`, `pfa:geom-get`,
`pfa:nod-dict create`.

**STATUS is four records, not one.** `STATUS_LABEL` covers the `.cl`,
`STATUS_INVERT` the `_INV .pro`, `STATUS_XING` the target `.cl` (per-source
checksums stay in `SCOPE`, which is not copied). The fourth — the overall
roll-up — is `pfa:status-roll`, **worked out on read and never stored**,
because nothing would update a saved summary when one of the three beneath
it moved. Worst state wins, so one failing input cannot read green.
`pfa:status-get` falls back to the pre-split `STATUS` record so an anchor
written before 2026-07-27 still reports something.
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
`C:PFREMOVE` (copy-safe purge offered for copies).

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

## Invariants

- Reads are pure. Writes happen only inside caller-opened undo groups.
- **The gather path's narration is suppressible; its findings are not.**
  `pfa:build-lines`' per-line "Loaded line …" and `pfa:status-for`'s DRIFT
  block go through `pf:progress`, because the palette runs this same path on
  every tree click (`pfa:target-counts` alone calls `status-for` twice). The
  "could not read a station range" error beside them stays a `prompt` and
  always prints. New output here picks a side deliberately.
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
- Unused exports (`pfa:status-get`, `pfa:twin-cksum`, four `pfa:xr-*`
  accessors) — [../Low_Priority_issues.md](../Low_Priority_issues.md) #10.
