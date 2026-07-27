# pftools-cfg.lsp — configuration (the FIRM'S constants)

**Load position:** 1 of 10 (first; every other file reads these).
**May depend on:** nothing.
**Depended on by:** every other file in the suite.

## What it owns

EVERY tunable in the suite lives here and nowhere else — Carlson API entry
points, membership tolerances, text/label geometry scalars, the structure
label rule table, naming conventions, per-type materials/layers/templates,
crossing rendering constants, PFINVERT geometry, anchor/ledger names, grid
layers, and the settings-file/NOD names. Meant to be edited in a text
editor; no code, only `setq` constants.

Do not confuse this with pfsettings:

- **pftools-cfg.lsp** = the FIRM'S constants (templates, maps, sizes) —
  edited here, by hand, rarely.
- **pfsettings.lsp** = the USER'S persisted state (last-used paths, dialog
  values, project root) — written by the tools.

## Public API

None — this file defines no functions, only `*pf-*` / `*pfx-*` / `*pfi-*` /
`*pfa-*` / `*pfg-*` / `*pfset-*` globals. Key load-bearing groups:

- `*pf-dtm-fn*` / `*pf-road-fn*` — the Carlson API entry symbols the lib
  wrappers apply.
- `*pf-rule-table*` — structure label rules, ORDERED, FIRST MATCH WINS
  (compounds before singles, SMH/DMH before MH). Order is load-bearing.
- `*pf-types*` / `*pf-pro-roles*` / `*pf-tin-design-prefix*` — the naming
  convention (identity keys).
- `*pfa-*` — anchor block, ledger dictionary, schema version, tolerances.
- `*pfset-std-subfolders*` / `*pfset-std-search-depth*` — firm-standard
  project subfolder routing.
- `*pf-corridor*` / `*pf-corridor-sampled*` — the membership pre-filter
  distances. The second is derived (`*pf-corridor*` + half a sample step)
  and applies to a line whose shape is the `.cl`'s own SAMPLED walk rather
  than an exact drawn twin: a station walk lands on the centerline, but the
  chords between samples cut corners at deflections, so the true `.cl` can
  sit up to half a step off. **Lowering these re-opens the error parade;**
  a line with no shape at all turns the pre-filter off entirely.
- `*pf-geom-exact*` / `*pf-geom-sampled*` — GEOM record KIND. **Both are
  live as of 2026-07-27** (previously EXACT had no writer): `pf:cl-geom`
  writes EXACT whenever `pf:cl-parse` reads the file and SAMPLED when the
  parse is refused. A drawing can hold both kinds at once.

## Invariants

- Loads FIRST; nothing here may reference a function from any other file.
- `*pf-rule-table*` order decides matches — reordering changes output.
- `*pfa-schema-ver*` 3 = the V4 record (FILES/EXTENTS/STATUS/SCOPE/PASS_/X_).

## Open issues local to this file

- The `[INERT]` block (vertex-band / misalign / grid-cell knobs) is set here
  but read NOWHERE — scaffold for the segment-membership fix. Do not tune
  them chasing a missing structure; see the PFLABEL CRITICAL entry in
  [../OPEN-ISSUES.md](../OPEN-ISSUES.md). Delete the banner when wired.
  **The geom KIND pair is no longer part of that block** — it has a writer
  now. `*pf-grid-cell*` is still inert, and is the intended home for the
  bounding-box / spatial pre-filter that would sit in front of
  `pf:pt-poly-dist`.
- **No provenance on tolerances.** A GEOM record does not store the
  `*pfx-sample-step*` it was walked at, so tuning that constant does not
  invalidate existing SAMPLED records. Same latent gap would apply to any
  future membership cache built under `*pf-offset-tol*` / `*pf-corridor*`.
