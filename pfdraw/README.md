# pfdraw.lsp — drawing boundary

**Load position:** 3 of 12 (after pftools-lib, before pfanchor).
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

- `pfd:ensure-layer-c name noplot color` → nil — creates the layer if
  missing, born at `color`. **CREATE-ONLY**: an existing layer is never
  recoloured, so a hand-set colour survives — and equally, changing a
  caller's colour does not repaint drawings that already carry the layer.
- `pfd:ensure-layer name noplot` → nil — the above at colour 7.
- `pfd:anno-layer` → `"PF-ANNO"` — ensures THE annotation layer (no-plot,
  green 80) and returns its name. **Every label pass writes here**, and this
  is the only place the suite decides that: callers ask for the layer, they
  never build a layer name. Create-only, so a drawing that already carries
  PF-ANNO keeps its own colour and plot flag. No exceptions as of 2026-08-06
  — PFXLABEL's crossing station LINE was the last holdout and now writes here
  too.
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
- `pfd:label-pipe x ycen file size mat sf ht style` → list of enames — row 1
  = NN" MATERIAL, row 2 = the standard line label. The rows straddle `ycen`
  (the pipe centre, not the invert) by half the row gap.

## Invariants

- Like the lib, this file may NEVER know what an anchor is, read a record,
  or reference a dialog.
- NO function here erases anything.

## Open issues local to this file

None on record ([../OPEN-ISSUES.md](../OPEN-ISSUES.md)).
