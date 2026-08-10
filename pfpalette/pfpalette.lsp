
;;; ==========================================================================
;;; pfpalette.lsp  --  OpenDCL palette front-end, read-only.  Command: PFPALETTE.
;;; Load position 10 of 10: last; may depend on every file above it.
;;; Model, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfp-loaded*))     (setq *pfp-loaded* nil))
(if (not (boundp '*pfp-tree-map*))   (setq *pfp-tree-map* '())) ; (Key . reg-row)
(if (not (boundp '*pfp-dbmod-mark*)) (setq *pfp-dbmod-mark* nil)) ; PFPDBMOD


;;; ==========================================================================
;;; SECTION 1  --  Loader + C:PFPALETTE toggle
;;; ==========================================================================

;; (pfp:odcl-path) -> full path to the project file, derived from *pftools-dir*
;;   The ONE path lives in pftools-load.lsp; never hardcode a second copy.
(defun pfp:odcl-path () (strcat *pftools-dir* "pfsuite-odcl/pfsuite.odcl"))

;; (pfp:ensure) -> project handle | nil
;;   Brings the OpenDCL runtime up quietly, then loads the project once.
(defun pfp:ensure ( / ce)
  (setq ce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_OPENDCL")
  (setvar "CMDECHO" ce)
  (if (not *pfp-loaded*)
    (setq *pfp-loaded* (dcl-Project-Load (pfp:odcl-path))))
  *pfp-loaded*)

;; C:PFPALETTE -- toggle: show the palette if down, close it if up.
;;   Close, not Hide: Close re-runs OnInitialize on the next open.
;;   Populate AFTER Show -- OnInitialize fires before the window is realized, so
;;   it owns columns only and the data fill (pfp:refresh) happens here.
;;   pfp:skin re-runs for the mirror reason: Close destroys the controls, so
;;   runtime formatting never survives a toggle.
;;   Do NOT add a resize call here: Studio's Min Width/Height clamp the form up,
;;   so dcl-Form-Resize cannot shrink it.  Fix the opening size in Studio.
(defun c:PFPALETTE ( / )
  (if (pfp:ensure)
    (if (dcl-Form-IsActive pfsuite/pfsPalette)
      (dcl-Form-Close pfsuite/pfsPalette)
      (progn
        (dcl-Form-Show pfsuite/pfsPalette)
        (pfp:skin nil nil)                  ; colours+font, for the same reason
        (pfp:refresh)))                     ; data fill AFTER the window exists
    (prompt "\nPFPALETTE: could not load the OpenDCL project."))
  (princ))

;; C:PFPRELOAD -- re-read the .odcl from disk.  RUN AFTER EVERY STUDIO SAVE.
;;   dcl-Project-Load no-ops when the project is already loaded unless its
;;   ForceReload argument is T, and pfp:ensure passes one argument -- so Studio
;;   saves never reach the runtime until this runs.  Kept out of pfp:ensure on
;;   purpose: production loads once, this is the development door.
(defun c:PFPRELOAD ( / ce r)
  (setq ce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (command "_OPENDCL")
  (setvar "CMDECHO" ce)
  ;; Forms must be closed before the project can be replaced.
  (vl-catch-all-apply
    '(lambda () (if (dcl-Form-IsActive pfsuite/pfsPalette)
                  (dcl-Form-Close pfsuite/pfsPalette))) '())
  (setq *pfp-loaded* nil
        r (vl-catch-all-apply 'dcl-Project-Load (list (pfp:odcl-path) T)))
  (if (vl-catch-all-error-p r)
    (prompt (strcat "\nPFPRELOAD: FAILED -- " (vl-catch-all-error-message r)))
    (progn
      (setq *pfp-loaded* r)
      (prompt "\nPFPRELOAD: .odcl re-read from disk.  Run PFPALETTE.")))
  (princ))

;; (pfp:refresh) -> nil
;;   THE one data-fill entry point: registry scan -> labels + tree.  Pure reads,
;;   so it is modeless-legal.  Error-guarded: a hostile drawing must never stop
;;   the palette from opening or docking.
(defun pfp:refresh ( / res)
  ;; The trees are about to be rebuilt, so the remembered selection and
  ;; *pfp-last-key* are stale.  Leaving them set would fire a verb against the
  ;; old row, and make the SelectItem below look like a repeat click (SECTION 5).
  (setq *pfp-sel* nil *pfp-tar-sel* nil *pfp-last-key* nil)
  (setq res (vl-catch-all-apply
              '(lambda ( / reg)
                 (setq reg (pfa:registry))
                 (pfp:seed-labels reg)
                 (setq *pfp-tree-map*
                         (pfp:fill-tree pfsuite/pfsPalette/tvwLines reg)
                       *pfp-tar-map*
                         (pfp:fill-tree pfsuite/pfsPalette/tarLines reg))
                 ;; Commands panels start empty: SelectItem on a Type parent
                 ;; fires no child selection, so nothing has asked for counts yet
                 (pfp:fill-details nil)
                 (pfp:fill-items nil)
                 (pfp:cmd-init))          ; grey Tools, default optRun (SECTION 9)
              '()))
  (if (vl-catch-all-error-p res)
    (prompt (strcat "\nPFPALETTE: registry read failed -- "
                    (vl-catch-all-error-message res))))
  (princ))


;;; ==========================================================================
;;; SECTION 2  --  The defer channel
;;; ==========================================================================
;;; A modeless handler cannot (command)/(getpoint), but a command it queues
;;; through vla-SendCommand lands in a real command context.
;;; EVERY palette verb goes through pfp:defer and nothing else.

;; (pfp:cmd-idle-p) -> T | nil
;;   The gate root README 5 requires before ANY palette-initiated write.
;;   CMDACTIVE alone is not enough: a dialog or a grip edit can leave
;;   CMDNAMES populated with CMDACTIVE at 0.
(defun pfp:cmd-idle-p ()
  (and (= 0 (getvar "CMDACTIVE"))
       (= "" (getvar "CMDNAMES"))))

;; (pfp:defer cmdline) -> T | nil
;;   Queue a command from a modeless handler; it runs after the handler unwinds.
;;   The trailing newline is what executes it -- without it the text just sits
;;   on the command line.  Refuses, loudly, when the command line is busy.
(defun pfp:defer (cmdline / doc)
  (cond
    ((not (pfp:cmd-idle-p))
     (prompt (strcat "\nPFPALETTE: command line busy (" (getvar "CMDNAMES")
                     ") -- finish it and try again."))
     nil)
    (T
     (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
     (vla-SendCommand doc (strcat cmdline "\n"))
     T)))


;;; ==========================================================================
;;; SECTION 3  --  Cell formatting
;;; ==========================================================================

;; (pfp:file-cell p) -> "name.ext" | "NOT FOUND" | "(not set)"
;;   Three states, not two: an empty slot was never bound, a bound slot whose
;;   file is gone is a different problem with a different fix.  vl-file-systime,
;;   NOT findfile -- findfile falls back to the support paths, so a name that is
;;   not absolute could match an unrelated file and read as present.
(defun pfp:file-cell (p)
  (cond
    ((or (null p) (= p "")) "(not set)")
    ((null (vl-file-systime p)) "NOT FOUND")
    (T (strcat (vl-filename-base p) (vl-filename-extension p)))))

;; (pfp:dash s) -> s | "-"   (a blank scalar reads as a dash, never "")
(defun pfp:dash (s) (if (and s (/= s "")) s "-"))


;;; ==========================================================================
;;; SECTION 4  --  OnInitialize  (columns once, seed labels, fill the tree)
;;; ==========================================================================

;; COLUMNS ONLY.  AddColumns is additive, so calling it from a refresh would
;; stack duplicate columns -- it lives here and nowhere else.  No data fill:
;; OnInitialize fires before the window is realized, so nothing written now
;; paints.  Data comes from pfp:refresh, called after Form-Show.
(defun c:pfsuite/pfsPalette#OnInitialize ( / )
  (dcl-ListView-AddColumns pfsuite/pfsPalette/metaList
    (list (list "Property" 0 110) (list "Value" 0 410)))
  (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwLinkage
    (list (list "Item" 0 90) (list "File" 0 440)))
  ;; detailsList is a per-target SUMMARY, not an item list -- hence the same
  ;; Property/Value shape as metaList.
  (dcl-ListView-AddColumns pfsuite/pfsPalette/detailsList
    (list (list "Property" 0 150) (list "Value" 0 370)))
  ;; lvwCommand -- the ITEM list beside detailsList's summary (SECTION 5c).
  ;; ONE COLUMN SET FOR ALL THREE PASSES: AddColumns runs once, so the columns
  ;; cannot be re-shaped when the radio changes.  Hence neutral headers -- "Item"
  ;; is a block name under Structures/Inverts, a line name under Crossings.
  ;; Widths total 370 against a 420 client: the slack leaves room for a vertical
  ;; scroll bar without forcing a horizontal one underneath it.
  ;; GATED, and deliberately LAST -- a List View call on a control that is not a
  ;; List View raises the uncatchable modal (see *pfp-items-mode*, SECTION 5c),
  ;; so the three column sets above are already in by the time it could throw.
  (if (eq *pfp-items-mode* 'listview)
    (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwCommand
      (list (list "Item" 0 150) (list "Station" 0 110) (list "Status" 0 110))))
  (princ))

;; (pfp:caption ctrl label text) -> T | nil
;;   Guarded SetCaption.  A control symbol the loaded project never defined
;;   evaluates to nil (AutoLISP does not error on an unbound symbol), and
;;   SetCaption on nil does nothing and reports nothing -- the label just stays
;;   blank while everything around it works.  So: name the miss.
(defun pfp:caption (ctrl label text / r)
  (cond
    ((null ctrl)
     (prompt (strcat "\nPFPALETTE: control \"" label "\" is not in the loaded"
                     " project -- check its (Name) in Studio."))
     nil)
    (T
     (setq r (vl-catch-all-apply 'dcl-Control-SetCaption (list ctrl text)))
     (cond
       ((vl-catch-all-error-p r)
        (prompt (strcat "\nPFPALETTE: SetCaption failed on \"" label "\" -- "
                        (vl-catch-all-error-message r)))
        nil)
       (T T)))))

;; (pfp:seed-labels reg) -> nil   (project root + registry tallies; all cheap)
(defun pfp:seed-labels (reg / root n anchored)
  (setq root (pfset:root-get))
  (pfp:caption pfsuite/pfsPalette/lblProject "lblProject"
    (strcat "Project: " (if root root "(none)")))
  (setq n        (length reg)
        anchored (length (vl-remove-if-not
                           '(lambda (r) (eq (caddr r) 'ANCHORED)) reg)))
  (pfp:caption pfsuite/pfsPalette/lblCounts "lblCounts"
    (strcat (itoa n) " line" (if (= n 1) "" "s") "  ("
            (itoa anchored) " anchored, "
            (itoa (- n anchored)) " registered)"))
  (princ))

;; (pfp:fill-tree ctrl reg) -> map     ((childKey . reg-row) ...)
;;   Two levels: distinct utility Type as parents, Line as children.  The
;;   registry arrives sorted by "TYPE NAME", so a type break is a new parent.
;;   Returns the map rather than writing a global: child keys are per-control,
;;   and two trees run over this registry (tvwLines, tarLines), so a shared map
;;   would make pfp:sel-row answer with the other tree's row.
(defun pfp:fill-tree (ctrl reg / cur-type pkey ckey first r map)
  (dcl-Tree-Clear ctrl)
  (setq map '() cur-type nil pkey nil first nil)
  (foreach r reg
    (if (not (equal (car r) cur-type))
      (setq cur-type (car r)
            pkey (dcl-Tree-AddParent ctrl cur-type -1 -1 -1)))
    (if (null first) (setq first pkey))     ; remember the first parent
    (setq ckey (dcl-Tree-AddChild ctrl pkey (cadr r) -1 -1 -1)
          map  (cons (cons ckey r) map)))
  (if first (dcl-Tree-SelectItem ctrl first))
  map)


;;; ==========================================================================
;;; SECTION 5  --  tvwLines selection -> fill metaList + lvwLinkage
;;; ==========================================================================
;;; Anchored lines read from the anchor block + ledger; registered (STUB) lines
;;; read from the stub row.  UI vocabulary is "Anchored" / "Registered" --
;;; never "placed" / "stub".

;; (pfp:sel-row Key map) -> reg-row | nil   (nil when Key is a Type parent)
;;   Child keys are per-control, so each tree is looked up in its own map.
(defun pfp:sel-row (key map) (cdr (assoc key map)))

;; (pfp:status-cell anchor) -> "PASSING" | "STALE (LABEL)" | ...
;;   Worked out here and never stored -- nothing would update a saved summary
;;   when a record beneath it moved.  Worst state wins, so one failing input
;;   can never render as green.
(defun pfp:status-cell (anchor / roll)
  (setq roll (pfa:status-roll anchor))
  (strcat (pfa:status-label (car roll))
          (if (nth 3 roll)
            (strcat " (" (pf:join (nth 3 roll) ", ") ")")
            "")))

;; (pfp:why-rows anchor) -> ("  LABEL" -1 finding -1) rows, possibly '()
;;   One indented row per stored finding, only for STALE/FAILING passes: it is
;;   what puts the explanation next to the Checks cell.  Pure ledger read.
(defun pfp:why-rows (anchor / out p f)
  (setq out '())
  (foreach p '("LABEL" "INVERT")
    (foreach f (pfa:status-why anchor p)
      (setq out (cons (list (strcat "  " p) -1 f -1) out))))
  (reverse out))

;; (pfp:meta-rows row) -> list of (prop -1 value -1) rows for metaList
;;   ty, NOT type: `type' is a subr, and this runs from a modeless handler with
;;   pfa: reads underneath it (2026-08-06).
(defun pfp:meta-rows (row / ty name ename at cl mat)
  (setq ty (car row) name (cadr row))
  (cond
    ((eq (caddr row) 'ANCHORED)
     (setq ename (nth 3 row)
           at    (pfa:read-attribs ename)
           cl    (cdr (assoc 1 (pfa:meta-get ename)))
           mat   (cdr (assoc 5 (pfa:files-get ename))))
     (append
       (list (list "Type"       -1 ty                            -1)
             (list "Line"       -1 name                          -1)
             (list "State"      -1 "Anchored"                    -1)
             (list "Checks"     -1 (pfp:status-cell ename)       -1))
       (pfp:why-rows ename)
       (list (list "Datum"      -1 (pfp:dash (pfa:att "DATUM" at)) -1)
             (list "Start sta"  -1 (pfp:dash (pfa:att "STA0"  at)) -1)
             (list "H plot"     -1 (pfp:dash (pfa:att "HPLOT" at)) -1)
             (list "V plot"     -1 (pfp:dash (pfa:att "VPLOT" at)) -1)
             (list "Centerline" -1 (pfp:file-cell cl)            -1)
             (list "Material"   -1 (pfp:dash mat)                -1))))
    (T                                            ; STUB = (type name cl inv top)
     (list (list "Type"       -1 ty                            -1)
           (list "Line"       -1 name                          -1)
           (list "State"      -1 "Registered"                  -1)
           (list "Centerline" -1 (pfp:file-cell (nth 2 (nth 4 row))) -1)))))

;; (pfp:linkage-files row) -> (cl inv top exist design)  each path or ""/nil
(defun pfp:linkage-files (row / ename files stub)
  (cond
    ((eq (caddr row) 'ANCHORED)
     (setq ename (nth 3 row)
           files (pfa:files-get ename))
     (list (cdr (assoc 1 (pfa:meta-get ename)))     ; .cl from META
           (if files (cdr (assoc 1 files)))         ; INV .pro
           (if files (cdr (assoc 2 files)))         ; TOP .pro
           (if files (cdr (assoc 3 files)))         ; existing .tin
           (if files (cdr (assoc 4 files)))))       ; DESIGN .tin
    (T                                            ; STUB = (type name cl inv top)
     (setq stub (nth 4 row))
     (list (nth 2 stub) (nth 3 stub) (nth 4 stub) nil nil))))

;; (pfp:fill-linkage row) -> nil   (row nil clears to five "(not set)" rows)
(defun pfp:fill-linkage (row / f)
  (setq f (if row (pfp:linkage-files row) '(nil nil nil nil nil)))
  (dcl-ListView-FillList pfsuite/pfsPalette/lvwLinkage
    (list (list "Centerline (.cl)" -1 (pfp:file-cell (nth 0 f)) -1)
          (list "Invert _INV .pro" -1 (pfp:file-cell (nth 1 f)) -1)
          (list "Crown _TOP .pro"  -1 (pfp:file-cell (nth 2 f)) -1)
          (list "Existing .tin"    -1 (pfp:file-cell (nth 3 f)) -1)
          (list "DESIGN_* .tin"    -1 (pfp:file-cell (nth 4 f)) -1)))
  (princ))

;; (pfp:route-sel Key) -> nil
;;   THE SELECTION ROUTER.  Both trees' OnSelChanged arrive here: the Commands
;;   tree dispatches under the Registry tree's name (crossed wiring in the
;;   .odcl), so the handler that fired cannot identify the tree.  Route on WHICH
;;   MAP OWNS THE KEY instead -- the key is the identity, and that stays correct
;;   if the .odcl is ever rebuilt with the right binding.
;;
;;   QUIET: the fills run the same self-narrating gather code the label commands
;;   run.  *pf-quiet* suppresses PROGRESS ONLY -- errors and refusals still
;;   print -- and is cleared OUTSIDE the fills, so an error cannot leave the
;;   suite mute for the rest of the session.
;;
;;   IDEMPOTENCE GUARD (*pfp-last-key*): every tree click dispatches
;;   OnSelChanged twice, and the Commands fill reaches pfa:xing-scan, which is
;;   O(n x m) on a target with no SCOPE.  Cleared wherever the data behind a key
;;   can have changed -- pfp:refresh and pfp:order-run.  Otherwise a click on the
;;   row already showing is a no-op; btnRefresh is the "repaint this" button.
(if (not (boundp '*pfp-last-key*)) (setq *pfp-last-key* nil))

(defun pfp:route-sel (Key)
  (if (and Key (equal Key *pfp-last-key*))
    (pfp:trace-sel "SKIP" nil Key)
    (pfp:route-sel-do Key))
  (princ))

(defun pfp:route-sel-do (Key / reg tar res)
  (setq *pfp-last-key* Key
        reg (pfp:sel-row Key *pfp-tree-map*)
        tar (pfp:sel-row Key *pfp-tar-map*)
        *pf-quiet* T
        res (vl-catch-all-apply
              '(lambda ()
                 (cond
                   (reg (pfp:show-registry reg))
                   (tar (pfp:show-commands tar))
                   ;; A Type parent belongs to neither map.  Clear both panels:
                   ;; we cannot tell which tree it came from, and the next
                   ;; child click repopulates.
                   (T (pfp:show-registry nil) (pfp:show-commands nil))))
              '()))
  ;; ALWAYS, including on a throw -- a skipped reset mutes the whole suite.
  (setq *pf-quiet* nil)
  (if (vl-catch-all-error-p res)
    (prompt (strcat "\nPFPALETTE: selection fill failed -- "
                    (vl-catch-all-error-message res))))
  (princ))

;; (pfp:show-registry row) -> nil    Registry tab panels
(defun pfp:show-registry (row)
  (dcl-ListView-FillList pfsuite/pfsPalette/metaList
    (if row (pfp:meta-rows row) '()))
  (pfp:fill-linkage row)
  (setq *pfp-sel* row)                    ; SECTION 8's verbs read this
  (princ))

;; (pfp:show-commands row) -> nil    Commands tab panels
;;   Two panels: detailsList's all-passes summary and lvwCommand's item list for
;;   the selected pass (SECTION 5c).  Items go LAST -- pfp:fill-items clears
;;   *pf-quiet* on its way out, and the summary fill wants it still bound.
(defun pfp:show-commands (row)
  (pfp:fill-details row)
  (pfp:fill-items row)
  (setq *pfp-tar-sel* row)
  (princ))

;; BOTH trees land here -- see pfp:route-sel.  The handler does no work of its
;; own beyond the trace; routing is by key ownership.
(defun c:pfsuite/pfsPalette/tvwLines#OnSelChanged (Label Key / )
  (pfp:trace-sel "TVW" Label Key)
  (pfp:route-sel Key)
  (princ))

;; (pfp:trace-sel tag Label Key) -> nil   PFPTAR's instrumentation.
;;   Reports the key against BOTH maps, which is the measurement that found
;;   the crossed wiring in the first place.
(defun pfp:trace-sel (tag Label Key / reg tar)
  (if *pfp-trace*
    (progn
      (setq reg (pfp:sel-row Key *pfp-tree-map*)
            tar (pfp:sel-row Key *pfp-tar-map*))
      (prompt (strcat "\n" tag "#OnSelChanged  Label=" (if Label Label "nil")
                      "\n    tree-map: "
                      (if reg (strcat "YES -> " (car reg) " " (cadr reg)) "no")
                      "   tar-map: "
                      (if tar (strcat "YES -> " (car tar) " " (cadr tar)) "no")
                      "   -> routed to "
                      (cond (reg "Registry") (tar "Commands") (T "cleared"))))))
  (princ))


;;; ==========================================================================
;;; SECTION 5b  --  tarLines selection -> fill detailsList  (Commands tab)
;;; ==========================================================================
;;; A per-target SUMMARY, not a list of items: pick a target, see what is on it,
;;; THEN choose the command.  All three passes show at once so the counts are on
;;; screen before the radio is touched.  Every number comes from
;;; pfa:target-counts; all pure reads, so this handler is modeless-legal.

(if (not (boundp '*pfp-tar-map*)) (setq *pfp-tar-map* '()))
(if (not (boundp '*pfp-tar-sel*)) (setq *pfp-tar-sel* nil))

;; (pfp:count-cell done out) -> "8 labeled, 4 outstanding"
;;   One cell rather than two rows -- the pair reads as one fact.
(defun pfp:count-cell (done out)
  (strcat (itoa done) " labeled, " (itoa out) " outstanding"))

;; (pfp:drift-cell n) -> "-" | "2 Incorrect label(s)"
;;   "Incorrect", never "stale": the Registry tab's Checks cell already uses
;;   STALE for a different axis -- an input FILE that changed since the pass ran.
;;   This row is about a LABEL that no longer sits where its structure does.
(defun pfp:drift-cell (n)
  (if (or (null n) (= n 0))
    "-"
    (strcat (itoa n) " Incorrect label(s)")))

;; (pfp:detail-rows row) -> list of (prop -1 value -1) rows for detailsList
;;   Three shapes, because 0 and "unknowable" are different answers:
;;     no row    -- a Type parent, or nothing picked yet
;;     STUB      -- registered but not anchored: no xform, no ledger, no pass
;;                  entities, so every count is undefined rather than zero
;;     ANCHORED  -- the real thing; nil from target-counts means no .cl bound
(defun pfp:detail-rows (row / c)
  (cond
    ((null row) '())
    ((not (eq (caddr row) 'ANCHORED))
     (list (list "Type"   -1 (car row)  -1)
           (list "Line"   -1 (cadr row) -1)
           (list "State"  -1 "Registered" -1)
           (list "Counts" -1 "anchor this line to see counts" -1)))
    ((null (setq c (pfa:target-counts (nth 3 row))))
     (list (list "Type"   -1 (car row)  -1)
           (list "Line"   -1 (cadr row) -1)
           (list "State"  -1 "Anchored" -1)
           (list "Counts" -1 "no .cl on record -- run PFSETUP (edit)" -1)))
    (T
     (list (list "Type"  -1 (car row)  -1)
           (list "Line"  -1 (cadr row) -1)
           (list "State" -1 "Anchored" -1)
           (list "Lines in gather set" -1
                 (itoa (cdr (assoc 'lines c))) -1)
           (list "Structures on line" -1
                 (itoa (cdr (assoc 'structures c))) -1)
           (list "Structure labels" -1
                 (pfp:count-cell (cdr (assoc 'label-done c))
                                 (cdr (assoc 'label-out  c))) -1)
           (list "Invert labels" -1
                 (pfp:count-cell (cdr (assoc 'invert-done c))
                                 (cdr (assoc 'invert-out  c))) -1)
           ;; "on record", not "found": pfxl:discover is a WRITER, so the palette
           ;; sees only already-merged crossings.  0 means "none discovered yet".
           (list "Crossings on record" -1
                 (itoa (cdr (assoc 'crossings c))) -1)
           (list "Crossing labels" -1
                 (pfp:count-cell (cdr (assoc 'xing-done c))
                                 (cdr (assoc 'xing-out  c))) -1)
           (list "Drift" -1 (pfp:drift-cell (cdr (assoc 'drift c))) -1)))))

;; (pfp:fill-details row) -> nil
;;   GUARDED, unlike Section 5's fill: this one reaches file I/O and the Road
;;   API through pfa:target-counts.  A failure shows in the panel AND on the
;;   command line rather than silently blanking.
(defun pfp:fill-details (row / rows res)
  ;; THE ROAD API IS NOT LOADED IN A HANDLER.  pf:run-command loads it at every
  ;; command prologue, but a modeless fill never goes through that wrapper and
  ;; pfa:target-counts reaches cl_location_at_pt -- without this, the first
  ;; click in a session dies with "bad function: CF:ROAD_API".
  ;; Legal here: two catch-wrapped scload calls, idempotent, no drawing write.
  ;; Here and not in pfp:route-sel because all three callers of this fill need
  ;; it -- the handler, pfp:refresh, and C:PFPDETAIL.
  (pf:load-apis)
  (setq res (vl-catch-all-apply 'pfp:detail-rows (list row)))
  (setq rows (if (vl-catch-all-error-p res)
               (progn
                 (prompt (strcat "\nPFPALETTE: target counts failed -- "
                                 (vl-catch-all-error-message res)))
                 (list (list "Error" -1
                             (vl-catch-all-error-message res) -1)))
               res))
  (dcl-ListView-FillList pfsuite/pfsPalette/detailsList rows)
  (princ))

;;; ==========================================================================
;;; SECTION 5c  --  lvwCommand:  the per-command ITEM list  (Commands tab)
;;; ==========================================================================
;;; "Which ones, and where" for the ONE pass selected: Structures and Inverts
;;; list every structure with its station and whether that pass labeled it;
;;; Crossings lists every crossing line and where it crosses.
;;; TWO TRIGGERS -- the list depends on the target AND the radio, so it refills
;;; from tarLines selection (via pfp:show-commands) and from optLabel.
;;; DISPLAY ONLY: it does not feed (sel . <items>) and does not unblock Label
;;; Selected.  FillList is attested; reading a selection back out of a List View
;;; is not.  Settle that with C:PFPAPI *LIST* before assuming a getter exists.

;;; ---- what kind of control lvwCommand is  (park switch) --------------------
;;; nil | 'listview.  TWO FAILURE SIGNATURES, and the fixes have nothing in
;;; common:
;;;   wrong NAME -> symbol is nil -> the call does nothing, SILENTLY.  Guard
;;;                 with a null test and name it (pfp:caption, pfp:fill-items).
;;;   wrong TYPE -> symbol is bound -> uncatchable modal, "Invalid argument
;;;                 type", Argument: 0 (the control).  vl-catch-all-apply does
;;;                 not suppress it and the caller still aborts.  No guard is
;;;                 possible: asking a control its type means calling something
;;;                 type-specific at it, and that call IS the fault.  Get the
;;;                 type from Studio instead.
;;; Studio rebuilt this as a List View, so the mode ships 'listview -- real
;;; columns, rather than three cells faked with pfset:pad, which never lined up
;;; under the proportional font pfp:skin paints.  pfp:rows->lb stays as the List
;;; Box fallback; the data side (pfa:target-items, pfp:item-rows) is neutral.
;;; PLAIN setq, not a boundp guard: under a guard an already-loaded session would
;;; keep the old mode and re-loading would look like it did nothing -- meaning
;;; dcl-ListBox-* calls at a List View, which is the modal.
(setq *pfp-items-mode* 'listview)

;;; ---- the List Box call names ---------------------------------------------
;;; All four attested in the vendor sample, not inferred:
;;;   dcl_ListBox_Clear      AUBlockTool_Final.lsp:11
;;;   dcl_LISTBOX_ADDLIST    AUBlockTool_Final.lsp:12  (takes a LIST OF STRINGS)
;;;   dcl_ListBox_GetCurSel  AUBlockTool_Final.lsp:31
;;;   dcl_ListBox_GetText    AUBlockTool_Final.lsp:32  (ctrl index)
;;; Hyphens first, underscores as fallback (OPENDCL-WIRING 4).  Candidate lists
;;; rather than bare calls: a wrong FUNCTION name is the catchable failure class,
;;; and pfp:first-callable degrades instead of erroring.
(setq *pfp-lb-clear*   '("dcl-ListBox-Clear"   "dcl_ListBox_Clear"))
(setq *pfp-lb-addlist* '("dcl-ListBox-AddList" "dcl_ListBox_AddList"))

;;; ---- what lvwCommand reports ---------------------------------------------
;;; (ItemIndexOrCount Value) -- index first, like an Option List and unlike the
;;; tree's (Label Key).
;;; RE-READ THIS IN STUDIO: it was measured off the Events panel of a List Box,
;;; and the panel is per control TYPE.  If a List View's SelChanged carries a
;;; different argument list, this handler binds the wrong things silently
;;; (OPENDCL-WIRING 3).  Also DELETE Studio's generated stub body -- for this
;;; control it emits a dcl-MessageBox, i.e. a modal on every row click.
;;; Vendor caveat: for a SINGLE selection list ItemIndexOrCount is the index and
;;; Value the row text; for a MULTIPLE selection list it is the COUNT and Value
;;; is "".  Nothing in LISP can read which way that Studio property is set, so
;;; do not treat *pfp-item-sel*'s first element as a row index.
;;; No List View getter is attested in this suite, so this event is the only
;;; source.  C:PFPAPI *LIST* is the only safe way to look for one -- it reads the
;;; symbol table and calls nothing; trial-calling a guessed getter at the live
;;; control is a missing PROPERTY, which is the uncatchable modal.
(if (not (boundp '*pfp-item-sel*)) (setq *pfp-item-sel* nil))

;; Records and stops: a selection is a noun.  Nothing here reads the control,
;; writes the drawing, or acts -- Label Selected consumes it later, from RUN.
(defun c:pfsuite/pfsPalette/lvwCommand#OnSelChanged (ItemIndexOrCount Value / )
  (setq *pfp-item-sel* (list ItemIndexOrCount Value))
  (princ))

;; (pfp:items-pass) -> "LABEL" | "INVERT" | "XING"
;;   Which pass the list is showing, read from what optLabel last reported.
;;   Defaults to Structures SILENTLY, unlike pfp:opt-item, which refuses to run
;;   on an unobserved group.  Filling a list is a read: the worst a wrong default
;;   does is show the wrong list until a radio is clicked.
(defun pfp:items-pass ( / rec hit i)
  (setq i 0)
  (if (and (setq rec (assoc "optLabel" *pfp-opt-vals*))
           (setq hit (pfp:cap-match "optLabel" (cadr rec))))
    (setq i (cdr hit)))
  (cond ((= i 1) *pfi-pass-name*)
        ((= i 2) "XING")
        (T       "LABEL")))

;; (pfp:item-status state) -> the Status cell
;;   state is pfa:target-items' symbol, one vocabulary for all three passes.
;;     NEW   -- on the ground, not in the ledger.  Running Crossings files it.
;;     MOVED -- on record, but the .cl now crosses somewhere else.
(defun pfp:item-status (state)
  (cond ((eq state 'LABELED) "labeled")
        ((eq state 'NEW)     "NEW -- not on record")
        ((eq state 'MOVED)   "MOVED -- station changed")
        (T                   "outstanding")))

;; (pfp:item-rows row) -> ((item station status) ...)   THREE STRINGS, no more.
;;   CONTROL-NEUTRAL ON PURPOSE: the renderers below turn a row into whatever the
;;   control wants, so a wrong guess about the control type costs one renderer.
;;   Three distinct empty shapes, like pfp:detail-rows -- a Type parent, an
;;   un-anchored line and an anchored line with no .cl are different answers.
(defun pfp:item-rows (row / pass res items out e)
  (cond
    ((null row) '())
    ((not (eq (caddr row) 'ANCHORED))
     (list (list "(not anchored)" "-" "anchor this line first")))
    ((null (setq res (pfa:target-items (nth 3 row) (setq pass (pfp:items-pass)))))
     (list (list "(unreadable)" "-" "no .cl on record -- run PFSETUP (edit)")))
    ((null (setq items (cdr res)))
     ;; GENUINELY none, for every pass: pfa:xing-find runs the crossing scan
     ;; read-only, so an empty list means nothing crosses -- not "nobody looked".
     (list (list (if (= pass "XING")
                   "(nothing crosses this line)"
                   "(no structures on this line)")
                 "-" "-")))
    (T
     (setq out '())
     (foreach e items
       (setq out (cons (list (car e)
                             (pf:fmt-station (cadr e))
                             (pfp:item-status (caddr e)))
                       out)))
     (reverse out))))

;; (pfp:rows->lv rows) -> the List View shape: (item -1 station -1 status -1)
;;   The -1s are the per-column image indices, as metaList and detailsList use.
(defun pfp:rows->lv (rows / out r)
  (setq out '())
  (foreach r rows
    (setq out (cons (list (car r) -1 (cadr r) -1 (caddr r) -1) out)))
  (reverse out))

;; (pfp:rows->lb rows) -> the List Box shape: ONE padded string per row
;;   NOT the live renderer -- the fallback *pfp-items-mode* can reach.  A List
;;   Box has no columns, so they are faked with spaces at pflabel:rd-fill's
;;   widths.  It never lined up: pfset:pad does not TRUNCATE, so a name over 20
;;   characters shoves the later columns right, and pfp:skin paints the
;;   proportional "MS Shell Dlg" over every control.  Left unclipped on purpose
;;   -- if this branch goes live again both fixes are still needed, and a
;;   half-fix here would hide that.
(defun pfp:rows->lb (rows / out r)
  (setq out '())
  (foreach r rows
    (setq out (cons (strcat (pfset:pad (car r) 20)
                            (pfset:pad (cadr r) 14)
                            (caddr r))
                    out)))
  (reverse out))

;; (pfp:fill-items row) -> nil
;;   Guarded like pfp:fill-details, for the same reason: it reaches file I/O and
;;   the Road API through pfa:target-items.
;;   QUIET (progress only -- errors and refusals still print).  The reset is
;;   unconditional and outside the catch, so no throw leaves the suite mute.
(defun pfp:fill-items (row / rows res)
  ;; The rows are about to be replaced, so a remembered index would point at a
  ;; different structure, or nothing.  Same staleness rule as pfp:refresh.
  (setq *pfp-item-sel* nil)
  (cond
    ;; PARKED until Studio settles the control type.  Silent by design: this
    ;; runs on every tree and radio click.
    ((null *pfp-items-mode*) nil)
    ;; WRONG-NAME case only: an undefined control symbol is nil and FillList on
    ;; nil does nothing silently (OPENDCL-WIRING 7), so name it.  Wrong TYPE is
    ;; bound and modal, and no test here can catch it -- see *pfp-items-mode*.
    ((null pfsuite/pfsPalette/lvwCommand)
     (prompt (strcat "\nPFPALETTE: control \"lvwCommand\" is not in the loaded"
                     " project -- check its (Name) in Studio.")))
    (T
      (pf:load-apis)                    ; not loaded in a handler -- see below
      (setq *pf-quiet* T
            res        (vl-catch-all-apply 'pfp:item-rows (list row)))
      (setq *pf-quiet* nil)
      (setq rows (if (vl-catch-all-error-p res)
                   (progn
                     (prompt (strcat "\nPFPALETTE: item list failed -- "
                                     (vl-catch-all-error-message res)))
                     (list (list "(error)" "-"
                                 (vl-catch-all-error-message res))))
                   res))
      (if (eq *pfp-items-mode* 'listbox)
        (progn
          ;; CLEAR THEN ADD (vendor idiom, AUBlockTool_Final.lsp:11-12).  AddList
          ;; is additive, so a refill without the Clear stacks the old rows.
          (pfp:first-callable *pfp-lb-clear*
                              (list pfsuite/pfsPalette/lvwCommand))
          ;; AddList with '() has never been exercised -- skip it rather than
          ;; find out; Clear has already emptied the panel.
          (if rows
            (pfp:first-callable *pfp-lb-addlist*
                                (list pfsuite/pfsPalette/lvwCommand
                                      (pfp:rows->lb rows)))))
        (dcl-ListView-FillList pfsuite/pfsPalette/lvwCommand
                               (pfp:rows->lv rows)))))
  (princ))


;; Set by C:PFPTAR.  Off by default -- a handler that chatters on every click
;; is worse than no handler.
(if (not (boundp '*pfp-trace*)) (setq *pfp-trace* nil))

;; Routed identically to the Registry handler.  On this .odcl it never fires --
;; the Commands tree dispatches under tvwLines -- but it starts working the
;; moment the wiring is rebuilt in Studio.
(defun c:pfsuite/pfsPalette/tarLines#OnSelChanged (Label Key / )
  (pfp:trace-sel "TAR" Label Key)
  (pfp:route-sel Key)
  (princ))

;; (pfp:live-keys map) -> how many entries carry a non-nil key
(defun pfp:live-keys (map / n c)
  (setq n 0)
  (foreach c map (if (car c) (setq n (1+ n))))
  n)

;; C:PFPTREES -- where do the two trees actually sit?
;;   Clicking the Commands tree fires tvwLines#OnSelChanged, not tarLines#, and
;;   both symbols are bound with populated maps.  The theory: tvwLines is not
;;   parented inside the Registry tab page, so it renders across every tab and
;;   covers tarLines.  Overlapping rects confirm that; disjoint rects refute it.
(defun c:PFPTREES ( / )
  (cond
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPTREES: run PFPALETTE first."))
    (T
     (prompt "\n=== PFPTREES -- runtime rects ===")
     (foreach pair (list (cons "tvwLines" pfsuite/pfsPalette/tvwLines)
                         (cons "tarLines" pfsuite/pfsPalette/tarLines)
                         (cons "detailsList" pfsuite/pfsPalette/detailsList))
       (prompt (strcat "\n  " (car pair) ":"))
       (if (null (cdr pair))
         (prompt "  NIL -- not defined in the loaded project")
         (foreach g '("GetLeft" "GetTop" "GetWidth" "GetHeight" "GetVisible")
           (prompt (strcat "  " (substr g 4) "="
                           (pfp:ask (strcat "dcl-Control-" g)
                                    (list (cdr pair))))))))
     (prompt (strcat "\n  Overlapping tvwLines/tarLines rects => tvwLines is"
                     " covering the Commands tab and taking the clicks."))))
  (princ))

;; C:PFPTAR -- why is the Commands panel empty when PFPDETAIL fills it?
;;   Turns the handler trace on and dumps the state it depends on.  Click a LINE
;;   (a child, not a Type parent) and read the command line:
;;     nothing printed        -> the event is not reaching the handler
;;     printed, row=NIL       -> the key is not in the map (map= says whether
;;                               the map is even populated)
;;     printed, row=TYPE NAME -> the handler is fine; the fill is the problem
;;   A TOGGLE, and boundp-guarded: neither a PFPALETTE re-toggle nor a suite
;;   reload clears it, so run PFPTAR again to stop the chatter.
(defun c:PFPTAR ( / )
  (cond
    (*pfp-trace*
     (setq *pfp-trace* nil)
     (prompt "\nPFPTAR: trace OFF.  Run PFPTAR again to turn it back on.")
     (princ))
    (T (pfp:tar-report))))

(defun pfp:tar-report ( / )
  (setq *pfp-trace* T)
  (prompt "\n=== PFPTAR ===")
  (prompt (strcat "\n  tarLines control symbol: "
                  (if pfsuite/pfsPalette/tarLines
                    "bound"
                    "NIL -- the project never defined it; check (Name) in Studio")))
  (prompt (strcat "\n  detailsList control symbol: "
                  (if pfsuite/pfsPalette/detailsList
                    "bound"
                    "NIL -- the project never defined it; check (Name) in Studio")))
  ;; COUNT THE KEYS, NOT THE ENTRIES.  pfp:fill-tree conses (ckey . row) whatever
  ;; dcl-Tree-AddChild returned, so 66 entries fits 66 successful adds AND 66
  ;; silent no-ops.  Only the non-nil key count tells them apart.
  (prompt (strcat "\n  *pfp-tar-map*:  " (itoa (length *pfp-tar-map*))
                  " entries, " (itoa (pfp:live-keys *pfp-tar-map*))
                  " with a real key"))
  (prompt (strcat "\n  *pfp-tree-map*: " (itoa (length *pfp-tree-map*))
                  " entries, " (itoa (pfp:live-keys *pfp-tree-map*))
                  " with a real key   (the working tree, for comparison)"))
  (if (= 0 (pfp:live-keys *pfp-tar-map*))
    (prompt (strcat "\n  >> EVERY tarLines key is nil: the Tree calls did"
                    " nothing.  The control is named and bound but is not"
                    " accepting TreeView calls -- check its TYPE in Studio"
                    " against tvwLines.")))
  (prompt "\n  Trace is ON.  Click a LINE in the Commands tree now.")
  (prompt "\n  Run PFPTAR again to turn it OFF.")
  (princ))


;;; ==========================================================================
;;; SECTION 6  --  Diagnostics  (PFPDIAG, PFPDBMOD)
;;; ==========================================================================

;; The full control roster from PALETTE-LAYOUT 4-6, wired and not.  The unwired
;; ones are checked too: a (Name) mismatch is cheap to fix now, expensive later.
(setq *pfp-controls*
  '("tabMain" "lblProject" "lblCounts" "btnRefresh" "btnHelp"
    "tvwLines" "metaList" "lvwLinkage"
    "btnPickCL" "btnPickINV" "btnPickTOP" "btnPickDESIGN" "btnPickEXIST"
    "btnAnchor" "btnEdit" "btnNew" "btnRemove" "btnZoom"
    "tarLines" "frmLabel" "optLabel" "frmTools" "optTools"
    "frmOptions" "optRun" "detailsList" "lvwCommand" "chkbxZoom"
    "btnClear" "btnRun"))

;; C:PFPDIAG -- name every control the project failed to define.
;;   A control that prints MISSING is a (Name) mismatch between the .odcl and
;;   the code -- the one failure mode that produces NO error at runtime.
;;   THE PALETTE MUST BE OPEN.  Control symbols exist only while the form is
;;   realized; Close destroys the children and every symbol goes nil, so running
;;   this closed would report all 29 MISSING.  (The FORM symbol survives, which
;;   is why C:PFPALETTE can call dcl-Form-IsActive on a closed palette.)
(defun c:PFPDIAG ( / nm val found miss)
  (cond
    ((not (pfp:ensure))
     (prompt "\nPFPDIAG: could not load the OpenDCL project."))
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPDIAG: the palette is CLOSED, so no control symbol exists")
     (prompt "\n         and every name would read MISSING.  Run PFPALETTE")
     (prompt "\n         first, then PFPDIAG."))
    (T
     (setq found '() miss '())
     (foreach nm *pfp-controls*
       ;; read -> the symbol, eval -> its value.  nil IS the finding, but only
       ;; while the form is open.
       (setq val (eval (read (strcat "pfsuite/pfsPalette/" nm))))
       (if val (setq found (cons nm found)) (setq miss (cons nm miss))))
     (prompt (strcat "\n=== PFPDIAG -- " (itoa (length found)) " of "
                     (itoa (length *pfp-controls*)) " controls resolved ==="))
     (if miss
       (progn
         (prompt "\n  MISSING (check the (Name) in Studio):")
         (foreach nm (reverse miss) (prompt (strcat "\n    " nm))))
       (prompt "\n  All control names resolve."))
     (prompt "\n=== end of PFPDIAG ===")))
  (princ))

;; (pfp:callable-p fname) -> T | nil
;;   MUST be checked before vl-catch-all-apply.  A "bad function" error -- an
;;   unbound symbol in the function position -- is raised BEFORE the catch
;;   engages, so the whole command aborts on the first name that does not exist.
;;   Catching works for a bad ARGUMENT, not for a bad FUNCTION.
;;   The detector: an unbound symbol evaluates to nil.  pfp:selfcheck proves
;;   that reading is sound against a function known to exist.
(defun pfp:callable-p (fname) (not (null (eval (read fname)))))

;; (pfp:selfcheck) -> nil   Does the "unbound evaluates to nil" test actually
;;   distinguish present from absent here?  dcl-Control-SetCaption is known
;;   good (it visibly repaints btnHelp), so it must read as callable.  If this
;;   prints anything but T, every "no such function" below is untrustworthy.
(defun pfp:selfcheck ()
  (prompt (strcat "\n  [detector self-check: dcl-Control-SetCaption callable -> "
                  (if (pfp:callable-p "dcl-Control-SetCaption") "T" "nil  <-- SUSPECT")
                  "]"))
  (princ))

;; (pfp:try fname args) -> "ok" | "no such function" | "FAILED -- <why>"
(defun pfp:try (fname args / r)
  (if (not (pfp:callable-p fname))
    "no such function"
    (progn
      (setq r (vl-catch-all-apply (read fname) args))
      (if (vl-catch-all-error-p r)
        (strcat "FAILED -- " (vl-catch-all-error-message r))
        "ok"))))

;; C:PFPPROBE -- why is a control that RESOLVES still showing nothing?
;;   Drives the controls directly; LOOK at the palette, do not just read the
;;   report.  [A] btnHelp is the control -- provably visible and caption-bearing,
;;   so it shows whether SetCaption works at all here.
;;   Read the results as a matrix: PALETTE-TESTING 2.3/2.4.
(defun c:PFPPROBE ( / )
  (cond
    ((not (pfp:ensure))
     (prompt "\nPFPPROBE: could not load the OpenDCL project."))
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPPROBE: run PFPALETTE first -- controls exist only while open."))
    (T
     (prompt "\n=== PFPPROBE -- watch the PALETTE, not just this report ===")
     (prompt (strcat "\n  [A] btnHelp    SetCaption -> "
                     (pfp:try "dcl-Control-SetCaption"
                              (list pfsuite/pfsPalette/btnHelp "<<PROBE-A>>"))))
     (prompt (strcat "\n  [B] lblProject SetCaption -> "
                     (pfp:try "dcl-Control-SetCaption"
                              (list pfsuite/pfsPalette/lblProject "<<PROBE-B>>"))))
     ;; No [C] SetText: these are Labels (Caption, no Text), and a missing
     ;; property raises the modal LISP cannot catch.  SetCaption is the setter.
     (prompt (strcat "\n  [D] lblProject SetVisible -> "
                     (pfp:try "dcl-Control-SetVisible"
                              (list pfsuite/pfsPalette/lblProject T))))
     (prompt (strcat "\n  [E] lblProject SetForeColor -> "
                     (pfp:try "dcl-Control-SetForeColor"
                              (list pfsuite/pfsPalette/lblProject 255))))
     (prompt "\n  Now LOOK at the palette:")
     (prompt "\n    Help button reads <<PROBE-A>>?   SetCaption works here.")
     (prompt "\n    Footer shows <<PROBE-B/C>>?      which setter is the right one.")
     (prompt "\n    Text appeared only after [D]/[E]? hidden or same-colour.")
     (prompt "\n  Toggle PFPALETTE off/on to restore -- Close destroys controls.")
     (prompt "\n=== end of PFPPROBE ===")))
  (princ))

;; (pfp:ask fname args) -> printable result | "no such function" | "-- <error>"
(defun pfp:ask (fname args / r)
  (if (not (pfp:callable-p fname))
    "no such function"
    (progn
      (setq r (vl-catch-all-apply (read fname) args))
      (if (vl-catch-all-error-p r)
        (strcat "-- " (vl-catch-all-error-message r))
        (vl-princ-to-string r)))))

;; (pfp:pause msg) -> nil   Stop so the operator can LOOK at the palette.
;;   Legal here: these are command-line diagnostics, not modeless handlers.
(defun pfp:pause (msg)
  (getstring (strcat "\n  >> " msg " -- look, then press Enter: "))
  (princ))

;; (pfp:read-ctrl nm ctrl) -> nil   dump every readable property of one control
(defun pfp:read-ctrl (nm ctrl / g)
  (prompt (strcat "\n  " nm ":"))
  ;; NO GetText: Labels have Caption and no Text, and a missing property raises
  ;; a MODAL dialog below LISP that vl-catch-all-apply cannot suppress.  Only
  ;; ask for properties known to exist.
  (foreach g '("GetCaption" "GetVisible" "GetEnabled"
               "GetLeft" "GetTop" "GetWidth" "GetHeight")
    (prompt (strcat "\n      " g "  -> "
                    (pfp:ask (strcat "dcl-Control-" g) (list ctrl)))))
  (princ))

;; C:PFPREAD -- read the RUNTIME state of the blank controls.  How to read it:
;;     - caption comes back with the probe string -> the control HOLDS the value
;;       and is not painting: covered, wrong tab, or z-order.
;;     - comes back empty -> the setter is not sticking despite returning ok, so
;;       the symbol is not the control we think it is (duplicate (Name)).
;;     - a 0 rect, or one nowhere near Studio's -> the RUNTIME rect is the fault.
;;       Studio shows design values; anchoring computes the real ones.
;;   btnHelp is dumped as the control -- it paints, so it shows what healthy
;;   looks like on this form.  tabMain because its background is the suspect for
;;   the gray box over the footer.
;;   RUN IT TWICE, docked and floating, and diff the dumps: nothing static
;;   changes between those states, so the difference is the bug.
(defun c:PFPREAD ( / )
  (cond
    ((not (pfp:ensure))
     (prompt "\nPFPREAD: could not load the OpenDCL project."))
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPREAD: run PFPALETTE first -- controls exist only while open."))
    (T
     (prompt "\n=== PFPREAD -- runtime state ===")
     (pfp:selfcheck)
     (prompt (strcat "\n  FORM  GetWidth  -> "
                     (pfp:ask "dcl-Form-GetWidth"  (list pfsuite/pfsPalette))))
     (prompt (strcat "\n  FORM  GetHeight -> "
                     (pfp:ask "dcl-Form-GetHeight" (list pfsuite/pfsPalette))))
     (pfp:read-ctrl "lblProject (BLANK)"  pfsuite/pfsPalette/lblProject)
     (pfp:read-ctrl "lblCounts  (BLANK)"  pfsuite/pfsPalette/lblCounts)
     (pfp:read-ctrl "btnHelp    (PAINTS)" pfsuite/pfsPalette/btnHelp)
     (pfp:read-ctrl "btnRefresh (PAINTS)" pfsuite/pfsPalette/btnRefresh)
     (pfp:read-ctrl "tabMain    (suspect)" pfsuite/pfsPalette/tabMain)
     (prompt "\n=== end of PFPREAD ===")
     (prompt "\n  Run this DOCKED and FLOATING, then diff the two dumps.")))
  (princ))

;; C:PFPDETAIL -- fill detailsList WITHOUT the event, to bisect an empty panel.
;;   Two causes look identical from outside: (1) tarLines#OnSelChanged never
;;   fires -- OpenDCL events are OPT-IN PER CONTROL and an unticked event calls
;;   nothing silently; (2) the handler fires but pfa:target-counts yields
;;   nothing.  Filling the first ANCHORED row directly separates them:
;;   panel fills -> tick the event in Studio.  Panel stays empty -> the fault is
;;   below the handler, and the row count printed here says how far it got.
(defun c:PFPDETAIL ( / reg row rows cnt)
  (cond
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPDETAIL: run PFPALETTE first."))
    ((null (setq reg (pfa:registry)))
     (prompt "\nPFPDETAIL: the registry is empty -- nothing to summarise."))
    ((null (setq row (car (vl-remove-if-not
                            '(lambda (r) (eq (caddr r) 'ANCHORED)) reg))))
     (prompt (strcat "\nPFPDETAIL: no ANCHORED line in the registry -- every"
                     " row is a stub, so every count is unknowable by design.")))
    (T
     (prompt (strcat "\nPFPDETAIL: filling from " (car row) " '" (cadr row) "'"))
     (setq cnt (vl-catch-all-apply 'pfa:target-counts (list (nth 3 row))))
     (cond
       ((vl-catch-all-error-p cnt)
        (prompt (strcat "\n  pfa:target-counts THREW: "
                        (vl-catch-all-error-message cnt))))
       ((null cnt)
        (prompt "\n  pfa:target-counts returned nil -- no xform, or no .cl bound."))
       (T
        (prompt (strcat "\n  counts ok: "
                        (itoa (cdr (assoc 'structures cnt))) " structure(s), "
                        (itoa (cdr (assoc 'crossings  cnt))) " crossing(s)"))))
     (setq rows (pfp:detail-rows row))
     (prompt (strcat "\n  rows built: " (itoa (length rows))))
     (pfp:fill-details row)
     (prompt (strcat "\n  Panel populated now?  YES -> the code is fine and"
                     " tarLines#OnSelChanged is not ticked in Studio."
                     "\n                        NO  -> the fault is the fill"
                     " itself; report the row count above."))))
  (princ))

;; C:PFPNUDGE -- find the repaint kick, if a repaint kick is what this needs.
;;   RUN IT DOCKED, with the gray box visible.  Each step re-sets the caption and
;;   tries one nudge; watch the footer and note WHICH step makes text appear.
;;   If nothing does, it is not a repaint fault -- the labels are covered, and
;;   PFPREAD's rects are the place to look.
;;   PAUSES BETWEEN STEPS ON PURPOSE: fired as a burst, only the final state is
;;   observable and there is no way to tell which nudge worked.
(defun c:PFPNUDGE ( / c)
  (cond
    ((not (pfp:ensure))
     (prompt "\nPFPNUDGE: could not load the OpenDCL project."))
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPNUDGE: run PFPALETTE first."))
    (T
     (setq c pfsuite/pfsPalette/lblProject)
     (prompt "\n=== PFPNUDGE -- WATCH THE FOOTER after each step ===")
     (pfp:selfcheck)
     (prompt (strcat "\n  [0] SetCaption <<NUDGE>>, no nudge -> "
                     (pfp:try "dcl-Control-SetCaption" (list c "<<NUDGE>>"))))
     (pfp:pause "[0] BASELINE -- text there already?")

     (prompt (strcat "\n  [1] SetEnabled nil/T (the old hack) -> "
                     (pfp:try "dcl-Control-SetEnabled" (list c nil)) " / "
                     (pfp:try "dcl-Control-SetEnabled" (list c T))))
     (pfp:pause "[1] enable-toggle")

     (prompt (strcat "\n  [2] SetVisible nil/T -> "
                     (pfp:try "dcl-Control-SetVisible" (list c nil)) " / "
                     (pfp:try "dcl-Control-SetVisible" (list c T))))
     (pfp:pause "[2] visible-toggle")

     (prompt (strcat "\n  [3] Control Update     -> "
                     (pfp:try "dcl-Control-Update" (list c))))
     (prompt (strcat "\n  [4] Control Invalidate -> "
                     (pfp:try "dcl-Control-Invalidate" (list c))))
     (prompt (strcat "\n  [5] Form Update        -> "
                     (pfp:try "dcl-Form-Update" (list pfsuite/pfsPalette))))
     (prompt (strcat "\n  [6] Form Invalidate    -> "
                     (pfp:try "dcl-Form-Invalidate" (list pfsuite/pfsPalette))))
     (pfp:pause "[3]-[6] whichever of those existed")

     (prompt "\n  Which step made <<NUDGE>> appear?  That is the fix.")
     (prompt "\n  None -> not a repaint fault.  Use PFPREAD / PFPMOVE.")
     (prompt "\n=== end of PFPNUDGE ===")))
  (princ))

;; C:PFPMOVE -- is the label CLIPPED by its parent, or COVERED by a sibling?
;;   The labels read as visible, enabled and captioned but sit at Top ~630, below
;;   tabMain's 606-tall client -- so if their coordinates are in tabMain's space
;;   they are past the bottom of their own parent.  Move one somewhere legal in
;;   EITHER space and look: appears -> it was clipped or covered at home; stays
;;   hidden -> position is not the mechanism.
;;   Reversible by toggling PFPALETTE (Close rebuilds from the .odcl).
;;   MAY POP MODAL DIALOGS -- SetLeft/SetTop are not attested.  Dismiss them;
;;   the report still prints.
(defun c:PFPMOVE ( / c)
  (cond
    ((not (pfp:ensure))
     (prompt "\nPFPMOVE: could not load the OpenDCL project."))
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPMOVE: run PFPALETTE first."))
    (T
     (setq c pfsuite/pfsPalette/lblProject)
     (prompt "\n=== PFPMOVE -- lblProject to (60,120), 400x30 ===")
     (pfp:try "dcl-Control-SetCaption" (list c "<<MOVED-lblProject>>"))
     (prompt (strcat "\n  SetLeft   -> " (pfp:try "dcl-Control-SetLeft"   (list c 60))))
     (prompt (strcat "\n  SetTop    -> " (pfp:try "dcl-Control-SetTop"    (list c 120))))
     (prompt (strcat "\n  SetWidth  -> " (pfp:try "dcl-Control-SetWidth"  (list c 400))))
     (prompt (strcat "\n  SetHeight -> " (pfp:try "dcl-Control-SetHeight" (list c 30))))
     (prompt "\n  LOOK: does <<MOVED-lblProject>> appear over the Registry tab?")
     (prompt "\n    YES -> it was clipped or covered where it lives.")
     (prompt "\n    NO  -> position is not the mechanism.")
     (prompt "\n  Toggle PFPALETTE off/on to restore.")
     (prompt "\n=== end of PFPMOVE ===")))
  (princ))

;; C:PFPDBMOD -- the write-free contract as a DELTA, not an absolute.
;;   DBMOD 0 is not reachable in general (opening a drawing can set it), so the
;;   contract is that opening and driving the palette CHANGES NOTHING.
;;   Mark, act, re-run, compare.
(defun c:PFPDBMOD ( / cur)
  (setq cur (getvar "DBMOD"))
  (if *pfp-dbmod-mark*
    (prompt (strcat "\nPFPDBMOD: " (itoa *pfp-dbmod-mark*) " -> " (itoa cur)
                    (if (= *pfp-dbmod-mark* cur)
                      "   UNCHANGED -- write-free."
                      "   CHANGED -- a read path wrote.  Find it.")))
    (prompt (strcat "\nPFPDBMOD: mark set at " (itoa cur)
                    ".  Act, then run PFPDBMOD again.")))
  (setq *pfp-dbmod-mark* cur)
  (princ))


;;; ==========================================================================
;;; SECTION 7  --  Native look:  the colour/font skin and the geometry probe
;;; ==========================================================================
;;
;; Mostly INHERIT, because the controls carrying this palette's content cannot
;; be coloured at all:
;;   Tree      -- NO colour property of any kind.  Font only.
;;   List View -- Background, but NO Foreground.
;;   Frame, Tab Strip -- neither.  Font only.
;;   Label, Option List, Check Box -- both.
;; So a dark scheme is not reachable -- the trees would stay light and the List
;; Views would take black text on a dark pane.  DARK COMES FROM THE WINDOWS
;; THEME, which the Tree and List common controls follow on their own.  What
;; this section does is unify the FONT across all 29 controls, set the form
;; background, and give the two Labels a real foreground.
;;
;; THE RULE: check the property page's applies-to list, never infer a property
;; from a similar control -- a missing property is the uncatchable modal.
;;
;; UI-only, no drawing write, so modeless-legal.  Confirm with PFPDBMOD.
;; Runtime formatting does not persist -- Close destroys the controls -- so
;; pfp:skin runs on every open, from C:PFPALETTE.

;; ---- tunables -- plain setq, so re-loading the suite restores the defaults

;; HOW MUCH to paint.
;;   'off  -- nothing; inherit everything.
;;   'font -- (DEFAULT) font on all 29 controls, form background, and Label
;;            colours.  Every call is documented for that control's type, and
;;            nothing here can be overridden by a visual style.
;;   'full -- adds Option List, Check Box and List View backgrounds.  Opt-in,
;;            because both caveats under `the capability table' below apply.
(setq *pfp-skin-mode* 'font)

;; WHICH colours.
;;   'sys   -- (DEFAULT) the OpenDCL system-colour enumeration.  Tracks the
;;             WINDOWS theme, which is also what the Tree and List controls
;;             do on their own, so the palette stays internally consistent.
;;   'theme -- RGB chosen off COLORTHEME.  See the dark-theme note below
;;             before reaching for this.
(setq *pfp-skin-scheme* 'sys)

;; The system enumeration (PALETTE-LAYOUT 8).  A Color may be a negative
;; logical value OR an (R G B) list -- both are documented, and the list form
;; is why no bit-packing helper exists here.
(setq *pfp-scheme-sys*
  '((chrome-bg -16) (chrome-fg -19)      ; button face / button text
    (data-bg    -6) (data-fg    -9)))    ; window / window text

;; STARTING VALUES, NOT A SPEC.  Autodesk publishes no RGB for palette chrome --
;; the documented dark value (33,40,48) is the drawing area, not the frame.
;; Eyedropper a docked Properties palette and correct these.  Kept even though a
;; dark pass cannot be completed (see the section note): the light side is
;; harmless and this is where measured values would go.
(setq *pfp-scheme-dark*
  '((chrome-bg  55  55  55) (chrome-fg 220 220 220)
    (data-bg    43  43  43) (data-fg   220 220 220)))

(setq *pfp-scheme-light*
  '((chrome-bg 240 240 240) (chrome-fg   0   0   0)
    (data-bg   255 255 255) (data-fg     0   0   0)))

;; Font.  "MS Shell Dlg" is OpenDCL's own default and the standard dialog font in
;; every localized Windows -- more native than naming Segoe UI.  nil leaves fonts
;; alone.  SIZE SIGN: negative is screen pixels, positive is points, and points
;; are the DPI-aware form.  A real size also masks the Studio-side `Font Size 0'
;; behind the blank footer labels, for as long as the skin runs.
(setq *pfp-font-name* "MS Shell Dlg")
(setq *pfp-font-size* 9)

;; ---- the capability table -------------------------------------------------
;; A property may only be called on a type the vendor documents it for: a missing
;; PROPERTY is the uncatchable modal, and pfp:try guards only a missing FUNCTION.
;; These applies-to lists come off the property reference pages, which are the
;; authority -- never a guess from what a similar control accepts.
;;   Font / Font Size ... every type below.  The broadest of the four, and why
;;                        'font mode can cover all 29 controls.
;;   Background Color ... label list optlist check + the Palette form.
;;                        NOT tree, NOT frame, NOT tab, NOT button.
;;   Foreground Color ... label optlist check.
;;                        NOT list, NOT tree, NOT frame, NOT tab, NOT button.
;; Two caveats behind 'full: a List View has no Foreground, so darkening it
;; leaves black text on a dark pane; and check/frame/optlist/tab/button carry
;; `Use Visual Style', which MAY OVERRIDE both colours -- so a colour set there
;; may silently do nothing, and switching the style off looks less native.
(setq *pfp-control-types*
  '(("tabMain" . tab)
    ("lblProject" . label) ("lblCounts" . label)
    ("btnRefresh" . button) ("btnHelp" . button)
    ("tvwLines" . tree) ("metaList" . list) ("lvwLinkage" . list)
    ("btnPickCL" . button) ("btnPickINV" . button) ("btnPickTOP" . button)
    ("btnPickDESIGN" . button) ("btnPickEXIST" . button)
    ("btnAnchor" . button) ("btnEdit" . button) ("btnNew" . button)
    ("btnRemove" . button) ("btnZoom" . button)
    ("tarLines" . tree)
    ("frmLabel" . frame) ("optLabel" . optlist)
    ("frmTools" . frame) ("optTools" . optlist)
    ("frmOptions" . frame) ("optRun" . optlist)
    ("detailsList" . list)
    ;; THE TABLE FOLLOWS STUDIO, NEVER THE (Name): `lvw` here read as List View
    ;; on paper for a week while the control was a List Box on screen.
    ("lvwCommand" . list)
    ("chkbxZoom" . check)
    ("btnClear" . button) ("btnRun" . button)))

;; Types that accept each colour, per the applies-to lists above.
(setq *pfp-can-backcolor* '(label list optlist check))
(setq *pfp-can-forecolor* '(label optlist check))

;; Types 'font mode is allowed to colour.  Label only: the one type that takes
;; BOTH colours, has no visual style to override it, and carries the blank-label
;; bug.
(setq *pfp-font-mode-colour* '(label))

;; Which scheme row a type reads.  The capability table blocks every colour on a
;; Tree and the foreground on a List View, so `data' only ever reaches a List
;; View background, and only in 'full mode.
(setq *pfp-data-types* '(list tree))

;; Design size, mirrored from Studio (PALETTE-LAYOUT 2) because there is no
;; form-size getter -- dcl-Form-GetWidth does not exist.  A STUDIO SIZE CHANGE IS
;; A TWO-FILE EDIT, permanently: nothing here can detect the divergence.
;; Only C:PFPSCALE reads it, which is why a stale copy is survivable -- PFPSCALE
;; is a probe whose effects are undone by toggling the palette, and nothing on
;; the open path reads it.  Min/Max Width, which actually decide the opening
;; rect, are Studio's alone and are not mirrored here at all.
(setq *pfp-design-size* '(420 670))

;; Baseline rects for PFPSCALE, captured once per session so repeated scaling
;; compounds from the design layout instead of from the last scaled one.
(if (not (boundp '*pfp-rect-base*)) (setq *pfp-rect-base* nil))


;; (pfp:colour scheme key) -> Color value | nil
;;   A scheme row is (key r g b) or (key <negative logical>); both are documented
;;   Color values, so the triple passes through as a list.  NOTHING here
;;   bit-packs a colour -- the packed form's byte order is undocumented.
(defun pfp:colour (scheme key / v)
  (setq v (cdr (assoc key scheme)))
  (cond ((null v) nil)
        ((= 1 (length v)) (car v))
        (T v)))

;; (pfp:scheme) -> the scheme alist to paint with
(defun pfp:scheme ( / ct)
  (if (eq *pfp-skin-scheme* 'sys)
    *pfp-scheme-sys*
    ;; COLORTHEME: 0 dark, 1 light.  getvar returns nil on a release that
    ;; predates it -- treat that as light, the pre-theme default.
    (progn
      (setq ct (getvar "COLORTHEME"))
      (if (and ct (= 0 ct)) *pfp-scheme-dark* *pfp-scheme-light*))))

;; (pfp:type-can nm prop) -> T | nil    prop is 'bg | 'fg | 'font
;;   THE GUARD THAT MATTERS, and it guards READS as much as writes: a getter is a
;;   property accessor too, so GetForeColor on a List View raises the same modal
;;   the setter would.  pfp:try catches a missing FUNCTION, this a missing
;;   PROPERTY.
(defun pfp:type-can (nm prop / ty)
  (setq ty (cdr (assoc nm *pfp-control-types*)))
  (cond
    ((null ty) nil)                       ; unknown name -> touch nothing
    ((eq prop 'font) T)                   ; every type here takes Font+FontSize
    ((eq prop 'bg) (and (member ty *pfp-can-backcolor*) T))
    (T             (and (member ty *pfp-can-forecolor*) T))))

;; (pfp:may nm prop) -> T | nil   capability AND what the mode permits
(defun pfp:may (nm prop / ty)
  (setq ty (cdr (assoc nm *pfp-control-types*)))
  (and (pfp:type-can nm prop)
       (or (eq prop 'font)
           (not (eq *pfp-skin-mode* 'font))
           (and (member ty *pfp-font-mode-colour*) T))))

;; (pfp:skin-one nm bg fg size) -> list of "<call> -> <result>" strings
;;   One control, every property its TYPE accepts and the mode allows.  Also
;;   routed through pfp:try, so a setter this build lacks reports "no such
;;   function" instead of aborting the pass.  The two guards cover different
;;   failures and both are needed.
(defun pfp:skin-one (nm bg fg size / c out p)
  (setq c   (eval (read (strcat "pfsuite/pfsPalette/" nm)))
        out '())
  (if (null c)
    (setq out (list (strcat "control is nil -- " nm)))
    ;; Vendor names, not inferred: the properties are Font and FontSize -- there
    ;; is no FontName and no FontHeight.
    (foreach p (list (list "dcl-Control-SetBackColor" bg              'bg)
                     (list "dcl-Control-SetForeColor" fg              'fg)
                     (list "dcl-Control-SetFont"      *pfp-font-name* 'font)
                     (list "dcl-Control-SetFontSize"  size            'font))
      (if (and (cadr p) (pfp:may nm (caddr p)))
        (setq out (cons (strcat (car p) " -> " (pfp:try (car p) (list c (cadr p))))
                        out)))))
  (reverse out))

;; (pfp:tally lines) -> ((line . count) ...)
;;   29 controls give 29 copies of the same result line.  Collapsing them makes
;;   the report four lines when it works, and names the outlier when it does not.
(defun pfp:tally (lines / acc s hit)
  (setq acc '())
  (foreach s lines
    (if (setq hit (assoc s acc))
      (setq acc (subst (cons s (1+ (cdr hit))) hit acc))
      (setq acc (cons (cons s 1) acc))))
  (reverse acc))

;; (pfp:skin verbose size) -> nil
;;   THE one formatting entry point, mirroring pfp:refresh for data.  size nil
;;   means *pfp-font-size*; PFPSCALE passes a scaled one.  Silent unless
;;   something failed, so the call from C:PFPALETTE costs no console noise.
(defun pfp:skin (verbose size / scheme cbg cfg dbg dfg lines nm ty r)
  (if (null size) (setq size *pfp-font-size*))
  (cond
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (if verbose (prompt "\n  skin: the palette is closed -- nothing to paint.")))
    ((eq *pfp-skin-mode* 'off)
     (if verbose (prompt "\n  skin: mode is 'off -- inheriting the host.")))
    (T
     (setq scheme (pfp:scheme)
           cbg    (pfp:colour scheme 'chrome-bg)
           cfg    (pfp:colour scheme 'chrome-fg)
           dbg    (pfp:colour scheme 'data-bg)
           dfg    (pfp:colour scheme 'data-fg)
           ;; The form is a Palette, which IS in Background Color's applies-to
           ;; list.  Foreground is not, so the form takes a background only.
           lines  (list (strcat "dcl-Form-SetBackColor -> "
                                (pfp:try "dcl-Form-SetBackColor"
                                         (list pfsuite/pfsPalette cbg)))))
     ;; Every control in the roster, every time -- pfp:may decides what each one
     ;; receives, so there is no second list to drift out of step.
     (foreach nm *pfp-controls*
       (setq ty (cdr (assoc nm *pfp-control-types*)))
       (if (member ty *pfp-data-types*)
         (setq lines (append lines (pfp:skin-one nm dbg dfg size)))
         (setq lines (append lines (pfp:skin-one nm cbg cfg size)))))
     ;; Report every distinct outcome when verbose; only the failures when not.
     (foreach r (pfp:tally lines)
       (if (or verbose (not (wcmatch (car r) "*-> ok")))
         (prompt (strcat "\n  " (itoa (cdr r)) "x  " (car r)))))))
  (princ))

;; C:PFPTHEME -- re-apply the skin now, verbosely, and read back what landed.
;;   COLORTHEME can be flipped while the palette is open and nothing tells the
;;   form, so run this after a theme flip or after editing the scheme tables.
;;   (A vlr-sysvar-reactor would automate it; not installed, because a reactor
;;   outlives the palette -- PALETTE-LAYOUT 10.)
(defun c:PFPTHEME ( / ct g L D)
  (cond
    ((not (pfp:ensure))
     (prompt "\nPFPTHEME: could not load the OpenDCL project."))
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPTHEME: the palette is CLOSED -- run PFPALETTE first."))
    (T
     (setq ct (getvar "COLORTHEME"))
     (prompt (strcat "\n=== PFPTHEME -- COLORTHEME "
                     (if ct (itoa ct) "(unavailable)")
                     (cond ((null ct) "") ((= 0 ct) " (dark)") (T " (light)"))
                     ",  mode "   (vl-princ-to-string *pfp-skin-mode*)
                     ",  scheme " (vl-princ-to-string *pfp-skin-scheme*) " ==="))
     (pfp:selfcheck)
     (pfp:skin T nil)
     ;; Read back a Label and a List View: a setter returning ok while the getter
     ;; reports the old value is the difference between "the call exists" and
     ;; "the call took".  Capability-gated like the writes.
     (setq L "lblProject" D "metaList")
     (prompt "\n  readback            lblProject (Label)   |   metaList (List View)")
     (foreach g '(("GetBackColor" . bg)   ("GetForeColor" . fg)
                  ("GetFont"      . font) ("GetFontSize"  . font))
       (prompt (strcat "\n    " (car g) "  " (pfp:peek L (car g) (cdr g))
                       "   |   "            (pfp:peek D (car g) (cdr g)))))
     (prompt "\n  n/a = the vendor does not document that property for that type.")
     (prompt "\n=== end of PFPTHEME ===")))
  (princ))

;; (pfp:peek nm getter prop) -> printable value | "n/a"
;;   Capability-gated read.  See pfp:type-can for why a getter needs the gate.
(defun pfp:peek (nm getter prop / c)
  (if (and (pfp:type-can nm prop)
           (setq c (eval (read (strcat "pfsuite/pfsPalette/" nm)))))
    (pfp:ask (strcat "dcl-Control-" getter) (list c))
    "n/a"))

;; (pfp:num fname ctrl) -> number | nil   guarded numeric read
(defun pfp:num (fname ctrl / r)
  (if (pfp:callable-p fname)
    (progn
      (setq r (vl-catch-all-apply (read fname) (list ctrl)))
      (if (and (not (vl-catch-all-error-p r)) (numberp r)) r))))

;; (pfp:capture) -> ((nm l t w h) ...)   read every rect the roster resolves
(defun pfp:capture ( / out nm c l tp w h)
  (setq out '())
  (foreach nm *pfp-controls*
    (if (setq c (eval (read (strcat "pfsuite/pfsPalette/" nm))))
      (progn
        (setq l  (pfp:num "dcl-Control-GetLeft"   c)
              tp (pfp:num "dcl-Control-GetTop"    c)
              w  (pfp:num "dcl-Control-GetWidth"  c)
              h  (pfp:num "dcl-Control-GetHeight" c))
        (if (and l tp w h) (setq out (cons (list nm l tp w h) out))))))
  (reverse out))

;; (pfp:scale-to f v) -> integer   round, never to zero
(defun pfp:scale-to (f v) (max 1 (fix (+ 0.5 (* f v)))))

;; (pfp:move-one nm l tp w h) -> list of "<call> -> <result>" strings
;;   The four setters are NOT attested (PALETTE-TESTING 1.7g never ran), so
;;   each is guarded and the tally names whichever one this build lacks.
(defun pfp:move-one (nm l tp w h / c out p)
  (setq c   (eval (read (strcat "pfsuite/pfsPalette/" nm)))
        out '())
  (if (null c)
    (setq out (list (strcat "control is nil -- " nm)))
    (foreach p (list (cons "dcl-Control-SetLeft"   l)
                     (cons "dcl-Control-SetTop"    tp)
                     (cons "dcl-Control-SetWidth"  w)
                     (cons "dcl-Control-SetHeight" h))
      (setq out (cons (strcat (car p) " -> " (pfp:try (car p) (list c (cdr p))))
                      out))))
  (reverse out))

;; (pfp:font-at f) -> font size scaled by f, SIGN PRESERVED | nil
;;   The sign picks the unit (negative pixels, positive points) and pfp:scale-to
;;   floors at 1, so scaling a negative size directly would return 1 and switch
;;   units as well as resizing.  Scale the magnitude, put the sign back.
(defun pfp:font-at (f)
  (if *pfp-font-size*
    (* (if (minusp *pfp-font-size*) -1 1)
       (pfp:scale-to f (abs *pfp-font-size*)))))

;; C:PFPSCALE -- geometry probe, X and Y independent.
;;   STUDIO OWNS THE GEOMETRY.  This is how you find the factors by looking at
;;   them, so the resulting rects can be typed into Studio.  Nothing it does
;;   survives a palette toggle, which is also the undo.
;;   X and Y are separate because a native palette is a narrow, tall strip: the
;;   useful experiment is X well under 1 with Y at or above 1.  Enter one factor
;;   and take the default on the second for uniform.
;;     X scales Left and Width;  Y scales Top and Height.
;;   X DOES NOT MOVE THE FRAME: Studio pins Min Width = Max Width, so Form-Resize
;;   is clamped both ways and only the controls move.  Read the controls, not the
;;   gap.  The five fixed-width Registry button rows have no layout flow to
;;   redistribute into, so captions clip well before 0.33 -- reflowing those rows
;;   is an unscheduled redesign.  Use this to trim 10-20% on X.
;;   FONTS FOLLOW THE SMALLER FACTOR: glyphs do not stretch on one axis, so the
;;   text still has to fit the X-narrowed box.
(defun c:PFPSCALE ( / fx fy w h r lines rect e)
  (cond
    ((not (pfp:ensure))
     (prompt "\nPFPSCALE: could not load the OpenDCL project."))
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPSCALE: the palette is CLOSED -- run PFPALETTE first."))
    (T
     (if (null *pfp-rect-base*)
       (progn
         (setq *pfp-rect-base* (pfp:capture))
         (prompt (strcat "\n  baseline captured from "
                         (itoa (length *pfp-rect-base*)) " controls."))))
     (if (null *pfp-rect-base*)
       (prompt "\nPFPSCALE: no rect getter returned a number -- cannot scale.")
       (progn
         (initget 6)                       ; no zero, no negative
         (setq fx (getreal "\nX factor (Left + Width) <0.85>: "))
         (if (null fx) (setq fx 0.85))
         (initget 6)
         (setq fy (getreal (strcat "\nY factor (Top + Height) <"
                                   (rtos fx 2 3) ">: ")))
         (if (null fy) (setq fy fx))       ; same on both -> uniform
         (setq w (pfp:scale-to fx (car  *pfp-design-size*))
               h (pfp:scale-to fy (cadr *pfp-design-size*)))
         (prompt (strcat "\n=== PFPSCALE  X x" (rtos fx 2 3)
                         "  Y x" (rtos fy 2 3)
                         "  -- form -> " (itoa w) " x " (itoa h) " ==="))
         (setq r (pfp:try "dcl-Form-Resize" (list pfsuite/pfsPalette w h)))
         (prompt (strcat "\n  dcl-Form-Resize -> " r))
         (if (/= w (car *pfp-design-size*))
           (prompt (strcat "\n  NOTE: Studio pins Min Width = Max Width = "
                           (itoa (car *pfp-design-size*))
                           " -- the FRAME will not move; only the controls do.")))
         (setq lines '())
         (foreach rect *pfp-rect-base*
           (setq lines (append lines
                               (pfp:move-one (car rect)
                                             (pfp:scale-to fx (cadr   rect))
                                             (pfp:scale-to fy (caddr  rect))
                                             (pfp:scale-to fx (cadddr rect))
                                             (pfp:scale-to fy (last   rect))))))
         (foreach e (pfp:tally lines)
           (prompt (strcat "\n  " (itoa (cdr e)) "x  " (car e))))
         ;; Text has to scale with the box or the exercise is pointless.
         (if *pfp-font-size* (pfp:skin nil (pfp:font-at (min fx fy))))
         (prompt "\n  LOOK, then toggle PFPALETTE off/on to restore.")
         (prompt "\n  Keep them?  Multiply the Studio rects per axis in Studio.")
         (prompt "\n=== end of PFPSCALE ===")))))
  (princ))


;;; ==========================================================================
;;; SECTION 8  --  Phase 3: the registry verbs  (one ticket, one dispatcher)
;;; ==========================================================================
;;; A modeless handler may not write, so no button acts.  Each records WHAT to do
;;; in *pfp-verb* and queues ONE command through pfp:defer; C:PFPVERB picks the
;;; ticket up in a real command context and runs it under pf:run-command.
;;; One dispatcher rather than five commands: the CMDACTIVE gate, the ticket
;;; discipline and the refresh belong in one place.
;;; Anchor and Edit need NO typed fields -- identity and the .cl come from the
;;; registry row, scales and datum are prompted by pfsetup at the command line.

(if (not (boundp '*pfp-verb*)) (setq *pfp-verb* nil))  ; (verb . reg-row)
(if (not (boundp '*pfp-sel*))  (setq *pfp-sel*  nil))  ; the tree selection

;; (pfp:fire verb row) -> T | nil
;;   THE only path from a button to a write.  The ticket is dropped again if
;;   the defer is refused: a ticket left behind after a refusal would fire on
;;   the NEXT verb, running yesterday's row.
(defun pfp:fire (verb row)
  (setq *pfp-verb* (cons verb row))
  (cond ((pfp:defer "PFPVERB") T)
        (T (setq *pfp-verb* nil) nil)))

;; (pfp:need-row row state) -> reg-row | nil
;;   Guard every verb shares: something selected, and in the right state.
;;   state 'ANCHORED | 'STUB | nil (either).  Reports rather than no-ops -- a
;;   button that does nothing silently is the palette's worst failure mode.
;;   Takes the row because the two tabs remember their selections separately
;;   (*pfp-sel* / *pfp-tar-sel*) and need the identical guard.
(defun pfp:need-row (row state)
  (cond
    ((null row) (prompt "\nPFPALETTE: select a line first.") nil)
    ((and (eq state 'ANCHORED) (not (eq (caddr row) 'ANCHORED)))
     (prompt (strcat "\nPFPALETTE: '" (cadr row)
                     "' is Registered, not Anchored -- use Anchor."))
     nil)
    ((and (eq state 'STUB) (eq (caddr row) 'ANCHORED))
     (prompt (strcat "\nPFPALETTE: '" (cadr row)
                     "' is already Anchored -- use Edit."))
     nil)
    (T row)))

;; (pfp:need-sel state) -> reg-row | nil   The Registry tab's selection.
(defun pfp:need-sel (state) (pfp:need-row *pfp-sel* state))

;; (pfp:row->res row) -> placement record   (Registered row -> Anchor)
;;   Type, Line and the file bindings come straight off the registry row, which
;;   is why Anchor needs no typed fields.  hs, vs and datum are DELIBERATELY
;;   ABSENT: a record missing them is what makes pfsetup prompt at the command
;;   line instead of opening the modal (pfs:complete-res).  Material seeds from
;;   the per-type memory -- the same default the dialog would have shown.
(defun pfp:row->res (row / stub ty mat pro)
  (setq stub (nth 4 row)
        ty   (car row)
        mat  (cdr (assoc (strcase ty) *pfs-mat-last*))
        pro  '())
  (if (and (nth 3 stub) (/= (nth 3 stub) ""))
    (setq pro (append pro (list (nth 3 stub)))))
  (if (and (nth 4 stub) (/= (nth 4 stub) ""))
    (setq pro (append pro (list (nth 4 stub)))))
  (list (cons 'type ty)
        (cons 'name (cadr row))
        (cons 'cl   (nth 2 stub))
        (cons 'pro  pro)
        (cons 'tin  '())
        (cons 'material (if mat mat ""))
        (cons 'repick nil)))

;; EDIT DOES NOT BUILD A RECORD, deliberately.  Anchor can be promptable because
;; everything it needs is on the registry row and only three numbers are missing.
;; Edit exists to change what is BOUND (material, the _INV/_TOP pair, the two
;; surfaces), and there is no prompt-shaped equivalent of a file picker with role
;; validation -- so it sends no preset and pfsetup opens the modal, seeded from
;; the stored record by pfs:anchor-init.

;; (pfp:zoom-anchor anchor) -> nil   Frame one grid.  COMMAND CONTEXT ONLY --
;;   pf:zoom-cwh issues ZOOM, so this is reachable from C:PFPVERB and nowhere
;;   else.  Falls back to the current view height when the record carries no
;;   extents (a legacy anchor).
(defun pfp:zoom-anchor (anchor / ins ext w h)
  (setq ins (cdr (assoc 10 (entget anchor)))
        ext (pfa:extents anchor)
        w   (car ext)
        h   (cadr ext))
  (if (and h (> h 0.0))
    (pf:zoom-cwh (list (+ (car ins) (* 0.5 (if w w 0.0)))
                       (+ (cadr ins) (* 0.5 h))
                       0.0)
                 (* 1.15 h))
    (progn
      (prompt "\n  No extents on record (legacy anchor) -- centering only.")
      (pf:zoom-cwh (list (car ins) (cadr ins) 0.0) (getvar "VIEWSIZE"))))
  (princ))

;; (pfp:verb-run) -> nil   The dispatcher body, under pf:run-command.
(defun pfp:verb-run ( / tkt verb row)
  ;; READ ONCE, CLEARED -- one setq, no window.  A ticket that survived a
  ;; failed run would re-fire on the next PFPVERB against a stale row.
  (setq tkt        *pfp-verb*
        *pfp-verb* nil
        verb       (car tkt)
        row        (cdr tkt))
  (cond
    ((null tkt) (prompt "\nPFPVERB: no pending action (run it from the palette)."))
    ;; The preset is what suppresses the modal.  Set it IMMEDIATELY before the
    ;; call that consumes it -- pfs:place-one / pfs:edit-one read and clear it
    ;; in their first setq, so it is live for one statement.
    ((eq verb 'anchor)
     (setq *pfs-preset-res* (pfp:row->res row))
     (pfs:place-one (nth 4 row)))
    ;; Edit and New send NO preset, so pfsetup opens the modal.  That is the
    ;; break-out path in both cases -- see the note above pfp:zoom-anchor.
    ((eq verb 'edit)   (pfs:edit-one  (nth 3 row)))
    ((eq verb 'new)    (pfs:place-one nil))
    ((eq verb 'zoom)   (pfp:zoom-anchor (nth 3 row)))
    ;; Remove ZOOMS FIRST, so the confirm modal opens over a view of what is
    ;; about to die -- that pairing is why the palette's Remove beats typing
    ;; PFREMOVE.  Then straight to pfrem:remove-anchor: same confirm, teardown
    ;; and undo group as the command line, and no preset global.
    ;; The entget is a staleness guard: the panel is only as fresh as the last
    ;; pfp:refresh, and tearing down a dead ename dies inside
    ;; pfa:teardown-counts.  'zoom and 'edit are NOT guarded -- neither is
    ;; destructive, and widening this is a separate decision.
    ((eq verb 'remove)
     (if (entget (nth 3 row))
       (progn (pfp:zoom-anchor      (nth 3 row))
              (pfrem:remove-anchor  (nth 3 row)))
       (prompt (strcat "\nPFPVERB: '" (cadr row)
                       "' is already gone -- the panel was stale. Refreshing."))))
    (T (prompt (strcat "\nPFPVERB: unknown action " (vl-princ-to-string verb)))))
  ;; Belt to the read-and-clear brace: a preset left live by a throw above would
  ;; reach the next command-line PFSETUP and place someone else's record.
  (setq *pfs-preset-res* nil)
  ;; the registry moved (or did not) -- either way the panels are now stale
  (pfp:refresh)
  (princ))

;; C:PFPVERB -- the ONE SendCommand target for every palette write.
;;   Additional to the frozen entry points, never a replacement: PFSETUP and
;;   PFREMOVE keep working untouched.
(defun c:PFPVERB ()
  (pf:run-command "PFPVERB" nil 'pfp:verb-run))


;;; ---- the button handlers -------------------------------------------------
;;; Verbs defer.  btnRefresh is the ONE exception: pfp:refresh is a pure read,
;;; so it runs inline.

(defun c:pfsuite/pfsPalette/btnAnchor#OnClicked ( / row)
  (if (setq row (pfp:need-sel 'STUB)) (pfp:fire 'anchor row))
  (princ))

(defun c:pfsuite/pfsPalette/btnEdit#OnClicked ( / row)
  (if (setq row (pfp:need-sel 'ANCHORED)) (pfp:fire 'edit row))
  (princ))

(defun c:pfsuite/pfsPalette/btnNew#OnClicked ()
  ;; No selection, no record: pfs:place-one with no preset opens the modal.
  ;; Still deferred -- start_dialog needs a command context as much as getpoint.
  (pfp:fire 'new nil)
  (princ))

(defun c:pfsuite/pfsPalette/btnZoom#OnClicked ( / row)
  (if (setq row (pfp:need-sel 'ANCHORED)) (pfp:fire 'zoom row))
  (princ))

;; Guarded to ANCHORED: a Registered stub has no anchor and no ledger, so there
;; is nothing to tear down.  The confirm modal stays -- deferring moves the
;; dialog into a command context, it does not replace it.
(defun c:pfsuite/pfsPalette/btnRemove#OnClicked ( / row)
  (if (setq row (pfp:need-sel 'ANCHORED)) (pfp:fire 'remove row))
  (princ))

;; btnRefresh REPORTS, and the report lives in the HANDLER rather than in
;; pfp:refresh: only the button has a user waiting on an acknowledgement, and
;; pfp:refresh is also the open and DocActivated path, where chatter is noise.
;; It doubles as the wiring test -- a line means the Studio tick is on and the
;; whole path ran; silence means the tick is off, or the (Name) is wrong (which
;; PFPDIAG names).  A direct prompt, not pf:progress, so it survives any
;; *pf-quiet* left bound by a read path.
(defun c:pfsuite/pfsPalette/btnRefresh#OnClicked ( / n anchored)
  (pfp:refresh)
  (setq n        (length *pfp-tree-map*)
        anchored (length (vl-remove-if-not
                           '(lambda (c) (eq (caddr (cdr c)) 'ANCHORED))
                           *pfp-tree-map*)))
  (prompt (strcat "\nPFPALETTE: refreshed -- " (itoa n) " line"
                  (if (= n 1) "" "s") " (" (itoa anchored) " anchored, "
                  (itoa (- n anchored)) " registered)."))
  (princ))


;;; ==========================================================================
;;; SECTION 9  --  Phase 4: the Commands tab  (one ticket, one dispatcher)
;;; ==========================================================================
;;; Twin of SECTION 8.  btnRun cannot write, so it records WHAT to run in
;;; *pfp-order* and queues ONE command through pfp:defer; C:PFPRUN picks the
;;; ticket up in a command context and hands it to pflabel:run / pfi:run /
;;; pfxl:run.
;;; THE GATHER IS HERE, NOT IN THE HANDLER -- the dispatcher is already in a
;;; command context, so Crossings stops being a special case (pfxl:discover is a
;;; writer and can never run modeless) and the numbers are read at RUN time.
;;; NO *pf-preset-target* GRAFT: the dispatcher calls the engines directly with
;;; the anchor off the registry row, so it never reaches pfs:choose-or-place.
;;; A Registered row is refused outright instead (pfp:need-row 'ANCHORED).
;;; TOOLS IS NOT WIRED -- frmTools/optTools are greyed and Label is permanently
;;; the active group, until a Carlson command name lands here.

(if (not (boundp '*pfp-order*)) (setq *pfp-order* nil))   ; the RUN ticket

;;; ---- reading the radios and the check box --------------------------------
;;; CHECK BOX ONLY, and the getter is GENERIC -- dcl_Control_GetValue, used on
;;; any control carrying a value (AUBlockTool_Final.lsp:33-36).  There is no
;;; dcl-OptionList-* or dcl-CheckBox-* family.  Hyphens first, underscores as the
;;; vendor-sample fallback.
;;; DO NOT ADD AN OPTION LIST GETTER BACK: GetValue on an Option List raises the
;;; modal "Property <Value> not found" AND returns nil to LISP, so it reads as a
;;; tidy nil in the report while having put a dialog on screen.  A Check Box does
;;; carry Value -- chkbxZoom answers 0 unticked, no dialog.
(setq *pfp-chk-getters* '("dcl-Control-GetValue" "dcl_Control_GetValue"))

;; What an Option List calls its first item: 0-based, measured.  Only the
;; caption-unrecognised fallback in pfp:opt-item still reads it.
(if (not (boundp '*pfp-opt-base*)) (setq *pfp-opt-base* 0))

;;; ---- Option Lists are read from their EVENT, not by a getter -------------
;;; OpenDCL passes the value into the handler (AUBlockTool_Final.lsp:101), so the
;;; palette remembers what the control last reported, the same way it remembers
;;; tree selections.  A plain setq; remembering touches nothing.
;;; STARTS EMPTY, AND AN UNOBSERVED GROUP REFUSES TO RUN.  Seeding it would be a
;;; guess about which pass to fire, and that error does not fail loudly -- it
;;; labels the wrong thing.  One click on the radio is exact.
(if (not (boundp '*pfp-opt-vals*)) (setq *pfp-opt-vals* '()))

;; (pfp:opt-remember nm Label Key) -> nil     stores (nm Label . Key)
;;   Keeps BOTH halves the event handed over: Label dispatches (see
;;   *pfp-opt-captions*), Key is the fallback if a caption is ever renamed.
(defun pfp:opt-remember (nm Label Key / cell)
  (setq *pfp-opt-vals*
          (if (setq cell (assoc nm *pfp-opt-vals*))
            (subst (list nm Label Key) cell *pfp-opt-vals*)
            (cons (list nm Label Key) *pfp-opt-vals*)))
  (princ))

;; WHICH ITEM IS WHICH, BY CAPTION -- not by index.  A wrong index base cannot
;;   fail loudly; it runs the wrong pass.  Patterns rather than equality because
;;   the .odcl's captions are not trustworthy to the character (btnClear's reads
;;   "CLear"), and a wildcard survives a typo or a re-word.
;;   THE optTools CAPTIONS ARE UNVERIFIED -- the .odcl is a binary Studio file --
;;   but matching by caption makes that safe: whichever slot Studio has them in,
;;   "*INV*" resolves to PFPROINV and "*TOP*" to PFPROTOP.  A caption matching
;;   neither is named by pfp:opt-item, and the fix is one pattern here.
;;   THE THIRD ITEM IS UNMAPPED ON PURPOSE: guessing a pattern for a command
;;   whose name is unknown would fire the WRONG command rather than refuse.
(setq *pfp-opt-captions*
  '(("optLabel" ("*STRUCT*"   . 0) ("*INVERT*" . 1) ("*CROSS*" . 2))
    ("optRun"   ("*OUTSTAND*" . 1) ("*ALL*"    . 0) ("*SEL*"   . 2))
    ("optTools" ("*INV*"      . 0) ("*TOP*"    . 1))))

;; SelChanged: an Option List offers NO Clicked event.
;; TWO ARGUMENTS, ORDER (nIndex sLabel) -- THE REVERSE OF THE TREE'S, which takes
;; (Label Key).  Do not "make this consistent" with the tree handler; they
;; genuinely differ, and binding them the wrong way round resolves to no caption
;; at all rather than erroring.  PFPCTL prints both halves.

;;; ---- which group RUN belongs to ------------------------------------------
;;; An active-group flag, because btnRun must never read "which radio has a
;;; selection" -- a radio group cannot un-select, so both groups stay filled.
;;; The greying half is NOT built: seven SetEnabled calls that only describe the
;;; decision this variable already makes.  Dispatch first, decoration after.
;;; WHY NOT FIRE ON SELECTION: with only SelChanged, picking-runs-it cannot
;;; re-run the item already selected -- no event fires and the palette looks
;;; broken.  RUN stays the verb; the radios stay nouns.
(if (not (boundp '*pfp-active-group*)) (setq *pfp-active-group* 'LABEL))

;; Label is the default: Structures is already the selected optLabel item, so no
;; third "nothing chosen yet" state is needed and RUN is never ambiguous.
(defun c:pfsuite/pfsPalette/optLabel#OnSelChanged (nIndex sLabel / )
  (setq *pfp-active-group* 'LABEL)
  (pfp:opt-remember "optLabel" sLabel nIndex)
  ;; the item list follows the command (SECTION 5c)
  (pfp:fill-items *pfp-tar-sel*)
  (princ))

(defun c:pfsuite/pfsPalette/optRun#OnSelChanged (nIndex sLabel / )
  ;; optRun MODIFIES the Label group rather than being a group of its own, so
  ;; touching it implies Label -- adjusting the mode last still leaves RUN armed.
  (setq *pfp-active-group* 'LABEL)
  (pfp:opt-remember "optRun" sLabel nIndex) (princ))

(defun c:pfsuite/pfsPalette/optTools#OnSelChanged (nIndex sLabel / )
  (setq *pfp-active-group* 'TOOLS)
  (pfp:opt-remember "optTools" sLabel nIndex) (princ))

;; (pfp:first-callable cands args) -> (fname . value) | nil
;;   Returns the NAME as well as the value: that is what makes PFPCTL able to
;;   report which accessor won without a second pass.
(defun pfp:first-callable (cands args / out r f)
  (setq out nil)
  (foreach f cands
    (if (and (null out) (pfp:callable-p f))
      (progn
        (setq r (vl-catch-all-apply (read f) args))
        (if (not (vl-catch-all-error-p r)) (setq out (cons f r))))))
  out)

;; (pfp:cap-match nm caption) -> (pattern . index) | nil
(defun pfp:cap-match (nm caption / p out)
  (setq out nil)
  (if (= (type caption) 'STR)
    (foreach p (cdr (assoc nm *pfp-opt-captions*))
      (if (and (null out) (wcmatch (strcase caption) (car p))) (setq out p))))
  out)

;; (pfp:opt-item ctrl nm) -> 0-based item index | nil
;;   READS NOTHING FROM THE CONTROL -- GetValue on an Option List puts a modal on
;;   screen (see *pfp-chk-getters*), so the event is the only source.  ctrl is
;;   still taken and checked: a control missing from the project is a different
;;   fault with a different fix.
;;   CAPTION BEFORE KEY: the caption cannot be read off by one.
(defun pfp:opt-item (ctrl nm / rec hit)
  (cond
    ((null ctrl)
     (prompt (strcat "\nPFPALETTE: control \"" nm "\" is not in the loaded"
                     " project -- check its (Name) in Studio."))
     nil)
    ((null (setq rec (assoc nm *pfp-opt-vals*)))
     (prompt (strcat "\nPFPALETTE: nothing has reported \"" nm "\" yet."
                     "  Click one item in that group."))
     nil)
    ((setq hit (pfp:cap-match nm (cadr rec))) (cdr hit))
    ((numberp (caddr rec)) (- (fix (caddr rec)) *pfp-opt-base*))
    ;; Reported, but neither half is usable: the caption matches no pattern AND
    ;; the key is not a number.  A renamed .odcl caption lands here, so name it
    ;; -- the fix is one pattern in *pfp-opt-captions*, not a code change.
    (T
     (prompt (strcat "\nPFPALETTE: \"" nm "\" reported caption "
                     (vl-princ-to-string (cadr rec)) " / key "
                     (vl-princ-to-string (caddr rec))
                     ",\n  which matches no entry in *pfp-opt-captions*."
                     "  Add a pattern for it."))
     nil)))

;; (pfp:chk-on-p ctrl label) -> T | nil
;;   NOT (if v T nil): GetValue is numeric, an unticked box answers 0, and in
;;   AutoLISP 0 is TRUE -- so the obvious spelling reads every box as ON.
;;   Compare against 0 explicitly.
;;   An unreadable box reads as OFF rather than refusing the run: Zoom To is a
;;   convenience, and killing a labeling pass over it is the wrong trade.
(defun pfp:chk-on-p (ctrl label / hit v)
  (cond
    ((null ctrl) nil)
    ((null (setq hit (pfp:first-callable *pfp-chk-getters* (list ctrl))))
     (prompt (strcat "\nPFPALETTE: cannot read \"" label "\" -- assuming Zoom"
                     " To is off.  Run PFPCTL."))
     nil)
    ((null (setq v (cdr hit))) nil)
    ((numberp v) (/= 0 (fix v)))
    (T T)))

;;; ---- the ticket ----------------------------------------------------------

;; optLabel's item order is fixed in the .odcl: Structures / Inverts / Crossings.
(setq *pfp-cmd-map* '((0 . LABEL) (1 . INVERT) (2 . XING)))

;; optTools -> a COMMAND NAME, not an engine call: PFPROINV/PFPROTOP each pick a
;; polyline and work out the grid themselves (pfpro:owner), so there is no
;; target, mode or selection to pass.  Hence a string here, a symbol in
;; *pfp-cmd-map*.
(setq *pfp-tools-map* '((0 . "PFPROINV") (1 . "PFPROTOP")))

;; (pfp:order-mode cmd) -> "All" | "Out" | nil
;;   optRun is Label All / Label Outstanding / Label Selected, in that order.
;;   Selected is REFUSED rather than coerced to All: quietly running a different
;;   pass than the one picked is worse than sending the operator to the modal.
;;   Crossings ignores optRun -- pfxl:run has no mode, and its All already means
;;   "every crossing not yet labeled".
(defun pfp:order-mode (cmd / i)
  (cond
    ((eq cmd 'XING) "All")
    ((null (setq i (pfp:opt-item pfsuite/pfsPalette/optRun "optRun"))) nil)
    ((= i 0) "All")
    ((= i 1) "Out")
    (T
     (prompt (strcat "\nPFPALETTE: Label Selected is not wired to the palette."
                     "  Run PFLABEL or PFINVERT from the command line to pick"
                     " structures from the list."))
     nil)))

;; (pfp:order-fire) -> T | nil
;;   THE only path from btnRun to a write.  The ticket is dropped again if the
;;   defer is refused, or it would fire on the NEXT run against the old row.
;;   Same discipline as pfp:fire.
;;   IT NAMES THE GROUP WHEN IT REFUSES: reaching this function at all means RUN
;;   thinks it is serving Label, which is itself the diagnosis when the operator
;;   clicked a Tools item (optTools#OnSelChanged unticked in Studio).
(defun pfp:order-fire ( / row i cmd mode)
  (cond
    ((null (setq row (pfp:need-row *pfp-tar-sel* 'ANCHORED)))
     (prompt (strcat "\n  RUN is armed for the Label group -- that is the last"
                     " group clicked.\n  For Create INV.pro / Create TOP.pro,"
                     " click a Tools item first."))
     nil)
    ((null (setq i (pfp:opt-item pfsuite/pfsPalette/optLabel "optLabel"))) nil)
    ((null (setq cmd (cdr (assoc i *pfp-cmd-map*))))
     (prompt (strcat "\nPFPALETTE: optLabel returned item " (itoa i)
                     " -- expected 0, 1 or 2.  Check the .odcl item list."))
     nil)
    ((null (setq mode (pfp:order-mode cmd))) nil)
    (T
     (setq *pfp-order*
             (list (cons 'cmd  cmd)
                   (cons 'row  row)
                   (cons 'mode mode)
                   (cons 'zoom (pfp:chk-on-p pfsuite/pfsPalette/chkbxZoom
                                             "chkbxZoom"))))
     (cond ((pfp:defer "PFPRUN") T)
           (T (setq *pfp-order* nil) nil)))))

;; (pfp:tools-fire) -> T | nil    RUN, with the Tools group active.
;;   THE WHOLE VERB: no ticket, no row, no state check -- it defers a bare
;;   command name.  Both commands are already pf:run-command-wrapped and both
;;   open with an entsel loop, so they can never run from a modeless handler, and
;;   both resolve their own grid from the picked polyline.
;;   Deliberately does NOT require a tarLines selection: these two never read it,
;;   and the polyline the user picks is the input.
(defun pfp:tools-fire ( / i cmd)
  (cond
    ((null (setq i (pfp:opt-item pfsuite/pfsPalette/optTools "optTools"))) nil)
    ((null (setq cmd (cdr (assoc i *pfp-tools-map*))))
     ;; The third item is unmapped on purpose (see *pfp-opt-captions*): refusing
     ;; names the gap, guessing would fire the wrong command.
     (prompt (strcat "\nPFPALETTE: that Tools item (" (itoa i) ") has no"
                     " command wired to it yet -- only Profile from INV and"
                     " Profile from TOP are wired."))
     nil)
    (T (pfp:defer cmd))))

;;; ---- the dispatcher ------------------------------------------------------

;; (pfp:order-gather anchor pass) -> (lines inlets pend status) | nil
;;   pflabel:run-dialog's gather minus the dialog.  Runs in a command context, so
;;   the write-free constraint does not apply here -- unlike the SECTION 5b fill.
(defun pfp:order-gather (anchor pass / xf cl prim pairs lines inlets g)
  (setq xf (pfa:anchor->xform anchor))
  (cond
    ((null xf)
     (prompt "\nPFPRUN: target grid record unreadable -- cannot label.") nil)
    ((null (setq cl (pf:xf-get 'clfile xf)))
     (prompt "\nPFPRUN: no .cl on record for this target -- run PFSETUP (edit).")
     nil)
    (T
     (setq prim   (pf:xf-get 'name xf)
           pairs  (pf:dedupe-pairs (cons (cons cl prim) (pfa:registry-pairs cl)))
           lines  (pfa:build-lines pairs)
           inlets (pfa:gather-inlets)
           g      (pfa:gather-compute anchor pass prim lines inlets))
     (cond
       ((null g)
        (prompt (strcat "\nPFPRUN: centerline for '" prim
                        "' could not be read -- nothing to label."))
        nil)
       (T (list lines inlets (car g) (cadr g)))))))

;; (pfp:outstanding pend status) -> the subset of pend carrying no label yet
;;   status is a list of booleans PARALLEL to pend (pfa:status-for), not an
;;   alist, so the two are walked together by index.
(defun pfp:outstanding (pend status / out i)
  (setq out '() i 0)
  (foreach p pend
    (if (not (nth i status)) (setq out (cons p out)))
    (setq i (1+ i)))
  (reverse out))

;; (pfp:run-labels cmd row mode) -> nil    Structures and Inverts
;;   Both engines take the identical ticket and read the SAME 'sel key -- mode
;;   only decides whether the previous pass is erased first.  So Outstanding is
;;   mode "Sel" over the unlabeled subset, and needed no engine edit.
;;   THE GATHER IS QUIET, the run is not: the gather narrates one "Loaded line"
;;   per centerline plus the DRIFT block, which on the palette buries the one
;;   line the operator wants.  Drift is not lost -- detailsList has its own row.
;;   PROGRESS ONLY: *pf-quiet* gates pf:progress and nothing else.  The reset is
;;   belt-and-braces -- pf:run-command and pf:run-error clear the flag too, which
;;   is what makes a plain setq safe here instead of another catch wrapper.
(defun pfp:run-labels (cmd row mode / anchor pass g lines inlets pend status sel)
  (setq anchor     (nth 3 row)
        pass       (if (eq cmd 'INVERT) *pfi-pass-name* "LABEL")
        *pf-quiet* T
        g          (pfp:order-gather anchor pass)
        *pf-quiet* nil)
  (if g
    (progn
      (setq lines  (car g)   inlets (cadr g)
            pend   (caddr g) status (cadddr g)
            sel    (if (= mode "All") pend (pfp:outstanding pend status)))
      (cond
        ((null pend)
         (prompt "\nPFPRUN: no structures on this line -- nothing to label."))
        ((null sel)
         (prompt (strcat "\nPFPRUN: every structure on this line already carries"
                         " a " pass " label -- nothing outstanding.")))
        (T
         (prompt (strcat "\nPFPRUN: " (if (= mode "All") "Label All" "Outstanding")
                         " -- " (itoa (length sel)) " of " (itoa (length pend))
                         " structure(s)."))
         (setq sel (list (cons 'mode   (if (= mode "All") "All" "Sel"))
                         (cons 'sel    sel)
                         (cons 'lines  lines)
                         (cons 'inlets inlets)))
         (if (eq cmd 'INVERT)
           (pfi:run anchor sel)
           (pflabel:run anchor sel))))))
  (princ))

;; (pfp:run-xings row) -> nil    Crossings
;;   C:PFXLABEL's body minus the target pick and the dialog.  Its All branch
;;   already means "every crossing not yet labeled", so there is no Outstanding
;;   variant and no relabel confirm -- labeled ones are filtered, not duplicated.
;;   The undo group is opened HERE because pfxl:discover writes before pfxl:run
;;   is reached; pflabel:run and pfi:run open their own, so pfp:run-labels
;;   must not double-wrap.
(defun pfp:run-xings (row / anchor xf work recon sel)
  (setq anchor (nth 3 row))
  (if (null (setq xf (pfa:anchor->xform anchor)))
    (prompt "\nPFPRUN: target grid record unreadable -- cannot label.")
    (progn
      (pf:undo-begin '*pfxl-undo-open*)
      (pfxl:discover anchor)
      (setq work  (pfa:xing-list anchor)
            recon (pfa:recon xf work)
            sel   (vl-remove-if
                    '(lambda (x) (cdr (assoc (pfa:xr-key x) recon)))
                    work))
      (cond
        ((null work) (prompt "\nPFPRUN: no crossings found for this target."))
        ((null sel)
         (prompt "\nPFPRUN: all crossings already labeled -- nothing to do."))
        (T
         (prompt (strcat "\nPFPRUN: " (itoa (length sel)) " of "
                         (itoa (length work)) " crossing(s) outstanding."))
         (pfxl:run anchor xf sel)))
      (if *pfxl-undo-open* (pf:undo-end '*pfxl-undo-open*))))
  (princ))

;; (pfp:order-run) -> nil    The body, run under pf:run-command.
(defun pfp:order-run ( / ord cmd row mode)
  ;; READ AND CLEARED IN ONE setq: a ticket left behind would re-fire on a bare
  ;; PFPRUN typed at the command line, against the old row.
  (setq ord        *pfp-order*
        *pfp-order* nil
        cmd        (cdr (assoc 'cmd  ord))
        row        (cdr (assoc 'row  ord))
        mode       (cdr (assoc 'mode ord)))
  ;; Zoom To rides the existing one-shot channel rather than the ticket:
  ;; pf:zoom-resolve reads AND clears it at the top of every engine run, which is
  ;; the read-once discipline the ticket would otherwise reimplement.
  (setq *pf-zoom-to* (if (cdr (assoc 'zoom ord)) 'ON 'OFF))
  (if (eq cmd 'XING)
    (pfp:run-xings row)
    (pfp:run-labels cmd row mode))
  ;; Counts only -- NOT pfp:refresh.  A labeling pass cannot change the registry,
  ;; so rebuilding both trees is wasted work AND clears *pfp-tar-sel*, blanking
  ;; the panel the operator is reading their result from.  SECTION 8's
  ;; registry-changing verbs still take the full refresh.
  ;; QUIET, like pfp:route-sel: the recount has to happen (the numbers changed
  ;; and the gather memo cannot be trusted across a write) but it must not
  ;; re-narrate every centerline.  The reset is unconditional and outside the
  ;; catch -- a skipped one mutes every command for the session, silently.
  (setq *pf-quiet* T)
  (if *pfp-tar-sel*
    (vl-catch-all-apply 'pfp:fill-details (list *pfp-tar-sel*)))
  (setq *pf-quiet* nil)
  ;; ...and the item list, whose Status column is what the run just changed.
  ;; Its own quiet + catch live inside pfp:fill-items, hence after the reset.
  (if *pfp-tar-sel*
    (vl-catch-all-apply 'pfp:fill-items (list *pfp-tar-sel*)))
  ;; The row still shows but its DATA changed, so the next click on that same row
  ;; must be allowed to repaint it.
  (setq *pfp-last-key* nil)
  (princ))

(defun pfp:order-flush ( / cmd)
  (setq cmd (cdr (assoc 'cmd *pfp-order*)))
  (cond ((eq cmd 'LABEL)  'pflabel:flush-pass)
        ((eq cmd 'INVERT) 'pfi:flush-pass)
        (T                'pfxl:flush-pass)))

;; C:PFPRUN -- the Commands tab's one deferred entry point.
(defun c:PFPRUN ()
  (if (null *pfp-order*)
    (progn
      (prompt (strcat "\nPFPRUN: no order ticket -- use RUN on the palette's"
                      " Commands tab."))
      (princ))
    (pf:run-command "PFPRUN" (pfp:order-flush) 'pfp:order-run)))

;;; ---- panel state + the button handlers -----------------------------------

;; (pfp:clear-target) -> nil    btnClear
;;   Inline, not deferred: it touches the palette and nothing else.  The TREE
;;   selection is left alone -- Trees have no attested "select nothing" call, and
;;   dropping the remembered row is what actually stops RUN firing.
(defun pfp:clear-target ()
  (setq *pfp-tar-sel* nil)
  (pfp:fill-details nil)
  (pfp:fill-items nil)
  (prompt "\nPFPALETTE: target cleared -- pick a line on the Commands tab.")
  (princ))

;; (pfp:cmd-init) -> nil    Resets the active group; it disables nothing.
;;   Called from pfp:refresh and NOT from OnInitialize, which fires before the
;;   window is realized (SECTION 4).  Idempotent, so a per-refresh call is free.
;;   A refresh drops both tree selections, so leaving RUN armed for Tools across
;;   one is the same class of staleness.
;;   IT DOES NOT TOUCH optRun: an Option List has no Value property to write any
;;   more than to read, and SetValue on one raises the modal "Property <Value>
;;   not found" on every open.  **vl-catch-all-apply does NOT suppress an OpenDCL
;;   argument-validation error** -- the ARX raises it as a modal box before LISP
;;   sees a return value, so wrapping a probe in a catch does not make it safe.
;;   Getters degrade quietly to nil; setters do not degrade at all.  Discover
;;   with C:PFPAPI, never by trial-calling against a live control.
;;   optRun's default item is therefore a STUDIO setting -- set it to Label
;;   Outstanding there, because Label All erases the pass's previous output
;;   before redrawing, and from the palette that is one click with no dialog.
;;   The unmapped third Tools item refuses BY NAME rather than being greyed:
;;   an Option List cannot grey one item, and a refusal naming the item beats an
;;   item that merely looks broken.
(defun pfp:cmd-init ( / )
  (setq *pfp-active-group* 'LABEL)
  (princ))

;; RUN READS THE FLAG, not the radios: both groups always hold a selection, so
;; "which one has something picked" cannot distinguish them.  *pfp-active-group*
;; records which group was touched last, which is the real question.
(defun c:pfsuite/pfsPalette/btnRun#OnClicked ()
  (if (eq *pfp-active-group* 'TOOLS)
    (pfp:tools-fire)
    (pfp:order-fire))
  (princ))

(defun c:pfsuite/pfsPalette/btnClear#OnClicked ()
  (pfp:clear-target)
  (princ))

;; (pfp:api-names pat) -> sorted names of every registered dcl* symbol matching
;;   pat.  atoms-family 0 is the whole symbol table, so this is the DEFINITIVE
;;   answer to "what is this accessor called" -- no more candidate lists.
;;   AutoLISP folds symbol names to upper case, so pat must be upper case too.
(defun pfp:api-names (pat / out s nm)
  (setq out '())
  (foreach s (atoms-family 0)
    (setq nm (vl-symbol-name s))
    (if (and (wcmatch nm "DCL*") (wcmatch nm pat)) (setq out (cons nm out))))
  (if out (acad_strlsort out) '()))

;; C:PFPAPI -- list the OpenDCL functions this build actually registers.
;;   NO PROMPT: a MODELESS FORM CAN INTERRUPT A COMMAND-LINE READ, so a getstring
;;   here is cancelled by any palette click and reads as "Function cancelled".
;;   Nothing that prompts is safe while the palette is open.  It dumps the groups
;;   the Commands tab needs; for anything else call the helper directly:
;;       (pfp:api-names "*TREE*")
(defun c:PFPAPI ( / pat names nm)
  (prompt (strcat "\n=== PFPAPI -- " (itoa (length (pfp:api-names "*")))
                  " dcl* functions registered in this build ==="))
  (foreach pat '("*OPTION*" "*RADIO*" "*CHECK*" "*VALUE*" "*CURSEL*" "*GETCUR*")
    (setq names (pfp:api-names pat))
    (prompt (strcat "\n  " pat "  (" (itoa (length names)) ")"))
    (foreach nm names (prompt (strcat "\n      " nm))))
  (prompt "\n  Anything else:  (pfp:api-names \"*TREE*\")  at the command line.")
  (princ))

;; C:PFPCTL -- what do the Commands tab's value controls actually return?
;;   Select Structures, tick Zoom To, then run it:
;;     optLabel 0, chkbxZoom non-zero -> *pfp-opt-base* 0 is right
;;     optLabel 1                     -> set *pfp-opt-base* to 1
;;     optLabel "" or nil             -> GetValue is not the accessor after all
;;   IT DOES NOT PROBE THE OPTION LISTS -- doing so caused the fault it was meant
;;   to diagnose: six GetValue calls, six modal dialogs, six tidy nils in the
;;   report.  They are reported from their events; only the Check Box is read.
(defun c:PFPCTL ( / f nm rec hit)
  (cond
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPCTL: run PFPALETTE first."))
    (T
     (prompt "\n=== PFPCTL -- Commands tab value controls ===")
     (prompt "\n  Option Lists (from their events -- NEVER read with GetValue):")
     (foreach nm '("optLabel" "optRun")
       (setq rec (assoc nm *pfp-opt-vals*))
       (prompt (strcat "\n    " nm " -> "
                       (cond
                         ((null rec)
                          "NOTHING REPORTED YET -- click an item in that group")
                         (T
                          (strcat "Label=" (vl-princ-to-string (cadr rec))
                                  "  Key="  (vl-princ-to-string (caddr rec))
                                  "  -> "
                                  (cond
                                    ((setq hit (pfp:cap-match nm (cadr rec)))
                                     (strcat "item " (itoa (cdr hit))
                                             " (by caption " (car hit) ")"))
                                    ((numberp (caddr rec))
                                     (strcat "item "
                                             (itoa (- (fix (caddr rec))
                                                      *pfp-opt-base*))
                                             " (by key, base "
                                             (itoa *pfp-opt-base*) ")"))
                                    (T "UNRESOLVED -- add a caption pattern"))))))))
     (prompt "\n  Check Box (Value is a real property here):")
     (foreach f *pfp-chk-getters*
       (prompt (strcat "\n    " f " -> "
                       (if (pfp:callable-p f)
                         (pfp:ask f (list pfsuite/pfsPalette/chkbxZoom))
                         "no such function"))))
     (if (null *pfp-opt-vals*)
       (prompt (strcat "\n  -> No event has fired.  Tick optLabel/optRun's event"
                       " in Studio, PFPRELOAD,\n     then click an item."))
       (prompt (strcat "\n  -> Events ARE firing.  If the item number looks off"
                       " by one, set *pfp-opt-base*.")))))
  (princ))


;;; ==========================================================================
;;; SECTION 10  --  Help  (C:PFPHELP + btnHelp)
;;; ==========================================================================
;;; A DCL DIALOG, NOT AN ALERT: the text runs ~90 lines and alert has no
;;; scrollbar.  pfp_help is a list_box, so length is free (pfdialog.dcl).
;;; DEFERRED THOUGH IT ONLY READS -- start_dialog needs a command context exactly
;;; as getpoint does, which is why btnNew defers too.  Deferring also buys the
;;; command-line-busy refusal for free.
;;; C:PFPHELP IS THE REAL ENTRY POINT, the button is a caller: it is typeable
;;; with the palette closed, which is where someone who cannot find it is.
;;; WRITTEN FOR A DRAFTER -- no function names, no file formats, no ledger
;;; vocabulary.  Every status word the two tabs can display is spelled out here;
;;; when a status string changes, change this with it.  The three feeds are
;;; pfa:status-label, pfp:item-status and pfp:drift-cell.

;; (pfp:help-lines) -> list of strings, one per line of the help page
;;   A function, not a global: built once per click and thrown away, and a global
;;   would be one more thing PFPRELOAD has to think about.
(defun pfp:help-lines ()
  (list
    "PFTOOLS PALETTE"
    ""
    "Looking is free.  The palette only reads the drawing.  Nothing"
    "is written until you press a button that draws."
    ""
    "--- REGISTRY TAB---------------------------------------------------"
    ""
    "WHAT IT IS"
    "  Registry contains profile this drawing knows about, in one of two states:"
    ""
    "  Registered   The profile exists and maps to its .cl file, but"
    "               has not been Anchored on the sheet.  Every profile is"
    "               found automatically using Labels on PF-NAME and its .cl."
    ""  
    "   Anchored    Registered AND Anchored -- the drawing knows where"
    "               the grid sits."
    ""
    "  Registration knows that the profile exists.  Anchoring is what lets"
    "  anything be DRAWN."
    ""
    "  Pick a line in the tree and the panels fill in its Registration"
    "  status as well as all anchoring properties and any files associated"
    "  with it"
    ""
    "ANCHOR"
    "  Anchoring tells the drawing where a profile grid physically"
    "  sits.  You type the datum elevation, then pick the grid's"
    "  lower-left and top-right corners."
    ""
    "  ANCHOR will insert a block at the profile grid's datum"
    "  The blocks attributes carry all the spatial data for that grid"
    ""  
    "  STATUS WORDS  (these describe the FILES, not the labels)"
    "  PASSING     every input file is as it was when the pass ran"
    "  STALE       an input file has CHANGED since -- output may be"
    "              wrong"
    "  FAILING     an input file cannot be read at all"
    "  UNCHECKED   no fingerprint on record -- run PFSETUP (edit)"
    ""
    ""
    ""
    "--- COMMANDS ---------------------------------------------------"
    ""
    "WHAT IT IS"
    "  Every command that creates anything in the drawing is here."
    ""
    "WHAT IT DOES"
    "  Pick a target line, pick which pass, check the list, run it."
    ""
    "  Label All"           
    "   Redraws the whole pass, replacing what the command drew last time."
    ""
    "  Label Outstanding"
    "   Draws any labels that the command has not made yet."
    ""
    "NOTE: Only recognizes labels that it has previously made."
    ""
    "WHAT EACH PASS FINDS"
    "  Structures  Every structure on the line.  Labels are stacked"
    "                   at the top of the grid above each one.  Grid tops"
    "                   step, so a station with no grid above it is"
    "                   skipped and reported, never guessed at."
    ""
    "  Inverts     Pipe elevations, read from the line's bound"
    "                _INV .pro file.  Nothing is measured off the"
    "                drawing."
    ""
    "  Crossings   Where other utilities cross this one.  Found by"
    "                  intersecting this line's centerline against every"
    "                  other registered line's centerline.  The pipe"
    "                  that gets drawn comes from the OTHER line's"
    "                  profile file, so a crossing can only be drawn if"
    "                  that line's files are bound."
    ""
    "THE SUMMARY PANEL"
    "  Counts for the selected line -- how many structures, and how"
    "  many of each label type are done versus outstanding."
    ""
    "  Drift       how many labels are drawn but no longer sit where"
    "              their structure does.  Reads \"2 Incorrect"
    "              label(s)\" when something has moved; \"-\" when all"
    "              is well."
    ""
    "STATUS WORDS  (these describe each ITEM in the list below)"
    "  labeled       already drawn by this pass"
    "  outstanding   not drawn yet"
    "  NEW           found on the ground, never filed"
    "  MOVED         on record, but at a different station than it"
    "                sits at now"
    ""
    "--- SETTINGS ---------------------------------------------------"
    ""
    "  Not in use yet."
    ""
    "----------------------------------------------------------------"
    "Refresh happens by itself after any PF command and when you"
    "come back to the drawing.  Press Refresh if the panels look"
    "behind."))

;; (pfp:help-show) -> nil   The dialog body.  COMMAND CONTEXT ONLY.
;;   Falls back to the command line rather than dying if the .dcl will not load.
(defun pfp:help-show ( / dcl_id ln)
  (cond
    ((setq dcl_id (pfset:load-dcl))
     (if (new_dialog "pfp_help" dcl_id)
       (progn
         (start_list "help_list")
         (foreach ln (pfp:help-lines) (add_list ln))
         (end_list)
         (start_dialog)))
     (unload_dialog dcl_id))
    (T
     (foreach ln (pfp:help-lines) (prompt (strcat "\n" ln)))))
  (princ))

;; C:PFPHELP -- the deferred target, and a command in its own right.
;;   NOT under pf:run-command: that wrapper is for the undo group and the
;;   ledger-flush error hook, and this writes nothing either one protects.
(defun c:PFPHELP ()
  (pfp:help-show)
  (princ))

;; btnHelp.  Deferred for the start_dialog reason in the section header, not
;; because it writes -- it does not.
(defun c:pfsuite/pfsPalette/btnHelp#OnClicked ()
  (pfp:defer "PFPHELP")
  (princ))


(princ "\npfpalette.lsp loaded (V5 palette, milestone 2).  Command: PFPALETTE.")
(princ "\n  AFTER EVERY STUDIO SAVE:  PFPRELOAD   (else the .odcl is not re-read)")
(princ "\n  Diagnostics: PFPDIAG (names), PFPPROBE (setters), PFPREAD (rects),")
(princ "\n               PFPMOVE (clipping),")
(princ "\n               PFPNUDGE (repaint), PFPDBMOD (writes).")
(princ "\n  Native look: PFPTHEME (re-skin after a COLORTHEME flip), PFPSCALE.")
(princ "\n  Commands tab: PFPRUN (the RUN ticket), PFPCTL (control values),")
(princ "\n                PFPAPI (what dcl* functions this build registers).")
(princ "\n  Help: PFPHELP (also the Help button -- tick btnHelp \"Clicked\").")
(princ)
;;; ==========================================================================
;;; end of pfpalette.lsp
;;; ==========================================================================
