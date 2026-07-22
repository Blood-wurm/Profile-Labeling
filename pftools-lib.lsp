;;; ==========================================================================
;;; pftools-lib.lsp  --  PFTools V4 shared engine  (PURE)
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg.lsp loaded first.
;;;
;;; DEPENDENCY GUARDRAIL: this file is the dependency root (with pfdraw).
;;; It may NEVER know what an anchor is, read a record, or reference a
;;; dialog.  Pure math, transforms, string helpers, name parsing, .cl
;;; sampling, membership, ranking, label composition, and READ-ONLY drawing
;;; queries (ssget/entget/textbox).  Nothing here writes to the drawing.
;;;
;;; Carlson native APIs:
;;;   Road API (EWORKS.ARX) -> real stationing + offset from .cl FILES
;;;   DTM  API (TRI4.ARX)   -> surface elevation at X,Y from a .tin FILE
;;; ==========================================================================

(vl-load-com)

;;; ==========================================================================
;;; SECTION 1  --  Carlson API loading + silent error-trapped wrappers
;;; ==========================================================================

(defun pf:load-apis ( / dir)
  (setq dir (if (boundp 'lspdir$) lspdir$ ""))
  (vl-catch-all-apply 'scload (list (strcat dir "tri4")))
  (vl-catch-all-apply 'scload (list (strcat dir "eworks")))
  (princ))

;; ---- Command-echo silencing (native commands are quiet) ------------------
;; Every c: command runs pf:echo-off at its prologue and pf:echo-on at exit;
;; the error path restores via pfa:undo-cleanup.  Saves and restores the
;; user's actual CMDECHO (0 is a valid value -- non-nil in LISP), so a user
;; who runs with echo off keeps it off.
(if (not (boundp '*pf-echo-save*)) (setq *pf-echo-save* nil))

(defun pf:echo-off ()
  (setq *pf-echo-save* (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (princ))

(defun pf:echo-on ()
  (setvar "CMDECHO" (if *pf-echo-save* *pf-echo-save* 1))
  (setq *pf-echo-save* nil)
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
;; Silences Carlson C++ console spam and provides radial fallback for termini.
(defun pf:cl-locate-safe (clfile pt / pt2d res rng sta0 stan pt0 ptn d0 dn)
  (setq pt2d (list (car pt) (cadr pt)))
  (setq res (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_pt" clfile pt2d)))
  (if (and (not (vl-catch-all-error-p res)) res)
    res
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

;; Profile wrappers (Road API "profile_z" / "profile_sta_range") -----------
;; A .pro is READ, never drawn -- the invert/top elevations are authored data.

;; (pf:pro-z pro sta) -> elevation | nil
(defun pf:pro-z (pro sta / r)
  (setq r (vl-catch-all-apply *pf-road-fn* (list "profile_z" pro sta)))
  (if (and (not (vl-catch-all-error-p r)) (numberp r)) r nil))

;; (pf:pro-range pro) -> (s0 s1) | nil
(defun pf:pro-range (pro / r)
  (setq r (vl-catch-all-apply *pf-road-fn* (list "profile_sta_range" pro)))
  (if (and (not (vl-catch-all-error-p r)) (listp r)) r nil))

;; (pf:pro-verts pro) -> ((sta . elev) ...) sorted by sta | nil
;;   Reads the .pro FILE directly for its EXACT vertices -- the one file read in
;;   the suite (every other profile access goes through the Road API), forced by
;;   the API exposing no vertex accessor (only profile_z / profile_sta_range).
;;   A .pro is CSV "sta,elev,0.0" rows, terminated by a "0,0,0" row (then a "1"
;;   and EOF).  Each vertex IS an invert -- PFINVERT brackets structures on them.
;;   Cross-checks one vertex against pf:pro-z (the trusted authored reader) and
;;   warns on a station-domain mismatch.  Cached per path+checksum.
(setq *pf-proverts-cache* '())   ; (path checksum verts)*

(defun pf:pro-verts (pro / cur cell f line parts sta elev verts done vs zz)
  (setq cur (pf:checksum-file pro))
  (cond
    ((null cur) nil)                                   ; unreadable
    ((and (setq cell (assoc pro *pf-proverts-cache*))
          (= (cadr cell) cur))
     (caddr cell))                                     ; HIT -- no re-read
    (T
     (setq verts '() done nil)
     (if (setq f (open pro "r"))
       (progn
         (while (and (not done) (setq line (read-line f)))
           (setq parts (pf:split line ","))
           (if (>= (length parts) 2)
             (progn
               (setq sta  (atof (pf:trim (car parts)))
                     elev (atof (pf:trim (cadr parts))))
               (if (and (equal sta 0.0 1e-9) (equal elev 0.0 1e-9))
                 (setq done T)                          ; "0,0,0" terminator
                 (setq verts (cons (cons sta elev) verts))))))
         (close f)))
     (if verts
       (progn
         (setq verts (vl-sort verts '(lambda (a b) (< (car a) (car b)))))
         ;; station-domain sanity: a mid vertex must match profile_z there
         (setq vs (nth (/ (length verts) 2) verts)
               zz (pf:pro-z pro (car vs)))
         (if (and zz (> (abs (- zz (cdr vs))) 0.02))
           (prompt (strcat "\n  Warning: .pro vertex vs profile_z mismatch at "
                           (pf:fmt-station (car vs)) " (" (rtos (cdr vs) 2 2)
                           " vs " (rtos zz 2 2)
                           ") -- station domain may differ; inverts suspect.")))
         (setq *pf-proverts-cache*
               (cons (list pro cur verts)
                     (vl-remove-if '(lambda (c) (= (car c) pro))
                                   *pf-proverts-cache*))))
       (prompt (strcat "\n  Warning: no vertices parsed from " pro ".")))
     verts)))

;; (pf:pipe-at inv-pro top-pro sta) -> (inv-elev . nominal-size) | nil
;;   inv = invert (flowline) elev; size = nearest nominal to (top-inv) x 12.
;;   Missing/failed TOP leaves size nil (placeholder handled downstream);
;;   a missing/failed INV is fatal to the crossing (nil).
(defun pf:pipe-at (inv-pro top-pro sta / inv top)
  (setq inv (if inv-pro (pf:pro-z inv-pro sta)))
  (if (null inv)
    nil
    (progn
      (setq top (if top-pro (pf:pro-z top-pro sta)))
      (cons inv
            (if (and top (> top inv))
              (pf:nearest-size (* (- top inv) 12.0))
              nil)))))

;;; ---- Crossing discovery: sampled-walk geometry (pure, Road-API) ----------
;;; A target .cl is intersected against a source .cl by walking BOTH at a
;;; fixed station step (arcs followed as Carlson reports them) and testing
;;; segment intersections.  Authored geometry only -- no drawn-entity read.

;; (pf:cl-sample-range clfile s0 s1 step) -> list of (x y) | nil
(defun pf:cl-sample-range (clfile s0 s1 step / rng lo hi sta pts r)
  (if (setq rng (pf:cl-range clfile))
    (progn
      (setq lo  (max (car rng) (min s0 s1))
            hi  (min (cadr rng) (max s0 s1))
            sta lo pts '())
      (while (< sta hi)
        (setq r (vl-catch-all-apply *pf-road-fn*
                  (list "cl_location_at_sta" clfile sta)))
        (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
          (setq pts (cons (list (car (car r)) (cadr (car r))) pts)))
        (setq sta (+ sta step)))
      (setq r (vl-catch-all-apply *pf-road-fn*
                (list "cl_location_at_sta" clfile hi)))
      (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
        (setq pts (cons (list (car (car r)) (cadr (car r))) pts)))
      (if (> (length pts) 1) (reverse pts)))))

;; (pf:cl-sample clfile) -> list of (x y) | nil   (full range walk)
(defun pf:cl-sample (clfile / rng)
  (if (setq rng (pf:cl-range clfile))
    (pf:cl-sample-range clfile (car rng) (cadr rng) *pfx-sample-step*)))

;; (pf:cl-verts clfile) -> list of (x y) | nil
;;   .cl sampling; endpoint chord as a flagged fallback (curves may be missed).
(defun pf:cl-verts (clfile / pts ends)
  (cond
    ((setq pts (pf:cl-sample clfile)) pts)
    ((setq ends (pf:cl-endpoints clfile))
     (prompt (strcat "\n  Warning: .cl sampling failed for "
                     (vl-filename-base clfile)
                     " -- using endpoint CHORD (curves may be missed)."))
     (list (list (car (car ends)) (cadr (car ends)))
           (list (car (cadr ends)) (cadr (cadr ends)))))))

;; (pf:cl-geom clfile) -> (range . verts) | nil     range = (s0 s1)
;;   The cached seam for .cl geometry.  Reads the drawing-wide GEOM store
;;   (pfa:geom-*); on a checksum match it returns the filed shape WITHOUT a
;;   single Road-API call -- this is what lets labeling read a shape instead
;;   of re-tracing it.  On a miss (absent, or the .cl changed on disk) it
;;   samples ONCE, files the result, and returns it.  A transient sample
;;   failure is NOT filed, so the next call retries.  Range is returned even
;;   when verts are unavailable (the proximity filter just goes off).
(defun pf:cl-geom (clfile / cur cached rng vts)
  (setq cur (pf:checksum-file clfile))
  (cond
    ((null cur) nil)                              ; .cl unreadable
    ((and (setq cached (pfa:geom-get clfile))
          (= (car cached) cur))
     (cons (cadr cached) (caddr cached)))         ; HIT -- no Road-API call
    (T                                            ; MISS -- sample + file once
     (setq rng (pf:cl-range clfile)
           vts (pf:cl-verts clfile))
     (cond
       ((and rng vts) (pfa:geom-put clfile cur rng vts) (cons rng vts))
       (rng (cons rng vts))                       ; range only; don't file a miss
       (T nil)))))


;;; ==========================================================================
;;; SECTION 2  --  Corridor geometry  (pure)
;;; ==========================================================================

;; (pf:pt-seg-dist p a b) -> real   distance from 2D point p to segment a-b
(defun pf:pt-seg-dist (p a b / px py ax ay bx by dx dy u len2)
  (setq px (car p)  py (cadr p)
        ax (car a)  ay (cadr a)
        bx (car b)  by (cadr b)
        dx (- bx ax) dy (- by ay)
        len2 (+ (* dx dx) (* dy dy)))
  (if (<= len2 1e-12)
    (distance (list px py) (list ax ay))
    (progn
      (setq u (/ (+ (* (- px ax) dx) (* (- py ay) dy)) len2))
      (setq u (max 0.0 (min 1.0 u)))
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
        (verts (distance (list (car p) (cadr p))
                         (list (caar verts) (cadar verts))))
        (T 1e30)))

;; (pf:in-corridor-p pt verts) -> T | nil
(defun pf:in-corridor-p (pt verts)
  (<= (pf:pt-poly-dist (list (car pt) (cadr pt)) verts) *pf-corridor*))


;;; ==========================================================================
;;; SECTION 3  --  Multi-line membership & stationing
;;; ==========================================================================

;; (pf:lines-at-point pt2d cl-table) -> list of unique (name station)
;;   cl-table entries: (clfile name start end verts)
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
        (if (and (<= off *pf-offset-tol*)
                 (>= sta (- lo *pf-range-eps*))
                 (<= sta (+ hi *pf-range-eps*)))
          (progn
            (setq seen (cons nm seen))
            (setq hits (cons (list off nm sta) hits)))))))
  (setq hits (vl-sort hits '(lambda (a b) (< (car a) (car b)))))
  (mapcar '(lambda (h) (list (cadr h) (caddr h))) hits))

(defun pf:sort-line-infos-alpha (line-infos / names)
  (if (cdr line-infos)                    ; 2+ entries -> sort by name
    (progn
      (setq names (acad_strlsort (mapcar 'car line-infos)))
      (mapcar '(lambda (nm) (assoc nm line-infos)) names))
    line-infos))                          ; 0 or 1 -> nothing to sort

;; (pf:rank-on-line station all-stations ascending eps) -> integer (1-based)
(defun pf:rank-on-line (station all-stations ascending eps / n)
  (setq n 0)
  (foreach s all-stations
    (if ascending
      (if (< s (- station eps)) (setq n (1+ n)))
      (if (> s (+ station eps)) (setq n (1+ n)))))
  (1+ n))

;; (pf:idx-add idx name val) -> idx   (prepends val to name's bucket)
(defun pf:idx-add (idx name val / cell)
  (if (setq cell (assoc name idx))
    (subst (cons name (cons val (cdr cell))) cell idx)
    (cons (list name val) idx)))


;;; ==========================================================================
;;; SECTION 4  --  Profile transform  (ALIST -- the V4 record seam)
;;; ==========================================================================
;;; The xform is an association list.  Core geometric keys (always present):
;;;   leftx  sta0  hscale  topy  basey  datum  vscale  hplot  vplot
;;; Record keys ride along when built from an anchor (pfa:anchor->xform):
;;;   type  name  clfile  pro-inv  pro-top  tin-exist  tin-design  rightx
;;; Extra keys are harmless everywhere; accessors below are the ONLY sanc-
;;; tioned way to read one.

(defun pf:xf-get (key xf) (cdr (assoc key xf)))

(defun pf:make-xform (leftx sta0 topy basey datum vscale hplot vplot)
  (list (cons 'leftx  leftx)
        (cons 'sta0   sta0)
        (cons 'hscale *pf-hscale-fixed*)
        (cons 'topy   topy)
        (cons 'basey  basey)
        (cons 'datum  datum)
        (cons 'vscale vscale)
        (cons 'hplot  hplot)
        (cons 'vplot  vplot)))

;; (pf:xf-put key val xf) -> xf with key set (replaced or added)
(defun pf:xf-put (key val xf / cell)
  (if (setq cell (assoc key xf))
    (subst (cons key val) cell xf)
    (cons (cons key val) xf)))

(defun pf:xf-leftx  (xf) (pf:xf-get 'leftx  xf))
(defun pf:xf-sta0   (xf) (pf:xf-get 'sta0   xf))
(defun pf:xf-hscale (xf) (pf:xf-get 'hscale xf))
(defun pf:xf-topy   (xf) (pf:xf-get 'topy   xf))
(defun pf:xf-basey  (xf) (pf:xf-get 'basey  xf))
(defun pf:xf-datum  (xf) (pf:xf-get 'datum  xf))
(defun pf:xf-vscale (xf) (pf:xf-get 'vscale xf))
(defun pf:xf-hplot  (xf) (pf:xf-get 'hplot  xf))
(defun pf:xf-vplot  (xf) (pf:xf-get 'vplot  xf))

;; sf: every base geometry scalar multiplies by this
(defun pf:xf-sf (xf) (/ (pf:xf-hplot xf) *pf-ref-hplot*))

(defun pf:scale-factor (hplot) (/ hplot *pf-ref-hplot*))
(defun pf:text-height (hplot) (* *pf-text-base-height* (pf:scale-factor hplot)))

;; (pf:station->profile-x station xform) -> real
(defun pf:station->profile-x (station xform)
  (+ (pf:xf-leftx xform)
     (* (- station (pf:xf-sta0 xform)) (pf:xf-hscale xform))))

;; (pf:elev->profile-y elev xform) -> real
(defun pf:elev->profile-y (elev xform)
  (+ (pf:xf-basey xform)
     (* (- elev (pf:xf-datum xform)) (pf:xf-vscale xform))))

;; (pf:y->elev y xform) -> real   (inverse of elev->profile-y)
(defun pf:y->elev (y xform)
  (+ (pf:xf-datum xform)
     (/ (- y (pf:xf-basey xform)) (pf:xf-vscale xform))))

(defun pf:grid-top-y (xform) (pf:xf-topy xform))


;;; ==========================================================================
;;; SECTION 5  --  String helpers  (pure)
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

(defun pf:trim (s) (vl-string-trim " \t" s))

;; (pf:subst-token str token repl) -> str with every `token` replaced
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

;; (pf:index-of item lst) -> 0-based index | nil
(defun pf:index-of (item lst / i found)
  (setq i 0 found nil)
  (foreach x lst
    (if (and (null found) (= x item)) (setq found i))
    (setq i (1+ i)))
  found)

;; (pf:remove-nth idx lst) -> lst with element idx dropped
(defun pf:remove-nth (idx lst / i out)
  (setq i 0 out '())
  (foreach x lst
    (if (/= i idx) (setq out (cons x out)))
    (setq i (1+ i)))
  (reverse out))

;; (pf:dedupe-pairs pairs) -> pairs with duplicate cars dropped (first wins)
(defun pf:dedupe-pairs (pairs / out)
  (setq out '())
  (foreach p pairs
    (if (not (assoc (car p) out)) (setq out (cons p out))))
  (reverse out))


;;; ==========================================================================
;;; SECTION 6  --  Naming convention  (identity keys -- handoff 4.2)
;;; ==========================================================================

(defun pf:basename (file) (vl-filename-base file))

;; (pf:type-of file) -> "STORM" | ...   (text before the FIRST underscore)
(defun pf:type-of (file / base pos)
  (setq base (pf:basename file))
  (if (setq pos (vl-string-search "_" base))
    (strcase (substr base 1 pos))
    (strcase base)))

;; (pf:name-of file) -> text AFTER the first underscore, upcased.
;;   On a .cl this is the line name.  On a .pro it INCLUDES the role suffix
;;   ("LINEA_INV") -- use pf:parse-pro-name for role-aware parsing.
(defun pf:name-of (file / base pos)
  (setq base (pf:basename file))
  (if (setq pos (vl-string-search "_" base))
    (strcase (substr base (+ pos 2)))
    (strcase base)))

;; Alias kept for the dialog code's vocabulary.
(defun pf:parse-line-name (file) (pf:name-of file))

;; (pf:parse-pro-name file) -> (name . role)
;;   Role-aware sibling of pf:name-of: strips the trailing role suffix.
;;   "Storm_LINEA_INV.pro" -> ("LINEA" . "INV")
;;   role nil => the file matches NO positive role suffix => ERROR upstream.
(defun pf:parse-pro-name (file / full len found r suf)
  (setq full (pf:name-of file) len (strlen full) found nil)
  (foreach r *pf-pro-roles*
    (setq suf (strcat "_" r))
    (if (and (null found)
             (> len (strlen suf))
             (= (substr full (- len (strlen suf) -1)) suf))
      (setq found (cons (substr full 1 (- len (strlen suf))) r))))
  (if found found (cons full nil)))

;; (pf:tin-role file) -> 'DESIGN | 'EXISTING   (inverse rule -- guard at setup)
(defun pf:tin-role (file / base pre)
  (setq base (strcase (vl-filename-base file))
        pre  (strcase *pf-tin-design-prefix*))
  (if (and (>= (strlen base) (strlen pre))
           (= (substr base 1 (strlen pre)) pre))
    'DESIGN
    'EXISTING))


;;; ==========================================================================
;;; SECTION 7  --  Utility-type derived layers, templates, sizes
;;; ==========================================================================

(defun pf:sym-layer  (file) (strcat (pf:type-of file) *pfx-layer-suffix*))
(defun pf:text-layer (file) (strcat (pf:type-of file) *pfx-text-layer-suffix*))

(defun pf:align-layer (file / cell)
  (if (setq cell (assoc (pf:type-of file) *pfx-align-layers*))
    (cdr cell)
    (progn
      (prompt (strcat "\n  Warning: no ALIGN layer mapped for type '"
                      (pf:type-of file) "' -- using " (pf:sym-layer file) "."))
      (pf:sym-layer file))))

(defun pf:std-label (file / cell)
  (if (setq cell (assoc (pf:type-of file) *pfx-label-templates*))
    (pf:subst-token (cdr cell) "[name]" (pf:name-of file))
    (progn
      (prompt (strcat "\n  Warning: no label template for type '"
                      (pf:type-of file) "' -- using generic wording."))
      (strcat (pf:type-of file) " LINE '" (pf:name-of file) "'"))))

(defun pf:cross-desc (file / cell)
  (if (setq cell (assoc (pf:type-of file) *pfx-cross-templates*))
    (cdr cell)
    (strcat (pf:type-of file) " CROSSING")))

(defun pf:nearest-size (inches / best bd d)
  (foreach s *pfx-pipe-sizes*
    (setq d (abs (- inches s)))
    (if (or (null best) (< d bd)) (setq best s bd d)))
  best)

(defun pf:size-blockname (n)
  (strcat *pfx-block-prefix* (if (< n 10) "0" "") (itoa n)))

;; (pf:size-rowtext n mat) -> "NN\" MATERIAL"  (blank/nil material -> PIPE)
(defun pf:size-rowtext (n mat)
  (strcat (itoa n) "\" " (if (and mat (/= mat "")) (strcase mat) "PIPE")))


;;; ==========================================================================
;;; SECTION 8  --  Structure label rules  (table lives in pftools-cfg.lsp)
;;; ==========================================================================

(defun pf:rule-tokens  (r) (nth 0 r))
(defun pf:rule-prefix  (r) (nth 1 r))
(defun pf:rule-type    (r) (nth 2 r))
(defun pf:rule-text2   (r) (nth 3 r))
(defun pf:rule-elev    (r) (nth 4 r))
(defun pf:rule-sized-p (r) (nth 5 r))

(defun pf:rule-match-p (upname tokens / ok)
  (setq ok T)
  (foreach tk tokens
    (if (null (vl-string-search tk upname)) (setq ok nil)))
  ok)

(defun pf:rule-for (name rule-table / upname found)
  (setq upname (strcase name) found nil)
  (foreach r rule-table
    (if (and (null found) (pf:rule-match-p upname (pf:rule-tokens r)))
      (setq found r)))
  found)

(defun pf:rule-size (name rule)
  (if (and rule (pf:rule-sized-p rule)) (pf:parse-size name)))

(defun pf:name-prefix (name / i c out)
  (setq i 1 out "")
  (while (and (<= i (strlen name))
              (setq c (substr name i 1))
              (/= c "_")
              (/= c "-")
              (not (pf:digit-p c)))
    (setq out (strcat out c) i (1+ i)))
  out)

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
;;; SECTION 9  --  Value formatting
;;; ==========================================================================

;; (pf:fmt-station sta) -> "X+XX.XX"
(defun pf:fmt-station (sta / hund rem)
  (setq hund (fix (/ sta 100.0)) rem (- sta (* hund 100.0)))
  (strcat (itoa hund) "+" (if (< rem 10.0) "0" "") (rtos rem 2 2)))

(defun pf:fmt-elev (elev prec) (rtos elev 2 prec))


;;; ==========================================================================
;;; SECTION 10  --  Label composition
;;; ==========================================================================

;; (pf:combine-id line-names ranks) -> "AA-1/BB-2/DA-1"
(defun pf:combine-id (line-names ranks)
  (pf:join
    (mapcar '(lambda (nm rk) (strcat nm "-" (itoa rk))) line-names ranks) "/"))

(defun pf:fmt-get (key fmt) (cdr (assoc key fmt)))

;; (pf:build-label-rows line-infos rule size id fmt) -> list of strings
;;   See v3 header for the composition contract (unchanged).
(defun pf:build-label-rows (line-infos rule size id fmt
                            / nlines idx sta-rows const-row text2-row elev-row
                              tail)
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
          (list (pf:rule-prefix rule) size (pf:rule-type rule) id
                (pf:fmt-get "con_suf" fmt))))
  (setq text2-row (pf:rule-text2 rule))
  (setq elev-row
        (if (pf:rule-elev rule)
          (pf:join-parts
            (list (pf:rule-elev rule) *pf-elev-placeholder*
                  (pf:fmt-get "gl_suf" fmt)))))
  (setq tail (list const-row))
  (if (and text2-row (/= text2-row ""))
    (setq tail (append tail (list text2-row))))
  (if elev-row
    (setq tail (append tail (list elev-row))))
  (append sta-rows tail))

;; (pf:text-length str style ht) -> baseline length when drawn (query only)
(defun pf:text-length (str style ht / box)
  (setq box (textbox (list (cons 1 str) (cons 40 ht) (cons 7 style) (cons 41 1.0))))
  (if box (- (car (cadr box)) (car (car box))) (* (strlen str) ht)))


;;; ==========================================================================
;;; SECTION 11  --  .cl sampling & plan intersection  (crossing geometry)
;;; ==========================================================================

(defun pf:pt2 (p) (list (car p) (cadr p)))

;; (pf:sample-cl clfile) -> list of (x y) | nil   (true alignment, arcs followed)
(defun pf:sample-cl (clfile / rng sta0 stan sta pts r)
  (if (setq rng (pf:cl-range clfile))
    (progn
      (setq sta0 (car rng) stan (cadr rng) sta sta0 pts '())
      (while (< sta stan)
        (setq r (vl-catch-all-apply *pf-road-fn*
                  (list "cl_location_at_sta" clfile sta)))
        (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
          (setq pts (cons (pf:pt2 (car r)) pts)))
        (setq sta (+ sta *pfx-sample-step*)))
      (setq r (vl-catch-all-apply *pf-road-fn*
                (list "cl_location_at_sta" clfile stan)))
      (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
        (setq pts (cons (pf:pt2 (car r)) pts)))
      (if (> (length pts) 1) (reverse pts)))))

;; (pf:sample-range clfile s0 s1 step) -> list of (x y) | nil
(defun pf:sample-range (clfile s0 s1 step / rng lo hi sta pts r)
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
          (setq pts (cons (pf:pt2 (car r)) pts)))
        (setq sta (+ sta step)))
      (setq r (vl-catch-all-apply *pf-road-fn*
                (list "cl_location_at_sta" clfile hi)))
      (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
        (setq pts (cons (pf:pt2 (car r)) pts)))
      (if (> (length pts) 1) (reverse pts)))))

;; (pf:poly-x vertsA vertsB) -> first (x y) intersection | nil
;;   cdr-walked, NOT nth-indexed: nth re-walks the list from the head every
;;   call, which made this effectively cubic on sampled alignments (minutes
;;   per pair at 2-ft steps).  Same scan order, same first-hit result.
(defun pf:poly-x (vertsA vertsB / ta tb a1 a2 b1 b2 hit)
  (setq ta vertsA hit nil)
  (while (and (cdr ta) (null hit))
    (setq a1 (car ta)
          a2 (cadr ta)
          tb vertsB)
    (while (and (cdr tb) (null hit))
      (setq b1 (car tb)
            b2 (cadr tb)
            hit (inters a1 a2 b1 b2))
      (setq tb (cdr tb)))
    (setq ta (cdr ta)))
  hit)

;; (pf:refine-x tfile tsta sfile ssta) -> (x y) | nil
(defun pf:refine-x (tfile tsta sfile ssta / tv sv)
  (setq tv (pf:sample-range tfile (- tsta *pfx-sample-step*)
                            (+ tsta *pfx-sample-step*) *pfx-refine-step*)
        sv (pf:sample-range sfile (- ssta *pfx-sample-step*)
                            (+ ssta *pfx-sample-step*) *pfx-refine-step*))
  (if (and tv sv) (pf:poly-x tv sv)))

;; (pf:get-verts clfile) -> list of (x y) vertices | nil
;;   Geometry source order, best first: .cl sampling -> drawn polyline
;;   (chords!) -> endpoint chord (loud warnings on the fallbacks).
(defun pf:get-verts (clfile / pts rng entry verts ends)
  (cond
    ((setq pts (pf:sample-cl clfile)) pts)
    ((setq rng (pf:cl-range clfile))
     (setq entry (pf:attach-corridor
                   (list clfile (pf:basename clfile) (car rng) (cadr rng)))
           verts (nth 4 entry))
     (if (and verts (> (length verts) 1))
       (progn
         (prompt (strcat "\n  Warning: .cl sampling failed for "
                         (pf:basename clfile)
                         " -- using drawn polyline vertices (arcs read as chords)."))
         (mapcar 'pf:pt2 verts))
       (if (setq ends (pf:cl-endpoints clfile))
         (progn
           (prompt (strcat "\n  Warning: using straight endpoint CHORD for "
                           (pf:basename clfile)
                           " -- crossings on curves may be missed or false."))
           (list (pf:pt2 (car ends)) (pf:pt2 (cadr ends)))))))))

;; (pf:sta-at clfile xy) -> station | nil
(defun pf:sta-at (clfile xy / res)
  (if (setq res (pf:cl-locate-safe clfile xy))
    (car res)))


;;; ==========================================================================
;;; SECTION 12  --  Corridor matching  (bind a .cl to its drawn polyline)
;;; ==========================================================================

(defun pf:pt2d-near (a b tol)
  (<= (distance (list (car a) (cadr a)) (list (car b) (cadr b))) tol))

(defun pf:poly-verts (ename / ed etype out sub sd)
  (setq ed (entget ename) etype (cdr (assoc 0 ed)) out '())
  (cond
    ((= etype "LWPOLYLINE")
     (foreach pair ed (if (= (car pair) 10) (setq out (cons (cdr pair) out))))
     (reverse out))
    ((= etype "LINE")
     (list (cdr (assoc 10 ed)) (cdr (assoc 11 ed))))
    ((= etype "POLYLINE")
     (setq sub (entnext ename))
     (while (and sub (setq sd (entget sub)) (= (cdr (assoc 0 sd)) "VERTEX"))
       (setq out (cons (cdr (assoc 10 sd)) out) sub (entnext sub)))
     (reverse out))
    (T nil)))

(defun pf:cl-endpoints (clfile / rng r0 rn p0 pn)
  (if (setq rng (pf:cl-range clfile))
    (progn
      (setq r0 (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_sta" clfile (car rng)))
            rn (vl-catch-all-apply *pf-road-fn* (list "cl_location_at_sta" clfile (cadr rng))))
      (setq p0 (if (and (not (vl-catch-all-error-p r0)) (listp r0)) (car r0))
            pn (if (and (not (vl-catch-all-error-p rn)) (listp rn)) (car rn)))
      (if (and (listp p0) (listp pn)) (list p0 pn)))))

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
(defun pf:attach-corridor (entry / ends verts)
  (if (setq ends (pf:cl-endpoints (car entry)))
    (setq verts (pf:find-cl-polyline (car ends) (cadr ends) *pf-corridor*)))
  (append entry (list verts)))

;; (pf:match-twin-ename p0 pn tol) -> ename | nil
;;   The drawn LWPOLYLINE/LINE/POLYLINE whose two ENDS match the .cl termini
;;   (either direction) within tol.  Endpoint match only -- the interior is
;;   the pre-filter, never a value source.
(defun pf:match-twin-ename (p0 pn tol / ss i e vs a b found)
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,LINE,POLYLINE"))) i 0)
  (if ss
    (while (and (< i (sslength ss)) (null found))
      (setq e  (ssname ss i)
            vs (pf:poly-verts e))
      (if (and vs (> (length vs) 1))
        (progn
          (setq a (car vs) b (last vs))
          (if (or (and (pf:pt2d-near a p0 tol) (pf:pt2d-near b pn tol))
                  (and (pf:pt2d-near a pn tol) (pf:pt2d-near b p0 tol)))
            (setq found e))))
      (setq i (1+ i))))
  found)

;; (pf:cl-twin-handle clfile tol) -> handle string | nil
;;   Match the drawn twin by the .cl's endpoints; return its HANDLE for filing.
(defun pf:cl-twin-handle (clfile tol / ends e)
  (if (and (setq ends (pf:cl-endpoints clfile))
           (setq e (pf:match-twin-ename (car ends) (cadr ends) tol)))
    (cdr (assoc 5 (entget e)))))

;; (pf:twin-verts handle) -> (x y)* | nil    LIVE read of the filed twin
;;   Resolves the handle each call -> verts are always as-drawn.  nil when the
;;   handle is absent, purged, or no longer a usable polyline.
(defun pf:twin-verts (handle / e vs)
  (if (and handle (/= handle "")
           (setq e (handent handle))
           (setq vs (pf:poly-verts e))
           (> (length vs) 1))
    vs))

;;; ==========================================================================
;;; SECTION 13  --  Sheet reads  (identity scan + top-of-grid probe)
;;; ==========================================================================
;;; The sheet-GEOMETRY parser (datum/scale/station-label derivation) is
;;; retired with the AUTO/USER registration model: placement is user-picked,
;;; scales are declared, datum is typed.  What survives of sheet reading:
;;;   - PF-NAME identity text (AUTO registration names the profiles)
;;;   - the TOP-OF-GRID PROBE (the ONLY probe in the suite -- the invert
;;;     probe is dead; inverts come from the .pro via the Road API)

;; (pf:parse-sheet-name s type) -> line name | nil
;;   "STORM LINE 'DA'" + "STORM" -> "DA"
(defun pf:parse-sheet-name (s type / u p1 p2)
  (setq u (strcase s))
  (if (vl-string-search (strcase type) u)
    (progn
      (setq p1 (vl-string-search "'" u))
      (if (null p1) (setq p1 (vl-string-search "`" u)))
      (if p1 (setq p2 (vl-string-search "'" u (1+ p1))))
      (if (and p1 p2 (> p2 (1+ p1)))
        (pf:trim (substr u (+ p1 2) (- p2 p1 1)))))))

;; (pf:sheet-type s) -> "STORM" | "SANITARY" | "WATER" | nil
(defun pf:sheet-type (s / u found)
  (setq u (strcase s) found nil)
  (foreach k *pf-types*
    (if (and (null found) (vl-string-search k u)) (setq found k)))
  found)

;; ---- geometry reads ------------------------------------------------------

;; (pf:bbox e) -> (minx miny maxx maxy) | nil
(defun pf:bbox (e / o mn mx r)
  (setq o (vlax-ename->vla-object e))
  (setq r (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx)))
  (if (not (vl-catch-all-error-p r))
    (progn
      (setq mn (vlax-safearray->list mn)
            mx (vlax-safearray->list mx))
      (list (car mn) (cadr mn) (car mx) (cadr mx)))))

;; (pf:text-pos ed) -> insertion point honoring justification
(defun pf:text-pos (ed / j1 j2)
  (setq j1 (cdr (assoc 72 ed))
        j2 (cdr (assoc 73 ed)))
  (if (and (assoc 11 ed)
           (or (and j1 (/= j1 0)) (and j2 (/= j2 0))))
    (cdr (assoc 11 ed))
    (cdr (assoc 10 ed))))

;; (pf:ss->list ss) -> list of enames
(defun pf:ss->list (ss / i out)
  (setq out '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq out (cons (ssname ss i) out) i (1+ i))))
  (reverse out))

(defun pf:on-layer-p (e la)
  (= (strcase (cdr (assoc 8 (entget e)))) (strcase la)))

(defun pf:filter-layer (ents la)
  (vl-remove-if-not '(lambda (e) (pf:on-layer-p e la)) ents))

;;; --------------------------------------------------------------------------
;;; THE TOP-OF-GRID PROBE  (distinct, named; the only probe in the suite)
;;; --------------------------------------------------------------------------
;;; Grids have STEPPED tops: the frame top varies across a long run, so
;;; "the top border" is a per-station question.  Rule (locked): cast a
;;; vertical ray at X, take the HIGHEST hit on PF-GRID-MJR only -- the top
;;; line lives there, and max self-selects the topmost major line (PF-HBOX
;;; stays out of the filter).  MAX, not min: this must NEVER be conflated
;;; with the dead invert probe (lowest-hit), which does not exist anymore.
;;;
;;; One scan per pass: callers grab pf:top-lines once, then fold pf:top-at
;;; per station.  Bounds come from the anchor (base-y .. nominal top +
;;; *pfg-top-margin* x sf) so the ray can't read the next grid up the sheet.

;; (pf:top-lines) -> list of ((x1 y1) (x2 y2)) for every LINE on the
;;   top-probe layer.  ONE database scan; feed the result to pf:top-at.
(defun pf:top-lines ( / ss i ed out)
  (setq ss (ssget "_X" (list '(0 . "LINE") (cons 8 *pfg-mjr-layer*)))
        out '()
        i 0)
  (if ss
    (while (< i (sslength ss))
      (setq ed (entget (ssname ss i)))
      (setq out (cons (list (pf:pt2 (cdr (assoc 10 ed)))
                            (pf:pt2 (cdr (assoc 11 ed))))
                      out))
      (setq i (1+ i))))
  out)

;; (pf:top-at x ylo yhi lines) -> highest hit Y in [ylo, yhi] | nil
;;   Pure fold over pf:top-lines output.  Verticals at exactly X are
;;   parallel to the ray and contribute nothing (inters -> nil) -- the top
;;   is a horizontal line and always hits.
(defun pf:top-at (x ylo yhi lines / pa pb best hit l)
  (setq pa (list x ylo) pb (list x yhi) best nil)
  (foreach l lines
    (if (setq hit (inters pa pb (car l) (cadr l)))
      (if (or (null best) (> (cadr hit) best))
        (setq best (cadr hit)))))
  best)


;;; ==========================================================================
;;; SECTION 14  --  Content checksum + misc
;;; ==========================================================================

;; (pf:checksum-file file) -> "a-b-n" | nil
;;   Adler-style rolling checksum over the file's text content, line-ending
;;   independent (read-line normalizes CRLF).  ~free on the few-KB .cl/.pro
;;   files; certain, not probabilistic.  nil when the file can't be opened.
(defun pf:checksum-file (file / f line a b n c)
  (setq a 1 b 0 n 0)
  (if (and file (/= file "") (setq f (open file "r")))
    (progn
      (while (setq line (read-line f))
        (foreach c (vl-string->list line)
          (setq a (rem (+ a c) 65521)
                b (rem (+ b a) 65521)))
        (setq a (rem (+ a 10) 65521)
              b (rem (+ b a) 65521)
              n (1+ n)))
      (close f)
      (strcat (itoa a) "-" (itoa b) "-" (itoa n)))))

;; (pf:handle e) -> handle string of an entity
(defun pf:handle (e) (cdr (assoc 5 (entget e))))

;; (pf:timestamp) -> decimal-date string (CDATE, stable rtos mode 2)
(defun pf:timestamp () (rtos (getvar "CDATE") 2 6))


(princ "\npftools-lib.lsp loaded (V4 engine).")
(princ)
;;; ==========================================================================
;;; end of pftools-lib.lsp
;;; ==========================================================================
