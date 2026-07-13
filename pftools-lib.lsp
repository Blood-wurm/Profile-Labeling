;;; ==========================================================================
;;; pftools-lib.lsp  --  Shared engine for the structure-labeling toolset
;;; --------------------------------------------------------------------------
;;; Carlson native APIs:
;;;   Road API (EWORKS.ARX) -> real stationing + offset from .cl FILES
;;;   DTM  API (TRI4.ARX)   -> surface elevation at X,Y from a .tin FILE
;;;
;;; Pure functions except the API wrappers and the drawing boundary.
;;; STATUS: not yet run in a live drawing. Test on a scratch copy first.
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  the honest assumptions; change here, nowhere else.
;;; --------------------------------------------------------------------------
;; Updated to match the exact Carlson SCAD_2007_CIVIL console output:
(setq *pf-dtm-fn* 'cf:dtm_api)
(setq *pf-road-fn* 'cf:road_api)

;; Membership: a structure is "on" a line if its perpendicular offset from that
;; centerline is within this tolerance (feet). This is the SINGLE membership
;; tolerance -- structures are snapped onto their centerlines, so offset is ~0.
;; It also groups co-located baselines at a junction (every line a junction
;; structure is snapped to reads as a hit). Loosen only if snapped structures
;; start reading as off-line.
(setq *pf-offset-tol* 0.15)

;; Corridor pre-filter: before asking the Road API to project a point onto a
;; line, require the point to be within this distance (feet) of that line's
;; matched drawing polyline. Skips the API call -- and its "unable to locate
;; point along centerline" console spam -- for lines a structure isn't near.
(setq *pf-corridor* 0.2)

;; Station range slack (feet) -- allows a structure sitting exactly at a line's
;; end to still count as on it.
(setq *pf-range-eps* 0.01)

;; Rank direction. T => rank 1 is the LOWEST station. Numbering is
;; downstream->upstream; set to match whichever end your .cl calls station 0.
(setq *pf-rank-ascending* T)

;; Text + spacing, all derived from the horizontal plot scale so the tool is
;; scale-correct. At 1"=20': height 1.60, offset 1.60, gaps 3.20 / 2.40.
(setq *pf-text-paper-height* 0.08)   ; plotted text height (inches)
(setq *pf-offset-factor* 1.0)    ; station-line -> text offset, x height
(setq *pf-gap-rest-factor* 1.5)    ; gap between adjacent rows, x height

;; Horizontal grid assumed 1:1 in model space (1 unit = 1 station foot).
(setq *pf-hscale-fixed* 1.0)


;;; ==========================================================================
;;; SECTION 1  --  Carlson API Loading + Silent Error-Trapped Wrappers
;;; ==========================================================================
(defun pf:load-apis ( / dir)
  (setq dir (if (boundp 'lspdir$) lspdir$ ""))
  (vl-catch-all-apply 'scload (list (strcat dir "tri4")))
  (vl-catch-all-apply 'scload (list (strcat dir "eworks")))
  (princ))

;; DTM wrappers -----------------------------------------------------------
(defun pf:tin-load (file)   (apply *pf-dtm-fn* (list "load_tin" file)))
(defun pf:tin-unload ()     (apply *pf-dtm-fn* (list "unload_tin")))
(defun pf:tin-z (pt)        (apply *pf-dtm-fn* (list "tin_z" (list (car pt) (cadr pt)))))

;; Road wrappers ----------------------------------------------------------
(defun pf:cl-range (clfile / rng)
  (setq rng (vl-catch-all-apply *pf-road-fn* (list "cl_sta_range" clfile)))
  (if (and (not (vl-catch-all-error-p rng)) rng) rng nil))

;; (pf:cl-locate-safe clfile pt) -> (station offset projected-point) | nil
;; Silences Carlson C++ console spam and provides radial fallback for line termini.
(defun pf:cl-locate-safe (clfile pt / pt2d res rng sta0 stan pt0 ptn d0 dn)
  (setq pt2d (list (car pt) (cadr pt)))

  ;; 1. Attempt standard orthogonal projection inside a silent error trap
  (setq res (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_pt" clfile pt2d)))
  (if (and (not (vl-catch-all-error-p res)) res)
    res

    ;; 2. Radial Terminus Fallback: If orthogonal fails (bend/overshoot), check endpoints
    (if (setq rng (pf:cl-range clfile))
      (progn
        (setq sta0 (car rng) stan (cadr rng))
        (setq pt0  (car (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_sta" clfile sta0)))
              ptn  (car (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_sta" clfile stan))))
        (if (and (listp pt0) (listp ptn))
          (progn
            (setq d0 (distance pt2d (list (car pt0) (cadr pt0)))
                  dn (distance pt2d (list (car ptn) (cadr ptn))))
            (cond
              ((<= d0 *pf-offset-tol*) (list sta0 d0 pt0))
              ((<= dn *pf-offset-tol*) (list stan dn ptn))
              (T nil))))))))

;;; ==========================================================================
;;; SECTION 1.5  --  Corridor geometry  (pure)
;;; ==========================================================================
;;; A line's "corridor" is the neighborhood of its matched drawing polyline.
;;; Points outside it can't be on the line, so we never bother the Road API
;;; with them -- this is what silences the projection-failure console spam.
;;; verts = list of (x y) vertices in polyline order.

;; (pf:pt-seg-dist p a b) -> real   distance from 2D point p to segment a-b
(defun pf:pt-seg-dist (p a b / px py ax ay bx by dx dy u len2)
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

;; (pf:pt-poly-dist p verts) -> real   min distance from p to the polyline
(defun pf:pt-poly-dist (p verts / best d prev)
  (setq best nil prev nil)
  (foreach v verts
    (if prev
      (progn
        (setq d (pf:pt-seg-dist p prev v))
        (if (or (null best) (< d best)) (setq best d))))
    (setq prev v))
  (cond (best best)
        (verts (distance (list (car p) (cadr p))    ; single-vertex polyline
                         (list (caar verts) (cadar verts))))
        (T 1e30)))                                   ; no vertices -> "infinitely far"

;; (pf:in-corridor-p pt verts) -> T | nil   (pt may be 3D; first two ordinates used)
(defun pf:in-corridor-p (pt verts)
  (<= (pf:pt-poly-dist (list (car pt) (cadr pt)) verts) *pf-corridor*))


;;; ==========================================================================
;;; SECTION 2  --  Multi-Line Membership & Stationing
;;; ==========================================================================
;; (pf:lines-at-point pt2d cl-table) -> list of unique (name station)
;;   Tests the point against every loaded centerline (corridor pre-filter
;;   gates the Road-API call). Every line the point is ON -- offset within
;;   *pf-offset-tol* and station within range -- is returned, closest first.
;;   Junction structures therefore report every line they're snapped to.
(defun pf:lines-at-point (pt2d cl-table / hits res sta off nm verts lo hi seen)
  (setq hits '() seen '())
  (foreach e cl-table
    (setq nm (cadr e) verts (nth 4 e))
    (if (and (not (member nm seen))
             (or (null verts) (pf:in-corridor-p pt2d verts))
             (setq res (pf:cl-locate-safe (car e) pt2d)))
      (progn
        (setq sta (car res) off (abs (cadr res))
              lo  (nth 2 e)  hi  (nth 3 e))
        ;; Must be ON the line (small offset) AND within its station range
        (if (and (<= off *pf-offset-tol*)
                 (>= sta (- lo *pf-range-eps*))
                 (<= sta (+ hi *pf-range-eps*)))
          (progn
            (setq seen (cons nm seen))
            (setq hits (cons (list off nm sta) hits)))))))
  ;; Closest line first (deterministic order for downstream consumers).
  (setq hits (vl-sort hits '(lambda (a b) (< (car a) (car b)))))
  (mapcar '(lambda (h) (list (cadr h) (caddr h))) hits))

;; (pf:sort-line-infos-alpha line-infos) -> line-infos sorted by name (A->Z)
;;   Used for the combined ID so a junction structure gets the SAME ID on
;;   every profile it appears in, regardless of which line is primary.
(defun pf:sort-line-infos-alpha (line-infos / names)
  (setq names (acad_strlsort (mapcar 'car line-infos)))
  (mapcar '(lambda (nm) (assoc nm line-infos)) names))

;; (pf:rank-on-line station all-stations ascending eps) -> integer (1-based)
(defun pf:rank-on-line (station all-stations ascending eps / n)
  (setq n 0)
  (foreach s all-stations
    (if ascending
      (if (< s (- station eps)) (setq n (1+ n)))
      (if (> s (+ station eps)) (setq n (1+ n)))))
  (1+ n))

;;; ==========================================================================
;;; SECTION 3  --  Profile transform
;;; ==========================================================================
;;; xform = (left-x start-sta h-scale top-y base-y datum v-scale)
;;;   left-x    world X at the grid's start station (lower-left corner X)
;;;   start-sta station value at that corner
;;;   h-scale   world units per station foot (1.0 under the 1:1 assumption)
;;;   top-y     world Y of the grid top border (where labels sit)
;;;   base-y    world Y of the grid bottom border (the datum line)
;;;   datum     elevation at the grid bottom border
;;;   v-scale   world units per elevation foot (consumed by the invert tool)

(defun pf:xf-leftx  (xf) (nth 0 xf))
(defun pf:xf-sta0   (xf) (nth 1 xf))
(defun pf:xf-hscale (xf) (nth 2 xf))
(defun pf:xf-topy   (xf) (nth 3 xf))
(defun pf:xf-basey  (xf) (nth 4 xf))
(defun pf:xf-datum  (xf) (nth 5 xf))
(defun pf:xf-vscale (xf) (nth 6 xf))

;; (pf:station->profile-x station xform) -> real
(defun pf:station->profile-x (station xform)
  (+ (pf:xf-leftx xform)
     (* (- station (pf:xf-sta0 xform)) (pf:xf-hscale xform))))

;; (pf:elev->profile-y elev xform) -> real
;;   NAMED SEAM for INVLABEL: world Y of an elevation on this grid.
;;   Unused by PFLABEL.
(defun pf:elev->profile-y (elev xform)
  (+ (pf:xf-basey xform)
     (* (- elev (pf:xf-datum xform)) (pf:xf-vscale xform))))

;; (pf:grid-top-y xform) -> real
(defun pf:grid-top-y (xform) (pf:xf-topy xform))


;;; ==========================================================================
;;; SECTION 4  --  String helpers  (pure)
;;; ==========================================================================

(defun pf:join (lst sep / out first)
  (setq out "" first T)
  (foreach s lst
    (setq out (if first (setq first nil out s) (strcat out sep s))))
  out)

(defun pf:split (str sep / i n c out cur)
  (setq i 1 n (strlen str) cur "" out '())
  (while (<= i n)
    (setq c (substr str i 1))
    (if (= c sep) (setq out (cons cur out) cur "") (setq cur (strcat cur c)))
    (setq i (1+ i)))
  (reverse (cons cur out)))

(defun pf:digit-p (ch) (and (>= (ascii ch) 48) (<= (ascii ch) 57)))


;;; ==========================================================================
;;; SECTION 5  --  Block name -> type / size lookup  (pure)
;;; ==========================================================================
;;; type-table entries: (PREFIX TYPE-STRING SIZE-BEARING?)

(setq *pf-type-table*
  '(("CBI"  "CURB BOX INLET" nil)
    ("DBI"  "DROP BOX INLET" nil)
    ("SMH"  "MANHOLE"        nil)
    ("MH"   "MANHOLE"        nil)
    ("HDWL" "HDWL"           T)))

;; (pf:name-prefix name) -> leading token before first "-", "_", or digit
(defun pf:name-prefix (name / i c out)
  (setq i 1 out "")
  (while (and (<= i (strlen name))
              (setq c (substr name i 1))
              (/= c "_")
              (/= c "-")
              (not (pf:digit-p c)))
    (setq out (strcat out c) i (1+ i)))
  out)

(defun pf:type-entry (name type-table)
  (assoc (strcase (pf:name-prefix name)) type-table))

(defun pf:blockname->type (name type-table / e)
  (if (setq e (pf:type-entry name type-table)) (cadr e)))

(defun pf:blockname->size (name type-table / e)
  (setq e (pf:type-entry name type-table))
  (if (and e (caddr e)) (pf:parse-size name)))

;; (pf:parse-size name) -> "18\"" | "24\"x24\"" | nil   (inches assumed)
(defun pf:parse-size (name / i n c out indim)
  (setq i 1 n (strlen name) out "" indim nil)
  (while (<= i n)
    (setq c (substr name i 1))
    (cond
      ((pf:digit-p c) (setq out (strcat out c) indim T))
      ((and indim (= (strcase c) "X")) (setq out (strcat out "x")))
      (indim (setq i n)))
    (setq i (1+ i)))
  (if (= out "") nil (pf:size-fmt out)))

(defun pf:size-fmt (s)
  (pf:join (mapcar '(lambda (p) (strcat p "\"")) (pf:split s "x")) "x"))


;;; ==========================================================================
;;; SECTION 6  --  Value formatting  (pure)
;;; ==========================================================================

;; (pf:fmt-station sta) -> "X+XX.XX"
(defun pf:fmt-station (sta / hund rem)
  (setq hund (fix (/ sta 100.0)) rem (- sta (* hund 100.0)))
  (strcat (itoa hund) "+" (if (< rem 10.0) "0" "") (rtos rem 2 2)))

(defun pf:fmt-elev (elev prec) (rtos elev 2 prec))


;;; ==========================================================================
;;; SECTION 7  --  Label composition  (pure)
;;; ==========================================================================

;; (pf:combine-id line-names ranks) -> "AA-1/BB-2/DA-1"
;;   Callers pass names + ranks ALPHABETICALLY sorted (pf:sort-line-infos-alpha)
;;   so IDs are stable across profiles.
(defun pf:combine-id (line-names ranks)
  (pf:join
    (mapcar '(lambda (nm rk) (strcat nm "-" (itoa rk))) line-names ranks) "/"))

;; (pf:subst-token str token repl) -> str with every `token` replaced by `repl`
(defun pf:subst-token (str token repl / pos out tlen)
  (setq out "" tlen (strlen token))
  (while (setq pos (vl-string-search token str))
    (setq out (strcat out (substr str 1 pos) repl)
          str (substr str (+ pos tlen 1))))
  (strcat out str))

;; (pf:join-parts parts) -> single-spaced string, empty/nil parts dropped
(defun pf:join-parts (parts)
  (pf:join (vl-remove-if '(lambda (p) (or (null p) (= p ""))) parts) " "))

;; (pf:strip-trailing-eq str) -> str without a trailing " ="
(defun pf:strip-trailing-eq (str / n)
  (setq n (strlen str))
  (if (and (> n 2) (= (substr str (- n 1)) " ="))
    (substr str 1 (- n 2))
    str))

;; (pf:build-label-rows line-infos type size id gl-str fmt) -> list of strings
;;   line-infos arrive PRIMARY FIRST, remaining lines alphabetical.
;;   gl-str is already a string ("579.95" or "----"), so G.L. never blocks.
;;   fmt = alist of user prefix/suffix strings from the settings dialog:
;;     "sta_pre" "sta_suf" "con_pre" "con_suf" "gl_pre" "gl_suf"
;;   The [line] token in sta_suf is replaced PER ROW with that row's line name,
;;   so one settings file serves storm / sewer / water.  Values stay
;;   engine-generated: station, size+type+ID, elevation.
(defun pf:fmt-get (key fmt) (cdr (assoc key fmt)))

(defun pf:build-label-rows (line-infos type size id gl-str fmt
                            / nlines idx sta-rows const-row gl-row)
  (setq nlines   (length line-infos)
        idx      0
        sta-rows '())
  (foreach li line-infos
    (setq idx (1+ idx))
    (setq sta-rows
      (cons
        (strcat
          (pf:join-parts
            (list (pf:fmt-get "sta_pre" fmt)
                  (pf:fmt-station (cadr li))
                  (pf:subst-token (pf:fmt-get "sta_suf" fmt) "[line]" (car li))))
          (if (< idx nlines) " =" ""))
        sta-rows)))
  (setq sta-rows (reverse sta-rows))
  (setq const-row
        (pf:join-parts
          (list (pf:fmt-get "con_pre" fmt) size type id
                (pf:fmt-get "con_suf" fmt))))
  (setq gl-row
        (pf:join-parts
          (list (pf:fmt-get "gl_pre" fmt) gl-str
                (pf:fmt-get "gl_suf" fmt))))
  (append sta-rows (list const-row gl-row)))


;;; ==========================================================================
;;; SECTION 8  --  Drawing boundary  (SIDE-EFFECTING)
;;; ==========================================================================

;; (pf:text-length str style ht) -> baseline length when drawn
(defun pf:text-length (str style ht / box)
  (setq box (textbox (list (cons 1 str) (cons 40 ht) (cons 7 style) (cons 41 1.0))))
  (if box (- (car (cadr box)) (car (car box))) (* (strlen str) ht)))

;; (pf:draw-text pt str layer style ht rot) -> ename  (MIDDLE-LEFT, rot rad)
(defun pf:draw-text (pt str layer style ht rot)
  (entmakex
    (list '(0 . "TEXT") (cons 8 layer) (cons 7 style)
          (cons 10 pt) (cons 11 pt) (cons 40 ht)
          (cons 1 str) (cons 50 rot) (cons 72 0) (cons 73 2))))

;; (pf:draw-label-stack line-x base-y rows layer style ht offset gapn) -> top-y
;;   Columns straddle the station line at line-x:
;;     row 1        -> line-x - offset          (left of the line)
;;     rows 2..n    -> line-x + offset, then + gapn each   (right of the line)
;;   So row1->row2 spans 2*offset across the line; rows after step by gapn.
;;   All share base-y and read upward.
;;   Returns the station-line top Y: base-y + the length of the FIRST row's
;;   text with any trailing " =" stripped (the line matches the first station
;;   text, not the tallest column).
(defun pf:draw-label-stack (line-x base-y rows layer style ht offset gapn
                            / x i rot line-top)
  (setq i 0 rot (/ pi 2.0) line-top base-y)
  (foreach str rows
    (setq x (if (= i 0)
              (- line-x offset)                     ; row 1: left of the line
              (+ line-x offset (* (1- i) gapn))))   ; rows 2+: right, stepping by gapn
    (pf:draw-text (list x base-y 0.0) str layer style ht rot)
    (if (= i 0)
      (setq line-top
            (+ base-y
               (pf:text-length (pf:strip-trailing-eq str) style ht))))
    (setq i (1+ i)))
  line-top)

;; (pf:draw-station-line x grid-top-y top-y layer) -> ename
(defun pf:draw-station-line (x grid-top-y top-y layer)
  (entmakex
    (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
          '(100 . "AcDbPolyline") '(90 . 2) '(70 . 0)
          (cons 10 (list x grid-top-y)) (cons 10 (list x top-y)))))

;;; --------------------------------------------------------------------------
;;; Corridor matching (setup-time)  --  bind each .cl file to its drawing
;;; polyline so pf:in-corridor-p can pre-filter without the Road API.
;;; --------------------------------------------------------------------------

;; (pf:pt2d-near a b tol) -> T | nil   (compares first two ordinates only)
(defun pf:pt2d-near (a b tol)
  (<= (distance (list (car a) (cadr a)) (list (car b) (cadr b))) tol))

;; (pf:poly-verts ename) -> list of vertex points (LWPOLYLINE / LINE / POLYLINE)
(defun pf:poly-verts (ename / ed etype out sub sd)
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

;; (pf:cl-endpoints clfile) -> (p-start p-end) | nil   (from the .cl station range)
(defun pf:cl-endpoints (clfile / rng r0 rn p0 pn)
  (if (setq rng (pf:cl-range clfile))
    (progn
      (setq r0 (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_sta" clfile (car rng)))
            rn (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_sta" clfile (cadr rng))))
      (setq p0 (if (and (not (vl-catch-all-error-p r0)) (listp r0)) (car r0))
            pn (if (and (not (vl-catch-all-error-p rn)) (listp rn)) (car rn)))
      (if (and (listp p0) (listp pn)) (list p0 pn)))))

;; (pf:find-cl-polyline p0 pn tol) -> verts | nil
;;   First drawing polyline whose two ends coincide with p0/pn (either order).
(defun pf:find-cl-polyline (p0 pn tol / ss i e vs verts a b)
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,LINE,POLYLINE"))) i 0)
  (if ss
    (while (and (< i (sslength ss)) (null verts))
      (setq e  (ssname ss i)
            vs (pf:poly-verts e))
      (if (and vs (> (length vs) 1))
        (progn
          (setq a (car vs) b (last vs))
          (if (or (and (pf:pt2d-near a p0 tol) (pf:pt2d-near b pn tol))
                  (and (pf:pt2d-near a pn tol) (pf:pt2d-near b p0 tol)))
            (setq verts vs))))
      (setq i (1+ i))))
  verts)

;; (pf:attach-corridor entry) -> (clfile name start end verts)
;;   verts is nil when no drawing polyline matches -> membership falls back to
;;   the plain Road-API test in pf:lines-at-point.
(defun pf:attach-corridor (entry / ends verts)
  (if (setq ends (pf:cl-endpoints (car entry)))
    (setq verts (pf:find-cl-polyline (car ends) (cadr ends) *pf-corridor*)))
  (append entry (list verts)))


(princ "\npftools-lib.lsp loaded (Carlson API build).")
(princ)
;;; ==========================================================================
;;; end of pftools-lib.lsp
;;; ==========================================================================
