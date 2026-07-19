;;; ==========================================================================
;;; pftools-cfg.lsp  --  PFTools V4 configuration
;;; --------------------------------------------------------------------------
;;; EVERY tunable in the suite lives HERE and nowhere else.  This file is
;;; meant to be edited in a text editor; no code below, only constants.
;;;
;;; Loads FIRST -- every other file reads these.
;;;
;;; Do not confuse this with pfsettings.lsp:
;;;   pftools-cfg.lsp  = the FIRM'S constants (templates, maps, sizes) --
;;;                      edited here, by hand, rarely.
;;;   pfsettings.lsp   = the USER'S persisted state (last-used paths, dialog
;;;                      values, project root) -- written by the tools.
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
(setq *pfx-xing-text-layer* "PF-XING-TEXT") ; vertical crossing station text
(setq *pfx-zoom-pause* 1.5)             ; seconds to pause on each inserted block
                                        ; (PFXLABEL verification pause -- boss ask)

;;; --------------------------------------------------------------------------
;;; Plan-geometry sampling  (crossing discovery)
;;; --------------------------------------------------------------------------
(setq *pfx-sample-step* 2.0)   ; ft -- .cl walk interval (arcs followed)
(setq *pfx-refine-step* 0.1)   ; ft -- re-sample interval near a hit

;;; --------------------------------------------------------------------------
;;; PFINVERT  (invert labels at structures)
;;; --------------------------------------------------------------------------
;;; Text base Y = lowest invert present MINUS this offset.  FIXED model units;
;;; deliberately NOT scaled by sf (see the V4 handoff, section 4.10).
(setq *pfi-invert-offset* 5.0)

;;; Grade-break bracket (pfi:invert-bracket): the structure's in/out inverts
;;; are read at the first grade break each side of the station -- the
;;; structure edge -- so the bracket auto-widens with structure size.
(setq *pfi-scan-window* 25.0)  ; ft each side -- must not reach the next structure
(setq *pfi-scan-step*   0.5)   ; ft -- .pro sampling interval for the walk
(setq *pfi-grade-tol*   0.05)  ; dslope (ft/ft) that reads as a break; catches
                               ; drop faces, ignores mild run-to-run grade
                               ; changes (the flat-case fallback covers those)

;;; --------------------------------------------------------------------------
;;; Anchor & ledger  (pfanchor.lsp)
;;; --------------------------------------------------------------------------
(setq *pfa-block-name*  "PF-GRIDANCHOR")
(setq *pfa-layer*       "PF-ANCHOR")      ; created NO-PLOT, unlocked
(setq *pfa-dict-name*   "PFXLEDGER")
(setq *pfa-schema-ver*  3)                ; schema 3 = the V4 record (FILES/EXTENTS/STATUS/SCOPE/PASS_/X_); matches pfanchor + README
(setq *pfa-att-tags*    '("LINE" "UTIL" "STA0" "DATUM" "HPLOT" "VPLOT"))
(setq *pfa-att-height*  0.8)
(setq *pfa-att-gap*     1.6)
(setq *pfa-xing-layer*  "PF-XING")        ; crossing station lines (recon scans this)
(setq *pfa-recon-eps*   1.0e-4)           ; float round-trip tolerance
(setq *pfa-key-tol*     2.0)              ; content-key station drift tolerance
(setq *pfa-probe-tol*   0.05)             ; grid-LINE-near-corner sanity probe
(setq *pfa-grid-layers* "PF-GRID-MJR,PF-GRID-MNR,PF-HBOX")

;;; --------------------------------------------------------------------------
;;; Carlson-drawn grid sheet layers
;;; Confirmed 2026-07-17: these ARE the layers Carlson draws the grids on.
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

(princ "\npftools-cfg.lsp loaded (V4 configuration).")
(princ)
;;; ==========================================================================
;;; end of pftools-cfg.lsp
;;; ==========================================================================
