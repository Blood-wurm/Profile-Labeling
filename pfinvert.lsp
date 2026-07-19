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
;;;             drawn longitudinally as its .pro linework.  I.I / I.O come
;;;             from bracketing the structure at the GRADE BREAKS of the
;;;             _INV.pro (pfi:invert-bracket): walking outward from the
;;;             station, the first break each side is the structure edge, so
;;;             the bracket auto-widens with structure size.  The LOWER of
;;;             the pair is downstream (self-determining) -> I.O.
;;;
;;;   LATERALS  every OTHER registry line the structure sits on: a bare
;;;             pipe block at TRUE elevation on the station X (non-present
;;;             pipe -- same rendering rule as crossings) plus a bare
;;;             "I.I <elev>" text row.  No size/material text at the block;
;;;             line identity is already on the structure's top label.
;;;
;;;   TEXT      ALL rows share ONE base Y = lowest invert present MINUS
;;;             *pfi-invert-offset* (FIXED model units -- deliberately NOT
;;;             scaled by sf), fanning left/right across the station X by
;;;             the same straddle rule as the top stack.  COLUMNS, not
;;;             true-elevation rows -- that is what keeps a 0.10' drop from
;;;             colliding two callouts.  Justification MR: right-justified
;;;             reading up GROWS DOWNWARD, so the stack hangs below base Y.
;;;             No leader line -- the top station line already marks the X.
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
  (if *pfinvert-undo-open*
    (progn
      (command-s "_.UNDO" "_End")
      (setq *pfinvert-undo-open* nil)))
  (setq *error* *pfinvert-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 2  --  The grade-break bracket  (the isolated helper)
;;; ==========================================================================
;;; SAMPLE-AND-DETECT body.  If a live session finds a Road-API call that
;;; returns the .pro's vertices/PVIs directly, swap THIS section only --
;;; the contract (pfi:invert-bracket -> (ii . io) | nil) stays.

;; (pfi:break-scan pro sta limit dir) -> elevation at first grade break | nil
;;   Walks from sta toward limit (dir -1 downstation / +1 upstation) at
;;   *pfi-scan-step*, comparing successive segment slopes; the first joint
;;   where |dslope| > *pfi-grade-tol* is the structure edge.  Returns the
;;   elevation AT that joint.  nil = no break inside the window (flat run).
(defun pfi:break-scan (pro sta limit dir / step s1 s2 z1 z2 sl sl-prev found)
  (setq step    (* dir *pfi-scan-step*)
        s1      sta
        z1      (pf:pro-z pro s1)
        sl-prev nil
        found   nil)
  (while (and (null found) z1
              (if (> dir 0)
                (<= (+ s1 step) (+ limit 1e-6))
                (>= (+ s1 step) (- limit 1e-6))))
    (setq s2 (+ s1 step)
          z2 (pf:pro-z pro s2))
    (if z2
      (progn
        (setq sl (/ (- z2 z1) step))
        (if (and sl-prev (> (abs (- sl sl-prev)) *pfi-grade-tol*))
          (setq found z1))                    ; break at the joint = s1
        (setq sl-prev sl)))
    (setq s1 s2 z1 z2))
  found)

;; (pfi:invert-bracket pro sta) -> (ii . io) | nil
;;   ii = invert in (higher), io = invert out (lower) -- downstream is
;;   self-determining, so neither the flow direction nor the .cl's station-0
;;   end needs to be known.  A side with no break inside *pfi-scan-window*
;;   reads pf:pro-z at the station itself (no drop -> ii = io; both rows
;;   still drawn).  nil when the .pro is unreadable at the station.
(defun pfi:invert-bracket (pro sta / rng lo hi z0 em ep)
  (setq z0 (pf:pro-z pro sta))
  (if (null z0)
    nil
    (progn
      (setq rng (pf:pro-range pro)
            lo  (- sta *pfi-scan-window*)
            hi  (+ sta *pfi-scan-window*))
      (if rng
        (setq lo (max (car rng) lo)
              hi (min (cadr rng) hi)))
      (setq em (pfi:break-scan pro sta lo -1)
            ep (pfi:break-scan pro sta hi  1))
      (if (null em) (setq em z0))
      (if (null ep) (setq ep z0))
      (cons (max em ep) (min em ep)))))


;;; ==========================================================================
;;; SECTION 3  --  Run setup  (anchor -> context; reuses pflabel's machinery)
;;; ==========================================================================

;; (pfi:setup anchor) -> context alist | nil
;;   Same record checks as pflabel:setup, PLUS the _INV .pro is FATAL when
;;   missing -- every elevation this command draws comes from it.
(defun pfi:setup (anchor / xf cl proinv s style clayer-p layer prim pairs
                  lines primary mode inlets)
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
         ;; line table: primary = the record's .cl; secondaries = registry
         (setq prim    (cons cl (pf:xf-get 'name xf))
               pairs   (pf:dedupe-pairs
                         (cons prim (pflabel:registry-pairs cl)))
               lines   (pflabel:build-lines pairs)
               primary (cdr prim))
         (cond
           ((null lines)
            (prompt "\nNo readable centerlines -- aborting.") nil)
           ((null (pflabel:line-loaded-p primary lines))
            (prompt (strcat "\nPrimary line '" primary
                            "' failed to load -- aborting."))
            nil)
           (T
            (initget "All Pick")
            (setq mode (getkword
                         (strcat "\nLabel inverts [All/Pick] on '"
                                 primary "' <Pick>: ")))
            (if (null mode) (setq mode "Pick"))
            (setq inlets (pflabel:gather-inlets))
            (list (cons 'xform    xf)
                  (cons 'anchor   anchor)
                  (cons 'lines    lines)
                  (cons 'primary  primary)
                  (cons 'proinv   proinv)
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

;; (pfi:process-structure block-ename context) -> nil
;;   Draws the invert column + lateral blocks for one structure.
(defun pfi:process-structure (block-ename context
                              / ed pt name xf primary hits primhit others
                                proinv bracket ii io rows elevs lat linfo
                                x baseY offset gapn ht style layer res en
                                lats)
  (setq ed      (entget block-ename)
        pt      (cdr (assoc 10 ed))
        name    (cdr (assoc 2 ed))
        xf      (cdr (assoc 'xform context))
        primary (cdr (assoc 'primary context))
        proinv  (cdr (assoc 'proinv context))
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
    ((null (setq bracket (pfi:invert-bracket proinv (cadr primhit))))
     (prompt (strcat "\n  " name " -- _INV .pro unreadable at sta "
                     (pf:fmt-station (cadr primhit)) "; skipped.")))
    (T
     (setq ii     (car bracket)
           io     (cdr bracket)
           x      (pf:station->profile-x (cadr primhit) xf)
           rows   (list (strcat "I.I " (rtos ii 2 2))
                        (strcat "I.O " (rtos io 2 2)))
           elevs  (list ii io)
           others (pf:sort-line-infos-alpha (vl-remove primhit hits))
           lats   '())
     ;; laterals: bare I.I row + bare block at true elevation
     (foreach lat others
       (setq linfo (pfi:lateral-info lat (cdr (assoc 'lines context))))
       (if (car linfo)
         (progn
           (setq rows  (append rows
                               (list (strcat "I.I " (rtos (car linfo) 2 2))))
                 elevs (cons (car linfo) elevs)
                 lats  (cons linfo lats)))
         (prompt (strcat "\n  " name " -- lateral '" (car lat)
                         "' skipped: " (cdr linfo) "."))))
     ;; one shared base Y: lowest invert present minus the FIXED offset
     (setq baseY  (- (pf:elev->profile-y (apply 'min elevs) xf)
                     *pfi-invert-offset*)
           offset (* ht *pf-offset-factor*)
           gapn   (* ht *pf-gap-rest-factor*))
     ;; the column stack: MR reading up = hangs DOWNWARD from base Y
     (setq res (pfd:draw-label-stack x baseY rows layer style ht
                                     offset gapn 'MR))
     (setq *pfinvert-run-ents* (append (cdr res) *pfinvert-run-ents*))
     ;; lateral pipe blocks at TRUE elevation (blocks may stack; text never)
     (foreach lat (reverse lats)
       (pfd:ensure-layer (pf:sym-layer (caddr lat)) nil)
       (if (setq en (pfd:insert-pipe
                      (list x (pf:elev->profile-y (car lat) xf))
                      (cadr lat)
                      (pf:sym-layer (caddr lat))
                      (pf:xf-vscale xf)
                      (pf:xf-sf xf)))
         (setq *pfinvert-run-ents* (cons en *pfinvert-run-ents*))))
     (prompt (strcat "\n  Inverts labeled at " name "  (I.I "
                     (rtos ii 2 2) " / I.O " (rtos io 2 2)
                     (if lats
                       (strcat ", " (itoa (length lats)) " lateral(s)")
                       "")
                     ").")))))


;;; ==========================================================================
;;; SECTION 5  --  Modes, pass record, command
;;; ==========================================================================

(defun pfi:label-pick (context / e ent ed)
  (prompt "\nPick structures to label (Enter to finish).")
  (while (setq e (entsel "\nSelect structure: "))
    (setq ent (car e) ed (entget ent))
    (cond
      ((/= (cdr (assoc 0 ed)) "INSERT")
       (prompt "\n  Not a block -- skipped."))
      ((null (pf:rule-for (cdr (assoc 2 ed)) *pf-rule-table*))
       (prompt (strcat "\n  Unknown structure block "
                       (cdr (assoc 2 ed)) " -- skipped.")))
      (T (pfi:process-structure ent context))))
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

(defun c:PFINVERT ( / anchor ctx n)
  (setq *pfinvert-prev-error* *error*
        *error*               pfinvert:*error*
        *pfinvert-undo-open*  nil)
  (pf:load-apis)
  (setq anchor (pfa:pick-anchor
                 "\nSelect profile grid anchor (Enter to list): "))
  (if (null anchor) (setq anchor (pfs:choose-or-place)))
  (if (null anchor)
    (prompt "\nNo placed grid -- run PFSETUP.")
    (progn
      (setq ctx (pfi:setup anchor))
      (if ctx
        (progn
          (setq *pfinvert-run-ents* '())
          (command "_.UNDO" "_Begin")
          (setq *pfinvert-undo-open* T)
          ;; All + derived layer = replace this pass's previous output
          ;; (erase-by-handle; hand work and CLAYER output are untouched)
          (if (and (= (cdr (assoc 'mode ctx)) "All")
                   (not (cdr (assoc 'clayer-p ctx))))
            (progn
              (setq n (pfa:erase-pass anchor *pfi-pass-name*))
              (if (> n 0)
                (prompt (strcat "\nReplaced previous invert pass ("
                                (itoa n) " entities erased by handle).")))))
          (if (= (cdr (assoc 'mode ctx)) "All")
            (pfi:label-all ctx)
            (pfi:label-pick ctx))
          (pfi:write-pass ctx)
          (command "_.UNDO" "_End")
          (setq *pfinvert-undo-open* nil)))))
  (setq *error* *pfinvert-prev-error*)
  (princ))

(defun c:PFI () (c:PFINVERT))

(princ "\npfinvert.lsp loaded (V4, anchor-driven).  Command: PFINVERT (alias PFI).")
(princ)
;;; ==========================================================================
;;; end of pfinvert.lsp
;;; ==========================================================================
