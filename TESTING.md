# PFTools V4 — Shakedown Checklist

Run on a **scratch copy** of a real job. Goal: break it. Every test names its
expected result — anything else is a finding. Work top to bottom; later
phases depend on earlier state.

**Bring:** a sheet with ≥2 profile grids (one with stepped tops), a drop
manhole with a known I.I/I.O, a junction structure on ≥2 lines, at least one
real crossing, the project folder (`Type_Name.cl` + `_INV`/`_TOP.pro` pairs,
`.tin` files), `PF-PIPE_<NN>` blocks, and the `L080` style.

**Known-open issues to probe deliberately** (expected findings, not
surprises):

- **Backtick names bug (UNFIXED):** `pf:parse-sheet-name` closes only on a
  straight `'` — a PF-NAME like ``STORM LINE `DA` `` silently skips in AUTO.
- **Command echo:** `CMDECHO` is never suppressed — UNDO/ZOOM/DELAY chatter
  is expected noise, not a bug (§13.2).
- **MR justification:** confirmed "grows down" by recollection — **verify
  visually** in 6.6; it decides the invert stack's direction.
- **PVI check:** while in the session, test whether the Road API returns
  `.pro` vertices (try `(cf:road_api "profile vertices" <pro>)` and similar
  spellings). If yes → swap `pfi:break-scan` later.
- **Dialog layer is BRAND-NEW (2026-07-19 rework, never opened in CAD):**
  the registry manager (`pfsetup_registry`), the shared run dialog
  (`pf_run`), the crossings dialog (`pfxl_run`), `pf_confirm`, and the
  slot-based `pfsetup_main` all shipped together. Expect DCL layout
  findings (tile widths, list column drift under the proportional font) on
  top of logic findings. Command line now carries ONLY screen picks.

---

## 0. Load

- [ ] 0.1 `(load ".../V4/pftools-load.lsp")` → banner lists **PFSETUP,
      PFLABEL (PFL), PFXLABEL (PFX), PFINVERT (PFI), PFLABELSET, PFROOT**,
      "Coming this cycle: PFCHECK". No load errors.
- [ ] 0.2 `*pftools-dir*` inside `pftools-load.lsp` points at THIS V4
      folder (it ships hardcoded — fix the path first or nothing loads).
- [ ] 0.3 Each command name autocompletes / runs from the command line.
- [ ] 0.4 **Dialog smoke:** every dialog OPENS (a DCL syntax error kills
      the whole file — `pfsetup_registry`, `pfsetup_main`, `pf_run`,
      `pfxl_run`, `pf_confirm`, `pf_pick`, `pflabel_settings`). Help
      buttons show their text; Esc/Cancel closes clean everywhere.

## 1. Project root + AUTO registration (PFSETUP first run)

- [ ] 1.1 Fresh drawing: `PFSETUP` prompts for a `.cl` in the data folder;
      root stored (verify: `PFROOT` shows it; survives save/reopen).
- [ ] 1.2 AUTO names every PF-NAME profile: each gets `Named <TY> '<NM>'`
      with its `.cl` + INV/TOP note. Count matches the sheet.
- [ ] 1.3 **Skip cases report loudly, never guess:** a PF-NAME with no
      matching `.cl` → SKIPPED; two `.cl` files matching one name → SKIPPED
      (ambiguous); a `.cl` with no sheet name → NOTE.
- [ ] 1.4 **Backtick attack:** make one PF-NAME use backticks. Expected
      (bug): silently absent from the register list — confirm, then decide
      if the fix is worth it.
- [ ] 1.5 The **Refresh button** re-scans: idempotent — nothing re-named,
      no duplicates.
- [ ] 1.6 **Registry manager behaves:** list shows every profile with
      [PLACED]/[unplaced]; Place on a placed row / Edit on a stub / no
      selection → errtile message, dialog stays open; double-click places
      a stub and edits an anchor; empty registry greys Place/Place
      All/Edit.

## 2. PFSETUP placement

- [ ] 2.1 Dialog validation rejects: empty name; zero/negative scales;
      empty datum; ONE `.pro` bound (pair rule); `.pro` whose name ≠ the
      Name field; one `.tin` bound. Each shows the errtile message, no
      crash. **Slot role guards:** picking a `_TOP.pro` on the Invert
      button, or a DESIGN_* tin on the Exist button → refused at pick
      time with an errtile message (wrong-role files can no longer reach
      OK).
- [ ] 2.2 Material popup follows the Type popup; last-used material per
      type sticks across placements in the session.
- [ ] 2.3 Extents picks: **running osnaps on** — pick the corners and check
      the anchor landed where you meant (known weakness; note how bad it
      is). Top-right left/below lower-left → refused.
- [ ] 2.4 Datum field: prefilled with the session-last value on the second
      grid; edit prefills the stored datum.
- [ ] 2.5 Placed anchor: block visible on `PF-ANCHOR` (no-plot), attributes
      LINE/UTIL/STA0/DATUM/HPLOT/VPLOT populated and plausible.
- [ ] 2.6 **One `U` removes exactly one grid's placement** (not the batch,
      not the AUTO stubs).
- [ ] 2.7 Edit mode: `.pro` swap accepted (cheap); the **re-pick extents
      toggle** re-picks (and is greyed on a fresh placement); same-range
      `.cl` swap accepted; **different-range `.cl` REFUSED**; **identity
      change REFUSED**. Ledger survives an accepted edit (place a label
      first, edit, confirm the pass record remains).

## 3. PFLABEL

- [ ] 3.0 **Run dialog:** the structure list matches the plan (every
      structure on the primary line, sorted by station); switching the
      Target popup repopulates it; Label Selected with nothing selected →
      errtile; Settings... opens PFLABELSET nested and changes apply to
      the same run; choosing an UNPLACED profile + labeling places it
      first (dialog → two picks), then labels.
- [ ] 3.1 Select the junction structure in the list → station rows primary
      first then alphabetical; combined ID alphabetical (`AA-1/BB-2`); const
      row from the rule table (SMH/DMH before MH — label one of each);
      elevation row placeholder; HDWL drops the elevation row.
- [ ] 3.2 **Stub contribution:** with a secondary line UNPLACED (stub
      only), the junction ID still includes it.
- [ ] 3.3 Stepped-top grid: labels sit on the top **at each station**, not
      the nominal top. A station past the grid edge (no MJR hit) skips with
      a report.
- [ ] 3.4 Label All: count matches structures on the line; sorted by
      station.
- [ ] 3.5 All re-run: prior pass replaced **by handle** (count reported);
      hand-drawn text on the same layer untouched. List rows flip
      [LABELED] on the next run's dialog (X-proximity to tracked pass
      entities — advisory; verify it doesn't false-mark two structures at
      near-identical stations).
- [ ] 3.6 CLAYER toggle: draws on current layer; re-run All does NOT erase
      it; pass recorded (run PFXLABEL later and confirm nothing eats it);
      CLAYER output never shows [LABELED] (untracked — by design).
- [ ] 3.7 Esc at the placement picks of an on-the-fly place-then-label:
      undo group unwinds, `*error*` restored (next command behaves
      normally).
- [ ] 3.8 `U` after a full pass reverses everything in one step.

## 4. PFXLABEL

- [ ] 4.1 First run: discovery reports N new = the real crossing count; the
      crossings DIALOG lists every crossing OUTSTANDING with the header
      counts matching. **No table** is drawn anywhere (the crossings-table
      subsystem is retired — if a `PF-TABLE` layer or `PF-TABLE_*` block
      appears, that's a finding).
- [ ] 4.2 **Zoom-pause:** each drawn crossing framed ~1.5 s, view restored
      to pre-run after the pass. Esc **during** the pause → clean unwind.
      Set `*pfx-zoom-pause*` to 0 → no zooming.
- [ ] 4.3 Select a [LABELED] row + Label Selected → duplicate confirm
      dialog, Enter/Esc both mean No; Label Outstanding with everything
      labeled → errtile, dialog stays open. Change Target clears the
      sticky target (rerun offers the registry picker).
- [ ] 4.4 Skip cases report per crossing and in the pass summary:
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

- [ ] 5.1 COPY a grid + its anchor: copy resolves as a COPY (registry
      excludes it; PFLABEL/PFXLABEL won't target it).
- [ ] 5.2 `PFREMOVE` on the copy → copy-safe purge offer; accepting erases
      ONLY the copied anchor — **the original's labels survive**.
- [ ] 5.3 Move a grid WITHOUT its anchor → next command reports the corner
      DRIFT warning. Move grid + anchor together → silent (by design).
- [ ] 5.4 Stretch the grid (taller) → top-drift warning on next touch.
- [ ] 5.5 Edit a bound `.cl`'s content → next PFLABEL pass writes STATUS
      FAILING with the changed-checksum finding.

## 6. PFINVERT (never executed — the critical section)

- [ ] 6.1 Record checks: run on an anchor with no `_INV.pro` bound → fatal
      with the PFSETUP message, no undo group left open.
- [ ] 6.2 **Drop manhole:** I.I and I.O match the `.pro`'s authored inverts
      at the structure edges (check against the profile printout). Lower
      value reads I.O.
- [ ] 6.3 **No-drop structure:** I.I = I.O = the through invert; both rows
      still drawn.
- [ ] 6.4 **Junction:** lateral gets a bare `I.I <elev>` row + a bare pipe
      block at its true elevation on the station X; block on the lateral's
      `<TYPE>_P` layer; correct size block (or circle + warning).
- [ ] 6.5 Column geometry: base Y = **lowest** invert present − 5.0 world
      units (measure it); rows fan left/right straddling the station X.
- [ ] 6.6 **MR direction (decides everything):** the stack hangs DOWNWARD
      from base Y. If it grows UP into the pipe → stop, that's the
      justification finding from the spec session.
- [ ] 6.7 Lateral skip cases report: unregistered lateral; lateral with no
      `_INV.pro`; station off its `.pro` range.
- [ ] 6.8 Grade-tol sanity: a structure where grades change mildly
      (< ~5%/ft) with no drop → bracket falls back to the station read, no
      false break. A real drop face → caught.
- [ ] 6.9 Label All re-run replaces by handle; Label Selected appends;
      CLAYER fire-and-forget; `U` reverses; Esc unwinds.
- [ ] 6.10 STATUS after the pass reflects the `_INV.pro` checksum (edit the
      file → FAILING finding on the next pass).
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
      `pfa:undo-cleanup` closes any pf group now); **(b)** Esc
      mid-zoom-parade in PFXLABEL → the view returns to where the run
      started.  Also: Cancel in the crossings dialog AFTER discovery ran →
      the undo group still closes (discovery writes are inside it).
- [ ] 8.2 Run commands in a drawing with NO registry, NO PF-NAME text, NO
      grid layers — graceful messages, never a crash.
- [ ] 8.3 Lock the target text layer, run PFLABEL → what happens? (Unknown
      — entmake on a locked layer; record the behavior.)
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

---

**Log findings** as: test #, expected vs observed, severity
(crash / wrong-output / annoyance). Wrong-output beats crash — a crash is
honest, silently wrong numbers on a plan sheet are not.
