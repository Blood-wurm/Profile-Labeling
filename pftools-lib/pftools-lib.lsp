;;; ==========================================================================
;;; pftools-lib.lsp  --  PFTools shared engine (PURE)
;;; Load position 2 of 10: after pftools-cfg, before pfdraw.
;;; Contract, API, and invariants: see README.md beside this file.
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
;; Every command runs pf:echo-off at its prologue (via pf:run-command) and
;; pf:echo-on at exit; the error path restores via pf:run-error.  Saves and
;; restores the user's actual CMDECHO (0 is a valid value -- non-nil in
;; LISP), so a user who runs with echo off keeps it off.
;; SAVE-ONCE semantics: echo-off saves only when no save is pending, so a
;; NESTED call (a queued/deferred command firing inside a wrapped run) can
;; never overwrite the user's CMDECHO with the suite's own 0.
(if (not (boundp '*pf-echo-save*)) (setq *pf-echo-save* nil))

(defun pf:echo-off ()
  (if (null *pf-echo-save*)                 ; save once -- never clobber
    (setq *pf-echo-save* (getvar "CMDECHO")))
  (setvar "CMDECHO" 0)
  (princ))

(defun pf:echo-on ()
  (if *pf-echo-save*
    (progn
      (setvar "CMDECHO" *pf-echo-save*)
      (setq *pf-echo-save* nil)))
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

;;; ---- The .cl FILE parser  (exact vertices, authored stations) -------------
;;; Format probe CLOSED 2026-07-27 against Carlson_References/*.cl.  A .cl is
;;; CSV, one row per alignment point, terminated by "0,0,L,0,0":
;;;
;;;   0, station, L,  northing, easting     tangent PI
;;;   0, station, PC, northing, easting     start of arc
;;;   0, delta,   R,  northing, easting     the arc's RADIUS POINT (centre)
;;;   0, station, PT, northing, easting     end of arc
;;;
;;; FOUR THINGS THAT BITE, every one of them SILENT if missed:
;;;   1. column 2 on an R row is the DELTA, not a station -- read it
;;;      positionally and negative "stations" splice into the list.
;;;   2. that delta is packed DD.MMSSsss, NOT decimal degrees:
;;;      -21.575746298 is -21d57'57.46" = -21.96596 deg.
;;;   3. columns 4/5 on an R row are the arc CENTRE, not a vertex.  Push it
;;;      into the shape and the polyline grows a leg running hundreds of feet
;;;      off the alignment (985 ft, on the sample set's flattest curve).
;;;   4. the file is NORTHING,EASTING; the drawing is X=easting, Y=northing.
;;;      A swapped parse reflects the alignment about y=x: correct lengths,
;;;      correct radii, correct stations, ~971,000 ft from where it belongs,
;;;      and nothing errors -- every structure just reads as "not on any named
;;;      centerline".  Confirmed by ID on the live drawing (Storm_BA start
;;;      X = 1804451.14 = column 5) and re-checked per file by pf:cl-parse-ok-p.
;;;
;;; Stations are measured ALONG THE ARC, so a curve's station delta IS its arc
;;; length -- which, with the centre, fixes the sweep without having to trust
;;; the delta at all.  The delta's SIGN gives turn direction (negative = right,
;;; in drawing space); its magnitude is used only as a cross-check.
;;;
;;; ARCS ARE DENSIFIED at *pfx-sample-step*, not carried as curves: the GEOM
;;; store holds points.  Densified points sit exactly ON the arc with exactly
;;; interpolated stations -- only the chords BETWEEN them cut the corner, by
;;; R(1-cos(sweep/2n)), which is ~0.005 ft on the tightest curve in the sample
;;; set (R=104) against a 0.2 ft corridor.  Carrying true bulges is the better
;;; long answer and does not require this parser to be rewritten.

;; (pf:dms->deg packed) -> signed decimal degrees.  DD.MMSSsss -> DD.dddddd
(defun pf:dms->deg (v / sgn d r m s)
  (setq sgn (if (< v 0) -1.0 1.0)
        v   (abs v)
        d   (fix v)
        r   (* (- v d) 100.0)                  ; MM.SSsss
        m   (fix r)
        s   (* (- r m) 100.0))
  (* sgn (+ d (/ m 60.0) (/ s 3600.0))))

;; (pf:cl-arc-points cx cy pc pt delta) -> intermediate (x y sta), PC/PT EXCLUDED
;;   pc/pt are (x y sta).  Sweep magnitude comes from the STATIONING
;;   (arclen / R) because that is what the label maths must agree with; the
;;   file's delta supplies only the direction, and its magnitude is checked
;;   against the stationing rather than trusted over it.
(defun pf:cl-arc-points (cx cy pc pt delta / r rt arclen a0 sweep n i tt out)
  (setq r      (distance (list cx cy) (pf:pt2 pc))
        rt     (distance (list cx cy) (pf:pt2 pt))
        arclen (- (caddr pt) (caddr pc)))
  (cond
    ((or (<= r 1e-6) (<= arclen 1e-6)) nil)
    (T
     (if (> (abs (- r rt)) 0.01)
       (prompt (strcat "\n  Warning: .cl arc at sta " (pf:fmt-station (caddr pc))
                       " -- centre is " (rtos r 2 3) " from PC but "
                       (rtos rt 2 3) " from PT; arc suspect.")))
     (setq a0    (atan (- (cadr pc) cy) (- (car pc) cx))
           sweep (/ arclen r))                        ; radians, magnitude
     (if (< delta 0) (setq sweep (- sweep)))          ; negative delta = right
     ;; cross-check the file's own delta against what the stationing implies
     (if (> (abs (- (abs (pf:dms->deg delta))
                    (/ (* (abs sweep) 180.0) pi))) 0.05)
       (prompt (strcat "\n  Warning: .cl arc at sta " (pf:fmt-station (caddr pc))
                       " -- delta reads " (rtos (abs (pf:dms->deg delta)) 2 4)
                       " deg but stationing implies "
                       (rtos (/ (* (abs sweep) 180.0) pi) 2 4)
                       " deg; stationing used.")))
     (setq n (fix (+ (/ arclen *pfx-sample-step*) 0.9999)))
     (if (< n 1) (setq n 1))
     (setq out '() i 1)
     (while (< i n)
       (setq tt  (/ (float i) (float n))
             out (cons (list (+ cx (* r (cos (+ a0 (* sweep tt)))))
                             (+ cy (* r (sin (+ a0 (* sweep tt)))))
                             (+ (caddr pc) (* arclen tt)))
                       out)
             i   (1+ i)))
     (reverse out))))

;; (pf:cl-parse-ok-p clfile verts) -> T | nil
;;   The pf:pro-verts precedent (line 92: cross-check the parse against the
;;   trusted authored reader) applied to the .cl.  Two Road-API calls, on a
;;   GEOM miss only -- against the ~570-2200 the walk it replaces would cost.
;;     - station domain: parsed first/last station vs cl_sta_range
;;     - coordinate order: parsed first vertex vs cl_location_at_sta there
;;   A mismatch REFUSES the parse (caller falls back to the walk) rather than
;;   silently correcting it.  The swapped case is called out by name because
;;   that is the one failure that otherwise looks like missing data.
(defun pf:cl-parse-ok-p (clfile verts / rng v0 vn r p)
  (setq v0 (car verts) vn (last verts))
  (cond
    ((null (setq rng (pf:cl-range clfile)))
     (prompt (strcat "\n  Note: no station range from the Road API for "
                     (vl-filename-base clfile)
                     " -- parse accepted unverified."))
     T)
    ((> (abs (- (caddr v0) (car rng))) 0.01)
     (prompt (strcat "\n  Warning: parsed .cl start sta "
                     (pf:fmt-station (caddr v0)) " but the API reports "
                     (pf:fmt-station (car rng)) " -- parse REFUSED."))
     nil)
    ((> (abs (- (caddr vn) (cadr rng))) 0.01)
     (prompt (strcat "\n  Warning: parsed .cl end sta "
                     (pf:fmt-station (caddr vn)) " but the API reports "
                     (pf:fmt-station (cadr rng)) " -- parse REFUSED."))
     nil)
    (T
     (setq r (vl-catch-all-apply *pf-road-fn*
               (list "cl_location_at_sta" clfile (caddr v0))))
     (cond
       ((or (vl-catch-all-error-p r) (not (listp r)) (not (listp (car r))))
        (prompt (strcat "\n  Note: could not locate the start station of "
                        (vl-filename-base clfile)
                        " for a coordinate check -- station domain matched, "
                        "parse accepted."))
        T)
       (T
        (setq p (pf:pt2 (car r)))
        (cond
          ((<= (distance p (pf:pt2 v0)) *pf-corridor*) T)
          ((<= (distance p (list (cadr v0) (car v0))) *pf-corridor*)
           (prompt (strcat "\n  Warning: " (vl-filename-base clfile)
                           " parses SWAPPED -- its columns are easting,northing,"
                           " not northing,easting.  Parse REFUSED (the shape"
                           " would be mirrored about y=x)."))
           nil)
          (T
           (prompt (strcat "\n  Warning: parsed .cl start point is "
                           (rtos (distance p (pf:pt2 v0)) 2 2)
                           " ft from where the API puts it ("
                           (vl-filename-base clfile) ") -- parse REFUSED."))
           nil)))))))

;; (pf:cl-parse clfile) -> ((x y sta) ...) | nil
;;   Drawing coordinates, strictly ascending station, arcs densified.  nil
;;   means this file is not parseable under the documented grammar and the
;;   CALLER must fall back to the Road-API walk.  NEVER GUESSES: one unknown
;;   row code refuses the whole file, because the failure mode of guessing
;;   (a curve read as a chord) is silent and wrong rather than loud.
(defun pf:cl-parse (clfile / f line parts v flag c4 c5 out pc ptv cen delta
                             done bad prev keep)
  (setq out '() pc nil cen nil delta nil done nil bad nil)
  (if (null (setq f (open clfile "r")))
    (setq bad "could not be opened")
    (progn
      (while (and (not done) (not bad) (setq line (read-line f)))
        (setq parts (pf:split line ","))
        (if (>= (length parts) 5)
          (progn
            (setq v    (atof (pf:trim (nth 1 parts)))
                  flag (strcase (pf:trim (nth 2 parts)))
                  c4   (atof (pf:trim (nth 3 parts)))
                  c5   (atof (pf:trim (nth 4 parts))))
            (cond
              ;; "0,0,L,0,0" -- end of alignment, not a vertex at the origin
              ((and (equal v 0.0 1e-9) (equal c4 0.0 1e-9) (equal c5 0.0 1e-9))
               (setq done T))
              ;; X = easting = col 5, Y = northing = col 4  (see note 4 above)
              ((= flag "L")
               (setq out (cons (list c5 c4 v) out)
                     pc nil cen nil delta nil))
              ((= flag "PC")
               (setq pc  (list c5 c4 v)
                     out (cons pc out)
                     cen nil delta nil))
              ((= flag "R")
               (if (null pc)
                 (setq bad "an R (radius point) row with no preceding PC")
                 (setq cen (list c5 c4) delta v)))
              ((= flag "PT")
               (if (not (and pc cen delta))
                 (setq bad "a PT row without its PC/R pair")
                 (progn
                   (setq ptv (list c5 c4 v))
                   (foreach p (pf:cl-arc-points (car cen) (cadr cen)
                                                pc ptv delta)
                     (setq out (cons p out)))
                   (setq out (cons ptv out) pc nil cen nil delta nil))))
              (T (setq bad (strcat "unknown row code '" flag "'")))))))
      (close f)))
  (setq out (reverse out))
  ;; Station must ASCEND -- every consumer assumes it.  But not every repeat is
  ;; a fault: a COMPOUND curve emits the first arc's PT and the second's PC at
  ;; the same point and the same station, and a duplicate vertex must be
  ;; DROPPED, not used to refuse the file.  Only two things are real faults --
  ;; a station that goes backwards, and a station that repeats while the point
  ;; MOVES (which would break station->X for everything between).  The two get
  ;; separate messages because they mean different things about the .cl.
  (if (and (not bad) (cdr out))
    (progn
      (setq keep (list (car out)) prev (car out))
      (foreach p (cdr out)
        (cond
          (bad)
          ((> (caddr p) (caddr prev))
           (setq keep (cons p keep) prev p))
          ((and (equal (caddr p) (caddr prev) 1e-6)
                (<= (distance (pf:pt2 p) (pf:pt2 prev)) 1e-4)))   ; duplicate -- drop
          ((equal (caddr p) (caddr prev) 1e-6)
           (setq bad (strcat "station " (pf:fmt-station (caddr p))
                             " REPEATS while the point moves "
                             (rtos (distance (pf:pt2 p) (pf:pt2 prev)) 2 2)
                             " ft")))
          (T
           (setq bad (strcat "station DECREASES to " (pf:fmt-station (caddr p))
                             " after " (pf:fmt-station (caddr prev)))))))
      (setq out (reverse keep))))
  (cond
    (bad
     (prompt (strcat "\n  Note: " (vl-filename-base clfile) ".cl -- " bad
                     "; falling back to the station walk."))
     nil)
    ((< (length out) 2)
     (prompt (strcat "\n  Note: " (vl-filename-base clfile)
                     ".cl parsed fewer than 2 vertices; falling back to the "
                     "station walk."))
     nil)
    ((null (pf:cl-parse-ok-p clfile out)) nil)
    (T out)))

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

;; (pf:cl-geom clfile write-p) -> (range . verts) | nil     range = (s0 s1)
;;   The cached seam for .cl geometry.  Reads the drawing-wide GEOM store
;;   (pfa:geom-*); on a checksum match it returns the filed shape WITHOUT a
;;   single Road-API call -- this is what lets labeling read a shape instead
;;   of re-tracing it.  On a miss (absent, or the .cl changed on disk) it
;;   samples ONCE and returns the result; it FILES the sample only when
;;   write-p is T.  A transient sample failure is never filed, so the next
;;   call retries.  Range is returned even when verts are unavailable (the
;;   proximity filter just goes off).
;;
;;   WRITE-P IS THE READ/WRITE SEAM (palette contract): the label commands'
;;   GATHER paths (run dialogs, setup -- all pre-undo-group, and one day a
;;   modeless palette handler) MUST pass nil -- a cache miss there costs one
;;   re-sample, never a drawing write.  Registration (PFSETUP) and discovery
;;   (PFXLABEL, inside its command undo group) pass T and own the filing.
(defun pf:cl-geom (clfile write-p / cur cached rng vts kind)
  (setq cur (pf:checksum-file clfile))
  (cond
    ((null cur) nil)                              ; .cl unreadable
    ((and (setq cached (pfa:geom-get clfile))
          (= (car cached) cur))
     (cons (cadr cached) (caddr cached)))         ; HIT -- no Road-API call
    (T                                            ; MISS -- read; file only when allowed
     ;; EXACT FIRST (stage 2, landed 2026-07-27): pf:cl-parse reads the .cl
     ;; file and returns stationed vertices for the cost of a file read.  The
     ;; range comes off the parse itself -- its endpoints were verified against
     ;; cl_sta_range inside pf:cl-parse-ok-p, so re-asking the API is waste.
     ;; A refused parse falls all the way back to the old station walk, so no
     ;; alignment this parser cannot read can regress.
     (setq vts (pf:cl-parse clfile))
     (if vts
       (setq rng  (list (caddr (car vts)) (caddr (last vts)))
             kind *pf-geom-exact*)
       (setq rng  (pf:cl-range clfile)
             vts  (pf:cl-verts clfile)
             kind *pf-geom-sampled*))             ; walked verts carry no station
     (cond
       ((and rng vts)
        (if write-p (pfa:geom-put clfile cur rng vts kind))
        ;; FILE the stationed triples (that is the whole point of EXACT), but
        ;; RETURN plain (x y) -- the HIT branch returns pfa:collect-10, so both
        ;; branches must agree.  This is not cosmetic: pf:poly-x feeds verts to
        ;; `inters`, which reads a third element as Z and finds no intersection
        ;; between segments hundreds of "feet" apart in a station-valued Z.
        ;; Callers wanting stations read (nth 4 (pfa:geom-get ...)).
        (cons rng (mapcar 'pf:pt2 vts)))
       (rng (cons rng (if vts (mapcar 'pf:pt2 vts))))  ; range only; don't file
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

;; (pf:in-corridor-p pt verts tol) -> T | nil
;;   tol nil => *pf-corridor* (an EXACT shape: drawn-twin PIs).  A shape that
;;   only approximates the .cl passes its own wider corridor -- see
;;   *pf-corridor-sampled*.
(defun pf:in-corridor-p (pt verts tol)
  (<= (pf:pt-poly-dist (list (car pt) (cadr pt)) verts)
      (if tol tol *pf-corridor*)))

;; (pf:verts-bbox verts) -> (minx miny maxx maxy) | nil
;;   Computed ONCE when the line table is built; the walk it saves is paid per
;;   structure per line.
(defun pf:verts-bbox (verts / minx miny maxx maxy v x y)
  (if verts
    (progn
      (setq minx 1e30 miny 1e30 maxx -1e30 maxy -1e30)
      (foreach v verts
        (setq x (car v) y (cadr v))
        (if (< x minx) (setq minx x))
        (if (> x maxx) (setq maxx x))
        (if (< y miny) (setq miny y))
        (if (> y maxy) (setq maxy y)))
      (list minx miny maxx maxy))))

;; (pf:in-bbox-p pt box tol) -> T | nil    O(1) REJECTION GUARD
;;   Sound with ZERO false negatives, and the proof does not mention the
;;   line's shape: if q is the nearest point on the polyline to pt and
;;   dist(pt,q) <= tol, then q is inside the box, and |pt.x - q.x| <= tol
;;   (same for y), so pt is inside the box grown by tol.  Contrapositive:
;;   anything this rejects was genuinely further than tol from the line.
;;   Deflections change how much it SAVES (a hooked line has a loose box),
;;   never what it DECIDES -- a false positive costs exactly the
;;   pf:pt-poly-dist walk that would have run anyway.
;;   The box is built from the SAME vertex list pf:pt-poly-dist walks, so the
;;   two can never disagree (densified arcs included).
(defun pf:in-bbox-p (pt box tol)
  (and box
       (>= (car pt)  (- (car box)   tol))
       (<= (car pt)  (+ (caddr box) tol))
       (>= (cadr pt) (- (cadr box)  tol))
       (<= (cadr pt) (+ (cadddr box) tol))))


;;; ==========================================================================
;;; SECTION 3  --  Multi-line membership & stationing
;;; ==========================================================================

;; (pf:lines-at-point pt2d cl-table) -> list of unique (name station)
;;   cl-table entries: (clfile name start end verts [corridor-tol] [bbox])
;;   Slots 6 and 7 are OPTIONAL -- absent (a 5-element entry from
;;   pf:attach-corridor) means the exact *pf-corridor* and no bbox guard.
;;
;;   THE PRE-FILTER IS THE ERROR-PARADE GUARD.  Every point that gets past it
;;   costs a cl_location_at_pt, and a miss makes EWORKS print "unable to locate
;;   point along centerline" straight to the command line -- below LISP, where
;;   pf:cl-locate-safe's vl-catch-all-apply cannot suppress it.  Keep verts on
;;   every entry: nil verts here means every structure in the drawing is tested
;;   against this line, and the parade is that product.
(defun pf:lines-at-point (pt2d cl-table / hits res sta off nm verts lo hi seen
                                          tol)
  (setq hits '() seen '())
  (foreach e cl-table
    (setq nm    (cadr e)
          verts (nth 4 e)
          tol   (if (nth 5 e) (nth 5 e) *pf-corridor*))
    (if (and (not (member nm seen))
             ;; O(1) box rejection BEFORE the O(verts) walk.  Most lines on a
             ;; job are nowhere near a given structure, and this is what stops
             ;; every one of them being walked end to end to find that out.
             (or (null verts)
                 (and (or (null (nth 6 e)) (pf:in-bbox-p pt2d (nth 6 e) tol))
                      (pf:in-corridor-p pt2d verts tol)))
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

;; (pf:profile-x->station x xform) -> real   (inverse of station->profile-x)
;;   Reads a DRAWN entity's X back as the station it was drawn at.  That is what
;;   lets an orphaned label name its station instead of an ordinate.
(defun pf:profile-x->station (x xform)
  (+ (pf:xf-sta0 xform)
     (/ (- x (pf:xf-leftx xform)) (pf:xf-hscale xform))))

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

;; (pf:progress s) -> nil   THE seam for suppressible console output.
;;   Progress is the running commentary a command owes its user while it works.
;;   The palette runs the SAME gather path on every tree click, where that
;;   commentary is noise, so it binds *pf-quiet* (pftools-cfg) around its reads.
;;
;;   USE IT FOR PROGRESS ONLY.  A finding -- an error, a refusal, a skip report,
;;   anything from *error* / pf:run-error -- calls (prompt) directly and always
;;   prints.  The distinction is the whole point: silence the narration, never
;;   the news.
(defun pf:progress (s)
  (if (not *pf-quiet*) (prompt s))
  (princ))

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

;; (pf:cl-id file) -> canonical identity string for a .cl/.pro path.
;;   Slash-normalized (/ -> \) and upcased so spelling variants of ONE file
;;   compare and key identically.  This is the single source of file identity
;;   for GEOM/TWIN keys and pair dedup -- it closes the "stored path string
;;   != requested path string" self-match gap.  Pure string work (no disk
;;   resolution: absolute paths are already what the records store; UNC/mapped
;;   and relative->absolute canonicalisation are deferred).
(defun pf:cl-id (file / i c out)
  (if (or (null file) (= file ""))
    ""
    (progn
      (setq out "" i 1)
      (while (<= i (strlen file))
        (setq c (substr file i 1))
        (setq out (strcat out (if (= c "/") "\\" c)))
        (setq i (1+ i)))
      (strcase out))))

;; (pf:dedupe-pairs pairs) -> pairs with duplicate cars dropped (first wins).
;;   Identity is pf:cl-id, so two spellings of one path collapse to one entry
;;   and the run's answer no longer depends on which spelling came first.
(defun pf:dedupe-pairs (pairs / out seen id)
  (setq out '() seen '())
  (foreach p pairs
    (setq id (pf:cl-id (car p)))
    (if (not (member id seen))
      (setq seen (cons id seen)
            out  (cons p out))))
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

;;; RETIRED 2026-07-29 -- see *pf-anno-layer* / pfd:anno-layer.  All three of
;;; these derive a layer name from the utility type, and nothing does that any
;;; more: every label pass writes to the ONE annotation layer PF-ANNO.  They are
;;; kept, unreferenced, so that reverting to per-type layers is a one-line change
;;; at each call site rather than a rebuild.  pf:align-layer already had no
;;; callers before this.  Expect pf-verify's dead-code gate to name all three.

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

;; (pf:sta-at-end-p rng sta) -> T | nil
;;   Station within *pfx-terminus-tol* of either end of that alignment's range.
(defun pf:sta-at-end-p (rng sta)
  (and rng sta (car rng) (cadr rng)
       (or (<= (abs (- sta (car  rng))) *pfx-terminus-tol*)
           (<= (abs (- sta (cadr rng))) *pfx-terminus-tol*))))

;; (pf:shared-structure-p trng tsta srng ssta) -> T | nil
;;   T when an intersection sits at a terminus of EITHER alignment: two lines
;;   meeting at a SHARED STRUCTURE (a junction manhole, or a branch tying into
;;   a main), not one pipe crossing over or under another.
;;
;;   pf:poly-x cannot tell them apart and never could -- `inters` is a bounded
;;   segment test, and endpoints that touch lie on both segments, so a junction
;;   returns a hit indistinguishable from a crossing.  Near-collinear ties make
;;   it worse by making it INTERMITTENT: whether the touch registers comes down
;;   to floating point, so the same drawing files a false crossing on one pair
;;   and not on its neighbour.
;;
;;   EITHER, not both, and the asymmetry is the whole point.  An end-to-end
;;   junction puts both lines at a terminus, but a branch tying into a main
;;   mid-run puts only the BRANCH there -- the main runs straight through, its
;;   station nowhere near either end.  Requiring both would let every tee past.
;;
;;   The cost of "either" is a genuine crossing that happens to fall within the
;;   band of a line's end.  That is why pfa:xing-scan RETURNS its skips by name
;;   rather than dropping them silently -- a rejected crossing is reported, not
;;   disappeared.  Tolerance is *pfx-terminus-tol* in pftools-cfg.
(defun pf:shared-structure-p (trng tsta srng ssta)
  (or (pf:sta-at-end-p trng tsta) (pf:sta-at-end-p srng ssta)))

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
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (410 . "Model"))) i 0)
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
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (410 . "Model"))) i 0)
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
  (setq ss (ssget "_X" (list '(0 . "LINE") (cons 8 *pfg-mjr-layer*)
                             '(410 . "Model")))     ; model space only
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

;; Adler-style rolling checksum over the file's text content, line-ending
;; independent (read-line normalizes CRLF); certain, not probabilistic.
;;
;; ---- The memo in front of it ---------------------------------------------
;; "~free on the few-KB .cl/.pro files" was true per call and wrong per RUN:
;; pf:checksum-read walks every byte in interpreted LISP.  PFLABEL's gather
;; checksums EVERY registry .cl on every run -- 47 full file reads on a real
;; job -- purely to conclude that nothing changed.  The stat probe below is
;; O(1) and answers the same question.
;;
;; CAVEAT: a file edited in place preserving BOTH mtime and size reads from
;; the memo.  Session-scoped (cleared by a reload), and the content walk is
;; still what fills it, so GEOM's self-validation is unchanged in kind.
(setq *pf-cksum-cache* '())        ; (path systime size checksum)*

;; (pf:checksum-file file) -> "a-b-n" | nil    memoised on (path, mtime, size)
(defun pf:checksum-file (file / st sz cell ck)
  (cond
    ((or (null file) (= file "")) nil)
    ((null (setq st (vl-file-systime file))) nil)      ; missing/unreadable
    (T
     (setq sz (vl-file-size file))
     (if (and (setq cell (assoc file *pf-cksum-cache*))
              (equal (cadr cell) st)
              (equal (caddr cell) sz))
       (cadddr cell)                                   ; HIT -- no file read
       (progn
         (setq ck (pf:checksum-read file))
         (if ck
           (setq *pf-cksum-cache*
                 (cons (list file st sz ck)
                       (vl-remove-if '(lambda (c) (= (car c) file))
                                     *pf-cksum-cache*))))
         ck)))))

;; (pf:checksum-read file) -> "a-b-n" | nil   the content walk itself
(defun pf:checksum-read (file / f line a b n c)
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

;; (pf:checksum-strict file) -> "a-b-n" | nil    MEMO-BYPASSING checksum.
;;   pf:checksum-file trusts (path, mtime, size) and its own header records the
;;   caveat: a file edited in place preserving BOTH reads stale out of the memo.
;;   That is an acceptable trade for a CHECK, whose wrong answer dies with the
;;   session.  It is NOT acceptable for a value about to be WRITTEN into a
;;   record, where the wrong answer is persisted and outlives every reload.
;;   So the index's write path calls this: always the content walk, then the
;;   memo is refreshed so later cheap reads agree with what was stored.
(defun pf:checksum-strict (file / st sz ck)
  (cond
    ((or (null file) (= file "")) nil)
    ((null (setq st (vl-file-systime file))) nil)      ; missing/unreadable
    (T
     (setq sz (vl-file-size file)
           ck (pf:checksum-read file))
     (if ck
       (setq *pf-cksum-cache*
             (cons (list file st sz ck)
                   (vl-remove-if '(lambda (c) (= (car c) file))
                                 *pf-cksum-cache*))))
     ck)))

;; (pf:hash-string s) -> "a-b-n" | nil    Adler-32 pair + length over a string.
;;   Same arithmetic as pf:checksum-read, fed characters instead of file lines,
;;   so a stamp built here reads like every other checksum in the suite.
(defun pf:hash-string (s / a b n c)
  (if s
    (progn
      (setq a 1 b 0 n 0)
      (foreach c (vl-string->list s)
        (setq a (rem (+ a c) 65521)
              b (rem (+ b a) 65521)
              n (1+ n)))
      (strcat (itoa a) "-" (itoa b) "-" (itoa n)))))

;; (pf:hash-num v) -> integer in [0, 65520]    one coordinate, foldable.
;;   REM BEFORE FIX, deliberately.  A state-plane northing is ~1.8e6; times
;;   *pf-hash-scale* that is 1.8e10, which is past what (fix) can return, so
;;   the obvious (fix (* v scale)) overflows on exactly the drawings this firm
;;   works on.  Taking the remainder while the value is still a real keeps it
;;   in range, and abs makes a southing hash like a northing.
(defun pf:hash-num (v)
  (fix (abs (rem (* v *pf-hash-scale*) 65521.0))))

;; (pf:verts-hash verts) -> "a-b-n" | nil    ORDER-SENSITIVE shape hash.
;;   WHY THIS EXISTS: the membership pre-filter's fingerprint used to be the
;;   bounding box plus the vertex COUNT (pfa:lines-sig).  Drag one interior
;;   PI of a drawn centerline parallel to the box and neither value moves -- so
;;   the shape reads unchanged while the corridor it defines has shifted, and a
;;   structure can fall outside it with nothing to say so.  That is the exact
;;   edit a drafter makes.  This walks the points.
;;   Cheap in context: O(verts) once per line per run, against a pre-filter that
;;   already walks every vertex once per structure per line.
(defun pf:verts-hash (verts / a b n v)
  (if verts
    (progn
      (setq a 1 b 0 n 0)
      (foreach v verts
        (setq a (rem (+ a (pf:hash-num (car v)))  65521)
              b (rem (+ b a) 65521)
              a (rem (+ a (pf:hash-num (cadr v))) 65521)
              b (rem (+ b a) 65521)
              n (1+ n)))
      (strcat (itoa a) "-" (itoa b) "-" (itoa n)))))

;; (pf:handle e) -> handle string of an entity
(defun pf:handle (e) (cdr (assoc 5 (entget e))))

;; (pf:timestamp) -> decimal-date string (CDATE, stable rtos mode 2)
(defun pf:timestamp () (rtos (getvar "CDATE") 2 6))


;;; ==========================================================================
;;; SECTION 15  --  View: the zoom-to verification parade  (command-agnostic)
;;; ==========================================================================
;;; The ONE place the pure lib issues (command ...) -- and every call is a VIEW
;;; op (ZOOM / DELAY), never an entity write, so the "nothing here writes the
;;; drawing" guardrail holds.  Every input is a resolved number (center, height,
;;; station X, a Y span): no record, anchor, or dialog knowledge crosses this
;;; seam, so all three label commands share it.
;;;
;;; The parade: after each item is drawn, frame it and DELAY so the drafter can
;;; verify the placement; restore the pre-run view when the pass ends.  Born in
;;; PFXLABEL (boss ask); generalized here so PFLABEL/PFINVERT get it too when the
;;; palette's "Zoom To" option is ticked.
;;;
;;; GATE (two independent switches, both must be on):
;;;   *pf-zoom-active*  the per-run flag -- set by pf:zoom-resolve at each engine's
;;;                     entry from either the palette override or the command's own
;;;                     default (PFXLABEL on, PFLABEL/PFINVERT off).
;;;   *pf-zoom-pause*   the DURATION (cfg); 0 disables regardless.

;; ---- gate state ----------------------------------------------------------
(if (not (boundp '*pf-zoom-to*))        (setq *pf-zoom-to* nil))     ; palette override channel: 'ON | 'OFF | nil (read once, cleared)
                                     ; TRANSITIONAL -- the Commands tab will carry
                                     ; the option IN the order ticket ((zoom . T))
                                     ; instead; this global goes away with that
                                     ; wiring (a one-shot global is fragile once
                                     ; commands are queued/deferred).
(if (not (boundp '*pf-zoom-active*))    (setq *pf-zoom-active* nil)) ; the effective per-run flag the primitives read
(if (not (boundp '*pf-zoom-count*))     (setq *pf-zoom-count* 0))    ; items framed this pass (drives the end-restore)
(if (not (boundp '*pf-zoom-floor*))     (setq *pf-zoom-floor* 0.0))  ; this pass's min frame height (set by pf:zoom-begin)
(if (not (boundp '*pf-zoom-view-save*)) (setq *pf-zoom-view-save* nil)) ; (ctr . size); global so an *error* handler can reach it

;; (pf:zoom-resolve default) -> boolean   Establish *pf-zoom-active* for this run.
;;   A pending palette override (*pf-zoom-to* 'ON/'OFF) wins and is consumed;
;;   otherwise the command's own default.  Call ONCE per engine run, INSIDE the
;;   ctx guard (a nil-ctx abort must not consume a pending override), so BOTH
;;   the modal command and the future deferred palette command route through it.
(defun pf:zoom-resolve (default / v)
  (setq v (cond ((eq *pf-zoom-to* 'ON)  T)
                ((eq *pf-zoom-to* 'OFF) nil)
                (T default))
        *pf-zoom-to*     nil          ; read once, cleared
        *pf-zoom-active* v)
  v)

;; (pf:zoom-on-p) -> T when the parade should run this pass
(defun pf:zoom-on-p () (and *pf-zoom-active* (> *pf-zoom-pause* 0.0)))

;; (pf:zoom-corners ctr h) -> (p1 p2)
;;   Window corners reproducing a center+height view at the current screen
;;   aspect.  ZOOM _Center <pt> <height> miscomputes in this Carlson/Map build
;;   (fails "No Center found for specified point"); ZOOM _Window is the robust
;;   equivalent, so every view change routes through here.  The framed area is
;;   identical -- height drives, width follows the viewport aspect.
;;   GUARDED: a degenerate SCREENSIZE (minimized/scripted session) falls back
;;   to aspect 1.0; a zero/nil height falls back to the current VIEWSIZE --
;;   a view op must never be the thing that crashes a label pass.
(defun pf:zoom-corners (ctr h / scr asp w)
  (setq scr (getvar "SCREENSIZE")
        asp (if (and scr (numberp (cadr scr)) (> (cadr scr) 0.0))
              (/ (car scr) (cadr scr))
              1.0)
        h   (if (and (numberp h) (> (abs h) 1e-9))
              (abs h)
              (getvar "VIEWSIZE"))
        w   (* h asp))
  (list (list (- (car ctr) (* 0.5 w)) (- (cadr ctr) (* 0.5 h)))
        (list (+ (car ctr) (* 0.5 w)) (+ (cadr ctr) (* 0.5 h)))))

;; (pf:zoom-cwh ctr h) -> nil   Window zoom in NORMAL command context.
;;   An *error* handler must NOT use this (command is illegal there) -- it issues
;;   its own command-s zoom off pf:zoom-corners (see pf:zoom-onerror).
(defun pf:zoom-cwh (ctr h / cw)
  (setq cw (pf:zoom-corners ctr h))
  (command "_.ZOOM" "_Window" (car cw) (cadr cw)))

;; (pf:zoom-begin sf) -> nil   Open a parade: reset the frame count, fix this
;;   pass's frame floor (*pf-zoom-min-height* x sf) and, when on, snapshot the
;;   pre-run view for the end-restore.  Call before the label loop with the
;;   run's scale factor (pf:xf-sf); nil sf = floor at base scale.
(defun pf:zoom-begin (sf)
  (setq *pf-zoom-count* 0
        *pf-zoom-floor* (* *pf-zoom-min-height* (if (numberp sf) sf 1.0)))
  (if (pf:zoom-on-p)
    (setq *pf-zoom-view-save* (cons (getvar "VIEWCTR") (getvar "VIEWSIZE"))))
  (princ))

;; (pf:zoom-item x ylo yhi) -> nil   THE COMMAND-AGNOSTIC SEAM.  Frame the item
;;   at station X over the vertical span [ylo yhi] and DELAY.  No-op unless the
;;   parade is on.  ONE RULE FOR ALL THREE COMMANDS: pass the full extent of
;;   interest at that station -- grid base/top plus whatever was drawn beyond
;;   them; this normalises the span (order-proof) and enforces the pass floor
;;   (*pf-zoom-floor*), so no caller can produce a flipped or keyhole window.
;;   Counts a frame so pf:zoom-end knows work happened.
(defun pf:zoom-item (x ylo yhi / lo hi h)
  (if (pf:zoom-on-p)
    (progn
      (setq lo (min ylo yhi)
            hi (max ylo yhi)
            h  (max (* 1.4 (- hi lo)) *pf-zoom-floor*))
      (pf:zoom-cwh (list x (* 0.5 (+ lo hi)) 0.0) h)
      (command "_.DELAY" (fix (* *pf-zoom-pause* 1000.0)))
      (setq *pf-zoom-count* (1+ *pf-zoom-count*))))
  (princ))

;; (pf:zoom-end) -> nil   Close a parade: restore the pre-run view when at least
;;   one item was framed (skip the redundant zoom when nothing drew).  Clears the
;;   snapshot either way.  Call after the label loop, before the pass report.
(defun pf:zoom-end ()
  (if (and *pf-zoom-view-save* (> *pf-zoom-count* 0))
    (pf:zoom-cwh (car *pf-zoom-view-save*) (cdr *pf-zoom-view-save*)))
  (setq *pf-zoom-view-save* nil)
  (princ))

;; (pf:zoom-onerror) -> nil   *error*-safe view restore.  Hardened three ways:
;;   - CMDACTIVE gate: command-s from a handler while a command is still live
;;     is the one unreliable case -- skip the restore (cosmetic loss) rather
;;     than risk a cascading error that unhooks the *error* chain.
;;   - CMDECHO is saved/zeroed/restored locally: pf:run-error has already
;;     run pf:echo-on by the time this fires, so without this the recovery
;;     ZOOM would echo on every Esc.
;;   - the ZOOM itself is vl-catch-all wrapped: an error INSIDE an *error*
;;     handler must never propagate.
;;   The snapshot is cleared on every path.
(defun pf:zoom-onerror ( / cw ce)
  (if (and *pf-zoom-view-save* (= (getvar "CMDACTIVE") 0))
    (progn
      (setq ce (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (setq cw (pf:zoom-corners (car *pf-zoom-view-save*)
                                (cdr *pf-zoom-view-save*)))
      (vl-catch-all-apply 'command-s
        (list "_.ZOOM" "_Window" (car cw) (cadr cw)))
      (setvar "CMDECHO" ce)))
  (setq *pf-zoom-view-save* nil)
  (princ))


(princ "\npftools-lib.lsp loaded (V4 engine).")
(princ)
;;; ==========================================================================
;;; end of pftools-lib.lsp
;;; ==========================================================================
