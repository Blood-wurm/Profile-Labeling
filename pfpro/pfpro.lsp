;;; ==========================================================================
;;; pfpro.lsp  --  C:PFPROINV / C:PFPROTOP
;;;                Write a Carlson .pro from a drafted profile polyline.
;;; --------------------------------------------------------------------------
;;; Load position 7 of 12 (after pfsetup, before pflabel).
;;; May depend on: pftools-cfg, pftools-lib, pfanchor, pfsettings.
;;; Contract, invariants and open issues: pfpro/README.md -- not here.
;;;
;;; The native Carlson command asks for H/V scale, start station, start
;;; elevation, a datum pick and a polyline pick.  Every one of those numbers is
;;; already on the anchor (STA0 / DATUM / HPLOT / VPLOT, insert point = datum at
;;; the lower-left), so this command asks for the polyline and nothing else.
;;; pf:profile-x->station and pf:y->elev are the exact inverses of the transform
;;; PFLABEL draws with, which is the point: a .pro cut here cannot disagree with
;;; the grid its labels are drawn against.
;;; ==========================================================================

;;; --------------------------------------------------------------------------
;;; SECTION 1  --  The picked polyline -> WCS vertices
;;; --------------------------------------------------------------------------
;;; Every vertex written becomes an invert, and PFINVERT brackets structures on
;;; adjacent pairs (*pfi-struct-width-max*).  So a curve of ANY kind is refused
;;; rather than densified: densifying would fabricate structures that PFINVERT
;;; and PFREPORT would then find and label.  Straight segments or nothing.

;; (pfpro:refuse msg) -> nil   A refusal always prints (never pf:progress).
(defun pfpro:refuse (msg)
  (prompt (strcat "\n  REFUSED: " msg))
  nil)

;; (pfpro:verts e) -> list of (x y) | nil   nil = refused, reason printed.
(defun pfpro:verts (e / ed typ flg ext out bulge v vd)
  (setq ed  (entget e)
        typ (cdr (assoc 0 ed))
        ext (cdr (assoc 210 ed))
        flg (cdr (assoc 70 ed)))
  (if (null flg) (setq flg 0))
  (cond
    ((not (member typ '("LWPOLYLINE" "POLYLINE")))
     (pfpro:refuse (strcat "that is a " typ
                           " -- pick the POLYLINE that draws the profile.")))
    ((and ext (not (equal ext '(0.0 0.0 1.0) 1e-8)))
     (pfpro:refuse
       (strcat "that polyline has an extrusion direction -- it is not in the "
               "world XY plane, so its vertices are not station/elevation.")))
    ((/= 0 (logand flg 1))
     (pfpro:refuse
       (strcat "that polyline is CLOSED.  A profile runs once from low station "
               "to high; closed, it doubles back on itself.")))
    ((/= 0 (logand flg 2))
     (pfpro:refuse
       (strcat "that polyline is CURVE-FIT.  Every .pro vertex is an invert, "
               "and fitted vertices would invent structures.  Decurve it.")))
    ((/= 0 (logand flg 4))
     (pfpro:refuse
       (strcat "that polyline is SPLINE-FIT.  Every .pro vertex is an invert, "
               "and spline vertices would invent structures.  Decurve it.")))
    ((/= 0 (logand flg 16))
     (pfpro:refuse "that is a polygon mesh, not a profile polyline."))
    ((/= 0 (logand flg 64))
     (pfpro:refuse "that is a polyface mesh, not a profile polyline."))
    (T
     (setq out '() bulge nil)
     (cond
       ((= typ "LWPOLYLINE")
        (foreach d ed
          (cond
            ((= (car d) 10) (setq out (cons (list (cadr d) (caddr d)) out)))
            ((and (= (car d) 42) (not (equal (cdr d) 0.0 1e-8)))
             (setq bulge T)))))
       (T                                   ; heavy POLYLINE: walk its VERTEXes
        (setq v (entnext e))
        (while (and v (setq vd (entget v)) (= (cdr (assoc 0 vd)) "VERTEX"))
          (if (and (assoc 42 vd) (not (equal (cdr (assoc 42 vd)) 0.0 1e-8)))
            (setq bulge T))
          (setq out (cons (pf:pt2 (cdr (assoc 10 vd))) out)
                v   (entnext v)))))
     (setq out (reverse out))
     (cond
       (bulge
        (pfpro:refuse
          (strcat "that polyline has an ARC segment (a bulge).  A .pro is "
                  "straight runs between vertices, and each vertex is an "
                  "invert -- densifying the arc would invent structures.")))
       ((< (length out) 2)
        (pfpro:refuse "that polyline has fewer than 2 vertices."))
       (T out)))))

;; (pfpro:pick role) -> ename | nil   entsel loop; Enter / miss = cancel.
(defun pfpro:pick (role / sel done res)
  (setq done nil res nil)
  (while (not done)
    (setq sel (entsel (strcat "\nSelect polyline to write " role
                              " profile from: (Enter to cancel): ")))
    (if (null sel)
      (setq done T)
      (setq res (car sel) done T)))
  res)


;;; --------------------------------------------------------------------------
;;; SECTION 2  --  Which grid does that polyline belong to?
;;; --------------------------------------------------------------------------
;;; ONE PICK, so the anchor resolves from the pick itself: the grid whose BOX is
;;; nearest the polyline's LEFTMOST ENDPOINT.  Distance to the box, not to the
;;; insert -- zero when the endpoint is inside the grid, growing with how far
;;; outside it is.  There is no directional rule and nothing to fail.
;;;
;;; Distance to the INSERT looks equivalent and is not.  The insert is a CORNER,
;;; so on the normal stacked sheet -- grids at (0,0) and (0,300) -- a polyline
;;; drawn high in the lower grid with its left end at (20,240) is 240.8 from its
;;; own insert and 63.2 from the grid above, and the wrong grid wins outright.
;;; That is what the old at-or-below-left guard was compensating for; the box
;;; makes the guard unnecessary instead of necessary.
;;;
;;; Extents come from pfa:extents (WIDTH/HEIGHT attributes).  A missing extent
;;; leaves that side of the box UNBOUNDED rather than refusing, so a pre-icon
;;; anchor with no WIDTH still resolves -- on the side it does know.
;;;
;;; COPIES are candidates, then refused if one WINS.  pfa:all-anchors does not
;;; filter them and pfa:find-anchor does, so skipping them here would hand a
;;; polyline drawn inside a copy to whatever real grid is next-nearest, and
;;; pfa:files-put would bind a .pro to a grid it was never cut from.

;; (pfpro:left-end pts) -> (x y)   the ENDPOINT with the lower X.
;;   Endpoints, not the whole vertex list: the polyline may be drawn in either
;;   direction, and pfpro:orient has not run yet -- it needs the xform that this
;;   function is on the way to finding.
(defun pfpro:left-end (pts / a b)
  (setq a (car pts) b (last pts))
  (if (<= (car a) (car b)) a b))

;; (pfpro:box-dist p ins ext) -> real >= 0   distance from p to the grid box.
;;   0 when p is inside it.  ins IS the lower-left (leftx, basey), so the box is
;;   x0..x0+WIDTH by y0..y0+HEIGHT.  A nil extent leaves that side unbounded.
(defun pfpro:box-dist (p ins ext / x0 y0 x1 y1 dx dy)
  (setq x0 (car  ins)
        y0 (cadr ins)
        x1 (if (car  ext) (+ x0 (car  ext)))
        y1 (if (cadr ext) (+ y0 (cadr ext)))
        dx (cond ((< (car p) x0)              (- x0 (car p)))
                 ((and x1 (> (car p) x1))     (- (car p) x1))
                 (T 0.0))
        dy (cond ((< (cadr p) y0)             (- y0 (cadr p)))
                 ((and y1 (> (cadr p) y1))    (- (cadr p) y1))
                 (T 0.0)))
  (sqrt (+ (* dx dx) (* dy dy))))

;; (pfpro:owner pts) -> anchor ename | nil   nil = refused, reason printed.
(defun pfpro:owner (pts / p best bestd ins d)
  (setq p     (pfpro:left-end pts)
        best  nil
        bestd nil)
  (foreach a (pfa:all-anchors)
    (if (setq ins (cdr (assoc 10 (entget a))))
      (progn
        (setq d (pfpro:box-dist p ins (pfa:extents a)))
        (if (or (null bestd) (< d bestd))
          (setq best a bestd d)))))
  (cond
    ((null best)
     (pfpro:refuse
       (strcat "there are no registered grids in this drawing, so there is no "
               "station/elevation transform to read that polyline with.  Run "
               "PFSETUP first.")))
    ((pfa:copy-p best)
     (pfpro:refuse
       (strcat "the nearest grid to that polyline is a COPIED anchor.  A copy "
               "never resolves -- its ledger is a clone -- so binding a .pro to "
               "it would write where nothing reads.  PFREMOVE the copy, then "
               "PFSETUP that grid properly.")))
    (T
     ;; Outside every grid still RESOLVES -- nearest wins, by design -- but it is
     ;; the shape of a polyline drawn beside its grid rather than in it, and the
     ;; stations that lands on disk are the ones PFINVERT reads back as truth.
     (if (> bestd 0.0)
       (prompt (strcat "\n  Warning: that polyline's left end is not inside "
                       (pfa:anchor-title best) " -- it is " (rtos bestd 2 2)
                       " outside the nearest grid.  Check STA0 and the datum "
                       "before trusting the stations.")))
     best)))


;;; --------------------------------------------------------------------------
;;; SECTION 3  --  Vertices -> (station . elevation)
;;; --------------------------------------------------------------------------
;;; Stations written are ABSOLUTE .cl stations, not offsets from the grid's
;;; start: a grid that starts at 100 carries a pipe whose first vertex is 115.59.
;;; That is what pf:xf-sta0 + pf:profile-x->station already produce.
;;;
;;; Order is NOT sorted into place.  A polyline drawn right-to-left is normal and
;;; is reversed; a polyline that genuinely backtracks is a drafting fault, and
;;; sorting it would silently launder that fault into a plausible .pro.

;; (pfpro:map-verts pts xf) -> ((sta . elev) ...) in drawn order
(defun pfpro:map-verts (pts xf)
  (mapcar '(lambda (p)
             (cons (pf:profile-x->station (car  p) xf)
                   (pf:y->elev           (cadr p) xf)))
          pts))

;; (pfpro:same-written a b) -> T when both print alike in the file.
;;   pfpro:write is 4 decimals, so two values that print alike ARE one value to
;;   everything that reads the .pro back.  That makes the FILE the arbiter of
;;   "same station" instead of an invented epsilon.
(defun pfpro:same-written (a b)
  (= (rtos a 2 4) (rtos b 2 4)))

;; (pfpro:ptstr p) -> "(1234.500, 789.250)"   drawing coordinates, for refusals.
(defun pfpro:ptstr (p)
  (strcat "(" (rtos (car p) 2 3) ", " (rtos (cadr p) 2 3) ")"))

;; (pfpro:orient verts pts) -> verts ascending by station | nil (refused)
;;   pts is the DRAWN vertex list, index-aligned with verts (map-verts is a
;;   mapcar), so a refusal can name the offending vertex where the drafter can
;;   find it.  A station cannot do that alone: the two vertices of a vertical
;;   segment print the SAME station.
;;
;;   Three faults sit at one station and the written precision separates them:
;;     same station + same elevation -- the two output lines would be identical,
;;       so the vertex carries nothing.  Collapsed and reported, never refused.
;;       Left in, its zero gap reads as a STRUCTURE to pfr:groups and PFINVERT.
;;     same station + different elevation -- a real vertical segment.  Refused:
;;       a .pro holds one elevation per station.
;;     a step back smaller than the written precision -- invisible in the file,
;;       so it is not a backtrack and does not decide direction.  Comparing with
;;       a bare <= made every such step a fault, and they are unfindable in the
;;       drawing.
(defun pfpro:orient (verts pts / vs ps v vp p pp pidx i keep dir d dups dupsta
                     vbad bad nasc ndesc out)
  (setq p     (car verts)
        pp    (car pts)
        pidx  1
        keep  (list p)
        vs    (cdr verts)
        ps    (cdr pts)
        i     1
        dups  0
        nasc  0
        ndesc 0)
  (while (and vs (null vbad))
    (setq v  (car vs)
          vp (car ps)
          i  (1+ i))
    (cond
      ((pfpro:same-written (car v) (car p))
       (if (pfpro:same-written (cdr v) (cdr p))
         (setq dups   (1+ dups)
               dupsta (if dupsta dupsta (car v)))
         (setq vbad (list pidx pp i vp (car v)))))
      (T
       (setq d (if (> (car v) (car p)) 1 -1))
       (if (null dir)
         (setq dir d)
         (if (and (/= d dir) (null bad))
           (setq bad (list pidx (car p) i (car v)))))
       (if (= d 1) (setq nasc (1+ nasc)) (setq ndesc (1+ ndesc)))
       (setq keep (cons v keep)
             p    v
             pp   vp
             pidx i)))
    (setq vs (cdr vs)
          ps (cdr ps)))
  (setq out (reverse keep))
  (cond
    (vbad
     (pfpro:refuse
       (strcat "vertices " (itoa (nth 0 vbad)) " and " (itoa (nth 2 vbad))
               " are both at station " (pf:fmt-station (nth 4 vbad))
               " -- a vertical segment.  They are at "
               (pfpro:ptstr (nth 1 vbad)) " and " (pfpro:ptstr (nth 3 vbad))
               ".  A .pro holds one elevation per station.  Draw a structure "
               "drop as the short run between its two vertices: any gap up to "
               (rtos *pfi-struct-width-max* 2 0)
               " ft still reads as ONE structure.")))
    ((and (> nasc 0) (> ndesc 0))
     (pfpro:refuse
       (strcat "that polyline runs back along the station axis: vertex "
               (itoa (nth 0 bad)) " is at " (pf:fmt-station (nth 1 bad))
               " and vertex " (itoa (nth 2 bad)) " goes back to "
               (pf:fmt-station (nth 3 bad))
               ".  Fix the polyline; sorting it here would launder a drafting "
               "fault into a plausible .pro.")))
    ((< (length out) 2)
     (pfpro:refuse
       (strcat "every vertex on that polyline is at the same point -- after "
               "dropping " (itoa dups)
               " duplicate vertices there is nothing left to write.")))
    (T
     (if (> dups 0)
       (prompt (strcat "\n  Note: collapsed " (itoa dups)
                       (if (= dups 1)
                         " duplicate vertex at "
                         " duplicate vertices, first at ")
                       (pf:fmt-station dupsta)
                       " -- a zero station gap would read as a structure.")))
     (if (= dir -1) (reverse out) out))))

;; (pfpro:check-range verts clfile) -> T | nil   nil = refused.
;;   The one gate that guards against a wrong STA0 on the anchor.  A wrong STA0
;;   only misplaces LABELS, which are redrawable; here it bakes wrong stations
;;   onto disk that PFINVERT and PFREPORT then read back as truth.
(defun pfpro:check-range (verts clfile / rng s0 s1 p0 p1)
  (setq p0 (car (car verts))
        p1 (car (last verts))
        rng (pf:cl-range clfile))
  (cond
    ((null rng)
     (prompt (strcat "\n  Warning: could not read the station range of "
                     (vl-filename-base clfile)
                     ".cl -- writing without the range check."))
     T)
    (T
     (setq s0 (car rng) s1 (cadr rng))
     (cond
       ((or (< p1 s0) (> p0 s1))
        (pfpro:refuse
          (strcat "the mapped stations (" (pf:fmt-station p0) " to "
                  (pf:fmt-station p1) ") fall entirely OUTSIDE "
                  (vl-filename-base clfile) ".cl (" (pf:fmt-station s0)
                  " to " (pf:fmt-station s1)
                  ").  Check STA0 on the anchor -- re-run PFSETUP in Edit mode.")))
       ((or (< p0 s0) (> p1 s1))
        (prompt (strcat "\n  Warning: the profile runs "
                        (pf:fmt-station p0) " to " (pf:fmt-station p1)
                        ", past the ends of " (vl-filename-base clfile)
                        ".cl (" (pf:fmt-station s0) " to "
                        (pf:fmt-station s1) ").  Writing anyway."))
        T)
       (T T)))))


;;; --------------------------------------------------------------------------
;;; SECTION 4  --  Name and destination
;;; --------------------------------------------------------------------------
;;; The name is built from the .cl BASENAME -- never invented, and never taken
;;; from a source that could disagree with the alignment on disk.  That is what
;;; makes the role suffix match *pf-pro-roles* by construction, which is what
;;; pf:parse-pro-name and PFSETUP's AUTO binding depend on.

;; (pfpro:filename clfile role) -> "STORM_BA_INV.pro"
;;   TYPE IS UPCASED.  *pf-types* are "STORM" / "SANITARY" / "WATER" and a .pro
;;   carries the type that way, even though the alignment on disk is spelled
;;   Storm_BA.cl.  The NAME segment is taken verbatim from the .cl, so a line
;;   keeps whatever the alignment file already calls it.
;;   Casing is cosmetic to every consumer, in both directions: pfs:pro-lookup
;;   compares strcase-to-strcase, so AUTO / Refresh pair the file whatever the
;;   spelling, and pf:parse-pro-name upcases before it splits off the role.
(defun pfpro:filename (clfile role / base pos)
  (setq base (vl-filename-base clfile)
        pos  (vl-string-search "_" base))
  (strcat (pf:type-of clfile)                  ; before the first "_", upcased
          (if pos (substr base (1+ pos)) "")   ; "_BA", as the .cl spells it
          "_" (strcase role) ".pro"))

;; (pfpro:dest-dir) -> "...\CivilSurvey\" | nil
;;   The firm-standard .pro folder ALWAYS wins (settled 2026-07-29): it never
;;   follows an already-bound sibling, because a sibling bound from a non-standard
;;   location would quietly pull every later cut out of the project template.
(defun pfpro:dest-dir ( / d)
  (if (setq d (pfset:get-company-dir "pro"))
    (strcat (vl-string-right-trim "\\/" d) "\\")))


;;; --------------------------------------------------------------------------
;;; SECTION 5  --  The writer
;;; --------------------------------------------------------------------------
;;; Format verified against a Carlson-written .pro:
;;;
;;;   115.5906,749.2500,0.0     <- sta,elev,vertical-curve-length; 4 decimals
;;;   ...                          on both, col 3 always 0.0 for a pipe run
;;;   0,0,0                     <- terminator, BARE zeros (not 0.0000)
;;;   1                         <- trailer, then EOF
;;;
;;; No header row.  This is exactly the grammar pf:pro-verts reads, so anything
;;; written here round-trips through the suite's own reader.
;;; rtos mode 2 is passed explicitly so an Architectural/Fractional drawing
;;; cannot corrupt the output (the same reason PFSETUP pins distof mode 2).

;; (pfpro:write file verts) -> T | nil
(defun pfpro:write (file verts / f)
  (if (null (setq f (open file "w")))
    (progn
      (prompt (strcat "\n  Could not open " file " for writing."))
      nil)
    (progn
      (foreach v verts
        (write-line (strcat (rtos (car v) 2 4) ","
                            (rtos (cdr v) 2 4) ",0.0")
                    f))
      (write-line "0,0,0" f)
      (write-line "1" f)
      (close f)
      T)))


;;; --------------------------------------------------------------------------
;;; SECTION 6  --  Bind the result to the anchor
;;; --------------------------------------------------------------------------

;; (pfpro:bind anchor role path) -> nil
;;   Fills ONE slot of the FILES record and preserves the other four (the
;;   sibling .pro, the TIN pair, the material) -- same shape as PFSETUP's late
;;   .pro binding.  Caller holds the undo group.
;;   No cache to clear: pf:checksum-file re-keys on systime+size and
;;   *pf-proverts-cache* re-keys on the checksum, so both self-invalidate on the
;;   rewrite of an already-bound path.
(defun pfpro:bind (anchor role path / files inv top tine tind mat invck topck ck)
  (setq files (pfa:files-get anchor)
        inv   (cdr (assoc 1   files))
        top   (cdr (assoc 2   files))
        tine  (cdr (assoc 3   files))
        tind  (cdr (assoc 4   files))
        mat   (cdr (assoc 5   files))
        invck (cdr (assoc 300 files))
        topck (cdr (assoc 301 files))
        ck    (pf:checksum-file path))
  (if (= (strcase role) "INV")
    (setq inv path invck ck)
    (setq top path topck ck))
  (pfa:files-put anchor inv invck top topck tine tind mat)
  (princ))


;;; --------------------------------------------------------------------------
;;; SECTION 7  --  The command
;;; --------------------------------------------------------------------------

;; (pfpro:run role) -> nil   role is "INV" | "TOP" (a member of *pf-pro-roles*)
(defun pfpro:run (role / e pts anchor xf clfile verts name dir file exists ok)
  (cond
    ((null (setq e (pfpro:pick role)))
     (prompt (strcat "\nPFPRO" role " cancelled.")))
    ((null (setq pts (pfpro:verts e))))            ; refusal already printed
    ((null (setq anchor (pfpro:owner pts))))       ; refusal already printed
    ((null (setq xf (pfa:anchor->xform anchor)))
     (prompt (strcat "\n  REFUSED: " (pfa:anchor-title anchor)
                     " has an unreadable transform (STA0 / DATUM / HPLOT / "
                     "VPLOT).  Re-run PFSETUP in Edit mode.")))
    ((null (setq clfile (pf:xf-get 'clfile xf)))
     (prompt (strcat "\n  REFUSED: " (pfa:anchor-title anchor)
                     " has no .cl bound, and the .pro name is derived from it.  "
                     "Bind the centerline in PFSETUP first.")))
    ((null (setq verts (pfpro:orient (pfpro:map-verts pts xf) pts))))
    ((null (pfpro:check-range verts clfile)))
    (T
     (prompt (strcat "\n  Grid:  " (pfa:anchor-title anchor)
                     "   (" (vl-filename-base clfile) ".cl, STA0 "
                     (pf:fmt-station (pf:xf-sta0 xf)) ", datum "
                     (rtos (pf:xf-datum xf) 2 2) ", H:"
                     (rtos (pf:xf-hplot xf) 2 0) " V:"
                     (rtos (pf:xf-vplot xf) 2 0) ")"))
     (prompt (strcat "\n  " (itoa (length verts)) " vertices, "
                     (pf:fmt-station (car (car verts))) " to "
                     (pf:fmt-station (car (last verts))) ", elev "
                     (rtos (cdr (car verts)) 2 2) " to "
                     (rtos (cdr (last verts)) 2 2) "."))
     (setq name (pfpro:filename clfile role)
           dir  (pfpro:dest-dir))
     (if (null dir)
       ;; No project root and no session directory -- ask, pre-filled.  getfiled
       ;; runs its own overwrite confirmation, so ours is skipped on this path.
       (setq file (getfiled (strcat "Write " role " profile") name "pro" 1)
             ok   (if file T nil))
       (progn
         (setq file   (strcat dir name)
               exists (findfile file)
               ok     (if exists
                        (pfset:confirm
                          (strcat "Overwrite " name "?")
                          (list (strcat "Already in " dir)
                                "Anything reading it (PFINVERT, PFXLABEL,"
                                "PFREPORT) will see the new inverts."))
                        T))))
     (cond
       ((null file) (prompt (strcat "\nPFPRO" role " cancelled -- no file chosen.")))
       ((null ok)   (prompt (strcat "\nPFPRO" role " cancelled -- "
                                    name " left as it was.")))
       ((null (pfpro:write file verts)))         ; message already printed
       (T
        (prompt (strcat "\n\nWrote " (itoa (length verts)) " vertices to " file))
        ;; The file is on disk either way; only the BINDING is a drawing write,
        ;; so the undo group opens here and nowhere earlier.
        ;; It borrows *pfs-undo-open* deliberately: pf:group-open-p checks a
        ;; FIXED list of flags, so a flag of our own would be invisible to
        ;; pf:run-error and an Esc would leak an open group.  PFPRO and PFSETUP
        ;; cannot run at once.  (Same call PFINDEX makes, pfanchor SECTION 8.)
        (pf:undo-begin '*pfs-undo-open*)
        (pfpro:bind anchor role file)
        (pf:undo-end '*pfs-undo-open*)
        (prompt (strcat "\n  Bound to " (pfa:anchor-title anchor) " as its "
                        role " profile.  (One U reverses the binding, not the "
                        "file.)"))))))
  (princ))

(defun pfpro:cmd-inv ( / ) (pfpro:run "INV"))
(defun pfpro:cmd-top ( / ) (pfpro:run "TOP"))

(defun c:PFPROINV ()
  (pf:run-command "PFPROINV" nil 'pfpro:cmd-inv))

(defun c:PFPROTOP ()
  (pf:run-command "PFPROTOP" nil 'pfpro:cmd-top))

(princ "\npfpro.lsp loaded (.pro from a profile polyline).  Commands: PFPROINV, PFPROTOP.")
(princ)
;;; ==========================================================================
;;; end of pfpro.lsp
;;; ==========================================================================
