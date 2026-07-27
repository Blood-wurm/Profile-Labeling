# pfanchor.lsp — record + registry

**Load position:** 4 of 10 (after pfdraw, before pfsettings).
**May depend on:** pftools-cfg, pftools-lib, pfdraw. *Runtime-only
exceptions:* `pfa:choose-anchor` uses `pfset:pick-index` and PFREMOVE uses
`pfset:confirm` (pfsettings, loads later) — resolved at call time.
**Depended on by:** pfsettings, pfsetup, pflabel, pfxlabel, pfinvert,
pfpalette (+ pftools-lib's `pf:cl-geom` reads the GEOM store back through
`pfa:geom-get`/`put`).

## What it owns

The V4 model: the anchor IS the grid record; crossings are one field among
many. PFSETUP creates the record; every other command reads/updates it.
Also home to the shared command wrapper (`pf:run-command`, audit #9) and
C:PFREMOVE (teardown).

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
- **LEDGER** — extension dictionary "PFXLEDGER" hard-owned by the anchor;
  schema 3 xrecords: `META` (.cl path + checksum + self-handle for copy
  detection), `FILES` (.pro/.tin bindings + checksums + material),
  `STATUS`, `SCOPE`, `PASS_*` (the erase-by-handle ledger; CLAYER passes
  record timestamp + layer but NO handles), `X_*` (content-keyed crossing
  records).
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
`pfa:status-put` **W**, `pfa:scope-put` **W**, `pfa:stub-put` **W**,
`pfa:stub-del` **W**, `pfa:twin-put` **W**, `pfa:geom-put` **W**.

**Record reads:** `pfa:meta-get`, `pfa:files-get`, `pfa:status-get`,
`pfa:status-label`, `pfa:scope-get`, `pfa:stub-get`, `pfa:stub-list`,
`pfa:twin-get`, `pfa:twin-cksum`, `pfa:geom-get`, `pfa:nod-dict create`.

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
  save/install, echo-off/on, error-path teardown. `flush` = the command's
  Esc ledger-flush hook (quoted symbol | nil); `work` = the command body.
- `pf:run-error msg` — the one *error* handler. Error-path order (locked):
  ledger-flush hook → close undo group → `pf:zoom-onerror` → restore
  `*error*`.
- `pf:undo-begin` / `pf:undo-end flag-sym` — the per-command undo-group +
  flag pattern. `pf:group-open-p` — any pf group open?

**Teardown (§7):** `pfa:teardown-counts`, `pfa:teardown` **W**;
`C:PFREMOVE` (copy-safe purge offered for copies).

## Invariants

- Reads are pure. Writes happen only inside caller-opened undo groups.
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
