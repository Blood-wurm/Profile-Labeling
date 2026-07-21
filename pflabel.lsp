;;; ==========================================================================
;;; pflabel.lsp  --  C:PFLABEL : top-of-grid structure labels  (V4)
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings loaded
;;; first.  Dialog: pflabel_settings in pfdialog.dcl (PFLABELSET).
;;;
;;; V4 PIVOT: the command reads the ANCHOR.  Everything the old dialogs
;;; gathered per run (grid corners, start station, datum, scales, primary
;;; .cl) lives in the record PFSETUP wrote.  The run is DIALOG-FIRST
;;; (pf_run, shared with PFINVERT): target popup = the registry, and a
;;; multi-select STRUCTURE LIST replaces the old All/Pick keyword.  The
;;; optional screen pick only preselects the popup.
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
  (pfa:undo-cleanup)                ; closes ANY pf group, incl. a nested one
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
        (action_tile "help"
          (strcat "(pfset:help \"Label text prefixes/suffixes feed PFLABEL's "
                  "rows; greyed fields are owned by the firm's rule table."
                  "\\n\\nLayer: the run derives <TYPE>-TEXT_P from the "
                  "anchor unless 'Use current layer' is on (then output is "
                  "untracked).\\nStyle must exist in the drawing.\\n\\n"
                  "Load/Save move the whole settings file.\")"))
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
;;   Geometry comes from the cached GEOM store (pf:cl-geom) -- the proximity
;;   filter's verts are the .cl's OWN sampled shape, not a hunted-for drawn
;;   twin, so no whole-drawing scan and no Road-API re-sampling on a cache hit.
(defun pflabel:build-lines (pairs / tbl file nm geom rng vts entry p)
  (setq tbl '())
  (foreach p pairs
    (setq file (car p) nm (cdr p))
    (if (setq geom (pf:cl-geom file))
      (progn
        (setq rng   (car geom)
              vts   (cdr geom)
              entry (list file nm (car rng) (cadr rng) vts)
              tbl   (cons entry tbl))
        (prompt (strcat "\nLoaded line '" nm "' (Sta " (pf:fmt-station (car rng))
                        " to " (pf:fmt-station (cadr rng)) ")"
                        (if vts "." "  [geometry unavailable -- proximity filter off]."))))
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


;;; ==========================================================================
;;; SECTION 3b  --  The run dialog  (pf_run; shared with PFINVERT)
;;; ==========================================================================
;;; Dialog-first every run (the Carlson idiom).  The target popup is the
;;; registry; the structure LIST replaces the old All/Pick keyword.  Rows
;;; are marked [LABELED] from the pass ledger: any tracked entity of this
;;; command's pass within eps of the station X.  Advisory only -- CLAYER
;;; passes are untracked and never marked.

;; (pflabel:pending inlets lines primary) -> ((sta ename blkname) ...)
;;   Every structure on the PRIMARY line, sorted by station.
(defun pflabel:pending (inlets lines primary / out e pt hits ph)
  (setq out '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (pf:lines-at-point pt lines)
          ph   (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
    (if ph (setq out (cons (list (cadr ph) e (cdr (assoc 2 (entget e))))
                           out))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

;; (pflabel:pass-xs anchor passname) -> X ordinates of the pass's entities
(defun pflabel:pass-xs (anchor passname / out h e ed p)
  (setq out '())
  (foreach h (pfa:pass-handles anchor passname)
    (if (and (setq e (handent h)) (setq ed (entget e))
             (setq p (cdr (assoc 10 ed))))
      (setq out (cons (car p) out))))
  out)

;; (pflabel:labeled-x-p x xs eps) -> T when a pass entity sits at this X
(defun pflabel:labeled-x-p (x xs eps / found v)
  (setq found nil)
  (foreach v xs
    (if (<= (abs (- v x)) eps) (setq found T)))
  found)

;; (pflabel:rd-fill) -> nil   Repopulate the structure list for the current
;;   target.  rd-* live in pflabel:run-dialog (dynamic scope).
(defun pflabel:rd-fill ( / r primary placed xf xs eps ndone p i v)
  (setq r       (nth rd-cur rd-reg)
        primary (cadr r)
        placed  (eq (caddr r) 'PLACED)
        rd-pend (if (pflabel:line-loaded-p primary rd-lines)
                  (pflabel:pending rd-inlets rd-lines primary)
                  'NOLINE))
  (cond
    ((eq rd-pend 'NOLINE)
     (setq rd-pend '())
     (start_list "run_list") (end_list)
     (set_tile "run_count"
               (strcat "Centerline for '" primary
                       "' could not be read -- nothing to list.")))
    (T
     (setq xs  (if placed (pflabel:pass-xs (nth 3 r) rd-pass))
           xf  (if placed (pfa:anchor->xform (nth 3 r)))
           eps (if xf
                 (max *pfa-recon-eps*
                      (* 1.5 (pf:text-height (pf:xf-hplot xf))))
                 *pfa-recon-eps*)
           ndone 0
           rd-status '())
     (foreach p rd-pend
       (setq rd-status
             (append rd-status
                     (list (and placed xf
                                (pflabel:labeled-x-p
                                  (pf:station->profile-x (car p) xf)
                                  xs eps))))))
     (setq i 0)
     (start_list "run_list")
     (foreach p rd-pend
       (add_list (strcat (pfset:pad (caddr p) 22)
                         (pfset:pad (pf:fmt-station (car p)) 16)
                         (cond ((nth i rd-status) "[LABELED]")
                               (placed "")
                               (T "(unplaced grid)"))))
       (setq i (1+ i)))
     (end_list)
     (foreach v rd-status (if v (setq ndone (1+ ndone))))
     (set_tile "run_count"
               (strcat (itoa (length rd-pend)) " structure(s) on '" primary
                       "'"
                       (if placed
                         (strcat "; " (itoa ndone) " already labeled.")
                         "; grid unplaced -- labeling will place it.")))))
  (set_tile "error" "")
  (princ))

(defun pflabel:rd-on-tgt ()
  (setq rd-cur (atoi (get_tile "run_tgt")))
  (pflabel:rd-fill))

(defun pflabel:rd-sel ( / s idxs out i)
  (setq s (get_tile "run_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select structures in the list first -- or Label All.")
    (progn
      (setq idxs (read (strcat "(" s ")")) out '())
      (foreach i idxs (setq out (cons (nth i rd-pend) out)))
      (setq rd-res (list (cons 'entry (nth rd-cur rd-reg))
                         (cons 'mode "Sel")
                         (cons 'sel (reverse out))
                         ;; hand the already-built line table + inlets to setup
                         ;; so it need not rebuild them (dialog built them once)
                         (cons 'lines rd-lines)
                         (cons 'inlets rd-inlets)))
      (done_dialog 1))))

(defun pflabel:rd-all ()
  (if (null rd-pend)
    (set_tile "error" "No structures on this line -- nothing to label.")
    (progn
      (setq rd-res (list (cons 'entry (nth rd-cur rd-reg))
                         (cons 'mode "All")
                         (cons 'sel rd-pend)
                         (cons 'lines rd-lines)
                         (cons 'inlets rd-inlets)))
      (done_dialog 1))))

;; (pflabel:run-dialog title passname pre-anchor) -> result alist | nil
;;   ('entry . registry-row) ('mode . "All"|"Sel") ('sel . pend-subset).
;;   pre-anchor (screen-picked) preselects the target popup.
(defun pflabel:run-dialog (title passname pre-anchor
                           / rd-reg rd-lines rd-inlets rd-pend rd-status
                             rd-cur rd-res rd-pass dcl_id pairs clf at r i
                             result)
  (setq rd-reg (pfa:registry) rd-pass passname rd-res nil)
  (cond
    ((null rd-reg)
     (prompt "\nNothing registered -- run PFSETUP.")
     nil)
    (T
     ;; the line table is target-independent: every registry .cl, once
     (setq pairs '())
     (foreach r rd-reg
       (if (setq clf (pfxl:entry-cl r))
         (setq pairs (cons (cons clf (cadr r)) pairs))))
     (setq pairs     (pf:dedupe-pairs (reverse pairs))
           rd-lines  (pflabel:build-lines pairs)
           rd-inlets (pflabel:gather-inlets))
     ;; preselect: the screen-picked anchor, else the first PLACED entry
     (setq rd-cur nil i 0)
     (if pre-anchor
       (progn
         (setq at (pfa:read-attribs pre-anchor))
         (foreach r rd-reg
           (if (and (null rd-cur)
                    (= (car r) (strcase (pfa:att "UTIL" at)))
                    (= (cadr r) (strcase (pfa:att "LINE" at))))
             (setq rd-cur i))
           (setq i (1+ i)))))
     (setq i 0)
     (foreach r rd-reg
       (if (and (null rd-cur) (eq (caddr r) 'PLACED)) (setq rd-cur i))
       (setq i (1+ i)))
     (if (null rd-cur) (setq rd-cur 0))
     (setq dcl_id (load_dialog (pfset:dcl-file)))
     (if (< dcl_id 0)
       (progn (prompt "\nCould not load pfdialog.dcl.") nil)
       (if (not (new_dialog "pf_run" dcl_id))
         (progn (unload_dialog dcl_id)
                (prompt "\nCould not open the run dialog.") nil)
         (progn
           (set_tile "run_title" title)
           (start_list "run_tgt")
           (foreach r rd-reg (add_list (pfs:reg-item r)))
           (end_list)
           (set_tile "run_tgt" (itoa rd-cur))
           (pflabel:rd-fill)
           (action_tile "run_tgt" "(pflabel:rd-on-tgt)")
           (action_tile "run_sel" "(pflabel:rd-sel)")
           (action_tile "run_all" "(pflabel:rd-all)")
           (action_tile "run_set" "(pflabel:show-dialog)")
           (action_tile "cancel"  "(done_dialog 0)")
           (action_tile "help"
             (strcat "(pfset:help \"Target Profile = the registry; choosing "
                     "an unplaced profile and labeling places it first "
                     "(two corner picks).\\n\\nSelect rows and Label "
                     "Selected, or Label All for every structure on the "
                     "primary line.  Label All REPLACES this command's "
                     "previous tracked pass; Selected appends.\\n\\n"
                     "[LABELED] = a tracked entity of this command's pass "
                     "already sits at that station (CLAYER passes are "
                     "untracked and never marked).\")"))
           (setq result (vl-catch-all-apply 'start_dialog '()))
           (unload_dialog dcl_id)
           (cond
             ((vl-catch-all-error-p result)
              (prompt (strcat "\nDialog error: "
                              (vl-catch-all-error-message result)))
              nil)
             ((= result 1) rd-res)
             (T nil))))))))

;; (pflabel:setup anchor mode prelines preinlets) -> context alist | nil
;;   Everything comes from the record + settings; the mode ("All"/"Sel")
;;   was chosen in the run dialog -- nothing is typed here.  prelines/preinlets
;;   are the run dialog's already-built line table and inlet set: when passed,
;;   setup reuses them instead of rebuilding (the dialog built them once).  A
;;   modal dialog can't change the drawing, and a freshly-placed target's .cl
;;   was already in that table under its identity, so reuse is always safe.
(defun pflabel:setup (anchor mode prelines preinlets
                       / xf cl s style clayer-p layer prim pairs
                         lines primary inlets index d)
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
            (prompt "\nIndexing structures for ranking...")
            (setq inlets (if preinlets preinlets (pflabel:gather-inlets))
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

;; (pflabel:label-sel context) -> nil
;;   Labels the structures picked in the run dialog's list (already sorted
;;   by station).  Replaces the old entsel Pick loop -- when the deferred
;;   "Screen Pick" button lands, it feeds this same path.
(defun pflabel:label-sel (context / sel pr)
  (setq sel (cdr (assoc 'sel context)))
  (prompt (strcat "\nLabeling " (itoa (length sel))
                  " selected structure(s)..."))
  (foreach pr sel (pflabel:process-structure (cadr pr) context))
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

(defun c:PFLABEL ( / pre rd entry anchor ctx n)
  (setq *pflabel-prev-error* *error*
        *error*               pflabel:*error*
        *pflabel-undo-open*  nil)
  (pf:load-apis)
  ;; dialog-first (parity with PFXLABEL): the run dialog's list IS the target
  ;; picker.  pfa:pick-anchor is kept (reserved) for a possible screen-pick
  ;; button later; no pre-anchor means the dialog preselects the first placed.
  (setq pre nil)
  (setq rd (pflabel:run-dialog
             "PFLABEL -- structure labels at the top of the grid"
             "LABEL" pre))
  (if (null rd)
    (prompt "\nPFLABEL cancelled.")
    (progn
      ;; resolve the chosen registry entry: labeling an unplaced profile
      ;; IS consent to place it (dialog -> two corner picks)
      (setq entry  (cdr (assoc 'entry rd))
            anchor (if (eq (caddr entry) 'PLACED)
                     (nth 3 entry)
                     (pfs:place-one (nth 4 entry))))
      (if (null anchor)
        (prompt "\nNo placed grid -- cancelled.")
        (progn
          (setq ctx (pflabel:setup anchor (cdr (assoc 'mode rd))
                                   (cdr (assoc 'lines rd))
                                   (cdr (assoc 'inlets rd))))
          (if ctx
            (progn
              (setq ctx (cons (cons 'sel (cdr (assoc 'sel rd))) ctx))
              (setq *pflabel-run-ents* '())
              (command "_.UNDO" "_Begin")
              (setq *pflabel-undo-open* T)
              ;; All + derived layer = replace this pass's previous output
              ;; (erase-by-handle; hand work and CLAYER output untouched)
              (if (and (= (cdr (assoc 'mode ctx)) "All")
                       (not (cdr (assoc 'clayer-p ctx))))
                (progn
                  (setq n (pfa:erase-pass anchor "LABEL"))
                  (if (> n 0)
                    (prompt (strcat "\nReplaced previous label pass ("
                                    (itoa n)
                                    " entities erased by handle).")))))
              (if (= (cdr (assoc 'mode ctx)) "All")
                (pflabel:label-all ctx)
                (pflabel:label-sel ctx))
              (pflabel:write-pass ctx)
              (command "_.UNDO" "_End")
              (setq *pflabel-undo-open* nil)))))))
  (setq *error* *pflabel-prev-error*)
  (princ))

(defun c:PFL () (c:PFLABEL))

(princ "\npflabel.lsp loaded (V4, anchor-driven).  Commands: PFLABEL (PFL), PFLABELSET.")
(princ)
;;; ==========================================================================
;;; end of pflabel.lsp
;;; ==========================================================================
