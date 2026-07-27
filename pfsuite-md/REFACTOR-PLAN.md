# V5 — Engine-extraction plan (Tab 2 prerequisite)

> **Status 2026-07-25 — Step 1 (engine extraction) DONE in this folder.**
> `Profile-Labeling-5-Palette` is a self-contained fork of `..\..\V5`; the loader
> points at this folder. Engines extracted: `pflabel:run (anchor rd)`,
> `pfi:run (anchor rd)`, `pfxl:run (anchor xf sel)`. Each `C:PF*` now gathers,
> then hands off to its engine; bodies moved verbatim, so command-line behavior
> is preserved **by construction** — paren-balanced, but **not yet run in CAD.**
> NOT done: the deferred-fire `C:PF*RUN` commands, the PFXLABEL discover/recon
> move + confirm→checkbox, and all Tab 2 wiring. Next gate: run all three from
> the command line in CAD and confirm identical output before any palette work.


Decided 2026-07-25. This is surgery on the three label commands so the palette's
Commands tab (README §2) can drive them without the modal run dialogs. It
operates **entirely in the V5 files**; V4 one level up is the frozen original and
is never touched.

## The idea in one line

Each command splits into three parts — **gather-compute** (reads → the item list
and its status), **gather-UI** (the modal dialog), and **engine** (the part that
draws on the sheet). The modal and the palette both use gather-compute + engine;
only the UI differs. Pull the engine out and give it a second ignition.

Why not a rewrite: the engines carry field-won fixes (I.I/I.O order, exact-vertex
bracket, same-type scoping, station-domain guards) that are still tagged
"FIXED (untested in CAD)" in `OPEN-ISSUES.md`. A rewrite throws them away and
re-earns the bugs. And a rewrite wouldn't help anyway — a modeless palette isn't
allowed to draw on the sheet regardless of how new the code is (OpenDCL rule), so
the deferred fire stays either way. We keep the engines; we only unweld them.

## Where each command already stands

The earlier "ghost dropdown" fix already split compute from UI in two of the
three, so this is less than it looks:

| Command | gather-compute | engine | Verdict |
|---|---|---|---|
| **PFLABEL** | `pflabel:rd-compute` (pflabel.lsp:290) + `pflabel:setup` (:405) — already separate | `pflabel:label-all` (:571) / `label-sel` (:564) / `write-pass` (:591) — named, but inlined in `C:PFLABEL` (:631) | Clean lift-out |
| **PFINVERT** | `pfi:rd-compute` (pfinvert.lsp:489) — already separate | parallel to pflabel; inlined in `C:PFINVERT` (:590) | Clean lift-out |
| **PFXLABEL** | **none** — `pfxl:discover` (pfxlabel.lsp:120) + `pfa:recon` + `pfxl:run-dialog` (:278) + a mid-run `pfset:confirm` are all interleaved in `C:PFXLABEL` (:365) | label loop inline | **Structural — the hard one** |

## The order ticket

Both label commands already funnel everything through one alist the gather
produces and the engine consumes:

```
rd = ( (mode . "All"|"Sel") (sel . <items>) (lines . <…>) (inlets . <…>) )
```

`C:PFLABEL` builds it from `pfs:choose-or-place` (target) + `pflabel:run-dialog`
(items); `C:PFINVERT` the same via `pfi:run-dialog`. That alist **is** the seam:
the modal produces it today, the palette produces the identical alist tomorrow.
PFXLABEL's equivalent is the `act` value out of `pfxl:run-dialog`
(`(cons 'all …)` / `('sel . list)` / `'target`) plus `work` + `recon`.

## The refactor, per command

### Step 1 — extract the engine (all three)

Pull the post-gather body of each `C:PF*` into `pfX:run (anchor rd)`:

- the `_.UNDO Begin` / `End` group,
- the All-mode erase-previous-pass,
- the label pass (`label-all` / `label-sel`, or the crossing loop),
- `write-pass` / the ledger append + status write.

`C:PFLABEL` / `C:PFINVERT` / `C:PFXLABEL` then reduce to: run gather-UI → get
`rd` → call `pfX:run`. **Behavioral bar: the command-line command must produce
byte-identical output after the extraction.** That is the regression gate before
any palette wiring.

### Step 2 — the palette path

Tab 2 assembles the same order ticket without a modal:

1. **Target** = the Tab 2 tree selection (a registry row → anchor). It is *not* an
   `entsel` pick, so `pfs:choose-or-place` / `pfxl:resolve-target` are simply not
   called on this path.
2. **gather-compute runs in the handler** — pure reads, modeless-legal — to fill
   the item list *and the Status column*.
3. User multi-selects items + ticks option checkboxes → assemble the same `rd`.
4. Set globals, **deferred-fire** a thin `C:PF*RUN` that reads the globals and
   calls `pfX:run` inside a real command context (where sheet writes are legal).

### PFXLABEL's extra work (why it is the hard one)

- `pfxl:discover` + `pfa:recon` move into a gather-compute function. They are
  reads; `recon` is literally the Status source.
- The mid-run `pfset:confirm` ("label already-labeled crossings? draws
  duplicates") **cannot survive** — you can't raise a modal in the middle of a
  deferred palette engine. It becomes a **pre-declared checkbox** on Tab 2
  ("allow relabeling"), read as an option *before* the engine starts. That is one
  of the Crossings checkboxes, found for free.

## Free win: the Status column already exists

Every gather-compute already computes labeled/outstanding — pflabel's `[LABELED]`
mark, pfinvert's `id-status`, pfxlabel's `recon`. That **is** Tab 2's Status
column: no new source to build, and all reads, so modeless-safe.

## The deferred fire

A modeless OpenDCL handler cannot call `command`, so both our verbs and the
native-Carlson buttons queue the real command into a command context. One shared
mechanism (a thin `C:PF*RUN` per command reading preset globals, or one
dispatcher). This is the single piece that can't be reasoned out from the
shipped samples — it gets its own tiny CAD proof first.

## Ordering (the part that keeps this safe)

1. **Validate the V5 fork in CAD.** The engines carry fixes untested in CAD.
   Confirm all three commands run correctly from the command line *before*
   unbolting anything.
2. **Prove the deferred fire** in isolation.
3. **PFLABEL first** — cleanest; proves the whole pattern end to end.
4. **PFINVERT** — mechanical repeat of the PFLABEL extraction.
5. **PFXLABEL last** — the structural one: the discover/recon move and the
   confirm→checkbox conversion.

After each engine extraction, run that command **from the command line** and
confirm identical output before wiring its palette path. The modal stays a
working front-end the whole time — nothing is deleted until the palette provably
replaces it.

## Not in scope here

Option-checkbox contents and the native-Carlson command list are still TBD
(Jake); neither blocks this refactor or the Tab 2 layout.
