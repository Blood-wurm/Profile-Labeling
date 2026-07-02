;;; ==========================================================================
;;; strtools-lib.lsp  --  Shared engine for the structure-labeling toolset
;;; --------------------------------------------------------------------------
;;; Pure functions (args in, value out, no globals) plus an isolated drawing
;;; boundary at the bottom. Commands (STRLABEL, later INVLABEL / STRPROF) call
;;; these; they never call each other. Nothing here reads global state.
;;;
;;; SCOPE: this build supports C:STRLABEL only. Every function below is either
;;; called by STRLABEL now or is a primitive its sibling tools will reuse.
;;;
;;; STATUS: written against the agreed spec; NOT yet run in a live drawing.
;;; Load on a scratch drawing and exercise piece by piece before deploying.
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  the few decisions that may need flipping after a real test.
;;; These are the honest assumptions; change here, nowhere else.
;;; --------------------------------------------------------------------------

;; Rank direction. T => rank 1 is the LOWEST station on the line.
;; Numbering is downstream->upstream. If your .CL is drawn from the downstream
;; (outfall) end as station 0, lowest station = most downstream = rank 1 => T.
;; If .CL zero sits at the upstream end, set this nil.
(setq *st-rank-ascending* T)

;; Column stepping: label lines sit side by side as vertical columns, reading
;; upward (text rotated 90). Columns advance in +X away from the station line.
;; First gap (col 1 -> col 2) is 3.2; every gap after is 2.4.
(setq *st-gap-first* 3.2)
(setq *st-gap-rest*  2.4)

;; Text offset: first text column sits this far in +X from the station line
;; (station line is AT the structure station; text is 1.6 to its right).
(setq *st-text-offset* 1.6)

;; Coincidence tolerance for "snapped" geometry (near-zero epsilon).
(setq *st-eps* 1e-6)


;;; ==========================================================================
;;; SECTION 1  --  String helpers  (pure)
;;; ==========================================================================

;; (st:join list sep) -> string.  Joins strings with a separator.
(defun st:join (lst sep / out first)
  (setq out "" first T)
  (foreach s lst
    (setq out (if first (setq first nil out s) (strcat out sep s))))
  out)

;; (st:split str sep) -> list of strings.  sep is a single character.
(defun st:split (str sep / i n c out cur)
  (setq i 1 n (strlen str) cur "" out '())
  (while (<= i n)
    (setq c (substr str i 1))
    (if (= c sep)
      (setq out (cons cur out) cur "")
      (setq cur (strcat cur c)))
    (setq i (1+ i)))
  (reverse (cons cur out)))

;; (st:digit-p ch) -> T if the single character is 0-9.
(defun st:digit-p (ch)
  (and (>= (ascii ch) 48) (<= (ascii ch) 57)))


;;; ==========================================================================
;;; SECTION 2  --  Centerline geometry / stationing  (pure)
;;; ==========================================================================

;; (st:cl-membership pt cl eps) -> (type . station) | nil
;;   pt  : world point
;;   cl  : centerline entity (ename)
;;   eps : coincidence tolerance
;;   type    is 'end (pt at a centerline endpoint) or 'through (pt on interior)
;;   station is distance along cl to the coincident point
(defun st:cl-membership (pt cl eps / cpt sta spt ept)
  (setq cpt (vlax-curve-getClosestPointTo cl pt))
  (if (and cpt (<= (distance pt cpt) eps))
    (progn
      (setq sta (vlax-curve-getDistAtPoint cl cpt)
            spt (vlax-curve-getStartPoint cl)
            ept (vlax-curve-getEndPoint cl))
      (cons
        (if (or (<= (distance cpt spt) eps) (<= (distance cpt ept) eps))
          'end
          'through)
        sta))
    nil))

;; (st:lines-at-point pt line-table eps) -> list of (name type station)
;;   line-table : list of (ename name) entries, one per named centerline
;;   Returns every centerline hit at pt. 1 hit = single-line, 2+ = junction.
(defun st:lines-at-point (pt line-table eps / result m)
  (setq result '())
  (foreach ent line-table
    (setq m (st:cl-membership pt (car ent) eps))
    (if m
      (setq result (cons (list (cadr ent) (car m) (cdr m)) result))))
  (reverse result))

;; (st:rank-on-line station all-stations ascending eps) -> integer (1-based)
;;   Counts how many structures come before this one in numbering order, +1.
;;   Tolerance-safe; the target station need not appear in all-stations.
(defun st:rank-on-line (station all-stations ascending eps / n)
  (setq n 0)
  (foreach s all-stations
    (if ascending
      (if (< s (- station eps)) (setq n (1+ n)))
      (if (> s (+ station eps)) (setq n (1+ n)))))
  (1+ n))


;;; ==========================================================================
;;; SECTION 3  --  Profile transform  (pure)
;;; ==========================================================================
;;; xform is a parameter list produced by the command's grid read:
;;;   (ll-x ll-y start-sta datum-elev h-scale v-scale top-y)
;;;     ll-x ll-y   : world coords of the grid lower-left corner
;;;     start-sta   : station at the lower-left
;;;     datum-elev  : elevation at the grid bottom
;;;     h-scale     : world units per foot of station   (1.0 if 1:1 horizontal)
;;;     v-scale     : world units per foot of elevation (vertical exaggeration)
;;;     top-y       : world Y of the grid top border

(defun st:xf-llx    (xf) (nth 0 xf))
(defun st:xf-lly    (xf) (nth 1 xf))
(defun st:xf-sta0   (xf) (nth 2 xf))
(defun st:xf-elev0  (xf) (nth 3 xf))
(defun st:xf-hscale (xf) (nth 4 xf))
(defun st:xf-vscale (xf) (nth 5 xf))

;; (st:station->profile-x station xform) -> real
(defun st:station->profile-x (station xform)
  (+ (st:xf-llx xform)
     (* (- station (st:xf-sta0 xform)) (st:xf-hscale xform))))

;; (st:elev->profile-y elev xform) -> real   (unused here; reused by invert pass)
(defun st:elev->profile-y (elev xform)
  (+ (st:xf-lly xform)
     (* (- elev (st:xf-elev0 xform)) (st:xf-vscale xform))))

;; (st:profile-y->elev y xform) -> real   (inverse of the above)
(defun st:profile-y->elev (y xform)
  (+ (st:xf-elev0 xform)
     (/ (- y (st:xf-lly xform)) (st:xf-vscale xform))))

;; (st:grid-top-y xform) -> real
(defun st:grid-top-y (xform) (nth 6 xform))


;;; ==========================================================================
;;; SECTION 4  --  Ground-line sampling  (pure)
;;; ==========================================================================

;; (st:poly-y-at-x ename x) -> Y | nil
;;   Y on a left-to-right polyline at world X, by segment interpolation.
;;   Assumes the ground profile is monotonic-ish in X (true for a drawn ground).
(defun st:poly-y-at-x (ename x / n i p1 p2 y)
  (setq n (fix (vlax-curve-getEndParam ename)) i 0 y nil)
  (while (and (< i n) (null y))
    (setq p1 (vlax-curve-getPointAtParam ename i)
          p2 (vlax-curve-getPointAtParam ename (1+ i)))
    (if (and (<= (min (car p1) (car p2)) x)
             (<= x (max (car p1) (car p2))))
      (if (equal (car p1) (car p2) 1e-9)
        (setq y (cadr p1))
        (setq y (+ (cadr p1)
                   (* (- (cadr p2) (cadr p1))
                      (/ (- x (car p1)) (- (car p2) (car p1))))))))
    (setq i (1+ i)))
  y)

;; (st:ground-elev-at-station station ground-ename xform) -> elev | nil
;;   Samples the proposed ground polyline at the structure's profile X, then
;;   converts the profile Y back to a real-world elevation.
(defun st:ground-elev-at-station (station ground-ename xform / x y)
  (setq x (st:station->profile-x station xform)
        y (st:poly-y-at-x ground-ename x))
  (if y (st:profile-y->elev y xform)))


;;; ==========================================================================
;;; SECTION 5  --  Block name -> type / size lookup  (pure)
;;; ==========================================================================
;;; type-table entries: (PREFIX TYPE-STRING SIZE-BEARING?)
;;;   PREFIX        leading alphabetic token, upper case
;;;   TYPE-STRING   what the label prints
;;;   SIZE-BEARING? T if a size token should be parsed from the name
;;; Extend this list as new families come online (DMH, DSBB, NSBB, castings...).

(setq *st-type-table*
  '(("CBI"  "CURB BOX INLET" nil)
    ("DBI"  "DROP BOX INLET" T)
    ("MH"   "MANHOLE"        nil)
    ("HDWL" "HDWL"           T)))

;; (st:name-prefix name) -> leading alphabetic token (before first "_" or digit)
;;   "CBI_MH_04" -> "CBI"   (first token wins; unambiguous)
;;   "HDWL_PLAN-18" -> "HDWL"
(defun st:name-prefix (name / i c out)
  (setq i 1 out "")
  (while (and (<= i (strlen name))
              (setq c (substr name i 1))
              (/= c "_")
              (not (st:digit-p c)))
    (setq out (strcat out c) i (1+ i)))
  out)

;; (st:type-entry name type-table) -> entry | nil
(defun st:type-entry (name type-table)
  (assoc (strcase (st:name-prefix name)) type-table))

;; (st:blockname->type name type-table) -> type-string | nil
(defun st:blockname->type (name type-table / e)
  (if (setq e (st:type-entry name type-table)) (cadr e)))

;; (st:blockname->size name type-table) -> size-string | nil
;;   Only size-bearing families parse a size; others always return nil, so a
;;   CBI/MH variant number (the "04" in CBI_MH_04) is never mistaken for a size.
;;   ASSUMPTION to verify: sizes are inches, formatted with a trailing ".
(defun st:blockname->size (name type-table / e)
  (setq e (st:type-entry name type-table))
  (if (and e (caddr e)) (st:parse-size name)))

;; (st:parse-size name) -> "18\"" | "24\"x24\"" | nil
;;   Scans for the first dimension token: digits, optional x, digits.
(defun st:parse-size (name / i n c out indim)
  (setq i 1 n (strlen name) out "" indim nil)
  (while (<= i n)
    (setq c (substr name i 1))
    (cond
      ((st:digit-p c) (setq out (strcat out c) indim T))
      ((and indim (member (strcase c) '("X"))) (setq out (strcat out "x")))
      (indim (setq i n)))            ; token ended -> stop scanning
    (setq i (1+ i)))
  (if (= out "") nil (st:size-fmt out)))

;; (st:size-fmt "3x2") -> "3\"x2\""   (append inch mark to each dimension)
(defun st:size-fmt (s)
  (st:join (mapcar '(lambda (p) (strcat p "\"")) (st:split s "x")) "x"))


;;; ==========================================================================
;;; SECTION 6  --  Value formatting  (pure)
;;; ==========================================================================

;; (st:fmt-station sta) -> "X+XX.XX"   e.g. 190.0 -> "1+90.00"
(defun st:fmt-station (sta / hund rem)
  (setq hund (fix (/ sta 100.0))
        rem  (- sta (* hund 100.0)))
  (strcat (itoa hund) "+" (if (< rem 10.0) "0" "") (rtos rem 2 2)))

;; (st:fmt-elev elev prec) -> "579.95"
(defun st:fmt-elev (elev prec) (rtos elev 2 prec))


;;; ==========================================================================
;;; SECTION 7  --  Label composition  (pure)
;;; ==========================================================================

;; (st:combine-id line-names ranks) -> "AB-3/AC-2"
;;   Joins per-line "<line>-<rank>" across every line the structure sits on.
(defun st:combine-id (line-names ranks)
  (st:join
    (mapcar '(lambda (nm rk) (strcat nm "-" (itoa rk))) line-names ranks)
    "/"))

;; (st:build-label-rows line-infos type size id prefix gl) -> list of strings
;;   line-infos : list of (name station), one per line hit, in print order
;;   Returns the ordered row strings, bottom-to-top:
;;     one "STA. <sta> STORM LINE '<line>'" per line
;;        (" =" appended to all but the last, and ONLY when >1 line)
;;     "<prefix> [<size> ]<type> <id>"
;;     "G.L. <elev>"
(defun st:build-label-rows (line-infos type size id prefix gl
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
  (setq const-row
    (strcat prefix " " (if size (strcat size " ") "") type " " id))
  (setq gl-row (strcat "G.L. " (st:fmt-elev gl 2)))
  (append sta-rows (list const-row gl-row)))


;;; ==========================================================================
;;; SECTION 8  --  Drawing boundary  (SIDE-EFFECTING -- isolated on purpose)
;;; ==========================================================================

;; (st:text-length str style ht) -> baseline length of the string when drawn.
;;   Uses textbox on a constructed data list (no temp entity created).
(defun st:text-length (str style ht / box)
  (setq box (textbox (list (cons 1 str) (cons 40 ht) (cons 7 style) (cons 41 1.0))))
  (if box (- (car (cadr box)) (car (car box))) (* (strlen str) ht)))

;; (st:draw-text pt str layer style ht rot) -> ename
;;   One left-justified / baseline-anchored TEXT. rot in radians.
(defun st:draw-text (pt str layer style ht rot)
  (entmakex
    (list '(0 . "TEXT")
          (cons 8 layer)
          (cons 7 style)
          (cons 10 pt)
          (cons 11 pt)
          (cons 40 ht)
          (cons 1 str)
          (cons 50 rot)
          (cons 72 0)      ; horizontal justification: left
          (cons 73 0))))   ; vertical justification: baseline

;; (st:draw-label-stack base-pt rows layer style ht) -> top-y
;;   Places rows as side-by-side vertical columns advancing in +X: first gap
;;   *st-gap-first*, the rest *st-gap-rest*. All columns share base Y and read
;;   upward. Returns the Y of the top of the tallest column (for the station
;;   line's upper endpoint).
(defun st:draw-label-stack (base-pt rows layer style ht / x y i maxlen tl rot)
  (setq x (car base-pt) y (cadr base-pt) i 0 maxlen 0.0 rot (/ pi 2.0))
  (foreach str rows
    (if (> i 0)
      (setq x (+ x (if (= i 1) *st-gap-first* *st-gap-rest*))))
    (st:draw-text (list x y 0.0) str layer style ht rot)
    (setq tl (st:text-length str style ht))
    (if (> tl maxlen) (setq maxlen tl))
    (setq i (1+ i)))
  (+ y maxlen))

;; (st:draw-station-line x grid-top-y top-y layer) -> ename
;;   Vertical LWPOLYLINE at the structure station, grid top up to text top.
(defun st:draw-station-line (x grid-top-y top-y layer)
  (entmakex
    (list '(0 . "LWPOLYLINE")
          '(100 . "AcDbEntity")
          (cons 8 layer)
          '(100 . "AcDbPolyline")
          '(90 . 2)
          '(70 . 0)
          (cons 10 (list x grid-top-y))
          (cons 10 (list x top-y)))))


(princ "\nstrtools-lib.lsp loaded.")
(princ)
;;; ==========================================================================
;;; end of strtools-lib.lsp
;;; ==========================================================================
