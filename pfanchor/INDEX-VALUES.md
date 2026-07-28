# INDEX-VALUES.md — the value census

**Status:** analysis of the code as it stands. Nothing here is built.
**Date:** 2026-07-27.
**Companion to:** [INDEX-DESIGN.md](INDEX-DESIGN.md) — that file argues the
*shape*; this one settles *which values*, *from which tool*, *at which
moment*, and *on which surface they appear*.

Read §6 first if you are about to build: it corrects three things
INDEX-DESIGN.md asserts, and answers two of its open questions from the code.

---

## 1. Phase vocabulary

Every value below is stamped with the phase it is produced in. The phases are
already load-bearing in the code — they are the read/write seam the palette
contract rests on (`pf:cl-geom`'s `write-p`, `pfa:nod-dict`'s `create`).

| Phase | Where | Undo group | May write the DB |
|---|---|---|---|
| **REG** | `pfs:auto`, `pfs:place-one`, `pfs:edit-one` | open | **yes** |
| **GATHER** | `pflabel:run-dialog` / `pfi:run-dialog` / `*:setup`, and any palette handler | none | **no** |
| **ENGINE** | `pflabel:run`, `pfi:run`, `pfxl:run` | open | yes |
| **EXPORT** | `pfr:run` | none | no (the `.stm` is the only write) |

The index writer lives in **REG**. The index reader is consumed in **GATHER**
and **ENGINE**. Nothing in **EXPORT** may write, which is why PFREPORT is a
pure beneficiary.

---

## 2. What the index stores — the whole list

Two records, seven values. That is the entire storage surface.

### 2.1 Per structure — xdict `PFINDEX`, key `MEMB`

| # | Value | Shape | Produced by | Phase | Cost today |
|---|---|---|---|---|---|
| 1 | insertion point as indexed | `(x y)` | `(cdr (assoc 10 (entget e)))` | REG | free |
| 2 | line set | `((name . sta) ...)` | **`pf:lines-at-point`** | REG | **the whole cost** |

Value 2 **is** `pf:lines-at-point`'s return list, unchanged. Store it in the
order returned — that order is offset-ascending (`pf:lines-at-point`
[pftools-lib.lsp:580](../pftools-lib/pftools-lib.lsp#L580)) and re-sorting on
write would make the reader non-identical to the function it replaces. The
offset *value* itself is discarded by `pf:lines-at-point` before it returns and
no consumer wants it back; the ordering is the only surviving trace of it.

Value 1 exists solely for staleness (§5.1 of the design). It is not consumed by
any label path.

### 2.2 Per drawing — NOD `PFTOOLS`, key `INDEX_META`

| # | Value | Shape | Produced by | Phase | Why |
|---|---|---|---|---|---|
| 3 | schema version | int | constant | REG | tolerance-set change invalidates everything |
| 4 | line identity | `pf:cl-id` per line | `pf:cl-id` | REG | keys the row; catches a **re-bind** |
| 5 | line content checksum | `pf:checksum-file` per line | `pf:checksum-file` | REG | catches an **edited `.cl`** — *see finding F1* |
| 6 | line station range | `(lo hi)` per line | `car` of `pf:cl-geom` | REG | membership gate; redundant given 5, cheap to keep |
| 7 | twin shape signature | `(handle bbox nverts tol)` per line | `pfa:twin-get` + `pf:twin-verts` + `pf:verts-bbox` | REG | catches a **moved drawn centerline** — *see finding F2* |

Values 4–7 repeat once per registry line. Value 7 is the one INDEX-DESIGN.md
does not have, and without it the persistent index is strictly weaker than the
session memo it is meant to outlive (§6, F2).

The tolerances that decide membership — `*pf-offset-tol*` 0.15,
`*pf-corridor*` 0.2, `*pf-corridor-sampled*` 1.2, `*pf-range-eps*` 0.01
([pftools-cfg.lsp:16-18](../pftools-cfg/pftools-cfg.lsp#L16-L18)) — are not
stored per line. They are drawing-wide and belong in value 3: bump the schema
version when any of them moves. `pftools-cfg.lsp:25` already carries the
warning that changing them changes answers.

---

## 3. What the index does **not** store, and where each of those comes from

Everything a label draws that is *not* in §2. Each row names the tool, so the
build can check nothing was quietly folded in.

### 3.1 Derived per run from the stored line set

| Value | Derived by | Phase | Input it needs |
|---|---|---|---|
| junction? | `(cdr line-set)` non-nil | GATHER | value 2 alone |
| primary hit / station | `vl-member-if` on name | GATHER + ENGINE | value 2 alone |
| the other lines | `vl-remove primhit` | ENGINE | value 2 alone |
| alphabetical line order | `pf:sort-line-infos-alpha` → `acad_strlsort` | ENGINE | value 2 alone |
| per-line station index | `pflabel:index-stations` → `pf:idx-add` | GATHER | value 2 of **every** structure |
| rank on each line | `pf:rank-on-line` | ENGINE | the station index |
| combined ID | `pf:combine-id` | ENGINE | names + ranks |

**The rank index is the one derived value that is not structure-local.**
Ranking needs every station on the line, so the reader must still walk every
inlet — but `pflabel:gather-inlets` already enumerates them with one `ssget`,
so this is an xdict read per structure, not a reverse lookup. No per-line
record is needed for it.

### 3.2 Live drawing reads — never cacheable, correctly absent

| Value | Tool | Phase | Why it can't be stored |
|---|---|---|---|
| block name → rule | `(assoc 2 (entget e))` → `pf:rule-for` | ENGINE | free from the entity already in hand |
| nominal size | `pf:rule-size` → `pf:parse-size` | ENGINE | ditto, parsed from the block name |
| grid transform | `pfa:anchor->xform` (attribs + META + FILES) | GATHER + ENGINE | the anchor is the record |
| label X | `pf:station->profile-x` | ENGINE | station + xform |
| grid top at station | `pf:top-lines` + `pf:top-at` | ENGINE | grid tops **step**; live scan by design |
| `[LABELED]` status | `pflabel:pass-xs` + `pflabel:labeled-x-p` | GATHER | per-pass, changes on every run |
| drift / orphans | `pflabel:orphan-xs` | GATHER | describes the drawing, not the computation |

`pf:top-lines` is the *other* O(drawing) scan in a run — a full model-space
`ssget` of `PF-GRID-MJR` LINEs. It is not membership and is out of this index's
scope, but it is the next thing to measure once membership stops dominating.

### 3.3 Profile-side — the design's "Out" column, confirmed

| Value | Tool | Phase | Source of truth |
|---|---|---|---|
| invert elevations | `pf:pro-verts` → `pfi:invert-bracket` | ENGINE | `_INV.pro` |
| pipe size at a station | `pf:pipe-at` | ENGINE | `_INV` + `_TOP.pro` |
| lateral invert | `pfi:lateral-info` → `pfxl:src-files` | ENGINE | the lateral's own `.pro` |
| rim / ground elevation | `pfr:elev-texts` → `pfr:rim-at` | EXPORT | **the drafter's typed TEXT on the sheet** |
| crossing elevations | `pfa:xing-put-elevs` | ENGINE | already persisted in `X_*` |

The rim row is worth naming: it is not PFTools data at all. PFLABEL draws
`T.R. XXX.XX`, a human types the number, and PFREPORT reads it back out of the
TEXT entity. Nothing in the index touches it.

---

## 4. Where each value is displayed

The same fact surfaces in up to four places. This is the map the palette's
`detailsList` will be built against.

| Value | Command line | Modal dialog | Drawn on the sheet | Exported |
|---|---|---|---|---|
| structure block name | `"  Labeled <id>."` | list col 1, `pfset:pad 22` | — | — |
| **station on primary** | `pf:fmt-station` in skip/drift messages | list col 2 | label row 1, `"STA 4+12.55"` | `.stm` node station |
| **the other lines** | `"is on line(s) BA,BC"` on a skip | — | rows 2..n, `"= STA 0+00.00 (BC)"` | — |
| **combined ID** | `"  Labeled BA-3/BC-1."` | — | const row, `"CONST. DRAINAGE MH BA-3/BC-1"` | `.stm` **Inlet ID** |
| rank | — | — | inside the combined ID | inside the Inlet ID |
| `[LABELED]` | — | `"[LABELED]"` + `run_count` tile | — | — |
| drift / orphans | `"  DRIFT: n label(s)..."` | `error` tile | — | — |
| line count / tallies | — | `xl_tgt`, `pi_count` tiles | — | — |
| registry state | — | — | — | palette `lblCounts`, `metaList` |

The three drawn rows come out of `pf:build-label-rows`
([pftools-lib.lsp:932](../pftools-lib/pftools-lib.lsp#L932)): station rows
first (primary first, then alpha), then const / text2 / elev. The station rows
and the ID are the **only** places value 2 becomes visible ink, and PFREPORT's
Inlet ID is composed by `pfr:struct-id` from the identical inputs so the sheet
and the `.stm` agree by construction.

**Palette target:** `detailsList` needs `Structure | Station | Status`, which is
values 2 + the live pass check — exactly what `pflabel:gather-compute` already
returns as `(pend status orphans)`. That call is write-free today; with the
index it also stops being expensive, which is the whole point of doing this
before the Commands tab.

---

## 5. Call-site census — what the index actually removes

Nine live call sites of `pf:lines-at-point`, plus the three helpers that wrap
it. `M` = inlets in the drawing, `L` = registry lines of the same type,
`N` = structures labeled this run. One "product" = M×L membership tests, each
of which may cost a `cl_location_at_pt`.

| Command | Products per run | Where |
|---|---|---|
| **PFLABEL** All | **2 M×L + N×L** | gather *(memoised)*, `pflabel:index-stations`, `process-structure` ×N |
| **PFINVERT** All | **2 M×L + N×L** | gather *(memoised)*, `pfi:label-all`, `process-structure` ×N |
| **PFINVERT** Sel | 2 M×L + K×L | gather, `pfi:line-min-sta`, `process-structure` ×K |
| **PFREPORT** (P profiles) | **(1+P) M×L + nodes×L** | `index-stations` once, `pflabel:pending` per profile, `pfr:struct-id` per node |

> **Corrected 2026-07-27.** An earlier revision of this table charged PFINVERT
> All three products by counting `pfi:line-min-sta`. That function is only
> called from `pfi:label-sel`; All mode takes its first station from
> `(caar pending)` directly. The redundant product in All mode was
> `pfi:label-all`'s rebuild, and in Sel mode it was `line-min-sta` — one each,
> not both. Both are now gone (INDEX-PLAN step 1).

Only the first row of each is memoised (`*pfl-gather-memo*`), and the memo is
session-scoped — it does nothing for the first run on a freshly opened drawing,
which is the case the user actually experiences as slow.

`pflabel:index-stations` is the largest *unmemoised* single item and it runs on
every PFLABEL and every PFREPORT.

---

## 6. Findings — corrections and answers

### F1. `pf:cl-id` is **not** content-addressed. INDEX-DESIGN §4 is wrong.

> "`cl-id` is `pf:cl-id` — already content-addressed, already used by the GEOM
> store."

`pf:cl-id` ([pftools-lib.lsp:740](../pftools-lib/pftools-lib.lsp#L740)) is pure
string work: slashes normalised, upcased. It is a canonical **path**, and its
own comment says so ("no disk resolution"). It cannot detect an edited `.cl`.

What the GEOM store actually does is key on the path (`GEOM_<cl-id>`) and carry
the **content checksum separately** in group 300, written from
`pf:checksum-file`; `pf:cl-geom` compares that checksum, not the key
([pftools-lib.lsp:436-438](../pftools-lib/pftools-lib.lsp#L436-L438)). The TWIN
store does the same thing with `pfa:twin-cksum`.

**Consequence:** `INDEX_META` needs **both** — value 4 (identity, so a re-bind
to a different `.cl` is visible) and value 5 (checksum, so an edit is visible).
Storing only `cl-id`, as the design says, detects re-binding and nothing else,
and every stale record after a `.cl` edit reads clean. `pf:checksum-file` is
already memoised on `(path, mtime, size)`, so asking for it per line per read
is an O(1) stat probe, not 47 file walks.

### F2. Twin drift is missing from the staleness table.

Membership is decided by `cl_location_at_pt` against the authored `.cl`, but it
is **gated** by a corridor pre-filter built from the *drawn* centerline's live
vertices (`pflabel:build-lines` → `pf:twin-verts`
[pflabel.lsp:133-141](../pflabel/pflabel.lsp#L133-L141)). Move the drawn
polyline and structures fall outside the corridor: they are rejected before the
authored test ever runs. The pre-filter can only produce false **negatives**,
but a false negative is still a wrong membership answer.

The session memo already knows this — `pflabel:lines-sig` keys on bbox, vertex
count and corridor tol precisely to catch a moved twin
([pflabel.lsp:362-368](../pflabel/pflabel.lsp#L362-L368)). INDEX-DESIGN §5's
three events do not include it.

**Consequence:** value 7. Without it the persistent index can serve an answer
the session memo would have refused — a regression dressed as an optimisation.

Note the design's own §7 already lists `pfa:twin-get` as a dependency of the
writer; this just makes it a dependency of the *validator* too.

### F3. `pfi:label-all` ignores its ticket — the PFLABEL fix was never applied.

`pflabel:label-all` reads `(cdr (assoc 'sel context))` and rebuilds only when a
caller hands it a ticket with no `'sel`; its comment
([pflabel.lsp:719-726](../pflabel/pflabel.lsp#L719-L726)) explains that
recomputing was "a second full inlet × line membership scan."

`pfi:label-all` ([pfinvert.lsp:375-391](../pfinvert/pfinvert.lsp#L375-L391))
rebuilds unconditionally and never reads `'sel` — the same bug, in the twin
function, uncorrected. This is the same divergence class as the registry-builder
and same-type-membership bugs already in OPEN-ISSUES.

**This is independently fixable today, before any index work**, and it removes
one whole M×L product from every PFINVERT All run. `pfi:line-min-sta` is a
second, and it only wants the minimum of the stations `pending` already holds.

### F4. §8.1 answered — crossings **are** done. Do not give them a home.

The `X_*` store is as mature as §8.1 hoped:

- `pfa:xing-merge` — content key `X_<SBASE>_<sta×100>`, additive, with
  `*pfa-key-tol*` **key-drift renaming** (a crossing that moves a little is
  renamed, not duplicated) and `'NEW`/`'UPDATED`/`'MOVED` status
  ([pfanchor.lsp:917](pfanchor.lsp#L917)).
- `pfa:xing-put-elevs` — nil preserves the stored elevation.
- `pfa:xing-list` — sorted read, `create nil`, palette-legal.
- `pfa:recon` — labeled/outstanding against the drawing.
- `SCOPE` — per-source `<base>|<target-cksum>|<source-cksum>` triples give
  `pfxl:discover` a **checksum short-circuit** that already skips unchanged
  pairs ([pfxlabel.lsp:118-125](../pfxlabel/pfxlabel.lsp#L118-L125)).

Crossings persist *more* than this index proposes to. Build order step 1 is
closed: **the work is "add a structure store beside the crossing store," as
§8.1 hoped.**

### F5. §8.2 is not a shape decision — water has no structures at all yet.

The design asks whether water membership forces a per-line record. It does not,
because there is nothing to record.

`pflabel:gather-inlets` selects model-space INSERTs matching `*pf-rule-table*`
([pflabel.lsp:197-206](../pflabel/pflabel.lsp#L197-L206)), and the rule table
holds `CBI`/`DBI`/`SMH`/`DMH`/`MH`/`HDWL`
([pftools-cfg.lsp:76-85](../pftools-cfg/pftools-cfg.lsp#L76-L85)) — no water
fittings. `WATER` is a registered *type* with materials, layers and crossing
templates, and water lines get crossings labeled against other profiles, but no
code anywhere discovers a water structure. `pflabel:registry-pairs` filters to
same-type, so a WATER primary gathers WATER lines and an empty inlet set.

**Consequence:** the index is **one-shaped**, not two. Build the per-structure
xdict store for block-backed structures — the only kind that exists. Water
structure *discovery* is an unbuilt feature; when it is built it will choose its
own storage, and the GEOM densification trap the design records (Water_H = 418
points from 11 real PIs, so the true PI set is not recoverable from GEOM) is a
note for **that** feature, not a constraint on this one.

---

## 7. The remaining open question

**§8.3, the write trigger.** The value census makes the case for top-up.

Every consumer already runs `pf:lines-at-point` on a miss and throws the answer
away. The index does not decide *whether* the work happens, only whether it is
kept. Explicit-only means the everyday path keeps paying full price until
someone remembers to run `PFINDEX`, and the palette — the whole reason for
this — is the surface *least* able to trigger a rebuild, because it may not
write.

The mechanics are already safe: PFLABEL, PFINVERT and PFXLABEL all hold an open
undo group at write-pass, and `pfa:xrec-put`/`dictadd` are the same calls the
Esc flush already makes inside `*error*`. GATHER must still never write — that
is the `create nil` contract — so a top-up belongs in the **ENGINE**, beside
`pflabel:write-pass`, not in the gather that discovered the miss.

**Recommendation: top up in the engine, explicit `PFINDEX` for a cold rebuild.**
Not either/or — the rebuild command is still wanted for the missing-GEOM
re-file path the design names in build step 8.

---

## 8. Revised build order

Steps 1 and 2 of INDEX-DESIGN §10 are answered above; the rest re-sequences
around what the census found.

1. ~~Verify §8.1~~ — **done, F4.** Crossings need nothing.
2. ~~Decide §8.2~~ — **done, F5.** One shape.
3. **F3 first, standalone.** Fix `pfi:label-all` to read its ticket and
   `pfi:line-min-sta` to fold over `pending`. Two M×L products gone from every
   PFINVERT run, no new storage, independently testable.
4. Move `pflabel:build-lines` / `pflabel:gather-inlets` to pfanchor (design §7).
5. Write the store: `pfa:memb-put` **W** / `pfa:memb-get` /
   `pfa:index-meta-put` **W** / `pfa:index-meta-get` — values 1–7, **including
   value 5 (checksum, F1) and value 7 (twin signature, F2)**.
6. Call the writer from `pfs:auto` and `pfs:place-one`, beside the existing
   `pf:cl-geom … T` and `pfa:twin-put` calls that already sit there.
7. Point `pflabel:gather-compute` at the reader, behind the session memo.
8. Point `pflabel:index-stations` at it — the largest unmemoised consumer.
9. Engine top-up (§7) + `PFINDEX` rebuild command.
