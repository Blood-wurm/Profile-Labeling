;;; ==========================================================================
;;; pfsetup.lsp  --  C:PFXSETUP : batch grid registration by sheet window
;;; --------------------------------------------------------------------------
;;; Requires pftools-lib.lsp and pfanchor.lsp loaded first.  Loads BEFORE
;;; pfcross.lsp (which supplies pfx:name-of / pfx:type-of at RUN time only --
;;; no load-order dependency on those).
;;;
;;; WHAT IT DOES
;;;   One window per discipline column registers every profile grid in that
;;;   column, replacing the corner-pick workflow.  The sheet is already
;;;   self-describing; this reads it:
;;;
;;;     corner + extent  <- PF-HBOX cluster       (left-x, base-y)
;;;     top border       <- PF-GRID-MJR verticals (top-y)
;;;     sta0             <- station labels below the grid    ("1+00")
;;;     datum + v-scale  <- elevation labels left of the grid ("568")
;;;     plot scales      <- the scale note        ("HORIZ. 1"=20'")
;;;     identity         <- PF-NAME               ("STORM LINE 'DA'")
;;;
;;; THE USER'S WINDOW IS A TYPE ASSERTION.  The type is prompted FIRST, so
;;; PF-NAME parsing only has to yield the line NAME, the .cl match runs
;;; against one utility's files, and anything in the window that doesn't
;;; match the asserted type is reported and skipped -- never guessed at.
;;;
;;; DUAL-SOURCE VALIDATION (the safety property):
;;;   Nearly every field has two independent derivations -- printed vs.
;;;   geometric.  They must AGREE or the grid is reported and left
;;;   UNREGISTERED.  A mis-picked corner fails loudly (the probe finds
;;;   nothing); a mis-READ datum would fail silently and poison everything
;;;   downstream, so inference is never trusted on one source alone:
;;;     - station labels must reproduce the fixed 1:1 h-scale across the row
;;;     - elevation labels must agree on ONE v-scale across the axis
;;;     - the printed plot scales must reproduce that measured v-scale
;;;
;;; SAFETY: the scan is PURE (ssget/entget only).  Nothing is written until
;;; the user confirms, and every write lands in one undo group.  Existing
;;; anchors are updated in place (ledger preserved), never duplicated.
;;;
;;; STATUS: new module -- the parser is calibrated to the observed sheet
;;; conventions and WANTS ITERATION against real drawings.  Read the report
;;; before confirming; that is what it is for.
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  the sheet's drafting conventions; change here, nowhere else.
;;; --------------------------------------------------------------------------

(setq *pfs-hbox-layer*  "PF-HBOX")        ; grid bottom border + station box
(setq *pfs-mjr-layer*   "PF-GRID-MJR")    ; major verticals -> top border
(setq *pfs-name-layer*  "PF-NAME")        ; "STORM LINE 'DA'"
(setq *pfs-scale-layer* "PF-TEXT")        ; "SCALE: HORIZ. 1"=20'  VERT. 1"=2'"

;; Elevation axis labels and station labels may share a layer -- they are
;; separated by POSITION, not layer (elevations sit left of the grid,
;; stations sit below it), so sharing is safe.
(setq *pfs-elevtext-layers* "PF-GRID-TEXT")
(setq *pfs-statext-layers*  "PF-GRID-TEXT")

;; NEVER READ.  Per-station ground elevations: rotated text inside the grid
;; column that would otherwise be mistaken for axis labels.  Listed here so
;; a future drawing that moves them onto an axis-label layer fails loudly
;; against the v-scale agreement check rather than silently misreading.
(setq *pfs-groundtext-layer* "PF-GROUND-TEXT_X")

;; Clustering: HBOX entities whose bounding boxes share a top edge within
;; this tolerance belong to the SAME grid.  Grids in a column are separated
;; by far more than this.
(setq *pfs-cluster-tol* 1.0)

;; Agreement tolerances for dual-source validation.
(setq *pfs-sta-tol*    0.10)   ; station labels vs. 1:1 h-scale (feet)
(setq *pfs-vscale-tol* 0.02)   ; v-scale agreement across axis labels
(setq *pfs-scale-tol*  0.02)   ; printed plot scales vs. measured v-scale

;; Known utility types (the window's type assertion picks one).
(setq *pfs-types* '("STORM" "SANITARY" "WATER"))


;;; ==========================================================================
;;; SECTION 1  --  Pure parsing helpers
;;; ==========================================================================

;; (pfs:trim s) -> s without leading/trailing blanks
(defun pfs:trim (s) (vl-string-trim " \t" s))

;; (pfs:parse-station "1+00") -> 100.0 | nil
(defun pfs:parse-station (s / pos hund rem)
  (setq s (pfs:trim s))
  (if (setq pos (vl-string-search "+" s))
    (progn
      (setq hund (distof (pfs:trim (substr s 1 pos)) 2)
            rem  (distof (pfs:trim (substr s (+ pos 2))) 2))
      (if (and hund rem (>= rem 0.0))
        (+ (* hund 100.0) rem)))))

;; (pfs:parse-elev "568") -> 568.0 | nil   (plain decimal only)
(defun pfs:parse-elev (s)
  (distof (pfs:trim s) 2))

;; (pfs:num-after s tok) -> first number appearing after `tok` | nil
;;   Skips to the first digit past the token, then reads digits and dots.
(defun pfs:num-after (s tok / p i c out n)
  (setq s (strcase s))
  (if (setq p (vl-string-search (strcase tok) s))
    (progn
      (setq i (+ p (strlen tok) 1) out "" n (strlen s))
      (while (and (<= i n) (not (pf:digit-p (substr i 1 1))) 
                  (not (pf:digit-p (substr s i 1))))
        (setq i (1+ i)))
      (while (and (<= i n)
                  (or (pf:digit-p (substr s i 1)) (= (substr s i 1) ".")))
        (setq out (strcat out (substr s i 1)) i (1+ i)))
      (if (/= out "") (distof out 2)))))

;; (pfs:from-token s tok) -> substring of s starting at tok | nil
(defun pfs:from-token (s tok / p)
  (if (setq p (vl-string-search (strcase tok) (strcase s)))
    (substr s (1+ p))))

;; (pfs:parse-scale s) -> (hplot . vplot) | (h . nil) | (nil . v) | nil
;;   Handles both one combined note and separate HORIZ / VERT strings:
;;     "SCALE: HORIZ. 1\"=20'  VERT. 1\"=2'"
(defun pfs:parse-scale (s / h v hs vs)
  (if (setq hs (pfs:from-token s "HORIZ")) (setq h (pfs:num-after hs "=")))
  (if (setq vs (pfs:from-token s "VERT"))  (setq v (pfs:num-after vs "=")))
  (if (or h v) (cons h v)))

;; (pfs:parse-name s type) -> line name | nil
;;   The window already asserted the type, so this only extracts the quoted
;;   name -- and confirms the printed type matches the assertion.
;;   "STORM LINE 'DA'" + "STORM" -> "DA"
(defun pfs:parse-name (s type / u p1 p2)
  (setq u (strcase s))
  (if (vl-string-search (strcase type) u)
    (progn
      (setq p1 (vl-string-search "'" u))
      (if (null p1) (setq p1 (vl-string-search "`" u)))
      (if p1 (setq p2 (vl-string-search "'" u (1+ p1))))
      (if (and p1 p2 (> p2 (1+ p1)))
        (pfs:trim (substr u (+ p1 2) (- p2 p1 1)))))))

;; (pfs:printed-type s) -> "STORM" | "SANITARY" | "WATER" | nil
(defun pfs:printed-type (s / u found)
  (setq u (strcase s) found nil)
  (foreach k *pfs-types*
    (if (and (null found) (vl-string-search k u)) (setq found k)))
  found)


;;; ==========================================================================
;;; SECTION 2  --  Geometry helpers  (pure reads)
;;; ==========================================================================

;; (pfs:bbox e) -> (minx miny maxx maxy) | nil
(defun pfs:bbox (e / o mn mx r)
  (setq o (vlax-ename->vla-object e))
  (setq r (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx)))
  (if (not (vl-catch-all-error-p r))
    (progn
      (setq mn (vlax-safearray->list mn)
            mx (vlax-safearray->list mx))
      (list (car mn) (cadr mn) (car mx) (cadr mx)))))

;; (pfs:text-pos ed) -> insertion point honoring justification
(defun pfs:text-pos (ed / j1 j2)
  (setq j1 (cdr (assoc 72 ed))
        j2 (cdr (assoc 73 ed)))
  (if (and (assoc 11 ed)
           (or (and j1 (/= j1 0)) (and j2 (/= j2 0))))
    (cdr (assoc 11 ed))
    (cdr (assoc 10 ed))))

;; (pfs:ss->list ss) -> list of enames
(defun pfs:ss->list (ss / i out)
  (setq out '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq out (cons (ssname ss i) out) i (1+ i))))
  (reverse out))

;; (pfs:on-layer-p e la) -> T | nil   (exact, case-insensitive)
(defun pfs:on-layer-p (e la)
  (= (strcase (cdr (assoc 8 (entget e)))) (strcase la)))

;; (pfs:filter-layer ents la) -> ents on that layer
(defun pfs:filter-layer (ents la)
  (vl-remove-if-not '(lambda (e) (pfs:on-layer-p e la)) ents))


;;; ==========================================================================
;;; SECTION 3  --  Grid discovery  (HBOX clustering -> corner + extent)
;;; ==========================================================================
;;; A grid's PF-HBOX entities (the bottom border and the station-column
;;; ticks hanging below it) all share a TOP edge at the grid's base-y.
;;; Clustering on that shared top edge separates stacked grids cleanly --
;;; each has its own HBOX at its own Y, so even adjacent grids can't merge.

;; (pfs:cluster-hbox ents) -> list of (base-y left-x right-x)
(defun pfs:cluster-hbox (ents / boxes cls e bb placed c out)
  (setq boxes '())
  (foreach e ents
    (if (setq bb (pfs:bbox e)) (setq boxes (cons bb boxes))))
  (setq cls '())
  (foreach bb boxes
    (setq placed nil)
    (setq cls
      (mapcar
        '(lambda (c)
           (if (and (null placed)
                    (<= (abs (- (car c) (nth 3 bb))) *pfs-cluster-tol*))
             (progn
               (setq placed T)
               (list (max (car c) (nth 3 bb))          ; base-y  (top edge)
                     (min (cadr c) (car bb))           ; left-x
                     (max (caddr c) (nth 2 bb))))      ; right-x
             c))
        cls))
    (if (null placed)
      (setq cls (cons (list (nth 3 bb) (car bb) (nth 2 bb)) cls))))
  ;; top-most grid first (reading order down the column)
  (vl-sort cls '(lambda (a b) (> (car a) (car b)))))

;; (pfs:top-y ents base-y left-x right-x) -> real | nil
;;   Highest point reached by PF-GRID-MJR verticals standing on this grid.
;;   X-bounded to the grid's own extent, Y-bounded above its base, so a
;;   neighbouring grid's verticals can never contribute.
(defun pfs:top-y (ents base-y left-x right-x / best bb cx)
  (setq best nil)
  (foreach e ents
    (if (setq bb (pfs:bbox e))
      (progn
        (setq cx (/ (+ (car bb) (nth 2 bb)) 2.0))
        (if (and (>= cx (- left-x *pfs-cluster-tol*))
                 (<= cx (+ right-x *pfs-cluster-tol*))
                 (> (nth 3 bb) (+ base-y *pfs-cluster-tol*)))
          (if (or (null best) (> (nth 3 bb) best))
            (setq best (nth 3 bb)))))))
  best)


;;; ==========================================================================
;;; SECTION 4  --  Annotation reading  (station / elevation / name / scale)
;;; ==========================================================================

;; (pfs:station-labels ents base-y left-x right-x) -> list of (x . sta)
;;   TEXT below the grid's base, inside its X extent, parsing as a station.
(defun pfs:station-labels (ents base-y left-x right-x / out ed p s)
  (setq out '())
  (foreach e ents
    (setq ed (entget e)
          p  (pfs:text-pos ed))
    (if (and p
             (< (cadr p) base-y)
             (>= (car p) (- left-x 5.0))
             (<= (car p) (+ right-x 5.0))
             (setq s (pfs:parse-station (cdr (assoc 1 ed)))))
      (setq out (cons (cons (car p) s) out))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

;; (pfs:elev-labels ents base-y top-y left-x) -> list of (y . elev)
;;   TEXT left of the grid, within its vertical span, parsing as a number.
(defun pfs:elev-labels (ents base-y top-y left-x / out ed p v)
  (setq out '())
  (foreach e ents
    (setq ed (entget e)
          p  (pfs:text-pos ed))
    (if (and p
             (< (car p) left-x)
             (>= (cadr p) (- base-y *pfs-cluster-tol*))
             (<= (cadr p) (+ top-y *pfs-cluster-tol*))
             (setq v (pfs:parse-elev (cdr (assoc 1 ed)))))
      (setq out (cons (cons (cadr p) v) out))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

;; (pfs:nearest-below ents base-y left-x right-x) -> entget of the closest
;;   TEXT sitting below this grid (and above the next one down) | nil
(defun pfs:nearest-below (ents base-y left-x right-x / best bd ed p d)
  (setq best nil bd nil)
  (foreach e ents
    (setq ed (entget e)
          p  (pfs:text-pos ed))
    (if (and p (< (cadr p) base-y)
             (>= (car p) (- left-x 10.0))
             (<= (car p) (+ right-x 10.0)))
      (progn
        (setq d (- base-y (cadr p)))
        (if (or (null bd) (< d bd)) (setq bd d best ed)))))
  best)


;;; ==========================================================================
;;; SECTION 5  --  Derivation + dual-source validation
;;; ==========================================================================
;;; Each grid record is:
;;;   (base-y left-x right-x top-y sta0 datum vscale hplot vplot name notes)
;;; `notes` is a list of failure strings; a grid with notes is REPORTED and
;;; NOT REGISTERED.  Nothing is ever registered on a single source.

;; (pfs:derive-sta0 labels left-x) -> (sta0 . note) -- note nil on success
;;   sta0 from the leftmost label, then EVERY other label must reproduce the
;;   fixed 1:1 h-scale from it.  That agreement is what confirms the scale
;;   assumption per grid instead of assuming it globally.
(defun pfs:derive-sta0 (labels left-x / s0 bad pred)
  (cond
    ((null labels) (cons nil "no station labels found below the grid"))
    (T
     (setq s0 (- (cdr (car labels)) (- (car (car labels)) left-x)))
     (setq bad nil)
     (foreach l labels
       (setq pred (+ s0 (- (car l) left-x)))       ; h-scale fixed at 1.0
       (if (> (abs (- pred (cdr l))) *pfs-sta-tol*) (setq bad T)))
     (if bad
       (cons nil "station labels disagree with 1:1 horizontal scale")
       (cons s0 nil)))))

;; (pfs:derive-vert labels base-y) -> (vscale datum . note)
;;   v-scale from the spread of the axis labels; every adjacent pair must
;;   agree, and every label must then reproduce one datum.
(defun pfs:derive-vert (labels base-y / n lo hi vs bad datum d2 prev)
  (cond
    ((or (null labels) (< (length labels) 2))
     (list nil nil "fewer than two elevation labels left of the grid"))
    (T
     (setq lo (car labels) hi (last labels))
     (if (<= (abs (- (cdr hi) (cdr lo))) 1e-9)
       (list nil nil "elevation labels do not differ in value")
       (progn
         (setq vs (/ (- (car hi) (car lo)) (- (cdr hi) (cdr lo))))
         (if (<= vs 0.0)
           (list nil nil "elevation labels imply a non-positive v-scale")
           (progn
             ;; every adjacent pair must reproduce the same v-scale
             (setq bad nil prev nil)
             (foreach l labels
               (if prev
                 (progn
                   (setq d2 (- (cdr l) (cdr prev)))
                   (if (> (abs d2) 1e-9)
                     (if (> (abs (- (/ (- (car l) (car prev)) d2) vs))
                            *pfs-vscale-tol*)
                       (setq bad T)))))
               (setq prev l))
             (if bad
               (list nil nil "elevation labels disagree on a single v-scale")
               (progn
                 (setq datum (- (cdr lo) (/ (- (car lo) base-y) vs)))
                 (list vs datum nil))))))))))

;; (pfs:check-scales h v vscale) -> note | nil
;;   The PRINTED plot scales must reproduce the MEASURED v-scale.  This is
;;   the dual-source check that catches a misread axis or a stale scale note.
(defun pfs:check-scales (h v vscale)
  (cond
    ((null h) "scale note: horizontal scale not found")
    ((null v) "scale note: vertical scale not found")
    ((or (<= h 0.0) (<= v 0.0)) "scale note: non-positive scale")
    ((> (abs (- (/ h v) vscale)) *pfs-scale-tol*)
     (strcat "printed scale H:" (rtos h 2 0) " V:" (rtos v 2 0)
             " implies v-scale " (rtos (/ h v) 2 2)
             " but the axis labels measure " (rtos vscale 2 2)))
    (T nil)))


;;; ==========================================================================
;;; SECTION 6  --  The scan  (PURE -- reads the window, writes nothing)
;;; ==========================================================================

;; (pfs:scan ents type) -> list of grid records
(defun pfs:scan (ents type / hbox mjr etxt stxt ntxt sctxt cls out
                             base-y left-x right-x top-y
                             slabs elabs s0r vr vs datum sta0
                             ned scale h v nm notes rec)
  (setq hbox  (pfs:filter-layer ents *pfs-hbox-layer*)
        mjr   (pfs:filter-layer ents *pfs-mjr-layer*)
        etxt  (pfs:filter-layer ents *pfs-elevtext-layers*)
        stxt  (pfs:filter-layer ents *pfs-statext-layers*)
        ntxt  (pfs:filter-layer ents *pfs-name-layer*)
        sctxt (pfs:filter-layer ents *pfs-scale-layer*))
  ;; The ground-elevation layer is never read.  Guard the axis-label set in
  ;; case a drawing ever puts them on the same layer.
  (setq etxt (vl-remove-if
               '(lambda (e) (pfs:on-layer-p e *pfs-groundtext-layer*)) etxt))
  (setq cls (pfs:cluster-hbox hbox)
        out '())
  (foreach c cls
    (setq base-y  (car c)
          left-x  (cadr c)
          right-x (caddr c)
          notes   '()
          sta0 nil datum nil vs nil h nil v nil nm nil)
    (setq top-y (pfs:top-y mjr base-y left-x right-x))
    (if (null top-y)
      (setq notes (cons "no PF-GRID-MJR verticals found above this grid"
                        notes))
      (progn
        ;; ---- horizontal: sta0 + 1:1 agreement -------------------------
        (setq slabs (pfs:station-labels stxt base-y left-x right-x)
              s0r   (pfs:derive-sta0 slabs left-x)
              sta0  (car s0r))
        (if (cdr s0r) (setq notes (cons (cdr s0r) notes)))
        ;; ---- vertical: v-scale + datum --------------------------------
        (setq elabs (pfs:elev-labels etxt base-y top-y left-x)
              vr    (pfs:derive-vert elabs base-y)
              vs    (car vr)
              datum (cadr vr))
        (if (caddr vr) (setq notes (cons (caddr vr) notes)))
        ;; ---- printed plot scales + agreement --------------------------
        (setq ned (pfs:nearest-below sctxt base-y left-x right-x))
        (if (null ned)
          (setq notes (cons "no scale note found below the grid" notes))
          (progn
            (setq scale (pfs:parse-scale (cdr (assoc 1 ned)))
                  h     (car scale)
                  v     (cdr scale))
            (if vs
              (if (setq nm (pfs:check-scales h v vs))
                (setq notes (cons nm notes))))
            (setq nm nil)))
        ;; ---- identity (type already asserted by the window) ------------
        (setq ned (pfs:nearest-below ntxt base-y left-x right-x))
        (cond
          ((null ned)
           (setq notes (cons "no PF-NAME label found below the grid" notes)))
          ((null (setq nm (pfs:parse-name (cdr (assoc 1 ned)) type)))
           (setq notes
                 (cons (strcat "PF-NAME reads \"" (cdr (assoc 1 ned))
                               "\" -- not a "  type
                               " line name; wrong column in the window?")
                       notes))))))
    (setq rec (list base-y left-x right-x top-y sta0 datum vs h v nm
                    (reverse notes)))
    (setq out (cons rec out)))
  (reverse out))

;; record accessors
(defun pfs:r-basey (r) (nth 0 r))
(defun pfs:r-leftx (r) (nth 1 r))
(defun pfs:r-topy  (r) (nth 3 r))
(defun pfs:r-sta0  (r) (nth 4 r))
(defun pfs:r-datum (r) (nth 5 r))
(defun pfs:r-vs    (r) (nth 6 r))
(defun pfs:r-hplot (r) (nth 7 r))
(defun pfs:r-vplot (r) (nth 8 r))
(defun pfs:r-name  (r) (nth 9 r))
(defun pfs:r-notes (r) (nth 10 r))

;; (pfs:r-ok-p r) -> T when every field parsed AND every check agreed
(defun pfs:r-ok-p (r)
  (and (null (pfs:r-notes r))
       (pfs:r-topy r) (pfs:r-sta0 r) (pfs:r-datum r)
       (pfs:r-vs r) (pfs:r-hplot r) (pfs:r-vplot r) (pfs:r-name r)))

;; (pfs:r-xform r) -> 8-element xform
;;   (left-x sta0 hscale top-y base-y datum v-scale hplot)
(defun pfs:r-xform (r)
  (list (pfs:r-leftx r) (pfs:r-sta0 r) *pf-hscale-fixed*
        (pfs:r-topy r) (pfs:r-basey r) (pfs:r-datum r)
        (pfs:r-vs r) (pfs:r-hplot r)))


;;; ==========================================================================
;;; SECTION 7  --  .cl matching
;;; ==========================================================================

;; (pfs:cl-match dir type name) -> full path | nil
;;   Matches "Type_Name.cl" against the asserted type and the parsed name.
;;   The type assertion shrinks the match space to one utility's files.
(defun pfs:cl-match (dir type name / files f found base pos ty nm)
  (setq files (vl-directory-files dir "*.cl" 1) found nil)
  (foreach f files
    (if (null found)
      (progn
        (setq base (vl-filename-base f)
              pos  (vl-string-search "_" base))
        (if pos
          (progn
            (setq ty (strcase (substr base 1 pos))
                  nm (strcase (substr base (+ pos 2))))
            (if (and (= ty (strcase type)) (= nm (strcase name)))
              (setq found (strcat dir f))))))))
  found)


;;; ==========================================================================
;;; SECTION 8  --  C:PFXSETUP
;;; ==========================================================================

(if (not (boundp '*pfs-undo-open*)) (setq *pfs-undo-open* nil))
(if (not (boundp '*pfs-dir*))       (setq *pfs-dir* ""))

(defun pfs:*error* (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFXSETUP error: " msg)))
  (if *pfs-undo-open*
    (progn (command-s "_.UNDO" "_End") (setq *pfs-undo-open* nil)))
  (setq *error* *pfs-prev-error*)
  (princ))

;; (pfs:report recs type dir) -> list of (rec . tfile) for the OK ones
;;   Prints one line per grid found.  A grid is listed OK only when every
;;   field parsed, every dual-source check agreed, AND its .cl was matched.
(defun pfs:report (recs type dir / i out tfile ok)
  (setq i 0 out '())
  (foreach r recs
    (setq i (1+ i) tfile nil)
    (cond
      ((not (pfs:r-ok-p r))
       (prompt (strcat "\n  " (itoa i) ".  "
                       (if (pfs:r-name r)
                         (strcat type " '" (pfs:r-name r) "'")
                         (strcat "grid at Y " (rtos (pfs:r-basey r) 2 2)))
                       "   -- NOT REGISTERED"))
       (foreach n (pfs:r-notes r) (prompt (strcat "\n        " n))))
      ((null (setq tfile (pfs:cl-match dir type (pfs:r-name r))))
       (prompt (strcat "\n  " (itoa i) ".  " type " '" (pfs:r-name r)
                       "'   -- NOT REGISTERED"))
       (prompt (strcat "\n        no " type "_" (pfs:r-name r)
                       ".cl found in the selected folder")))
      (T
       (prompt (strcat "\n  " (itoa i) ".  " type " '" (pfs:r-name r)
                       "'   sta " (pf:fmt-station (pfs:r-sta0 r))
                       "   datum " (rtos (pfs:r-datum r) 2 2)
                       "   H:" (rtos (pfs:r-hplot r) 2 0)
                       " V:" (rtos (pfs:r-vplot r) 2 0)
                       "   " (vl-filename-base tfile) ".cl   OK"))
       (setq out (cons (cons r tfile) out)))))
  (reverse out))

(defun c:PFXSETUP ( / type p1 p2 ss ents recs good dir n existing anchor
                      cnt-new cnt-upd r tfile)
  (setq *pfs-prev-error* *error*
        *error*          pfs:*error*
        *pfs-undo-open*  nil)

  ;; ---- 1. type assertion (BEFORE the window: it defines the window) -----
  (initget 1 "Storm SAnitary Water")
  (setq type (getkword "\nUtility type for this column [Storm/SAnitary/Water]: "))
  (setq type (strcase type))

  ;; ---- 2. the window ---------------------------------------------------
  (prompt (strcat "\nWindow the " type
                  " profile column (a loose box -- precision is irrelevant)."))
  (setq p1 (getpoint "\nFirst corner: "))
  (if (null p1)
    (prompt "\nCancelled.")
    (progn
      (setq p2 (getcorner p1 "\nOpposite corner: "))
      (if (null p2)
        (prompt "\nCancelled.")
        (progn
          (setq ss   (ssget "_C" p1 p2)
                ents (pfs:ss->list ss))
          (cond
            ((null ents) (prompt "\nNothing in that window."))
            (T
             ;; ---- 3. the .cl folder ------------------------------------
             (setq dir (pflabel:browse
                         (strcat "Select any " type
                                 " Centerline (.CL) in This Project's Folder")
                         '*pflabel-dir-cl* "cl"))
             (if (null dir)
               (prompt "\nNo .cl folder selected -- cancelled.")
               (progn
                 (setq dir (strcat (vl-filename-directory dir) "\\"))
                 ;; ---- 4. scan (PURE) ----------------------------------
                 (prompt (strcat "\nScanning window... "))
                 (setq recs (pfs:scan ents type)
                       n    (length recs))
                 (if (null recs)
                   (prompt (strcat "no " *pfs-hbox-layer*
                                   " grids found in the window."))
                   (progn
                     (prompt (strcat (itoa n) " grid(s) found.\n"))
                     ;; ---- 5. report ------------------------------------
                     (setq good (pfs:report recs type dir))
                     (cond
                       ((null good)
                        (prompt "\n\nNo grid passed validation -- nothing to register."))
                       (T
                        ;; ---- 6. confirm --------------------------------
                        (initget "Yes No")
                        (prompt (strcat "\n\n" (itoa (length good))
                                        " of " (itoa n) " grid(s) ready."))
                        (if (/= (getkword "\nRegister them? [Yes/No] <Yes>: ")
                                "No")
                          (progn
                            ;; ---- 7. write, one undo group -------------
                            (command "_.UNDO" "_Begin")
                            (setq *pfs-undo-open* T
                                  cnt-new 0
                                  cnt-upd 0)
                            (foreach g good
                              (setq r        (car g)
                                    tfile    (cdr g)
                                    existing (pfa:find-anchor (pfs:r-name r)
                                                              type))
                              (if existing
                                (progn
                                  (pfa:reanchor existing (pfs:r-xform r))
                                  (setq cnt-upd (1+ cnt-upd)))
                                (progn
                                  (pfa:write-anchor (pfs:r-name r) type
                                                    (pfs:r-xform r) tfile)
                                  (setq cnt-new (1+ cnt-new)))))
                            (command "_.UNDO" "_End")
                            (setq *pfs-undo-open* nil)
                            (prompt (strcat "\n" (itoa cnt-new)
                                            " anchor(s) written, "
                                            (itoa cnt-upd)
                                            " updated in place (ledgers preserved)."
                                            (if (< (length good) n)
                                              (strcat "  " (itoa (- n (length good)))
                                                      " skipped -- see above.")
                                              "")
                                            "  One U reverses the pass.")))
                          (prompt "\nNothing registered.")))))))))))))
  (setq *error* *pfs-prev-error*)
  (princ))


(princ "\npfsetup.lsp loaded.  Command: PFXSETUP (register a profile column).")
(princ)
;;; ==========================================================================
;;; end of pfsetup.lsp
;;; ==========================================================================
