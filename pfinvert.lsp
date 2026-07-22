;;; ==========================================================================
;;; pfinvert.lsp  --  C:PFINVERT : invert labels at structures  (V4)
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings, pfsetup,
;;; pflabel, pfxlabel loaded first (reuses pflabel's structure walk and
;;; pfxlabel's registry file resolution -- depend-only-upward holds).
;;;
;;; THE COMMAND SPLIT (locked): PFLABEL owns top-of-grid text; PFINVERT owns
;;; EVERYTHING AT PIPE ELEVATION.  At each structure on the primary line:
;;;
;;;   PRIMARY   in/out inverts, TEXT ONLY -- the primary pipe is already
;;;             drawn longitudinally as its .pro linework.  I.O / I.I are the
;;;             two ADJACENT _INV.pro VERTICES that meet at the structure
;;;             (pfi:invert-bracket over pf:pro-verts): each vertex IS an
;;;             invert, so the reading is exact.  The LOWER of the pair is
;;;             downstream (self-determining) -> I.O.  A polyline endpoint is a
;;;             terminus -> ONE invert (lower end I.O, higher end I.I).  Each
;;;             row carries its pipe size: "I.O. 755.83 (8")".
;;;
;;;   LATERALS  every OTHER registry line the structure sits on: a bare
;;;             pipe block at TRUE elevation on the station X (non-present
;;;             pipe -- same rendering rule as crossings) plus an "I.I <elev>
;;;             (NN")" text row.  No size/material text at the block; line
;;;             identity is already on the structure's top label.
;;;
;;;   TEXT      ALL rows share ONE base Y = lowest invert present MINUS
;;;             (*pfi-invert-offset-factor* x text height) -- 16 units at H:50,
;;;             scaling with text like every other label gap.  COLUMNS fan
;;;             left/right across the station X: I.O. downstream-left, shared
;;;             lateral I.I.(s) centred, primary I.I. upstream-right.  Columns,
;;;             not true-elevation rows -- that keeps a 0.10' drop from
;;;             colliding two callouts.  Justification MR: right-justified
;;;             reading up GROWS DOWNWARD, so the stack hangs below base Y.
;;;             The leftmost structure's stack shifts right to clear the grid's
;;;             elevation-axis labels.  No leader -- the station line marks X.
;;;
;;; LAYER RULE, PASS LEDGER, UNDO: identical to PFLABEL.  Derived
;;; <TYPE>-TEXT_P handle-tracked (PASS "INVERT", All replaces by handle);
;;; "Use current layer" -> CLAYER, fire-and-forget (PASS "INVERT-CLAYER",
;;; no handles).  One undo group per run.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfinvert-undo-open*)) (setq *pfinvert-undo-open* nil))
(if (not (boundp '*pfinvert-run-ents*)) (setq *pfinvert-run-ents* '()))

(setq *pfi-pass-name* "INVERT")


;;; ==========================================================================
;;; SECTION 1  --  Error handling
;;; ==========================================================================

(defun pfinvert:*error* (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFINVERT error: " msg)))
  (pfa:undo-cleanup)                ; closes ANY pf group, incl. a nested one
  (setq *error* *pfinvert-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 2  --  The vertex bracket  (the isolated helper)
;;; ==========================================================================
;;; EXACT-VERTEX body.  Each .pro vertex IS an invert (the profile is authored
;;; from the polyline endpoints), so a structure's in/out inverts are simply the
;;; two ADJACENT vertices that meet at it -- no sampling, no grade tolerance, no
;;; half-step bias.  The contract (pfi:invert-bracket verts sta -> (io ii) | nil)
;;; is what SECTION 4 consumes; io / ii are each (edge-sta . elev) or nil.
;;; Vertices come from pf:pro-verts (file-parsed, cached).

;; (pfi:nearest-vert verts sta) -> index of the vertex closest in station to sta
(defun pfi:nearest-vert (verts sta / i bi bd d)
  (setq i 0 bi 0 bd nil)
  (foreach v verts
    (setq d (abs (- (car v) sta)))
    (if (or (null bd) (< d bd)) (setq bd d bi i))
    (setq i (1+ i)))
  bi)

;; (pfi:invert-bracket verts sta) -> (io ii) | nil
;;   io = downstream invert (LOWER elev), ii = upstream invert (higher) -- each
;;   (edge-sta . elev) or nil; downstream is self-determining from elevation.
;;   Two adjacent vertices a structure-width apart form a normal structure (both
;;   set).  A polyline ENDPOINT whose only neighbour is a full pipe-run away is a
;;   terminus (one invert): the LOWER-elevation profile end is downstream -> I.O
;;   only, the higher -> I.I only.  nil when there are no vertices.
(defun pfi:invert-bracket (verts sta / n i cur prev nxt gp gn partner a b
                            io ii other)
  (if (null verts)
    nil
    (progn
      (setq n    (length verts)
            i    (pfi:nearest-vert verts sta)
            cur  (nth i verts)
            prev (if (> i 0)      (nth (1- i) verts))
            nxt  (if (< i (1- n)) (nth (1+ i) verts))
            gp   (if prev (- (car cur) (car prev)))
            gn   (if nxt  (- (car nxt) (car cur))))
      (cond
        ;; interior vertex: pair with the nearer neighbour (its structure edge)
        ((and prev nxt) (setq partner (if (<= gp gn) prev nxt)))
        ;; endpoint with a NARROW neighbour = a structure at the very .pro end
        ((and prev (<= gp *pfi-struct-width-max*)) (setq partner prev))
        ((and nxt  (<= gn *pfi-struct-width-max*)) (setq partner nxt))
        ;; endpoint whose only neighbour is a pipe-run away = terminus (single)
        (T (setq partner nil)))
      (if partner
        (progn                            ; two inverts: lower = io, higher = ii
          (setq a cur b partner)
          (if (<= (cdr a) (cdr b)) (setq io a ii b) (setq io b ii a))
          (list io ii))
        (progn                            ; terminus: classify by elevation
          (setq other (if (= i 0) (last verts) (car verts)))
          (if (<= (cdr cur) (cdr other))
            (list cur nil)                ; lower profile end -> I.O only
            (list nil cur)))))))          ; higher profile end -> I.I only


;;; ==========================================================================
;;; SECTION 3  --  Run setup  (anchor -> context; reuses pflabel's machinery)
;;; ==========================================================================

;; (pfi:setup anchor mode prelines preinlets) -> context alist | nil
;;   Same record checks as pflabel:setup, PLUS the _INV .pro is FATAL when
;;   missing -- every elevation this command draws comes from it.  The mode
;;   ("All"/"Sel") was chosen in the shared run dialog; prelines/preinlets are
;;   that dialog's already-built line table + inlets, reused when passed.
(defun pfi:setup (anchor mode prelines preinlets
                  / xf cl proinv s style clayer-p layer prim pairs
                    lines primary inlets)
  (setq xf (pfa:anchor->xform anchor))
  (cond
    ((null xf)
     (prompt "\nAnchor attributes unreadable -- run PFSETUP on this grid.")
     nil)
    ((null (setq cl (pf:xf-get 'clfile xf)))
     (prompt "\nNo .cl on record for this anchor -- run PFSETUP (edit) to bind one.")
     nil)
    ((null (findfile cl))
     (prompt (strcat "\n.cl on record not found on disk: " cl
                     "\nRe-bind it with PFSETUP (edit)."))
     nil)
    ((null (setq proinv (pf:xf-get 'pro-inv xf)))
     (prompt "\nNo _INV .pro bound on this record -- run PFSETUP (edit).  Every invert comes from it.")
     nil)
    ((null (findfile proinv))
     (prompt (strcat "\n_INV .pro on record not found on disk: " proinv
                     "\nRe-bind it with PFSETUP (edit)."))
     nil)
    (T
     (setq s     (pfset:settings)
           style (pfset:active-style))
     (if (= style "")
       (progn (prompt "\nNo usable text style in this drawing -- aborting.") nil)
       (progn
         ;; layer per the settings toggle (same rule as PFLABEL)
         (setq clayer-p (= (cdr (assoc "use_clayer" s)) "1")
               layer    (if clayer-p
                          (getvar "CLAYER")
                          (strcat (strcase (pf:xf-get 'type xf))
                                  *pfx-text-layer-suffix*)))
         (if (not clayer-p) (pfd:ensure-layer layer nil))
         (prompt (strcat "\nLayer " layer
                         (if clayer-p " (current)" "")
                         ", style " style "."))
         ;; line table: primary = the record's .cl; secondaries = registry.
         ;; Reuse the dialog's build when handed one; else build it here.
         (setq prim    (cons cl (pf:xf-get 'name xf))
               lines   (if prelines
                         prelines
                         (progn
                           (setq pairs (pf:dedupe-pairs
                                         (cons prim (pflabel:registry-pairs cl))))
                           (pflabel:build-lines pairs)))
               primary (cdr prim))
         (cond
           ((null lines)
            (prompt "\nNo readable centerlines -- aborting.") nil)
           ((null (pflabel:line-loaded-p primary lines))
            (prompt (strcat "\nPrimary line '" primary
                            "' failed to load -- aborting."))
            nil)
           (T
            (setq inlets (if preinlets preinlets (pflabel:gather-inlets)))
            (list (cons 'xform    xf)
                  (cons 'anchor   anchor)
                  (cons 'lines    lines)
                  (cons 'primary  primary)
                  (cons 'proinv   proinv)
                  (cons 'protop   (pf:xf-get 'pro-top xf))
                  (cons 'mode     mode)
                  (cons 'inlets   inlets)
                  (cons 'clayer-p clayer-p)
                  (cons 'style    style)
                  (cons 'layer    layer)
                  (cons 'ht       (pf:text-height (pf:xf-hplot xf)))))))))))


;;; ==========================================================================
;;; SECTION 4  --  Per-structure labeling
;;; ==========================================================================

;; (pfi:lateral-info hit lines) -> (elev size clfile) | (nil . reason)
;;   hit = (name station) on a NON-primary line.  Resolves that line's
;;   _INV/_TOP .pro through the registry (anchor first, stub second) and
;;   reads invert + nominal size at ITS station.
(defun pfi:lateral-info (hit lines / entry clfile ty nm sf3 pipe)
  (setq entry  (pflabel:line-loaded-p (car hit) lines)
        clfile (if entry (car entry)))
  (cond
    ((null clfile) (cons nil "no line-table entry"))
    (T
     (setq ty  (pf:type-of clfile)
           nm  (pf:name-of clfile)
           sf3 (pfxl:src-files ty nm))
     (cond
       ((null sf3)       (cons nil "not registered"))
       ((null (car sf3)) (cons nil "no _INV .pro bound"))
       ((null (setq pipe (pf:pipe-at (car sf3) (cadr sf3) (cadr hit))))
        (cons nil "invert unreadable (profile z)"))
       (T (list (car pipe) (cdr pipe) clfile))))))

;; (pfi:endpoint-hits pt lines seen) -> extra (name station) for same-type
;;   lines that TERMINATE at this structure -- an endpoint within
;;   *pfi-junction-tol* of the point -- and are not already in `seen`.  The
;;   on-line membership (pf:lines-at-point) is tuned for pass-through hits, so a
;;   lateral joining at its own END (common at the primary's downstream
;;   structure) slips past it; this recovers those junctions.  The station used
;;   is the line's near range-end (lo for its start, hi for its end).
(defun pfi:endpoint-hits (pt lines seen / out pt2d e nm verts lo hi ends p0 pn)
  (setq out  '()
        pt2d (list (car pt) (cadr pt)))         ; drop z: 2D plan distance only
  (foreach e lines
    (setq nm    (cadr e)
          verts (nth 4 e)
          lo    (nth 2 e)
          hi    (nth 3 e))
    (if (not (member nm seen))
      (progn
        (if (and verts (cdr verts))
          (setq p0 (car verts) pn (last verts))    ; drawn twin endpoints
          (if (setq ends (pf:cl-endpoints (car e))) ; stub/no twin: authored ends
            (setq p0 (car ends) pn (cadr ends))
            (setq p0 nil pn nil)))
        (cond
          ((and p0 (<= (distance pt2d (list (car p0) (cadr p0)))
                       *pfi-junction-tol*))
           (setq out (cons (list nm lo) out)))
          ((and pn (<= (distance pt2d (list (car pn) (cadr pn)))
                       *pfi-junction-tol*))
           (setq out (cons (list nm hi) out)))))))
  out)

;; (pfi:inv-row prefix elev size) -> "PREFIX elev (NN\")" | "PREFIX elev"
;;   size nil (no _TOP .pro / unreadable) omits the parenthetical.
(defun pfi:inv-row (prefix elev size)
  (strcat prefix " " (rtos elev 2 2)
          (if size (strcat " (" (itoa size) "\")") "")))

;; (pfi:prim-size proinv protop sta) -> nominal size | nil   (pipe at an edge)
(defun pfi:prim-size (proinv protop sta / pipe)
  (if (setq pipe (pf:pipe-at proinv protop sta)) (cdr pipe)))

;; (pfi:process-structure block-ename context) -> nil
;;   Draws the invert column + lateral blocks for one structure.
(defun pfi:process-structure (block-ename context
                              / ed pt name xf primary hits primhit others
                                proinv protop verts bracket io ii rows elevs
                                lat linfo x drawX baseY offset gapn ht style
                                layer res en lats first-sta target shift)
  (setq ed      (entget block-ename)
        pt      (cdr (assoc 10 ed))
        name    (cdr (assoc 2 ed))
        xf      (cdr (assoc 'xform context))
        primary (cdr (assoc 'primary context))
        proinv  (cdr (assoc 'proinv context))
        protop  (cdr (assoc 'protop context))
        style   (cdr (assoc 'style context))
        layer   (cdr (assoc 'layer context))
        ht      (cdr (assoc 'ht context))
        hits    (pf:lines-at-point pt (cdr (assoc 'lines context))))
  (setq primhit (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
  (cond
    ((null hits)
     (prompt (strcat "\n  " name " -- not on any named centerline; skipped.")))
    ((null primhit)
     (prompt (strcat "\n  " name " is on line(s) "
                     (pf:join (mapcar 'car hits) ",")
                     " but the profiled line is '" primary "'; skipped.")))
    ((null (setq verts (pf:pro-verts proinv)))
     (prompt (strcat "\n  " name " -- _INV .pro has no readable vertices; skipped.")))
    ((null (setq bracket (pfi:invert-bracket verts (cadr primhit))))
     (prompt (strcat "\n  " name " -- no invert at sta "
                     (pf:fmt-station (cadr primhit)) "; skipped.")))
    (T
     (setq io     (car bracket)          ; (edge-sta . elev) or nil (downstream)
           ii     (cadr bracket)         ; (edge-sta . elev) or nil (upstream)
           x      (pf:station->profile-x (cadr primhit) xf)
           rows   '()
           elevs  '()
           others (pf:sort-line-infos-alpha
                    (append (vl-remove primhit hits)
                            (pfi:endpoint-hits pt (cdr (assoc 'lines context))
                                               (mapcar 'car hits))))
           lats   '())
     ;; I.O. downstream -- left of the station line (row 0)
     (if io
       (setq rows  (list (pfi:inv-row "I.O." (cdr io)
                                      (pfi:prim-size proinv protop (car io))))
             elevs (list (cdr io))))
     ;; shared laterals -- CENTRED (between I.O. and primary I.I.)
     (foreach lat others
       (setq linfo (pfi:lateral-info lat (cdr (assoc 'lines context))))
       (if (car linfo)
         (setq rows  (append rows
                             (list (pfi:inv-row "I.I." (car linfo) (cadr linfo))))
               elevs (cons (car linfo) elevs)
               lats  (cons linfo lats))
         (prompt (strcat "\n  " name " -- lateral '" (car lat)
                         "' skipped: " (cdr linfo) "."))))
     ;; primary I.I. upstream -- far right (row last)
     (if ii
       (setq rows  (append rows
                           (list (pfi:inv-row "I.I." (cdr ii)
                                              (pfi:prim-size proinv protop (car ii)))))
             elevs (cons (cdr ii) elevs)))
     ;; one shared base Y: lowest invert present minus the text-scaled drop
     (setq baseY  (- (pf:elev->profile-y (apply 'min elevs) xf)
                     (* ht *pfi-invert-offset-factor*))
           offset (* ht *pf-offset-factor*)
           gapn   (* ht *pf-gap-rest-factor*))
     ;; leftmost structure: shift the TEXT stack right, clear of the elev axis
     (setq first-sta (cdr (assoc 'first-sta context))
           drawX     x)
     (if (and first-sta (equal (cadr primhit) first-sta *pf-range-eps*))
       (progn
         (setq target (+ (pf:xf-leftx xf)
                         (* *pfi-first-shift-clearance* (pf:xf-sf xf)))
               shift  (max 0.0 (- target (- x offset))))
         (setq drawX (+ x shift))))
     ;; the column stack: MR reading up = hangs DOWNWARD from base Y
     (setq res (pfd:draw-label-stack drawX baseY rows layer style ht
                                     offset gapn 'MR))
     (setq *pfinvert-run-ents* (append (cdr res) *pfinvert-run-ents*))
     ;; lateral pipe blocks at TRUE station + elevation (blocks may stack)
     (foreach lat (reverse lats)
       (pfd:ensure-layer (pf:sym-layer (caddr lat)) nil)
       (if (setq en (pfd:insert-pipe
                      (list x (pf:elev->profile-y (car lat) xf))
                      (cadr lat)
                      (pf:sym-layer (caddr lat))
                      (pf:xf-vscale xf)
                      (pf:xf-sf xf)))
         (setq *pfinvert-run-ents* (cons en *pfinvert-run-ents*))))
     (prompt (strcat "\n  Inverts labeled at " name "  ("
                     (if io (strcat "I.O. " (rtos (cdr io) 2 2)) "")
                     (if (and io ii) " / " "")
                     (if ii (strcat "I.I. " (rtos (cdr ii) 2 2)) "")
                     (if lats
                       (strcat ", " (itoa (length lats)) " lateral(s)")
                       "")
                     ").")))))


;;; ==========================================================================
;;; SECTION 5  --  Modes, pass record, command
;;; ==========================================================================

;; (pfi:line-min-sta context) -> lowest station of any structure on the primary
;;   line (across ALL inlets, not just the selected subset), or nil.  This is
;;   the leftmost structure on the grid -- the one whose stack shifts clear of
;;   the elevation-axis labels.
(defun pfi:line-min-sta (context / lines primary inlets best e pt hits ph)
  (setq lines   (cdr (assoc 'lines context))
        primary (cdr (assoc 'primary context))
        inlets  (cdr (assoc 'inlets context))
        best    nil)
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (pf:lines-at-point pt lines)
          ph   (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
    (if (and ph (or (null best) (< (cadr ph) best))) (setq best (cadr ph))))
  best)

;; (pfi:label-sel context) -> nil
;;   Labels the structures picked in the run dialog's list (sorted by
;;   station).  Replaces the old entsel Pick loop.
(defun pfi:label-sel (context / sel pr)
  (setq context (cons (cons 'first-sta (pfi:line-min-sta context)) context)
        sel     (cdr (assoc 'sel context)))
  (prompt (strcat "\nLabeling inverts at " (itoa (length sel))
                  " selected structure(s)..."))
  (foreach pr sel (pfi:process-structure (cadr pr) context))
  (princ))

(defun pfi:label-all (context / lines primary inlets pt hits ph pending e pr)
  (setq lines   (cdr (assoc 'lines context))
        primary (cdr (assoc 'primary context))
        inlets  (cdr (assoc 'inlets context))
        pending '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (pf:lines-at-point pt lines)
          ph   (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
    (if ph (setq pending (cons (list (cadr ph) e) pending))))
  (setq pending (vl-sort pending '(lambda (a b) (< (car a) (car b)))))
  ;; first structure = lowest station (pending is sorted ascending)
  (setq context (cons (cons 'first-sta (caar pending)) context))
  (prompt (strcat "\nLabeling inverts at " (itoa (length pending))
                  " structure(s) on '" primary "'."))
  (foreach pr pending (pfi:process-structure (cadr pr) context))
  (princ))

;; (pfi:write-pass ctx) -> nil
;;   Records the pass + validates the _INV .pro against the FILES checksum,
;;   writing STATUS after (labeling can never be older than its check).
(defun pfi:write-pass (ctx / anchor clayer-p allmode handles old files
                       stored cur state findings e layer)
  (setq anchor   (cdr (assoc 'anchor ctx))
        clayer-p (cdr (assoc 'clayer-p ctx))
        layer    (cdr (assoc 'layer ctx))
        allmode  (= (cdr (assoc 'mode ctx)) "All")
        handles  '())
  (foreach e *pfinvert-run-ents*
    (if (entget e) (setq handles (cons (pf:handle e) handles))))
  (cond
    (clayer-p
     ;; fire-and-forget: record THAT it ran + where; no handles
     (pfa:pass-put anchor "INVERT-CLAYER" layer T '()))
    (T
     ;; Pick mode appends to the existing ledger; All mode replaced it
     (if (and (not allmode)
              (setq old (pfa:pass-handles anchor *pfi-pass-name*)))
       (setq handles (append old handles)))
     (pfa:pass-put anchor *pfi-pass-name* layer nil handles)))
  ;; ---- input validation -> STATUS ---------------------------------------
  (setq files   (pfa:files-get anchor)
        stored  (if (and files (assoc 300 files)) (cdr (assoc 300 files)) "")
        cur     (pf:checksum-file (cdr (assoc 'proinv ctx)))
        findings '())
  (cond
    ((= stored "")
     (setq state 0
           findings '("no _INV .pro checksum on record -- run PFSETUP (edit)")))
    ((null cur)
     (setq state 2
           findings '("_INV .pro on record could not be read for checksum")))
    ((= stored cur)
     (setq state 1))
    (T
     (setq state 2
           findings '("_INV .pro content CHANGED since setup -- inverts may be stale; re-run PFSETUP"))))
  (pfa:status-put anchor state findings)
  (prompt (strcat "\nPass recorded.  Status: " (pfa:status-label state)))
  (foreach e findings (prompt (strcat "\n  FINDING: " e)))
  (princ))

;;; ==========================================================================
;;; SECTION 5b  --  PFINVERT run dialog  (its OWN dialog: pfi_run)
;;;   Pick-first, compute-then-render, mirroring pflabel but standalone so
;;;   invert-specific fields can grow here.  Pure compute helpers (pending /
;;;   build-lines / gather-inlets / pass-xs / labeled-x-p) are shared from
;;;   pflabel; the dialog wiring is local (pi_* tiles, id-* dynamic locals).
;;; ==========================================================================

;; RENDER ONLY -- id-* precomputed by pfi:rd-compute.
(defun pfi:rd-fill ( / i p v ndone)
  (setq i 0)
  (start_list "pi_list")
  (foreach p id-pend
    (add_list (strcat (pfset:pad (caddr p) 22)
                      (pfset:pad (pf:fmt-station (car p)) 16)
                      (if (nth i id-status) "[LABELED]" "")))
    (setq i (1+ i)))
  (end_list)
  (setq ndone 0)
  (foreach v id-status (if v (setq ndone (1+ ndone))))
  (set_tile "pi_count"
            (strcat (itoa (length id-pend)) " structure(s) on '" id-primary
                    "'; " (itoa ndone) " already inverted."))
  (set_tile "error" "")
  (princ))

;; ALL HEAVY WORK, BEFORE new_dialog.  -> T when there is a list; nil on no line.
(defun pfi:rd-compute ( / xf xs eps p)
  (setq id-pend (if (pflabel:line-loaded-p id-primary id-lines)
                  (pflabel:pending id-inlets id-lines id-primary)
                  'NOLINE))
  (cond
    ((eq id-pend 'NOLINE) (setq id-pend '()) nil)
    (T
     (setq xf        (pfa:anchor->xform id-anchor)
           xs        (pflabel:pass-xs id-anchor id-pass)
           eps       (max *pfa-recon-eps*
                          (* 1.5 (pf:text-height (pf:xf-hplot xf))))
           id-status '())
     (foreach p id-pend
       (setq id-status
             (append id-status
                     (list (pflabel:labeled-x-p
                             (pf:station->profile-x (car p) xf) xs eps)))))
     T)))

(defun pfi:rd-sel ( / s idxs out i)
  (setq s (get_tile "pi_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select structures in the list first -- or Label All.")
    (progn
      (setq idxs (read (strcat "(" s ")")) out '())
      (foreach i idxs (setq out (cons (nth i id-pend) out)))
      (setq id-res (list (cons 'mode   "Sel")
                         (cons 'sel    (reverse out))
                         (cons 'lines  id-lines)
                         (cons 'inlets id-inlets)))
      (done_dialog 1))))

(defun pfi:rd-all ()
  (if (null id-pend)
    (set_tile "error" "No structures on this line -- nothing to label.")
    (progn
      (setq id-res (list (cons 'mode   "All")
                         (cons 'sel    id-pend)
                         (cons 'lines  id-lines)
                         (cons 'inlets id-inlets)))
      (done_dialog 1))))

;; (pfi:run-dialog title passname anchor) -> result alist | nil
(defun pfi:run-dialog (title passname anchor
                       / id-anchor id-primary id-pass id-lines id-inlets
                         id-pend id-status id-res dcl_id xf cl pairs result)
  (setq id-anchor anchor id-pass passname id-res nil
        xf        (pfa:anchor->xform anchor))
  (cond
    ((null xf)
     (prompt "\nTarget grid record unreadable -- cannot label.") nil)
    ((null (setq cl (pf:xf-get 'clfile xf)))
     (prompt "\nNo .cl on record for this target -- run PFSETUP (edit).") nil)
    (T
     (setq id-primary (pf:xf-get 'name xf)
           pairs      (pf:dedupe-pairs
                        (cons (cons cl id-primary)
                              (pflabel:registry-pairs cl)))
           id-lines   (pflabel:build-lines pairs)
           id-inlets  (pflabel:gather-inlets))
     (if (null (pfi:rd-compute))
       (progn
         (prompt (strcat "\nCenterline for '" id-primary
                         "' could not be read -- nothing to label."))
         nil)
       (progn
         (setq dcl_id (load_dialog (pfset:dcl-file)))
         (if (< dcl_id 0)
           (progn (prompt "\nCould not load pfdialog.dcl.") nil)
           (if (not (new_dialog "pfi_run" dcl_id))
             (progn (unload_dialog dcl_id)
                    (prompt "\nCould not open the invert dialog.") nil)
             (progn
               (set_tile "pi_title" title)
               (pfi:rd-fill)
               (action_tile "pi_sel" "(pfi:rd-sel)")
               (action_tile "pi_all" "(pfi:rd-all)")
               (action_tile "pi_set" "(pflabel:show-dialog)")
               (action_tile "cancel" "(done_dialog 0)")
               (action_tile "help"
                 (strcat "(pfset:help \"Every elevation comes from the target's "
                         "bound _INV .pro.  Select rows and Label Selected, or "
                         "Label All for every structure on the primary line.  "
                         "Label All REPLACES this command's previous tracked "
                         "pass; Selected appends.\\n\\n[LABELED] = an invert of "
                         "this command's pass already sits at that station.\\n\\n"
                         "Wrong target?  Cancel and rerun.\")"))
               (setq result (vl-catch-all-apply 'start_dialog '()))
               (unload_dialog dcl_id)
               (cond
                 ((vl-catch-all-error-p result)
                  (prompt (strcat "\nDialog error: "
                                  (vl-catch-all-error-message result)))
                  nil)
                 ((= result 1) id-res)
                 (T nil))))))))))


;;; ==========================================================================
;;; SECTION 6  --  C:PFINVERT   (pick-first, then the invert dialog)
;;; ==========================================================================
(defun c:PFINVERT ( / anchor rd ctx n)
  (setq *pfinvert-prev-error* *error*
        *error*               pfinvert:*error*
        *pfinvert-undo-open*  nil)
  (pf:echo-off)
  (pf:load-apis)
  ;; pick-first (PFXLABEL parity): choose/place the target, THEN list only its
  ;; structures.  choose-or-place places an unplaced pick on the fly.
  (setq anchor (pfs:choose-or-place))
  (if (null anchor)
    (prompt "\nPFINVERT cancelled -- no target.")
    (progn
      (setq rd (pfi:run-dialog
                 "PFINVERT -- invert labels at pipe elevation"
                 *pfi-pass-name* anchor))
      (if (null rd)
        (prompt "\nPFINVERT cancelled.")
        (progn
          (setq ctx (pfi:setup anchor (cdr (assoc 'mode rd))
                               (cdr (assoc 'lines rd))
                               (cdr (assoc 'inlets rd))))
          (if ctx
            (progn
              (setq ctx (cons (cons 'sel (cdr (assoc 'sel rd))) ctx))
              (setq *pfinvert-run-ents* '())
              (command "_.UNDO" "_Begin")
              (setq *pfinvert-undo-open* T)
              ;; All + derived layer = replace this pass's previous output
              ;; (erase-by-handle; hand work and CLAYER output untouched)
              (if (and (= (cdr (assoc 'mode ctx)) "All")
                       (not (cdr (assoc 'clayer-p ctx))))
                (progn
                  (setq n (pfa:erase-pass anchor *pfi-pass-name*))
                  (if (> n 0)
                    (prompt (strcat "\nReplaced previous invert pass ("
                                    (itoa n)
                                    " entities erased by handle).")))))
              (if (= (cdr (assoc 'mode ctx)) "All")
                (pfi:label-all ctx)
                (pfi:label-sel ctx))
              (pfi:write-pass ctx)
              (command "_.UNDO" "_End")
              (setq *pfinvert-undo-open* nil)))))))
  (pf:echo-on)
  (setq *error* *pfinvert-prev-error*)
  (princ))

(defun c:PFI () (c:PFINVERT))

(princ "\npfinvert.lsp loaded (V4, anchor-driven).  Command: PFINVERT (alias PFI).")
(princ)
;;; ==========================================================================
;;; end of pfinvert.lsp
;;; ==========================================================================
