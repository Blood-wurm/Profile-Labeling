# pfsettings.lsp — user-state layer + shared dialogs

**Load position:** 5 of 12 (after pfanchor, before pfsetup).
**May depend on:** pftools-cfg, pftools-lib, pfanchor (the NOD helpers reuse
pfanchor's generic xrecord machinery).
**Depended on by:** pfsetup, pflabel, pfxlabel, pfinvert, pfpalette
(+ runtime-only by pfanchor: `pfset:pick-index`, `pfset:confirm`).

## What it owns

The USER'S state — three kinds, three stores — plus the shared nested
dialogs every command reuses. The FIRM'S constants live in pftools-cfg;
don't let them bleed together.

1. **Settings file** (`usrdir$` → LOCALAPPDATA → TEMP, `\PFTools\
   pftools-settings.txt`): plain KEY=VALUE text — label prefix/suffix
   strings, text layer/style, plot-scale defaults. Falls back to the v3
   `pflabel-settings.txt` on first read.
2. **Session globals** — last-browsed directory per file type
   (`*pfset-dir-cl/pro/tin/txt*`).
3. **Project root** — NATIVE (Carlson `tmpdir$`), read live; a one-shot
   browse seeds a session fallback when no project is active. No NOD root
   record. Firm-standard subfolders are found by searching UP
   (`pfset:find-std-dir`).

## Public API

All pure reads/UI (settings-file writes touch disk, never the drawing —
the module has no drawing-write path since its NOD passthrough was
quarantined 2026-08-01).

**Settings:** `pfset:settings` (auto-loads once), `pfset:put-setting`,
`pfset:merge`, `pfset:read-settings` / `pfset:write-settings` (disk),
`pfset:save-auto` (disk), `pfset:dir`.

**Project root + routing:** `pfset:root-get` (tmpdir$ → session fallback),
`pfset:root-set`, `pfset:tmpdir`, `pfset:find-std-dir`,
`pfset:get-company-dir fileType` (std subfolder → session dir → root),
`pfset:native-scale sym` (seeds the setup dialog from sv:sm / sv:vs).

**Browse:** `pfset:browse title dirvar ext` — getfiled wrapper with
per-type last-directory memory (dirvar = QUOTED global symbol).

**Drawing lookups:** `pfset:layer-list`, `pfset:style-list`,
`pfset:active-style` (settings choice → firm default → Standard → "").

**Shared dialogs (modal; command context only):** `pfset:dcl-file` (the
ONE pfdialog.dcl path, off `*pftools-dir*`), `pfset:load-dcl`,
`pfset:help`, `pfset:pad`, `pfset:confirm title lines` (Yes/No; No is
default and the Esc path), `pfset:pick-index`, `pfset:pick-from-list`.

Quarantined to `_attic` 2026-08-01 (DATA-FLOW §5, no callers in .lsp or
.dcl): the ask-name and scan-dialog helpers, and the NOD passthrough —
readers call `pfa:nod-dict` directly.

## Invariants

- This is the USER'S state; the firm's constants stay in pftools-cfg.
- Per-command dialog WIRING lives with each command, not here — only the
  SHARED dialogs live here.
- `pfset:dcl-file` derives from `*pftools-dir*` — never hardcode a second
  copy of the path.

## Open issues local to this file

- The per-type last-browsed-directory memory is clobbered by pfsetup's
  company-folder routing on every pick, so it never takes effect —
  [../pfsuite-md/OPEN-ISSUES.md](../pfsuite-md/OPEN-ISSUES.md) LOW-3.
