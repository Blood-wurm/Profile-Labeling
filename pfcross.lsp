;;; ==========================================================================
;;; pfcross.lsp  --  Pipe-crossing tools:  C:PFXFIND  +  C:PFXLABEL
;;; --------------------------------------------------------------------------
;;; Requires pftools-lib.lsp and pfdialog.lsp loaded first (reuses the .cl
;;; wrappers, xform seams, draw helpers, browse + folder-scan dialogs).
;;;
;;; TOOL 1  --  PFXFIND   (plan only, no grids)
;;;   Pick the TARGET .cl, check off candidate crossing .cl files from the
;;;   target's folder, and the tool intersects drawn plan polylines segment-
;;;   by-segment to find every real crossing on curved alignments. For each
;;;   hit it reads BOTH stations off the Road API and stores the result in
;;;   *pfx-crossings* for PFXLABEL.
;;;
;;; TOOL 2  --  PFXLABEL  (one crossing per run, two grids)
;;;   Pick a crossing from PFXFIND's table, define the SOURCE (crossing
;;;   line's) grid and the TARGET grid (corner picks + grid dialog), then:
;;;     1. probe BOTH grids vertically at their own stations -> each pipe's
;;;        invert elevation (lowest bore line) + pipe size (bore spacing);
;;;     2. on EACH grid draw: a station line from 30 below the grid bottom
;;;        to the grid top, vertical station text at its lower end, and BOTH
;;;        pipes as PF-PIPE_NN blocks (Y-scaled by that grid's exaggeration)
;;;        at their true elevations -- the grid's own pipe on its ALIGN-*
;;;        layer, the crossing pipe on its utility layer -- each with a
;;;        two-row label (standard line label / NN" PIPE);
;;;     3. rebuild the crossings table at the target grid's top-left on
;;;        PF-TABLE (all crossings on record; elevations fill in as they're
;;;        labeled).  PF-TABLE is TOOL-OWNED: every entity on it is erased
;;;        on rebuild -- put nothing else on that layer.  The invert ticks
;;;        + elevation text stay on PF-TEMP, which is NEVER erased.
;;;
;;; HANDOFF: in-session globals (*pfx-crossings*), same pattern as the
;;; transient *pflabel-* run inputs.  PFXFIND must run before PFXLABEL in
;;; the same session.  A crossings FILE is a named seam for later.
;;;
;;; STATUS: batch-A rewrite (blocks + sizes + standard labels + PF-TABLE).
;;; Dynamic scaling enabled (1.6 text height standard for H:20).
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  the honest assumptions; change here, nowhere else.
;;; --------------------------------------------------------------------------

;; Grid layers EXCLUDED from the vertical probe (the pipe bore lines are the
;; surviving LINE intersections at the crossing station).  PF-TEMP carries
;; the tool's own invert ticks (horizontal LINEs at the invert Y), so it MUST
;; stay excluded or a re-run reads a stale tick as a bore line and the size
;; collapses to the smallest block.  PF-TABLE is excluded on principle.
(setq *pfx-grid-layers* '("PF-GRID-MJR" "PF-GRID-MNR" "PF-HBOX"
                          "PF-GROUND_X" "PF-XING" "PF-TEMP" "PF-TABLE"))

;; Text: style must exist in the drawing; height is now dynamically calculated
;; relative to the plot scale (1.6 standard at H:20).
(setq *pfx-style*  "L080")

;; Vertical station-text style (falls back to pfx:active-style when missing
;; from the drawing).
(setq *pfx-vtext-style* "ARIAL_L080")

;; Label geometry, HARDCODED base scalars from the measured sample.
;;   row 1 (lower) = NN" PIPE      row 2 (upper) = standard line label
(setq *pfx-text-dx*   3.20)
(setq *pfx-row1-dy*   1.73)
(setq *pfx-row-gap*   3.20)

;; Station line extends this far BELOW the grid bottom (base scalar).
(setq *pfx-line-ext* 30.0)

;; Crossing block family: PF-PIPE_<NN>, NN = zero-padded nominal inches.
(setq *pfx-pipe-sizes* '(4 6 8 10 12 15 18 24 30 36 42 48 54 60))
(setq *pfx-block-prefix* "PF-PIPE_")

;; Plan-geometry sampling step (feet).  Crossing discovery walks each .cl at
;; this interval via cl_location_at_sta, so arcs are followed as the Road API
;; reports them -- no drawn-polyline dependency, no straight-chord artifacts.
(setq *pfx-sample-step* 2.0)

;; Refinement step (feet).  Once a crossing is found, both lines are re-
;; sampled at THIS interval within +/- one sample step of the hit and re-
;; intersected, so stations on arcs are exact to ~0.1 ft.  Cheap: runs only
;; per crossing found, ~80 calls each.
(setq *pfx-refine-step* 0.1)

;; Placeholder when the block definition is missing from the drawing.
;; Base scalar -- multiplied by the grid's sf at draw time.
(setq *pfx-circle-radius* 1.0)

;; Layer derivation: layers follow the utility TYPE.
(setq *pfx-layer-suffix*      "_P")
(setq *pfx-text-layer-suffix* "-TEXT_P")
(setq *pfx-align-layers*
  '(("WATER"    . "ALIGN-WATER_P")
    ("SANITARY" . "ALIGN-SAN_P")
    ("STORM"    . "ALIGN-STM_P")))

;; Standard line labels, PER TYPE. [name] is replaced with the .cl basename suffix.
(setq *pfx-label-templates*
  '(("WATER"    . "PROPOSED WATER MAIN '[name]'")
    ("SANITARY" . "PROPOSED SANITARY LINE '[name]'")
    ("STORM"    . "STORM LINE '[name]'")))

;; Vertical station-text descriptor, PER TYPE.
(setq *pfx-cross-templates*
  '(("WATER"    . "PROPOSED WATER CROSSING")
    ("SANITARY" . "PROPOSED SANITARY CROSSING")
    ("STORM"    . "STORM CROSSING")))

;; Crossings table (6 columns) -- PF-TABLE is TOOL-OWNED and blanket-cleared
;; on every rebuild.  The invert ticks/elev text live on PF-TEMP (untouched).
(setq *pfx-table-layer*  "PF-TABLE")
(setq *pfx-tick-layer*   "PF-TEMP")
(setq *pfx-table-margin* 2.0)                  ; offset from the grid corner (base scalar)
(setq *pfx-table-step*   3.20)                 ; row-to-row spacing (base scalar)
(setq *pfx-table-cols*   '(0.0 8.0 32.0 68.0 96.0 120.0))  ; #, LINE, TGT STA, TGT INV, SRC STA, SRC INV

;;; ==========================================================================
;;; SECTION 1  --  Pure helpers
;;; ==========================================================================

(defun pfx:basename (file) (vl-filename-base file))

(defun pfx:type-of (file / base pos)
  (setq base (pfx:basename file))
  (if (setq pos (vl-string-search "_" base))
    (strcase (substr base 1 pos))
    (strcase base)))

(defun pfx:name-of (file / base pos)
  (setq base (pfx:basename file))
  (if (setq pos (vl-string-search "_" base))
    (strcase (substr base (+ pos 2)))
    (strcase base)))

(defun pfx:sym-layer  (file) (strcat (pfx:type-of file) *pfx-layer-suffix*))
(defun pfx:text-layer (file) (strcat (pfx:type-of file) *pfx-text-layer-suffix*))

(defun pfx:align-layer (file / cell)
  (if (setq cell (assoc (pfx:type-of file) *pfx-align-layers*))
    (cdr cell)
    (progn
      (prompt (strcat "\n  Warning: no ALIGN layer mapped for type '"
                      (pfx:type-of file) "' -- using " (pfx:sym-layer file) "."))
      (pfx:sym-layer file))))

(defun pfx:std-label (file / cell)
  (if (setq cell (assoc (pfx:type-of file) *pfx-label-templates*))
    (pf:subst-token (cdr cell) "[name]" (pfx:name-of file))
    (progn
      (prompt (strcat "\n  Warning: no label template for type '"
                      (pfx:type-of file) "' -- using generic wording."))
      (strcat (pfx:type-of file) " LINE '" (pfx:name-of file) "'"))))

(defun pfx:cross-desc (file / cell)
  (if (setq cell (assoc (pfx:type-of file) *pfx-cross-templates*))
    (cdr cell)
    (strcat (pfx:type-of file) " CROSSING")))

(defun pfx:pt2 (p) (list (car p) (cadr p)))

(defun pfx:y->elev (y xform)
  (+ (pf:xf-datum xform)
     (/ (- y (pf:xf-basey xform)) (pf:xf-vscale xform))))

;; (pfx:xf-hplot xf) -> horizontal PLOT scale (8th xform element, appended by
;;   pfx:get-grid; drives the sf scale factor -- named seam, no raw nth 7s)
(defun pfx:xf-hplot (xf) (nth 7 xf))

;; (pfx:xf-sf xf) -> scale factor for this grid (1.0 at the H:20 standard)
(defun pfx:xf-sf (xf) (/ (pfx:xf-hplot xf) 20.0))

(defun pfx:nearest-size (inches / best bd d)
  (foreach s *pfx-pipe-sizes*
    (setq d (abs (- inches s)))
    (if (or (null best) (< d bd)) (setq best s bd d)))
  best)

(defun pfx:size-blockname (n)
  (strcat *pfx-block-prefix* (if (< n 10) "0" "") (itoa n)))

(defun pfx:size-rowtext (n) (strcat (itoa n) "\" PIPE"))

;; (pfx:sample-cl clfile) -> list of (x y) | nil
;;   Walks the .cl at *pfx-sample-step* via cl_location_at_sta (the proven
;;   pf:cl-endpoints call, in a loop), always including the exact end
;;   station.  TRUE alignment geometry -- arcs included -- straight from the
;;   .cl, independent of what's drawn.
(defun pfx:sample-cl (clfile / rng sta0 stan sta pts r)
  (if (setq rng (pf:cl-range clfile))
    (progn
      (setq sta0 (car rng) stan (cadr rng) sta sta0 pts '())
      (while (< sta stan)
        (setq r (vl-catch-all-apply *pf-road-fn*
                  (list "cl_location_at_sta" clfile sta)))
        (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
          (setq pts (cons (pfx:pt2 (car r)) pts)))
        (setq sta (+ sta *pfx-sample-step*)))
      (setq r (vl-catch-all-apply *pf-road-fn*
                (list "cl_location_at_sta" clfile stan)))
      (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
        (setq pts (cons (pfx:pt2 (car r)) pts)))
      (if (> (length pts) 1) (reverse pts)))))

;; (pfx:sample-range clfile s0 s1 step) -> list of (x y) | nil
;;   Like pfx:sample-cl but over [s0, s1] (clamped to the .cl's range) at
;;   `step`, always including the exact end of the window.
(defun pfx:sample-range (clfile s0 s1 step / rng lo hi sta pts r)
  (if (setq rng (pf:cl-range clfile))
    (progn
      (setq lo  (max (car rng) (min s0 s1))
            hi  (min (cadr rng) (max s0 s1))
            sta lo
            pts '())
      (while (< sta hi)
        (setq r (vl-catch-all-apply *pf-road-fn*
                  (list "cl_location_at_sta" clfile sta)))
        (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
          (setq pts (cons (pfx:pt2 (car r)) pts)))
        (setq sta (+ sta step)))
      (setq r (vl-catch-all-apply *pf-road-fn*
                (list "cl_location_at_sta" clfile hi)))
      (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
        (setq pts (cons (pfx:pt2 (car r)) pts)))
      (if (> (length pts) 1) (reverse pts)))))

;; (pfx:refine-x tfile tsta sfile ssta) -> (x y) | nil
;;   Local refinement: re-sample both lines at *pfx-refine-step* within
;;   +/- one *pfx-sample-step* of the coarse hit and re-intersect.  nil when
;;   either window fails to sample (caller keeps the coarse result).
(defun pfx:refine-x (tfile tsta sfile ssta / tv sv)
  (setq tv (pfx:sample-range tfile (- tsta *pfx-sample-step*)
                             (+ tsta *pfx-sample-step*) *pfx-refine-step*)
        sv (pfx:sample-range sfile (- ssta *pfx-sample-step*)
                             (+ ssta *pfx-sample-step*) *pfx-refine-step*))
  (if (and tv sv) (pfx:poly-x tv sv)))

;; (pfx:get-verts clfile) -> list of (x y) vertices | nil
;;   Geometry source order, best first:
;;     1. .cl sampling (true alignment, arcs followed)
;;     2. drawn-polyline vertices  (WARNING: arc bulges read as chords)
;;     3. endpoint chord           (WARNING: straight-line approximation)
;;   2 and 3 announce themselves -- a chord-based result can both miss real
;;   crossings on curves and report false ones, so it must never be silent.
(defun pfx:get-verts (clfile / pts rng entry verts ends)
  (cond
    ((setq pts (pfx:sample-cl clfile)) pts)
    ((setq rng (pf:cl-range clfile))
     (setq entry (pf:attach-corridor
                   (list clfile (pfx:basename clfile) (car rng) (cadr rng)))
           verts (nth 4 entry))
     (if (and verts (> (length verts) 1))
       (progn
         (prompt (strcat "\n  Warning: .cl sampling failed for "
                         (pfx:basename clfile)
                         " -- using drawn polyline vertices (arcs read as chords)."))
         (mapcar 'pfx:pt2 verts))
       (if (setq ends (pf:cl-endpoints clfile))
         (progn
           (prompt (strcat "\n  Warning: using straight endpoint CHORD for "
                           (pfx:basename clfile)
                           " -- crossings on curves may be missed or false."))
           (list (pfx:pt2 (car ends)) (pfx:pt2 (cadr ends)))))))))

(defun pfx:poly-x (vertsA vertsB / i j lenA lenB a1 a2 b1 b2 hit)
  (setq lenA (length vertsA)
        lenB (length vertsB)
        i    0
        hit  nil)
  (while (and (< i (1- lenA)) (null hit))
    (setq a1 (nth i vertsA)
          a2 (nth (1+ i) vertsA)
          j  0)
    (while (and (< j (1- lenB)) (null hit))
      (setq b1 (nth j vertsB)
            b2 (nth (1+ j) vertsB))
      (if (setq hit (inters a1 a2 b1 b2))
        nil)
      (setq j (1+ j)))
    (setq i (1+ i)))
  hit)

(defun pfx:sta-at (clfile xy / res)
  (if (setq res (pf:cl-locate-safe clfile xy))
    (car res)))

;;; ==========================================================================
;;; SECTION 2  --  Vertical probe  (invert + size reader)
;;; ==========================================================================

;; (pfx:probe x base-y top-y) -> list of (y ename layer), lowest Y first
(defun pfx:probe (x base-y top-y / pa pb ss i e ed la p1 p2 hit hits excl)
  ;; Extend the vertical probe exactly 50 drawing units beyond the grid top
  ;; (the grid is sometimes trimmed low where the profile rises; the pipe can
  ;; sit above the trimmed border), but keep the bottom flush with the base.
  (setq pa   (list x base-y)
        pb   (list x (+ top-y 50.0))
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

(defun pfx:read-pipe (role xform sta / x hits y1 y2 raw-in size)
  (setq x    (pf:station->profile-x sta xform)
        hits (pfx:probe x
                        (pf:xf-basey xform)
                        (pf:grid-top-y xform)))
  (cond
    ((null hits)
     (prompt (strcat "\n" role ": no pipe LINE found on the probe at sta "
                     (pf:fmt-station sta) " -- pipe skipped."
                     "\n(Check the grid picks and that the pipe is a LINE "
                     "off the grid layers.)"))
     nil)
    (T
     (prompt (strcat "\n" role ": probe at sta " (pf:fmt-station sta)
                     " found " (itoa (length hits)) " line(s):"))
     (foreach h hits
       (prompt (strcat "\n    Y " (rtos (car h) 2 4)
                       "   elev " (rtos (pfx:y->elev (car h) xform) 2 2)
                       "   layer " (caddr h))))
     (setq y1 (car (car hits)))
     (if (> (length hits) 1)
       (progn
         (setq y2     (car (cadr hits))
               raw-in (/ (* (- y2 y1) 12.0) (pf:xf-vscale xform))
               size   (pfx:nearest-size raw-in))
         (prompt (strcat "\n" role ": bore spacing " (rtos raw-in 2 2)
                         "\" -> " (pfx:size-blockname size))))
       (prompt (strcat "\n" role ": only one hit -- size undetermined, "
                       "placeholder circle will be used.")))
     (list (pfx:y->elev y1 xform) size))))

;;; ==========================================================================
;;; SECTION 3  --  Drawing boundary  (SIDE-EFFECTING)
;;; ==========================================================================

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

(defun pfx:draw-circle (pt r layer)
  (entmakex
    (list '(0 . "CIRCLE") (cons 8 layer)
          (cons 10 (list (car pt) (cadr pt) 0.0)) (cons 40 r))))

(defun pfx:active-style ( / st s)
  (setq s  (vl-catch-all-apply 'pflabel:settings '())
        st (if (and (listp s) (assoc "style" s)) (cdr (assoc "style" s))))
  (cond
    ((and st (/= st "") (tblsearch "STYLE" st)) st)
    ((tblsearch "STYLE" *pfx-style*) *pfx-style*)
    ((tblsearch "STYLE" "Standard") "Standard")
    (T "")))

(defun pfx:text (pt str layer rot ht / style)
  (setq style (pfx:active-style))
  (if (null (pf:draw-text pt str layer style ht rot))
    (prompt (strcat "\n  Warning: entmakex failed drawing text '" str "'."))))

;; (pfx:text-right pt str layer rot ht style)   Middle Right justification
(defun pfx:text-right (pt str layer rot ht style)
  ;; Fall back to the dialog/default style if `style` isn't in the drawing
  (if (null (tblsearch "STYLE" style))
    (progn
      (prompt (strcat "\n  Warning: Style '" style "' not found. Falling back to default."))
      (setq style (pfx:active-style))))

  (if (null
        (entmakex
          (list '(0 . "TEXT") (cons 8 layer) (cons 7 style)
                (cons 10 pt) (cons 11 pt) (cons 40 ht)
                (cons 1 str) (cons 50 rot) (cons 72 2) (cons 73 2))))
    (prompt (strcat "\n  Warning: entmakex failed drawing text '" str "'."))))

(defun pfx:insert-pipe (pt size layer yscale sf / bname)
  (cond
    ((null size)
     (pfx:draw-circle pt (* *pfx-circle-radius* sf) layer))
    ((null (tblsearch "BLOCK" (setq bname (pfx:size-blockname size))))
     (prompt (strcat "\n  Warning: block '" bname
                     "' not defined in this drawing -- circle placeholder."))
     (pfx:draw-circle pt (* *pfx-circle-radius* sf) layer))
    (T
     (entmakex
       (list '(0 . "INSERT") (cons 8 layer) (cons 2 bname)
             (cons 10 (list (car pt) (cadr pt) 0.0))
             (cons 41 1.0) (cons 42 yscale) (cons 43 1.0)
             (cons 50 0.0))))))

(defun pfx:label-pipe (x y file size sf ht / la dx dy gap)
  (setq la  (pfx:text-layer file)
        dx  (* *pfx-text-dx* sf)
        dy  (* *pfx-row1-dy* sf)
        gap (* *pfx-row-gap* sf))
  (pfx:ensure-layer la)
  (if size
    (pfx:text (list (+ x dx) (+ y dy) 0.0)
              (pfx:size-rowtext size) la 0.0 ht))
  (pfx:text (list (+ x dx) (+ y dy gap) 0.0)
            (pfx:std-label file) la 0.0 ht))

;; (pfx:draw-grid-side xform own-file own-sta own-pipe other-file other-pipe)
(defun pfx:draw-grid-side (xform own-file own-sta own-pipe other-file
                           other-pipe / x ybot line-la vtxt-la y sf ht)
  (setq sf      (pfx:xf-sf xform)
        ht      (* 1.60 sf)
        x       (pf:station->profile-x own-sta xform)
        ybot    (- (pf:xf-basey xform) (* *pfx-line-ext* sf))
        line-la "PF-XING"
        vtxt-la "PF-XING-TEXT")

  (pfx:ensure-layer line-la)
  (pfx:ensure-layer vtxt-la)

  ;; station line
  (pf:draw-station-line x ybot (pf:grid-top-y xform) line-la)

  ;; vertical station text at the lower end, reading upward
  ;; Middle Right insertion anchors text to ybot and grows upwards.
  (pfx:text-right (list x ybot 0.0)
                  (strcat (pf:fmt-station own-sta) " " (pfx:cross-desc other-file))
                  vtxt-la (/ pi 2.0) ht *pfx-vtext-style*)

  ;; the grid's OWN pipe (redundant) -> pipe block + marker + vertical elev on PF-TEMP
  (if own-pipe
    (progn
      (setq y (pf:elev->profile-y (car own-pipe) xform))

      ;; 1. Restore the block insertion to its ALIGN layer
      (pfx:ensure-layer (pfx:align-layer own-file))
      (pfx:insert-pipe (list x y) (cadr own-pipe)
                       (pfx:align-layer own-file) (pf:xf-vscale xform) sf)

      ;; 2. Invert marker and elevation label
      (pfx:ensure-layer *pfx-tick-layer*)
      ;; Marker: horizontal tick across the station line
      (entmakex (list '(0 . "LINE") (cons 8 *pfx-tick-layer*)
                      (cons 10 (list (- x (* ht 0.75)) y 0.0))
                      (cons 11 (list (+ x (* ht 0.75)) y 0.0))))
      ;; Elevation label snapped to invert, reading vertical
      (pfx:text (list (+ x (* ht 0.5)) y 0.0)
                (rtos (car own-pipe) 2 2) *pfx-tick-layer* (/ pi 2.0) ht)))

  ;; the CROSSING pipe -> its utility layer
  (if other-pipe
    (progn
      (setq y (pf:elev->profile-y (car other-pipe) xform))
      (pfx:ensure-layer (pfx:sym-layer other-file))
      (pfx:insert-pipe (list x y) (cadr other-pipe)
                       (pfx:sym-layer other-file) (pf:xf-vscale xform) sf)
      (pfx:label-pipe x y other-file (cadr other-pipe) sf ht)))
  (princ))

;;; ==========================================================================
;;; SECTION 4  --  PF-TABLE crossings table  (TOOL-OWNED layer)
;;; ==========================================================================

;; (pfx:clear-table)   erase every entity on PF-TABLE.  Safe ONLY because
;;   PF-TABLE is exclusively this tool's output; nothing else goes there.
(defun pfx:clear-table ( / ss i)
  (setq ss (ssget "_X" (list (cons 8 *pfx-table-layer*))))
  (if ss
    (progn
      (setq i 0)
      (while (< i (sslength ss))
        (entdel (ssname ss i))
        (setq i (1+ i)))
      (prompt (strcat "\nCleared " (itoa (sslength ss))
                      " old entit(ies) off " *pfx-table-layer* ".")))))

(defun pfx:table-row (x0 y cells tcols ht / i)
  (setq i 0)
  (foreach c cells
    (if (and c (/= c ""))
      (pfx:text (list (+ x0 (nth i tcols)) y 0.0)
                c *pfx-table-layer* 0.0 ht))
    (setq i (1+ i)))
  (princ))

(defun pfx:draw-table (tgt-xf / x0 y0 i sf ht tmarg tstep tcols)
  (pfx:ensure-layer *pfx-table-layer*)
  (setq sf    (pfx:xf-sf tgt-xf)
        ht    (* 1.60 sf)
        tmarg (* *pfx-table-margin* sf)
        tstep (* *pfx-table-step* sf)
        tcols (mapcar '(lambda (x) (* x sf)) *pfx-table-cols*)
        x0    (+ (pf:xf-leftx tgt-xf) tmarg)
        y0    (+ (pf:grid-top-y tgt-xf) tmarg
                 (* (+ (length *pfx-crossings*) 1) tstep)))

  (pfx:table-row x0 y0
    (list (strcat "CROSSINGS -- TARGET '" (pfx:xing-tbase (car *pfx-crossings*)) "'")) tcols ht)

  (pfx:table-row x0 (- y0 tstep)
    (list "#" "LINE" "TGT STATION" "TGT INV ELEV" "SRC STA" "SRC INV ELEV") tcols ht)

  (setq i 0)
  (foreach e *pfx-crossings*
    (setq i (1+ i))
    (pfx:table-row x0 (- y0 (* (1+ i) tstep))
      (list (itoa i)
            (pfx:xing-sbase e)
            (pf:fmt-station (pfx:xing-tsta e))
            (if (pfx:xing-telev e) (rtos (pfx:xing-telev e) 2 2) "--")
            (pf:fmt-station (pfx:xing-ssta e))
            (if (pfx:xing-selev e) (rtos (pfx:xing-selev e) 2 2) "--"))
      tcols ht))
  (princ))

;;; ==========================================================================
;;; SECTION 5  --  Grid capture  (corner picks + grid dialog, per role)
;;; ==========================================================================

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
         ;; xform = (left-x sta0 hscale top-y base-y datum vscale hplot)
         (list (car ll) (nth 0 g) *pf-hscale-fixed*
               (cadr top) (cadr ll) (nth 1 g)
               (/ (nth 2 g) (nth 3 g))
               (nth 2 g)))))))

;;; ==========================================================================
;;; SECTION 6  --  TOOL 1:  C:PFXFIND   (crossing finder, plan only)
;;; ==========================================================================

(if (not (boundp '*pfx-crossings*)) (setq *pfx-crossings* nil))

(defun pfx:xing-tfile (e) (nth 0 e))
(defun pfx:xing-tbase (e) (nth 1 e))
(defun pfx:xing-sfile (e) (nth 2 e))
(defun pfx:xing-sbase (e) (nth 3 e))
(defun pfx:xing-xy    (e) (nth 4 e))
(defun pfx:xing-tsta  (e) (nth 5 e))
(defun pfx:xing-ssta  (e) (nth 6 e))
(defun pfx:xing-telev (e) (if (> (length e) 7) (nth 7 e)))
(defun pfx:xing-selev (e) (if (> (length e) 8) (nth 8 e)))

(defun pfx:xing-store-elevs (e telev selev / new)
  (setq new (list (nth 0 e) (nth 1 e) (nth 2 e) (nth 3 e)
                  (nth 4 e) (nth 5 e) (nth 6 e) telev selev))
  (setq *pfx-crossings* (subst new e *pfx-crossings*))
  new)

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
                        "   source sta " (pf:fmt-station (pfx:xing-ssta e))
                        (if (pfx:xing-telev e)
                          (strcat "   TGT inv " (rtos (pfx:xing-telev e) 2 2))
                          "")
                        (if (pfx:xing-selev e)
                          (strcat "   SRC inv " (rtos (pfx:xing-selev e) 2 2))
                          ""))))))
  (princ))

(defun c:PFXFIND ( / dcl_id tgt tverts dir files self chosen out
                     f path sverts xy tsta ssta xy2 tsta2 ssta2)
  (pf:load-apis)
  (setq tgt (pflabel:browse "Select TARGET Centerline (.CL) File"
                            '*pflabel-dir-cl* "cl"))
  (cond
    ((null tgt) (prompt "\nNo target selected -- cancelled."))
    ((null (setq tverts (pfx:get-verts tgt)))
     (prompt (strcat "\nCould not read plan geometry from " tgt " -- aborting.")))
    (T
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
                 (setq out '())
                 (foreach i chosen
                   (setq f      (nth i files)
                         path   (strcat dir f)
                         sverts (pfx:get-verts path))
                   (cond
                     ((null sverts)
                      (prompt (strcat "\n  " f " -- could not read plan geometry; skipped.")))
                     ((null (setq xy (pfx:poly-x tverts sverts)))
                      (prompt (strcat "\n  " f " -- does not cross the target.")))
                     (T
                      (setq tsta (pfx:sta-at tgt  xy)
                            ssta (pfx:sta-at path xy))
                      ;; Refine: re-intersect at fine step around the coarse
                      ;; hit; on success re-read both stations off the exact
                      ;; XY.  Falls back to the coarse values silently only
                      ;; when refinement can't sample (coarse is still good
                      ;; to ~half the sample step).
                      (if (and tsta ssta
                               (setq xy2 (pfx:refine-x tgt tsta path ssta)))
                        (progn
                          (setq tsta2 (pfx:sta-at tgt  xy2)
                                ssta2 (pfx:sta-at path xy2))
                          (if (and tsta2 ssta2)
                            (setq xy xy2 tsta tsta2 ssta ssta2))))
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
;;; SECTION 7  --  TOOL 2:  C:PFXLABEL   (invert reader + labeler)
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

(defun c:PFXLABEL ( / n pick e src-xf tgt-xf src-pipe tgt-pipe)
  (setq *pfx-prev-error* *error*
        *error*          pfx:*error*
        *pfx-undo-open*  nil)
  (cond
    ((null *pfx-crossings*)
     (prompt "\nNo crossings on record -- run PFXFIND first."))
    (T
     (pfx:print-crossings)
     (setq n (length *pfx-crossings*))
     (initget 6)
     (setq pick (getint (strcat "\nCrossing to label <1-" (itoa n) ">: ")))
     (cond
       ((or (null pick) (> pick n))
        (prompt "\nNo valid crossing picked -- cancelled."))
       (T
        (setq e (nth (1- pick) *pfx-crossings*))
        (setq src-xf (pfx:get-grid
                       (strcat "SOURCE (" (pfx:xing-sbase e) ")")))
        (if src-xf
          (progn
            (setq src-pipe (pfx:read-pipe "SOURCE" src-xf (pfx:xing-ssta e)))
            (if (null src-pipe)
              (prompt "\nSource pipe unreadable -- nothing drawn.")
              (progn
                (setq tgt-xf (pfx:get-grid
                               (strcat "TARGET (" (pfx:xing-tbase e) ")")))
                (if tgt-xf
                  (progn
                    (setq tgt-pipe (pfx:read-pipe "TARGET" tgt-xf
                                                  (pfx:xing-tsta e)))
                    (command "_.UNDO" "_Begin")
                    (setq *pfx-undo-open* T)
                    (pfx:draw-grid-side src-xf
                                        (pfx:xing-sfile e) (pfx:xing-ssta e)
                                        src-pipe
                                        (pfx:xing-tfile e) tgt-pipe)
                    (pfx:draw-grid-side tgt-xf
                                        (pfx:xing-tfile e) (pfx:xing-tsta e)
                                        tgt-pipe
                                        (pfx:xing-sfile e) src-pipe)
                    (pfx:xing-store-elevs e
                                          (if tgt-pipe (car tgt-pipe) nil)
                                          (if src-pipe (car src-pipe) nil))
                    (pfx:clear-table)
                    (pfx:draw-table tgt-xf)
                    (command "_.UNDO" "_End")
                    (setq *pfx-undo-open* nil)
                    (prompt (strcat "\nLabeled crossing "
                                    (pfx:xing-tbase e) " x "
                                    (pfx:xing-sbase e)
                                    " on both grids; PF-TABLE rebuilt."))))))))))))
  (setq *error* *pfx-prev-error*)
  (princ))

(princ "\npfcross.lsp loaded.  Commands: PFXFIND (find crossings), PFXLABEL (label one).")
(princ)
;;; ==========================================================================
;;; end of pfcross.lsp
;;; ==========================================================================
