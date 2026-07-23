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
- **Command echo (FIXED 2026-07-21, verify):** `CMDECHO` is now saved/zeroed
  per command (`pf:echo-off`/`pf:echo-on`) and restored on both normal and
  error exit. Confirm no UNDO/ZOOM/DELAY chatter during a run, and that
  CMDECHO returns to its prior value after the command (and after an Esc).
- **MR justification:** confirmed "grows down" by recollection — **verify
  visually** in 6.6; it decides the invert stack's direction.
- **PVI check:** RESOLVED 2026-07-22 — the Road API has no vertex accessor
  (only `profile z` / `profile sta range`). `pfi:invert-bracket` now reads exact
  vertices by parsing the `.pro` file (`pf:pro-verts`); `pfi:break-scan` is gone.
- **Dialog layer (2026-07-19 rework + 2026-07-21 pick-first split):**
  the registry manager (`pfsetup_registry`), PFLABEL's `pf_run`, PFINVERT's
  own `pfi_run` (separate definition, `pi_*` tiles), the crossings dialog
  (`pfxl_run`), `pf_confirm`, and the slot-based `pfsetup_main`. **Both label
  commands are now pick-first:** `pfs:choose-or-place` resolves the target
  (a `pf_pick` list) *before* the run dialog opens — there is **no target
  popup**, and the dialog lists a single target's structures. Expect DCL
  layout findings (tile widths, list column drift under the proportional
  font) on top of logic findings.
- **PFINVERT bracket is BROKEN (wrong-output, CRITICAL — probe first):**
  I.I/I.O swapped, the I.O elevation applied to both inverts, shared inverts
  missed, ~0.05 ft high. The 2026-07-21 upload touched only PFINVERT's
  dialog, not its bracket math — this is live. See §6 and `OPEN-ISSUES.md`.
- **Cross-utility scoping (FIXED 2026-07-21, verify):** PFLABEL/PFINVERT
  membership is now scoped to the primary's utility type (was whole-registry).
  Verify in 3.1 and 6.4 that other-utility blocks no longer leak in and
  same-type junctions still combine.

---

## 0. Load

- [ ] 0.1 `(load ".../V4/pftools-load.lsp")` → banner lists **PFSETUP,
      PFLABEL (PFL), PFXLABEL (PFX), PFINVERT (PFI), PFLABELSET** (PFROOT is
      retired — project root is native `tmpdir$`), "Coming this cycle:
      PFCHECK". No load errors.
- [ ] 0.2 `*pftools-dir*` inside `pftools-load.lsp` points at THIS V4
      folder (it ships hardcoded — fix the path first or nothing loads).
- [ ] 0.3 Each command name autocompletes / runs from the command line.
- [ ] 0.4 **Dialog smoke:** every dialog OPENS (a DCL syntax error kills
      the whole file — `pfsetup_registry`, `pfsetup_main`, `pf_run`,
      `pfi_run`, `pfxl_run`, `pf_confirm`, `pf_pick`, `pflabel_settings`).
      Help buttons show their text; Esc/Cancel closes clean everywhere.

## 1. Project root + AUTO registration (PFSETUP first run)

- [ ] 1.1 **Native root (tmpdir$) — CHANGED 2026-07-21, re-verify.** With an
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
- [ ] 1.3 **Skip cases report loudly, never guess:** a PF-NAME with no
      matching `.cl` → SKIPPED; two `.cl` files matching one name → SKIPPED
      (ambiguous); a `.cl` with no sheet name → NOTE.
- [ ] 1.4 **Backtick attack:** make one PF-NAME use backticks. Expected
      (bug): silently absent from the register list — confirm, then decide
      if the fix is worth it.
- [ ] 1.5 The **Refresh button** re-scans: idempotent — nothing re-named,
      no duplicates.
- [x] 1.6 **Registry manager behaves:** list shows every profile with
      [PLACED]/[unplaced]; Place on a placed row / Edit on a stub / no
      selection → errtile message, dialog stays open; double-click places
      a stub and edits an anchor; empty registry greys Place/Place
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
- [ ] 2.2 Material popup follows the Type popup; last-used material per
      type sticks across placements in the session.
- [x] 2.3 Extents picks: **running osnaps on** — pick the corners and check
      the anchor landed where you meant (known weakness; note how bad it
      is). Top-right left/below lower-left → refused.
- [ ] 2.4 Datum field: prefilled with the session-last value on the second
      grid; edit prefills the stored datum.
- [x] 2.5 Placed anchor: block visible on `PF-ANCHOR` (no-plot), attributes
      LINE/UTIL/STA0/DATUM/HPLOT/VPLOT populated and plausible.
- [ ] 2.6 **One `U` removes exactly one grid's placement** (not the batch,
      not the AUTO stubs).
- [ ] 2.7 Edit mode: `.pro` swap accepted (cheap); the **re-pick extents
      toggle** re-picks (and is greyed on a fresh placement); same-range
      `.cl` swap accepted; **different-range `.cl` REFUSED**; **identity
      change REFUSED**. Ledger survives an accepted edit (place a label
      first, edit, confirm the pass record remains).

## 3. PFLABEL

- [ ] 3.0 **Pick-first + run dialog:** target is chosen by the `pf_pick` list
      BEFORE the dialog opens (no target popup); the structure list then
      matches the plan (every structure on the primary line, sorted by
      station); Label Selected with nothing selected → errtile; Settings...
      opens PFLABELSET nested and changes apply to the same run; picking an
      UNPLACED profile places it first (two corner picks) then lists it.
      **Ghost-dropdown check:** the list paints cleanly on open (the
      compute-before-`new_dialog` fix) — no flicker/glitch.
- [ ] 3.1 Select the junction structure in the list → station rows primary
      first then alphabetical; combined ID alphabetical (`AA-1/BB-2`); const
      row from the rule table (SMH/DMH before MH — label one of each);
      elevation row placeholder; HDWL drops the elevation row.
      **Cross-utility scoping (FIXED 2026-07-21, verify):** on a sheet with
      mixed types near the same station, confirm the label does NOT pull in a
      different-type line's structure/block — membership is now scoped to the
      primary's type. A same-type junction (two STORM lines) MUST still get the
      combined ID; a SANITARY line the STORM merely crosses MUST NOT appear.
- [ ] 3.2 **Stub contribution:** with a secondary line UNPLACED (stub
      only), the junction ID still includes it.
- [x] 3.3 Stepped-top grid: labels sit on the top **at each station**, not
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

- [x] 4.1 First run: discovery reports N new = the real crossing count; the
      crossings DIALOG lists every crossing OUTSTANDING with the header
      counts matching. **No table** is drawn anywhere (the crossings-table
      subsystem is retired — if a `PF-TABLE` layer or `PF-TABLE_*` block
      appears, that's a finding).
- [x] 4.2 **Zoom-pause:** each drawn crossing framed ~1.5 s, view restored
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

## Field-test findings (2026-07-20), triaged 2026-07-21

Open issues are now tracked in **`OPEN-ISSUES.md`** (separated by tool). This
section keeps the record of what the pull resolved; the raw log is archived
below it.

**Resolved by the 2026-07-21 pull — re-verify, then close:**

- PFXLABEL `"Checking for crossings"` progress message added (was silent).
- PFXLABEL zero-count `"Discovery: 0 new, 0 updated, 0 moved"` now suppressed
  (prints only when something changed).
- `profile z` → **`profile_z`** Road-API fix. This is almost certainly why
  `SANITARY_A @ 5+14.38` skipped "SOURCE INVERT UNREADABLE" **and** why the
  crossing line "dropped" (skipped crossings draw nothing). Re-run that case.
- PFLABEL station-line prefix now per-type via the `[util]` token
  (`sta_suf` = `"[util] LINE '[line]'"`), not a hardcoded "STORM".
- Perpendicular-deflection miss fixed by the drawn-twin pre-filter (exact PIs).
- Ghost dropdown *likely* fixed by the pick-first refactor — verify in 3.0.

**Still open → see `OPEN-ISSUES.md`:** PFINVERT I.I/I.O bracket bug (CRITICAL),
cross-utility scoping, PFSETUP Place-All flow + dialog size, discover-at-setup,
anchor block style, CMDECHO, per-crossing scan perf, backtick names, PICKADD,
GEOM sidecar decision, PVI probe.

---

### Raw field log (2026-07-20, archived)

•	.cl crossings and shared stations need to be found at pfsetup.
•	For pflabel and pfinvert we don’t need to run checks against other utility types. If STORM we only need to compare to STORM etc.
•	Performance improvements?
•	Pfxlabel suppressed cmdecho for .cl checks. Need at least “Checking for crossings” so the user doesn’t think it is freezing up.
•	Pfxlabel “Discovery: 0 new, 0 updated, 0 moved.” is a bit confusing makes it seem like nothing was labeled. Probably move this to an output only if something has changed.
•	Pfxlabel dropped the crossing line 
•	First pfxlabel run. == PFXLABEL: 0 labeled, 1 skipped ==
  SKIPPED  SANITARY_A @ tgt sta 5+14.38  -- SOURCE INVERT UNREADABLE (profile z)
•	Didn’t recognize profile names in drawing. (Don’t need this anyway.)
•	PICKADD variable change?
- pfsetup place all gives you an unskipple dialog paraded one after the other. Think about being able to pause dialog to navigate to profile then reopen.
- Dialog for pfsetup needs to allow navigation between each placement. (or something....its current dialog flow is annoying. Click place > dialog > elevation > extents pick > back to main dialog.....leaves no way to navigate to next profile without closing the main dialog and reopening afterward)
- Size of dialog box should be increased.
- anchorblock style.
- pflabel is using STORM LINE prefix for station line instead of defaulting per type.
- pflabel dialog has ghost dropdown upon opening. Looks glitchy/unprofessional.
- pflabel is labeling structures that aren't there, may be using multiple .cl files instead of just target.
- missed a structure at a perpendicular deflection. - solved- 
- pfinvert labels I.I. and I.O. swapped. Is applying the I.O. elevation (Incorrectly labeled I.I) to bothe inverts. Missed shared structure inverts. elevation is consistently .05 feet higher than the actual elevation.
- pflabel grabs block from other utilities
- pflabel names by [UTIL]
- 

> **UPDATE 2026-07-21 — the project-path question below is ANSWERED.** The
> suite now reads the project data folder natively from Carlson's `tmpdir$`
> (`pfset:root-get`); the user-declared NOD "ROOT" / `C:PFROOT` mechanism is
> retired. This *unblocks* the GEOM-sidecar option (a reliable project path was
> its prerequisite) — that decision still rides on the one open question:
> **one sheet per project, or many sheets sharing one data folder?** The
> discussion below is kept as the rationale.

*The storage-location deviation I called out in the plan: geometry lives in a shared NOD store keyed by .cl identity, not on the stub/anchor record with promotion carry-forward. Behavior matches what we designed; it's just less machinery. If you specifically want it on the record, that's a different edit.

*Here's the current mechanism, because it reframes the storage decision.

Today the suite does NOT read the project location from Carlson at all. C:PFSETUP calls pfset:root-get, which reads a "ROOT" xrecord from the drawing's NOD dictionary. If it's unset, the user browses to any file in the data folder (pfset:browse → getfiled), and the derived directory is stored back per-drawing (pfset:root-set, also exposed as C:PFROOT). So the data folder is user-declared once and remembered in each drawing — pfs:cl-lookup/pfs:pro-lookup then vl-directory-files that path.

The Carlson bridge itself is cf:road_api (from EWORKS.ARX, scload-ed from lspdir$) — a named-dispatch: the suite calls "cl_sta_range", "cl_location_at_pt", "profile_z", etc. through it. Nothing project-path-related goes through it today.

Whether Carlson can hand us the project path through that bridge is empirical — I can't determine it from the LISP source. The ARX is a black box; the source only shows which ops the suite currently uses, not the full menu EWORKS exposes. So this needs a live probe. Candidates to try in Carlson, best-first:

A cf:road_api op for it — try things like (cf:road_api "project_path") / "data_path" / "current_project". Carlson's civil ARX often exposes the active project's data directory; if EWORKS has such an op, that's the cleanest source.
Carlson config getters — Carlson SCAD exposes settings via its own config functions (varies by version). The current project/data path is usually queryable there.
(getvar "DWGPREFIX") — the reliable AutoLISP fallback: the sheet drawing's own folder. In many workflows the .cl/.pro data sits alongside the sheet or in a known subfolder, so this is at minimum a good seed for the browse default even if it's not authoritative.
Why this matters for the GEOM storage decision — and I think this is the real reason you linked them: the cache I built lives in the drawing's NOD, so it's per-drawing. Every sheet that references the same project data re-traces the lines. If you can reliably resolve the project data folder, the alternative is a sidecar cache file in that folder — traced once per project, shared across every sheet drawing. That's a strictly bigger win than per-drawing, and it's exactly what a reliable project path unlocks.

So the storage fork is really:

In-drawing NOD (what I built) — self-contained, no external files, survives as part of the DWG; but per-drawing, so N sheets = N traces.
Project-folder sidecar — trace once per project, every sheet reads it; but depends on reliably knowing (and re-finding) the data folder, and it's an external file to manage/invalidate.
My read: keep the NOD "ROOT" as the source of truth / fallback regardless (it works today and needs no Carlson cooperation), add a Carlson-read as an auto-seed if a probe finds one, and let the in-DWG-vs-sidecar choice come down to one question — do multiple sheet drawings in your workflow share the same project .cl/.pro data? If yes, the sidecar's "trace once per project" is worth the external-file complexity. If each project is basically one drawing, the in-DWG cache I built is already the right shape.

Before I take this further: which is it — one sheet per project, or many sheets sharing one data folder?

The following is a list of useful variables:
lspdir$ - Carlson LSP folder where program files are located (string)
tmpdir$ - current project data folder (string)
usrdir$ - folder for program settings and temporary files (string)
psname - Carlson Support folder (string)
sv:sm - horizontal scale (real)
sv:vs - vertical scale (real)
sv:ts - text size scaler (real)
sv:ps - symbol size scaler (real)
is metric - english/metric mode (0=english, 1=metric)
crdfile - current coordinate file (string)

Both right-flags on = the whole label rides the right edge at fixed width; top-flags off = it stays pinned near the top.

For reference later, that 4-flag model maps the README table like this: fixed top-left = 0/0/0/0; stretch horizontally (like tvwLines, metaList) = Left-from-right 0, Right-from-right 1; stretch vertically = Top-from-bottom 0, Bottom-from-bottom 1. tvwLines (stretches both) ends up 0/1/0/1.