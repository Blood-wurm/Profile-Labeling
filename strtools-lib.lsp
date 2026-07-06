;;; ==========================================================================
;;; strtools-lib.lsp  --  Shared engine for the structure-labeling toolset
;;; --------------------------------------------------------------------------
;;; PIVOTED to Carlson native APIs:
;;;   Road API (EWORKS.ARX) -> real stationing + offset from .cl FILES
;;;   DTM  API (TRI4.ARX)   -> surface elevation at X,Y from a .tin FILE
;;; This removes the hand-rolled vlax-curve stationing and the CL-origin bug
;;; (Carlson returns true station, not raw polyline distance).
;;;
;;; Pure functions except the API wrappers and the drawing boundary.
;;; STATUS: not yet run in a live drawing. Test on a scratch copy first.
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  the honest assumptions; change here, nowhere else.
;;; --------------------------------------------------------------------------
;; Updated to match the exact Carlson SCAD_2007_CIVIL console output:
(setq *st-dtm-fn* 'cf:dtm_api)
(setq *st-road-fn* 'cf:road_api)

;; Membership: a structure is "on" a line if its perpendicular offset from that
;; centerline is within this tolerance (feet). This is the SINGLE small
;; membership tolerance -- structures are snapped onto their centerlines, so
;; offset is ~0. It also groups co-located baselines at a junction (two lines
;; whose offsets differ by less than this read as the same tie-in). Loosen only
;; if snapped structures start reading as off-line.
(setq *st-offset-tol* 0.15)

(setq *st-junction-dist* 1.50)  ; Maximum distance to consider multiple centerlines sharing a junction

;; Corridor pre-filter: before asking the Road API to project a point onto a
;; line, require the point to be within this distance (feet) of that line's
;; matched drawing polyline. Skips the API call -- and its "unable to locate
;; point along centerline" console spam -- for lines a structure isn't near.
(setq *st-corridor* 0.2)

;; Station range slack (feet) -- allows a structure sitting exactly at a line's
;; end to still count as on it.
(setq *st-range-eps* 0.01)

;; Rank direction. T => rank 1 is the LOWEST station. Numbering is
;; downstream->upstream; set to match whichever end your .cl calls station 0.
(setq *st-rank-ascending* T)

;; Text + spacing, all derived from the horizontal plot scale so the tool is
;; scale-correct. At 1"=20': height 1.60, offset 1.60, gaps 3.20 / 2.40.
(setq *st-text-paper-height* 0.08)   ; plotted text height (inches)
(setq *st-offset-factor* 1.0)    ; station-line -> text offset, x height
(setq *st-gap-rest-factor* 1.5)    ; gap between adjacent rows, x height

;; Horizontal grid assumed 1:1 in model space (1 unit = 1 station foot).
(setq *st-hscale-fixed* 1.0)


;;; ==========================================================================
;;; SECTION 1  --  Carlson API Loading + Silent Error-Trapped Wrappers
;;; ==========================================================================
(defun st:load-apis ( / dir)
  (setq dir (if (boundp 'lspdir$) lspdir$ ""))
  (vl-catch-all-apply 'scload (list (strcat dir "tri4")))
  (vl-catch-all-apply 'scload (list (strcat dir "eworks")))
  (princ))

;; DTM wrappers -----------------------------------------------------------
(defun st:tin-load (file)   (apply *st-dtm-fn* (list "load_tin" file)))
(defun st:tin-unload ()     (apply *st-dtm-fn* (list "unload_tin")))
(defun st:tin-z (pt)        (apply *st-dtm-fn* (list "tin_z" (list (car pt) (cadr pt)))))

;; Road wrappers ----------------------------------------------------------
(defun st:cl-range (clfile / rng)
  (setq rng (vl-catch-all-apply *st-road-fn* (list "cl_sta_range" clfile)))
  (if (and (not (vl-catch-all-error-p rng)) rng) rng nil))

;; (st:cl-locate-safe clfile pt) -> (station offset projected-point) | nil
;; Silences Carlson C++ console spam and provides radial fallback for line termini.
(defun st:cl-locate-safe (clfile pt / pt2d res rng sta0 stan pt0 ptn d0 dn)
  (setq pt2d (list (car pt) (cadr pt)))
  
  ;; 1. Attempt standard orthogonal projection inside a silent error trap
  (setq res (vl-catch-all-apply *st-road-fn* (list "cl_location_at_pt" clfile pt2d)))
  (if (and (not (vl-catch-all-error-p res)) res)
    res
    
    ;; 2. Radial Terminus Fallback: If orthogonal fails (bend/overshoot), check endpoints
    (if (setq rng (st:cl-range clfile))
      (progn
        (setq sta0 (car rng) stan (cadr rng))
        (setq pt0  (car (vl-catch-all-apply *st-road-fn* (list "cl_location_at_sta" clfile sta0)))
              ptn  (car (vl-catch-all-apply *st-road-fn* (list "cl_location_at_sta" clfile stan))))
        (if (and (listp pt0) (listp ptn))
          (progn
            (setq d0 (distance pt2d (list (car pt0) (cadr pt0)))
                  dn (distance pt2d (list (car ptn) (cadr ptn))))
            (cond
              ((<= d0 *st-offset-tol*) (list sta0 d0 pt0))
              ((<= dn *st-offset-tol*) (list stan dn ptn))
              (T nil))))))))

;;; ==========================================================================
;;; SECTION 1.5  --  Corridor geometry  (pure)
;;; ==========================================================================
;;; A line's "corridor" is the neighborhood of its matched drawing polyline.
;;; Points outside it can't be on the line, so we never bother the Road API
;;; with them -- this is what silences the projection-failure console spam.
;;; verts = list of (x y) vertices in polyline order.

;; (st:pt-seg-dist p a b) -> real   distance from 2D point p to segment a-b
(defun st:pt-seg-dist (p a b / px py ax ay bx by dx dy u len2)
  (setq px (car p)  py (cadr p)
        ax (car a)  ay (cadr a)
        bx (car b)  by (cadr b)
        dx (- bx ax) dy (- by ay)
        len2 (+ (* dx dx) (* dy dy)))
  (if (<= len2 1e-12)
    (distance (list px py) (list ax ay))            ; degenerate segment -> point
    (progn
      (setq u (/ (+ (* (- px ax) dx) (* (- py ay) dy)) len2))
      (setq u (max 0.0 (min 1.0 u)))                ; clamp onto the segment
      (distance (list px py) (list (+ ax (* u dx)) (+ ay (* u dy)))))))

;; (st:pt-poly-dist p verts) -> real   min distance from p to the polyline
(defun st:pt-poly-dist (p verts / best d prev)
  (setq best nil prev nil)
  (foreach v verts
    (if prev
      (progn
        (setq d (st:pt-seg-dist p prev v))
        (if (or (null best) (< d best)) (setq best d))))
    (setq prev v))
  (cond (best best)
        (verts (distance (list (car p) (cadr p))    ; single-vertex polyline
                         (list (caar verts) (cadar verts))))
        (T 1e30)))                                   ; no vertices -> "infinitely far"

;; (st:in-corridor-p pt verts) -> T | nil   (pt may be 3D; first two ordinates used)
(defun st:in-corridor-p (pt verts)
  (<= (st:pt-poly-dist (list (car pt) (cadr pt)) verts) *st-corridor*))


;;; ==========================================================================
;;; SECTION 2  --  Dynamic Multi-Line Binding & Stationing
;;; ==========================================================================
;; (st:lines-at-point pt2d cl-table) -> list of unique (name station)
;; Evaluates all loaded centerlines simultaneously, binds the closest line,
;; and dynamically appends any additional lines sharing the junction.
(defun st:lines-at-point (pt2d cl-table / hits res sta off nm verts min-off out seen)
  (setq hits '() seen '() out '())

  ;; 1. Scan all loaded centerlines without generating console errors.
  ;;    The corridor pre-filter (or null verts -> test as before) gates the API
  ;;    call so off-corridor lines never trigger projection-failure spam.
  (foreach e cl-table
    (setq nm (cadr e) verts (nth 4 e))
    (if (and (not (member nm seen))
             (or (null verts) (st:in-corridor-p pt2d verts))
             (setq res (st:cl-locate-safe (car e) pt2d)))
      (progn
        (setq sta (car res) off (abs (cadr res))
              lo  (nth 2 e) hi (nth 3 e))
        ;; Must be ON the line (small offset) AND within its station range
        (if (and (<= off *st-offset-tol*)
                 (>= sta (- lo *st-range-eps*))
                 (<= sta (+ hi *st-range-eps*)))
          (progn
            (setq seen (cons nm seen))
            (setq hits (cons (list off nm sta) hits)))))))
  
  ;; 2. Sort all valid hits from lowest offset distance to highest
  (setq hits (vl-sort hits '(lambda (a b) (< (car a) (car b)))))
  
  ;; 3. Dynamic Binding: Keep the winning line + any lines within the junction threshold
  (if hits
    (progn
      (setq min-off (car (car hits)))
      (foreach h hits
        (if (or (= h (car hits))                              ; Always keep absolute closest line
                (<= (car h) *st-junction-dist*)               ; Keep shared tie-in lines (up to 4+)
                (<= (abs (- (car h) min-off)) *st-offset-tol*)) ; Keep co-located baselines
          (setq out (cons (list (cadr h) (caddr h)) out))))))
  
  (reverse out))

;; (st:rank-on-line station all-stations ascending eps) -> integer (1-based)
(defun st:rank-on-line (station all-stations ascending eps / n)
  (setq n 0)
  (foreach s all-stations
    (if ascending
      (if (< s (- station eps)) (setq n (1+ n)))
      (if (> s (+ station eps)) (setq n (1+ n)))))
  (1+ n))

;;; ==========================================================================
;;; SECTION 3  --  Profile transform  (horizontal only; vertical deferred)
;;; ==========================================================================
;;; xform = (left-x start-sta h-scale top-y v-scale)
;;;   left-x    world X at the grid's start station (lower-left corner X)
;;;   start-sta station value at that corner
;;;   h-scale   world units per station foot (1.0 under the 1:1 assumption)
;;;   top-y     world Y of the grid top border (where labels sit)
;;;   v-scale   stored for the future invert tool; unused by STRLABEL

(defun st:xf-leftx  (xf) (nth 0 xf))
(defun st:xf-sta0   (xf) (nth 1 xf))
(defun st:xf-hscale (xf) (nth 2 xf))
(defun st:xf-topy   (xf) (nth 3 xf))

;; (st:station->profile-x station xform) -> real
(defun st:station->profile-x (station xform)
  (+ (st:xf-leftx xform)
     (* (- station (st:xf-sta0 xform)) (st:xf-hscale xform))))

;; (st:grid-top-y xform) -> real
(defun st:grid-top-y (xform) (st:xf-topy xform))


;;; ==========================================================================
;;; SECTION 4  --  String helpers  (pure)
;;; ==========================================================================

(defun st:join (lst sep / out first)
  (setq out "" first T)
  (foreach s lst
    (setq out (if first (setq first nil out s) (strcat out sep s))))
  out)

(defun st:split (str sep / i n c out cur)
  (setq i 1 n (strlen str) cur "" out '())
  (while (<= i n)
    (setq c (substr str i 1))
    (if (= c sep) (setq out (cons cur out) cur "") (setq cur (strcat cur c)))
    (setq i (1+ i)))
  (reverse (cons cur out)))

(defun st:digit-p (ch) (and (>= (ascii ch) 48) (<= (ascii ch) 57)))


;;; ==========================================================================
;;; SECTION 5  --  Block name -> type / size lookup  (pure)
;;; ==========================================================================
;;; type-table entries: (PREFIX TYPE-STRING SIZE-BEARING?)

(setq *st-type-table*
  '(("CBI"  "CURB BOX INLET" nil)
    ("DBI"  "DROP BOX INLET" T)
    ("MH"   "MANHOLE"        nil)
    ("HDWL" "HDWL"           T)))

;; (st:name-prefix name) -> leading token before first "-", "_", or digit
(defun st:name-prefix (name / i c out)
  (setq i 1 out "")
  (while (and (<= i (strlen name))
              (setq c (substr name i 1))
              (/= c "_")
			  (/= c "-")
              (not (st:digit-p c)))
    (setq out (strcat out c) i (1+ i)))
  out)

(defun st:type-entry (name type-table)
  (assoc (strcase (st:name-prefix name)) type-table))

(defun st:blockname->type (name type-table / e)
  (if (setq e (st:type-entry name type-table)) (cadr e)))

(defun st:blockname->size (name type-table / e)
  (setq e (st:type-entry name type-table))
  (if (and e (caddr e)) (st:parse-size name)))

;; (st:parse-size name) -> "18\"" | "24\"x24\"" | nil   (inches assumed)
(defun st:parse-size (name / i n c out indim)
  (setq i 1 n (strlen name) out "" indim nil)
  (while (<= i n)
    (setq c (substr name i 1))
    (cond
      ((st:digit-p c) (setq out (strcat out c) indim T))
      ((and indim (= (strcase c) "X")) (setq out (strcat out "x")))
      (indim (setq i n)))
    (setq i (1+ i)))
  (if (= out "") nil (st:size-fmt out)))

(defun st:size-fmt (s)
  (st:join (mapcar '(lambda (p) (strcat p "\"")) (st:split s "x")) "x"))


;;; ==========================================================================
;;; SECTION 6  --  Value formatting  (pure)
;;; ==========================================================================

;; (st:fmt-station sta) -> "X+XX.XX"
(defun st:fmt-station (sta / hund rem)
  (setq hund (fix (/ sta 100.0)) rem (- sta (* hund 100.0)))
  (strcat (itoa hund) "+" (if (< rem 10.0) "0" "") (rtos rem 2 2)))

(defun st:fmt-elev (elev prec) (rtos elev 2 prec))


;;; ==========================================================================
;;; SECTION 7  --  Label composition  (pure)
;;; ==========================================================================

(defun st:combine-id (line-names ranks)
  (st:join
    (mapcar '(lambda (nm rk) (strcat nm "-" (itoa rk))) line-names ranks) "/"))

;; (st:build-label-rows line-infos type size id prefix gl-str) -> list of strings
;;   gl-str is already a string ("579.95" or "----"), so G.L. never blocks.
(defun st:build-label-rows (line-infos type size id prefix gl-str
                            / nlines idx sta-rows const-row gl-row)
  (setq nlines (length line-infos) idx 0 sta-rows '())
  (foreach li line-infos
    (setq idx (1+ idx))
    (setq sta-rows
      (cons
        (strcat "STA. " (st:fmt-station (cadr li))
                " STORM LINE '" (car li) "'"
                (if (< idx nlines) " =" ""))
        sta-rows)))
  (setq sta-rows (reverse sta-rows))
  (setq const-row (strcat prefix " " (if size (strcat size " ") "") type " " id))
  (setq gl-row (strcat "G.L. " gl-str))
  (append sta-rows (list const-row gl-row)))


;;; ==========================================================================
;;; SECTION 8  --  Drawing boundary  (SIDE-EFFECTING)
;;; ==========================================================================

;; (st:text-length str style ht) -> baseline length when drawn
(defun st:text-length (str style ht / box)
  (setq box (textbox (list (cons 1 str) (cons 40 ht) (cons 7 style) (cons 41 1.0))))
  (if box (- (car (cadr box)) (car (car box))) (* (strlen str) ht)))

;; (st:draw-text pt str layer style ht rot) -> ename  (MIDDLE-LEFT, rot rad)
(defun st:draw-text (pt str layer style ht rot)
  (entmakex
    (list '(0 . "TEXT") (cons 8 layer) (cons 7 style)
          (cons 10 pt) (cons 11 pt) (cons 40 ht)
          (cons 1 str) (cons 50 rot) (cons 72 0) (cons 73 2))))

;; (st:draw-label-stack line-x base-y rows layer style ht offset gapn) -> top-y
;;   Columns straddle the station line at line-x:
;;     row 1        -> line-x - offset          (left of the line)
;;     rows 2..n    -> line-x + offset, then + gapn each   (right of the line)
;;   So row1->row2 spans 2*offset across the line; rows after step by gapn.
;;   All share base-y and read upward. Returns Y of the tallest column top.
(defun st:draw-label-stack (line-x base-y rows layer style ht offset gapn / x i maxlen tl rot)
  (setq i 0 maxlen 0.0 rot (/ pi 2.0))
  (foreach str rows
    (setq x (if (= i 0)
              (- line-x offset)                       ; row 1: left of the line
              (+ line-x offset (* (1- i) gapn))))  ; rows 2+: right of the line, stepping right by gapn
    (st:draw-text (list x base-y 0.0) str layer style ht rot)
    (setq tl (st:text-length str style ht))
    (if (> tl maxlen) (setq maxlen tl))
    (setq i (1+ i)))
  (+ base-y maxlen))

;; (st:draw-station-line x grid-top-y top-y layer) -> ename
(defun st:draw-station-line (x grid-top-y top-y layer)
  (entmakex
    (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
          '(100 . "AcDbPolyline") '(90 . 2) '(70 . 0)
          (cons 10 (list x grid-top-y)) (cons 10 (list x top-y)))))

;;; --------------------------------------------------------------------------
;;; Corridor matching (setup-time)  --  bind each .cl file to its drawing
;;; polyline so st:in-corridor-p can pre-filter without the Road API.
;;; --------------------------------------------------------------------------

;; (st:pt2d-near a b tol) -> T | nil   (compares first two ordinates only)
(defun st:pt2d-near (a b tol)
  (<= (distance (list (car a) (cadr a)) (list (car b) (cadr b))) tol))

;; (st:poly-verts ename) -> list of vertex points (LWPOLYLINE / LINE / POLYLINE)
(defun st:poly-verts (ename / ed etype out sub sd)
  (setq ed (entget ename) etype (cdr (assoc 0 ed)) out '())
  (cond
    ((= etype "LWPOLYLINE")
     (foreach pair ed (if (= (car pair) 10) (setq out (cons (cdr pair) out))))
     (reverse out))
    ((= etype "LINE")
     (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))
    ((= etype "POLYLINE")                              ; heavy polyline: walk VERTEX chain
     (setq sub (entnext ename))
     (while (and sub (setq sd (entget sub)) (= (cdr (assoc 0 sd)) "VERTEX"))
       (setq out (cons (cdr (assoc 10 sd)) out) sub (entnext sub)))
     (reverse out))
    (T nil)))

;; (st:cl-endpoints clfile) -> (p-start p-end) | nil   (from the .cl station range)
(defun st:cl-endpoints (clfile / rng r0 rn p0 pn)
  (if (setq rng (st:cl-range clfile))
    (progn
      (setq r0 (vl-catch-all-apply *st-road-fn* (list "cl_location_at_sta" clfile (car rng)))
            rn (vl-catch-all-apply *st-road-fn* (list "cl_location_at_sta" clfile (cadr rng))))
      (setq p0 (if (and (not (vl-catch-all-error-p r0)) (listp r0)) (car r0))
            pn (if (and (not (vl-catch-all-error-p rn)) (listp rn)) (car rn)))
      (if (and (listp p0) (listp pn)) (list p0 pn)))))

;; (st:find-cl-polyline p0 pn tol) -> verts | nil
;;   First drawing polyline whose two ends coincide with p0/pn (either order).
(defun st:find-cl-polyline (p0 pn tol / ss i e vs verts a b)
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,LINE,POLYLINE"))) i 0)
  (if ss
    (while (and (< i (sslength ss)) (null verts))
      (setq e  (ssname ss i)
            vs (st:poly-verts e))
      (if (and vs (> (length vs) 1))
        (progn
          (setq a (car vs) b (last vs))
          (if (or (and (st:pt2d-near a p0 tol) (st:pt2d-near b pn tol))
                  (and (st:pt2d-near a pn tol) (st:pt2d-near b p0 tol)))
            (setq verts vs))))
      (setq i (1+ i))))
  verts)

;; (st:attach-corridor entry) -> (clfile name start end verts)
;;   verts is nil when no drawing polyline matches -> membership falls back to
;;   the plain Road-API test in st:lines-at-point.
(defun st:attach-corridor (entry / ends verts)
  (if (setq ends (st:cl-endpoints (car entry)))
    (setq verts (st:find-cl-polyline (car ends) (cadr ends) *st-corridor*)))
  (append entry (list verts)))


(princ "\nstrtools-lib.lsp loaded (Carlson API build).")
(princ)
;;; ==========================================================================
;;; end of strtools-lib.lsp
;;; ==========================================================================