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
    (setq sel (entsel (strcat "\nPick the polyline drawing the " role
                              " profile (Enter to cancel): ")))
    (if (null sel)
      (setq done T)
      (setq res (car sel) done T)))
  res)


;;; --------------------------------------------------------------------------
;;; SECTION 2  --  Which grid does that polyline belong to?
;;; --------------------------------------------------------------------------
;;; Jake asked for ONE pick, so the anchor resolves from the pick itself:
;;; the nearest anchor to the polyline's LEFTMOST ENDPOINT.  No bounding box and
;;; no containment test -- which also means pfa:extents is never consulted, so a
;;; legacy anchor with no WIDTH recorded resolves exactly like any other.
;;;
;;; Two guards ride along, and neither costs a prompt:
;;;
;;;   1. The anchor's insert must be at or below-left of that endpoint.  The
;;;      insert IS the grid's lower-left (leftx, basey), and a profile always
;;;      draws up and to the right of it (pf:elev->profile-y from the datum,
;;;      pf:station->profile-x from sta0).  Without this, stacked grids -- the
;;;      normal sheet layout -- steal each other's polylines: a pipe drawn high
;;;      in its own grid is nearer to the insert of the grid ABOVE it than to
;;;      its own.  Delete the two <= tests to get pure nearest-insert.
;;;   2. COPIES are excluded, the way pfa:find-anchor excludes them and
;;;      pfa:all-anchors does not.  A copy sits elsewhere in the drawing and
;;;      would win outright for a polyline drawn inside it, and pfa:files-put
;;;      would then bind into a cloned ledger nothing else resolves.

;; (pfpro:left-end pts) -> (x y)   the ENDPOINT with the lower X.
;;   Endpoints, not the whole vertex list: the polyline may be drawn in either
;;   direction, and pfpro:orient has not run yet -- it needs the xform that this
;;   function is on the way to finding.
(defun pfpro:left-end (pts / a b)
  (setq a (car pts) b (last pts))
  (if (<= (car a) (car b)) a b))

;; (pfpro:owner pts) -> anchor ename | nil   nil = refused, reason printed.
(defun pfpro:owner (pts / p px py best bestd copies any ins d)
  (setq p      (pfpro:left-end pts)
        px     (car  p)
        py     (cadr p)
        best   nil
        bestd  nil
        copies 0
        any    nil)
  (foreach a (pfa:all-anchors)
    (setq any T
          ins (cdr (assoc 10 (entget a))))
    (if (and ins (<= (car ins) px) (<= (cadr ins) py))
      (if (pfa:copy-p a)
        (setq copies (1+ copies))
        (progn
          (setq d (distance (list px py) (list (car ins) (cadr ins))))
          (if (or (null bestd) (< d bestd))
            (setq best a bestd d))))))
  (cond
    (best best)
    ((> copies 0)
     (pfpro:refuse
       (strcat "the nearest grid to that polyline is a COPIED anchor.  A copy "
               "never resolves -- its ledger is a clone -- so binding a .pro to "
               "it would write where nothing reads.  PFREMOVE the copy, then "
               "PFSETUP that grid properly.")))
    ((null any)
     (pfpro:refuse
       (strcat "there are no registered grids in this drawing, so there is no "
               "station/elevation transform to read that polyline with.  Run "
               "PFSETUP first.")))
    (T
     (pfpro:refuse
       (strcat "no registered grid lies below-left of that polyline's left end, "
               "so there is no station/elevation transform to read it with.  "
               "Check that it was drawn inside its grid, not beside it.")))))


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

;; (pfpro:orient verts) -> verts ascending by station | nil (refused)
(defun pfpro:orient (verts / asc desc prev bad)
  (setq asc T desc T prev (car verts))
  (foreach v (cdr verts)
    (if (<= (car v) (car prev)) (setq asc  nil))
    (if (>= (car v) (car prev)) (setq desc nil))
    (setq prev v))
  (cond
    (asc  verts)
    (desc (reverse verts))
    (T
     ;; Name the first offending vertex -- "it backtracks" is not actionable.
     (setq prev (car verts) bad nil)
     (foreach v (cdr verts)
       (if (and (null bad) (<= (car v) (car prev)))
         (setq bad (list (car prev) (car v))))
       (setq prev v))
     (pfpro:refuse
       (if (equal (car bad) (cadr bad) 1e-6)
         (strcat "that polyline has two vertices at station "
                 (pf:fmt-station (car bad))
                 " -- a vertical segment.  A .pro holds one elevation per "
                 "station; a structure drop is drawn as the short run between "
                 "its two vertices, never as a vertical drop.")
         (strcat "that polyline does not run monotonically along the station "
                 "axis -- it goes from " (pf:fmt-station (car bad))
                 " back to " (pf:fmt-station (cadr bad))
                 ".  Fix the polyline; sorting it here would launder a "
                 "drafting fault into a plausible .pro."))))))

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
;;; Format verified against a Carlson-written .pro (Jake, 2026-07-29):
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
    ((null (setq verts (pfpro:orient (pfpro:map-verts pts xf)))))
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
