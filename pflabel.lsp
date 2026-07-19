;;; ==========================================================================
;;; pflabel.lsp  --  C:PFLABEL : top-of-grid structure labels  (V4)
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings loaded
;;; first.  Dialog: pflabel_settings in pfdialog.dcl (PFLABELSET).
;;;
;;; V4 PIVOT: the command reads the ANCHOR.  Everything the old dialogs
;;; gathered per run (grid corners, start station, datum, scales, primary
;;; .cl) lives in the record PFSETUP wrote.  The run collapses to:
;;;
;;;   PFLABEL -> "Select profile grid anchor" -> [All/Pick] -> run.
;;;
;;; SECONDARY .cl SET = THE REGISTRY -- anchors AND stubs.  Membership is
;;; plan-view station math, so identity alone qualifies a line: the moment
;;; AUTO names the sheet, every junction's combined ID (AA-1/BB-2) is
;;; complete, placed or not.  PFSETUP order stops mattering, and the old
;;; silently-shorter-ID gap is closed by construction.
;;;
;;; LABEL Y = THE TOP-OF-GRID PROBE at each structure's station (grids have
;;; stepped tops; the stored top is "top at max station" only).  A station
;;; with no PF-GRID-MJR hit is skipped and reported.
;;;
;;; LAYER RULE: derived <TYPE>-TEXT_P from the anchor's utility type,
;;; handle-tracked, erase-and-replace on an All re-run.  The "Use current
;;; layer" toggle in PFLABELSET (Carlson-style) draws on CLAYER instead:
;;; not tracked, not erased, not counted -- the pass is still recorded
;;; (timestamp + layer, no handles) so the record can distinguish "labeled
;;; off-scope" from "never labeled".
;;;
;;; Label composition (unchanged from v3 -- validated near-100%):
;;;   STA rows   -> primary line FIRST, remaining lines ALPHABETICAL.
;;;   Combined ID-> ALPHABETICAL by line name (stable across profiles).
;;;   Const rows -> *pf-rule-table* (cfg), ordered wildcard match.
;;;   Elevation  -> "<G.L.|T.G.|T.R.> XXX.XX" placeholder; HDWL drops it.
;;; ==========================================================================

(vl-load-com)

;; Run-scoped state (set fresh by every command run).
(setq *pf-layer*  "STORM-TEXT_P")
(setq *pf-style*  "L080")
(setq *pf-height* 1.60)
(if (not (boundp '*pflabel-run-ents*)) (setq *pflabel-run-ents* '()))


;;; ==========================================================================
;;; SECTION 1  --  Error handling
;;; ==========================================================================

(if (not (boundp '*pflabel-undo-open*)) (setq *pflabel-undo-open* nil))

(defun pflabel:*error* (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFLABEL error: " msg)))
  (if *pflabel-undo-open*
    (progn
      (command-s "_.UNDO" "_End")
      (setq *pflabel-undo-open* nil)))
  (setq *error* *pflabel-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 2  --  Settings dialog  (PFLABELSET; wiring only -- I/O lives in
;;;                pfsettings.lsp)
;;; ==========================================================================

;; Main-dialog tile keys (populate/harvest order).
(setq *pflabel-keys*
  '("sta_pre" "sta_val" "sta_suf"
    "con_pre" "con_val" "con_suf"
    "gl_pre"  "gl_val"  "gl_suf"
    "layer"   "use_clayer" "style"))

(defun pflabel:populate-tiles (settings / k)
  (foreach k *pflabel-keys* (set_tile k (cdr (assoc k settings)))))

(defun pflabel:harvest-tiles ()
  (mapcar '(lambda (k) (cons k (get_tile k))) *pflabel-keys*))

(defun pflabel:on-save ( / f cur)
  (setq cur (pfset:merge (pfset:settings) (pflabel:harvest-tiles)))
  (if (setq f (getfiled "Save PFTools Settings" (pfset:dir) "txt" 1))
    (progn (pfset:write-settings f cur)
           (prompt (strcat "\nSaved settings to " f)))))

(defun pflabel:on-load ( / f loaded)
  (if (setq f (getfiled "Load PFTools Settings" (pfset:dir) "txt" 0))
    (progn
      (setq loaded (pfset:merge *pfset-def-settings* (pfset:read-settings f)))
      (pflabel:populate-tiles loaded)
      (pfset:put-setting "hscale" (cdr (assoc "hscale" loaded)))
      (pfset:put-setting "vscale" (cdr (assoc "vscale" loaded)))
      (prompt (strcat "\nLoaded settings from " f)))))

;; (pflabel:show-dialog) -> settings alist | nil
(defun pflabel:show-dialog ( / dcl_id cur result)
  (setq dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pflabel_settings" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the settings dialog.") nil)
      (progn
        (setq cur (pfset:settings))
        (pflabel:populate-tiles cur)
        (action_tile "pick_layer"
          "(set_tile \"layer\" (pfset:pick-from-list dcl_id \"Select Layer\" (pfset:layer-list) (get_tile \"layer\")))")
        (action_tile "pick_style"
          "(set_tile \"style\" (pfset:pick-from-list dcl_id \"Select Text Style\" (pfset:style-list) (get_tile \"style\")))")
        (action_tile "save_btn" "(pflabel:on-save)")
        (action_tile "load_btn" "(pflabel:on-load)")
        (action_tile "ok"
          "(setq cur (pflabel:harvest-tiles)) (done_dialog 1)")
        (action_tile "cancel" "(done_dialog 0)")
        (setq result (vl-catch-all-apply 'start_dialog '()))
        (unload_dialog dcl_id)
        (cond
          ((vl-catch-all-error-p result)
           (prompt (strcat "\nDialog error: "
                           (vl-catch-all-error-message result)))
           nil)
          ((= result 1)
           (setq *pfset-settings* (pfset:merge (pfset:settings) cur))
           (pfset:save-auto)
           (prompt "\nPFTools settings saved.")
           *pfset-settings*)
          (T (prompt "\nSettings unchanged.") nil))))))

(defun c:PFLABELSET ( ) (pflabel:show-dialog) (princ))


;;; ==========================================================================
;;; SECTION 3  --  Run setup helpers
;;; ==========================================================================

;; (pflabel:build-lines pairs) -> list of (clfile name start end verts)
(defun pflabel:build-lines (pairs / tbl file nm rng entry p)
  (setq tbl '())
  (foreach p pairs
    (setq file (car p) nm (cdr p))
    (if (setq rng (pf:cl-range file))
      (progn
        (setq entry (pf:attach-corridor (list file nm (car rng) (cadr rng))))
        (setq tbl (cons entry tbl))
        (prompt (strcat "\nLoaded line '" nm "' (Sta " (pf:fmt-station (car rng))
                        " to " (pf:fmt-station (cadr rng)) ")"
                        (if (nth 4 entry) "." "  [no corridor polyline matched]."))))
      (prompt (strcat "\nError: Could not read station range from " file))))
  (reverse tbl))

(defun pflabel:line-loaded-p (name lines)
  (car (vl-member-if '(lambda (e) (= (cadr e) name)) lines)))

;; (pflabel:registry-pairs primary-cl) -> list of (path . name): every
;;   OTHER registry entry's .cl -- anchors AND stubs.  The self-maintaining
;;   secondary set.  Stubs count because membership is plan-view station
;;   math: IDENTITY IS ENOUGH -- an unplaced line still contributes to a
;;   junction's combined ID.  (This closes the old silently-shorter-ID gap.)
(defun pflabel:registry-pairs (primary-cl / out e meta tfile at s)
  (setq out '())
  (foreach e (pfa:all-anchors)
    (setq meta  (pfa:meta-get e)
          tfile (if (and meta (assoc 1 meta)) (cdr (assoc 1 meta)) ""))
    (if (and (/= tfile "")
             (/= (strcase tfile) (strcase primary-cl)))
      (progn
        (setq at (pfa:read-attribs e))
        (setq out (cons (cons tfile (pfa:att "LINE" at)) out)))))
  (foreach s (pfa:stub-list)
    (setq tfile (caddr s))
    (if (and tfile (/= tfile "")
             (/= (strcase tfile) (strcase primary-cl))
             (not (assoc tfile out)))
      (setq out (cons (cons tfile (cadr s)) out))))
  (reverse out))

;; (pflabel:gather-inlets) -> block enames matching a *pf-rule-table* rule
(defun pflabel:gather-inlets ( / ss i e nm lst)
  (setq ss (ssget "_X" '((0 . "INSERT"))) lst '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq e  (ssname ss i)
            nm (cdr (assoc 2 (entget e))))
      (if (pf:rule-for nm *pf-rule-table*)
        (setq lst (cons e lst)))
      (setq i (1+ i))))
  (reverse lst))

;; (pflabel:index-stations inlets line-table) -> (name . sorted-stations)*
(defun pflabel:index-stations (inlets line-table / idx pt hits e h)
  (setq idx '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (pf:lines-at-point pt line-table))
    (foreach h hits
      (setq idx (pf:idx-add idx (car h) (cadr h)))))
  (mapcar '(lambda (pair) (cons (car pair) (vl-sort (cdr pair) '<))) idx))

;; (pflabel:label-fmt settings) -> the prefix/suffix strings the engine uses
(defun pflabel:label-fmt (settings)
  (mapcar
    '(lambda (k) (cons k (cdr (assoc k settings))))
    '("sta_pre" "sta_suf" "con_suf" "gl_suf")))

;; (pflabel:setup anchor) -> context alist | nil
;;   Everything comes from the record + settings; zero dialogs, zero typing.
(defun pflabel:setup (anchor / xf cl s style clayer-p layer prim pairs
                       lines primary mode inlets index d)
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
    (T
     ;; drift + corner sanity: warn loudly, let the user decide
     (foreach d (pfa:corner-check anchor)
       (prompt (strcat "\n  DRIFT: " d)))
     (if (not (pfa:probe-corner (list (pf:xf-leftx xf) (pf:xf-basey xf))))
       (prompt "\n  WARNING: no grid LINE found at the anchor corner (grid moved without its anchor?)"))
     ;; style must exist; layer per the V4 rule
     (setq s     (pfset:settings)
           style (pfset:active-style))
     (if (= style "")
       (progn (prompt "\nNo usable text style in this drawing -- aborting.") nil)
       (progn
         ;; layer per the settings toggle (Carlson-style "use current layer")
         (setq clayer-p (= (cdr (assoc "use_clayer" s)) "1")
               layer    (if clayer-p
                          (getvar "CLAYER")
                          (strcat (strcase (pf:xf-get 'type xf))
                                  *pfx-text-layer-suffix*)))
         (if (not clayer-p) (pfd:ensure-layer layer nil))
         (setq *pf-layer*  layer
               *pf-style*  style
               *pf-height* (pf:text-height (pf:xf-hplot xf)))
         (prompt (strcat "\nLayer " layer
                         (if clayer-p " (current)" "")
                         ", style " style
                         ", text height " (rtos *pf-height* 2 2) "."))
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
                         (strcat "\nLabel [All/Pick] structures on '"
                                 primary "' <Pick>: ")))
            (if (null mode) (setq mode "Pick"))
            (prompt "\nIndexing structures for ranking...")
            (setq inlets (pflabel:gather-inlets)
                  index  (pflabel:index-stations inlets lines))
            (list (cons 'xform    xf)
                  (cons 'anchor   anchor)
                  (cons 'lines    lines)
                  (cons 'primary  primary)
                  (cons 'mode     mode)
                  (cons 'inlets   inlets)
                  (cons 'index    index)
                  (cons 'clayer-p clayer-p)
                  ;; ONE scan for the top-of-grid probe; pf:top-at folds
                  ;; over this per station (grids have STEPPED tops)
                  (cons 'toplines (pf:top-lines))
                  (cons 'fmt      (pflabel:label-fmt s))))))))))


;;; ==========================================================================
;;; SECTION 4  --  Per-structure labeling  (engine unchanged from v3)
;;; ==========================================================================

(defun pflabel:ranks-for (line-infos context / index)
  (setq index (cdr (assoc 'index context)))
  (mapcar
    '(lambda (li)
       (pf:rank-on-line (cadr li)
                        (cdr (assoc (car li) index))
                        *pf-rank-ascending* *pf-range-eps*))
    line-infos))

(defun pflabel:process-structure (block-ename context
                                   / ed pt name xf gtop primary hits primhit
                                     others sta-infos alpha-infos names ranks
                                     rule size id px basey topy res e2
                                     offset gapn)
  (setq ed      (entget block-ename)
        pt      (cdr (assoc 10 ed))
        name    (cdr (assoc 2 ed))
        xf      (cdr (assoc 'xform context))
        primary (cdr (assoc 'primary context))
        hits    (pf:lines-at-point pt (cdr (assoc 'lines context))))
  (setq primhit (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
  ;; label X = transform; label Y = the TOP-OF-GRID PROBE at that station.
  ;; Grid tops STEP, so the stored top is nominal only -- each label sits
  ;; on the top of the grid AT ITS STATION.
  (if primhit
    (setq px   (pf:station->profile-x (cadr primhit) xf)
          gtop (pf:top-at px (pf:xf-basey xf)
                          (+ (pf:grid-top-y xf)
                             (* *pfg-top-margin* (pf:xf-sf xf)))
                          (cdr (assoc 'toplines context)))))
  (cond
    ((null hits)
     (prompt (strcat "\n  " name " -- not on any named centerline; skipped.")))
    ((null primhit)
     (prompt (strcat "\n  " name " is on line(s) "
                     (pf:join (mapcar 'car hits) ",")
                     " but the profiled line is '" primary "'; skipped.")))
    ((null gtop)
     (prompt (strcat "\n  " name " -- no " *pfg-mjr-layer*
                     " top found at sta "
                     (pf:fmt-station (cadr primhit)) "; skipped.")))
    (T
     (setq others      (vl-remove primhit hits)
           sta-infos   (cons primhit
                             (pf:sort-line-infos-alpha others))
           alpha-infos (pf:sort-line-infos-alpha hits)
           names       (mapcar 'car alpha-infos)
           ranks       (pflabel:ranks-for alpha-infos context)
           rule        (pf:rule-for name *pf-rule-table*)
           size        (pf:rule-size name rule)
           id          (pf:combine-id names ranks))
     (if (null rule)
       (prompt (strcat "\n  " name " matches no label rule -- skipped."))
       (progn
         (setq offset (* *pf-height* *pf-offset-factor*)
               gapn   (* *pf-height* *pf-gap-rest-factor*))
         ;; text baseline sits `offset` above the grid top; the station line
         ;; runs from the grid top up to the first row's text top.
         (setq basey (+ gtop offset)
               res   (pfd:draw-label-stack
                       px basey
                       (pf:build-label-rows sta-infos rule size id
                                            (cdr (assoc 'fmt context)))
                       *pf-layer* *pf-style* *pf-height* offset gapn 'ML)
               topy  (car res))
         (setq *pflabel-run-ents* (append (cdr res) *pflabel-run-ents*))
         (setq e2 (pfd:station-line px gtop topy *pf-layer*))
         (if e2 (setq *pflabel-run-ents* (cons e2 *pflabel-run-ents*)))
         (prompt (strcat "\n  Labeled " id ".")))))))


;;; ==========================================================================
;;; SECTION 5  --  Modes + command
;;; ==========================================================================

(defun pflabel:label-pick (context / e ent ed)
  (prompt "\nPick structures to label (Enter to finish).")
  (while (setq e (entsel "\nSelect structure: "))
    (setq ent (car e) ed (entget ent))
    (cond
      ((/= (cdr (assoc 0 ed)) "INSERT")
       (prompt "\n  Not a block -- skipped."))
      ((null (pf:rule-for (cdr (assoc 2 ed)) *pf-rule-table*))
       (prompt (strcat "\n  Unknown structure block "
                       (cdr (assoc 2 ed)) " -- skipped.")))
      (T (pflabel:process-structure ent context))))
  (princ))

(defun pflabel:label-all (context / lines primary inlets pt hits ph pending e pr)
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
  (prompt (strcat "\nLabeling " (itoa (length pending))
                  " structure(s) on '" primary "'..."))
  (foreach pr pending (pflabel:process-structure (cadr pr) context))
  (princ))

;; (pflabel:write-pass ctx) -> nil
;;   Records the pass + writes STATUS.  A label pass validates its own
;;   inputs and writes status AFTER, so labeling can never be older than
;;   its check.
(defun pflabel:write-pass (ctx / anchor clayer-p allmode handles old meta
                            stored cur state findings e)
  (setq anchor   (cdr (assoc 'anchor ctx))
        clayer-p (cdr (assoc 'clayer-p ctx))
        allmode  (= (cdr (assoc 'mode ctx)) "All")
        handles  '())
  (foreach e *pflabel-run-ents*
    (if (entget e) (setq handles (cons (pf:handle e) handles))))
  (cond
    (clayer-p
     ;; fire-and-forget: record THAT it ran + where; no handles
     (pfa:pass-put anchor "LABEL-CLAYER" *pf-layer* T '()))
    (T
     ;; Pick mode appends to the existing ledger; All mode replaced it
     (if (and (not allmode)
              (setq old (pfa:pass-handles anchor "LABEL")))
       (setq handles (append old handles)))
     (pfa:pass-put anchor "LABEL" *pf-layer* nil handles)))
  ;; ---- input validation -> STATUS ---------------------------------------
  (setq meta    (pfa:meta-get anchor)
        stored  (if (assoc 301 meta) (cdr (assoc 301 meta)) "")
        cur     (pf:checksum-file (cdr (assoc 1 meta)))
        findings '())
  (cond
    ((= stored "")
     (setq state 0
           findings '("no .cl checksum on record (pre-V4 anchor) -- run PFSETUP")))
    ((null cur)
     (setq state 2
           findings '(".cl on record could not be read for checksum")))
    ((= stored cur)
     (setq state 1))
    (T
     (setq state 2
           findings '(".cl content CHANGED since setup -- stations may be stale; re-run PFSETUP"))))
  (pfa:status-put anchor state findings)
  (prompt (strcat "\nPass recorded.  Status: " (pfa:status-label state)))
  (foreach e findings (prompt (strcat "\n  FINDING: " e)))
  (princ))

(defun c:PFLABEL ( / anchor ctx n)
  (setq *pflabel-prev-error* *error*
        *error*               pflabel:*error*
        *pflabel-undo-open*  nil)
  (pf:load-apis)
  (setq anchor (pfa:pick-anchor
                 "\nSelect profile grid anchor (Enter to list): "))
  ;; registry list: choosing an unplaced profile places it on the fly
  (if (null anchor) (setq anchor (pfs:choose-or-place)))
  (if (null anchor)
    (prompt "\nNo placed grid -- run PFSETUP.")
    (progn
      (setq ctx (pflabel:setup anchor))
      (if ctx
        (progn
          (setq *pflabel-run-ents* '())
          (command "_.UNDO" "_Begin")
          (setq *pflabel-undo-open* T)
          ;; All + derived layer = replace this pass's previous output
          ;; (erase-by-handle; hand work and CLAYER output are untouched)
          (if (and (= (cdr (assoc 'mode ctx)) "All")
                   (not (cdr (assoc 'clayer-p ctx))))
            (progn
              (setq n (pfa:erase-pass anchor "LABEL"))
              (if (> n 0)
                (prompt (strcat "\nReplaced previous label pass ("
                                (itoa n) " entities erased by handle).")))))
          (if (= (cdr (assoc 'mode ctx)) "All")
            (pflabel:label-all ctx)
            (pflabel:label-pick ctx))
          (pflabel:write-pass ctx)
          (command "_.UNDO" "_End")
          (setq *pflabel-undo-open* nil)))))
  (setq *error* *pflabel-prev-error*)
  (princ))

(defun c:PFL () (c:PFLABEL))

(princ "\npflabel.lsp loaded (V4, anchor-driven).  Commands: PFLABEL (PFL), PFLABELSET.")
(princ)
;;; ==========================================================================
;;; end of pflabel.lsp
;;; ==========================================================================
