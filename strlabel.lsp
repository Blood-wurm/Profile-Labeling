;;; ==========================================================================
;;; strlabel.lsp  --  C:STRLABEL : top-of-grid structure labels
;;; --------------------------------------------------------------------------
;;; Requires strtools-lib.lsp (the shared engine) to be loaded first.
;;;
;;; What it does, per the agreed spec:
;;;   - You calibrate the profile grid once, pick the proposed ground line,
;;;     name each storm centerline, and name the line THIS profile follows.
;;;   - Then you pick plan-view structure blocks one at a time. For each, it
;;;     computes line membership + station + ID from geometry, looks up type
;;;     and size from the block name, samples G.L. off the ground line, and
;;;     draws the vertical text stack + station line up in the profile.
;;;
;;; Inverts are NOT drawn here (second-pass tool). This command draws only the
;;; top-of-grid label family.
;;;
;;; STATUS: not yet run in a live drawing. Test on a scratch copy first.
;;; ==========================================================================

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  firm-standard constants and the honest assumptions.
;;; --------------------------------------------------------------------------

(setq *st-layer*  "STORM-TEXT_P")   ; label layer (assumed to already exist)
(setq *st-style*  "L080")           ; text style
(setq *st-height* 1.60)             ; text height (model units)
(setq *st-prefix* "CONST.")         ; row prefix; edit rare exceptions by hand

;; ASSUMPTION: the combined ID lists lines in the SAME order as the STA rows
;; (the profiled/primary line first). Your junction sample image showed the
;; ID in the opposite order (AA-3/AC-2 with AC as the first STA row). If the
;; ID should be reversed or alphabetized, that change lives in
;; strlabel:process-structure where `names` is built -- flag it and I'll adjust.


;;; ==========================================================================
;;; SETUP  --  one-time context for a labeling run
;;; ==========================================================================

;; (strlabel:read-grid) -> xform list  (see strtools-lib SECTION 3 for layout)
;;   Pick + prompt calibration. Version-proof: works regardless of Carlson
;;   build. If Carlson exposes the grid parameters to LISP, this is the ONE
;;   function to swap -- everything downstream reads the returned xform list.
(defun strlabel:read-grid ( / ll top sta0 elev0 hs vs)
  (setq ll (getpoint "\nPick grid LOWER-LEFT corner: "))
  (setq top (getpoint ll "\nPick a point on the grid TOP border: "))
  (initget 1)
  (setq sta0  (getreal "\nStart station at lower-left (feet, e.g. 0): "))
  (initget 1)
  (setq elev0 (getreal "\nDatum elevation at grid bottom: "))
  (setq hs (getreal "\nHorizontal scale (world units per station-foot) <1.0>: "))
  (if (null hs) (setq hs 1.0))
  (initget 1)
  (setq vs (getreal "\nVertical scale (world units per elevation-foot): "))
  (list (car ll) (cadr ll) sta0 elev0 hs vs (cadr top)))

;; (strlabel:pick-lines) -> list of (ename name)
(defun strlabel:pick-lines ( / tbl e nm)
  (setq tbl '())
  (while (setq e (entsel "\nSelect a storm centerline (Enter to finish): "))
    (setq nm (getstring "\nLine name (e.g. AA): "))
    (setq tbl (cons (list (car e) (strcase nm)) tbl)))
  (reverse tbl))

;; (strlabel:gather-inlets) -> list of block enames whose name is a known type
(defun strlabel:gather-inlets ( / ss i e nm lst)
  (setq ss (ssget "_X" '((0 . "INSERT"))) lst '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq e  (ssname ss i)
            nm (cdr (assoc 2 (entget e))))
      (if (st:type-entry nm *st-type-table*)
        (setq lst (cons e lst)))
      (setq i (1+ i))))
  (reverse lst))

;; (st:idx-add idx name val) -> idx   (prepends val to name's bucket)
(defun st:idx-add (idx name val / cell)
  (if (setq cell (assoc name idx))
    (subst (cons name (cons val (cdr cell))) cell idx)
    (cons (list name val) idx)))

;; (strlabel:index-stations inlets line-table eps) -> (name . sorted-stations)*
;;   Builds, per line, the ascending list of every structure station on it,
;;   so any structure can be ranked without re-scanning the drawing.
(defun strlabel:index-stations (inlets line-table eps / idx pt hits)
  (setq idx '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (st:lines-at-point pt line-table eps))
    (foreach h hits                         ; h = (name type station)
      (setq idx (st:idx-add idx (car h) (caddr h)))))
  (mapcar '(lambda (pair) (cons (car pair) (vl-sort (cdr pair) '<))) idx))

;; (strlabel:setup) -> context alist | nil
(defun strlabel:setup ( / xf ground lines primary inlets index)
  (setq xf (strlabel:read-grid))
  (setq ground (car (entsel "\nSelect the PROPOSED GROUND profile polyline: ")))
  (setq lines (strlabel:pick-lines))
  (if (null lines)
    (progn (prompt "\nNo centerlines selected -- aborting.") nil)
    (progn
      (setq primary (strcase (getstring "\nName of the line THIS profile follows: ")))
      (prompt "\nIndexing structures for ranking...")
      (setq inlets (strlabel:gather-inlets)
            index  (strlabel:index-stations inlets lines *st-eps*))
      (list (cons 'xform   xf)
            (cons 'lines   lines)
            (cons 'primary primary)
            (cons 'ground  ground)
            (cons 'index   index)))))


;;; ==========================================================================
;;; PER-STRUCTURE  --  reads context + engine, draws one label
;;; ==========================================================================

;; (strlabel:ranks-for line-infos context) -> list of integers
(defun strlabel:ranks-for (line-infos context / index)
  (setq index (cdr (assoc 'index context)))
  (mapcar
    '(lambda (li)
       (st:rank-on-line (cadr li)
                        (cdr (assoc (car li) index))
                        *st-rank-ascending* *st-eps*))
    line-infos))

;; (strlabel:process-structure block-ename context) -> nil
(defun strlabel:process-structure (block-ename context
                                   / ed pt name xf gtop primary hits primhit
                                     others line-infos names ranks
                                     type size id gl px basept topy)
  (setq ed      (entget block-ename)
        pt      (cdr (assoc 10 ed))
        name    (cdr (assoc 2 ed))
        xf      (cdr (assoc 'xform context))
        gtop    (st:grid-top-y xf)
        primary (cdr (assoc 'primary context))
        hits    (st:lines-at-point pt (cdr (assoc 'lines context)) *st-eps*))
  (setq primhit (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
  (cond
    ((null hits)
     (prompt (strcat "\n  " name " -- not on any named centerline; skipped.")))
    ((null primhit)
     (prompt (strcat "\n  " name " is on line(s) "
                     (st:join (mapcar 'car hits) ",")
                     " but the profiled line is '" primary "'; skipped.")))
    (T
     (setq others     (vl-remove primhit hits)
           line-infos (cons (list (car primhit) (caddr primhit))
                            (mapcar '(lambda (h) (list (car h) (caddr h))) others))
           names      (mapcar 'car line-infos)
           ranks      (strlabel:ranks-for line-infos context)
           type       (st:blockname->type name *st-type-table*)
           size       (st:blockname->size name *st-type-table*)
           id         (st:combine-id names ranks)
           gl         (st:ground-elev-at-station
                        (caddr primhit) (cdr (assoc 'ground context)) xf)
           px         (st:station->profile-x (caddr primhit) xf))
     (if (null gl)
       (prompt "\n  Ground line not found at this station -- skipped.")
       (progn
         (setq basept (list (+ px *st-text-offset*) gtop 0.0)
               topy   (st:draw-label-stack
                        basept
                        (st:build-label-rows line-infos type size id *st-prefix* gl)
                        *st-layer* *st-style* *st-height*))
         (st:draw-station-line px gtop topy *st-layer*)
         (prompt (strcat "\n  Labeled " id "."))))))
  (princ))


;;; ==========================================================================
;;; COMMAND
;;; ==========================================================================

(defun c:STRLABEL ( / ctx e ent ed)
  (setq ctx (strlabel:setup))
  (if ctx
    (progn
      (prompt "\nPick structures to label (Enter to finish).")
      (while (setq e (entsel "\nSelect structure: "))
        (setq ent (car e) ed (entget ent))
        (cond
          ((/= (cdr (assoc 0 ed)) "INSERT")
           (prompt "\n  Not a block -- skipped."))
          ((null (st:type-entry (cdr (assoc 2 ed)) *st-type-table*))
           (prompt (strcat "\n  Unknown structure block "
                           (cdr (assoc 2 ed)) " -- skipped.")))
          (T (strlabel:process-structure ent ctx))))))
  (princ))

(princ "\nstrlabel.lsp loaded.  Command: STRLABEL")
(princ)
;;; ==========================================================================
;;; end of strlabel.lsp
;;; ==========================================================================
