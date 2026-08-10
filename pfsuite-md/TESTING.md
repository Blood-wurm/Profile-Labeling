# PFTools V5 — Shakedown Checklist

Run on a **scratch copy** of a real job. Goal: break it. Every test names its
expected result — anything else is a finding. Work top to bottom; later
phases depend on earlier state.

**Bring:** a sheet with ≥2 profile grids (one with stepped tops), a drop
manhole with a known I.I/I.O, a junction structure on ≥2 lines, at least one
real crossing, the project folder (`Type_Name.cl` + `_INV`/`_TOP.pro` pairs,
`.tin` files), `PF-PIPE_<NN>` blocks, and the `L080` style.
**For §9 also bring a drawing registered before 2026-07-27** — that is the
only way to test the ledger rename against a real legacy record.

**Known-open issues to probe deliberately** (expected findings, not
surprises). Everything else lives in `OPEN-ISSUES.md`; this list is only what
you should expect to *see* during a shakedown:

- **Structures silently dropped near deflection PIs (wrong-output, CRITICAL,
  OPEN).** `cl_location_at_pt` returns nil where there is no perpendicular
  foot. Unblocked but not fixed — `pf:cl-parse` removed the blocker, not the
  bug. Membership still gates on `cl_location_at_pt`. Probe in §3 and §9.
- **Backtick names (UNFIXED):** `pf:parse-sheet-name` closes only on a
  straight `'` — a PF-NAME like ``STORM LINE `DA` `` silently skips in AUTO.
- **MR justification:** confirmed "grows down" by recollection — **verify
  visually** in 6.6; it decides the invert stack's direction.
- **Dialog layer.** Both label commands are **pick-first**:
  `pfs:choose-or-place` resolves the target (a `pf_pick` list) *before* the
  run dialog opens — there is **no target popup**, and the dialog lists a
  single target's structures. Expect DCL layout findings (tile widths, list
  column drift under the proportional font) on top of logic findings.

**Closed since the last shakedown — do not re-litigate, just confirm in
passing:** the PFINVERT I.I/I.O bracket bug (exact-vertex bracket, no grade
tolerance, `pfi:break-scan` gone), cross-utility contamination (membership is
same-type via `pflabel:registry-pairs`), `CMDECHO` suppression (now
`pf:run-command`'s job), and the PVI probe (the Road API has no vertex
accessor; `pf:pro-verts` parses the file).

---

## 0. Load

- [x] 0.1 `(load ".../V5/pftools-load.lsp")` → banner lists **PFSETUP,
      PFLABEL (PFL), PFXLABEL (PFX), PFINVERT (PFI), PFLABELSET, PFREMOVE,
      PFINDEX, PFREPORT, PFPALETTE** (PFROOT is retired — project root is
      native `tmpdir$`). No load errors.
- [x] 0.2 `*pftools-dir*` inside `pftools-load.lsp` points at THIS V5
      folder (it ships hardcoded — fix the path first or nothing loads).
- [x] 0.3 Each command name autocompletes / runs from the command line.
- [x] 0.4 **Dialog smoke:** every dialog OPENS (a DCL syntax error kills
      the whole file — `pfsetup_registry`, `pfsetup_main`, `pf_run`,
      `pfi_run`, `pfxl_run`, `pf_confirm`, `pf_pick`, `pflabel_settings`).
      Help buttons show their text; Esc/Cancel closes clean everywhere.

## 1. Project root + AUTO registration (PFSETUP first run)

- [x] 1.1 **Native root (tmpdir$) — CHANGED 2026-07-21, re-verify.** With an
      active Carlson project: `PFSETUP` uses the project folder with NO browse
      — reports `Project data folder: <dir>  (Carlson project)`. **Empirical
      check that gates the whole rewrite:** confirm `get-company-dir`'s
      search-up actually lands on the firm subfolders — AUTO finds the
      `.cl` under `…\Alignments` and the `_INV/_TOP.pro` under `…\CivilSurvey`.
      If it can't, note what `tmpdir$` returned and where the files really sit
      (the `*pfset-std-subfolders*` map or `*pfset-std-search-depth*` may need
      retargeting). With NO active project: falls back to a one-shot browse
      (reports `(session)`), good for the session only — does NOT survive
      save/reopen (no persistent root by design).
- [x] 1.2 AUTO names every PF-NAME profile: each gets `Named <TY> '<NM>'`
      with its `.cl` + INV/TOP note. Count matches the sheet.
- [x] 1.3 **Skip cases report loudly, never guess:** a PF-NAME with no
      matching `.cl` → SKIPPED; two `.cl` files matching one name → SKIPPED
      (ambiguous); a `.cl` with no sheet name → NOTE.
- [ ] 1.4 **Backtick attack:** make one PF-NAME use backticks. Expected
      (bug): silently absent from the register list — confirm, then decide
      if the fix is worth it.
- [x] 1.5 The **Refresh button** re-scans: idempotent — nothing re-named,
      no duplicates.
- [x] 1.5a **Late .pro binding:** register a line whose `_INV`/`_TOP` .pro
      does not exist yet (AUTO reports `-- no .pro pair`). Place one such
      grid, leave another as a stub. Drop both .pro files into the profile
      folder, hit **Refresh**. Expected: `Bound <TY> '<NM>' (anchored) + INV
      <file> + TOP <file>` and the same for `(registered)`, the tail count
      reads `N late .pro binding(s) added`, both show bound in the registry.
      Refresh again → 0 bindings added (idempotent).
- [x] 1.5b **Refresh never overwrites:** on an anchored grid, use Edit to bind
      an `_INV` .pro whose name does NOT match the convention. Refresh.
      Expected: that binding is untouched, no report line for it; only the
      empty `_TOP` slot fills. Confirm the TIN pair and material survive.
- [x] 1.6 **Registry manager behaves:** list shows every profile with
      [ANCHORED]/[registered]; Anchor on an anchored row / Edit on a stub / no
      selection → errtile message, dialog stays open; double-click anchors
      a stub and edits an anchor; empty registry greys Anchor/Anchor
      All/Edit.

## 2. PFSETUP placement

- [ ] 2.0 **Native scale seed (NEW 2026-07-21, verify):** on a NEW placement
      the H/V fields prefill from Carlson `sv:sm`/`sv:vs` — confirm they match
      the profile grid's actual H/V scale (if not, note what they returned;
      they may be the plan scale, not the grid's). Fields stay editable; on
      Edit the stored value prefills, not the native read. Also confirm the
      settings file lands under `usrdir$\PFTools` (native), not LOCALAPPDATA.
- [x] 2.1 Dialog validation rejects: empty name; zero/negative scales;
      empty datum; ONE `.pro` bound (pair rule); `.pro` whose name ≠ the
      Name field; one `.tin` bound. Each shows the errtile message, no
      crash. **Slot role guards:** picking a `_TOP.pro` on the Invert
      button, or a DESIGN_* tin on the Exist button → refused at pick
      time with an errtile message (wrong-role files can no longer reach
      OK).
- [x] 2.2 Material popup follows the Type popup; last-used material per
      type sticks across placements in the session.
- [x] 2.3 Extents picks: **running osnaps on** — pick the corners and check
      the anchor landed where you meant (known weakness; note how bad it
      is). Top-right left/below lower-left → refused.
- [x] 2.4 Datum field: prefilled with the session-last value on the second
      grid; edit prefills the stored datum.
- [x] 2.5 Anchored profile: block visible on `PF-ANCHOR` (no-plot), attributes
      LINE/UTIL/STA0/DATUM/HPLOT/VPLOT populated and plausible.
- [x] 2.6 **One `U` removes exactly one grid's placement** (not the batch,
      not the AUTO stubs).
- [ ] 2.7 Edit mode: `.pro` swap accepted (cheap); the **re-pick extents
      toggle** re-picks (and is greyed on a fresh placement); same-range
      `.cl` swap accepted; **different-range `.cl` REFUSED**; **identity
      change REFUSED**. Ledger survives an accepted edit (place a label
      first, edit, confirm the pass record remains).

## 3. PFLABEL

- [x] 3.0 **Pick-first + run dialog:** target is chosen by the `pf_pick` list
      BEFORE the dialog opens (no target popup); the structure list then
      matches the plan (every structure on the primary line, sorted by
      station); Label Selected with nothing selected → errtile; Settings...
      opens PFLABELSET nested and changes apply to the same run; picking an
      unanchored profile anchors it first (two corner picks) then lists it.
      **Ghost-dropdown check:** the list paints cleanly on open (the
      compute-before-`new_dialog` fix) — no flicker/glitch.
- [x] 3.1 Select the junction structure in the list → station rows primary
      first then alphabetical; combined ID alphabetical (`AA-1/BB-2`); const
      row from the rule table (SMH/DMH before MH — label one of each);
      elevation row placeholder; HDWL drops the elevation row.
      **Type scoping:** on a sheet with mixed types near the same station,
      the label must NOT pull in a different-type line's structure/block —
      membership is scoped to the primary's type. A same-type junction (two
      STORM lines) MUST still get the combined ID; a SANITARY line the STORM
      merely crosses MUST NOT appear. **Re-run this after §9.5** — it is the
      test most likely to expose a bad saved record, because a wrong line set
      shows up directly in the combined ID.
- [x] 3.2 **Stub contribution:** with a secondary line unanchored (stub
      only), the junction ID still includes it.
- [x] 3.3 Stepped-top grid: labels sit on the top **at each station**, not
      the nominal top. A station past the grid edge (no MJR hit) skips with
      a report.
- [x] 3.4 Label All: count matches structures on the line; sorted by
      station.
- [x] 3.5 All re-run: prior pass replaced **by handle** (count reported);
      hand-drawn text on the same layer untouched. List rows flip
      [LABELED] on the next run's dialog (X-proximity to tracked pass
      entities — advisory; verify it doesn't false-mark two structures at
      near-identical stations).
- [ ] 3.6 CLAYER toggle: draws on current layer; re-run All does NOT erase
      it; pass recorded (run PFXLABEL later and confirm nothing eats it);
      CLAYER output never shows [LABELED] (untracked — by design).
- [x] 3.7 Esc at the placement picks of an on-the-fly place-then-label:
      undo group unwinds, `*error*` restored (next command behaves
      normally).
- [x] 3.8 `U` after a full pass reverses everything in one step.

## 4. PFXLABEL

- [x] 4.1 First run: discovery reports N new = the real crossing count; the
      crossings DIALOG lists every crossing OUTSTANDING with the header
      counts matching. **No table** is drawn anywhere (the crossings-table
      subsystem is retired — if a `PF-TABLE` layer or `PF-TABLE_*` block
      appears, that's a finding).
- [x] 4.2 **Zoom-pause:** each drawn crossing framed ~1.5 s, view restored
      to pre-run after the pass. Esc **during** the pause → clean unwind.
      Set `*pf-zoom-pause*` to 0 → no zooming (renamed from `*pfx-zoom-pause*`;
      the parade is now the shared `pf:zoom-*` facility, gated by the per-run
      `*pf-zoom-active*` flag — the palette's "Zoom To" option — with PFXLABEL
      defaulting on, PFLABEL/PFINVERT off).
- [ ] 4.3 Select a [LABELED] row + Label Selected → duplicate confirm
      dialog, Enter/Esc both mean No; Label Outstanding with everything
      labeled → errtile, dialog stays open. Change Target clears the
      sticky target (rerun offers the registry picker).
- [x] 4.4 Skip cases report per crossing and in the pass summary:
      unregistered source; source with no `_INV.pro`; station outside the
      `.pro` range.
- [ ] 4.5 Checksum short-circuit: immediate re-run reports 0 new/updated
      fast; touch a source `.cl` (add a blank line) → that pair rescans.
- [ ] 4.6 Labeled crossing = its dialog row flips LABELED on the next run;
      erase the station line by hand → row honestly returns OUTSTANDING
      (derived, never stored).
- [ ] 4.7 Missing `PF-PIPE_<NN>` block → circle placeholder + warning, no
      crash.

## 5. Copy / drift / integrity attacks

- [x] 5.1 COPY a grid + its anchor: copy resolves as a COPY (registry
      excludes it; PFLABEL/PFXLABEL won't target it).
- [ ] 5.2 `PFREMOVE` on the copy → copy-safe purge offer; accepting erases
      ONLY the copied anchor — **the original's labels survive**.
- [ ] 5.3 Move a grid WITHOUT its anchor → next command reports the corner
      DRIFT warning. Move grid + anchor together → silent (by design).
- [ ] 5.4 Stretch the grid (taller) → top-drift warning on next touch.
- [ ] 5.5 Edit a bound `.cl`'s content → next PFLABEL pass writes
      `STATUS_LABEL` = **STALE**, with the changed-input finding. **This
      changed 2026-07-27:** it used to report FAILING. State 2 now means
      only "the file cannot be read at all"; state 3 means "the file changed
      under you", and collapsing the two lost the difference.
- [ ] 5.6 **Delete** a bound `.cl` from disk → next pass writes **FAILING**
      (state 2), not STALE. The two must not be confusable.

## 6. PFINVERT (the least-exercised command)

- [x] 6.1 Record checks: run on an anchor with no `_INV.pro` bound → fatal
      with the PFSETUP message, no undo group left open.
- [ ] 6.2 **Drop manhole:** I.I and I.O match the `.pro`'s authored inverts
      at the structure edges (check against the profile printout). Lower
      value reads I.O.
- [ ] 6.3 **No-drop structure:** I.I = I.O = the through invert; both rows
      still drawn.
- [ ] 6.4 **Junction:** lateral gets a bare `I.I <elev>` row + a bare pipe
      block at its true elevation on the station X; block on **PF-ANNO**
      (was the lateral's `<TYPE>_P` layer before 2026-07-29); correct size
      block (or circle + warning).
- [ ] 6.5 Column geometry: base Y = **lowest** invert present − 5.0 world
      units (measure it); rows fan left/right straddling the station X.
- [ ] 6.6 **MR direction (decides everything):** the stack hangs DOWNWARD
      from base Y. If it grows UP into the pipe → stop, that's the
      justification finding from the spec session.
- [ ] 6.7 Lateral skip cases report: unregistered lateral; lateral with no
      `_INV.pro`; station off its `.pro` range.
- [ ] 6.8 **Terminus:** a `.pro` endpoint whose only neighbour is a full
      pipe-run away → ONE invert row, classified by elevation (lower profile
      end = I.O only, higher = I.I only). There is no grade tolerance and no
      station fallback any more — the bracket is exact-vertex, so a mild
      grade change must not invent a break.
- [ ] 6.9 Label All re-run replaces by handle; Label Selected appends;
      CLAYER fire-and-forget; `U` reverses; Esc unwinds.
- [ ] 6.10 `STATUS_INVERT` after the pass reflects the `_INV.pro` checksum
      (edit the file → **STALE** on the next pass; delete it → FAILING).
      **Then run PFLABEL and re-read `STATUS_LABEL`** — it must be
      untouched. One shared record used to make the second command erase the
      first's verdict.
- [ ] 6.11 **Scale test:** place a grid at a different HPLOT (e.g. 50):
      text height scales, but the 5.0 column drop does NOT (by design —
      confirm it still reads well at that scale; this was a deliberate
      choice worth eyeballing once).

## 7. PFREMOVE + teardown

- [ ] 7.1 Counts in the confirm DIALOG match reality (tracked entities /
      crossings / passes); Enter and Esc both mean No, Yes is a click.
- [ ] 7.2 After removal: labels, crossing lines, invert output, anchor
      gone; CLAYER output and hand-drawn work UNTOUCHED; stubs untouched.
- [ ] 7.3 One `U` restores the whole profile — anchor, ledger, labels.
- [ ] 7.4 Re-register the same profile after removal → clean, no ghost
      state.

## 8. Free-swing attacks (try to break it)

- [ ] 8.1 Esc at EVERY screen pick and Cancel in EVERY dialog — no stuck
      undo group ever (check: draw a line, `U` undoes just the line).
      Include the two paths fixed pre-session: **(a)** Esc at the extent
      picks during an ON-THE-FLY placement launched from
      PFLABEL/PFXLABEL/PFINVERT (the nested-group leak —
      `pf:run-error`, the shared wrapper's handler, closes any pf group
      now); **(b)** Esc mid-zoom-parade in PFXLABEL → the view returns to
      where the run started.  Also: Cancel in the crossings dialog AFTER
      discovery ran → the undo group still closes (discovery writes are
      inside it).
- [ ] 8.9 **BEHAVIOR CHANGE (2026-07-26, `pf:run-command` Esc flush) — the
      one intentional change of the restructure:** after an **Esc mid-run**,
      entities drawn before the interrupt are now ON the pass ledger —
      `pfa:erase-pass`, PFREMOVE, and recon see them. Before this they were
      orphans unless the user pressed `U`. Gate test, PFLABEL: Esc a run
      mid-parade (turn the zoom parade on to widen the window); confirm
      **(a)** one `U` still peels everything (the flush's record writes die
      with the group), and **(b)** without `U`, a re-run's `[LABELED]`
      marks and `pfa:erase-pass` account for the partial pass. Repeat for
      PFXLABEL (its flush appends the partial crossing handles to the XING
      ledger) and PFINVERT.
- [ ] 8.2 Run commands in a drawing with NO registry, NO PF-NAME text, NO
      grid layers — graceful messages, never a crash.
- [ ] 8.3 Lock the target TEXT layer, run PFLABEL → what happens? (Still
      unknown — `entmake` on a locked layer; record the behaviour.)
- [ ] 8.3b Lock the layer the STRUCTURE BLOCKS sit on, run PFLABEL → the
      run must COMPLETE. The index top-up writes an xdict to each structure
      and a locked layer refuses it; `pfa:memb-sync` is catch-wrapped so
      that costs a cache entry, never the run. Those structures then show up
      under `PFINDEX Report` as not-indexed. **A caching optimisation that
      can kill a labeling run is a failed test, not a finding.**
- [ ] 8.4 Line names with spaces / hyphens / numbers → sanitize survives in
      block names, dict keys, table names.
- [ ] 8.5 A `.cl` with negative stations → crossing key breaks (documented
      unsupported) — confirm it fails loudly, not silently wrong.
- [ ] 8.6 Delete a bound `.pro` from disk mid-session → next pass reports,
      no crash.
- [ ] 8.7 Save, close, reopen: registry, ledger, root, statuses all
      survive; commands pick up where they left off.
- [ ] 8.8 Big-drawing feel: on the largest available job, time the FIRST
      discovery pass (longest alignments = worst case). `pf:poly-x` is
      already cdr-walked (the minutes-scale nth bug is fixed pre-session),
      so expect seconds; if an All-crossings pass still drags, the residual
      suspect is §13.3's per-crossing `pfa:find-anchor` scans — note the
      crossing count vs. wall time.

## 9. Membership index (built 2026-07-27, NEVER run in CAD)

Design: `pfanchor/INDEX-PLAN.md`. Nine steps landed together and **not one
of them has touched AutoCAD.** Static gates only.

**The shape of the thing:** each structure block gets a `MEMB` xrecord —
where it was, a roster stamp, and the lines it sits on with stations. The
stamp covers *every* registered line, so any `.cl` edit stales every record.
That is coarse on purpose: a record lists HITS, so nothing in it can say
which lines were tested and missed, and only a whole-roster stamp can answer
"was this worked out when the world looked like it does now".

### 9a. The order matters — do these first

- [x] 9.1 **Timing baseline, BEFORE anything else.** On the largest real job:
      time `PFLABEL` → Label All, cold (drawing just opened), then again
      without closing. Write both numbers down. Skip this and every later
      "it's faster" claim is unfalsifiable.
- [x] 9.2 `PFINDEX` → Enter (Report is the default) on that same untouched
      drawing. Expect **everything under "not indexed"**, 0 current, 0
      stale, and a roster string. Pure read: `DBMOD` must not move.
- [x] 9.3 `PFINDEX` → `Build`. Expect a count of structures indexed and
      nothing skipped. **One `U` must reverse the whole build.**
- [x] 9.4 `PFINDEX` → `Report` again → all current, 0 stale, 0 not-indexed.
- [x] 9.5 **`PFINDEX` → `Verify`. THIS IS THE ACCEPTANCE GATE.** It computes
      membership from the saved record AND the long way, then names every
      disagreement. **Empty output is the only passing result.** Anything
      else: stop, set `*pf-index-on*` nil in `pftools-cfg.lsp`, and report
      the lines it printed. Do not proceed to 9.6.
- [x] 9.6 Re-time `PFLABEL` Label All cold against 9.1. Labels must be
      **identical**; the time should not be. Diff the two runs' command-line
      output if anything looks off.

### 9b. Staleness — each of these must be caught

Run `PFINDEX Report` after each; the changed structures must read **stale**,
and a re-run of `PFLABEL` must produce the same labels as before the change.

- [ ] 9.7 **Move one structure** a few feet along its line → that structure
      stale (the stored insertion point no longer matches). Move it back
      under `*pfa-memb-move-tol*` (0.001 ft) → still current.
- [ ] 9.8 **Edit a bound `.cl`'s content** → *every* record stale, not just
      that line's. Coarse by design; confirm it is not silently partial.
- [ ] 9.9 **Move ONE interior PI of a drawn centerline**, parallel to its
      bounding box, without adding or removing a vertex. **This is the
      specific fault step 2 was written to close** — the old fingerprint was
      the bounding box plus the vertex count, and neither moves under that
      edit, so the shape read unchanged while the corridor had shifted.
      `pf:verts-hash` walks the points. Records must go stale. **If they do
      not, `pf:verts-hash` is not wired into the stamp and the index can
      serve a wrong answer with no signal at all.**
- [ ] 9.10 **Register a new line** (PFSETUP AUTO or place) → every record
      stale. Known and accepted: registration deliberately does not
      re-index (INDEX-PLAN "What was built"). `PFINDEX Build` clears it.
- [ ] 9.11 **Erase a structure** → its record dies with it (the xdict is
      hard-owned). No orphan, no error on the next run.
- [ ] 9.12 **Copy a structure** to a different spot → the copy inherits the
      stamp but not the position, so it re-derives. A copy **in place** does
      not, and that is documented-degenerate, not a finding.

### 9c. Top-up and the off switch

- [ ] 9.13 On a drawing where 9.10 left everything stale, run `PFLABEL` →
      Label All on ONE line. `PFINDEX Report` → only that line's structures
      are current. The index heals along the route driven; nothing in normal
      use walks every structure, which is what Build is for.
- [ ] 9.14 Run the same `PFLABEL` twice. The second must write nothing —
      `pfa:memb-sync` is a no-op when the record is current. Check with
      `PFPDBMOD`: mark, re-run, compare.
- [ ] 9.15 **The off switch.** Set `*pf-index-on*` nil, reload, run every
      command. Everything must behave exactly as it did before the index
      existed, records in the drawing left untouched. `PFINDEX` says so
      rather than pretending to work. Set it back to `T` → the existing
      records resume being used with no rebuild.
- [ ] 9.16 **Esc mid-run with the top-up live** (extends 8.9). Esc a
      `PFLABEL` All mid-parade → one `U` peels the labels *and* the index
      writes together, because both are in the same group.

### 9d. Write-free contract (the palette can never write)

- [x] 9.17 `PFPDBMOD` to mark → open the palette, click through every line
      in the tree (which now reads the new "Checks" row via
      `pfa:status-roll`) → `PFPDBMOD` again → **UNCHANGED**. `pfa:lines-at`
      and `pfp:status-cell` are new on palette read paths; both claim
      `create` nil, and this is the only thing that proves it.
- [x] 9.18 Same with a drawing that has **no** `PFTOOLS` dictionary at all —
      opening the palette must not create one.

## 10. Ledger rename + the STATUS split

- [ ] 10.1 **On a drawing registered BEFORE 2026-07-27** (the legacy record
      is the whole point — a fresh drawing cannot test this): run `PFLABEL`.
      It must find the anchor's ledger under the old `PFXLEDGER` name, and
      the first write must **rename the entry to `PFLEDGER`**.
- [ ] 10.2 Then `PFREMOVE` on that same anchor → the confirm counts are
      right and teardown erases the tracked entities. **This is the test
      that matters:** if the rename lost the `PASS_*` records, teardown
      finds no handles and silently erases nothing.
- [ ] 10.3 `dictrename` on an xdict entry has **no precedent anywhere in the
      suite** — if 10.1/10.2 fail, the fallback branch still *reads* old
      ledgers, so nothing is lost; the migration just never happens. Report
      it rather than working around it.
- [ ] 10.4 Open a legacy drawing in the **palette only** and touch nothing.
      The rename must NOT happen — it is gated on `create`, because a read
      may never dirty the drawing. `PFPDBMOD` unchanged.
- [ ] 10.5 **Four statuses, not one.** On one anchor run PFLABEL, then
      PFINVERT, then PFXLABEL. All three verdicts must survive
      independently — check the palette's "Checks" row. Before the split,
      each command erased the previous one's.
- [ ] 10.6 PFXLABEL now writes a status **at all** (it never used to).
      Confirm `STATUS_XING` appears after a crossings pass.
- [ ] 10.7 **The roll-up is worst-wins.** With one input edited and the
      others clean, the palette's "Checks" row reads STALE and names which
      pass. One failing input must never render as green.
- [ ] 10.8 **Edits reset per file, not wholesale.** PFSETUP → Edit → rebind
      only the `_INV .pro`. `STATUS_INVERT` goes UNCHECKED; `STATUS_LABEL`
      and `STATUS_XING` keep their state, timestamp and findings. Rebind
      only the `.cl` → the mirror image.

## 11. PFINVERT ticket fix

- [ ] 11.1 `PFINVERT` → Label All, and `PFINVERT` → Label Selected. Output
      must be **identical to before** — this change removed two redundant
      membership scans, nothing else.
- [x] 11.2 The **leftmost structure's** invert stack still shifts right,
      clear of the elevation axis. That shift depends on
      `pfi:line-min-sta`, which now reads the ticket's `'pend` instead of
      re-walking every inlet. If the shift is missing or lands on the wrong
      structure, `'pend` is not reaching the context.
- [x] 11.3 Time both against a pre-change run if you have one.

## 12. PF-ANNO — the global label layer (2026-07-29, NEVER run in CAD)

In a drawing that has **never** carried a PF-ANNO layer:

- [x] 12.1 First label pass creates `PF-ANNO`: colour **green, index 80**,
      **plot flag OFF**. Check the layer properties, not just the colour on
      screen. Console says `Created layer 'PF-ANNO' (no-plot).` once.
- [x] 12.2 `PFLABEL` → All: every row AND the station line land on PF-ANNO.
      Nothing new appears on `STORM-TEXT_P` or any other `<TYPE>-TEXT_P`.
- [x] 12.3 `PFINVERT` → All: invert stacks on PF-ANNO, **and the lateral pipe
      blocks too** — the blocks are the easiest thing to miss, they used to
      go to `<TYPE>_P`.
- [ ] 12.4 `PFXLABEL` → Label Outstanding: the whole pass lands on PF-ANNO —
      station TEXT, crossing pipe block, size/material rows, **and the station
      LINE** (moved off `PF-XING` 2026-08-06). Nothing new on `PF-XING`; on a
      fresh drawing that layer should not be created at all.
- [ ] 12.5 **Recon still works** (this is the one that matters): re-run
      `PFXLABEL` on the same target. Already-labeled crossings must read
      labeled, not outstanding. If everything reads outstanding,
      `pfa:station-line-tops` is scanning the wrong layer.
- [ ] 12.6 **Structure line must not be mistaken for a crossing** — the risk
      the layer split used to cover. Label a structure with `PFLABEL`, then run
      `PFXLABEL` on a crossing at the SAME station. The crossing must read
      outstanding, not labeled: recon now separates the two by top-vertex
      height (grid top vs text-stack top), not by layer. Then label the
      crossing and confirm both re-read correctly.
- [ ] 12.7 Erase the structure's label stack by hand, leaving its station line,
      and re-run `PFXLABEL`. The crossing must still read honestly — a stray
      structure line on PF-ANNO is now inside recon's scan.
- [ ] 12.8 Plot preview / `PLOT`: no label text appears. That is intended —
      PF-ANNO is no-plot by design. Confirm it is what you want on a real
      sheet before this ships to anyone else.
- [ ] 12.9 Settings → "Use current layer" ON: output goes to CLAYER, not
      PF-ANNO, and the pass records as `LABEL-CLAYER` / `INVERT-CLAYER` with
      no handles (unchanged behaviour).
- [ ] 12.10 `PFLABEL` → All a SECOND time: the previous pass is erased by
      handle and redrawn. Then repeat in a drawing labeled BEFORE this change
      — the old `<TYPE>-TEXT_P` entities must still be erased by handle and
      come back on PF-ANNO.
- [ ] 12.11 `PFREMOVE`: clears passes regardless of which layer they landed
      on (erase-by-handle, untouched by this change).
- [ ] 12.12 In a drawing that ALREADY has a PF-ANNO layer in some other
      colour / plotting: it is **left alone** (`pfd:ensure-layer-c` is
      create-only). Labels still go there. Expected, not a bug.

---

**Log findings** as: test #, expected vs observed, severity
(crash / wrong-output / annoyance). Wrong-output beats crash — a crash is
honest, silently wrong numbers on a plan sheet are not.

## History

The 2026-07-20 field test and its 2026-07-21 triage are **closed**. Everything
that survived is in `OPEN-ISSUES.md`, tracked per tool; everything that did not
is in git. The raw log, the resolved-item list, and the project-path discussion
that used to sit here were removed 2026-07-27 — they described work that has
since shipped, and a checklist that carries its own obituary is a checklist
people stop reading to the bottom of.

Two things from that era are still worth knowing while testing:

- **The project data folder is native.** `pfset:root-get` reads Carlson's
  `tmpdir$`; the user-declared NOD "ROOT" and `C:PFROOT` are retired. Useful
  Carlson variables: `lspdir$` (LSP folder), `tmpdir$` (project data),
  `usrdir$` (settings/temp), `sv:sm` / `sv:vs` (h/v scale), `sv:ts` (text
  scaler), `crdfile` (coordinate file).
- **GEOM lives in the drawing's NOD, keyed by `.cl` identity** — not in a
  project-folder sidecar. That fork was left open pending one question: do
  several sheet drawings share one data folder? If they ever do, a sidecar
  traces once per project instead of once per sheet. Until then the in-drawing
  store is the right shape, and the membership index (§9) follows the same
  rule for the same reason.
