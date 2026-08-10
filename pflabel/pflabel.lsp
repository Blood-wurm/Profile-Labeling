;;; ==========================================================================
;;; pflabel.lsp  --  C:PFLABEL : top-of-grid structure labels
;;;                  Dialogs: pf_run, pflabel_settings (PFLABELSET).
;;; Load position 7 of 10: after pfsetup, before pfxlabel.
;;; Model, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)

;; Run-scoped state (set fresh by every command run).
(setq *pf-layer*  "PF-ANNO")     ; placeholder; pflabel:setup overwrites it every
                                 ; run from *pf-anno-layer* (pftools-cfg)
(setq *pf-style*  "L080")
(setq *pf-height* 1.60)
(if (not (boundp '*pflabel-run-ents*)) (setq *pflabel-run-ents* '()))


;;; ==========================================================================
;;; SECTION 1  --  Esc ledger flush  (error handling lives in pf:run-command)
;;; ==========================================================================

(if (not (boundp '*pflabel-undo-open*)) (setq *pflabel-undo-open* nil))
(if (not (boundp '*pflabel-run-ctx*))   (setq *pflabel-run-ctx* nil))

;; (pflabel:flush-pass) -> nil   The Esc ledger flush (pf:run-command hook).
;;   Writes the pass ledger for whatever got drawn before the Esc, INSIDE the
;;   still-open undo group (entmakex/dictadd are *error*-legal).  The engine
;;   publishes *pflabel-run-ctx* and clears it on normal exit, so this fires
;;   only on a genuine mid-run interrupt.
(defun pflabel:flush-pass ()
  (if (and *pflabel-undo-open* *pflabel-run-ctx*)
    (progn (pflabel:write-pass *pflabel-run-ctx*)
           (setq *pflabel-run-ctx* nil)))
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
                  "\\n\\nLayer: ALL label output goes to PF-ANNO (no-plot, "
                  "green) unless 'Use current layer' is on -- then it goes to "
                  "the current layer and the pass is untracked.  The Layer "
                  "field itself is retired and no longer read."
                  "\\nStyle must exist in the drawing.\\n\\n"
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

;; The line-table builder and the inlet gather moved to pfanchor SECTION 4b as
;; pfa:build-lines / pfa:gather-inlets, 2026-07-27.  Both were always registry
;; and selection knowledge rather than label knowledge, and the membership index
;; writer -- position 4 -- cannot reach up to this file at 7.  No alias left
;; behind; same precedent as pfa:entry-cl, moved out of pfxlabel 2026-07-26.

;; THE WHOLE GATHER lives in pfanchor SECTION 4c -- line-loaded-p,
;; registry-pairs, pending, pass-xs, labeled-x-p, cluster-xs, orphan-xs,
;; inlet-sig, lines-sig, the memo pair, pend-for, status-for and gather-compute,
;; all pfa:.  It is membership-and-ledger knowledge, and the palette at position
;; 11 needs per-target counts that pfanchor at 4 can serve and this file at 7
;; cannot.  No aliases left behind.
;; index-stations followed them on 2026-08-03, as pfa:index-stations /
;; pfa:index-for.  It was kept back as combined-ID RANKING rather than
;; membership, but the palette needs the ranked NAME for its Item column and
;; position 11 cannot reach position 7; pfreport and pf2sew were already
;; reaching across for it too.  It is no longer the largest unmemoised consumer
;; of membership: on the primary-line paths pfa:pending folds the index out of
;; the walk it was already making, and the gather memo holds it.
;; No alias left behind.

(defun pflabel:label-fmt (settings util)
  (mapcar
    '(lambda (k)
       (cons k (pf:subst-token (cdr (assoc k settings)) "[util]" util)))
    '("sta_pre" "sta_suf" "con_suf" "gl_suf")))


;;; ==========================================================================
;;; SECTION 3b  --  The run dialog  (pf_run; shared with PFINVERT)
;;; ==========================================================================
;;; Dialog-first every run (the Carlson idiom).  The target popup is the
;;; registry; the structure LIST replaces the old All/Pick keyword.  Rows
;;; are marked [LABELED] from the pass ledger: any tracked entity of this
;;; command's pass within eps of the station X.  Advisory only -- CLAYER
;;; passes are untracked and never marked.

;; pending / pass-xs / labeled-x-p / cluster-xs / orphan-xs -> pfanchor 4c.

;; ---- Run dialog: RENDER + handlers (rd-* live in pflabel:run-dialog) -------
;; rd-fill only PAINTS; rd-compute does the heavy work BEFORE new_dialog.

;; Column 1 is the DRAWN NAME, not the block name -- the same string the label
;; will carry and the same one the palette's Item column shows, off the row's
;; own hits (pfa:pending position 3) so painting costs no membership work.
(defun pflabel:rd-fill ( / i p v ndone)
  (setq i 0)
  (start_list "run_list")
  (foreach p rd-pend
    (add_list (strcat (pfset:pad (pfa:id-for-hits (nth 3 p) rd-index) 22)
                      (pfset:pad (pf:fmt-station (car p)) 16)
                      (if (nth i rd-status) "[LABELED]" "")))
    (setq i (1+ i)))
  (end_list)
  (setq ndone 0)
  (foreach v rd-status (if v (setq ndone (1+ ndone))))
  (set_tile "run_count"
            (strcat (itoa (length rd-pend)) " structure(s) on '" rd-primary
                    "'; " (itoa ndone) " already labeled."))
  ;; the drift echo's dialog half -- the error tile is already here and is the
  ;; only thing the user is looking at while the modal is up
  (set_tile "error"
            (if rd-orphans
              (strcat (itoa (length rd-orphans))
                      " label(s) with no structure -- something moved.")
              ""))
  (princ))

;; ALL heavy work, BEFORE new_dialog.  -> T when there is a list; nil on no line.
;; This is what keeps Road-API / recon work OUT of the dialog-init block.
;;; The gather memo, its two signatures, the memo pair, pend-for, status-for
;;; and gather-compute all moved to pfanchor SECTION 4c on 2026-07-29, as
;;; *pfa-gather-memo* / pfa:inlet-sig / pfa:lines-sig / pfa:memo-get /
;;; pfa:memo-put / pfa:pend-for / pfa:status-for / pfa:gather-compute.
;;; Rationale lives in that section; no aliases left behind.

;; Binds the shared compute into PFLABEL's dialog locals.  -> T | nil
(defun pflabel:rd-compute ( / g)
  (setq g (pfa:gather-compute rd-anchor rd-pass rd-primary
                                  rd-lines rd-inlets))
  (if (null g)
    (progn (setq rd-pend '() rd-status '() rd-orphans '() rd-index '()) nil)
    (progn (setq rd-pend    (car g)
                 rd-status  (cadr g)
                 rd-orphans (caddr g)
                 ;; memo hit off the gather that just ran -- rd-fill needs it to
                 ;; name the rows, and pflabel:setup reads the same entry later
                 rd-index   (pfa:index-for rd-primary rd-lines rd-inlets))
           T)))

(defun pflabel:rd-sel ( / s idxs out i)
  (setq s (get_tile "run_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select structures in the list first -- or Label All.")
    (progn
      (setq idxs (read (strcat "(" s ")")) out '())
      (foreach i idxs (setq out (cons (nth i rd-pend) out)))
      (setq rd-res (list (cons 'mode   "Sel")
                         (cons 'sel    (reverse out))
                         (cons 'lines  rd-lines)
                         (cons 'inlets rd-inlets)))
      (done_dialog 1))))

(defun pflabel:rd-all ()
  (if (null rd-pend)
    (set_tile "error" "No structures on this line -- nothing to label.")
    (progn
      (setq rd-res (list (cons 'mode   "All")
                         (cons 'sel    rd-pend)
                         (cons 'lines  rd-lines)
                         (cons 'inlets rd-inlets)))
      (done_dialog 1))))

;; (pflabel:run-dialog title passname anchor) -> result alist | nil
;;   Target is ALREADY resolved (pfs:choose-or-place, before this call).  Line
;;   table, inlets, pending and recon all run BEFORE new_dialog -- the init
;;   block only paints, which is what cured the ghost-dropdown freeze.  No
;;   target popup: this dialog shows ONE target's structures.  The line table
;;   is the ONE registry builder (pfa:registry-pairs) plus the primary --
;;   the same build pfi:run-dialog and both setups use.
(defun pflabel:run-dialog (title passname anchor
                           / rd-anchor rd-primary rd-pass rd-lines rd-inlets
                             rd-pend rd-status rd-orphans rd-index rd-res
                             dcl_id xf cl pairs result)
  (setq rd-anchor anchor rd-pass passname rd-res nil
        xf        (pfa:anchor->xform anchor))
  (cond
    ((null xf)
     (prompt "\nTarget grid record unreadable -- cannot label.") nil)
    ((null (setq cl (pf:xf-get 'clfile xf)))
     (prompt "\nNo .cl on record for this target -- run PFSETUP (edit).") nil)
    (T
     (setq rd-primary (pf:xf-get 'name xf)
           pairs      (pf:dedupe-pairs
                        (cons (cons cl rd-primary)
                              (pfa:registry-pairs cl)))
           rd-lines   (pfa:build-lines pairs)
           rd-inlets  (pfa:gather-inlets))
     (if (null (pflabel:rd-compute))
       (progn
         (prompt (strcat "\nCenterline for '" rd-primary
                         "' could not be read -- nothing to label."))
         nil)
       (progn
         (setq dcl_id (load_dialog (pfset:dcl-file)))
         (if (< dcl_id 0)
           (progn (prompt "\nCould not load pfdialog.dcl.") nil)
           (if (not (new_dialog "pf_run" dcl_id))
             (progn (unload_dialog dcl_id)
                    (prompt "\nCould not open the run dialog.") nil)
             (progn
               (set_tile "run_title" title)
               (pflabel:rd-fill)
               (action_tile "run_sel" "(pflabel:rd-sel)")
               (action_tile "run_all" "(pflabel:rd-all)")
               (action_tile "run_set" "(pflabel:show-dialog)")
               (action_tile "cancel"  "(done_dialog 0)")
               (action_tile "help"
                 (strcat "(pfset:help \"Select rows and Label Selected, or "
                         "Label All for every structure on the primary line.  "
                         "Label All REPLACES this command's previous tracked "
                         "pass; Selected appends.\\n\\n[LABELED] = a tracked "
                         "entity of this command's pass already sits at that "
                         "station (CLAYER passes are untracked, never "
                         "marked).\\n\\nWrong target?  Cancel and rerun.\")"))
               (setq result (vl-catch-all-apply 'start_dialog '()))
               (unload_dialog dcl_id)
               (cond
                 ((vl-catch-all-error-p result)
                  (prompt (strcat "\nDialog error: "
                                  (vl-catch-all-error-message result)))
                  nil)
                 ((= result 1) rd-res)
                 (T nil))))))))))

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
         ;; layer per the settings toggle (Carlson-style "use current layer");
         ;; otherwise THE annotation layer -- no longer derived from the
         ;; utility type (2026-07-29)
         (setq clayer-p (= (cdr (assoc "use_clayer" s)) "1")
               layer    (if clayer-p (getvar "CLAYER") (pfd:anno-layer)))
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
            (prompt "\nIndexing structures for ranking...")
            (setq inlets (if preinlets preinlets (pfa:gather-inlets))
                  ;; memo hit whenever the run dialog got here first, which is
                  ;; every path but a caller handing us its own line table
                  index  (pfa:index-for primary lines inlets))
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
                  (cons 'fmt (pflabel:label-fmt s (pf:xf-get 'type xf)))))))))))


;;; ==========================================================================
;;; SECTION 4  --  Per-structure labeling  (engine unchanged from v3)
;;; ==========================================================================

;; ranks-for retired 2026-08-03 -- rank + alpha-sort + combine-id are one step
;; and live together in pfa:id-for-hits, which the palette and the run dialog
;; call as well.

(defun pflabel:process-structure (block-ename context
                                   / ed pt name xf gtop primary hits primhit
                                     others sta-infos
                                     rule size id px basey topy res e2
                                     offset gapn)
  (setq ed      (entget block-ename)
        pt      (cdr (assoc 10 ed))
        name    (cdr (assoc 2 ed))
        xf      (cdr (assoc 'xform context))
        primary (cdr (assoc 'primary context))
        hits    (pfa:lines-at block-ename pt (cdr (assoc 'lines context))))
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
     (setq others    (vl-remove primhit hits)
           sta-infos (cons primhit
                           (pf:sort-line-infos-alpha others))
           rule      (pf:rule-for name *pf-rule-table*)
           size      (pf:rule-size name rule)
           id        (pfa:id-for-hits hits (cdr (assoc 'index context))))
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
         ;; THE TOP-UP.  Engine side, inside the open undo group, so writing is
         ;; legal here in a way it never is on the gather path.  The index
         ;; therefore fills in along the routes actually driven; nothing walks
         ;; every structure in normal use, which is what PFINDEX is for.
         ;; No-op when the record is already current, and catch-wrapped inside
         ;; pfa:memb-sync so a locked-layer structure costs a cache entry, not
         ;; the run.
         (pfa:memb-sync block-ename pt (cdr (assoc 'lines context)) *pfa-roster*)
         (prompt (strcat "\n  Labeled " id "."))
         ;; verification parade (no-op unless "Zoom To" on).  ONE RULE, all
         ;; three commands: grid base up to grid top OR the drawn stack top,
         ;; whichever is higher -- the structure is verified in grid context,
         ;; not as a keyhole on the text alone.
         (pf:zoom-item px
                       (pf:xf-basey xf)
                       (max topy (pf:grid-top-y xf))))))))


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

;; (pflabel:label-all context) -> nil
;;   The ticket ALREADY carries this list: pflabel:rd-all files rd-pend (the
;;   gather's pfa:pending result, sorted by station) under 'sel for mode
;;   "All" exactly as rd-sel does for "Sel".  Recomputing it here was a second
;;   full inlet x line membership scan -- every one of those points costs a
;;   cl_location_at_pt.  Use the ticket; rebuild ONLY when a caller hands us a
;;   mode-"All" ticket with no 'sel (nothing does today, but pflabel:run is the
;;   documented entry point for the palette's deferred command too).
(defun pflabel:label-all (context / lines primary inlets pt hits ph pending e pr)
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
  (prompt (strcat "\nLabeling " (itoa (length pending))
                  " structure(s) on '" primary "'..."))
  (foreach pr pending (pflabel:process-structure (cadr pr) context))
  (princ))

;; (pflabel:write-pass ctx) -> nil
;;   Records the pass + writes STATUS.  A label pass validates its own
;;   inputs and writes status AFTER, so labeling can never be older than
;;   its check.
(defun pflabel:write-pass (ctx / anchor clayer-p allmode handles old meta
                            stored res state findings e)
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
  ;; ---- input validation -> STATUS_LABEL ---------------------------------
  ;; PFLABEL's input is the .cl and nothing else.  This used to write the one
  ;; shared "STATUS" record, so a later PFINVERT run about a .pro erased it.
  (setq meta   (pfa:meta-get anchor)
        stored (if (assoc 301 meta) (cdr (assoc 301 meta)) "")
        res    (pfa:status-check anchor "LABEL" (cdr (assoc 1 meta)) stored)
        state  (car res)
        findings (cdr res))
  (pfa:status-put anchor "LABEL" state stored findings)
  (prompt (strcat "\nPass recorded.  Status: " (pfa:status-label state)))
  (foreach e findings (prompt (strcat "\n  FINDING: " e)))
  (princ))

;; (pflabel:run anchor rd) -> nil
;;   The ENGINE: consumes the gathered order ticket (mode/lines/inlets/sel) and
;;   does all the drawing.  Called by C:PFLABEL after its modal gather, and by
;;   the palette's deferred command with the identical alist.  Assumes a command
;;   context under pf:run-command (pf:run-error installed) -- the CALLER owns
;;   the *error*/echo wrapper, so this body is unchanged from the old inline
;;   form.  Publishes *pflabel-run-ctx* so an Esc mid-run flushes the ledger.
(defun pflabel:run (anchor rd / ctx n)
  (setq ctx (pflabel:setup anchor (cdr (assoc 'mode rd))
                           (cdr (assoc 'lines rd))
                           (cdr (assoc 'inlets rd))))
  (if ctx
    (progn
      ;; resolve INSIDE the ctx guard: a nil-ctx abort must not consume a
      ;; pending one-shot palette override
      (pf:zoom-resolve nil)          ; PFLABEL does NOT parade unless the palette asks
      (setq ctx (cons (cons 'sel (cdr (assoc 'sel rd))) ctx))
      (setq *pflabel-run-ents* '())
      (setq *pflabel-run-ctx* ctx)        ; publish for the Esc flush
      (pf:undo-begin '*pflabel-undo-open*)
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
      (pf:zoom-begin (pf:xf-sf (cdr (assoc 'xform ctx)))) ; snapshot + frame floor
      (if (= (cdr (assoc 'mode ctx)) "All")
        (pflabel:label-all ctx)
        (pflabel:label-sel ctx))
      (pf:zoom-end)                   ; restore the pre-run view after the parade
      (pflabel:write-pass ctx)
      (setq *pflabel-run-ctx* nil)      ; normal exit: the Esc flush disarms
      (pf:undo-end '*pflabel-undo-open*)))
  (princ))

;; (pflabel:cmd) -> nil   The command body, run under pf:run-command.
(defun pflabel:cmd ( / anchor rd)
  (setq *pflabel-undo-open* nil)
  ;; pick-first (PFXLABEL parity): choose/place the target, THEN list only its
  ;; structures.  choose-or-place anchors a registered pick on the fly.
  (setq anchor (pfs:choose-or-place))
  (if (null anchor)
    (prompt "\nPFLABEL cancelled -- no target.")
    (progn
      (setq rd (pflabel:run-dialog
                 "PFLABEL -- structure labels at the top of the grid"
                 "LABEL" anchor))
      (if (null rd)
        (prompt "\nPFLABEL cancelled.")
        (pflabel:run anchor rd))))       ; gather done -> hand to the engine
  (princ))

(defun c:PFLABEL ()
  (pf:run-command "PFLABEL" 'pflabel:flush-pass 'pflabel:cmd))

(defun c:PFL () (c:PFLABEL))

(princ "\npflabel.lsp loaded (V4, anchor-driven).  Commands: PFLABEL (PFL), PFLABELSET.")
(princ)
;;; ==========================================================================
;;; end of pflabel.lsp
;;; ==========================================================================
