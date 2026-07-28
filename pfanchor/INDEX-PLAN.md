# INDEX-PLAN.md — the build plan

**Status:** BUILT 2026-07-27, steps 1–9. Static gates pass. **No CAD gate has
been run** — see §"What still needs Jake" at the bottom.
**Date:** 2026-07-27.
**Replaces:** [INDEX-DESIGN.md](INDEX-DESIGN.md) §4, §5, §8, §10 and
[INDEX-VALUES.md](INDEX-VALUES.md) §2, §6, §7. Both are kept as history — the
reasoning still holds, the record shape changed.

---

## Why

Right now the tools work out which structures sit on which lines every single
time. PFLABEL does it. PFINVERT does it again. PFREPORT does it again. Nothing
keeps the answer.

The answer barely changes. A structure gets placed and stays put.

So: work it out once, save it in the drawing, and read it after that.

---

## What gets saved

**On each structure block** — key `MEMB`:

```lisp
(10 x y 0.0)                    ; where it was when we saved it
(302 . "<roster stamp>")        ; what the lines looked like at the time
(300 . "BA") (40 . 412.55)      ; the lines it sits on, and the station on each
(300 . "BC") (40 . 0.00)
```

**Once per drawing** — key `INDEX_META`:

```lisp
(70 . schema)
(300 . "BA") (301 . "<line stamp>")     ; one row per registered line
```

A **line stamp** is one short string built from four things about a line: the
`.cl` file's checksum, the station range, the corridor width, and a hash of the
drawn centerline's points. If any of those move, the stamp moves.

A **roster stamp** is one string covering *every* registered line's stamp. That
is what lets a record say "I was worked out when the lines looked like this."
If it still matches, the record is complete and current — the lines it names
are right, and the ones it doesn't name are right to leave out.

---

## Three rules that don't bend

1. **Reading never writes.** The palette reads. It must never dirty a clean
   drawing.
2. **Only commands write**, and only inside their undo group. One `U` still
   undoes a run.
3. **If a record can't be trusted, throw it away and do the math.** Never guess.

---

## The steps

### 0. Take a timing baseline
Time PFLABEL All on a real drawing — first run and second run. Write the
numbers down.

Without this you can't tell if steps 5–7 were worth doing.

*The output regression check is already done — tested 2026-07-27.*

- **Size:** tiny
- **Done when:** two numbers on paper.

### 1. Fix PFINVERT doing the same work twice
`pfi:label-all` is handed a list of structures and builds it again anyway.
`pfi:line-min-sta` walks every structure a third time just to find the smallest
station — a number the list already holds.

PFLABEL was fixed for this; PFINVERT never was.

- **Why first:** no new storage, no risk, faster today.
- **Size:** small
- **Done when:** PFINVERT All draws the same labels, quicker.

### 2. Close the two quiet faults
Both give a wrong answer with no warning. Fix them before anything leans on
them.

- The drawn centerline's fingerprint is its bounding box and vertex count. Move
  a middle point and both stay the same. Use a real hash of the points.
- The file-changed check uses date and size only. That is fine for a quick
  look, but not when we are about to *save* the answer. Do the full read on the
  save path.

- **Size:** small
- **Done when:** nudge one middle vertex of a drawn centerline — the tool
  notices.

### 3. Rename the ledger
`PFXLEDGER` holds six kinds of record. Four have nothing to do with crossings.
Structures are about to use the same store, so fix the name before there are
two owners.

Read both names. Move an old drawing to the new name the first time something
writes to it.

- **Size:** small, but it is the only step that touches drawings you already
  have.
- **Risk:** get it wrong and an old drawing loses its pass handles, so PFREMOVE
  finds nothing to erase. Test on a real old drawing.
- **Optional.** The index works fine under the old name. It just gets more
  expensive to change later.
- **Done when:** an old drawing still labels, still removes, still reports.

### 4. Move two functions into pfanchor
`build-lines` and `gather-inlets` are registry helpers sitting in pflabel. The
index writer needs them, and it loads before pflabel, so it can't reach them.

- **Size:** small, mechanical
- **Done when:** all three commands still run.

### 5. Build the store — with an off switch
Four things: write a record, read a record, build the stamps, and one global
flag.

**The flag matters.** When it is off, the reader always says "no record," and
everything falls back to how it works today. If the index goes wrong in the
field you turn it off, not patch it.

Nothing calls any of this yet.

- **Size:** medium
- **Done when:** write a record by hand, read it back, get the same thing. Flip
  the flag off and the reader goes quiet.

### 6. Write records at registration
When PFSETUP names or places a line, it checks every structure against **that
line** and saves what it finds.

This is also what stops a newly added line from making every old record stale —
registration has already accounted for it.

**Be honest about the cost.** Placing one line is cheap. `pfs:auto` registers
every line on the sheet at once, so it pays the full bill. That's the right
place for it — it is the one moment the user expects to wait.

- **Size:** medium
- **Done when:** register a line, the records are there.

### 7. Start reading
Point the gather at the store first. Then the ranking pass, which is the
biggest single user.

A structure with no record just gets worked out the old way. That is normal, not
a fault — a newly drawn inlet has no record until something labels it.

- **Size:** medium
- **Done when:** same labels as before. Second run on a drawing is much faster.
  First run on a cold drawing is unchanged.

### 8. Split STATUS into four
See the next section. This is where the "how many profiles are done" number
comes from.

- **Size:** medium
- **Done when:** running PFLABEL no longer wipes PFINVERT's verdict.

### 9. Top up, rebuild, verify, report
- **Top up:** labeling refreshes the records it touched, inside its own undo
  group. Wrap it so a locked layer just means "no saved record for that one,"
  not a dead command.
- **`PFINDEX`:** builds from cold, rebuilds on demand.
- **`PFINDEX VERIFY`:** for every structure, read the record *and* do the math
  the old way, then report where they disagree. Slow. Run it once. This is the
  only thing that actually proves the index is right, and it turns every quiet
  fault into something you can see.
- **The report:**

```
PFINDEX  STORM: 214 structures — 190 current, 18 stale, 6 skipped (locked layer)
         roster r3  ·  BA .cl changed since indexing
```

- **Size:** medium
- **Done when:** VERIFY finds nothing on a clean drawing, and finds the fault
  when you plant one.

---

## STATUS, split four ways

Today three commands write one record about three different files. The last one
to run erases the others. Split it.

| Key | Covers | Checks |
|---|---|---|
| `STATUS_LABEL` | PFLABEL | the `.cl` |
| `STATUS_INVERT` | PFINVERT | the `_INV .pro` |
| `STATUS_XING` | PFXLABEL | target + source `.cl` — **points at SCOPE, does not copy it** |
| *(overall)* | the profile | worked out on the fly, never saved |

`STATUS_<PASS>` matches the `PASS_<name>` keys already there, so each command
writes only its own.

**PFXLABEL writes no status at all today.** That one is new work, not a rename.

### Save the baseline, count live

Each value splits in two.

**Save** — the input file's checksum at the moment of the pass, and the time.
You cannot work out later what a file *was* when you labeled it. That is real
state, and it is what makes "stale" answerable.

```lisp
(70  . state)          ; 0 never ran, 1 ok, 2 can't read the file, 3 changed since the pass
(1   . timestamp)
(301 . "<checksum at pass time>")
(300 . "finding")      ; zero or more
```

State 3 finally gets a writer. "The file changed since you labeled" is a
different thing from "I couldn't read the file at all."

**Count live** — done out of total. Do **not** save these. A saved "12 of 12"
stays 12 of 12 after someone erases a label. The code already says so, at
[pflabel.lsp:423-429](../pflabel/pflabel.lsp#L423-L429):

> STATUS means "correct as of the last pass" and drift accumulates BETWEEN
> passes, so a stored flag would always read clean one command after it stopped
> being true.

The numbers are already there, from pure reads: `pflabel:gather-compute`
returns a labeled/not flag per structure for both PFLABEL and PFINVERT, and
`pfa:xing-list` + `pfa:recon` do the same for crossings at almost no cost.

**The index is what makes counting live affordable.** Counting across every
profile means a gather per profile — the exact cost the index removes.

### Keep the two apart

State is about the **input files**. Done-out-of-total is a **separate pair**.
Mixing them makes both hard to read.

### The overall value

Worked out at read time, per profile, from:
- the three saved states
- the three live done/total pairs
- whether any structure on this line has a stale record

That gives the per-line dot on the palette. Counting the dots gives the thing
you asked for: *"5 of 7 profiles fully labeled, 2 with a changed `.cl`."*

### Editing follows the file
`pfs:edit-one` blanks STATUS today. With four records that is wrong — rebinding
the `_INV .pro` should not clear PFLABEL's verdict, which is about the `.cl`.
Reset only the record whose file changed.

---

## Known limits, stated up front

- **Any `.cl` edit makes every record stale.** Coarse, but geometry doesn't
  change often and a rebuild is one command.
- **Structures on a locked layer never get saved.** Always right, always slow.
  The report says which ones.
- **A structure copied in place** keeps the original's answer. That answer is
  right for that spot, so no harm.
- **PFREPORT never refreshes anything** — it is read-only by design. It only
  benefits.

---

## What we are not doing

- Inverts, pipe sizes, cover, clearance, wall thickness. Those come from `.pro`
  files that change all week. Work them out fresh, every time.
- Rim elevations. Those are typed by a person onto the sheet.
- Crossings. They already have their own store and it already works — additive
  merge, key drift renaming, kept elevations, and a checksum short-circuit.
  Leave it alone.
- Water structures. Nothing anywhere finds one today; there are no water
  fittings in the rule table. When that feature gets built it picks its own
  storage.

---

## Order at a glance

```
0.  Timing baseline                                  tiny
1.  Fix PFINVERT's double work                       small   ← pays off alone
2.  Close the two quiet faults                       small   ← do not skip
3.  Rename the ledger                                small   ← optional, touches old drawings
4.  Move the two functions                           small
5.  Build the store + the off switch                 medium
6.  Write records at registration                    medium
7.  Start reading                                    medium
8.  Split STATUS into four                           medium
9.  Top up, rebuild, verify, report                  medium
```

Steps 1–4 are worth doing even if the index never gets built.
Steps 5–7 are where the speed comes from, and they are what the palette needs.
Step 9 is what lets you trust any of it.

---

## What was built, and where it differs from the plan

Steps 1–9 landed 2026-07-27. Three deliberate departures:

**1. Registration does not index (step 6 changed).** The plan had PFSETUP
walking the structures when a line is registered, so an added line never
staled anything. It does not, and the reason is the roster stamp: adding a line
moves the roster, which stales every record anyway, so an incremental merge at
registration would have to be trusted against the *old* roster and re-stamped
against the new one. That is the one piece of this design that can be subtly
wrong, and it buys a rebuild that `C:PFINDEX Build` already does correctly.
Placing a line is also an interactive moment where a full walk would be a bad
surprise.

**What that costs:** after registering a line, every record reads stale until
`PFINDEX Build`. The engine top-up still heals whatever gets labeled. This is
slower, not wrong — the roster stamp catches the added line either way, which
was the actual correctness requirement.

**2. `pfa:checksum-file!` became `pf:checksum-strict`.** The `!` made the symbol
invisible to `pf-verify`'s undefined-call and dead-code gates — it read as dead
while having three live callers. A symbol the static gates cannot see is a
symbol whose typos go uncaught, which is worse than an ugly name.

**3. The roll-up got a home immediately.** `pfa:status-roll` would have been
dead code, so it is wired into the palette's info panel as a "Checks" row
(`pfp:status-cell`). Pure read, modeless-legal.

## What still needs Jake

Static gates pass (parens, dupes, undefined, load order, API drift). **Nothing
here has touched AutoCAD.** In rough order of what would hurt most if wrong:

1. **`dictrename` on an xdict entry (step 3).** The legacy-ledger heal is the
   one call in this change with no precedent anywhere in the suite. If it
   fails, an old drawing's ledger stays readable under the old name — the
   fallback branch still finds it — but it never migrates. Test on a real
   pre-2026-07-27 drawing: PFLABEL, then PFREMOVE, and confirm the pass
   handles still resolve.
2. **`C:PFINDEX Verify` on a real job.** This is the acceptance test for the
   whole feature. Empty output is the evidence; anything else means stop.
3. **Timing baseline (step 0).** Never taken — take it before Build so the
   second-run number means something.
4. **The write-free contract.** `PFPDBMOD` delta across a palette session must
   still be zero. `pfa:lines-at` and `pfp:status-cell` are new on read paths
   the palette touches; both use `create` nil, but that is the claim, not the
   proof.
5. **Esc mid-run**, both directions, per TESTING §8.9 — the top-up now writes
   inside the same group the flush uses.
6. **A locked-layer structure.** Should go uncached and report under
   `PFINDEX Report`, never kill the run.
