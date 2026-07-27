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
- **ANCHOR** — one PF-GRIDANCHOR block per PLACED profile, keyed LINE+UTIL.
  Insertion point = grid lower-left (datum + lower-left = transform
  origin). EXTENTS ARE RELATIVE: X-scale = width, Y-scale = height to the
  top-right pick — never an absolute corner (a window-move carries both).
  The stored top means "top at max station" ONLY; per-station top-Y comes
  from the top-of-grid probe (`pf:top-at`), because grid tops STEP.
  Attributes = LINE / UTIL / STA0 / DATUM / HPLOT / VPLOT.
- **LEDGER** — extension dictionary "PFXLEDGER" hard-owned by the anchor;
  schema 3 xrecords: `META` (.cl path + checksum + self-handle for copy
  detection), `FILES` (.pro/.tin bindings + checksums + material),
  `STATUS`, `SCOPE`, `PASS_*` (the erase-by-handle ledger; CLAYER passes
  record timestamp + layer but NO handles), `X_*` (content-keyed crossing
  records).
- **NOD "PFTOOLS"** — drawing-wide store: STUB_*, GEOM_* (cached .cl
  geometry, content-addressed by `pf:cl-id`), TWIN_* (drawn-centerline
  handle per .cl).
- **DERIVED** — labeled/outstanding is NEVER stored; re-read from the
  drawing on every touch (SECTION 5 recon).

## Public API

Pure reads unless marked; **writers require a caller-held undo group**.
Reads are modeless-safe (the palette contract): `pfa:nod-dict` /
`pfa:ledger-dict` with `create` nil NEVER write.

**Registry + resolution:**
- `pfa:registry` → sorted `(type name state ename stub)` rows — THE
  registry: anchors + stubs, copy-excluding, one merged sorted walk.
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
- CAVEATS: do NOT run ATTSYNC/BATTMAN on PF-GRIDANCHOR (attribute positions
  are absolute). Negative stations are not supported by the crossing
  content key.

## Open issues local to this file

- Per-crossing `pfa:find-anchor` full-DB scans (perf) —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md) "Shared / cross-cutting".
- Anchor block style wants a formatting pass —
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md).
- Unused exports (`pfa:status-get`, `pfa:twin-cksum`, four `pfa:xr-*`
  accessors) — [../Low_Priority_issues.md](../Low_Priority_issues.md) #10.
