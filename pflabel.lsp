;;; ==========================================================================
;;; pflabel.lsp  --  C:PFLABEL : top-of-grid structure labels
;;; --------------------------------------------------------------------------
;;; Requires pftools-lib.lsp (the shared engine) and pfdialog.lsp (the
;;; settings + data-file dialogs) to be loaded first.
;;;
;;; Run order (Carlson pattern -- dialogs first, graphics last):
;;;   1. Main dialog: text properties, TIN surface, primary centerline,
;;;      secondary centerlines.
;;;   2. Grid dialog: start station, datum elevation, H/V scales.
;;;   3. Graphic picks: grid lower-left corner + a point on the top border.
;;;   4. All/Pick keyword prompt on the command line.
;;;   5. Label run inside a single undo group (one U reverses the pass).
;;;
;;; Label composition:
;;;   STA rows   -> primary line FIRST, remaining lines ALPHABETICAL.
;;;   Combined ID-> ALPHABETICAL by line name (stable across profiles).
;;;   Row text   -> user prefix/suffix from the dialog around engine values;
;;;                 [line] in the station suffix substitutes per row.
;;;
;;; Inverts are NOT drawn here (second-pass tool; the xform now carries
;;; base-y / datum / v-scale for it).
;;;
;;; STATUS: not yet run in a live drawing. Test on a scratch copy first.
;;; ==========================================================================

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  firm-standard constants and the honest assumptions.
;;; --------------------------------------------------------------------------

(setq *pf-layer* "STORM-TEXT_P")   ; label layer (overridden by the dialog)
(setq *pf-style* "L080")           ; text style  (overridden by the dialog)
(setq *pf-height* 1.60)             ; text height (model units)


;;; ==========================================================================
;;; ERROR HANDLING  --  cleanup on Esc / error anywhere in the command
;;; ==========================================================================

(if (not (boundp '*pflabel-undo-open*)) (setq *pflabel-undo-open* nil))

;; (pflabel:*error* msg)  --  installed by C:PFLABEL.  Unloads the TIN,
;;   closes an open undo group, and restores the previous handler.
(defun pflabel:*error* (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFLABEL error: " msg)))
  (vl-catch-all-apply 'pf:tin-unload '())
  (if *pflabel-undo-open*
    (progn
      (command-s "_.UNDO" "_End")
      (setq *pflabel-undo-open* nil)))
  (setq *error* *pflabel-prev-error*)
  (princ))


;;; ==========================================================================
;;; SETUP  --  one-time context for a labeling run
;;; ==========================================================================

;; (pflabel:apply-text-props settings) -> T | nil
;;   Style MUST exist in the drawing (we can't invent a font); the layer is
;;   created if missing (default properties), matching Carlson behavior.
(defun pflabel:apply-text-props (settings / layer style)
  (setq layer (cdr (assoc "layer" settings))
        style (cdr (assoc "style" settings)))
  (cond
    ((or (null style) (= style "")
         (null (tblsearch "STYLE" style)))
     (prompt (strcat "\nText style '" (if style style "")
                     "' not found in this drawing -- aborting."))
     nil)
    ((or (null layer) (= layer ""))
     (prompt "\nNo label layer specified -- aborting.")
     nil)
    (T
     (if (null (tblsearch "LAYER" layer))
       (progn
         (entmake (list '(0 . "LAYER")
                        '(100 . "AcDbSymbolTableRecord")
                        '(100 . "AcDbLayerTableRecord")
                        (cons 2 layer)
                        '(70 . 0)
                        '(62 . 7)
                        (cons 6 "Continuous")))
         (prompt (strcat "\nCreated layer '" layer "'."))))
     (setq *pf-layer* layer
           *pf-style* style)
     T)))

;; (pflabel:pick-grid-points) -> (ll top) | nil   (nil-checked graphic picks)
(defun pflabel:pick-grid-points ( / ll top)
  (setq ll (getpoint "\nPick grid LOWER-LEFT corner: "))
  (if (null ll)
    (progn (prompt "\nNo point picked -- aborting.") nil)
    (progn
      (setq top (getpoint ll "\nPick a point on the grid TOP border: "))
      (if (null top)
        (progn (prompt "\nNo point picked -- aborting.") nil)
        (list ll top)))))

;; (pflabel:dedupe-pairs pairs) -> pairs with duplicate .cl paths dropped
;;   (keeps the FIRST occurrence, so the primary entry wins on collision)
(defun pflabel:dedupe-pairs (pairs / out)
  (setq out '())
  (foreach p pairs
    (if (not (assoc (car p) out)) (setq out (cons p out))))
  (reverse out))

;; (pflabel:build-lines pairs) -> list of (clfile name start end verts)
;;   Consumes (path . name) pairs collected by the dialog.  For each, reads
;;   the station range and binds the .cl to its drawing polyline via
;;   pf:attach-corridor so membership can pre-filter without Road-API spam.
(defun pflabel:build-lines (pairs / tbl file nm rng entry)
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

;; (pflabel:line-loaded-p name lines) -> entry | nil
(defun pflabel:line-loaded-p (name lines)
  (car (vl-member-if '(lambda (e) (= (cadr e) name)) lines)))

;; (pflabel:gather-inlets) -> list of block enames whose name is a known type
(defun pflabel:gather-inlets ( / ss i e nm lst)
  (setq ss (ssget "_X" '((0 . "INSERT"))) lst '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq e  (ssname ss i)
            nm (cdr (assoc 2 (entget e))))
      (if (pf:type-entry nm *pf-type-table*)
        (setq lst (cons e lst)))
      (setq i (1+ i))))
  (reverse lst))

;; (pf:idx-add idx name val) -> idx   (prepends val to name's bucket)
(defun pf:idx-add (idx name val / cell)
  (if (setq cell (assoc name idx))
    (subst (cons name (cons val (cdr cell))) cell idx)
    (cons (list name val) idx)))

;; (pflabel:index-stations inlets line-table) -> (name . sorted-stations)*
;;   Builds, per line, the ascending list of every structure station on it,
;;   so any structure can be ranked without re-scanning the drawing.
(defun pflabel:index-stations (inlets line-table / idx pt hits)
  (setq idx '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (pf:lines-at-point pt line-table))
    (foreach h hits                         ; h = (name station)
      (setq idx (pf:idx-add idx (car h) (cadr h)))))
  (mapcar '(lambda (pair) (cons (car pair) (vl-sort (cdr pair) '<))) idx))

;; (pflabel:label-fmt settings) -> alist of the six prefix/suffix strings
(defun pflabel:label-fmt (settings)
  (mapcar
    '(lambda (k) (cons k (cdr (assoc k settings))))
    '("sta_pre" "sta_suf" "con_pre" "con_suf" "gl_pre" "gl_suf")))

;; (pflabel:setup) -> context alist | nil
;;   Order:  main dialog  ->  grid dialog  ->  graphic picks  ->  surface +
;;           line table  ->  mode  ->  structure index.
(defun pflabel:setup ( / s g tin prim cl-pairs pts ll top xf pairs lines
                          primary mode inlets index)
  ;; 1. Main dialog: settings + TIN + primary + secondary centerlines.
  (setq s (pflabel:show-dialog))
  (cond
    ((null s) (prompt "\nPFLABEL cancelled.") nil)
    ;; 2. Grid dialog: (sta0 datum hplot vplot) | nil.  H/V are PLOT scales
    ;;    (e.g. 50 and 5), matching Carlson native commands.
    ((null (setq g (pflabel:show-grid-dialog)))
     (prompt "\nPFLABEL cancelled.") nil)
    (T
     (setq tin      (pflabel:tin)
           prim     (pflabel:primary-pair)
           cl-pairs (pflabel:cl-pairs))
     (cond
       ((null tin)
        (prompt "\nNo surface (.TIN) selected -- aborting.") nil)
       ((null prim)
        (prompt "\nNo primary centerline selected -- aborting.") nil)
       ;; Validate style, create layer if missing, apply both.
       ((null (pflabel:apply-text-props s)) nil)
       ;; 3. Graphic picks (dialogs are done; Carlson pattern).
       ((null (setq pts (pflabel:pick-grid-points))) nil)
       (T
        (setq ll (car pts) top (cadr pts))
        ;; xform = (left-x sta0 hscale top-y base-y datum vscale)
        ;;   hscale fixed at 1.0 (model space is 1:1 horizontally);
        ;;   vscale = vertical exaggeration = H-plot / V-plot (usually 10),
        ;;   giving world units per elevation foot for the invert tool.
        (setq xf (list (car ll) (nth 0 g) *pf-hscale-fixed*
                       (cadr top) (cadr ll) (nth 1 g)
                       (/ (nth 2 g) (nth 3 g))))
        ;; 4. Load the surface, then build the line table (primary first;
        ;;    duplicates of the primary in the secondary list are dropped).
        (pf:tin-load tin)
        (setq pairs   (pflabel:dedupe-pairs (cons prim cl-pairs))
              lines   (pflabel:build-lines pairs)
              primary (cdr prim))
        (cond
          ((null lines)
           (prompt "\nNo readable centerlines -- aborting.")
           (pf:tin-unload) nil)
          ((null (pflabel:line-loaded-p primary lines))
           (prompt (strcat "\nPrimary line '" primary
                           "' failed to load -- aborting."))
           (pf:tin-unload) nil)
          (T
           ;; 5. Labeling mode (command line, per spec).
           (initget "All Pick")
           (setq mode (getkword
                        (strcat "\nLabel [All/Pick] structures on '"
                                primary "' <Pick>: ")))
           (if (null mode) (setq mode "Pick"))
           ;; 6. Index structures for ranking.
           (prompt "\nIndexing structures for ranking...")
           (setq inlets (pflabel:gather-inlets)
                 index  (pflabel:index-stations inlets lines))
           (list (cons 'xform   xf)
                 (cons 'lines   lines)
                 (cons 'primary primary)
                 (cons 'mode    mode)
                 (cons 'tin     tin)
                 (cons 'inlets  inlets)
                 (cons 'index   index)
                 ;; user prefix/suffix strings consumed by pf:build-label-rows
                 (cons 'fmt     (pflabel:label-fmt s))))))))))


;;; ==========================================================================
;;; PER-STRUCTURE  --  reads context + engine, draws one label
;;; ==========================================================================

;; (pflabel:ranks-for line-infos context) -> list of integers
(defun pflabel:ranks-for (line-infos context / index)
  (setq index (cdr (assoc 'index context)))
  (mapcar
    '(lambda (li)
       (pf:rank-on-line (cadr li)
                        (cdr (assoc (car li) index))
                        *pf-rank-ascending* *pf-range-eps*))
    line-infos))

;; (pflabel:process-structure block-ename context) -> nil
;;   Two orderings from the same hits:
;;     sta-infos   = primary first          -> drives the STA rows
;;     alpha-infos = alphabetical by name   -> drives the combined ID
(defun pflabel:process-structure (block-ename context
                                   / ed pt name xf gtop primary hits primhit
                                     others sta-infos alpha-infos names ranks
                                     type size id gl-val gl-str px basey topy
                                     offset gapn)
  (setq ed      (entget block-ename)
        pt      (cdr (assoc 10 ed))
        name    (cdr (assoc 2 ed))
        xf      (cdr (assoc 'xform context))
        gtop    (pf:grid-top-y xf)
        primary (cdr (assoc 'primary context))
        hits    (pf:lines-at-point pt (cdr (assoc 'lines context))))
  (setq primhit (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
  (cond
    ((null hits)
     (prompt (strcat "\n  " name " -- not on any named centerline; skipped.")))
    ((null primhit)
     (prompt (strcat "\n  " name " is on line(s) "
                     (pf:join (mapcar 'car hits) ",")
                     " but the profiled line is '" primary "'; skipped.")))
    (T
     (setq others      (vl-remove primhit hits)
           sta-infos   (cons primhit                      ; STA rows: primary first,
                             (pf:sort-line-infos-alpha others)) ; then alphabetical
           alpha-infos (pf:sort-line-infos-alpha hits)    ; ID: alphabetical
           names       (mapcar 'car alpha-infos)
           ranks       (pflabel:ranks-for alpha-infos context)
           type        (pf:blockname->type name *pf-type-table*)
           size        (pf:blockname->size name *pf-type-table*)
           id          (pf:combine-id names ranks)
           gl-val      (pf:tin-z pt)
           px          (pf:station->profile-x (cadr primhit) xf))
     (if (null gl-val)
       (prompt "\n  Structure X,Y is off the DTM surface -- skipped.")
       (progn
         (setq gl-str (pf:fmt-elev gl-val 2)
               offset (* *pf-height* *pf-offset-factor*)
               gapn   (* *pf-height* *pf-gap-rest-factor*))
         ;; text baseline sits `offset` above the grid top (the vertical gap);
         ;; the station line still runs from the grid top up to the text top.
         (setq basey (+ gtop offset)
               topy  (pf:draw-label-stack
                        px basey
                        (pf:build-label-rows sta-infos type size id gl-str
                                             (cdr (assoc 'fmt context)))
                        *pf-layer* *pf-style* *pf-height* offset gapn))
         (pf:draw-station-line px gtop topy *pf-layer*)
         (prompt (strcat "\n  Labeled " id ".")))))))
  

;;; ==========================================================================
;;; COMMAND
;;; ==========================================================================

;; (pflabel:label-pick context) -> nil   Pick mode: label structures one at a
;;   time from interactive selection.
(defun pflabel:label-pick (context / e ent ed)
  (prompt "\nPick structures to label (Enter to finish).")
  (while (setq e (entsel "\nSelect structure: "))
    (setq ent (car e) ed (entget ent))
    (cond
      ((/= (cdr (assoc 0 ed)) "INSERT")
       (prompt "\n  Not a block -- skipped."))
      ((null (pf:type-entry (cdr (assoc 2 ed)) *pf-type-table*))
       (prompt (strcat "\n  Unknown structure block "
                       (cdr (assoc 2 ed)) " -- skipped.")))
      (T (pflabel:process-structure ent context))))
  (princ))

;; (pflabel:label-all context) -> nil   All mode: label every structure whose
;;   membership includes the profiled line, sorted by station.  Draws regardless
;;   of existing labels (no erase -- that pass is deferred).
(defun pflabel:label-all (context / lines primary inlets pt hits ph pending)
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

(defun c:PFLABEL ( / ctx)
  ;; Install the error handler FIRST so Esc anywhere cleans up.
  (setq *pflabel-prev-error* *error*
        *error*               pflabel:*error*
        *pflabel-undo-open*  nil)
  (pf:load-apis)
  (setq ctx (pflabel:setup))
  (if ctx
    (progn
      ;; One undo group per run: a single U reverses the whole pass.
      (command "_.UNDO" "_Begin")
      (setq *pflabel-undo-open* T)
      (if (= (cdr (assoc 'mode ctx)) "All")
        (pflabel:label-all ctx)
        (pflabel:label-pick ctx))
      (command "_.UNDO" "_End")
      (setq *pflabel-undo-open* nil)
      ;; Clean up loaded TIN surface when command completes normally.
      (pf:tin-unload)))
  (setq *error* *pflabel-prev-error*)
  (princ))

(defun c:PFL () (c:PFLABEL))

(princ "\npflabel.lsp loaded.  Commands: PFLABEL (alias PFL)")
(princ)
;;; ==========================================================================
;;; end of pflabel.lsp
;;; ==========================================================================
