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
;;; SECTION 1  --  Carlson API loading + wrappers
;;; ==========================================================================
;; (st:load-apis) -> loads TRI4 (DTM) and EWORKS (Road). Never unload them.
(defun st:load-apis ( / dir)
  (setq dir (if (boundp 'lspdir$) lspdir$ ""))
  (vl-catch-all-apply 'scload (list (strcat dir "tri4")))
  (vl-catch-all-apply 'scload (list (strcat dir "eworks")))
  (princ))

;; DTM wrappers -----------------------------------------------------------
(defun st:tin-load (file)
  (apply *st-dtm-fn* (list "load_tin" file)))

(defun st:tin-unload ()
  (apply *st-dtm-fn* (list "unload_tin")))

;; (st:tin-z pt2d) -> elevation | nil  (nil if point is off the surface)
(defun st:tin-z (pt2d)
  (apply *st-dtm-fn* (list "tin_z" pt2d)))

;; Road wrappers ----------------------------------------------------------
;; (st:cl-locate clfile pt2d) -> (station offset projected-point) | nil
(defun st:cl-locate (clfile pt2d)
  (apply *st-road-fn* (list "cl_location_at_pt" clfile pt2d)))

;; (st:cl-range clfile) -> (start-station end-station) | nil
(defun st:cl-range (clfile)
  (apply *st-road-fn* (list "cl_sta_range" clfile)))


;;; ==========================================================================
;;; SECTION 2  --  Membership + stationing  (via Road API)
;;; ==========================================================================
;;; cl-table entries: (clfile name start end)   -- start/end cached at setup.

;; (st:on-line-p entry pt2d) -> station | nil
;;   On the line if offset within tolerance AND station within the line's range.
(defun st:on-line-p (entry pt2d / res sta off lo hi)
  (setq res (st:cl-locate (car entry) pt2d))
  (if res
    (progn
      (setq sta (car res) off (cadr res)
            lo  (nth 2 entry) hi (nth 3 entry))
      (if (and (<= (abs off) *st-offset-tol*)
               (>= sta (- lo *st-range-eps*))
               (<= sta (+ hi *st-range-eps*)))
        sta))))

;; (st:lines-at-point pt2d cl-table) -> list of (name station)
;;   Every centerline the point sits on. 1 = single-line, 2+ = junction.
(defun st:lines-at-point (pt2d cl-table / out sta)
  (setq out '())
  (foreach e cl-table
    (if (setq sta (st:on-line-p e pt2d))
      (setq out (cons (list (cadr e) sta) out))))
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

;; (st:draw-text pt str layer style ht rot) -> ename  (left / baseline, rot rad)
(defun st:draw-text (pt str layer style ht rot)
  (entmakex
    (list '(0 . "TEXT") (cons 8 layer) (cons 7 style)
          (cons 10 pt) (cons 11 pt) (cons 40 ht)
          (cons 1 str) (cons 50 rot) (cons 72 0) (cons 73 0))))

;; (st:draw-label-stack base-pt rows layer style ht gap1 gapn) -> top-y
;;   Rows as side-by-side vertical columns advancing +X: first gap gap1, rest
;;   gapn. All share base Y, read upward. Returns Y of the tallest column top.
(defun st:draw-label-stack (base-pt rows layer style ht gap1 gapn / x y i maxlen tl rot)
  (setq x (car base-pt) y (cadr base-pt) i 0 maxlen 0.0 rot (/ pi 2.0))
  (foreach str rows
    (if (> i 0) (setq x (+ x (if (= i 1) gap1 gapn))))
    (st:draw-text (list x y 0.0) str layer style ht rot)
    (setq tl (st:text-length str style ht))
    (if (> tl maxlen) (setq maxlen tl))
    (setq i (1+ i)))
  (+ y maxlen))

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
