# PFTools V4 — Open Issues

Live issue list, separated by tool. Sourced from the 2026-07-20 field-test
session (the raw log lived in `TESTING.md` NOTES) and triaged against the
2026-07-21 pull. Resolved items are recorded in `TESTING.md` ("Resolved since
last pull"), not here.

Severity: **crash** | **wrong-output** | **scope** | **ux** | **perf** |
**feature** | **question**. Wrong-output outranks crash — silently wrong
numbers on a plan sheet are the worst outcome.

---

## PFINVERT

- ~~**[wrong-output — CRITICAL] I.I / I.O are swapped and collapsed.**~~
  **FIXED (untested in CAD).** Root cause was the sample-and-detect bracket
  (`pfi:break-scan`): 0.5-ft sampling read the break ~half a step past the true
  vertex (the ~0.05-ft-high bias, ≈ `*pfi-grade-tol*`) and couldn't classify
  one-sided/no-break structures. Replaced with an **exact vertex bracket** —
  `pf:pro-verts` parses the `.pro` file directly (the Road API has no vertex
  accessor, confirmed) and `pfi:invert-bracket` takes the two adjacent vertices
  meeting at the structure: lower = I.O., higher = I.I., a polyline endpoint = a
  single-invert terminus. Also added pipe size to callouts, the
  I.O.|shared|I.I. column order, text-scaled drop, and the leftmost-structure
  shift. **Verify in CAD:** numbers match the `.pro` to the penny; no
  station-domain warning fires. *(field note 258)*
- ~~**[scope] Type-scoping.**~~ **FIXED 2026-07-21** with PFLABEL (shared
  builders). Laterals now come only from same-type lines via the scoped table.

## PFLABEL

- ~~**[scope] Cross-utility contamination.**~~ **FIXED 2026-07-21 (untested in
  CAD).** Membership was built from the whole registry (all types), pulling in
  other utilities' structures/blocks. Now the secondary `.cl` set is scoped to
  the primary's utility type in both builders — `pflabel:registry-pairs`
  (covers PFINVERT + both `setup` paths) and the direct build in
  `pflabel:run-dialog` — keyed on `pf:type-of` (filename truth). PFXLABEL is
  deliberately untouched (crossings stay cross-type). Laterals inherit the
  scoping via the filtered line table. **Verify in CAD:** a STORM MH that a
  SANITARY line merely crosses no longer appears in the STORM label; genuine
  same-type junctions still get the combined ID. *(field notes 2, 256, 259)*
- **[ux — verify] Ghost dropdown on open.** Reported glitchy/unprofessional.
  *Likely fixed* by the pick-first refactor (target popup removed from `pf_run`;
  all compute moved before `new_dialog` via `pflabel:rd-compute`) — re-check in
  CAD before closing. *(field note 255)*

## PFXLABEL

- Field findings 243, 244, 245, 247 are **resolved** by this pull
  (`"Checking for crossings"` message; zero-count report suppressed;
  `profile z`→`profile_z` — the skipped crossing that dropped its line should
  now label). **Re-test the skipped-source case** (`SANITARY_A @ 5+14.38`) to
  confirm before considering it closed.

## PFSETUP

- **[ux] "Place All" dialog parade.** Place All fires one unskippable dialog
  per profile, one after another, with no way to pause and navigate to the next
  profile. Current per-placement flow (Place → dialog → elevation → extents
  pick → back to main dialog) leaves no way to move to the next profile without
  closing and reopening the manager. Wants a pausable/navigable flow.
  *(field notes 250, 251)*
- **[ux] Dialog box size.** Setup dialogs should be larger. *(field note 252)*
- **[feature] Discover crossings & shared stations at PFSETUP.** Currently
  crossing discovery only runs in PFXLABEL; the ask is to find `.cl` crossings
  and shared stations at registration time. *(field note 240)*

## PFREMOVE

- No open field findings. (Covered by TESTING.md §7 / §5, not yet executed.)

---

## Shared / cross-cutting

- ~~**[scope] Same-type membership** (PFLABEL + PFINVERT).~~ **FIXED
  2026-07-21** — one fix in the shared builders (`pflabel:registry-pairs` +
  `pflabel:run-dialog`) served both, keyed on `pf:type-of`. *(field note 2)*
- **[ux] Anchor block style.** Formatting/appearance of the `PF-GRIDANCHOR`
  block wants a pass. *(field note 253)*
- ~~**[ux] `CMDECHO` never suppressed** (§13.2).~~ **FIXED 2026-07-21 (untested
  in CAD).** Shared `pf:echo-off`/`pf:echo-on` in the lib save the user's
  CMDECHO and zero it for the run; every command's prologue calls `echo-off`,
  every normal epilogue calls `echo-on`, and `pfa:undo-cleanup` restores on the
  error path. Kills the UNDO/ZOOM/DELAY chatter. (The ×5 error/undo scaffolding
  itself — §13.4 — is still un-refactored; CMDECHO is now one less thing the
  eventual `pf:run-command` wrapper must absorb.)
- **[perf] Per-crossing `pfa:find-anchor` full-DB scans** (§13.3). An All-mode
  pass re-scans the whole database per crossing; scan the registry once per
  command and pass it down. *(field note "Performance improvements?")*
- **[crash-guard] Backtick sheet names** still unfixed: `pf:parse-sheet-name`
  closes only on a straight `'`, so `` STORM LINE `DA` `` silently skips in
  AUTO. *(TESTING.md known-open)*
- **[question] `PICKADD`** — does the suite need to save/restore it around
  selection? Flagged, not investigated. *(field note "PICKADD variable
  change?")*

---

## Native Carlson integration

Policy (Jake, 2026-07-21): **make every native Carlson call we can** instead of
hand-entered or hardcoded values.

- ~~Project root~~ **DONE** — `tmpdir$` (`pfset:root-get`); PFROOT retired.
- ~~Plot scales~~ **DONE (verify)** — the setup dialog seeds HPLOT/VPLOT from
  `sv:sm`/`sv:vs` (`pfset:native-scale`); still editable, stored value wins on
  Edit. **Verify in CAD** that `sv:sm`/`sv:vs` actually equal the profile
  grid's H/V (not some unrelated plan scale).
- ~~Settings/temp folder~~ **DONE** — `pfset:dir` prefers `usrdir$`, falls back
  to LOCALAPPDATA/TEMP. (Old settings in `LOCALAPPDATA\PFTools` are orphaned,
  not migrated — harmless; last-used values just repopulate.)
- **[feature] Metric guard (`is metric`).** The suite hardcodes english —
  `pf:pipe-at` does `(TOP−INV)×12` (inches), stations/elevations in feet. A
  metric drawing would be silently wrong. Minimal step: read the metric flag
  and **warn/refuse**; full metric support is a larger feature. **Blocked on
  the exact variable name** — the reference lists "is metric" (a space → not a
  valid symbol); confirm the real symbol in a live session before wiring.
- **[decision] `sv:ts` / `sv:ps` (text / symbol scalers).** Deliberately NOT
  adopted: label size comes from the firm-standard `*pf-text-base-height*` × sf,
  an intentional firm choice, not Carlson's scaler. Keep as a possible
  cross-check only.
- **[future] `psname` (Carlson Support folder).** Candidate home for the
  `PF-PIPE_*` block library `.dwg`/`.dwt` — use when the block library is built
  ([[block-material-library-direction]]).
- **N/A:** `crdfile` (plan-view coordinates, irrelevant to profiles); no native
  crossing-finder / station-formatter / profile-grid-geometry exists (confirmed
  API catalog) — `pf:fmt-station`, `.cl` intersection, top-of-grid probe stay.

## Design decisions / open questions

- **[question] GEOM cache storage location.** Geometry lives in the drawing's
  NOD (per-drawing) keyed by `.cl` identity. If multiple sheet drawings share
  one project data folder, a project-folder **sidecar** cache (trace once per
  project) is a strictly bigger win. **Now unblocked:** the reliable project
  path this needed landed 2026-07-21 (native `tmpdir$`, `pfset:root-get`). Only
  open question left: **one sheet per project, or many sheets sharing one data
  folder?** If many, build the sidecar; if one, the in-DWG NOD cache is already
  right. *(TESTING.md storage-location discussion)*
- ~~**[question] PVI probe.**~~ **RESOLVED 2026-07-22.** The Road API exposes
  **no** vertex accessor — the only profile calls are `profile z` and `profile
  sta range` (confirmed against the live `cf:road_api` catalog). `pfi:invert-
  bracket` now reads exact vertices by **parsing the `.pro` file** (`pf:pro-
  verts`), the suite's one file read, with a `profile_z` cross-check guarding the
  station domain.

## PFPALETTE
- Palette persists across drawings. Intentional? 