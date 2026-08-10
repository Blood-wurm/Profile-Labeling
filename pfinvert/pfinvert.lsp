;;; ==========================================================================
;;; pfinvert.lsp  --  C:PFINVERT : invert labels at structures
;;;                   Dialog: pfi_run.
;;; Load position 9 of 10: after pfxlabel, before pfpalette.
;;; Model, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfinvert-undo-open*)) (setq *pfinvert-undo-open* nil))
(if (not (boundp '*pfinvert-run-ents*)) (setq *pfinvert-run-ents* '()))

(setq *pfi-pass-name* "INVERT")


;;; ==========================================================================
;;; SECTION 1  --  Esc ledger flush  (error handling lives in pf:run-command)
;;; ==========================================================================

(if (not (boundp '*pfinvert-run-ctx*)) (setq *pfinvert-run-ctx* nil))

;; (pfi:flush-pass) -> nil   The Esc ledger flush (pf:run-command hook).
;;   Writes the pass ledger for whatever got drawn before the Esc, INSIDE the
;;   still-open undo group.  The engine publishes *pfinvert-run-ctx* and
;;   clears it on normal exit, so this fires only on a mid-run interrupt.
(defun pfi:flush-pass ()
  (if (and *pfinvert-undo-open* *pfinvert-run-ctx*)
    (progn (pfi:write-pass *pfinvert-run-ctx*)
           (setq *pfinvert-run-ctx* nil)))
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
;;   io = the invert that LEAVES this structure, ii = the one that ARRIVES --
;;   each (edge-sta . elev) or nil.  Two adjacent vertices a structure-width
;;   apart form a normal structure (both set): of that pair the LOWER is the
;;   outgoing pipe, so direction is self-determining from elevation.
;;   A polyline ENDPOINT whose only neighbour is a full pipe-run away is a
;;   TERMINUS -- one invert, and the pair rule does NOT apply, because the single
;;   vertex is the end of a whole pipe rather than one side of a structure.
;;   Which end of the RUN it is decides the direction:
;;     high end = the upstream head -- the only pipe LEAVES  -> I.O only
;;     low  end = the downstream terminus -- the pipe ARRIVES -> I.I only
;;   Compared against the far END of the profile, not the neighbouring vertex,
;;   which keeps it independent of which way the line is stationed.
;;   nil when there are no vertices, or when the nearest vertex is farther from
;;   sta than a structure is wide -- that structure has no invert in THIS .pro
;;   and must not silently inherit its neighbour's elevation.
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
      (if (> (abs (- (car cur) sta)) *pfi-struct-width-max*)
        nil                    ; nearest vertex is a pipe-run away: NOT this one
        (progn
          (cond
            ;; interior vertex: pair with the nearer neighbour (structure edge)
            ((and prev nxt) (setq partner (if (<= gp gn) prev nxt)))
            ;; endpoint with a NARROW neighbour = a structure at the very .pro end
            ((and prev (<= gp *pfi-struct-width-max*)) (setq partner prev))
            ((and nxt  (<= gn *pfi-struct-width-max*)) (setq partner nxt))
            ;; endpoint whose only neighbour is a pipe-run away = terminus
            (T (setq partner nil)))
          (if partner
            (progn                        ; two inverts: lower leaves, higher arrives
              (setq a cur b partner)
              (if (<= (cdr a) (cdr b)) (setq io a ii b) (setq io b ii a))
              (list io ii))
            (progn                        ; terminus: classify by profile END
              (setq other (if (= i 0) (last verts) (car verts)))
              (if (<= (cdr cur) (cdr other))
                (list nil cur)            ; low end  -- pipe ARRIVES -> I.I only
                (list cur nil)))))))))    ; high end -- pipe LEAVES  -> I.O only


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
               layer    (if clayer-p (getvar "CLAYER") (pfd:anno-layer)))
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
                                         (cons prim (pfa:registry-pairs cl))))
                           (pfa:build-lines pairs)))
               primary (cdr prim))
         (cond
           ((null lines)
            (prompt "\nNo readable centerlines -- aborting.") nil)
           ((null (pfa:line-loaded-p primary lines))
            (prompt (strcat "\nPrimary line '" primary
                            "' failed to load -- aborting."))
            nil)
           (T
            (setq inlets (if preinlets preinlets (pfa:gather-inlets)))
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

;; (pfi:lateral-info hit lines) -> (clfile (role elev size) ...) | (nil . reason)
;;   hit = (name station) on a NON-primary line.  Resolves that line's _INV/_TOP
;;   .pro through the registry (anchor first, stub second) and BRACKETS its
;;   vertices at ITS station -- the same exact-vertex read the primary gets, so a
;;   shared line's DIRECTION is derived rather than assumed.
;;   role = 'IO (the pipe leaves this structure) | 'II (it arrives).  A line that
;;   terminates at the structure yields ONE row; one that passes through yields
;;   both, I.O first.
;;   NOT a pf:pipe-at sample: sampling at a junction means sampling at the .pro's
;;   own station-range boundary, where profile_z returns nil and the row silently
;;   vanishes.
(defun pfi:lateral-info (hit lines / entry clfile ty nm sf3 verts br out)
  (setq entry  (pfa:line-loaded-p (car hit) lines)
        clfile (if entry (car entry)))
  (cond
    ((null clfile) (cons nil "no line-table entry"))
    (T
     (setq ty  (pf:type-of clfile)
           nm  (pf:name-of clfile)
           sf3 (pfa:src-files ty nm))
     (cond
       ((null sf3)       (cons nil "not registered"))
       ((null (car sf3)) (cons nil "no _INV .pro bound"))
       ((null (setq verts (pf:pro-verts (car sf3))))
        (cons nil "_INV .pro has no readable vertices"))
       ((null (setq br (pfi:invert-bracket verts (cadr hit))))
        (cons nil (strcat "no invert at its sta "
                          (pf:fmt-station (cadr hit)))))
       (T
        (setq out '())
        (if (cadr br)                     ; arrives here
          (setq out (cons (list 'II (cdr (cadr br))
                                (pfi:size-at (car sf3) (cadr sf3)
                                             (car (cadr br))))
                          out)))
        (if (car br)                      ; leaves here -- consed last = first out
          (setq out (cons (list 'IO (cdr (car br))
                                (pfi:size-at (car sf3) (cadr sf3)
                                             (car (car br))))
                          out)))
        (cons clfile out))))))

;; (pfi:endpoint-hits pt lines seen) -> extra (name station) for same-type lines
;;   that TERMINATE at this structure -- an endpoint within *pfi-junction-tol* of
;;   the point -- and are not already in `seen`.  On-line membership
;;   (pf:lines-at-point) is tuned for pass-through hits, so a lateral joining at
;;   its own END slips past it; this recovers those junctions.
;;   TWO STAGES, and the split matters.  The drawn twin's vertices are a cheap
;;   PROXIMITY filter ONLY -- their order is the drafting direction, which need
;;   not follow the .cl's stationing, so pairing the first vertex with `lo` reads
;;   the invert at the WRONG END of any line drawn against its stationing: nil
;;   when the .pro does not reach, a plausible wrong elevation when it does.
;;   The STATION therefore comes from pf:cl-endpoints, which is station-ordered
;;   by construction (p0 at lo, pn at hi).  A line whose authored end is not
;;   within tolerance contributes nothing, so the station returned is always one
;;   the structure actually sits at.
(defun pfi:endpoint-hits (pt lines seen / out pt2d e nm verts lo hi ends
                          p0 pn sta near)
  (setq out  '()
        pt2d (list (car pt) (cadr pt)))         ; drop z: 2D plan distance only
  (foreach e lines
    (setq nm    (cadr e)
          verts (nth 4 e)
          lo    (nth 2 e)
          hi    (nth 3 e))
    (if (not (member nm seen))
      (progn
        ;; stage 1 -- is either DRAWN end anywhere near?  (no twin: no filter)
        (if (and verts (cdr verts))
          (setq p0   (car verts)
                pn   (last verts)
                near (<= (min (distance pt2d (list (car p0) (cadr p0)))
                              (distance pt2d (list (car pn) (cadr pn))))
                         *pfi-junction-tol*))
          (setq near T))
        ;; stage 2 -- AUTHORED ends decide which station this junction is at
        (if near
          (progn
            (setq ends (pf:cl-endpoints (car e))
                  sta  nil)
            (if ends
              (progn
                (setq p0 (car ends) pn (cadr ends))
                (cond
                  ((<= (distance pt2d (list (car p0) (cadr p0)))
                       *pfi-junction-tol*)
                   (setq sta lo))
                  ((<= (distance pt2d (list (car pn) (cadr pn)))
                       *pfi-junction-tol*)
                   (setq sta hi)))))
            (if sta (setq out (cons (list nm sta) out))))))))
  out)

;; (pfi:inv-row prefix elev size) -> "PREFIX elev (NN\")" | "PREFIX elev"
;;   size nil (no _TOP .pro / unreadable) omits the parenthetical.
(defun pfi:inv-row (prefix elev size)
  (strcat prefix " " (rtos elev 2 2)
          (if size (strcat " (" (itoa size) "\")") "")))

;; (pfi:size-at proinv protop sta) -> nominal size | nil    (pipe at an edge)
;;   Sampled, not bracketed, and that is correct here: the size is (top - inv)
;;   at a station the BRACKET already proved is a vertex, never a probe for the
;;   invert itself.  Serves the primary and every shared line -- it was
;;   pfi:prim-size until laterals started bracketing their own .pro (2026-07-29).
(defun pfi:size-at (proinv protop sta / pipe)
  (if (setq pipe (pf:pipe-at proinv protop sta)) (cdr pipe)))

;; (pfi:node-hits enames lines) -> ((name station) ...)   union over one node
;;   The blocks of a merged shared structure each carry only their OWN line's
;;   membership -- a block set on line A sits too far off line B to pass the
;;   0.15-ft offset test.  The node's true line set is therefore the union of
;;   its blocks', deduped by line name (first station for a name wins; at a
;;   shared structure they agree to within a hair by definition).
(defun pfi:node-hits (enames lines / out seen e p h)
  (setq out '() seen '())
  (foreach e enames
    (setq p (cdr (assoc 10 (entget e))))
    (foreach h (pfa:lines-at e p lines)
      (if (not (member (car h) seen))
        (setq out  (cons h out)
              seen (cons (car h) seen)))))
  (reverse out))

;; (pfi:process-structure block-ename mates context) -> nil
;;   Draws the invert column + shared-line blocks for one structure.  `mates`
;;   are the other blocks merged into this node (pfi:merge-nodes), '() when the
;;   structure stands alone -- they contribute membership, never a second stack.
(defun pfi:process-structure (block-ename mates context
                              / ed pt name xf primary hits primhit others
                                proinv protop verts bracket io ii rows elevs
                                lat linfo r txt low io-row mid ii-row
                                x drawX lineX baseY offset gapn halfw ht style
                                layer res e en lats first-sta target shift)
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
        hits    (pfi:node-hits (cons block-ename mates)
                               (cdr (assoc 'lines context))))
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
     ;; COLUMNS ARE ASSIGNED BY ROLE, NOT BY ARRIVAL ORDER.  draw-label-stack
     ;; puts row 0 left of the station line and fans the rest right, so the
     ;; ordering contract -- I.O. | shared | I.I. -- holds only if the row that
     ;; LEAVES the structure is chosen for row 0 whoever owns it.  At a
     ;; downstream terminus the primary has no outgoing invert and the
     ;; continuing shared line owns it; putting that row in the centre (what
     ;; this did until 2026-07-29) left the left column empty and printed two
     ;; I.I. rows at a structure that plainly has a pipe running out of it.
     (setq io     (car bracket)          ; (edge-sta . elev) or nil -- LEAVES
           ii     (cadr bracket)         ; (edge-sta . elev) or nil -- ARRIVES
           x      (pf:station->profile-x (cadr primhit) xf)
           io-row nil
           mid    '()
           ii-row nil
           elevs  '()
           others (pf:sort-line-infos-alpha
                    (append (vl-remove primhit hits)
                            (pfi:endpoint-hits pt (cdr (assoc 'lines context))
                                               (mapcar 'car hits))))
           lats   '())
     ;; primary: what leaves takes the left column, what arrives the far right
     (if io
       (setq io-row (pfi:inv-row "I.O." (cdr io)
                                 (pfi:size-at proinv protop (car io)))
             elevs  (cons (cdr io) elevs)))
     (if ii
       (setq ii-row (pfi:inv-row "I.I." (cdr ii)
                                 (pfi:size-at proinv protop (car ii)))
             elevs  (cons (cdr ii) elevs)))
     ;; shared lines -- CENTRED, except an outgoing one claiming a vacant I.O.
     (foreach lat others
       (setq linfo (pfi:lateral-info lat (cdr (assoc 'lines context))))
       (if (car linfo)
         (progn
           (foreach r (cdr linfo)
             (setq txt   (pfi:inv-row (if (eq (car r) 'IO) "I.O." "I.I.")
                                      (cadr r) (caddr r))
                   elevs (cons (cadr r) elevs))
             (if (and (eq (car r) 'IO) (null io-row))
               (setq io-row txt)
               (setq mid (append mid (list txt)))))
           ;; ONE block per shared line, at its LOWEST invert on this station:
           ;; a line passing through has two, and two blocks at one station X
           ;; would sit on top of each other.
           (setq low  (car (vl-sort (cdr linfo)
                                    '(lambda (a b) (< (cadr a) (cadr b)))))
                 lats (cons (list (cadr low) (caddr low) (car linfo)) lats)))
         (prompt (strcat "\n  " name " -- lateral '" (car lat)
                         "' skipped: " (cdr linfo) "."))))
     (setq rows (append (if io-row (list io-row))
                        mid
                        (if ii-row (list ii-row))))
     ;; one shared base Y: lowest invert present minus the text-scaled drop
     ;;
     ;; UNIFORM GAPS, FAN CENTRED ON THE STATION X.  PFLABEL's stack is
     ;; deliberately lopsided -- row 0 left of the station X, the rest right, and
     ;; the 2 x offset straddle gives pfd:station-line room to run up between
     ;; them.  PFINVERT draws no station line, so that geometry only produces a
     ;; first gap a third wider than the rest and a fan hanging off to the right
     ;; of the structure it belongs to.
     ;;
     ;; pfd:draw-label-stack still does the drawing -- untouched, so PFLABEL is
     ;; untouched.  Two arguments steer it:
     ;;   offset = gapn/2  makes the straddle 2 x offset = gapn, so EVERY
     ;;                    centre-to-centre gap is one gapn;
     ;;   lineX  = drawX - halfw + gapn/2  slides the fan left by half its width,
     ;;                    which centres it on drawX.
     ;; halfw is centre-to-outermost-column, so the fan spans drawX +/- halfw and
     ;; an odd row count puts the middle row exactly on the station X.
     ;; Row ORDER is untouched: I.O. still reads leftmost, I.I. rightmost.
     (setq baseY  (- (pf:elev->profile-y (apply 'min elevs) xf)
                     (* ht *pfi-invert-offset-factor*))
           gapn   (* ht *pfi-row-gap-factor*)
           offset (/ gapn 2.0)
           halfw  (* 0.5 gapn (float (1- (length rows)))))
     ;; leftmost structure: shift the TEXT stack right, clear of the elev axis.
     ;; The stack's left edge is now drawX - halfw, not drawX - offset.
     (setq first-sta (cdr (assoc 'first-sta context))
           drawX     x)
     (if (and first-sta (equal (cadr primhit) first-sta *pf-range-eps*))
       (progn
         (setq target (+ (pf:xf-leftx xf)
                         (* *pfi-first-shift-clearance* (pf:xf-sf xf)))
               shift  (max 0.0 (- target (- x halfw))))
         (setq drawX (+ x shift))))
     ;; the column stack: MR reading up = hangs DOWNWARD from base Y
     (setq lineX (+ (- drawX halfw) offset))
     (setq res (pfd:draw-label-stack lineX baseY rows layer style ht
                                     offset gapn 'MR))
     (setq *pfinvert-run-ents* (append (cdr res) *pfinvert-run-ents*))
     ;; lateral pipe blocks at TRUE station + elevation (blocks may stack)
     (foreach lat (reverse lats)
       (if (setq en (pfd:insert-pipe
                      (list x (pf:elev->profile-y (car lat) xf))
                      (cadr lat)
                      (pfd:anno-layer)
                      (pf:xf-vscale xf)
                      (pf:xf-sf xf)))
         (setq *pfinvert-run-ents* (cons en *pfinvert-run-ents*))))
     ;; top-up, same contract as PFLABEL's: engine side, inside the undo group,
     ;; no-op when current, catch-wrapped against a locked layer.  EVERY block
     ;; of a merged node, not just the leader -- the mates were read through
     ;; pfa:lines-at too, and skipping them would leave them re-deriving their
     ;; membership on every run forever.
     (foreach e (cons block-ename mates)
       (pfa:memb-sync e (cdr (assoc 10 (entget e)))
                      (cdr (assoc 'lines context)) *pfa-roster*))
     (prompt (strcat "\n  Inverts labeled at " name "  ("
                     (if io (strcat "I.O. " (rtos (cdr io) 2 2)) "")
                     (if (and io ii) " / " "")
                     (if ii (strcat "I.I. " (rtos (cdr ii) 2 2)) "")
                     (if lats
                       (strcat ", " (itoa (length lats)) " lateral(s)")
                       "")
                     (if mates
                       (strcat ", shared node of " (itoa (1+ (length mates)))
                               " blocks")
                       "")
                     ")."))
     ;; verification parade (no-op unless "Zoom To" on).  ONE RULE, all three
     ;; commands: grid top down to the grid base OR past the hanging invert
     ;; stack, whichever is lower (the offset-factor margin clears the stack).
     (pf:zoom-item x
                   (min (pf:xf-basey xf)
                        (- baseY (* ht *pfi-invert-offset-factor*)))
                   (pf:grid-top-y xf)))))


;;; ==========================================================================
;;; SECTION 5  --  Modes, pass record, command
;;; ==========================================================================

;; (pfi:line-min-sta context) -> lowest station of any structure on the primary
;;   line (across ALL inlets, not just the selected subset), or nil.  This is the
;;   leftmost structure on the grid -- the one whose stack shifts clear of the
;;   elevation-axis labels.
;;   THE TICKET ALREADY CARRIES THIS: pfi:rd-sel / pfi:rd-all file the gather's
;;   pending list under 'pend, station-sorted ascending, so the minimum is its
;;   first station.  Recomputing it was a full inlet x line membership scan --
;;   every point costing a cl_location_at_pt -- to learn a number the caller was
;;   already holding.  The walk survives ONLY for a caller handing in a ticket
;;   with no 'pend.
(defun pfi:line-min-sta (context / pend lines primary inlets best e pt hits ph)
  (if (setq pend (cdr (assoc 'pend context)))
    (caar pend)
    (progn
      (setq lines   (cdr (assoc 'lines context))
            primary (cdr (assoc 'primary context))
            inlets  (cdr (assoc 'inlets context))
            best    nil)
      (foreach e inlets
        (setq pt   (cdr (assoc 10 (entget e)))
              hits (pfa:lines-at e pt lines)
              ph   (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
        (if (and ph (or (null best) (< (cadr ph) best))) (setq best (cadr ph))))
      best)))

;; (pfi:merge-nodes pend) -> ((sta ename blkname (mate-ename ...)) ...)
;;   ONE STACK PER NODE.  Structures whose stations match within *pfr-node-tol*
;;   are one shared structure drafted as two or more blocks -- one registered per
;;   line, which is how a junction is drawn.  Labeled independently they produce
;;   identical stacks at the same station X and base Y, superimposed into what
;;   looks like a single half-empty label.  Merged, the node draws once and its
;;   blocks' memberships are unioned by pfi:node-hits, so every line at the node
;;   gets its row exactly once.
;;   Entries keep pfa:pending's (sta ename blkname) prefix with the MATES at
;;   position 3, so the leader is still (cadr) and the station still (car).
;;   Position 3 is the row's HITS on the way in (pfa:pending) and the mates on
;;   the way out -- this rebuilds the list rather than appending, so the two
;;   never coexist, and pfi:process-structure only ever sees the mates.
(defun pfi:merge-nodes (pend / out cur p)
  (setq out '())
  (foreach p (vl-sort pend '(lambda (a b) (< (car a) (car b))))
    (if (and out (<= (abs (- (car p) (caar out))) *pfr-node-tol*))
      (setq cur (car out)
            out (cons (list (car cur) (cadr cur) (caddr cur)
                            (cons (cadr p) (nth 3 cur)))
                      (cdr out)))
      (setq out (cons (list (car p) (cadr p) (caddr p) '()) out))))
  (reverse out))

;; (pfi:merge-note nodes pend) -> the "(n merged)" clause | ""
(defun pfi:merge-note (nodes pend)
  (if (< (length nodes) (length pend))
    (strcat " (" (itoa (- (length pend) (length nodes)))
            " merged into shared structures)")
    ""))

;; (pfi:label-sel context) -> nil
;;   Labels the structures picked in the run dialog's list (sorted by
;;   station).  Replaces the old entsel Pick loop.
(defun pfi:label-sel (context / sel nodes pr)
  (setq context (cons (cons 'first-sta (pfi:line-min-sta context)) context)
        sel     (cdr (assoc 'sel context))
        nodes   (pfi:merge-nodes sel))
  (prompt (strcat "\nLabeling inverts at " (itoa (length nodes))
                  " selected structure(s)" (pfi:merge-note nodes sel) "..."))
  (foreach pr nodes (pfi:process-structure (cadr pr) (nth 3 pr) context))
  (princ))

;; (pfi:label-all context) -> nil
;;   The ticket ALREADY carries this list: pfi:rd-all files id-pend (the
;;   gather's pending result, station-sorted) under 'sel for mode "All" exactly
;;   as pfi:rd-sel does for "Sel".  Rebuilding it here was a second full
;;   inlet x line membership scan.  Twin of the pflabel:label-all fix; use the
;;   ticket, and rebuild ONLY when handed a mode-"All" ticket with no 'sel.
(defun pfi:label-all (context / lines primary inlets pt hits ph pending nodes
                      e pr)
  (setq lines   (cdr (assoc 'lines context))
        primary (cdr (assoc 'primary context))
        inlets  (cdr (assoc 'inlets context))
        pending (cdr (assoc 'sel context)))
  (if (null pending)
    (progn
      (foreach e inlets
        (setq pt   (cdr (assoc 10 (entget e)))
              hits (pfa:lines-at e pt lines)
              ph   (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
        (if ph (setq pending (cons (list (cadr ph) e) pending))))
      (setq pending (vl-sort pending '(lambda (a b) (< (car a) (car b)))))))
  ;; first structure = lowest station (pending is sorted ascending)
  (setq context (cons (cons 'first-sta (caar pending)) context)
        nodes   (pfi:merge-nodes pending))
  (prompt (strcat "\nLabeling inverts at " (itoa (length nodes))
                  " structure(s) on '" primary "'"
                  (pfi:merge-note nodes pending) "."))
  (foreach pr nodes (pfi:process-structure (cadr pr) (nth 3 pr) context))
  (princ))

;; (pfi:write-pass ctx) -> nil
;;   Records the pass + validates the _INV .pro against the FILES checksum,
;;   writing STATUS after (labeling can never be older than its check).
(defun pfi:write-pass (ctx / anchor clayer-p allmode handles old files
                       stored res state findings e layer)
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
  ;; ---- input validation -> STATUS_INVERT --------------------------------
  ;; PFINVERT's input is the _INV .pro and nothing else.  Its own record now,
  ;; so this no longer overwrites what PFLABEL learned about the .cl.
  (setq files  (pfa:files-get anchor)
        stored (if (and files (assoc 300 files)) (cdr (assoc 300 files)) "")
        res    (pfa:status-check anchor "INVERT" (cdr (assoc 'proinv ctx)) stored)
        state  (car res)
        findings (cdr res))
  (pfa:status-put anchor "INVERT" state stored findings)
  (prompt (strcat "\nPass recorded.  Status: " (pfa:status-label state)))
  (foreach e findings (prompt (strcat "\n  FINDING: " e)))
  (princ))

;;; ==========================================================================
;;; SECTION 5b  --  PFINVERT run dialog  (its OWN dialog: pfi_run)
;;;   Pick-first, compute-then-render.  The GATHER-COMPUTE is not local: it is
;;;   pfa:gather-compute, the one copy, because both commands ask the same
;;;   question of the same data and only the pass name differed.  PFINVERT's
;;;   profile work is downstream in the engine (pfi:invert-bracket /
;;;   pf:pro-verts) -- no .pro is read on this path.
;;;   What IS local is the dialog: pi_* tiles, id-* dynamic locals, and the
;;;   fill/sel/all handlers, since tile names belong to pfi_run alone.
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
  ;; the drift echo's dialog half -- the error tile is already here and is the
  ;; only thing the user is looking at while the modal is up
  (set_tile "error"
            (if id-orphans
              (strcat (itoa (length id-orphans))
                      " label(s) with no structure -- something moved.")
              ""))
  (princ))

;; ALL HEAVY WORK, BEFORE new_dialog.  -> T when there is a list; nil on no line.
;;   Binds pfa:gather-compute -- THE one gather-compute -- into this
;;   dialog's locals.  This was a line-for-line copy of pflabel:rd-compute
;;   until 2026-07-27, and the copy had already silently missed the drift echo;
;;   that divergence is the same class as the registry-builder and same-type
;;   membership bugs (OPEN-ISSUES).  Invert-specific compute, if it ever
;;   arrives, composes on top of the shared call rather than forking it again.
(defun pfi:rd-compute ( / g)
  (setq g (pfa:gather-compute id-anchor id-pass id-primary
                                  id-lines id-inlets))
  (if (null g)
    (progn (setq id-pend '() id-status '() id-orphans '()) nil)
    (progn (setq id-pend    (car g)
                 id-status  (cadr g)
                 id-orphans (caddr g))
           T)))

(defun pfi:rd-sel ( / s idxs out i)
  (setq s (get_tile "pi_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select structures in the list first -- or Label All.")
    (progn
      (setq idxs (read (strcat "(" s ")")) out '())
      (foreach i idxs (setq out (cons (nth i id-pend) out)))
      ;; 'pend rides beside 'sel: the FULL station-sorted list of structures on
      ;; the primary, which pfi:line-min-sta needs and which the gather already
      ;; computed.  Without it that function walked every inlet a second time
      ;; just to find the smallest number in a list it was standing next to.
      (setq id-res (list (cons 'mode   "Sel")
                         (cons 'sel    (reverse out))
                         (cons 'pend   id-pend)
                         (cons 'lines  id-lines)
                         (cons 'inlets id-inlets)))
      (done_dialog 1))))

(defun pfi:rd-all ()
  (if (null id-pend)
    (set_tile "error" "No structures on this line -- nothing to label.")
    (progn
      (setq id-res (list (cons 'mode   "All")
                         (cons 'sel    id-pend)
                         (cons 'pend   id-pend)
                         (cons 'lines  id-lines)
                         (cons 'inlets id-inlets)))
      (done_dialog 1))))

;; (pfi:run-dialog title passname anchor) -> result alist | nil
(defun pfi:run-dialog (title passname anchor
                       / id-anchor id-primary id-pass id-lines id-inlets
                         id-pend id-status id-orphans id-res dcl_id xf cl
                         pairs result)
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
                              (pfa:registry-pairs cl)))
           id-lines   (pfa:build-lines pairs)
           id-inlets  (pfa:gather-inlets))
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
;; (pfi:run anchor rd) -> nil
;;   The ENGINE: consumes the gathered order ticket (mode/lines/inlets/sel) and
;;   does all the drawing.  Twin of pflabel:run -- called by C:PFINVERT after
;;   its modal gather, and by the palette's deferred command with the identical
;;   alist.  Caller owns the *error*/echo wrapper; body unchanged from inline.
(defun pfi:run (anchor rd / ctx n)
  (setq ctx (pfi:setup anchor (cdr (assoc 'mode rd))
                       (cdr (assoc 'lines rd))
                       (cdr (assoc 'inlets rd))))
  (if ctx
    (progn
      ;; resolve INSIDE the ctx guard: a nil-ctx abort must not consume a
      ;; pending one-shot palette override
      (pf:zoom-resolve nil)         ; PFINVERT does NOT parade unless the palette asks
      (setq ctx (cons (cons 'sel  (cdr (assoc 'sel  rd))) ctx)
            ctx (cons (cons 'pend (cdr (assoc 'pend rd))) ctx))
      (setq *pfinvert-run-ents* '())
      (setq *pfinvert-run-ctx* ctx)       ; publish for the Esc flush
      (pf:undo-begin '*pfinvert-undo-open*)
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
      (pf:zoom-begin (pf:xf-sf (cdr (assoc 'xform ctx)))) ; snapshot + frame floor
      (if (= (cdr (assoc 'mode ctx)) "All")
        (pfi:label-all ctx)
        (pfi:label-sel ctx))
      (pf:zoom-end)                  ; restore the pre-run view after the parade
      (pfi:write-pass ctx)
      (setq *pfinvert-run-ctx* nil)     ; normal exit: the Esc flush disarms
      (pf:undo-end '*pfinvert-undo-open*)))
  (princ))

;; (pfi:cmd) -> nil   The command body, run under pf:run-command.
(defun pfi:cmd ( / anchor rd)
  (setq *pfinvert-undo-open* nil)
  ;; pick-first (PFXLABEL parity): choose/place the target, THEN list only its
  ;; structures.  choose-or-place anchors a registered pick on the fly.
  (setq anchor (pfs:choose-or-place))
  (if (null anchor)
    (prompt "\nPFINVERT cancelled -- no target.")
    (progn
      (setq rd (pfi:run-dialog
                 "PFINVERT -- invert labels at pipe elevation"
                 *pfi-pass-name* anchor))
      (if (null rd)
        (prompt "\nPFINVERT cancelled.")
        (pfi:run anchor rd))))          ; gather done -> hand to the engine
  (princ))

(defun c:PFINVERT ()
  (pf:run-command "PFINVERT" 'pfi:flush-pass 'pfi:cmd))

(defun c:PFI () (c:PFINVERT))

(princ "\npfinvert.lsp loaded (V4, anchor-driven).  Command: PFINVERT (alias PFI).")
(princ)
;;; ==========================================================================
;;; end of pfinvert.lsp
;;; ==========================================================================
