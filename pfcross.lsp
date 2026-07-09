;;; ==========================================================================
;;; pfcross.lsp  --  Pipe-crossing tools:  C:PFXFIND  +  C:PFXLABEL
;;; --------------------------------------------------------------------------
;;; Requires pftools-lib.lsp and pfdialog.lsp loaded first (reuses the .cl
;;; wrappers, xform seams, draw helpers, browse + folder-scan dialogs).
;;;
;;; TOOL 1  --  PFXFIND   (plan only, no grids)
;;;   Pick the TARGET .cl, check off candidate crossing .cl files from the
;;;   target's folder, and the tool intersects endpoint segments (alignments
;;;   are always straight two-point runs) to find every real crossing.  For
;;;   each hit it reads BOTH stations off the Road API and stores the result
;;;   in *pfx-crossings* for PFXLABEL.
;;;
;;; TOOL 2  --  PFXLABEL  (one crossing per run, two grids)
;;;   Pick a crossing from PFXFIND's table, define the SOURCE (crossing
;;;   line's) grid and the TARGET grid (corner picks + grid dialog, PFLABEL
;;;   pattern), and the tool:
;;;     1. probes the source grid vertically at the source station,
;;;        intersecting LINEs (grid layers excluded) -> pipe Y -> INVERT
;;;        elevation via the inverse xform;
;;;     2. draws, on BOTH grids: a full-height station line at that grid's
;;;        own station, a placeholder circle at the invert elevation, and a
;;;        stacked label (own station / other line's basename).
;;;
;;; HANDOFF: in-session globals (*pfx-crossings*), same pattern as the
;;; transient *pflabel-* run inputs.  PFXFIND must run before PFXLABEL in
;;; the same session.  A crossings FILE is a named seam for later.
;;;
;;; STATUS: not yet run in a live drawing.  Test on a scratch copy first.
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  the honest assumptions; change here, nowhere else.
;;; --------------------------------------------------------------------------

;; Grid layers EXCLUDED from the vertical probe (the pipe is the sole
;; surviving LINE intersection at the crossing station).
(setq *pfx-grid-layers* '("PF-GRID-MJR" "PF-GRID-MNR" "PF-HBOX"))

;; Placeholder crossing symbol: circle radius (model units).  Swaps to the
;; real PF-PIPE_NN block (Y-scale = vertical exaggeration) post-POC.
(setq *pfx-circle-radius* 1.0)

;; Text: style must exist in the drawing; height is the firm standard.
(setq *pfx-style*  "L080")
(setq *pfx-height* 1.60)

;; Label geometry, HARDCODED from the measured sample (LIST of the manual
;; annotation): text mid-left, +3.20 in X from the symbol; row 1 sits +1.73
;; above the symbol Y, row 2 sits +3.20 above row 1.
(setq *pfx-text-dx*   3.20)
(setq *pfx-row1-dy*   1.73)
(setq *pfx-row-gap*   3.20)

;; Row order: row 1 (lower) = own station, row 2 (upper) = other basename.
;; Swap the two pf:draw-text calls in pfx:draw-crossing to invert.

;; Layer derivation -- ASSUMPTION flagged: layers follow the crossing
;; utility's TYPE (text before the first "_" in the .cl basename, upper-
;; cased), per the measured sample (Sanitary_A -> SANITARY_P and
;; SANITARY-TEXT_P).  Both symbol+line and text layers derive from it.
(setq *pfx-layer-suffix*      "_P")
(setq *pfx-text-layer-suffix* "-TEXT_P")

;; The pipe interior is drawn as TWO lines (top + bottom of bore); the INVERT
;; is the bottom, so the probe takes the LOWEST surviving hit.  Every hit is
;; reported (Y / elev / layer) so a stray line shows instead of silently
;; skewing the read.  Zero hits still aborts.


;;; ==========================================================================
;;; SECTION 1  --  Pure helpers
;;; ==========================================================================

;; (pfx:basename file) -> "Sanitary_A"   (no dir, no extension)
(defun pfx:basename (file) (vl-filename-base file))

;; (pfx:type-of file) -> "SANITARY"   (basename text before the FIRST "_",
;;   uppercased; no underscore -> the whole basename)
(defun pfx:type-of (file / base pos)
  (setq base (pfx:basename file))
  (if (setq pos (vl-string-search "_" base))
    (strcase (substr base 1 pos))
    (strcase base)))

;; (pfx:sym-layer file)  -> "SANITARY_P"
;; (pfx:text-layer file) -> "SANITARY-TEXT_P"
(defun pfx:sym-layer  (file) (strcat (pfx:type-of file) *pfx-layer-suffix*))
(defun pfx:text-layer (file) (strcat (pfx:type-of file) *pfx-text-layer-suffix*))

;; (pfx:pt2 p) -> (x y)   (drop Z / extra ordinates)
(defun pfx:pt2 (p) (list (car p) (cadr p)))

;; (pfx:y->elev y xform) -> elevation
;;   INVERSE of pf:elev->profile-y:  elev = datum + (y - base-y) / v-scale
(defun pfx:y->elev (y xform)
  (+ (pf:xf-datum xform)
     (/ (- y (pf:xf-basey xform)) (pf:xf-vscale xform))))

;; (pfx:cl-seg clfile) -> ((x y) (x y)) | nil
;;   The alignment's plan segment = its two .cl endpoints (alignments are
;;   always straight two-point runs, so the endpoints ARE the geometry).
(defun pfx:cl-seg (clfile / ends)
  (if (setq ends (pf:cl-endpoints clfile))
    (list (pfx:pt2 (car ends)) (pfx:pt2 (cadr ends)))))

;; (pfx:seg-x segA segB) -> (x y) | nil
;;   BOUNDED intersection of two plan segments (inters with onseg omitted
;;   treats both as bounded -- a crossing must fall within both runs).
(defun pfx:seg-x (segA segB)
  (inters (car segA) (cadr segA) (car segB) (cadr segB)))

;; (pfx:sta-at clfile xy) -> station | nil   (offset sanity-checked)
(defun pfx:sta-at (clfile xy / res)
  (if (setq res (pf:cl-locate-safe clfile xy))
    (car res)))


;;; ==========================================================================
;;; SECTION 2  --  Vertical probe  (the invert reader)
;;; ==========================================================================

;; (pfx:probe x base-y top-y) -> list of (y ename layer), lowest Y first
;;   Intersects the vertical segment (x, base-y)-(x, top-y) against every
;;   LINE in the drawing NOT on a grid layer.  Bounded inters, so only
;;   pipes actually inside the grid's height count.
(defun pfx:probe (x base-y top-y / pa pb ss i e ed la p1 p2 hit hits excl)
  (setq pa   (list x base-y)
        pb   (list x top-y)
        excl (mapcar 'strcase *pfx-grid-layers*)
        hits '()
        ss   (ssget "_X" '((0 . "LINE")))
        i    0)
  (if ss
    (while (< i (sslength ss))
      (setq e  (ssname ss i)
            ed (entget e)
            la (cdr (assoc 8 ed)))
      (if (not (member (strcase la) excl))
        (progn
          (setq p1 (pfx:pt2 (cdr (assoc 10 ed)))
                p2 (pfx:pt2 (cdr (assoc 11 ed))))
          (if (setq hit (inters pa pb p1 p2))
            (setq hits (cons (list (cadr hit) e la) hits)))))
      (setq i (1+ i))))
  (vl-sort hits '(lambda (a b) (< (car a) (car b)))))


;;; ==========================================================================
;;; SECTION 3  --  Drawing boundary  (SIDE-EFFECTING)
;;; ==========================================================================

;; (pfx:ensure-layer name)   (create with defaults if missing, Carlson-style)
(defun pfx:ensure-layer (name)
  (if (null (tblsearch "LAYER" name))
    (progn
      (entmake (list '(0 . "LAYER")
                     '(100 . "AcDbSymbolTableRecord")
                     '(100 . "AcDbLayerTableRecord")
                     (cons 2 name)
                     '(70 . 0)
                     '(62 . 7)
                     (cons 6 "Continuous")))
      (prompt (strcat "\nCreated layer '" name "'.")))))

;; (pfx:draw-circle pt r layer) -> ename
(defun pfx:draw-circle (pt r layer)
  (entmakex
    (list '(0 . "CIRCLE") (cons 8 layer)
          (cons 10 (list (car pt) (cadr pt) 0.0)) (cons 40 r))))

;; (pfx:draw-crossing xform own-sta elev other-base line-file)
;;   Draws ONE grid's half of a crossing:
;;     - full-height station line at own-sta   (grid bottom -> grid top)
;;     - placeholder circle at the invert elevation
;;     - stacked label: row 1 own station, row 2 other line's basename
;;   line-file drives the layer derivation (the utility being represented).
(defun pfx:draw-crossing (xform own-sta elev other-base line-file
                          / x y sym-la txt-la)
  (setq x      (pf:station->profile-x own-sta xform)
        y      (pf:elev->profile-y   elev    xform)
        sym-la (pfx:sym-layer  line-file)
        txt-la (pfx:text-layer line-file))
  (pfx:ensure-layer sym-la)
  (pfx:ensure-layer txt-la)
  ;; station line, full grid height (reuses the PFLABEL primitive)
  (pf:draw-station-line x (pf:xf-basey xform) (pf:grid-top-y xform) sym-la)
  ;; placeholder symbol at the crossing invert
  (pfx:draw-circle (list x y) *pfx-circle-radius* sym-la)
  ;; stacked label, mid-left, horizontal (rot 0), hardcoded offsets
  (pf:draw-text (list (+ x *pfx-text-dx*) (+ y *pfx-row1-dy*) 0.0)
                (pf:fmt-station own-sta)
                txt-la *pfx-style* *pfx-height* 0.0)
  (pf:draw-text (list (+ x *pfx-text-dx*) (+ y *pfx-row1-dy* *pfx-row-gap*) 0.0)
                other-base
                txt-la *pfx-style* *pfx-height* 0.0)
  (princ))


;;; ==========================================================================
;;; SECTION 4  --  Grid capture  (corner picks + grid dialog, per role)
;;; ==========================================================================

;; (pfx:get-grid role) -> xform | nil
;;   role is a prompt string ("SOURCE ..." / "TARGET ...").  Corner picks
;;   first, then the shared grid dialog (sta0 datum hplot vplot).  xform is
;;   the standard 7-element form the whole suite shares.
(defun pfx:get-grid (role / ll top g)
  (prompt (strcat "\n== Define the " role " grid =="))
  (setq ll (getpoint (strcat "\nPick " role " grid LOWER-LEFT corner: ")))
  (if (null ll)
    (progn (prompt "\nNo point picked -- aborting.") nil)
    (progn
      (setq top (getpoint ll (strcat "\nPick a point on the " role
                                     " grid TOP border: ")))
      (cond
        ((null top) (prompt "\nNo point picked -- aborting.") nil)
        ((null (setq g (pflabel:show-grid-dialog)))
         (prompt "\nGrid dialog cancelled -- aborting.") nil)
        (T
         ;; xform = (left-x sta0 hscale top-y base-y datum vscale)
         (list (car ll) (nth 0 g) *pf-hscale-fixed*
               (cadr top) (cadr ll) (nth 1 g)
               (/ (nth 2 g) (nth 3 g))))))))


;;; ==========================================================================
;;; SECTION 5  --  TOOL 1:  C:PFXFIND   (crossing finder, plan only)
;;; ==========================================================================

;; Crossings live here between the two commands (in-session handoff).
;; Entry: (tgt-file tgt-base src-file src-base (x y) tgt-sta src-sta)
(if (not (boundp '*pfx-crossings*)) (setq *pfx-crossings* nil))

(defun pfx:xing-tfile (e) (nth 0 e))
(defun pfx:xing-tbase (e) (nth 1 e))
(defun pfx:xing-sfile (e) (nth 2 e))
(defun pfx:xing-sbase (e) (nth 3 e))
(defun pfx:xing-xy    (e) (nth 4 e))
(defun pfx:xing-tsta  (e) (nth 5 e))
(defun pfx:xing-ssta  (e) (nth 6 e))

;; (pfx:print-crossings) -> nil   (numbered table for PFXLABEL's pick)
(defun pfx:print-crossings ( / i)
  (if (null *pfx-crossings*)
    (prompt "\nNo crossings on record -- run PFXFIND.")
    (progn
      (setq i 0)
      (prompt (strcat "\nCrossings vs target '"
                      (pfx:xing-tbase (car *pfx-crossings*)) "':"))
      (foreach e *pfx-crossings*
        (setq i (1+ i))
        (prompt (strcat "\n  " (itoa i) ".  " (pfx:xing-sbase e)
                        "   target sta " (pf:fmt-station (pfx:xing-tsta e))
                        "   source sta " (pf:fmt-station (pfx:xing-ssta e)))))))
  (princ))

(defun c:PFXFIND ( / dcl_id tgt tseg dir files self chosen out
                     f path sseg xy tsta ssta)
  (pf:load-apis)
  ;; 1. Target .cl (reuses the suite's remembered-directory browser).
  (setq tgt (pflabel:browse "Select TARGET Centerline (.CL) File"
                            '*pflabel-dir-cl* "cl"))
  (cond
    ((null tgt) (prompt "\nNo target selected -- cancelled."))
    ((null (setq tseg (pfx:cl-seg tgt)))
     (prompt (strcat "\nCould not read endpoints from " tgt " -- aborting.")))
    (T
     ;; 2. Candidates: every OTHER .cl in the target's folder, checklist.
     (setq dir   (strcat (vl-filename-directory tgt) "\\")
           files (acad_strlsort (vl-directory-files dir "*.cl" 1))
           self  (strcase (strcat (pfx:basename tgt) ".CL"))
           files (vl-remove-if '(lambda (f) (= (strcase f) self)) files))
     (if (null files)
       (prompt "\nNo other .cl files in that folder -- nothing to test.")
       (progn
         (setq dcl_id (load_dialog (pflabel:dcl-file)))
         (if (< dcl_id 0)
           (prompt "\nCould not load pfdialog.dcl.")
           (progn
             (setq chosen (pflabel:scan-dialog dcl_id files nil))
             (unload_dialog dcl_id)
             (if (null chosen)
               (prompt "\nNo candidates checked -- cancelled.")
               (progn
                 ;; 3. Intersect each candidate against the target.
                 (setq out '())
                 (foreach i chosen
                   (setq f    (nth i files)
                         path (strcat dir f)
                         sseg (pfx:cl-seg path))
                   (cond
                     ((null sseg)
                      (prompt (strcat "\n  " f " -- could not read endpoints; skipped.")))
                     ((null (setq xy (pfx:seg-x tseg sseg)))
                      (prompt (strcat "\n  " f " -- does not cross the target.")))
                     (T
                      ;; 4. Both stations off the Road API at the crossing XY.
                      (setq tsta (pfx:sta-at tgt  xy)
                            ssta (pfx:sta-at path xy))
                      (if (and tsta ssta)
                        (progn
                          (setq out (cons (list tgt (pfx:basename tgt)
                                                path (pfx:basename path)
                                                xy tsta ssta)
                                          out))
                          (prompt (strcat "\n  " f " -- CROSSES at target sta "
                                          (pf:fmt-station tsta)
                                          ", source sta "
                                          (pf:fmt-station ssta))))
                        (prompt (strcat "\n  " f
                                        " -- crossing found but a station read "
                                        "failed; skipped."))))))
                 (setq *pfx-crossings* (reverse out))
                 (prompt (strcat "\n" (itoa (length *pfx-crossings*))
                                 " crossing(s) stored."))
                 (pfx:print-crossings))))))))) 
  (princ))


;;; ==========================================================================
;;; SECTION 6  --  TOOL 2:  C:PFXLABEL   (invert reader + labeler)
;;; ==========================================================================

(if (not (boundp '*pfx-undo-open*)) (setq *pfx-undo-open* nil))

(defun pfx:*error* (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFXLABEL error: " msg)))
  (if *pfx-undo-open*
    (progn (command-s "_.UNDO" "_End") (setq *pfx-undo-open* nil)))
  (setq *error* *pfx-prev-error*)
  (princ))

(defun c:PFXLABEL ( / n pick e src-xf tgt-xf x hits elev)
  (setq *pfx-prev-error* *error*
        *error*          pfx:*error*
        *pfx-undo-open*  nil)
  (cond
    ((null *pfx-crossings*)
     (prompt "\nNo crossings on record -- run PFXFIND first."))
    (T
     ;; 1. Pick a crossing from the table.
     (pfx:print-crossings)
     (setq n (length *pfx-crossings*))
     (initget 6)                                   ; no zero, no negative
     (setq pick (getint (strcat "\nCrossing to label <1-" (itoa n) ">: ")))
     (cond
       ((or (null pick) (> pick n))
        (prompt "\nNo valid crossing picked -- cancelled."))
       (T
        (setq e (nth (1- pick) *pfx-crossings*))
        ;; 2. SOURCE grid (the crossing line's own profile).
        (setq src-xf (pfx:get-grid
                       (strcat "SOURCE (" (pfx:xing-sbase e) ")")))
        (if src-xf
          (progn
            ;; 3. Vertical probe: source station -> world X -> pipe Y.
            (setq x    (pf:station->profile-x (pfx:xing-ssta e) src-xf)
                  hits (pfx:probe x (pf:xf-basey src-xf)
                                    (pf:grid-top-y src-xf)))
            (cond
              ((null hits)
               (prompt (strcat "\nNo pipe LINE found on the probe at sta "
                               (pf:fmt-station (pfx:xing-ssta e))
                               " -- nothing drawn."
                               "\n(Check the grid picks and that the pipe is "
                               "a LINE off the grid layers.)")))
              (T
               ;; 4. INVERT = the LOWEST surviving hit.  The pipe interior is
               ;;    drawn as two lines (top + bottom of bore); the bottom is
               ;;    the invert, and pfx:probe already sorts lowest-Y first.
               ;;    Report every hit so a stray line is visible, not silent.
               (prompt (strcat "\nProbe at sta "
                               (pf:fmt-station (pfx:xing-ssta e))
                               " found " (itoa (length hits)) " line(s):"))
               (foreach h hits
                 (prompt (strcat "\n    Y " (rtos (car h) 2 4)
                                 "   elev " (rtos (pfx:y->elev (car h) src-xf) 2 2)
                                 "   layer " (caddr h))))
               (setq elev (pfx:y->elev (car (car hits)) src-xf))
               (prompt (strcat "\nInvert (lowest) = "
                               (rtos elev 2 2)
                               "  on layer " (caddr (car hits))))
               ;; 5. TARGET grid, then draw both halves in one undo group.
               (setq tgt-xf (pfx:get-grid
                              (strcat "TARGET (" (pfx:xing-tbase e) ")")))
               (if tgt-xf
                 (progn
                   (command "_.UNDO" "_Begin")
                   (setq *pfx-undo-open* T)
                   ;; SOURCE grid: own sta = source sta; represents TARGET line.
                   (pfx:draw-crossing src-xf (pfx:xing-ssta e) elev
                                      (pfx:xing-tbase e) (pfx:xing-tfile e))
                   ;; TARGET grid: own sta = target sta; represents SOURCE line.
                   (pfx:draw-crossing tgt-xf (pfx:xing-tsta e) elev
                                      (pfx:xing-sbase e) (pfx:xing-sfile e))
                   (command "_.UNDO" "_End")
                   (setq *pfx-undo-open* nil)
                   (prompt (strcat "\nLabeled crossing "
                                   (pfx:xing-tbase e) " x "
                                   (pfx:xing-sbase e) " on both grids."))))))))))))
  (setq *error* *pfx-prev-error*)
  (princ))


(princ "\npfcross.lsp loaded.  Commands: PFXFIND (find crossings), PFXLABEL (label one).")
(princ)
;;; ==========================================================================
;;; end of pfcross.lsp
;;; ==========================================================================
