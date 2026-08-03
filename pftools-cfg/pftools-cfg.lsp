;;; ==========================================================================
;;; pftools-cfg.lsp  --  PFTools configuration (the firm's constants)
;;; Load position 1 of 10 (first; every other file reads these).
;;; Contract, tunable groups, and invariants: see README.md beside this file.
;;; ==========================================================================

;;; --------------------------------------------------------------------------
;;; Carlson API entry points
;;; --------------------------------------------------------------------------
(setq *pf-dtm-fn*  'cf:dtm_api)     ; TRI4.ARX   (load_tin / unload_tin / tin_z)
(setq *pf-road-fn* 'cf:road_api)    ; EWORKS.ARX (cl_sta_range / cl_location_*)

;;; --------------------------------------------------------------------------
;;; Membership & corridor  (plan-view structure/line association)
;;; --------------------------------------------------------------------------
(setq *pf-offset-tol* 0.15)   ; max perpendicular offset (ft) to count as ON a line
(setq *pf-corridor*   0.2)    ; corridor pre-filter distance (ft) before Road-API calls
(setq *pf-range-eps*  0.01)   ; station-range slack (ft) for line-end structures
(setq *pf-rank-ascending* T)  ; T => rank 1 at the LOWEST station

;;; --------------------------------------------------------------------------
;;; Membership INDEX  (the saved structure->lines answer; pfanchor SECTION 4b)
;;; --------------------------------------------------------------------------
;;; THE OFF SWITCH.  nil makes pfa:memb-get always report a miss, so every
;;; caller falls back to pf:lines-at-point exactly as it did before the index
;;; existed.  This is the field rollback: if a saved answer is ever wrong, turn
;;; it off here rather than patching the reader.  Records already in the drawing
;;; are left alone and resume being used when it goes back on.
(setq *pf-index-on* T)

;; Bumping this invalidates EVERY saved record, drawing-wide.  It is the only
;; cover for the tolerances above: *pf-offset-tol* and *pf-range-eps* are
;; applied INSIDE pf:lines-at-point, after the corridor test, so no per-line
;; stamp can see them move.  Change one of those, bump this in the same edit.
(setq *pf-index-schema* 1)

;; A structure that moved less than this did not move.  Compared against the
;; insertion point stored in the record; anything larger re-derives membership.
(setq *pfa-memb-move-tol* 0.001)  ; ft

;; Coordinate scale for pf:verts-hash.  4 decimal places of a foot is far below
;; any real plan movement and far above float noise.  Applied as a REMAINDER,
;; never a plain multiply -- state-plane northings times 10000 overflow (fix).
(setq *pf-hash-scale* 10000.0)

;;; --------------------------------------------------------------------------
;;; INERT SCAFFOLD -- set here, read NOWHERE in the suite.
;;; These belong to the planned point-to-SEGMENT membership fix for the
;;; "structures silently dropped" bug (OPEN-ISSUES / PFLABEL).  Membership still
;;; gates on cl_location_at_pt via pf:lines-at-point, so CHANGING ANY VALUE
;;; BELOW HAS NO EFFECT ON A RUN.  Do not tune them chasing a missing structure
;;; -- the fix is not wired yet.  Delete this banner when it is.
;;; --------------------------------------------------------------------------

;; [INERT] Vertex-proximity membership (segment-distance model).  RADIAL
;; distance to the .cl polyline -- semantically distinct from the perpendicular
;; *pf-offset-tol*; kept separate so the two can diverge.
;;   <= hi          : member, high confidence
;;   hi < d <= lo   : member, LOW confidence -- labeled, flagged, distance reported
;;   > lo           : not a member
(setq *pf-vertex-band-hi* 0.15)   ; [INERT] ft -- radial, high-confidence membership
(setq *pf-vertex-band-lo* 1.0)    ; [INERT] ft -- radial, low-confidence outer bound

;; [INERT] Twin-vs-.cl misalignment, checked at PFSETUP.  The .cl checksum
;; proves the FILE is stable; it cannot see a drawn plan-PL that diverges.
(setq *pf-misalign-flag*   0.15)  ; [INERT] ft -- report a drawn-PL / .cl offset above this
(setq *pf-misalign-refuse* 1.0)   ; [INERT] ft -- treat as a wrong/foreign twin above this

;; [INERT] Spatial-grid pre-filter: prunes candidate LINES before any distance
;; test.  No grid is built yet; the pre-filter in use is pf:in-corridor-p.
(setq *pf-grid-cell* 50.0)        ; [INERT] ft -- uniform bucket edge

;; GEOM record KIND: EXACT = parsed .cl vertices (stations authoritative);
;; SAMPLED = Road-API station walk (vertex stations not carried, so the z slot
;; stores 0.0).  Both are live: pf:cl-geom writes EXACT whenever pf:cl-parse
;; reads the file, SAMPLED when the parse is refused and it falls back to the
;; walk.  A drawing can hold both kinds at once.
(setq *pf-geom-exact*   0)
(setq *pf-geom-sampled* 1)

;;; --------------------------------------------------------------------------
;;; Text & label geometry  (base scalars AT the reference H plot scale)
;;; --------------------------------------------------------------------------
;;;   sf     = hplot / *pf-ref-hplot*
;;;   height = *pf-text-base-height* * sf       1.60 at H:20,  4.00 at H:50
(setq *pf-text-base-height* 1.60)
(setq *pf-ref-hplot*        20.0)
(setq *pf-offset-factor*    1.0)    ; station-line -> text offset, x height
(setq *pf-gap-rest-factor*  1.5)    ; gap between adjacent label rows, x height
(setq *pf-hscale-fixed*     1.0)    ; model space 1:1 horizontally (1 unit = 1 sta ft)
(setq *pf-elev-placeholder* "XXX.XX") ; drafter-filled elevation rows

(setq *pf-style-default*  "L080")       ; label text style (firm standard)
(setq *pf-vtext-style*    "ARIAL_L080") ; vertical station-text style

;;; --------------------------------------------------------------------------
;;; Structure label rules  --  ORDERED, FIRST MATCH WINS.
;;;   (TOKENS  PREFIX  TYPE  TEXT2  ELEV-PREFIX  SIZE-BEARING?)
;;;   ORDER IS LOAD-BEARING: compounds before singles, SMH/DMH before MH.
;;; --------------------------------------------------------------------------
(setq *pf-rule-table*
  ;;  TOKENS         PREFIX    TYPE              TEXT2                      ELEV     SIZE
  '((("CBI" "MH")   "CONST."  "DRAINAGE MH"     "W/ CURB INLET CASTING"    "G.L."   nil)
    (("DBI" "MH")   "CONST."  "DRAINAGE MH"     "W/ SQUARE GRATE CASTING"  "T.G."   nil)
    (("SMH")        "CONST."  "SANITARY MH"     ""                         "T.R."   nil)
    (("DMH")        "CONST."  "DRAINAGE MH"     ""                         "T.R."   nil)
    (("CBI")        "CONST."  "CURB BOX INLET"  ""                         "G.L."   nil)
    (("DBI")        "CONST."  "DROP BOX INLET"  ""                         "T.G."   nil)
    (("MH")         "CONST."  "MANHOLE"         ""                         "T.R."   nil)
    (("HDWL")       "CONST."  "HDWL"            ""                         nil      T)))

;;; --------------------------------------------------------------------------
;;; Naming convention  (identity keys -- see the V4 handoff, section 4.2)
;;;   Storm_LINEA.cl / Storm_LINEA_INV.pro / Storm_LINEA_TOP.pro
;;; --------------------------------------------------------------------------
(setq *pf-pro-roles*        '("INV" "TOP"))  ; positive role suffixes; neither = ERROR
(setq *pf-tin-design-prefix* "DESIGN_")      ; TIN prefix => proposed; else existing
(setq *pf-types*            '("STORM" "SANITARY" "WATER"))

;;; --------------------------------------------------------------------------
;;; Pipe materials, PER UTILITY TYPE.  Asserted in the PFSETUP dialog (a
;;; dropdown that follows the selected type) and stored on the anchor; the
;;; crossing label reads the SOURCE profile's material -> NN" <MATERIAL>.
;;; First entry is the per-type default.  PLACEHOLDERS -- edit to the firm's
;;; real material lists.  Keys must match *pf-types*.
;;; --------------------------------------------------------------------------
(setq *pf-materials*
  '(("STORM"    . ("RCP" "HDPE" "PVC"))
    ("SANITARY" . ("PVC" "DI"))
    ("WATER"    . ("DI" "PVC" "COPPER"))))

;;; --------------------------------------------------------------------------
;;; Utility-type derived layers & templates
;;; --------------------------------------------------------------------------
;;; RETIRED -- see *pf-anno-layer*.  Every label pass now writes to the ONE
;;; annotation layer, so nothing derives a layer from the utility type.  Kept
;;; (with pf:sym-layer / pf:text-layer) so a per-type revert is a one-line
;;; change rather than an archaeology exercise.
(setq *pfx-layer-suffix*      "_P")
(setq *pfx-text-layer-suffix* "-TEXT_P")
(setq *pfx-align-layers*
  '(("WATER"    . "ALIGN-WATER_P")
    ("SANITARY" . "ALIGN-SAN_P")
    ("STORM"    . "ALIGN-STM_P")))
(setq *pfx-label-templates*
  '(("WATER"    . "PROPOSED WATER MAIN '[name]'")
    ("SANITARY" . "PROPOSED SANITARY LINE '[name]'")
    ("STORM"    . "STORM LINE '[name]'")))
(setq *pfx-cross-templates*
  '(("WATER"    . "PROPOSED WATER CROSSING")
    ("SANITARY" . "PROPOSED SANITARY CROSSING")
    ("STORM"    . "STORM CROSSING")))

;;; --------------------------------------------------------------------------
;;; Crossing / pipe rendering
;;; --------------------------------------------------------------------------
(setq *pfx-pipe-sizes* '(4 6 8 10 12 15 18 24 30 36 42 48 54 60))
(setq *pfx-block-prefix*  "PF-PIPE_")   ; block family PF-PIPE_<NN>
(setq *pfx-circle-radius* 1.0)          ; placeholder when the block is missing
(setq *pfx-text-dx*   3.20)             ; pipe-label x offset (base scalar)
(setq *pfx-row1-dy*   1.73)             ; pipe-label row 1 y offset
(setq *pfx-row-gap*   3.20)             ; pipe-label row gap
(setq *pfx-line-ext*  30.0)             ; station line extension below the grid
(setq *pfx-tick-layer* "PF-TEMP")       ; invert ticks + elev text; NEVER erased
(setq *pfx-xing-text-layer* "PF-XING-TEXT") ; RETIRED -- crossing station text
                                        ; went to PF-XING, and as of 2026-07-29 goes to PF-ANNO with
                                        ; every other label; kept for compatibility
(setq *pf-zoom-pause* 1.5)              ; DURATION of the verification pause, seconds.
                                        ; The ON/OFF switch is per run: each engine's
                                        ; pf:zoom-resolve call (PFXLABEL on by default,
                                        ; PFLABEL/PFINVERT off until the palette's
                                        ; "Zoom To" checkbox feeds the order ticket).
                                        ; Set this to 0 to disable the pause regardless.
                                        ; Shared by all three via pf:zoom-* (lib 15).
(setq *pf-zoom-min-height* 60.0)        ; parade frame FLOOR, base model units (x sf).
                                        ; pf:zoom-item never frames tighter than this,
                                        ; so a short label stack still shows its grid
                                        ; context.  60 x sf ~= a full grid panel at H:20.

;;; --------------------------------------------------------------------------
;;; Console volume
;;; --------------------------------------------------------------------------
;;; *pf-quiet* suppresses PROGRESS ONLY -- the running commentary a command
;;; owes the user while it works ("Loaded line 'A' ...").  It is bound T around
;;; palette READS, where the same gather path runs on every tree click and the
;;; commentary is pure noise: one click can otherwise emit a line per line in
;;; the gather set plus two DRIFT blocks.
;;;
;;; IT NEVER SILENCES A FINDING.  Errors, refusals, skip reports and anything
;;; from *error* / pf:run-error print regardless -- route those through
;;; (prompt) directly, never through pf:progress.  A palette that hides a
;;; failure is worse than a palette that chatters.
(setq *pf-quiet* nil)

;;; --------------------------------------------------------------------------
;;; Plan-geometry sampling  (crossing discovery)
;;; --------------------------------------------------------------------------
(setq *pfx-sample-step* 2.0)   ; ft -- .cl walk interval (arcs followed)
(setq *pfx-refine-step* 0.1)   ; ft -- re-sample interval near a hit

;; Terminus band, EITHER alignment -- a hit this close to a .cl's first or last
;; station is two lines meeting at a SHARED STRUCTURE (junction manhole, or a
;; branch tying into a main mid-run), not a pipe crossing over or under one.
;; `inters` cannot tell the difference: touching endpoints lie on both segments,
;; so a junction files exactly like a crossing.  Widen this if two .cl files
;; that meet at a structure stop further apart than a manhole radius; narrow it
;; if a genuine crossing near a line end is being skipped (discovery names its
;; skips, so that case reports rather than vanishing).
(setq *pfx-terminus-tol* 2.0)  ; ft -- see pf:shared-structure-p

;; Corridor pre-filter distance for a SAMPLED .cl shape (pflabel:build-lines'
;; last-resort verts).  A station walk lands ON the centerline, but the chords
;; BETWEEN samples cut corners at deflections: with the PI up to one step from
;; the nearest sample on each leg, the worst case (a hairpin) puts the true .cl
;; half a step off the sampled chord.  So the sampled corridor is the exact
;; corridor plus that bound -- wide enough never to drop a real structure at a
;; bend, and still ~6x tighter than the no-filter path it replaces.
(setq *pf-corridor-sampled* (+ *pf-corridor* (/ *pfx-sample-step* 2.0)))

;;; --------------------------------------------------------------------------
;;; PFINVERT  (invert labels at structures)
;;; --------------------------------------------------------------------------
;;; Text base Y = lowest invert present MINUS (this factor x text height).  The
;;; label drop now SCALES with text height like every other label spacing in
;;; the suite: 4.0 x height = 16 model units at H:50 (height 4.0), 6.4 at H:20.
(setq *pfi-invert-offset-factor* 4.0)

;;; Vertex bracket (pfi:invert-bracket): the structure's in/out inverts are the
;;; two ADJACENT .pro vertices that straddle the station -- exact endpoints, no
;;; sampling.  Two vertices count as one structure only when their station gap
;;; is <= this width (a real pipe run between structures is far wider); a lone
;;; endpoint vertex is a terminus (single invert).
(setq *pfi-struct-width-max* 15.0)  ; ft -- max gap for a vertex pair to be ONE structure

;;; PFINVERT row spacing.  Its own factor, NOT *pf-gap-rest-factor*: PFLABEL's
;;; stack straddles pfd:station-line (row 0 left of the station X, the rest
;;; right, with the wide 2 x offset gap giving the line room), while PFINVERT
;;; draws no station line and centres its whole fan on the station X with one
;;; uniform gap throughout.  Gap = this x text height, so at H:50 (height 4.0)
;;; a factor of 2.0 leaves a 4.0 gutter between 4.0-wide rotated rows -- one
;;; clear text height between columns.  TUNE HERE; nothing else reads it.
(setq *pfi-row-gap-factor* 2.0)   ; centre-to-centre row gap, x text height

;;; Junction detection: a lateral that TERMINATES at a structure sits at its own
;;; endpoint, beyond the tight on-line membership tolerances (built for
;;; pass-through hits).  PFINVERT adds any same-type registered line whose
;;; endpoint lands within this distance of the structure as a shared lateral.
(setq *pfi-junction-tol* 2.0)  ; ft -- line endpoint <= this from a structure = a junction

;;; First (leftmost) structure: its label stack is shifted right so the left
;;; column clears the grid's elevation-axis labels.  Target left edge =
;;; grid leftx + (this base scalar x sf).  Tune against a real sheet.
(setq *pfi-first-shift-clearance* 12.0)  ; base model units (x sf) of axis clearance

;;; --------------------------------------------------------------------------
;;; Anchor & ledger  (pfanchor.lsp)
;;; --------------------------------------------------------------------------
;;; The anchor block is the hand-authored PF-ANCHOR (color 152): a small fixed
;;; ICON snapped to the datum, NOT a frame spanning the grid.  Same string as
;;; *pfa-layer* below; block and layer live in separate symbol tables, so the
;;; collision is legal and intentional.  pfa:ensure-anchor-block entmakes a
;;; placeholder icon under this name only in a drawing that has no PF-ANCHOR
;;; definition, so the toolset never dies on a bare drawing.
(setq *pfa-block-name*  "PF-ANCHOR")

;;; Block names an anchor may be INSERTED as.  New anchors are always written
;;; as *pfa-block-name*; PF-GRIDANCHOR is the pre-icon name, kept here so that
;;; anchors in drawings registered before the swap still resolve instead of
;;; going invisible to every lookup.  ssget's (2 . ...) filter takes this comma
;;; list directly.  Those older anchors also store their extents differently --
;;; see pfa:extents.
(setq *pfa-block-names* "PF-ANCHOR,PF-GRIDANCHOR")
(setq *pfa-layer*       "PF-ANCHOR")      ; created NO-PLOT, unlocked
;;; Colour the PF-ANCHOR layer is BORN at (pfd:ensure-layer-c is create-only, so
;;; a drawing that already carries the layer keeps whatever colour it has -- this
;;; does not repaint anything already anchored).  The icon geometry is all
;;; ByLayer on layer "0" inside the block, so this one number colours the whole
;;; symbol except the white triangle.  152 matches the hand-authored artwork.
(setq *pfa-layer-color* 152)
;;; THE annotation layer: EVERY label pass writes here -- PFLABEL's stacks and
;;; station lines, PFINVERT's stacks and lateral pipe blocks, PFXLABEL's station
;;; text, crossing pipe block and pipe labels.  Replaces the per-utility-type
;;; derived layers (<TYPE>-TEXT_P / <TYPE>_P).
;;; NO-PLOT is deliberate and is the whole point: labels are review output here,
;;; not plotted sheet annotation.
;;; Same create-only caveat as *pfa-layer-color* -- pfd:ensure-layer-c never
;;; recolours an existing layer, so a drawing already carrying PF-ANNO keeps its
;;; colour AND its plot flag.  Only fresh drawings are born green no-plot.
(setq *pf-anno-layer*       "PF-ANNO")
(setq *pf-anno-layer-color* 80)          ; green
;;; THE LEDGER dictionary, hung off an entity's extension dictionary.  Owner is
;;; whatever entity carries it: an ANCHOR holds META/FILES/STATUS_*/SCOPE/PASS_*
;;; /X_*, a STRUCTURE holds MEMB.  pfa:ledger-dict is owner-agnostic.
;;; The old name is a fossil of the one tool that happened to need a record
;;; first.  *pfa-dict-legacy* is READ for drawings registered before the rename,
;;; and pfa:ledger-dict RENAMES the entry the first time something writes, so
;;; the fallback empties out on its own instead of living forever.
(setq *pfa-dict-name*   "PFLEDGER")
(setq *pfa-dict-legacy* "PFXLEDGER")
(setq *pfa-schema-ver*  3)                ; schema 3 = the V4 record (FILES/EXTENTS/STATUS/SCOPE/PASS_/X_); matches pfanchor + README
;;; WIDTH/HEIGHT are the grid extents RELATIVE to the insertion point.  The
;;; insert's X/Y scale factors carried them back when the block spanned the
;;; grid; the block is a fixed-size icon now and its scales carry plot scale, so
;;; these two attributes are the only extent truth on a current anchor.  An
;;; anchor with no WIDTH/HEIGHT is pre-icon -- that absence IS the legacy
;;; discriminator (see pfa:extents).  ORDER MATTERS: pfa:write-anchor writes
;;; values positionally against this list.
(setq *pfa-att-tags*    '("LINE" "UTIL" "STA0" "DATUM" "HPLOT" "VPLOT"
                          "WIDTH" "HEIGHT"))
(setq *pfa-att-height*  0.8)
(setq *pfa-att-gap*     1.6)

;;; ATTRIB (70) flags on the anchor's attributes.  1 = INVISIBLE: the anchor
;;; carries eight fields of machine state and none belong on the sheet.
;;; NOT 8 (PRESET) -- a different bit entirely, which leaves every value
;;; rendering under the datum.  Add 8 back only if a manual INSERT of the block
;;; should skip prompting; the entmade path never prompts.
;;; ATTDISP ON still forces them visible -- the intended debug escape.
(setq *pfa-att-flags*   1)

;;; H plot scale the anchor ICON was drawn at: at H:50 the block reads at the
;;; size it should, so the insert scale is hplot/50, applied UNIFORMLY (X=Y=Z)
;;; to keep the icon undistorted and a constant size on the plotted sheet.
;;; NOT *pf-ref-hplot* (20.0) -- that is the reference for the text/label base
;;; scalars, which were authored at a different scale.  Using it here would
;;; draw the icon 2.5x too big.
(setq *pfa-icon-ref-hplot* 50.0)
(setq *pfa-xing-layer*  "PF-XING")        ; crossing station lines (recon scans this)
(setq *pfa-recon-eps*   1.0e-4)           ; float round-trip tolerance
(setq *pfa-key-tol*     2.0)              ; content-key station drift tolerance
(setq *pfa-probe-tol*   0.05)             ; grid-LINE-near-corner sanity probe
(setq *pfa-grid-layers* "PF-GRID-MJR,PF-GRID-MNR,PF-HBOX")

;;; --------------------------------------------------------------------------
;;; Carlson-drawn grid sheet layers -- these ARE the layers Carlson draws on.
;;; The sheet-geometry parser is retired; the only sheet reads left are the
;;; PF-NAME identity scan (AUTO registration) and the top-of-grid probe.
;;; --------------------------------------------------------------------------
(setq *pfg-mjr-layer*  "PF-GRID-MJR")   ; the TOP line -- the per-station top probe
(setq *pfg-name-layer* "PF-NAME")       ; "STORM LINE 'DA'" -- AUTO identity scan

;;; Top-of-grid probe bounds.  The probe ray runs from the anchor's base up
;;; to (nominal top + this margin), base scalar x sf.  Must exceed the rise
;;; of any panel step ABOVE the top-right pick, but stay under the sheet's
;;; grid-stacking gap or the ray reads the next grid up.
(setq *pfg-top-margin* 25.0)

;;; Top-drift tolerance: probed top at the right edge vs. the registered
;;; top-right pick.  Loose -- the pick is a user click, not a snap.
(setq *pfa-top-tol* 0.5)

;;; --------------------------------------------------------------------------
;;; Settings & drawing-dictionary names  (pfsettings.lsp)
;;; --------------------------------------------------------------------------
(setq *pfset-fname*        "pftools-settings.txt")   ; auto last-used settings
(setq *pfset-fname-legacy* "pflabel-settings.txt")   ; v3 fallback, read once
(setq *pfset-nod-name*     "PFTOOLS")                ; drawing dictionary (NOD)

;;; --------------------------------------------------------------------------
;;; Project data folders  (NATIVE routing off Carlson's tmpdir$)
;;; --------------------------------------------------------------------------
;;; The project data root comes from Carlson (tmpdir$); file picks and AUTO
;;; lookups route to these firm-standard subfolders.  pfset:find-std-dir
;;; SEARCHES UP from the root (0..depth parent levels) for each subfolder, so
;;; it self-calibrates no matter which level tmpdir$ lands on -- no fixed
;;; "step up N" assumption.  Edit these paths to the firm's project template.
(setq *pfset-std-subfolders*
  '(("cl"  . "02_ProjectData\\Alignments")
    ("pro" . "05_Drawings\\DrawingData\\CivilSurvey")
    ("tin" . "02_ProjectData\\Surfaces")))
(setq *pfset-std-search-depth* 3)   ; parent levels to search up from the root

;;; --------------------------------------------------------------------------
;;; PFREPORT  (Hydraflow Storm Sewers .stm export)
;;; --------------------------------------------------------------------------
;;; The format was spec'd from Hydraflow_Reference\_Sampl.txt -- see
;;; pfreport/README.md for the field-by-field decode.  Everything here is a
;;; firm/plan-level constant; nothing in this block is derived from a drawing.

;;; DIRECTION CONVENTION -- the one load-bearing assumption in the export.
;;;   T   = station INCREASES upstream (sta 0 is the outfall end)
;;;   nil = station increases downstream
;;; Wrong value => EVERY pipe on every line reports an adverse slope, and
;;; pfr:validate says so by name.  It can never fail silently.
(setq *pfr-sta-upstream* T)

;;; Plan-coincidence tolerance for two structures to be ONE node.  Matched at
;;; each structure's CENTRE station (the .pro vertex pair's midpoint), never
;;; at the pipe-end vertices, so this stays tight -- same order as
;;; *pfi-junction-tol*.
(setq *pfr-node-tol* 2.0)          ; ft

;;; Invert continuity at a shared node (validation only, never derivation).
(setq *pfr-invert-tol* 0.02)       ; ft -- below this, inverts "match"
(setq *pfr-drop-max*   6.0)        ; ft -- a larger structure drop is reported

;;; Rim/ground reads.  Elevation label rows are drafter-filled TEXT drawn by
;;; PFLABEL at the top of the grid; the prefixes come from *pf-rule-table*.
;;; A row still reading *pf-elev-placeholder* counts as UNFILLED, not zero.
(setq *pfr-elev-prefixes* '("T.R." "T.G." "G.L."))
(setq *pfr-label-band*    50.0)    ; base model units (x sf) above the grid top
                                   ; that the elevation-row scan will look in
(setq *pfr-rim-eps-factor* 10.0)   ; x text height -- max |dX| from a structure's
                                   ; station line to claim one of its label rows

;;; Slope units in the .stm.  T = percent, nil = ft/ft.  The reference sample
;;; carries 0 for every line, so this is inferred from the Storm Sewers UI --
;;; one flip if a round trip disagrees.
(setq *pfr-slope-percent* T)

(setq *pfr-sigfigs* 7)             ; Hydraflow writes ~7 significant digits
(setq *pfr-line-type* "Cir")       ; circular; Rise = Span = size / 12
(setq *pfr-junction-loss* 0.15)    ; inert: the header turns auto-compute ON
(setq *pfr-nvalue-default* 0.013)
(setq *pfr-nvalues*                ; Manning's n by the record's material
  '(("RCP"    . 0.013)
    ("HDPE"   . 0.012)
    ("PVC"    . 0.010)
    ("DI"     . 0.013)
    ("CMP"    . 0.024)
    ("COPPER" . 0.011)))

;;; The global-settings block, verbatim file lines.  <NLINES> is the only
;;; substitution.  These are Hydraflow DESIGN settings, not model data --
;;; edit to the firm's standards and they ride every export.
(setq *pfr-header*
  '("\"Hydraflow Storm Sewers 2003\""
    "\"Metric Units? \",#FALSE#"
    "\"Total No. Lines = \",<NLINES>"
    "\"Starting HGL = \",0"
    "\"Return Period Index = \",2"
    "\"Min Cover = \",4"
    "\"Design Vel = \",2.5"
    "\"Min Slope = \",0"
    "\"Min Pipe Size = \",12"
    "\"Max Pipe Size = \",96"
    "\"Omit 21-inch pipes = \",#TRUE#"
    "\"Omit 27-inch pipes = \",#TRUE#"
    "\"Omit 33-inch pipes = \",#FALSE#"
    "\"Design Alignment = \",0"
    "\"N-Value of Inlets = \",.016"
    "\"Grate Design Depth = \",.3"
    "\"Composite C1 = \",.2"
    "\"Composite C2 = \",.5"
    "\"Composite C3 = \",.9"
    "\"Min. Starting Depth = \",\"Normal\""
    "\"Accumulate Known Qs = \",#TRUE#"
    "\"Use Inlet Captured Flows in System = \",#FALSE#"
    "\"Auto Compute Junct. Loss Coeff. = \",#TRUE#"
    "\"Supress Pipe Travel Time = \",#FALSE#"
    "\"Minimum Tc used to calc Intensity\",5"
    "\"Check for Inlet Control? = \",#FALSE#"
    "\"Using HDS-5 Method? = \",#FALSE#"))

;;; The trailer, verbatim.  RAINFALL IS NOT PFTOOLS DATA -- this is the
;;; reference file's NAMED curve (Portland 2, 40-7359), carried so the .stm
;;; opens and so the engineer sees which curve is loaded in Hydraflow's
;;; Rainfall tab.  Hydrology is exported zeroed, so nothing computed depends
;;; on it; PFREPORT prints a warning naming this curve on every export.
;;; Replace this block with the firm's own IDF export to change it.
(setq *pfr-trailer*
  '("\"IDF Curves\""
    "\"FHA\""
    "48.38522,57.28075,61.93248,65.07044,61.77916,54.94071,50.68927,45.9"
    "11.80001,12.20001,12.70001,12.90001,12.30001,11.00001,10.1,8.999998"
    ".8630495,.8590845,.8603584,.8417071,.799021,.7384071,.6961845,.6514508"
    "0,.01886,.01812,.02535,.03519,.04818,.06176,0"
    "4.24,2.82,1.93,1.21"
    "4.98,3.34,2.3,1.45"
    "5.23,3.52,2.45,1.55"
    "5.74,3.87,2.75,1.76"
    "6.34,4.28,3.1,2.02"
    "7.1,4.79,3.54,2.36"
    "7.67,5.16,3.88,2.63"
    "8.23,5.51,4.22,2.91"
    "\"IDF PORTLAND 2 (40-7359).IDF\""
    "#FALSE#,\"\",\"\""
    "#FALSE#,\"\",\"\""
    "\"Number of Parcel lines = \",0"
    "\"Number of Parcel circles = \",0"
    "0,0,0,0"
    "\"End of file\""))
(setq *pfr-idf-name* "IDF PORTLAND 2 (40-7359).IDF")   ; named in the warning


;;; --------------------------------------------------------------------------
;;; PF2SEW  --  Carlson Hydrology .SEW export
;;; --------------------------------------------------------------------------
;;; TUNABLES LIVE IN ONE TABLE ON PURPOSE.  *pfsew-opts* is a flat
;;; (KEY VALUE LABEL) list, not thirty named globals, because the planned home
;;; for these is a PFTools settings page / pfpalette tab -- and a data-driven
;;; table is one `foreach` away from a tile per row, where named globals would
;;; need a hand-written tile each.  pfsew:opt reads at EMIT time, never at load
;;; time, so changing a value takes effect on the next export with no reload.
;;; Anything a drafter might plausibly want to change belongs here; anything
;;; structural belongs in pf2sew.lsp.
;;;
;;; VALUES ARE STRINGS -- they are written into XML attributes verbatim, so
;;; what is typed here is what Carlson reads.  Keep Carlson's own spellings.
(setq *pfsew-opts*
  '(;; ---- file-level settings (the <SewerSettings> fragment) ---------------
    (network-type      "0"      "Network type (0 = storm)")
    (unit              "0"      "Units (0 = US feet)")
    (hydro-method      "0"      "Hydrology method (0 = Rational)")
    (comp-method       "0"      "Computation method")
    (program           "Carlson Software 2025" "Program string")
    (debug             "7"      "Debug flag Carlson writes")
    ;; ---- number grammar ---------------------------------------------------
    (coord-decimals    "4"      "Decimal places on coordinates")
    (elev-decimals     "4"      "Decimal places on elevations")
    ;; ---- pipe defaults ----------------------------------------------------
    (pipe-shape        "0"      "Pipe shape (0 = circular)")
    (pipe-thickness    "1"      "Wall thickness, inches")
    (barrel-num        "1"      "Barrels per pipe")
    (material-default  "RCP"    "Material when the record has none")
    ;; ---- structure defaults ----------------------------------------------
    (node-prefix       "CSMH"   "SewerNodeID prefix")
    (junction-method   "3"      "Junction loss method")
    (junction-coeff    "0"      "Junction loss coefficient")
    (sump              "0"      "Structure sump depth")
    (rim-raised        "0"      "Rim raised height")
    (skew-angle        "90"     "Symbol skew angle")
    ;; ---- hydrology: written at CARLSON'S DEFAULTS, never fabricated -------
    ;; PFTools does not hold drainage data.  These are the values Carlson's own
    ;; dialog writes for an un-entered structure, so the model opens and
    ;; computes capacity while the drainage side reads visibly unentered.
    (runoff-cf         "0.5"    "Rational Cf (Carlson default)")
    (scs-cn            "50"     "SCS curve number (Carlson default)")
    (scs-swamp         "1"      "SCS swamp factor (Carlson default)")
    (pave-lon-slope    "0.01"   "Pavement longitudinal slope")
    (pave-cross-slope  "0.02"   "Pavement cross slope")
    (pave-mannings     "0.013"  "Pavement Manning's n")
    (inlet-profile     "1"      "Inlet profile flag")
    (gutter-width      "3"      "Gutter width")
    (grate-length      "3"      "Grate length")
    (grate-width       "2"      "Grate width")
    (grate-weir-c      "3"      "Grate weir coefficient")
    (grate-orifice-c   "0.67"   "Grate orifice coefficient")
    (grate-splash-v    "1"      "Grate splash-over velocity")
    (curb-length       "3"      "Curb throat length")
    (curb-weir-c       "2.3"    "Curb weir coefficient")
    (curb-orifice-c    "0.67"   "Curb orifice coefficient")))

;;; --------------------------------------------------------------------------
;;; Carlson library mapping  --  ORDERED, FIRST MATCH WINS, same token lists as
;;; *pf-rule-table* above.  Deliberately a PARALLEL table, not extra columns on
;;; *pf-rule-table*: that one is load-bearing for every sheet label PFLABEL
;;; draws, and export concerns do not belong in the drafting path.  Adding a
;;; row here can never change a label.
;;;
;;;   (TOKENS  STRUCT-ID  STRUCT-TYPE  WIDTH  GEOMETRY-XML  INLET-ID  INLET-TYPE  SYMBOL)
;;;
;;; STRUCT-ID / INLET-ID / SYMBOL are CARLSON'S OWN library names.  Only four
;;; are confirmed present on the target install (MH1, Outfall-Funnel,
;;; Combo-Grade, INLET3 -- from Carlson_References/STORM_CA.sew).  Every row
;;; below resolves to one of those four ON PURPOSE: a file that opens beats a
;;; file naming a library entry Carlson does not have.  Refine per row once the
;;; real library is enumerated -- see pf2sew/README.md, "Open issues".
;;; INLET-ID nil = a junction structure that captures no flow.
(setq *pfsew-type-map*
  '((("CBI" "MH") "MH1" "2" "4"
     "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
     "Combo-Grade" "3" "INLET3")
    (("DBI" "MH") "MH1" "2" "4"
     "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
     "Combo-Grade" "3" "INLET3")
    (("SMH")      "MH1" "2" "4"
     "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
     nil nil "")
    (("DMH")      "MH1" "2" "4"
     "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
     nil nil "")
    (("CBI")      "MH1" "2" "4"
     "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
     "Combo-Grade" "3" "INLET3")
    (("DBI")      "MH1" "2" "4"
     "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
     "Combo-Grade" "3" "INLET3")
    (("MH")       "MH1" "2" "4"
     "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
     nil nil "")
    (("HDWL")     "Outfall-Funnel" "0" "0"
     "<Funnel Length=\"4\" InWidth=\"2\" OutWidth=\"3\"/>"
     nil nil "")))

;;; The row used when a structure's block matches no rule above.  A network
;;; still exports; the structure is a plain junction and the run says so.
(setq *pfsew-type-fallback*
  '(NIL "MH1" "2" "4"
    "<Manhole TaperFormat=\"0\" BottomDia=\"4\" TopDia=\"4\" TaperOffset=\"0\" FixedTaperHeight=\"0\" Thick=\"8\"/>"
    nil nil ""))

(princ "\npftools-cfg.lsp loaded (V4 configuration).")
(princ)
;;; ==========================================================================
;;; end of pftools-cfg.lsp
;;; ==========================================================================
