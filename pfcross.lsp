;;; ==========================================================================
;;; pfcross.lsp  --  Pipe-crossing tools:  C:PFXFIND + C:PFXLABEL + C:PFXGRID
;;; --------------------------------------------------------------------------
;;; Requires pftools-lib.lsp, pfanchor.lsp, and pfdialog.lsp loaded first
;;; (engine, anchor/ledger/table module, grid dialog + browse helpers).
;;;
;;; TOOL 1  --  PFXFIND   (plan only, no grids)
;;;   Pick the TARGET .cl, check off candidate crossing .cl files from the
;;;   target's folder; intersects true .cl geometry (sampled, arcs followed)
;;;   to find every real crossing, refines each hit to ~0.1 ft, and reads
;;;   both stations off the Road API.
;;;   PERSISTENCE: when the target profile has a grid anchor, results MERGE
;;;   into its ledger (new records added, existing records keep their read
;;;   elevations -- re-running discovery is never destructive) and the
;;;   crossings table rebuilds.  With no anchor yet, results are held in
;;;   session and persist automatically when the target grid is first
;;;   defined in PFXLABEL.
;;;
;;; TOOL 2  --  PFXLABEL  (the loop: all sources, then the target, once)
;;;   Prints every crossing on record with derived status, then labels ONE
;;;   crossing (1-N) or [All] outstanding:
;;;     - source grids are keyed PER SOURCE FILE: one grid definition per
;;;       distinct source, however many crossings share it;
;;;     - grids are READ from anchors when registered (zero picks) and
;;;       picked + registered on the way out when not (pick once, ever);
;;;     - in All mode an UNREGISTERED source is SKIPPED AND REPORTED (CLI +
;;;       table STATUS column) -- label it individually once to register;
;;;     - the target grid is defined/read ONCE for the whole pass;
;;;     - partial failures (cancelled pick, unreadable pipe) skip that
;;;       crossing and the pass finishes; everything reports at the end;
;;;     - probed inverts persist to the ledger; the table block rebuilds
;;;       (replaced BY HANDLE -- no layer-scoped erase exists anywhere).
;;;   One undo group wraps every write in the pass -- anchors, ledger,
;;;   labels, table.  One U reverses it; Esc is unwound by the handler.
;;;
;;; TOOL 3  --  PFXGRID   (optional; never a gate)
;;;   Register or update a profile's grid anchor directly.
;;;
;;; COMPLETENESS MODEL: TARGET-ONLY.  A crossing is "labeled" when its
;;; station line stands on the target grid (exact X + top-Y match, see
;;; pfanchor.lsp).  Source-side annotation is drawn but not tracked.
;;;
;;; STATUS: ledger rewrite -- test on a scratch copy first.
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

;; Text: style must exist in the drawing; height is dynamically calculated
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
;; intersected, so stations on arcs are exact to ~0.1 ft.
(setq *pfx-refine-step* 0.1)

;; Placeholder when the block definition is missing from the drawing.
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

;; The invert ticks + elevation text stay on PF-TEMP, which is NEVER erased.
(setq *pfx-tick-layer* "PF-TEMP")

;; SESSION PENDING BUFFER.  Holds PFXFIND results ONLY while the target
;; profile has no grid anchor yet; merged into the ledger (and cleared) the
;; moment the target anchor exists.  The LEDGER is the system of record.
(if (not (boundp '*pfx-crossings*)) (setq *pfx-crossings* nil))

;; SESSION LAST TARGET.  Which profile PFXLABEL is working on, so repeat
;; runs continue the same target instead of re-asking.  The 'Target' option
;; at the crossing prompt clears it to switch profiles.
(if (not (boundp '*pfx-last-target*)) (setq *pfx-last-target* nil))


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

;; xform 8th element = horizontal PLOT scale (drives the sf scale factor).
(defun pfx:xf-hplot (xf) (nth 7 xf))
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
  (if (null (tblsearch "STYLE" style))
    (progn
      (prompt (strcat "\n  Warning: Style '" style
                      "' not found. Falling back to default."))
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
;;   Station lines land on *pfa-xing-layer* -- the layer reconciliation
;;   scans -- with their top vertex at exactly this grid's top-Y.  That
;;   X + top-Y pair is the "labeled" signature; do not change one without
;;   the other (see pfanchor.lsp SECTION 4).
(defun pfx:draw-grid-side (xform own-file own-sta own-pipe other-file
                           other-pipe / x ybot line-la vtxt-la y sf ht)
  (setq sf      (pfx:xf-sf xform)
        ht      (* 1.60 sf)
        x       (pf:station->profile-x own-sta xform)
        ybot    (- (pf:xf-basey xform) (* *pfx-line-ext* sf))
        line-la *pfa-xing-layer*
        vtxt-la "PF-XING-TEXT")

  (pfx:ensure-layer line-la)
  (pfx:ensure-layer vtxt-la)

  ;; station line
  (pf:draw-station-line x ybot (pf:grid-top-y xform) line-la)

  ;; vertical station text at the lower end, reading upward
  (pfx:text-right (list x ybot 0.0)
                  (strcat (pf:fmt-station own-sta) " "
                          (pfx:cross-desc other-file))
                  vtxt-la (/ pi 2.0) ht *pfx-vtext-style*)

  ;; the grid's OWN pipe (redundant) -> block + invert tick on PF-TEMP
  (if own-pipe
    (progn
      (setq y (pf:elev->profile-y (car own-pipe) xform))
      (pfx:ensure-layer (pfx:align-layer own-file))
      (pfx:insert-pipe (list x y) (cadr own-pipe)
                       (pfx:align-layer own-file) (pf:xf-vscale xform) sf)
      (pfx:ensure-layer *pfx-tick-layer*)
      (entmakex (list '(0 . "LINE") (cons 8 *pfx-tick-layer*)
                      (cons 10 (list (- x (* ht 0.75)) y 0.0))
                      (cons 11 (list (+ x (* ht 0.75)) y 0.0))))
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
;;; SECTION 4  --  Grid acquisition  (anchor first, pick as fallback)
;;; ==========================================================================

;; (pfx:pick-grid-xform role) -> 8-element xform | nil
;;   Corner picks + grid dialog (the pre-anchor pick path, unchanged).
(defun pfx:pick-grid-xform (role / ll top g)
  (prompt (strcat "\n== Define the " role " grid =="))
  (setq ll (getpoint (strcat "\nPick " role " grid LOWER-LEFT corner: ")))
  (if (null ll)
    (progn (prompt "\nNo point picked -- cancelled.") nil)
    (progn
      (setq top (getpoint ll (strcat "\nPick a point on the " role
                                     " grid TOP border: ")))
      (cond
        ((null top) (prompt "\nNo point picked -- cancelled.") nil)
        ((null (setq g (pflabel:show-grid-dialog)))
         (prompt "\nGrid dialog cancelled.") nil)
        (T
         ;; xform = (left-x sta0 hscale top-y base-y datum vscale hplot)
         (list (car ll) (nth 0 g) *pf-hscale-fixed*
               (cadr top) (cadr ll) (nth 1 g)
               (/ (nth 2 g) (nth 3 g))
               (nth 2 g)))))))

;; (pfx:anchored-xform anchor role) -> xform | nil
;;   Reads the registered grid; sanity-probes the corner.  On a failed probe
;;   the user may re-pick (anchor updated IN PLACE, ledger preserved) or
;;   trust the stored grid.  Caller must hold an open undo group (a re-pick
;;   writes).  nil = unreadable attributes, or re-pick chosen then cancelled.
(defun pfx:anchored-xform (anchor role / xf)
  (setq xf (pfa:anchor->xform anchor))
  (cond
    ((null xf)
     (prompt (strcat "\n" role ": anchor attributes unreadable."))
     nil)
    ((not (pfa:probe-corner (list (pf:xf-leftx xf) (pf:xf-basey xf))))
     (prompt (strcat "\n" role ": no grid line found at the stored anchor "
                     "corner (grid may have moved without its anchor)."))
     (initget "Yes No")
     (if (= (getkword (strcat "\nRe-pick the " role
                              " grid? [Yes/No] <No>: ")) "Yes")
       (progn
         (setq xf (pfx:pick-grid-xform role))
         (if xf
           (progn
             (pfa:reanchor anchor xf)
             ;; round-trip through the anchor so draw-time and every future
             ;; reconciliation compute bit-identical X values
             (pfa:anchor->xform anchor))))
       xf))
    (T xf)))


;;; ==========================================================================
;;; SECTION 5  --  Working list + status printing
;;; ==========================================================================
;;; Working entries are pfanchor 10-lists:
;;;   (key tfile tbase sfile sbase xy tsta ssta telev selev)

;; (pfx:print-crossings work recon) -> nil
(defun pfx:print-crossings (work recon / i e st)
  (if (null work)
    (prompt "\nNo crossings on record -- run PFXFIND.")
    (progn
      (prompt (strcat "\nCrossings vs target '"
                      (pfa:xr-tbase (car work)) "':"))
      (setq i 0)
      (foreach e work
        (setq i (1+ i)
              st (cond
                   ((null recon) "")
                   ((cdr (assoc (pfa:xr-key e) recon)) "   [LABELED]")
                   (T "   [OUTSTANDING]")))
        (prompt (strcat "\n  " (itoa i) ".  " (pfa:xr-sbase e)
                        "   target sta " (pf:fmt-station (pfa:xr-tsta e))
                        "   source sta " (pf:fmt-station (pfa:xr-ssta e))
                        (if (pfa:xr-telev e)
                          (strcat "   TGT inv " (rtos (pfa:xr-telev e) 2 2))
                          "")
                        (if (pfa:xr-selev e)
                          (strcat "   SRC inv " (rtos (pfa:xr-selev e) 2 2))
                          "")
                        st)))))
  (princ))

;; (pfx:ledger-has-source anchor sbase) -> T | nil
(defun pfx:ledger-has-source (anchor sbase / found e)
  (setq found nil)
  (foreach e (pfa:xing-list anchor)
    (if (= (strcase (pfa:xr-sbase e)) (strcase sbase)) (setq found T)))
  found)

;; (pfx:anchored-targets) -> list of (tfile line util count)
;;   Every registered profile in the drawing that has crossings on record
;;   AND a stored target .cl path -- i.e. everything PFXLABEL can run on
;;   without a file dialog.
(defun pfx:anchored-targets ( / out e at recs meta tfile)
  (setq out '())
  (foreach e (pfa:all-anchors)
    (setq recs (pfa:xing-list e))
    (if recs
      (progn
        (setq at    (pfa:read-attribs e)
              meta  (pfa:meta-get e)
              tfile (if (assoc 1 meta) (cdr (assoc 1 meta)) ""))
        (if (/= tfile "")
          (setq out (cons (list tfile
                                (pfa:att "LINE" at)
                                (pfa:att "UTIL" at)
                                (length recs))
                          out))))))
  (reverse out))

;; (pfx:resolve-target) -> target .cl path | nil
;;   Exhausts what is already known before ever opening a file dialog:
;;     1. pending PFXFIND results        -> their target
;;     2. last target this session       -> reuse silently (named)
;;     3. ONE registered profile w/ crossings -> use it (named)
;;     4. several                        -> short numbered pick (+ Browse)
;;     5. nothing on record              -> browse (the only cold-start path)
(defun pfx:resolve-target ( / cands i c pick)
  (cond
    (*pfx-crossings* (pfa:xr-tfile (car *pfx-crossings*)))
    (*pfx-last-target*
     (prompt (strcat "\nTarget: " (pfx:type-of *pfx-last-target*)
                     " '" (pfx:name-of *pfx-last-target*)
                     "'   ('Target' at the crossing prompt switches profiles)"))
     *pfx-last-target*)
    (T
     (setq cands (pfx:anchored-targets))
     (cond
       ((null cands)
        (pflabel:browse "Select TARGET Centerline (.CL) File"
                        '*pflabel-dir-cl* "cl"))
       ((= (length cands) 1)
        (prompt (strcat "\nTarget: " (nth 2 (car cands))
                        " '" (nth 1 (car cands))
                        "'   (only registered profile with crossings on record)"))
        (car (car cands)))
       (T
        (prompt "\nRegistered profiles with crossings on record:")
        (setq i 0)
        (foreach c cands
          (setq i (1+ i))
          (prompt (strcat "\n  " (itoa i) ".  " (nth 2 c) " '" (nth 1 c)
                          "'   (" (itoa (nth 3 c)) " crossing(s))")))
        (initget 6 "Browse")
        (setq pick (getint (strcat "\nTarget profile [Browse] <1-"
                                   (itoa (length cands)) ">: ")))
        (cond
          ((null pick) nil)
          ((= pick "Browse")
           (pflabel:browse "Select TARGET Centerline (.CL) File"
                           '*pflabel-dir-cl* "cl"))
          ((and (numberp pick) (>= pick 1) (<= pick (length cands)))
           (car (nth (1- pick) cands)))
          (T nil)))))))


;;; ==========================================================================
;;; SECTION 6  --  Error handler  (shared by all three commands)
;;; ==========================================================================

(if (not (boundp '*pfx-undo-open*)) (setq *pfx-undo-open* nil))

(defun pfx:*error* (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFX error: " msg)))
  (if *pfx-undo-open*
    (progn (command-s "_.UNDO" "_End") (setq *pfx-undo-open* nil)))
  (setq *error* *pfx-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 7  --  TOOL 1:  C:PFXFIND   (discovery -> ledger)
;;; ==========================================================================

(defun c:PFXFIND ( / dcl_id tgt tverts dir files self chosen out f path
                     sverts xy tsta ssta xy2 tsta2 ssta2 i line util anchor
                     e st cnt-new cnt-upd cnt-mov xform recon)
  (setq *pfx-prev-error* *error*
        *error*          pfx:*error*
        *pfx-undo-open*  nil)
  (pf:load-apis)
  (setq tgt (pflabel:browse "Select TARGET Centerline (.CL) File"
                            '*pflabel-dir-cl* "cl"))
  (cond
    ((null tgt) (prompt "\nNo target selected -- cancelled."))
    ((null (setq tverts (pfx:get-verts tgt)))
     (prompt (strcat "\nCould not read plan geometry from " tgt
                     " -- aborting.")))
    (T
     (setq *pfx-last-target* tgt)       ; session continuity for PFXLABEL
     (setq line   (pfx:name-of tgt)
           util   (pfx:type-of tgt)
           anchor (pfa:find-anchor line util)
           dir    (strcat (vl-filename-directory tgt) "\\")
           files  (acad_strlsort (vl-directory-files dir "*.cl" 1))
           self   (strcase (strcat (pfx:basename tgt) ".CL"))
           files  (vl-remove-if '(lambda (f) (= (strcase f) self)) files))
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
                 ;; ---- discovery (proven geometry, unchanged) ------------
                 (setq out '())
                 (foreach i chosen
                   (setq f      (nth i files)
                         path   (strcat dir f)
                         sverts (pfx:get-verts path))
                   (cond
                     ((null sverts)
                      (prompt (strcat "\n  " f
                                      " -- could not read plan geometry; skipped.")))
                     ((null (setq xy (pfx:poly-x tverts sverts)))
                      (prompt (strcat "\n  " f " -- does not cross the target."))
                      ;; stale-record heads-up: never silently deleted
                      (if (and anchor
                               (pfx:ledger-has-source anchor (pfx:basename path)))
                        (prompt (strcat "\n      NOTE: the ledger holds a "
                                        "crossing on record for this source; "
                                        "it may be stale (record kept)."))))
                     (T
                      (setq tsta (pfx:sta-at tgt  xy)
                            ssta (pfx:sta-at path xy))
                      (if (and tsta ssta
                               (setq xy2 (pfx:refine-x tgt tsta path ssta)))
                        (progn
                          (setq tsta2 (pfx:sta-at tgt  xy2)
                                ssta2 (pfx:sta-at path xy2))
                          (if (and tsta2 ssta2)
                            (setq xy xy2 tsta tsta2 ssta ssta2))))
                      (if (and tsta ssta)
                        (progn
                          (setq out (cons (list (pfa:xing-key
                                                  (pfx:basename path) tsta)
                                                tgt (pfx:basename tgt)
                                                path (pfx:basename path)
                                                (pfx:pt2 xy) tsta ssta
                                                nil nil)
                                          out))
                          (prompt (strcat "\n  " f " -- CROSSES at target sta "
                                          (pf:fmt-station tsta)
                                          ", source sta "
                                          (pf:fmt-station ssta))))
                        (prompt (strcat "\n  " f
                                        " -- crossing found but a station read "
                                        "failed; skipped."))))))
                 (setq out (reverse out))
                 ;; ---- persist (anchored) or pend (session) --------------
                 (cond
                   ((and anchor out)
                    (command "_.UNDO" "_Begin")
                    (setq *pfx-undo-open* T)
                    (setq cnt-new 0 cnt-upd 0 cnt-mov 0)
                    (foreach e out
                      (setq st (pfa:xing-merge anchor e))
                      (cond
                        ((eq st 'NEW)   (setq cnt-new (1+ cnt-new)))
                        ((eq st 'MOVED) (setq cnt-mov (1+ cnt-mov)))
                        (T              (setq cnt-upd (1+ cnt-upd)))))
                    (setq *pfx-crossings* nil)
                    (if (setq xform (pfa:anchor->xform anchor))
                      (pfa:rebuild-table anchor xform (pfx:active-style) nil))
                    (command "_.UNDO" "_End")
                    (setq *pfx-undo-open* nil)
                    (prompt (strcat "\n" (itoa (length out))
                                    " crossing(s) merged into the " util
                                    " '" line "' ledger  (" (itoa cnt-new)
                                    " new, " (itoa cnt-upd) " updated, "
                                    (itoa cnt-mov) " station-moved).  "
                                    "Elevations on record were preserved."))
                    (setq recon (if xform
                                  (pfa:recon xform (pfa:xing-list anchor))))
                    (pfx:print-crossings (pfa:xing-list anchor) recon))
                   (out
                    (setq *pfx-crossings* out)
                    (prompt (strcat "\n" (itoa (length out))
                                    " crossing(s) stored IN SESSION -- no grid "
                                    "anchor yet for " util " '" line "'.  They "
                                    "persist to the ledger when the target grid "
                                    "is first defined (PFXLABEL or PFXGRID + "
                                    "re-run)."))
                    (pfx:print-crossings out nil))
                   (T (prompt "\nNo crossings found.")))))))))))
  (setq *error* *pfx-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 8  --  TOOL 2:  C:PFXLABEL   (the loop)
;;; ==========================================================================

(defun c:PFXLABEL ( / tgt line util anchor xform style work recon n pick e
                     sel allmode groups g sfile sline sutil sanchor sxf sp tp
                     jobs j skips drawn xf2 sk)
  (setq *pfx-prev-error* *error*
        *error*          pfx:*error*
        *pfx-undo-open*  nil)
  (pf:load-apis)

  ;; ---- 0. target identity --------------------------------------------------
  (setq tgt (pfx:resolve-target))
  (if (null tgt)
    (prompt "\nNo target -- cancelled.")
    (progn
      (setq *pfx-last-target* tgt)      ; repeat runs continue this profile
      (setq line   (pfx:name-of tgt)
            util   (pfx:type-of tgt)
            style  (pfx:active-style)
            anchor (pfa:find-anchor line util)
            drawn  0
            skips  '())

      ;; ONE undo group wraps every write in the pass -- anchors, ledger,
      ;; labels, table.  Opened before the first possible write; Esc
      ;; anywhere is unwound by pfx:*error*.
      (command "_.UNDO" "_Begin")
      (setq *pfx-undo-open* T)

      ;; ---- 1. target grid: READ EARLY when anchored (no picks) ----------
      (if anchor
        (setq xform (pfx:anchored-xform anchor (strcat "TARGET (" line ")"))))

      ;; ---- 2. working list (the ledger is truth; pending merges in) -----
      (if (and anchor *pfx-crossings*)
        (progn
          (foreach e *pfx-crossings* (pfa:xing-merge anchor e))
          (setq *pfx-crossings* nil)
          (prompt "\nPending PFXFIND results persisted to the profile ledger.")))
      (setq work (if anchor (pfa:xing-list anchor) *pfx-crossings*))

      (cond
        ((null work)
         (prompt "\nNo crossings on record for this target -- run PFXFIND."))
        (T
         (setq work  (vl-sort work '(lambda (a b)
                                      (< (pfa:xr-tsta a) (pfa:xr-tsta b))))
               recon (if xform (pfa:recon xform work))
               n     (length work))

         ;; ---- 3. print + select --------------------------------------
         (pfx:print-crossings work recon)
         (initget 6 "All Target")
         (setq pick (getint (strcat "\nCrossing to label [All/Target] <1-"
                                    (itoa n) ">: ")))
         (setq allmode (= pick "All"))
         (cond
           ((null pick) (prompt "\nNothing picked -- cancelled."))
           ((= pick "Target")
            (setq *pfx-last-target* nil)
            (prompt "\nSession target cleared -- run PFXLABEL again to choose a profile."))
           ((and (not allmode) (or (not (numberp pick)) (> pick n)))
            (prompt "\nNo valid crossing picked -- cancelled."))
           (T
            (if allmode
              ;; All = every OUTSTANDING crossing (target-only completeness);
              ;; with no target grid yet nothing can be labeled -> all.
              (setq sel (if recon
                          (vl-remove-if
                            '(lambda (e) (cdr (assoc (pfa:xr-key e) recon)))
                            work)
                          work))
              (progn
                (setq e (nth (1- pick) work) sel (list e))
                (if (and recon (cdr (assoc (pfa:xr-key e) recon)))
                  (progn
                    (prompt (strcat "\nThat crossing is already labeled on "
                                    "the target grid; labeling again will "
                                    "draw DUPLICATE entities."))
                    (initget "Yes No")
                    (if (/= (getkword "\nProceed anyway? [Yes/No] <No>: ")
                            "Yes")
                      (setq sel nil))))))
            (cond
              ((null sel)
               (prompt (if allmode
                         "\nAll crossings are already labeled -- nothing to do."
                         "\nCancelled.")))
              (T
               ;; ---- 4. SOURCE phase: grids keyed PER SOURCE FILE ------
               (setq groups '())
               (foreach e sel
                 (setq g (assoc (strcase (pfa:xr-sfile e)) groups))
                 (setq groups
                       (if g
                         (subst (append g (list e)) g groups)
                         (append groups
                                 (list (list (strcase (pfa:xr-sfile e))
                                             e))))))
               (setq jobs '())
               (foreach g groups
                 (setq sfile   (pfa:xr-sfile (cadr g))
                       sline   (pfx:name-of sfile)
                       sutil   (pfx:type-of sfile)
                       sanchor (pfa:find-anchor sline sutil)
                       sxf     nil)
                 (cond
                   ;; registered source -> read it (zero picks)
                   (sanchor
                    (setq sxf (pfx:anchored-xform
                                sanchor
                                (strcat "SOURCE (" (pfx:basename sfile) ")")))
                    (if (null sxf)
                      (foreach e (cdr g)
                        (setq skips (cons (list (pfa:xr-key e)
                                                (pfa:xr-sbase e)
                                                (pfa:xr-tsta e)
                                                "SOURCE GRID UNREADABLE")
                                          skips)))))
                   ;; single pick keeps the inline pick path -- and
                   ;; registers the anchor on the way out (pick once, ever)
                   ((not allmode)
                    (setq sxf (pfx:pick-grid-xform
                                (strcat "SOURCE (" (pfx:basename sfile) ")")))
                    (if sxf
                      (progn
                        (setq sanchor (pfa:write-anchor sline sutil sxf sfile))
                        ;; round-trip through the anchor: draw-time and all
                        ;; future recon X math stay bit-identical
                        (setq sxf (pfa:anchor->xform sanchor)))
                      (foreach e (cdr g)
                        (setq skips (cons (list (pfa:xr-key e)
                                                (pfa:xr-sbase e)
                                                (pfa:xr-tsta e)
                                                "SOURCE GRID PICK CANCELLED")
                                          skips)))))
                   ;; All mode + unregistered source => SKIP AND REPORT
                   (T
                    (prompt (strcat "\n  " (pfx:basename sfile)
                                    " -- no grid registered; skipped "
                                    (itoa (length (cdr g)))
                                    " crossing(s).  (Label one individually "
                                    "to register its grid.)"))
                    (foreach e (cdr g)
                      (setq skips (cons (list (pfa:xr-key e)
                                              (pfa:xr-sbase e)
                                              (pfa:xr-tsta e)
                                              "NO GRID REGISTERED")
                                        skips)))))
                 ;; probe every crossing on this source's ONE grid
                 (if sxf
                   (foreach e (cdr g)
                     (setq sp (pfx:read-pipe
                                (strcat "SOURCE (" (pfa:xr-sbase e) ")")
                                sxf (pfa:xr-ssta e)))
                     (if sp
                       (setq jobs (cons (list e sxf sp) jobs))
                       (setq skips (cons (list (pfa:xr-key e)
                                               (pfa:xr-sbase e)
                                               (pfa:xr-tsta e)
                                               "SOURCE PIPE UNREADABLE")
                                         skips))))))
               (setq jobs (reverse jobs))

               ;; ---- 5. TARGET grid, once ------------------------------
               (if (and jobs (null xform))
                 (progn
                   (setq xf2 (pfx:pick-grid-xform
                               (strcat "TARGET (" line ")")))
                   (cond
                     ((null xf2)
                      (foreach j jobs
                        (setq e (car j))
                        (setq skips (cons (list (pfa:xr-key e)
                                                (pfa:xr-sbase e)
                                                (pfa:xr-tsta e)
                                                "TARGET GRID PICK CANCELLED")
                                          skips)))
                      (setq jobs '()))
                     (anchor        ; existed but was unreadable / moved
                      (pfa:reanchor anchor xf2)
                      (setq xform (pfa:anchor->xform anchor)))
                     (T
                      (setq anchor (pfa:write-anchor line util xf2 tgt)
                            xform  (pfa:anchor->xform anchor))
                      ;; the ledger now exists: persist the working set
                      (foreach e work (pfa:xing-merge anchor e))
                      (setq *pfx-crossings* nil)))))

               ;; ---- 6. target probes + BOTH-SIDE draw + ledger elevs --
               (foreach j jobs
                 (setq e   (nth 0 j)
                       sxf (nth 1 j)
                       sp  (nth 2 j)
                       tp  (pfx:read-pipe (strcat "TARGET (" line ")")
                                          xform (pfa:xr-tsta e)))
                 ;; source side: own pipe = source's, other = target's
                 (pfx:draw-grid-side sxf (pfa:xr-sfile e) (pfa:xr-ssta e)
                                     sp tgt tp)
                 ;; target side: own pipe = target's, other = source's
                 (pfx:draw-grid-side xform tgt (pfa:xr-tsta e)
                                     tp (pfa:xr-sfile e) sp)
                 (if anchor
                   (pfa:xing-put-elevs anchor (pfa:xr-key e)
                                       (if tp (car tp)) (if sp (car sp))))
                 (setq drawn (1+ drawn)))

               ;; ---- 7. table (replaced BY HANDLE; skips rendered) -----
               (if (and anchor xform)
                 (pfa:rebuild-table anchor xform style skips))

               ;; ---- 8. pass report ------------------------------------
               (prompt (strcat "\n== PFXLABEL pass: " (itoa drawn)
                               " crossing(s) labeled, "
                               (itoa (length skips)) " skipped =="))
               (foreach sk (reverse skips)
                 (prompt (strcat "\n  SKIPPED  " (cadr sk)
                                 " @ target sta "
                                 (pf:fmt-station (caddr sk))
                                 "  -- " (nth 3 sk)))))))))
      (if *pfx-undo-open*
        (progn (command "_.UNDO" "_End") (setq *pfx-undo-open* nil))))))
  (setq *error* *pfx-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 9  --  TOOL 3:  C:PFXGRID   (register / update a grid anchor)
;;; ==========================================================================

(defun c:PFXGRID ( / f line util anchor xf)
  (setq *pfx-prev-error* *error*
        *error*          pfx:*error*
        *pfx-undo-open*  nil)
  (setq f (pflabel:browse "Select Centerline (.CL) for This Profile Grid"
                          '*pflabel-dir-cl* "cl"))
  (if (null f)
    (prompt "\nCancelled.")
    (progn
      (setq line   (pfx:name-of f)
            util   (pfx:type-of f)
            anchor (pfa:find-anchor line util))
      (if anchor
        (prompt (strcat "\n" util " '" line "' already has a grid anchor -- "
                        "re-picking updates it in place (ledger preserved).")))
      (setq xf (pfx:pick-grid-xform (strcat util " '" line "'")))
      (if xf
        (progn
          (command "_.UNDO" "_Begin")
          (setq *pfx-undo-open* T)
          (if anchor
            (pfa:reanchor anchor xf)
            (pfa:write-anchor line util xf f))
          (command "_.UNDO" "_End")
          (setq *pfx-undo-open* nil))
        (prompt "\nNo grid defined."))))
  (setq *error* *pfx-prev-error*)
  (princ))


(princ "\npfcross.lsp loaded.  Commands: PFXFIND (find crossings -> ledger), ")
(princ "PFXLABEL (label 1-N or All), PFXGRID (register a grid).")
(princ)
;;; ==========================================================================
;;; end of pfcross.lsp
;;; ==========================================================================
