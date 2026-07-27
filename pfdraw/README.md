# pfdraw.lsp — drawing boundary

**Load position:** 3 of 10 (after pftools-lib, before pfanchor).
**May depend on:** pftools-cfg, pftools-lib.
**Depended on by:** pfanchor, pflabel, pfxlabel, pfinvert.

## What it owns

The ONLY file that entmakes label output. Callers hand it fully resolved
values (layer, style, height); it draws and returns enames so the caller
can ledger the handles. Layers, text, label stacks, station lines, circles,
pipe block inserts, and the two-row pipe label.

## Public API

All WRITERS (they entmake); every function returns the ename(s) it created
(nil on entmake failure) — handle capture is the caller's job, and it is
what makes the erase-by-handle contract possible. Callers must hold an
open undo group.

- `pfd:ensure-layer name noplot` → nil — creates the layer if missing.
- `pfd:style-or-fallback style` → a style that exists (firm default →
  Standard → ""). Pure read; used internally by `pfd:text`.
- `pfd:text pt str layer style ht rot just` → ename | nil — just `'ML` =
  middle-left (label-stack default), `'MR` = middle-right (rot pi/2: text
  hangs BELOW the anchor).
- `pfd:draw-label-stack line-x base-y rows layer style ht offset gapn just`
  → `(line-top . enames)` — columns straddle the station line; line-top =
  base-y + length of row 1 with any trailing " =" stripped.
- `pfd:station-line x ybot ytop layer` → ename | nil (LWPOLYLINE).
- `pfd:circle pt r layer` → ename | nil.
- `pfd:insert-pipe pt size layer yscale sf` → ename | nil — size nil or
  block undefined → placeholder circle (with a warning).
- `pfd:label-pipe x y file size mat sf ht style` → list of enames — row 1
  = NN" MATERIAL, row 2 = the standard line label.

## Invariants

- Like the lib, this file may NEVER know what an anchor is, read a record,
  or reference a dialog.
- NO function here erases anything.

## Open issues local to this file

None on record ([../OPEN-ISSUES.md](../OPEN-ISSUES.md)).
