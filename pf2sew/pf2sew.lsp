;;; ==========================================================================
;;; pf2sew.lsp  --  C:PF2SEW : Carlson Hydrology .SEW export
;;;                  Dialog: pfsew_run.
;;; Load position 12 of 13: after pfreport, before pfpalette.
;;; Model, API, and invariants: see README.md beside this file.
;;;
;;; SYSTEM-scoped and entirely READ-ONLY on the drawing, exactly like
;;; PFREPORT: no anchor pick, no pfs:choose-or-place, no undo group, no pass
;;; ledger, no STATUS update.  The .sew on disk is the only write.
;;;
;;; THE GATHER IS PFREPORT'S.  This file deliberately calls pfr:line-pipes,
;;; pfr:build-nodes, pfr:order and pfr:validate rather than carrying its own
;;; copy -- the node/pipe model those build is already the shape .SEW wants
;;; (see ../pf2sew.md section 7).  Load order permits it: pfreport is above
;;; this file.  Hoisting that gather into pf: engine code is still the right
;;; end state and is ticketed in ../pf2sew.md section 8 step 1; doing it BEFORE
;;; either command has run in CAD would put two unverified things in flight.
;;;
;;; TUNABLES ARE NOT HERE.  Everything a drafter might want to change lives in
;;; *pfsew-opts* / *pfsew-type-map* in pftools-cfg.lsp, read at emit time
;;; through pfsew:opt.  That is what makes a future settings page or pfpalette
;;; tab a data-driven loop over one table instead of an edit to this file.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Options
;;; ==========================================================================
;;; Read at EMIT time, never captured at load time, so a settings page that
;;; setq's a row takes effect on the next export with no reload.

;; (pfsew:opt key) -> the option's value string
;;   A missing key is a programming error, not a user error: it returns "" and
;;   says so once, rather than writing the symbol name into the XML.
(defun pfsew:opt (key / row)
  (if (setq row (assoc key *pfsew-opts*))
    (cadr row)
    (progn (pfr:warn (strcat "PF2SEW option '" (vl-princ-to-string key)
                             "' is not in *pfsew-opts* -- written as empty."))
           "")))

;; (pfsew:opt-num key) -> the option's value as a number
(defun pfsew:opt-num (key) (atof (pfsew:opt key)))

;; (pfsew:set-opt key val) -> the updated *pfsew-opts*
;;   The seam a settings page / pfpalette tab writes through.  Values are
;;   always strings: they go into XML attributes verbatim.
;;   KEEP though the dead-code gate names it: Version 5.1.md §7 names this
;;   options seam as the hydraulics attach point.
(defun pfsew:set-opt (key val / row)
  (if (setq row (assoc key *pfsew-opts*))
    (setq *pfsew-opts*
          (subst (list key val (caddr row)) row *pfsew-opts*)))
  *pfsew-opts*)


;;; ==========================================================================
;;; SECTION 2  --  Carlson library mapping
;;; ==========================================================================
;;; One structure's block name -> one row of *pfsew-type-map*.  Keyed on the
;;; same token lists as *pf-rule-table*, through the same pf:rule-for matcher,
;;; so "which rule fires" cannot drift between the sheet label and the export.

(defun pfsew:tm-struct-id (row) (nth 1 row))
(defun pfsew:tm-struct-ty (row) (nth 2 row))
(defun pfsew:tm-width     (row) (nth 3 row))
(defun pfsew:tm-geom      (row) (nth 4 row))
(defun pfsew:tm-inlet-id  (row) (nth 5 row))
(defun pfsew:tm-inlet-ty  (row) (nth 6 row))
(defun pfsew:tm-symbol    (row) (nth 7 row))

;; (pfsew:type-for blk) -> a *pfsew-type-map* row (never nil)
;;   An unmatched or missing block falls back to a plain junction structure.
;;   The caller warns; the export continues, because a network that opens with
;;   one structure typed wrong is more useful than no network at all.
(defun pfsew:type-for (blk / found)
  (if (and blk (setq found (pf:rule-for blk *pfsew-type-map*)))
    found
    *pfsew-type-fallback*))

;; (pfsew:desc-for blk) -> the *pf-rule-table* TYPE string, for Desc=
;;   The sheet label's own words, so the model and the plan set read alike.
(defun pfsew:desc-for (blk / rule)
  (if (and blk (setq rule (pf:rule-for blk *pf-rule-table*)))
    (nth 2 rule)
    ""))


;;; ==========================================================================
;;; SECTION 3  --  XML grammar
;;; ==========================================================================
;;; Carlson writes 17-significant-digit doubles.  Those are a writer artifact
;;; (pf2sew.md section 2); clean fixed-decimal numbers parse identically, and
;;; they make an export diffable against the sheet, which 17 digits never are.
;;; rtos mode 2 is pinned decimal -- correct in Architectural drawings too.

;; (pfsew:num v dp) -> v as a fixed-decimal string
(defun pfsew:num (v dp)
  (if (numberp v) (rtos (float v) 2 (fix dp)) "0"))

;; (pfsew:xy v) / (pfsew:elev v) -> a coordinate / an elevation, at the
;;   configured precision
(defun pfsew:xy   (v) (pfsew:num v (pfsew:opt-num 'coord-decimals)))
(defun pfsew:elev (v) (pfsew:num v (pfsew:opt-num 'elev-decimals)))

;; (pfsew:esc s) -> s with the five XML metacharacters escaped
;;   Structure IDs come from drawing text, so this is not theoretical: an
;;   unescaped & in a block-derived ID would make the file unreadable.
(defun pfsew:esc (s)
  (if (null s)
    ""
    (progn
      (setq s (pf:subst-token s "&" "&amp;"))
      (setq s (pf:subst-token s "<" "&lt;"))
      (setq s (pf:subst-token s ">" "&gt;"))
      (setq s (pf:subst-token s "\"" "&quot;"))
      (pf:subst-token s "'" "&apos;"))))

;; (pfsew:att name val) -> ` name="val"`   val is escaped
(defun pfsew:att (name val)
  (strcat " " name "=\"" (pfsew:esc val) "\""))

;; (pfsew:atts pairs) -> the concatenation of (name . val) pairs
(defun pfsew:atts (pairs / out e)
  (setq out "")
  (foreach e pairs (setq out (strcat out (pfsew:att (car e) (cdr e)))))
  out)

;; (pfsew:pad n) -> n spaces of indent
(defun pfsew:pad (n / s)
  (setq s "")
  (repeat (fix n) (setq s (strcat s "    ")))
  s)


;;; ==========================================================================
;;; SECTION 4  --  The .sew view of a node
;;; ==========================================================================
;;; PFREPORT's node table is (xy id sta line rim blk) and its pipes carry
;;; 'dn-node / 'up-node indices into it.  A .SEW structure needs three things
;;; that table does not hold: a stable ID string, the invert AT the structure,
;;; and the junction drop through it.  All three are derived here; nothing is
;;; read from the drawing a second time.

;; (pfsew:node-id i) -> "CSMH3"   the SewerNodeID for node index i
(defun pfsew:node-id (i) (strcat (pfsew:opt 'node-prefix) (itoa i)))

;; (pfsew:center-invs pipes) -> pipes with 'dn-cinv / 'up-cinv stamped
;;   Carlson stores no pipe length and no slope -- there is no such attribute on
;;   <SewerPipe> -- so it derives both, measuring between STRUCTURE CENTRES, not
;;   between the drafted faces the .pro vertices sit on.  Handing it face inverts
;;   over a centre-to-centre run reports the authored slope flat by the ratio of
;;   the two lengths.  Each end's invert is carried along the pipe's OWN slope
;;   from its face vertex to the node's centre station, so the slope Carlson
;;   derives is the slope that was drafted.
;;
;;   Length still reads half a structure long at each end.  That is the
;;   centre-to-centre convention doing what it says, and unlike the inside-edge
;;   reduction it needs no structure footprint -- which is why it is the setting
;;   to hold the target install to while *pfsew-type-map*'s widths are Carlson
;;   defaults rather than the real inlets.
;;
;;   THE CENTRE STATION COMES FROM THE PIPE'S OWN 'dn-nd / 'up-nd, NEVER FROM THE
;;   MERGED NODE TABLE.  A shared node keeps the station of whichever line first
;;   created it, and that station is in THAT line's stationing.  Reading it for a
;;   branch pipe subtracts a trunk station from a branch station and extrapolates
;;   the invert over hundreds of feet of phantom run -- every branch came out ten
;;   to thirty feet high, and the downstream end read above the upstream one.
;;   The pipe's own node alist carries the same structure's centre in the same
;;   stationing as 'dn-sta / 'up-sta, which is the only pair that can be
;;   subtracted.  (Found 2026-08-05, on the first CAD export.)
(defun pfsew:center-invs (pipes / out p run s dnc upc)
  (setq out '())
  (foreach p pipes
    (setq run (- (pfr:g 'up-sta p) (pfr:g 'dn-sta p))
          s   (if (equal run 0.0 1e-8)
                0.0
                (/ (- (pfr:g 'up-inv p) (pfr:g 'dn-inv p)) run))
          dnc (+ (pfr:g 'dn-inv p)
                 (* s (- (pfr:g 'sta (pfr:g 'dn-nd p))
                         (pfr:g 'dn-sta p))))
          upc (+ (pfr:g 'up-inv p)
                 (* s (- (pfr:g 'sta (pfr:g 'up-nd p))
                         (pfr:g 'up-sta p))))
          p   (pfr:p 'dn-cinv dnc p)
          p   (pfr:p 'up-cinv upc p)
          out (cons p out)))
  (reverse out))

;; (pfsew:node-invs pipes i) -> (out-inv . in-inv)   either may be nil
;;   out-inv = the invert of the pipe LEAVING this structure (its upstream
;;   end sits here).  in-inv = the LOWEST invert arriving.  Both read the
;;   CENTRE inverts, so Base and JunctionDrop stay on the same datum as the
;;   pipe elevations they are derived from.  pfr:validate reads the face
;;   inverts and still agrees on which pipe is lower -- the extrapolation is
;;   monotonic -- but the two no longer report the same NUMBER.
(defun pfsew:node-invs (pipes i / out-up dn-in p)
  (setq out-up nil dn-in nil)
  (foreach p pipes
    (if (= (pfr:g 'up-node p) i) (setq out-up (pfr:g 'up-cinv p)))
    (if (and (= (pfr:g 'dn-node p) i)
             (or (null dn-in) (< (pfr:g 'dn-cinv p) dn-in)))
      (setq dn-in (pfr:g 'dn-cinv p))))
  (cons out-up dn-in))

;; (pfsew:node-base pipes i) -> the structure's Base elevation
;;   The OUTGOING invert where there is one, the arriving invert at the
;;   outfall.  Written explicitly rather than left for Carlson to infer --
;;   see pf2sew.md section 2.  Where a structure has both and they differ,
;;   Base carries the outgoing one and the difference goes to JunctionDrop.
(defun pfsew:node-base (pipes i / v)
  (setq v (pfsew:node-invs pipes i))
  (cond ((car v)) ((cdr v)) (T 0.0)))

;; (pfsew:node-drop pipes i) -> the junction drop through the structure, ft
;;   0.0 unless the structure has both an arriving and a leaving pipe and
;;   their inverts differ.  A designed drop is data, not an error: pfr:validate
;;   has already reported anything implausible.
(defun pfsew:node-drop (pipes i / v d)
  (setq v (pfsew:node-invs pipes i))
  (if (and (car v) (cdr v))
    (progn (setq d (- (cdr v) (car v)))
           (if (> (abs d) *pfr-invert-tol*) d 0.0))
    0.0))

;; (pfsew:node-order pipes nodes) -> node indices, outfall first
;;   pfr:order has already numbered the pipes breadth-first from the outfall,
;;   so walking them in that order and taking each end the first time it is
;;   seen reproduces Carlson's own CSMH0-at-the-outfall numbering.  Any node
;;   no pipe reaches cannot exist -- pfr:order would have failed first -- but
;;   the tail sweep makes that independent of this function.
(defun pfsew:node-order (pipes nodes / seen out sorted p i)
  (setq sorted (vl-sort pipes '(lambda (a b) (< (pfr:g 'no a) (pfr:g 'no b))))
        seen '() out '())
  (foreach p sorted
    (foreach i (list (pfr:g 'dn-node p) (pfr:g 'up-node p))
      (if (not (member i seen)) (setq seen (cons i seen) out (cons i out)))))
  (setq i 0)
  (foreach p nodes
    (if (not (member i seen)) (setq out (cons i out)))
    (setq i (1+ i)))
  (reverse out))

;; (pfsew:system-of nd) -> the utility/line name for System=
;;   The line the structure was read on; "CA" out of "CA-3".
(defun pfsew:system-of (nd / id pos)
  (setq id (pfr:nd-id nd))
  (cond
    ((or (null id) (= id "")) (if (pfr:nd-line nd) (pfr:nd-line nd) ""))
    ((setq pos (vl-string-search "-" id)) (substr id 1 pos))
    (T id)))

;; (pfsew:name-of nd i) -> the structure's Name=
;;   PFLABEL's combined ID, so the model and the sheet call it the same thing.
;;   A structure PFLABEL never labelled falls back to its node id, which is at
;;   least unique.
(defun pfsew:name-of (nd i)
  (if (and (pfr:nd-id nd) (/= (pfr:nd-id nd) ""))
    (pfr:nd-id nd)
    (pfsew:node-id i)))


;;; ==========================================================================
;;; SECTION 5  --  Emit: the four fragments
;;; ==========================================================================
;;; FOUR CONCATENATED FRAGMENTS, NO XML DECLARATION AND NO SINGLE ROOT.  This
;;; is not an oversight to tidy up later: Carlson's reader wants
;;; <SewerSettings>, <SewerNetwork>, <Graph> as siblings at top level, and
;;; wrapping them in a root element is expected to break it.

;; (pfsew:settings) -> the <SewerSettings> fragment, a list of lines
(defun pfsew:settings ()
  (list
    (strcat "<SewerSettings"
            (pfsew:atts (list (cons "NetworkType" (pfsew:opt 'network-type))
                              (cons "Unit"        (pfsew:opt 'unit))))
            ">")
    (strcat (pfsew:pad 1) "<HydraulicCalc"
            (pfsew:atts
              (list (cons "HydroMethod"       (pfsew:opt 'hydro-method))
                    (cons "ComputationMethod" (pfsew:opt 'comp-method))))
            "/>")
    (strcat (pfsew:pad 1) "<Libraries/>")
    "</SewerSettings>"
    ""))

;; (pfsew:hydro-inlet tm) -> the <HydroInlet> block | nil for a junction
;;   Geometry at Carlson's defaults.  PFTools does not hold gutter or grate
;;   dimensions, and the values here are the ones Carlson's own dialog writes
;;   for an un-entered inlet -- so the model computes, and nothing has been
;;   invented that a reader could mistake for a measurement.
(defun pfsew:hydro-inlet (tm / out)
  (if (null (pfsew:tm-inlet-id tm))
    nil
    (list
      (strcat (pfsew:pad 3) "<HydroInlet"
              (pfsew:atts
                (list (cons "ID"          (pfsew:tm-inlet-id tm))
                      (cons "Desc"        "")
                      (cons "Type"        (pfsew:tm-inlet-ty tm))
                      (cons "ProfileType" (pfsew:opt 'inlet-profile))
                      (cons "Symbol"      (pfsew:tm-symbol tm))
                      (cons "Unit"        (pfsew:opt 'unit))
                      (cons "InletBottomDepth" "0")))
              ">")
      (strcat (pfsew:pad 4) "<Gutter"
              (pfsew:atts
                (list (cons "Depression"      "0")
                      (cons "Slope"           "0")
                      (cons "Width"           (pfsew:opt 'gutter-width))
                      (cons "LocalDepression" "0")
                      (cons "useSlope"        "false")))
              "/>")
      (strcat (pfsew:pad 4) "<Grate"
              (pfsew:atts
                (list (cons "Type"            "0")
                      (cons "Length"          (pfsew:opt 'grate-length))
                      (cons "Width"           (pfsew:opt 'grate-width))
                      (cons "CloggingRatio"   "0")
                      (cons "OpeningRatio"    "1")
                      (cons "WeirCoeff"       (pfsew:opt 'grate-weir-c))
                      (cons "OrificeCoeff"    (pfsew:opt 'grate-orifice-c))
                      (cons "SplashVelocity"  (pfsew:opt 'grate-splash-v))
                      (cons "isCircularGrate" "false")))
              "/>")
      (strcat (pfsew:pad 4) "<Curb"
              (pfsew:atts
                (list (cons "ThroatType"    "0")
                      (cons "Length"        (pfsew:opt 'curb-length))
                      (cons "OpeningHeight" "0")
                      (cons "InclinedAngle" "0")
                      (cons "WeirCoeff"     (pfsew:opt 'curb-weir-c))
                      (cons "OrificeCoeff"  (pfsew:opt 'curb-orifice-c))))
              "/>")
      (strcat (pfsew:pad 3) "</HydroInlet>"))))

;; (pfsew:structure i nd pipes) -> the <SewerStructure> block, a list of lines
(defun pfsew:structure (i nd pipes / tm blk base rim drop out)
  (setq blk  (pfr:nd-blk nd)
        tm   (pfsew:type-for blk)
        base (pfsew:node-base pipes i)
        drop (pfsew:node-drop pipes i)
        rim  (if (pfr:nd-rim nd) (pfr:nd-rim nd) 0.0))
  (setq out
    (list
      (strcat (pfsew:pad 2) "<SewerStructure"
              (pfsew:atts
                (list (cons "Name"        (pfsew:name-of nd i))
                      (cons "SewerNodeID" (pfsew:node-id i))
                      (cons "System"      (pfsew:system-of nd))
                      (cons "Desc"        (pfsew:desc-for blk))
                      (cons "Line"        "")
                      (cons "Type"        (pfsew:tm-struct-ty tm))
                      (cons "Length"      "0")
                      (cons "Width"       (pfsew:tm-width tm))))
              ">")
      ;; Z is the rim: what Carlson's own dialog writes, and the only
      ;; elevation at a structure PFTools reads rather than derives.
      (strcat (pfsew:pad 3) "<Center"
              (pfsew:atts
                (list (cons "X" (pfsew:xy   (car  (pfr:nd-xy nd))))
                      (cons "Y" (pfsew:xy   (cadr (pfr:nd-xy nd))))
                      (cons "Z" (pfsew:elev rim))))
              "/>")
      (strcat (pfsew:pad 3) "<Elevation"
              (pfsew:atts
                (list (cons "Base"             (pfsew:elev base))
                      (cons "Rim"              (pfsew:elev rim))
                      (cons "RimRaisedHeight"  (pfsew:opt 'rim-raised))
                      (cons "JunctionDrop"     (pfsew:elev drop))
                      (cons "Sump"             (pfsew:opt 'sump))
                      (cons "Underdrain"       "0")
                      (cons "RiserNumber"      "0")))
              "/>")
      (strcat (pfsew:pad 3) "<Symbol"
              (pfsew:atts
                (list (cons "symbol2D"                (pfsew:tm-symbol tm))
                      (cons "symbol3D"                "")
                      (cons "symbolProfileFrontView"  "")
                      (cons "symbolProfileSideView"   "")
                      (cons "RotateType"              "0")
                      (cons "SizeType"                "1")
                      (cons "AzimuthAngle"            "0")
                      (cons "SkewAngle"  (pfsew:opt 'skew-angle))))
              "/>")
      (strcat (pfsew:pad 3) "<JunctionLoss"
              (pfsew:atts
                (list (cons "Method"      (pfsew:opt 'junction-method))
                      (cons "Coefficient" (pfsew:opt 'junction-coeff))))
              "/>")
      (strcat (pfsew:pad 3) "<OutfallTailwater Elevation=\"0\"/>")
      ;; DRAINAGE IS NOT FABRICATED.  Area and flow are 0 -- visibly unentered
      ;; in Carlson.  Cf / CN / swamp factor are Carlson's own defaults for an
      ;; un-entered structure, inert while Area is 0, and present only so the
      ;; model opens without complaint.
      (strcat (pfsew:pad 3) "<DrainageData"
              (pfsew:atts
                (list (cons "Type"           "0")
                      (cons "Area"           "0")
                      (cons "CatchmentFlow"  "0")
                      (cons "Tc"             "0")
                      (cons "ActualTc"       "0")
                      (cons "Cf"             (pfsew:opt 'runoff-cf))
                      (cons "ScsCN"          (pfsew:opt 'scs-cn))
                      (cons "ScsSwampFactor" (pfsew:opt 'scs-swamp))))
              "/>")
      (strcat (pfsew:pad 3) "<Pavement"
              (pfsew:atts
                (list (cons "LonSlope"     (pfsew:opt 'pave-lon-slope))
                      (cons "CrossSlope"   (pfsew:opt 'pave-cross-slope))
                      (cons "ManningsN"    (pfsew:opt 'pave-mannings))
                      (cons "InletProfile" (pfsew:opt 'inlet-profile))))
              "/>")))
  (setq out (append out (pfsew:hydro-inlet tm)))
  (append out
    (list
      (strcat (pfsew:pad 3) "<SwrStruct"
              (pfsew:atts (list (cons "ID"   (pfsew:tm-struct-id tm))
                                (cons "Desc" "")
                                (cons "Type" (pfsew:tm-struct-ty tm))))
              ">")
      (strcat (pfsew:pad 4) (pfsew:tm-geom tm))
      (strcat (pfsew:pad 3) "</SwrStruct>")
      (strcat (pfsew:pad 2) "</SewerStructure>"))))

;; (pfsew:pipe p) -> the <SewerPipe> block, a list of lines
;;   Rise is INCHES in this format, and pf:pipe-at already returns the nominal
;;   size in inches -- so unlike the Hydraflow path there is no division here.
(defun pfsew:pipe (p / size mat wall)
  (setq size (pfr:g 'size p)
        mat  (if (and (pfr:g 'mat p) (/= (pfr:g 'mat p) ""))
               (pfr:g 'mat p)
               (pfsew:opt 'material-default))
        ;; Real wall when the material table carries one for this nominal;
        ;; the flat pipe-thickness constant is the fallback, as before.
        wall (pf:mat-wall mat size))
  (list
    (strcat (pfsew:pad 2) "<SewerPipe"
            (pfsew:atts
              (list (cons "Name" (strcat (pfr:g 'line p) "-"
                                         (itoa (pfr:g 'no p))))
                    (cons "Desc" "")
                    (cons "DownstreamStructureID"
                          (pfsew:node-id (pfr:g 'dn-node p)))
                    (cons "UpstreamStructureID"
                          (pfsew:node-id (pfr:g 'up-node p)))))
            ">")
    (strcat (pfsew:pad 3) "<Pipe"
            (pfsew:atts
              (list (cons "Shape"         (pfsew:opt 'pipe-shape))
                    (cons "Material"      mat)
                    (cons "Rise"          (pfsew:num (if size size 0) 0))
                    (cons "Width"         "0")
                    (cons "Thickness"     (if wall
                                            (pfsew:num wall 2)
                                            (pfsew:opt 'pipe-thickness)))
                    (cons "ManningsValue" (rtos (pf:mat-n mat) 2 4))
                    (cons "BarrelNum"     (pfsew:opt 'barrel-num))))
            "/>")
    ;; The .pro vertices carried to the STRUCTURE CENTRES -- pfsew:center-invs.
    ;; Length and slope are NOT stored: Carlson derives both, and it measures
    ;; from the centres, so that is the datum the inverts have to be on.
    (strcat (pfsew:pad 3) "<Elevation"
            (pfsew:atts
              (list (cons "Downstream" (pfsew:elev (pfr:g 'dn-cinv p)))
                    (cons "Upstream"   (pfsew:elev (pfr:g 'up-cinv p)))))
            "/>")
    (strcat (pfsew:pad 2) "</SewerPipe>")))

;; (pfsew:graph pipes nodes) -> the <Graph> fragment, a list of lines
;;   One <LINE> per pipe, centre to centre.  This is the plan-view geometry
;;   Carlson draws; it uses the STRUCTURE centres, not the pipe-end vertices,
;;   which sit half a structure away on each side.
(defun pfsew:graph (pipes nodes / out p dn up)
  (setq out (list "<Graph>"))
  (foreach p pipes
    (setq dn (pfr:nd-xy (nth (pfr:g 'dn-node p) nodes))
          up (pfr:nd-xy (nth (pfr:g 'up-node p) nodes)))
    (setq out (cons (strcat (pfsew:pad 1) "<LINE"
                            (pfsew:atts
                              (list (cons "X_From" (pfsew:xy (car  dn)))
                                    (cons "Y_From" (pfsew:xy (cadr dn)))
                                    (cons "X_To"   (pfsew:xy (car  up)))
                                    (cons "Y_To"   (pfsew:xy (cadr up)))))
                            "/>")
                    out)))
  (reverse (cons "</Graph>" out)))


;;; ==========================================================================
;;; SECTION 6  --  The writer
;;; ==========================================================================

;; (pfsew:write file pipes nodes) -> T | nil
(defun pfsew:write (file pipes nodes / f l p i order sorted)
  (if (null (setq f (open file "w")))
    (progn (prompt (strcat "\nCould not open " file " for writing.")) nil)
    (progn
      ;; Once, before anything reads an invert: every consumer below wants the
      ;; centre datum, and pfr's records carry the faces.
      (setq pipes (pfsew:center-invs pipes))
      (foreach l (pfsew:settings) (write-line l f))
      (write-line (strcat "<SewerNetwork"
                          (pfsew:atts
                            (list (cons "Debug"   (pfsew:opt 'debug))
                                  (cons "Program" (pfsew:opt 'program))))
                          ">")
                  f)
      (write-line (strcat (pfsew:pad 1) "<SewerStructures>") f)
      (setq order (pfsew:node-order pipes nodes))
      (foreach i order
        (foreach l (pfsew:structure i (nth i nodes) pipes) (write-line l f)))
      (write-line (strcat (pfsew:pad 1) "</SewerStructures>") f)
      (write-line (strcat (pfsew:pad 1) "<SewerPipes>") f)
      (setq sorted
            (vl-sort pipes '(lambda (a b) (< (pfr:g 'no a) (pfr:g 'no b)))))
      (foreach p sorted (foreach l (pfsew:pipe p) (write-line l f)))
      (write-line (strcat (pfsew:pad 1) "</SewerPipes>") f)
      (write-line "</SewerNetwork>" f)
      (write-line "" f)
      (foreach l (pfsew:graph sorted nodes) (write-line l f))
      (close f)
      T)))


;;; ==========================================================================
;;; SECTION 7  --  The run dialog  (pfsew_run)
;;; ==========================================================================
;;; Candidates are PFREPORT's: an ANCHORED registry entry with a .cl and an
;;; _INV .pro.  Same rule, same exclusions, named on the command line -- a
;;; line that cannot be exported is never silently missing.

;; (pfsew:sys-name sys) -> "CA-CB"   the joined member names
(defun pfsew:sys-name (sys)
  (pf:join (mapcar 'cadr sys) "-"))

;; (pfsew:sys-row sys) -> the list_box line for one system
(defun pfsew:sys-row (sys)
  (strcat (pfset:pad (car (car sys)) 11)
          (pfset:pad (pfsew:sys-name sys) 32)
          (itoa (length sys))))

(defun pfsew:rd-sel ( / s i)
  (setq s (get_tile "sw_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select a system to export.")
    (progn
      (setq i (car (read (strcat "(" s ")"))))
      (setq sw-res (nth i sw-rows))
      (done_dialog 1))))

;; (pfsew:run-dialog sw-rows) -> the chosen system's registry rows | nil
;;   sw-rows is a list of SYSTEMS (pfa:line-systems), each itself a list of
;;   registry rows.  One system per export, so the list is single-select and
;;   the old Export All is gone: two systems are two hydraulic models and two
;;   files, never one .sew.
(defun pfsew:run-dialog (sw-rows / dcl_id sw-res r result)
  (setq sw-res nil dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfsew_run" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the export dialog.") nil)
      (progn
        (set_tile "sw_title" "PF2SEW -- Carlson Hydrology (.sew) export")
        (start_list "sw_list")
        (foreach r sw-rows (add_list (pfsew:sys-row r)))
        (end_list)
        (set_tile "sw_count"
                  (strcat (itoa (length sw-rows))
                          " system(s) found.  Pick one."))
        (set_tile "error" "")
        (action_tile "sw_sel" "(pfsew:rd-sel)")
        (action_tile "cancel" "(done_dialog 0)")
        (action_tile "help"
          (strcat "(pfset:help \"Each row is ONE hydraulic system -- trunk plus "
                  "every branch -- grouped automatically from the structures "
                  "the lines share.  A line that shares no structure is a "
                  "system of one and is still listed.  Storm and sanitary "
                  "never merge, so a shared casting appears in both."
                  "\\n\\nStructures, pipes and inverts come from each line's "
                  "bound _INV .pro; pipe sizes from its _TOP .pro (the Crown "
                  "column above); plan coordinates from its .cl; rim "
                  "elevations are READ from the drafter-filled elevation rows "
                  "PFLABEL drew at the top of the grid.\\n\\nStructure and "
                  "inlet types map from the block name through the same rule "
                  "table that writes the sheet label.\\n\\nDRAINAGE AREAS ARE "
                  "NOT EXPORTED -- PFTools does not hold them.  Every "
                  "structure carries area 0, which reads as unentered in "
                  "Carlson.  Enter catchments there, or wait for the drainage "
                  "phase of PF2SEW.\")"))
        (setq result (vl-catch-all-apply 'start_dialog '()))
        (unload_dialog dcl_id)
        (cond
          ((vl-catch-all-error-p result)
           (prompt (strcat "\nDialog error: "
                           (vl-catch-all-error-message result)))
           nil)
          ((= result 1) sw-res)
          (T nil))))))


;;; ==========================================================================
;;; SECTION 8  --  The engine + C:PF2SEW
;;; ==========================================================================

;; (pfsew:default-path sel) -> the save dialog's starting path
(defun pfsew:default-path (sel / dir)
  (setq dir (cond ((pfset:root-get)) (T (pfset:dir))))
  (strcat dir (strcase (car (car sel))) "_" (cadr (car sel))
          (if (cdr sel) "_SYSTEM" "")))

;; (pfsew:untyped nodes) -> the block names that matched no *pfsew-type-map*
;;   row, once each.  Reported by name: a structure exported as a plain
;;   junction because its block is unknown is a real modelling difference, and
;;   the fix is a table row, not a redraw.
(defun pfsew:untyped (nodes / out nd blk)
  (setq out '())
  (foreach nd nodes
    (setq blk (pfr:nd-blk nd))
    (cond
      ((or (null blk) (= blk ""))
       (if (not (member "(no block)" out)) (setq out (cons "(no block)" out))))
      ((pf:rule-for blk *pfsew-type-map*) nil)
      ((not (member blk out)) (setq out (cons blk out)))))
  (reverse out))

;; (pfsew:run sel) -> nil    THE ENGINE.  Read-only; the .sew is the only write.
;;   The gather is PFREPORT's, unchanged: same line table, same decomposition,
;;   same graph, same validation.  Everything below pfr:validate is this
;;   command's own.
(defun pfsew:run (sel / lines index inlets texts pipes r built nodes file
                        types untyped)
  (setq *pfr-fatal* '() *pfr-warn* '())
  (setq types '())
  (foreach r sel
    (if (not (member (car r) types)) (setq types (cons (car r) types))))
  (if (cdr types)
    (pfr:warn (strcat "the selection mixes utility types ("
                      (pf:join (reverse types) ", ")
                      ") -- confirm these really are one system.")))
  (prompt "\nBuilding the line table...")
  (setq lines  (pfr:line-table sel)
        inlets (pfa:gather-inlets)
        index  (pfa:index-stations inlets lines)
        texts  (pfr:elev-texts))
  (prompt (strcat "\n" (itoa (length texts))
                  " elevation label row(s) in model space; "
                  (itoa (length inlets)) " structure block(s)."))
  (setq pipes '())
  (foreach r sel
    (if (setq built (pfr:line-pipes r lines index texts inlets))
      (setq pipes (append pipes built))))
  (cond
    (*pfr-fatal*
     (prompt "\n\nPF2SEW ABORTED -- a selected profile could not be read:")
     (pfr:report))
    ((null pipes)
     (prompt "\nNothing to export -- no pipe runs were found.")
     (pfr:report))
    (T
     (setq built (pfr:build-nodes pipes)
           pipes (car built)
           nodes (cdr built))
     (prompt (strcat "\n" (itoa (length pipes)) " pipe(s) across "
                     (itoa (length nodes)) " structure(s)."))
     (setq pipes (pfr:order pipes nodes))
     (cond
       ((null pipes)
        ;; No longer a picking mistake: pfa:line-systems groups by shared
        ;; structures, so the members ARE connected.  Failing here means the
        ;; connectivity in the data disagrees with itself -- two outfalls, or a
        ;; break the shared structure implied but the profiles do not carry.
        (prompt (strcat "\n\nPF2SEW ABORTED -- this system does not resolve to "
                        "one network with one outfall.  The lines share a "
                        "structure but their pipe runs disagree:"))
        (pfr:report))
       (T
        (pfr:validate pipes nodes)
        (foreach r (pfsew:untyped nodes)
          (pfr:warn (strcat "block '" r "' matches no *pfsew-type-map* row -- "
                            "exported as a plain junction structure with no "
                            "inlet capture.")))
        (cond
          (*pfr-fatal*
           (prompt "\n\nPF2SEW ABORTED -- fix these first:")
           (pfr:report))
          (T
           (pfr:report)
           (setq file (getfiled "Export Carlson Hydrology Sewer File"
                                (pfsew:default-path sel) "sew" 1))
           (cond
             ((null file) (prompt "\nExport cancelled -- no file chosen."))
             ((pfsew:write file pipes nodes)
              (prompt (strcat "\n\nWrote " (itoa (length pipes)) " pipe(s) and "
                              (itoa (length nodes)) " structure(s) to " file))
              (prompt (strcat "\n  Drainage areas are NOT exported -- every "
                              "structure carries Area 0, which reads as "
                              "unentered in Carlson."))
              (prompt (strcat "\n  Structure and inlet library names come from "
                              "*pfsew-type-map*; they must exist in the "
                              "target Carlson install."))
              (prompt (strcat "\n  Length and slope are NOT in this file -- "
                              "Carlson derives both.  Set the mains to "
                              "\"actual pipe slope\" to reproduce the sheet."
                              ))))))))))
  (princ))

;; (pfsew:cmd) -> nil   The command body, run under pf:run-command.
(defun pfsew:cmd ( / rows systems sel)
  (setq rows (pfr:candidates))
  (if (null rows)
    (prompt (strcat "\nNo profile is ready to export.  PF2SEW needs an ANCHORED "
                    "registry entry with both a .cl and an _INV .pro bound -- "
                    "run PFSETUP."))
    (progn
      (prompt "\nGrouping profiles into systems...")
      (setq systems (pfa:line-systems rows))
      (prompt (strcat "\n" (itoa (length systems)) " system(s) from "
                      (itoa (length rows)) " profile(s)."))
      (setq sel (pfsew:run-dialog systems))
      (if (null sel)
        (prompt "\nPF2SEW cancelled.")
        (pfsew:run sel))))
  (princ))

(defun c:PF2SEW ()
  (pf:run-command "PF2SEW" nil 'pfsew:cmd))

(princ "\npf2sew.lsp loaded (Carlson Hydrology .sew export).  Command: PF2SEW.")
(princ)
;;; ==========================================================================
;;; end of pf2sew.lsp
;;; ==========================================================================
