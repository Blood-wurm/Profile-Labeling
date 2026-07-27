# Wiring prompt

Paste the block below into a fresh instance. It assumes the working directory is
the pfsuite project folder and that `V5\README.md` is readable.

---

```
Wire the PFTools V5 OpenDCL palette to the existing V4 command layer.

READ FIRST, IN THIS ORDER
  V4\V5\README.md        — palette structure, control names, geometry,
                           OpenDCL constraints, milestones. Authoritative.
  V4\README.md           — the V4 suite (§13 is an honest self-assessment)
  V4\OPEN-ISSUES.md      — known-broken, by tool
  V4\pfanchor.lsp        — pfa:registry, pfa:read-attribs, pfa:att,
                           pfa:rec-get, pfa:files-get, pfa:stub-list,
                           pfa:copy-p. The anchor block IS the record.
  V4\pfsetup.lsp         — pfs:registry-dialog, pfs:reg-item,
                           pfs:choose-or-place (line ~679), pfs:place-one
  V4\pftools-load.lsp    — load order; *pftools-dir* is a hardcoded path

Working OpenDCL examples ship with Studio and are worth reading before
writing anything:
  C:\Program Files (x86)\OpenDCL Studio\ENU\Samples\Methods.lsp     (TabStrip)
  C:\Program Files (x86)\OpenDCL Studio\ENU\Samples\ListView.lsp    (ListView)
  C:\Program Files (x86)\OpenDCL Studio\ENU\Samples\Tree.lsp        (TreeView)
  C:\Program Files (x86)\OpenDCL Studio\ENU\Samples\Modeless.lsp    (lifecycle)

SCOPE — milestone 2 only, plus the loader

  1. pfpalette.lsp, a new file in V5\, loaded last by pftools-load.lsp.
     - ensure the runtime is up (_OPENDCL, CMDECHO suppressed)
     - dcl-Project-Load on V4\V5\pfsetup.odcl, path derived from
       *pftools-dir*, never hardcoded a second time
     - C:PFPALETTE as a toggle (dcl-Form-IsActive -> hide, else show)

  2. c:pfsetup/pfsPalette#OnInitialize
     - dcl-ListView-AddColumns on metaList and lvwLinkage (see README §4).
       Once only. This call is additive.
     - seed lblProject from pfset:root-get, lblCounts from the registry
     - initial tree population

  3. Populate tvwLines from (pfa:registry).
     Two levels: utility Type as parents, Line as children. Registry rows are
     (type name state ename stub) with state 'PLACED or 'STUB. Use the settled
     vocabulary in the UI — "Anchored" / "Registered", not "placed" / "stub".

  4. tvwLines selection handler -> fill metaList and lvwLinkage for the
     selected line. Read from the anchor (pfa:read-attribs / pfa:att /
     pfa:rec-get / pfa:files-get) for anchored lines, from the stub data for
     registered ones. lvwLinkage always shows exactly five rows; unbound
     entries read "(not set)".

  Do NOT build in this pass: the verb buttons, the file pickers, the
  *pf-preset-target* graft, the refresh reactors, or tabs 2 and 3. Milestone 2
  is read-only on purpose — it must not be able to modify a drawing.

HARD CONSTRAINTS

  - V4 is FUNCTIONAL IN CAD. Do not refactor it. The only V4 edit this whole
    project needs is the *pf-preset-target* graft, and that is milestone 3,
    not now. Surgical graft over rewrite; proven code is never rewritten.

  - Palette handlers are MODELESS — they run outside a command context. No
    entsel, getpoint, command, or undo group in a handler, ever. Milestone 2
    touches nothing in the drawing, so this should not come up; if it seems
    to, the design is wrong.

  - labeled/outstanding and every status shown is DERIVED, never stored.
    Re-read the drawing on each refresh. Do not add a cache.

  - Registry counts per line (labels done, crossings done) are expensive —
    they recon-read the drawing per row. Populate them for the SELECTED row
    only, never for every row on a document switch. Show "—" otherwise.

  - Read V4\..\..\ memory or CLAUDE.md if present for the V4 design
    invariants, and do not "simplify" any of them. Several look like cleanup
    opportunities and are load-bearing (anchor-owns-the-record, relative
    extents, the plain-string self-handle copy stamp, the single top-of-grid
    probe feeding both draw and recon).

  - T is a protected constant in AutoLISP. Never a local variable name.

STYLE

  Match the surrounding code — V4's comment density, naming (pf: / pfa: /
  pfs: / pfset: prefixes by module), and idiom. New palette functions get a
  pfp: prefix. Keep the load-order guardrail: a file may only depend on files
  above it.

DELIVERABLE

  Resolve the design questions first and state them, then execute in one pass.
  Report honestly what was verified statically versus what needs CAD to prove —
  none of this can be executed here, and the palette has never been opened in
  AutoCAD, so nothing should be described as working. End with the exact steps
  to test it in CAD.
```
