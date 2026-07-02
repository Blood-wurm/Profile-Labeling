;;; ==========================================================================
;;; strlabel.lsp  --  C:STRLABEL : top-of-grid structure labels
;;; --------------------------------------------------------------------------
;;; Requires strtools-lib.lsp (the shared engine) to be loaded first.
;;;
;;; What it does, per the agreed spec:
;;;   - You calibrate the profile grid once, select the Carlson surface (.tin),
;;;     select one or more Carlson centerline files (.cl), and name the line
;;;     THIS profile follows.
;;;   - Then you pick plan-view structure blocks one at a time. For each, it
;;;     computes line membership + station + ID from geometry, looks up type
;;;     and size from the block name, samples G.L. from the TIN surface, and
;;;     draws the vertical text stack + station line up in the profile.
;;;
;;; Inverts are NOT drawn here (second-pass tool). This command draws only the
;;; top-of-grid label family.
;;;
;;; STATUS: updated to Carlson Road/DTM APIs. Test on a scratch copy first.
;;; ==========================================================================

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  firm-standard constants and the honest assumptions.
;;; --------------------------------------------------------------------------

(setq *st-layer* "STORM-TEXT_P")   ; label layer (assumed to already exist)
(setq *st-style* "L080")           ; text style
(setq *st-height* 1.60)             ; text height (model units)
(setq *st-prefix* "CONST.")         ; row prefix; edit rare exceptions by hand

;; ASSUMPTION: the combined ID lists lines in the SAME order as the STA rows
;; (the profiled/primary line first).


;;; ==========================================================================
;;; SETUP  --  one-time context for a labeling run
;;; ==========================================================================

;; (strlabel:read-grid) -> xform list  (Matches Section 3 in strtools-lib.lsp)
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
  ;; Returns exact 5-element array expected by the backend engine:
  (list (car ll) sta0 hs (cadr top) vs))

;; (strlabel:load-lines) -> list of (clfile name start end)
;;   Loops file selection so multiple .cl files can be loaded for junctions.
(defun strlabel:load-lines ( / tbl file defname nm rng)
  (setq tbl '())
  (while (setq file (getfiled "Select Carlson Centerline (.CL) File (Cancel when done)" 
                              (if file file "") "cl" 0))
    (if (setq rng (st:cl-range file))
      (progn
        (setq defname (strcase (vl-filename-base file)))
        (setq nm (getstring (strcat "\nLine name for " defname " <" defname ">: ")))
        (if (= nm "") (setq nm defname) (setq nm (strcase nm)))
        (setq tbl (cons (list file nm (car rng) (cadr rng)) tbl))
        (prompt (strcat "\nLoaded line '" nm "' (Sta " (st:fmt-station (car rng)) 
                        " to " (st:fmt-station (cadr rng)) ").")))
      (prompt (strcat "\nError: Could not read station range from " file))))
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

;; (strlabel:index-stations inlets line-table) -> (name . sorted-stations)*
;;   Builds, per line, the ascending list of every structure station on it,
;;   so any structure can be ranked without re-scanning the drawing.
(defun strlabel:index-stations (inlets line-table / idx pt hits)
  (setq idx '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (st:lines-at-point pt line-table))
    (foreach h hits                         ; h = (name station)
      (setq idx (st:idx-add idx (car h) (cadr h)))))
  (mapcar '(lambda (pair) (cons (car pair) (vl-sort (cdr pair) '<))) idx))

;; (strlabel:setup) -> context alist | nil
(defun strlabel:setup ( / xf tin lines primary inlets index)
  (setq xf (strlabel:read-grid))
  (if (setq tin (getfiled "Select Carlson Surface (.TIN) File" "" "tin" 0))
    (progn
      (st:tin-load tin)
      (setq lines (strlabel:load-lines))
      (if (null lines)
        (progn (prompt "\nNo centerlines selected -- aborting.") (st:tin-unload) nil)
        (progn
          (setq primary (strcase (getstring "\nName of the line THIS profile follows: ")))
          (prompt "\nIndexing structures for ranking...")
          (setq inlets (strlabel:gather-inlets)
                index  (strlabel:index-stations inlets lines))
          (list (cons 'xform   xf)
                (cons 'lines   lines)
                (cons 'primary primary)
                (cons 'tin     tin)
                (cons 'index   index)))))))


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
                        *st-rank-ascending* *st-range-eps*))
    line-infos))

;; (strlabel:process-structure block-ename context) -> nil
(defun strlabel:process-structure (block-ename context
                                   / ed pt name xf gtop primary hits primhit
                                     others line-infos names ranks
                                     type size id gl-val gl-str px basept topy
                                     offset gap1 gapn)
  (setq ed      (entget block-ename)
        pt      (cdr (assoc 10 ed))
        name    (cdr (assoc 2 ed))
        xf      (cdr (assoc 'xform context))
        gtop    (st:grid-top-y xf)
        primary (cdr (assoc 'primary context))
        hits    (st:lines-at-point pt (cdr (assoc 'lines context))))
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
           line-infos (cons primhit others)
           names      (mapcar 'car line-infos)
           ranks      (strlabel:ranks-for line-infos context)
           type       (st:blockname->type name *st-type-table*)
           size       (st:blockname->size name *st-type-table*)
           id         (st:combine-id names ranks)
           gl-val     (st:tin-z pt)
           px         (st:station->profile-x (cadr primhit) xf))
     (if (null gl-val)
       (prompt "\n  Structure X,Y is off the DTM surface -- skipped.")
       (progn
         (setq gl-str (st:fmt-elev gl-val 2)
               offset (* *st-height* *st-offset-factor*)
               gap1   (* *st-height* *st-gap-first-factor*)
               gapn   (* *st-height* *st-gap-rest-factor*))
         (setq basept (list (+ px offset) gtop 0.0)
               topy   (st:draw-label-stack
                        basept
                        (st:build-label-rows line-infos type size id *st-prefix* gl-str)
                        *st-layer* *st-style* *st-height* gap1 gapn))
         (st:draw-station-line px gtop topy *st-layer*)
         (prompt (strcat "\n  Labeled " id "."))))))
  (princ))


;;; ==========================================================================
;;; COMMAND
;;; ==========================================================================

(defun c:STRLABEL ( / ctx e ent ed)
  (st:load-apis)
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
          (T (strlabel:process-structure ent ctx))))
      ;; Clean up loaded TIN surface when command completes normally
      (st:tin-unload)))
  (princ))

(princ "\nstrlabel.lsp loaded.  Command: STRLABEL")
(princ)
;;; ==========================================================================
;;; end of strlabel.lsp
;;; ==========================================================================