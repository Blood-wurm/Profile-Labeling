;;; ==========================================================================
;;; pfreport.lsp  --  C:PFREPORT : Hydraflow Storm Sewers .stm export
;;;                   Dialog: pfrpt_run.
;;; Load position 10 of 11: after pfinvert, before pfpalette.
;;; Model, API, and invariants: see README.md beside this file.
;;;
;;; THE STRUCTURAL DIFFERENCE from every other PFTools command: this one is
;;; SYSTEM-scoped, not target-scoped.  There is no anchor pick and no
;;; pfs:choose-or-place -- the user selects a SET of registered profiles and
;;; the export builds ONE network out of them.  It is also entirely READ-ONLY
;;; on the drawing: the .stm on disk is the only write, so there is no undo
;;; group, no pass ledger and no STATUS update.
;;; ==========================================================================

(vl-load-com)

(setq *pfr-fatal* '())      ; run-scoped: blocking findings
(setq *pfr-warn*  '())      ; run-scoped: advisory findings


;;; ==========================================================================
;;; SECTION 1  --  Findings
;;; ==========================================================================
;;; Warnings describe what the file will say; fatals stop the export.  Both
;;; are collected and printed once, so the user gets the whole picture in one
;;; pass instead of fixing one thing per run.

(defun pfr:fatal (msg) (setq *pfr-fatal* (cons msg *pfr-fatal*)) nil)
(defun pfr:warn  (msg) (setq *pfr-warn*  (cons msg *pfr-warn*))  nil)

(defun pfr:report ( / m)
  (foreach m (reverse *pfr-warn*)  (prompt (strcat "\n  NOTE:  " m)))
  (foreach m (reverse *pfr-fatal*) (prompt (strcat "\n  ERROR: " m)))
  (princ))

;; (pfr:set-nth i v lst) -> lst with element i replaced
(defun pfr:set-nth (i v lst / n out e)
  (setq n 0 out '())
  (foreach e lst
    (setq out (cons (if (= n i) v e) out) n (1+ n)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 2  --  Value formatting  (the .stm number grammar)
;;; ==========================================================================
;;; Hydraflow writes ~7 SIGNIFICANT digits, trailing zeros dropped, and drops
;;; the leading zero of a magnitude < 1 -- "-.3674316", ".016", "1804860",
;;; "59.98177".  pfr:num reproduces that exactly; every numeric field goes
;;; through it, so an export diffs cleanly against a Hydraflow-written file.

;; (pfr:trim-num s) -> s with trailing zeros / point and the leading 0 dropped
(defun pfr:trim-num (s)
  (if (vl-string-search "." s)
    (progn
      (while (and (> (strlen s) 1) (= (substr s (strlen s) 1) "0"))
        (setq s (substr s 1 (1- (strlen s)))))
      (if (= (substr s (strlen s) 1) ".")
        (setq s (substr s 1 (1- (strlen s)))))))
  (cond
    ((and (>= (strlen s) 3) (= (substr s 1 3) "-0.")) (strcat "-" (substr s 3)))
    ((and (>= (strlen s) 2) (= (substr s 1 2) "0."))  (substr s 2))
    (T s)))

;; (pfr:num v) -> string   v at *pfr-sigfigs* significant digits.
;;   The leading-digit count comes from rtos, not (log), so an exact power of
;;   ten cannot land on the wrong side of a float epsilon.  rtos mode 2 is
;;   pinned decimal -- correct in Architectural/Fractional drawings too.
(defun pfr:num (v / a lead scan dp)
  (if (not (numberp v)) (setq v 0))
  (setq v (float v) a (abs v))
  (cond
    ((< a 1e-12) "0")
    (T
     (if (>= a 1.0)
       (setq lead (strlen (rtos a 2 0)))
       (progn                                   ; < 1: count the leading zeros
         (setq scan a lead 0)
         (while (< scan 0.1) (setq scan (* scan 10.0) lead (1+ lead)))
         (setq lead (- lead))))
     (setq dp (max 0 (min 12 (- *pfr-sigfigs* lead))))
     (pfr:trim-num (rtos v 2 dp)))))

;; ---- record line writers -------------------------------------------------
;; `key` always carries its own trailing " = ": a few Hydraflow keys have no
;; " = " at all ("Minimum Tc used to calc Intensity"), so it is never appended.
(defun pfr:q   (s)       (strcat "\"" (if s s "") "\""))
(defun pfr:kv  (key val) (strcat (pfr:q key) "," (pfr:num val)))
(defun pfr:kvi (key n)   (strcat (pfr:q key) "," (itoa n)))
(defun pfr:kvs (key s)   (strcat (pfr:q key) "," (pfr:q s)))
(defun pfr:kv2 (key a b) (strcat (pfr:q key) "," (pfr:num a) "," (pfr:num b)))
(defun pfr:kv0 (key)     (strcat (pfr:q key) ",0"))


;;; ==========================================================================
;;; SECTION 3  --  The working records
;;; ==========================================================================
;;; PIPE (an alist -- the .stm is LINK-based, so one record carries both ends):
;;;   line clfile mat idx no dsno brg size
;;;   dn-sta up-sta dn-inv up-inv dn-xy up-xy   (the pipe's own end vertices)
;;;   dn-nd  up-nd                              (the structure alists)
;;;   dn-node up-node                           (indices into the node table)
;;; Identity is `idx`, never list identity -- every stamp returns a new list.
;;;
;;; NODE (a structure, in the node table): (xy id sta line rim)

(defun pfr:g (key p) (cdr (assoc key p)))

(defun pfr:p (key val p / cell)
  (if (setq cell (assoc key p))
    (subst (cons key val) cell p)
    (cons (cons key val) p)))

(defun pfr:nd-xy   (nd) (nth 0 nd))
(defun pfr:nd-id   (nd) (nth 1 nd))
(defun pfr:nd-sta  (nd) (nth 2 nd))
(defun pfr:nd-line (nd) (nth 3 nd))
(defun pfr:nd-rim  (nd) (nth 4 nd))


;;; ==========================================================================
;;; SECTION 4  --  Plan geometry  (Road API + bearings)
;;; ==========================================================================

;; (pfr:xy clfile sta) -> (x y) | nil    station -> plan coordinate
(defun pfr:xy (clfile sta / r)
  (setq r (vl-catch-all-apply *pf-road-fn*
            (list "cl_location_at_sta" clfile sta)))
  (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
    (list (car (car r)) (cadr (car r)))))

;; (pfr:norm360 deg) -> deg in [0, 360)
(defun pfr:norm360 (d)
  (setq d (rem d 360.0))
  (if (< d 0.0) (+ d 360.0) d))

;; (pfr:bearing dn up) -> the Hydraflow Bearing field, degrees
;;   Decoded from _Sampl.txt: the NEGATED azimuth measured CCW from +X over
;;   [0,360).  Line 5 of the sample is what pins the branch -- it reads
;;   -215.8961, not the +144.4 a (-180,180] convention would give.
(defun pfr:bearing (dn up / dx dy)
  (setq dx (- (car up) (car dn))
        dy (- (cadr up) (cadr dn)))
  (if (and (equal dx 0.0 1e-9) (equal dy 0.0 1e-9))
    0.0
    (- (pfr:norm360 (/ (* 180.0 (atan dy dx)) pi)))))


;;; ==========================================================================
;;; SECTION 5  --  Profile decomposition  (the .pro IS the pipe network)
;;; ==========================================================================
;;; PFINVERT's vertex bracket, walked whole instead of probed per structure:
;;; every _INV.pro vertex IS an invert, adjacent vertices no more than
;;; *pfi-struct-width-max* apart are ONE structure, and the gaps between those
;;; groups are the PIPES.  Structure, pipe, structure, pipe.

;; (pfr:groups verts) -> list of groups; a group is ((sta . elev) ...)
(defun pfr:groups (verts / out cur prev v)
  (setq out '() cur '() prev nil)
  (foreach v verts
    (if (or (null prev) (<= (- (car v) (car prev)) *pfi-struct-width-max*))
      (setq cur (cons v cur))
      (setq out (cons (reverse cur) out) cur (list v)))
    (setq prev v))
  (if cur (setq out (cons (reverse cur) out)))
  (reverse out))

(defun pfr:grp-lo  (g) (car g))                 ; low-station vertex
(defun pfr:grp-hi  (g) (last g))                ; high-station vertex
(defun pfr:grp-mid (g) (* 0.5 (+ (car (pfr:grp-lo g)) (car (pfr:grp-hi g)))))


;;; ==========================================================================
;;; SECTION 6  --  Drawing reads  (structure IDs + rim elevations)
;;; ==========================================================================
;;; Both are pure reads.  Rim/ground elevation is NOT PFTools data: it is the
;;; drafter-filled elevation row PFLABEL drew at the top of the grid
;;; ("T.R. 812.40").  A row still reading *pf-elev-placeholder* is UNFILLED
;;; and exports as 0 with a named warning -- never as a number nobody typed.

;; (pfr:lead-num s) -> real | nil   the first numeric run in s
(defun pfr:lead-num (s / i n c out started)
  (setq i 1 n (strlen s) out "" started nil)
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((pf:digit-p c)          (setq out (strcat out c) started T))
      ((and started (= c ".")) (setq out (strcat out c)))
      (started                 (setq i n))       ; the run ended -- stop
      ((= c "-")               (setq out "-"))
      (T                       (setq out "")))
    (setq i (1+ i)))
  (if started (atof out)))

;; (pfr:text-pt ed) -> the entity's REAL insertion point
;;   Justified TEXT (PFLABEL's rows are ML / MR) carries its position in
;;   group 11, not group 10.
(defun pfr:text-pt (ed / j1 j2)
  (setq j1 (cdr (assoc 72 ed))
        j2 (cdr (assoc 73 ed)))
  (if (and (assoc 11 ed)
           (or (and j1 (/= j1 0)) (and j2 (/= j2 0))))
    (cdr (assoc 11 ed))
    (cdr (assoc 10 ed))))

;; (pfr:elev-texts) -> ((x y prefix value raw) ...)   ONE model-space scan
;;   value is nil for an unfilled placeholder row.  Model space only, for the
;;   same reason pfa:gather-inlets is: paper-space text carries sheet
;;   coordinates, which the station transform would misread.
(defun pfr:elev-texts ( / ss i ed s pt out p)
  (setq ss  (ssget "_X" '((0 . "TEXT") (410 . "Model")))
        out '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq ed (entget (ssname ss i))
            s  (cdr (assoc 1 ed))
            pt (pfr:text-pt ed))
      (if (and s pt)
        (foreach p *pfr-elev-prefixes*
          (if (and (>= (strlen s) (strlen p))
                   (= (strcase (substr s 1 (strlen p))) p))
            (setq out (cons (list (car pt) (cadr pt) p
                                  (pfr:lead-num (substr s (1+ (strlen p))))
                                  s)
                            out)))))
      (setq i (1+ i))))
  out)

;; (pfr:band-texts texts xf) -> the subset that belongs to THIS grid
;;   Y window = grid base up to the top plus *pfr-label-band* x sf.  Grids
;;   stacked on one sheet are separated by this window, never by X.
(defun pfr:band-texts (texts xf / ylo yhi out e)
  (setq ylo (pf:xf-basey xf)
        yhi (+ (pf:xf-topy xf) (* *pfr-label-band* (pf:xf-sf xf)))
        out '())
  (foreach e texts
    (if (and (>= (cadr e) ylo) (<= (cadr e) yhi))
      (setq out (cons e out))))
  out)

;; (pfr:rim-at band xf sta others) -> (elev . prefix) | (nil . reason)
;;   `others` = the other structure stations on this line.  A label row is
;;   claimed only by the structure it is CLOSEST to, which is what keeps the
;;   right-fanning stack (rows sit at line-x + offset + n x gap) from being
;;   read by the next structure over.
(defun pfr:rim-at (band xf sta others / x eps best bd e ex d ox s raw)
  (setq x    (pf:station->profile-x sta xf)
        eps  (* *pfr-rim-eps-factor* (pf:text-height (pf:xf-hplot xf)))
        best nil bd nil raw nil)
  (foreach e band
    (setq ex (car e) d (abs (- ex x)))
    (if (<= d eps)
      (progn
        (setq ox nil)
        (foreach s others
          (if (< (abs (- ex (pf:station->profile-x s xf))) d) (setq ox T)))
        (if (and (null ox) (or (null bd) (< d bd)))
          (setq bd d best e raw (nth 4 e))))))
  (cond
    ((null best) (cons nil "no elevation label row found at this structure"))
    ((null (nth 3 best))
     (cons nil (strcat "the elevation row is still the placeholder (\""
                       (if raw raw "") "\")")))
    (T (cons (nth 3 best) (caddr best)))))

;; (pfr:struct-id ename lines index) -> "AA-1/BB-2" -- PFLABEL's combined ID
;;   Same composition PFLABEL draws, so the .stm's Inlet ID and the sheet's
;;   structure label are the same string by construction.
(defun pfr:struct-id (ename lines index / pt hits alpha names ranks)
  (setq pt    (cdr (assoc 10 (entget ename)))
        hits  (pfa:lines-at ename pt lines)
        alpha (pf:sort-line-infos-alpha hits)
        names (mapcar 'car alpha)
        ranks (mapcar '(lambda (li)
                         (pf:rank-on-line (cadr li)
                                          (cdr (assoc (car li) index))
                                          *pf-rank-ascending* *pf-range-eps*))
                      alpha))
  (if names (pf:combine-id names ranks) ""))

;; (pfr:struct-at pending sta) -> (sta ename blkname) | nil
;;   The nearest structure block within one structure width of the station.
(defun pfr:struct-at (pending sta / best bd d e)
  (setq best nil bd nil)
  (foreach e pending
    (setq d (abs (- (car e) sta)))
    (if (and (<= d *pfi-struct-width-max*) (or (null bd) (< d bd)))
      (setq bd d best e)))
  best)


;;; ==========================================================================
;;; SECTION 7  --  One profile -> its pipe records
;;; ==========================================================================

;; (pfr:node-of grp clfile pending lines index band xf allstas) -> node alist
;;   A NODE is a structure: its CENTRE station (the vertex pair's midpoint),
;;   the plan point THERE -- this is what the graph matches on, never the
;;   pipe-end vertices, which sit half a structure away on each side -- its
;;   PFLABEL combined ID, and its rim elevation read off the sheet.
(defun pfr:node-of (grp clfile pending lines index band xf allstas
                    / mid xy st sta id rim)
  (setq mid (pfr:grp-mid grp)
        xy  (pfr:xy clfile mid)
        st  (pfr:struct-at pending mid)
        sta (if st (car st) mid)
        id  (if st (pfr:struct-id (cadr st) lines index) "")
        rim (pfr:rim-at band xf sta (vl-remove sta allstas)))
  (list (cons 'sta mid)
        (cons 'xy  xy)
        (cons 'id  id)
        (cons 'rim (car rim))
        (cons 'why (if (car rim) nil (cdr rim)))))

;; (pfr:line-pipes r lines index texts inlets) -> list of pipe records | nil
;;   r = a pfa:registry row that pfr:candidates already proved usable.
(defun pfr:line-pipes (r lines index texts inlets
                       / anchor xf clfile name sf3 inv top mat verts grps
                         band pending allstas nodes out i n g gk gk1 lo hi
                         dnv upv dnn upn dnxy upxy mid size pipe nd bad)
  (setq anchor  (nth 3 r)
        name    (cadr r)
        xf      (pfa:anchor->xform anchor)
        clfile  (pf:xf-get 'clfile xf)
        sf3     (pfxl:src-files (car r) name)
        inv     (car sf3)
        top     (cadr sf3)
        mat     (caddr sf3)
        verts   (pf:pro-verts inv)
        grps    (if verts (pfr:groups verts))
        band    (pfr:band-texts texts xf)
        pending (pfa:pending inlets lines name)
        allstas (mapcar 'car pending))
  (cond
    ((null verts)
     (pfr:fatal (strcat "'" name "': the _INV .pro has no readable vertices.")))
    ((< (length grps) 2)
     (pfr:fatal (strcat "'" name "': the _INV .pro holds "
                        (itoa (length grps))
                        " structure(s) -- no pipe run to export.")))
    (T
     ;; one node per structure group, built once and shared by both its pipes
     (setq nodes '() bad nil)
     (foreach g grps
       (setq nodes (cons (pfr:node-of g clfile pending lines index band xf
                                      allstas)
                         nodes)))
     (setq nodes (reverse nodes))
     ;; per-STRUCTURE findings, reported here so an interior node (shared by
     ;; two pipes) is not warned about twice
     (foreach nd nodes
       (if (null (pfr:g 'xy nd))
         (progn
           (pfr:fatal (strcat "'" name "': the .cl returned no plan coordinate "
                              "at Sta " (pf:fmt-station (pfr:g 'sta nd))
                              " -- re-bind the .cl with PFSETUP (edit)."))
           (setq bad T)))
       (if (pfr:g 'why nd)
         (pfr:warn (strcat "'" name "' Sta " (pf:fmt-station (pfr:g 'sta nd))
                           ": " (pfr:g 'why nd) " -- rim exported as 0."))))
     (if bad
       nil
       (progn
         (setq out '() i 0 n (length grps))
         (while (< i (1- n))
           (setq gk   (nth i grps)
                 gk1  (nth (1+ i) grps)
                 ;; the pipe runs from Gk's HIGH-station vertex to Gk+1's
                 ;; LOW-station vertex -- face to face, so length, inverts and
                 ;; slope stay mutually consistent with the authored profile
                 lo   (pfr:grp-hi gk)             ; (sta . elev), lower station
                 hi   (pfr:grp-lo gk1)            ; (sta . elev), higher station
                 dnv  (if *pfr-sta-upstream* lo hi)
                 upv  (if *pfr-sta-upstream* hi lo)
                 dnn  (nth (if *pfr-sta-upstream* i (1+ i)) nodes)
                 upn  (nth (if *pfr-sta-upstream* (1+ i) i) nodes)
                 dnxy (pfr:xy clfile (car dnv))
                 upxy (pfr:xy clfile (car upv))
                 mid  (* 0.5 (+ (car lo) (car hi)))
                 size (cdr (pf:pipe-at inv top mid)))
           (cond
             ((or (null dnxy) (null upxy))
              (pfr:fatal (strcat "'" name "': no plan coordinate from the .cl "
                                 "between Sta " (pf:fmt-station (car lo))
                                 " and " (pf:fmt-station (car hi)) ".")))
             (T
              (if (null size)
                (pfr:warn (strcat "'" name "' Sta " (pf:fmt-station (car lo))
                                  " to " (pf:fmt-station (car hi))
                                  ": no pipe size (no _TOP .pro bound, or it "
                                  "is unreadable there) -- Rise/Span exported "
                                  "as 0.")))
              (setq pipe (list (cons 'line   name)
                               (cons 'clfile clfile)
                               (cons 'mat    mat)
                               (cons 'dn-sta (car dnv))
                               (cons 'up-sta (car upv))
                               (cons 'dn-inv (cdr dnv))
                               (cons 'up-inv (cdr upv))
                               (cons 'dn-xy  dnxy)
                               (cons 'up-xy  upxy)
                               (cons 'dn-nd  dnn)
                               (cons 'up-nd  upn)
                               (cons 'size   size)
                               (cons 'idx    0)
                               (cons 'no     0)
                               (cons 'dsno   0)
                               (cons 'brg    0.0))
                    out  (cons pipe out))))
           (setq i (1+ i)))
         (prompt (strcat "\n  '" name "': " (itoa (length out)) " pipe(s), "
                         (itoa n) " structure(s)."))
         (reverse out))))))


;;; ==========================================================================
;;; SECTION 8  --  The graph  (plan coincidence -> Downstream Line No.)
;;; ==========================================================================
;;; Selection bounds the search; it does not supply order.  Nodes are matched
;;; by PLAN COINCIDENCE -- immune to the drop-structure problem that defeats
;;; elevation matching.  Direction comes from stationing.  Elevation is only
;;; ever the check (SECTION 9).

;; (pfr:node-index tbl xy) -> index of the node within *pfr-node-tol* | nil
(defun pfr:node-index (tbl xy / i found nd)
  (setq i 0 found nil)
  (foreach nd tbl
    (if (and (null found) (pfr:nd-xy nd) xy
             (<= (distance (pfr:nd-xy nd) xy) *pfr-node-tol*))
      (setq found i))
    (setq i (1+ i)))
  found)

;; (pfr:build-nodes pipes) -> (pipes . node-table)
;;   Stamps 'idx (the pipe's identity) and 'dn-node / 'up-node (indices) onto
;;   every pipe.  A node shared by two lines is ONE table entry: whichever
;;   line first read an ID or a rim contributes it.
(defun pfr:build-nodes (pipes / tbl out p i k nd idx e)
  (setq tbl '() out '() i 0)
  (foreach p pipes
    (foreach k '(dn-nd up-nd)
      (setq nd  (pfr:g k p)
            idx (pfr:node-index tbl (pfr:g 'xy nd)))
      (if (null idx)
        (setq tbl (append tbl (list (list (pfr:g 'xy nd) (pfr:g 'id nd)
                                          (pfr:g 'sta nd) (pfr:g 'line p)
                                          (pfr:g 'rim nd)))))
        (progn                                  ; merge what this line knows
          (setq e (nth idx tbl))
          (if (and (= (pfr:nd-id e) "") (/= (pfr:g 'id nd) ""))
            (setq e (list (pfr:nd-xy e) (pfr:g 'id nd) (pfr:nd-sta e)
                          (pfr:nd-line e) (pfr:nd-rim e))))
          (if (and (null (pfr:nd-rim e)) (pfr:g 'rim nd))
            (setq e (list (pfr:nd-xy e) (pfr:nd-id e) (pfr:nd-sta e)
                          (pfr:nd-line e) (pfr:g 'rim nd))))
          (setq tbl (pfr:set-nth idx e tbl)))))
    (setq p   (pfr:p 'idx i p)
          p   (pfr:p 'dn-node (pfr:node-index tbl (pfr:g 'xy (pfr:g 'dn-nd p))) p)
          p   (pfr:p 'up-node (pfr:node-index tbl (pfr:g 'xy (pfr:g 'up-nd p))) p)
          out (cons p out)
          i   (1+ i)))
  (cons (reverse out) tbl))

;; (pfr:ds-idx pipes p) -> idx of the pipe whose UP node is p's DN node | nil
;;   nil = p is an outfall.
(defun pfr:ds-idx (pipes p / found q)
  (setq found nil)
  (foreach q pipes
    (if (and (null found)
             (/= (pfr:g 'idx q) (pfr:g 'idx p))
             (= (pfr:g 'up-node q) (pfr:g 'dn-node p)))
      (setq found (pfr:g 'idx q))))
  found)

;; (pfr:order pipes nodes) -> pipes renumbered outfall-first | nil (fatal)
;;   Line 1 is the outfall and every Downstream Line No. is lower than its own
;;   Line No. -- the shape Hydraflow itself writes.  A picked set that is not
;;   ONE connected system with exactly ONE outfall fails here, by name.
(defun pfr:order (pipes nodes / p q outs seen n numbered left keep progress
                   out d nd)
  ;; ---- 1. exactly one outfall --------------------------------------------
  (setq outs '())
  (foreach p pipes
    (if (null (pfr:ds-idx pipes p)) (setq outs (cons p outs))))
  (setq outs (reverse outs))
  (cond
    ((null outs)
     (pfr:fatal "no outfall -- every pipe drains into another one; the selection loops."))
    ((cdr outs)
     (pfr:fatal (strcat "the selection is not ONE system: " (itoa (length outs))
                        " pipes have no downstream neighbour --"))
     (foreach p outs
       (setq nd (nth (pfr:g 'dn-node p) nodes))
       (pfr:fatal
         (strcat "    '" (pfr:g 'line p) "' at Sta "
                 (pf:fmt-station (pfr:g 'dn-sta p))
                 (if (and (pfr:nd-id nd) (/= (pfr:nd-id nd) ""))
                   (strcat " (" (pfr:nd-id nd) ")") "")
                 " ends at a structure no other selected pipe leaves.")))))
  ;; ---- 2. one structure, one outgoing pipe -------------------------------
  (setq seen '())
  (foreach p pipes
    (foreach q pipes
      (if (and (< (pfr:g 'idx p) (pfr:g 'idx q))
               (= (pfr:g 'up-node p) (pfr:g 'up-node q))
               (not (member (pfr:g 'up-node p) seen)))
        (progn
          (setq seen (cons (pfr:g 'up-node p) seen))
          (pfr:fatal (strcat "two pipes leave the same structure: '"
                             (pfr:g 'line p) "' Sta "
                             (pf:fmt-station (pfr:g 'up-sta p)) " and '"
                             (pfr:g 'line q) "' Sta "
                             (pf:fmt-station (pfr:g 'up-sta q)) "."))))))
  (if *pfr-fatal*
    nil
    (progn
      ;; ---- 3. breadth-first from the outfall: a pipe is numbered only
      ;;         after the pipe it drains into
      (setq numbered '() left pipes n 0 out '() progress T)
      (while (and left progress)
        (setq progress nil keep '())
        (foreach p left
          (setq d (pfr:ds-idx pipes p))
          (if (or (null d) (assoc d numbered))
            (setq n        (1+ n)
                  numbered (cons (cons (pfr:g 'idx p) n) numbered)
                  out      (cons (pfr:p 'no n p) out)
                  progress T)
            (setq keep (cons p keep))))
        (setq left (reverse keep)))
      (cond
        (left
         (foreach p left
           (pfr:fatal (strcat "'" (pfr:g 'line p) "' Sta "
                              (pf:fmt-station (pfr:g 'dn-sta p))
                              " never reaches the outfall (disconnected).")))
         nil)
        (T
         ;; ---- 4. stamp Downstream Line No. now that every pipe has one
         (setq out (reverse out))
         (mapcar '(lambda (x / y)
                    (setq y (pfr:ds-idx pipes x))
                    (pfr:p 'dsno (if y (cdr (assoc y numbered)) 0) x))
                 out))))))

;; (pfr:bearings pipes) -> pipes with 'brg stamped
;;   Deflection Angle is emitted as brg(this) - brg(downstream); the ordering
;;   guarantees the downstream bearing is already known.
(defun pfr:bearings (pipes)
  (mapcar '(lambda (p)
             (pfr:p 'brg (pfr:bearing (pfr:g 'dn-xy p) (pfr:g 'up-xy p)) p))
          pipes))


;;; ==========================================================================
;;; SECTION 9  --  Validation  (elevation is the CHECK, never the source)
;;; ==========================================================================
;;; Three independent signals with only one load-bearing: plan coincidence
;;; builds the graph, stationing gives direction, invert continuity proves
;;; both.  A drop structure is not an error -- adjacent pipes simply carry
;;; different elevations at a shared node, exactly as the .pro encodes it.

;; (pfr:node-label nd) -> the structure's ID, or a line+station fallback
(defun pfr:node-label (nd)
  (if (and (pfr:nd-id nd) (/= (pfr:nd-id nd) ""))
    (pfr:nd-id nd)
    (strcat "'" (pfr:nd-line nd) "' Sta " (pf:fmt-station (pfr:nd-sta nd)))))

(defun pfr:validate (pipes nodes / p i nd adverse byline nm cell dn-in out-up
                      drop)
  ;; ---- adverse slope, and the "the convention is backwards" tell ----------
  (setq byline '())
  (foreach p pipes
    (setq nm   (pfr:g 'line p)
          cell (assoc nm byline))
    (if (null cell)
      (setq byline (cons (list nm 0 0) byline) cell (assoc nm byline)))
    (setq adverse (<= (pfr:g 'up-inv p) (pfr:g 'dn-inv p)))
    (setq byline (subst (list nm (1+ (cadr cell))
                              (+ (caddr cell) (if adverse 1 0)))
                        cell byline))
    (if adverse
      (pfr:warn (strcat "'" nm "' Sta " (pf:fmt-station (pfr:g 'dn-sta p))
                        " to " (pf:fmt-station (pfr:g 'up-sta p))
                        ": ADVERSE -- upstream invert "
                        (rtos (pfr:g 'up-inv p) 2 2)
                        " is not above downstream "
                        (rtos (pfr:g 'dn-inv p) 2 2) "."))))
  (foreach cell byline
    (if (and (> (cadr cell) 1) (= (cadr cell) (caddr cell)))
      (pfr:fatal
        (strcat "'" (car cell) "': EVERY pipe reads adverse.  The station "
                "direction convention is backwards for this project -- set "
                "*pfr-sta-upstream* to " (if *pfr-sta-upstream* "nil" "T")
                " in pftools-cfg.lsp and re-run."))))
  ;; ---- invert continuity through each structure --------------------------
  (setq i 0)
  (foreach nd nodes
    (setq out-up nil dn-in nil)
    (foreach p pipes
      (if (= (pfr:g 'up-node p) i) (setq out-up (pfr:g 'up-inv p)))
      (if (and (= (pfr:g 'dn-node p) i)
               (or (null dn-in) (< (pfr:g 'dn-inv p) dn-in)))
        (setq dn-in (pfr:g 'dn-inv p))))
    (if (and out-up dn-in)
      (progn
        (setq drop (- dn-in out-up))
        (cond
          ((< drop (- *pfr-invert-tol*))
           (pfr:fatal (strcat "the invert RISES through structure "
                              (pfr:node-label nd) ": " (rtos dn-in 2 2)
                              " in, " (rtos out-up 2 2)
                              " out.  Fix the .pro or the drawing.")))
          ((> drop *pfr-drop-max*)
           (pfr:warn (strcat "structure " (pfr:node-label nd) " drops "
                             (rtos drop 2 2)
                             " ft -- exported as authored; confirm it is a "
                             "designed drop structure."))))))
    (setq i (1+ i)))
  (princ))


;;; ==========================================================================
;;; SECTION 10  --  Emit
;;; ==========================================================================
;;; Field ORDER is load-bearing -- it is _Sampl.txt's, record for record.

;; Zeroed because PFTools does not hold them.  Fabricating hydrology would be
;; worse than leaving it out: a zero area is visibly unentered in Hydraflow,
;; a plausible one is not.
(setq *pfr-zero-hydrology*
  '("Known Q = " "Sub Drainage Area 1 = " "Sub Drainage Area 2 = "
    "Sub Drainage Area 3 = " "Drainage Area = " "Runoff Coeff. = "
    "Inlet Time = "))

(setq *pfr-zero-inlet*
  '("Inlet Length = " "Inlet throat height = " "Grate Opening Area = "
    "Grate Width = " "Grate Length = " "Known Capacity = " "Gutter Width = "
    "Gutter Slope = " "Inlet Cross Slope Sw = " "Inlet Cross Slope Sx = "
    "Inlet Sag = "))

(defun pfr:nvalue (mat / cell)
  (if (and mat (setq cell (assoc (strcase mat) *pfr-nvalues*)))
    (cdr cell)
    *pfr-nvalue-default*))

;; (pfr:slope p) -> the Line Slope field
(defun pfr:slope (p / len)
  (setq len (abs (- (pfr:g 'up-sta p) (pfr:g 'dn-sta p))))
  (if (< len 1e-9)
    0.0
    (* (/ (- (pfr:g 'up-inv p) (pfr:g 'dn-inv p)) len)
       (if *pfr-slope-percent* 100.0 1.0))))

;; (pfr:deflection p pipes) -> bearing(this) - bearing(downstream); the
;;   bearing itself at the outfall (which is what the sample's line 1 shows).
(defun pfr:deflection (p pipes / d q)
  (setq d (pfr:g 'dsno p))
  (if (= d 0)
    (pfr:g 'brg p)
    (progn
      (setq q (car (vl-member-if '(lambda (x) (= (pfr:g 'no x) d)) pipes)))
      (if q (- (pfr:g 'brg p) (pfr:g 'brg q)) (pfr:g 'brg p)))))

;; (pfr:record p pipes nodes) -> the file lines for one pipe
(defun pfr:record (p pipes nodes / dn up size rise dnn upn out k)
  (setq dn   (pfr:g 'dn-xy p)
        up   (pfr:g 'up-xy p)
        dnn  (nth (pfr:g 'dn-node p) nodes)
        upn  (nth (pfr:g 'up-node p) nodes)
        size (pfr:g 'size p)
        rise (if size (/ (float size) 12.0) 0.0))
  (setq out
    (list
      (pfr:kvi "Line No. = "            (pfr:g 'no p))
      (pfr:kvs "Line ID = "             (pfr:g 'line p))
      (pfr:kvi "Downstream Line No. = " (pfr:g 'dsno p))
      (pfr:kv2 "X,Y Coord Dn = " (car dn) (cadr dn))
      (pfr:kv2 "X,Y Coord Up = " (car up) (cadr up))
      (pfr:kv  "Deflection Angle = "    (pfr:deflection p pipes))
      (pfr:kv  "Bearing = "             (pfr:g 'brg p))))
  (foreach k *pfr-zero-hydrology* (setq out (append out (list (pfr:kv0 k)))))
  (setq out
    (append out
      (list
        (pfr:kv "Line Length = " (abs (- (pfr:g 'up-sta p) (pfr:g 'dn-sta p))))
        (pfr:kv "Invert Elev Dn = " (pfr:g 'dn-inv p))
        (pfr:kv "Line Slope = "     (pfr:slope p))
        (pfr:kv "Invert Elev Up = " (pfr:g 'up-inv p))
        (pfr:kv "Rise = " rise)
        (pfr:kv "Span = " rise)
        (pfr:kv "N-Value = " (pfr:nvalue (pfr:g 'mat p)))
        (pfr:kvs "Line Type = " *pfr-line-type*)
        (pfr:kv "Junction Loss Coeff = " *pfr-junction-loss*)
        (pfr:kv "Ground / Rim Elev Dn = "
                (if (pfr:nd-rim dnn) (pfr:nd-rim dnn) 0))
        (pfr:kv "Ground / Rim Elev Up = "
                (if (pfr:nd-rim upn) (pfr:nd-rim upn) 0))
        (pfr:kv0 "Junction Type = ")
        ;; inlet N sits at the UPSTREAM end of line N, so the inlet at this
        ;; pipe's downstream end is the downstream line's -- same number
        (pfr:kvi "Downstream Inlet No. = " (pfr:g 'dsno p)))))
  (foreach k *pfr-zero-inlet* (setq out (append out (list (pfr:kv0 k)))))
  (append out
    (list (pfr:kvs "Inlet ID = " (pfr:nd-id upn))
          (pfr:kv0 "Local Inlet Depression = ")
          (pfr:kv0 "Gutter N-Value = ")
          (pfr:q "---------------------------------------"))))

;; (pfr:write file pipes nodes) -> T | nil
;;   AutoLISP text-mode output is CRLF on Windows, which is what the format
;;   wants; nothing here re-terminates a line.
(defun pfr:write (file pipes nodes / f l p)
  (if (null (setq f (open file "w")))
    (progn (prompt (strcat "\nCould not open " file " for writing.")) nil)
    (progn
      (foreach l *pfr-header*
        (write-line (pf:subst-token l "<NLINES>" (itoa (length pipes))) f))
      (write-line (pfr:q "LINE DATA =============================") f)
      (foreach p pipes
        (foreach l (pfr:record p pipes nodes) (write-line l f)))
      (foreach l *pfr-trailer* (write-line l f))
      (close f)
      T)))


;;; ==========================================================================
;;; SECTION 11  --  Candidates + the run dialog  (pfrpt_run)
;;; ==========================================================================
;;; SYSTEM-scoped: the list is the REGISTRY, not one target's structures.
;;; Only ANCHORED entries with both a .cl and an _INV .pro are offered -- a stub
;;; has no grid, so it has no rim elevations to read, and the locked decision
;;; is that stubs cannot be picked.  Everything excluded is NAMED on the
;;; command line, so a missing line is never a silent one.

;; (pfr:candidates) -> list of usable pfa:registry rows
(defun pfr:candidates ( / out r cl sf3)
  (setq out '())
  (foreach r (pfa:registry)
    (cond
      ((not (eq (caddr r) 'ANCHORED))
       (prompt (strcat "\n  Not offered: " (car r) " '" (cadr r)
                       "' is registered but not anchored -- a stub has no grid, so "
                       "no rim elevations.  Place it with PFSETUP.")))
      ((null (setq cl (pfa:entry-cl r)))
       (prompt (strcat "\n  Not offered: " (car r) " '" (cadr r)
                       "' has no .cl on record.")))
      ((null (findfile cl))
       (prompt (strcat "\n  Not offered: " (car r) " '" (cadr r)
                       "' -- .cl on record not found on disk: " cl)))
      ((null (car (setq sf3 (pfxl:src-files (car r) (cadr r)))))
       (prompt (strcat "\n  Not offered: " (car r) " '" (cadr r)
                       "' has no _INV .pro bound -- every invert comes from it.")))
      ((null (findfile (car sf3)))
       (prompt (strcat "\n  Not offered: " (car r) " '" (cadr r)
                       "' -- _INV .pro not found on disk: " (car sf3))))
      (T (setq out (cons r out)))))
  (reverse out))

;; (pfr:row r) -> the column-formatted list row
(defun pfr:row (r / sf3)
  (setq sf3 (pfxl:src-files (car r) (cadr r)))
  (strcat (pfset:pad (car r) 11)
          (pfset:pad (cadr r) 14)
          (pfset:pad (if (cadr sf3) "yes" "NO") 9)
          (if (caddr sf3) (caddr sf3) "-")))

(defun pfr:rd-sel ( / s idxs i out)
  (setq s (get_tile "rp_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select the profiles that make up ONE system.")
    (progn
      (setq idxs (read (strcat "(" s ")")) out '())
      (foreach i idxs (setq out (cons (nth i rp-rows) out)))
      (setq rp-res (reverse out))
      (done_dialog 1))))

(defun pfr:rd-all ()
  (setq rp-res rp-rows)
  (done_dialog 1))

;; (pfr:run-dialog rp-rows) -> list of chosen registry rows | nil
(defun pfr:run-dialog (rp-rows / dcl_id rp-res r result)
  (setq rp-res nil dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfrpt_run" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the export dialog.") nil)
      (progn
        (set_tile "rp_title"
                  "PFREPORT -- Hydraflow Storm Sewers (.stm) export")
        (start_list "rp_list")
        (foreach r rp-rows (add_list (pfr:row r)))
        (end_list)
        (set_tile "rp_count"
                  (strcat (itoa (length rp-rows))
                          " profile(s) ready.  Pick every line in the system."))
        (set_tile "error" "")
        (action_tile "rp_sel" "(pfr:rd-sel)")
        (action_tile "rp_all" "(pfr:rd-all)")
        (action_tile "cancel" "(done_dialog 0)")
        (action_tile "help"
          (strcat "(pfset:help \"Pick the registered profiles that form ONE "
                  "storm system -- trunk plus every branch.  They must "
                  "connect: the export stops and names the offender if the "
                  "picked set is not one network with exactly one outfall."
                  "\\n\\nPipes, structures, inverts and lengths come from each "
                  "line's bound _INV .pro; sizes from its _TOP .pro (the "
                  "Crown column above); plan coordinates from its .cl; rim "
                  "elevations are READ from the drafter-filled elevation rows "
                  "PFLABEL drew at the top of the grid.\\n\\nHydrology "
                  "(areas, runoff C, inlet times, grate geometry) exports "
                  "ZEROED -- PFTools does not hold it.  Enter it in "
                  "Hydraflow.\")"))
        (setq result (vl-catch-all-apply 'start_dialog '()))
        (unload_dialog dcl_id)
        (cond
          ((vl-catch-all-error-p result)
           (prompt (strcat "\nDialog error: "
                           (vl-catch-all-error-message result)))
           nil)
          ((= result 1) rp-res)
          (T nil))))))


;;; ==========================================================================
;;; SECTION 12  --  The engine + C:PFREPORT
;;; ==========================================================================

;; (pfr:line-table sel) -> the shared line table for membership + combined IDs
;;   Same rule as PFLABEL, through the ONE builder: same-utility-type registry
;;   lines.  Union over the distinct types in the selection, so a mixed pick
;;   still resolves every ID (it is warned about separately).
(defun pfr:line-table (sel / pairs r cl seen ty)
  (setq pairs '() seen '())
  (foreach r sel
    (if (setq cl (pfa:entry-cl r))
      (progn
        (setq pairs (cons (cons cl (cadr r)) pairs)
              ty    (pf:type-of cl))
        (if (not (member ty seen))
          (setq seen  (cons ty seen)
                pairs (append (reverse (pfa:registry-pairs cl)) pairs))))))
  (pfa:build-lines (pf:dedupe-pairs (reverse pairs))))

;; (pfr:default-path sel) -> the save dialog's starting path
(defun pfr:default-path (sel / dir)
  (setq dir (cond ((pfset:root-get)) (T (pfset:dir))))
  (strcat dir (strcase (car (car sel))) "_" (cadr (car sel))
          (if (cdr sel) "_SYSTEM" "")))

;; (pfr:run sel) -> nil    THE ENGINE.  Read-only; the .stm is the only write.
(defun pfr:run (sel / lines index inlets texts pipes r built nodes file types)
  (setq *pfr-fatal* '() *pfr-warn* '())
  ;; mixed utility types share no network -- allowed, but never silently
  (setq types '())
  (foreach r sel
    (if (not (member (car r) types)) (setq types (cons (car r) types))))
  (if (cdr types)
    (pfr:warn (strcat "the selection mixes utility types ("
                      (pf:join (reverse types) ", ")
                      ") -- confirm these really are one system.")))
  (prompt "\nBuilding the line table...")
  (setq lines  (pfr:line-table sel)
        inlets (pfa:gather-inlets)
        index  (pflabel:index-stations inlets lines)
        texts  (pfr:elev-texts))
  (prompt (strcat "\n" (itoa (length texts))
                  " elevation label row(s) in model space; "
                  (itoa (length inlets)) " structure block(s)."))
  (setq pipes '())
  (foreach r sel
    (if (setq built (pfr:line-pipes r lines index texts inlets))
      (setq pipes (append pipes built))))
  (cond
    (*pfr-fatal*
     (prompt "\n\nPFREPORT ABORTED -- a selected profile could not be read:")
     (pfr:report))
    ((null pipes)
     (prompt "\nNothing to export -- no pipe runs were found.")
     (pfr:report))
    (T
     (setq built (pfr:build-nodes pipes)
           pipes (car built)
           nodes (cdr built))
     (prompt (strcat "\n" (itoa (length pipes)) " pipe(s) across "
                     (itoa (length nodes)) " structure(s)."))
     (setq pipes (pfr:order pipes nodes))
     (cond
       ((null pipes)
        (prompt "\n\nPFREPORT ABORTED -- the picked set is not one system:")
        (pfr:report))
       (T
        (setq pipes (pfr:bearings pipes))
        (pfr:validate pipes nodes)
        (cond
          (*pfr-fatal*
           (prompt "\n\nPFREPORT ABORTED -- fix these first:")
           (pfr:report))
          (T
           (pfr:report)
           (setq file (getfiled "Export Hydraflow Storm Sewers File"
                                (pfr:default-path sel) "stm" 1))
           (cond
             ((null file) (prompt "\nExport cancelled -- no file chosen."))
             ((pfr:write file pipes nodes)
              (prompt (strcat "\n\nWrote " (itoa (length pipes))
                              " line(s) to " file))
              (prompt (strcat "\n  Rainfall is NOT PFTools data: this file "
                              "carries the reference curve \"" *pfr-idf-name*
                              "\".  Load the project's own IDF in Hydraflow "
                              "before running hydrology."))
              (prompt (strcat "\n  Drainage areas, runoff C, inlet times and "
                              "grate geometry are ZEROED by design."))))))))))
  (princ))

;; (pfr:cmd) -> nil   The command body, run under pf:run-command.
(defun pfr:cmd ( / rows sel)
  (setq rows (pfr:candidates))
  (if (null rows)
    (prompt (strcat "\nNo profile is ready to export.  PFREPORT needs an ANCHORED "
                    "registry entry with both a .cl and an _INV .pro bound -- "
                    "run PFSETUP."))
    (progn
      (setq sel (pfr:run-dialog rows))
      (if (null sel)
        (prompt "\nPFREPORT cancelled.")
        (pfr:run sel))))
  (princ))

(defun c:PFREPORT ()
  (pf:run-command "PFREPORT" nil 'pfr:cmd))

(defun c:PFR () (c:PFREPORT))

(princ "\npfreport.lsp loaded (Hydraflow .stm export).  Command: PFREPORT (alias PFR).")
(princ)
;;; ==========================================================================
;;; end of pfreport.lsp
;;; ==========================================================================
