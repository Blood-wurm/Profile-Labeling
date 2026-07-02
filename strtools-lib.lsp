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
;; New tolerance settings for coordinate matching:
(setq *st-micro-snap-tol* 0.15)  ; Direct coordinate coincidence tolerance for skewed outfalls/termini
(setq *st-junction-dist* 1.50)  ; Maximum distance to consider multiple centerlines sharing a junction

;; Membership: a structure is "on" a line if its perpendicular offset from that
;; centerline is within this tolerance (feet). Structures are snapped, so this
;; is small; loosen only if snapped structures read as off-line.
(setq *st-offset-tol* 30.0)

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
(setq *st-gap-first-factor* 2.0)    ; gap between row 1 and row 2, x height
(setq *st-gap-rest-factor* 1.5)    ; every gap after, x height

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
;;; SECTION 2  --  Dynamic Multi-Line Binding & Stationing
;;; ==========================================================================
;; (st:on-line-p entry pt2d) -> station | nil
(defun st:on-line-p (entry pt2d / res sta off lo hi)
  (setq res (st:cl-locate-safe (car entry) pt2d))
  (if res
    (progn
      (setq sta (car res) off (abs (cadr res))
            lo  (nth 2 entry) hi (nth 3 entry))
      (if (and (<= off *st-offset-tol*)
               (>= sta (- lo *st-range-eps*))
               (<= sta (+ hi *st-range-eps*)))
        sta))))

;; (st:lines-at-point pt2d cl-table) -> list of unique (name station)
;; Evaluates all loaded centerlines simultaneously, binds the closest line,
;; and dynamically appends any additional lines sharing the junction.
(defun st:lines-at-point (pt2d cl-table / hits res sta off nm min-off out seen)
  (setq hits '() seen '() out '())
  
  ;; 1. Scan all loaded centerlines without generating console errors
  (foreach e cl-table
    (setq nm (cadr e))
    (if (and (not (member nm seen))
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
                (<= (abs (- (car h) min-off)) *st-micro-snap-tol*)) ; Keep co-located baselines
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

;; (st:name-prefix name) -> leading token before first "_" or digit
(defun st:name-prefix (name / i c out)
  (setq i 1 out "")
  (while (and (<= i (strlen name))
              (setq c (substr name i 1))
              (/= c "_")
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
              (+ line-x offset (* (1- i) gapn))))  ; rows 2+: right; +ht clears glyphs off the line
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


(princ "\nstrtools-lib.lsp loaded (Carlson API build).")
(princ)
;;; ==========================================================================
;;; end of strtools-lib.lsp
;;; ==========================================================================