;;; ==========================================================================
;;; pfpalette.lsp  --  PFTools V5 OpenDCL palette front-end (milestone 2,
;;;                    read-only).  Command: PFPALETTE.
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
;;   Close (not Hide): Hide is not attested in the installed OpenDCL samples,
;;   and Close re-runs OnInitialize on the next open.
;;   POPULATE AFTER SHOW: OnInitialize fires before the window is realized,
;;   which is exactly why data written there didn't paint until the palette
;;   was moved (field-tested).  So OnInitialize owns COLUMNS ONLY, and the
;;   data fill (pfp:refresh) runs here, after dcl-Form-Show returns and the
;;   window exists.  This replaces the old pfp:repaint enable-toggle hack.
;;   pfp:refresh is also the single entry point for the three refresh
;;   signals to come (OnDocActivated / PF* command-ended reactor / btnRefresh).
;;   pfp:skin (7) runs here for the same reason from the other side: Close
;;   DESTROYS the controls, so runtime formatting never survives a toggle and
;;   has to be re-applied on every open.  Silent unless a setter failed.
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
;;   dcl-Project-Load "does nothing if the project is already loaded, unless
;;   the optional ForceReload argument is T" (vendor docs).  pfp:ensure passes
;;   ONE argument and guards on *pfp-loaded*, a session-long global -- so once
;;   the project is in memory, saving in Studio changes nothing and every
;;   PFPALETTE keeps showing the OLD layout.  The HelloWorld sample passes T;
;;   we dropped it.
;;
;;   FIELD-CAUGHT 2026-07-27 the expensive way: btnHelp still displayed the
;;   runtime caption "<<PROBE-A>>" set by a probe, and a Background Color
;;   edit had no effect.  Earlier measurements were taken against a stale
;;   in-memory project -- notably PFPREAD reporting lblProject at 41,632
;;   199x30 while Studio showed 16,635 250x25.  That was never an anchoring
;;   fault; it was two different versions of the file.
;;
;;   Deliberately NOT folded into pfp:ensure: production should load once,
;;   not re-read the file on every toggle.  This is the development door.
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
;;   THE one data-fill entry point: registry scan -> labels + tree.  Pure
;;   reads (pfa:registry no longer creates the NOD dictionary -- see
;;   pfa:nod-dict), so it is modeless-legal.  The read is error-guarded: a
;;   hostile drawing must never stop the palette from opening or docking.
(defun pfp:refresh ( / res)
  ;; The tree is rebuilt from scratch, so the remembered selection (SECTION 8)
  ;; is stale by definition -- its state may have flipped, or its anchor may be
  ;; gone.  Dropping it here is what stops a verb firing against yesterday's
  ;; row after a placement.
  (setq *pfp-sel* nil *pfp-tar-sel* nil)
  (setq res (vl-catch-all-apply
              '(lambda ( / reg)
                 (setq reg (pfa:registry))
                 (pfp:seed-labels reg)
                 (setq *pfp-tree-map*
                         (pfp:fill-tree pfsuite/pfsPalette/tvwLines reg)
                       *pfp-tar-map*
                         (pfp:fill-tree pfsuite/pfsPalette/tarLines reg))
                 ;; the Commands panel starts empty -- SelectItem on a Type
                 ;; parent fires no child selection, so nothing has asked for
                 ;; counts yet
                 (pfp:fill-details nil)
                 ;; grey the unwired Tools group and default optRun to the
                 ;; non-destructive item (SECTION 9)
                 (pfp:cmd-init))
              '()))
  (if (vl-catch-all-error-p res)
    (prompt (strcat "\nPFPALETTE: registry read failed -- "
                    (vl-catch-all-error-message res))))
  (princ))


;;; ==========================================================================
;;; SECTION 2  --  The defer channel  (PROVEN -- Phase 1, PALETTE-TESTING 4)
;;; ==========================================================================
;;; Promoted verbatim from pfp-proof.lsp Section 1 after the field test passed
;;; [1]-[5]: a modeless handler cannot (command)/(getpoint), but a command it
;;; queues through vla-SendCommand lands in a real command context -- getpoint
;;; prompted and returned (4.6), the work sat in one undo group (4.8), and the
;;; busy-line refusal fired against a live PLINE (4.9).
;;;
;;; EVERY palette verb goes through pfp:defer and nothing else.

;; (pfp:cmd-idle-p) -> T | nil
;;   The gate root README 5 requires before ANY palette-initiated write.
;;   CMDACTIVE alone is not enough: a dialog or a grip edit can leave
;;   CMDNAMES populated with CMDACTIVE at 0.
(defun pfp:cmd-idle-p ()
  (and (= 0 (getvar "CMDACTIVE"))
       (= "" (getvar "CMDNAMES"))))

;; (pfp:defer cmdline) -> T | nil
;;   Queue a command from a modeless handler.  SendCommand returns
;;   immediately -- the command runs after the handler unwinds, in a real
;;   command context.  The trailing newline is what executes it; without it
;;   the text sits on the command line unexecuted.
;;   Refuses (and says so) when the command line is busy, rather than
;;   stacking input behind whatever is already running.
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

;; (pfp:file-cell p) -> "name.ext" | "(not set)"   (unbound reads explicit)
(defun pfp:file-cell (p)
  (if (and p (/= p ""))
    (strcat (vl-filename-base p) (vl-filename-extension p))
    "(not set)"))

;; (pfp:dash s) -> s | "-"   (a blank scalar reads as a dash, never "")
(defun pfp:dash (s) (if (and s (/= s "")) s "-"))


;;; ==========================================================================
;;; SECTION 4  --  OnInitialize  (columns once, seed labels, fill the tree)
;;; ==========================================================================

;; COLUMNS ONLY.  AddColumns is additive -- calling it from a refresh would
;; stack duplicate columns (README 4) -- so it lives here and nowhere else.
;; NO data fill here: OnInitialize fires before the window is realized, so
;; anything written now doesn't paint (the "populated only after moving the
;; palette" failure).  Data comes from pfp:refresh, called after Form-Show.
(defun c:pfsuite/pfsPalette#OnInitialize ( / )
  (dcl-ListView-AddColumns pfsuite/pfsPalette/metaList
    (list (list "Property" 0 110) (list "Value" 0 410)))
  (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwLinkage
    (list (list "Item" 0 90) (list "File" 0 440)))
  ;; detailsList is a per-target SUMMARY, not an item list -- same two-column
  ;; Property/Value shape as metaList, and for the same reason: the Commands
  ;; tab answers "what is on this line" before a command is chosen.
  (dcl-ListView-AddColumns pfsuite/pfsPalette/detailsList
    (list (list "Property" 0 150) (list "Value" 0 370)))
  (princ))

;; (pfp:caption ctrl label text) -> T | nil
;;   Guarded SetCaption.  WHY THIS EXISTS (PALETTE-TESTING 2.3/2.4, "labels
;;   completely blank"): an OpenDCL control symbol that the loaded project
;;   never defined evaluates to NIL -- AutoLISP returns nil for an unbound
;;   symbol instead of erroring -- and SetCaption on nil does nothing and says
;;   nothing.  The caption silently never appears while everything around it
;;   keeps working, which is exactly what the field test saw: blank labels, no
;;   message, tree filling normally two lines later.
;;   So: name the miss.  A blank label must never again be a silent failure.
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
;;
;;   TAKES THE CONTROL AND RETURNS THE MAP (2026-07-29) rather than writing a
;;   global.  There are now TWO trees over the same registry -- tvwLines on
;;   Registry and tarLines on Commands -- and one shared *pfp-tree-map* would
;;   make pfp:sel-row answer with the other tree's row, because the child keys
;;   are per-control.  Returning it keeps each caller owning its own map, and
;;   avoids `set` on a quoted symbol.
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
;;; Anchored lines read from the anchor block + ledger; registered (STUB)
;;; lines read from the stub row.  UI vocabulary is "Anchored" / "Registered"
;;; -- never "placed" / "stub".

;; (pfp:sel-row Key map) -> reg-row | nil   (nil when Key is a Type parent)
;;   Takes the map since 2026-07-29 -- child keys are per-control, so the
;;   Commands tree must be looked up in its own map (see pfp:fill-tree).
(defun pfp:sel-row (key map) (cdr (assoc key map)))

;; (pfp:status-cell anchor) -> "PASSING" | "STALE (LABEL, XING)" | ...
;;   The ROLL-UP, worked out here and never stored: nothing would update a saved
;;   summary when one of the three records beneath it moved.  Worst state wins,
;;   so one failing input can never render as green.  Pure reads throughout, so
;;   it is legal from this modeless handler.
(defun pfp:status-cell (anchor / roll)
  (setq roll (pfa:status-roll anchor))
  (strcat (pfa:status-label (car roll))
          (if (nth 3 roll)
            (strcat " (" (pf:join (nth 3 roll) ", ") ")")
            "")))

;; (pfp:meta-rows row) -> list of (prop -1 value -1) rows for metaList
(defun pfp:meta-rows (row / type name ename at cl mat)
  (setq type (car row) name (cadr row))
  (cond
    ((eq (caddr row) 'ANCHORED)
     (setq ename (nth 3 row)
           at    (pfa:read-attribs ename)
           cl    (cdr (assoc 1 (pfa:meta-get ename)))
           mat   (cdr (assoc 5 (pfa:files-get ename))))
     (list (list "Type"       -1 type                          -1)
           (list "Line"       -1 name                          -1)
           (list "State"      -1 "Anchored"                    -1)
           (list "Checks"     -1 (pfp:status-cell ename)       -1)
           (list "Datum"      -1 (pfp:dash (pfa:att "DATUM" at)) -1)
           (list "Start sta"  -1 (pfp:dash (pfa:att "STA0"  at)) -1)
           (list "H plot"     -1 (pfp:dash (pfa:att "HPLOT" at)) -1)
           (list "V plot"     -1 (pfp:dash (pfa:att "VPLOT" at)) -1)
           (list "Centerline" -1 (pfp:file-cell cl)            -1)
           (list "Material"   -1 (pfp:dash mat)                -1)))
    (T                                            ; STUB = (type name cl inv top)
     (list (list "Type"       -1 type                          -1)
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
;;   THE SELECTION ROUTER.  Both trees' OnSelChanged arrive here, because they
;;   cannot be told apart by the handler they land in.
;;
;;   MEASURED 2026-07-29: clicking the COMMANDS tree fires
;;   tvwLines#OnSelChanged carrying a key that resolves in *pfp-tar-map* and
;;   NOT in *pfp-tree-map*.  The two symbols report different rects, so they
;;   are different controls -- but the Commands tree's event dispatches under
;;   the Registry tree's name.  Consistent with it having been duplicated from
;;   tvwLines in Studio and keeping the source's handler binding.  PFPDIAG
;;   cannot see this: both names resolve, so nothing reads as missing.
;;
;;   So: route on WHICH MAP OWNS THE KEY, never on which handler fired.  That
;;   is the stronger rule regardless -- the key is the identity, the control
;;   name has proven not to be -- and it keeps working unchanged if the .odcl
;;   is ever rebuilt with correct wiring.
;;   QUIET: the fill paths run the same gather code the label commands run, and
;;   that code narrates itself (pfa:build-lines' per-line "Loaded line ...",
;;   pfa:status-for's DRIFT block -- twice, LABEL and INVERT).  Fine for a
;;   command, noise on every click.  *pf-quiet* suppresses PROGRESS ONLY; every
;;   error, refusal and *error*-handler message still prints.
;;
;;   The flag is cleared OUTSIDE the fills, not inside one, because
;;   pfp:fill-details catches its own errors and an escape route that skipped
;;   the reset would leave the whole suite mute for the rest of the session.
(defun pfp:route-sel (Key / reg tar res)
  (setq reg (pfp:sel-row Key *pfp-tree-map*)
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
  ;; ALWAYS, including on a throw.  A skipped reset would leave *pf-quiet* T
  ;; for the rest of the session and mute every command's progress output --
  ;; a far worse bug than the noise this is fixing, and a silent one.
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
  ;; SECTION 8 reads this.  A plain setq -- the selection is the only state
  ;; the verbs need, and nothing about remembering it touches the drawing.
  (setq *pfp-sel* row)
  (princ))

;; (pfp:show-commands row) -> nil    Commands tab panel
(defun pfp:show-commands (row)
  (pfp:fill-details row)
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
;;; detailsList is a per-target SUMMARY, not a list of items: pick a target,
;;; see what is on it, THEN choose the command to run.  So the counts must be
;;; on screen before the radio is touched, which is why all three passes are
;;; shown at once rather than only the selected one.
;;;
;;; Every number comes from pfa:target-counts -- one pend walk shared by both
;;; label passes, plus the crossing ledger.  All pure reads, so this handler
;;; is modeless-legal.
;;;
;;; Section 5 is deliberately untouched: the Registry tab's handler keeps its
;;; own map and its own panels.

(if (not (boundp '*pfp-tar-map*)) (setq *pfp-tar-map* '()))
(if (not (boundp '*pfp-tar-sel*)) (setq *pfp-tar-sel* nil))

;; (pfp:count-cell done out) -> "8 labeled, 4 outstanding"
;;   One cell rather than two rows: the pair reads as one fact, and splitting
;;   it doubled the row count for no gain.
(defun pfp:count-cell (done out)
  (strcat (itoa done) " labeled, " (itoa out) " outstanding"))

;; (pfp:drift-cell n) -> "-" | "2 stale label(s) -- something moved"
(defun pfp:drift-cell (n)
  (if (or (null n) (= n 0))
    "-"
    (strcat (itoa n) " stale label(s) -- something moved")))

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
           ;; "on record" and not "found": pfxl:discover is a WRITER, so the
           ;; palette can only ever see already-merged crossings.  A line that
           ;; has never had PFXLABEL run reads 0, and 0 here means "none
           ;; discovered yet", not "none exist".
           (list "Crossings on record" -1
                 (itoa (cdr (assoc 'crossings c))) -1)
           (list "Crossing labels" -1
                 (pfp:count-cell (cdr (assoc 'xing-done c))
                                 (cdr (assoc 'xing-out  c))) -1)
           (list "Drift" -1 (pfp:drift-cell (cdr (assoc 'drift c))) -1)))))

;; (pfp:fill-details row) -> nil
;;   GUARDED, unlike Section 5's fill.  That one reads attributes and
;;   dictionaries and cannot realistically throw; this one reaches file I/O
;;   and the Road API through pfa:target-counts, and an escaping error inside
;;   a modeless OpenDCL handler is worth not having.  A failure shows in the
;;   panel AND on the command line, rather than silently blanking.
(defun pfp:fill-details (row / rows res)
  ;; THE ROAD API IS NOT LOADED IN A HANDLER.  pf:run-command calls
  ;; pf:load-apis at every command prologue, so anything reached from the
  ;; command line has eworks by the time it reads a centerline -- but a
  ;; modeless fill never goes through that wrapper, and pfa:target-counts
  ;; reaches cl_location_at_pt.  In a session where no PFTools command had run
  ;; yet, clicking a line on the Commands tab died with "bad function:
  ;; CF:ROAD_API" (field report 2026-07-29).  Exactly the failure pfanchor
  ;; SECTION 6 records for btnAnchor, and it read as working for the same
  ;; reason: testing the palette almost always follows a command-line run that
  ;; already scloaded eworks.
  ;;   Legal here -- pf:load-apis is two catch-wrapped scload calls, no
  ;; (command), no prompt, no drawing write.  Idempotent, so the repeat cost
  ;; per click is a no-op.  HERE and not in pfp:route-sel because all three
  ;; callers of this fill need it: the handler, pfp:refresh, and C:PFPDETAIL.
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

;; Set by C:PFPTAR.  Off by default -- a handler that chatters on every click
;; is worse than no handler.
(if (not (boundp '*pfp-trace*)) (setq *pfp-trace* nil))

;; Defined and routed identically to the Registry handler.  On this .odcl it
;; never fires -- the Commands tree dispatches under tvwLines -- but it costs
;; nothing and starts working the moment the wiring is rebuilt in Studio,
;; without any other change.
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
;;   SETTLED BY MEASUREMENT 2026-07-29: clicking the tree on the COMMANDS tab
;;   fires tvwLines#OnSelChanged, not tarLines#.  Both symbols are bound and
;;   both maps hold real keys, so tarLines exists and was populated -- it is
;;   simply not the control receiving the click.
;;
;;   The reading that fits: tvwLines is not parented INSIDE the Registry tab
;;   page, so it renders across every tab and covers tarLines.  Whichever
;;   control is on top gets the mouse, and the handler that fires names it.
;;
;;   Overlapping rects confirm it.  Disjoint rects refute it, and then the
;;   question becomes which control is where the cursor was.
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
;;   PFPDETAIL proved the fill works, so the break is upstream of it: either
;;   the handler never runs, or it runs and resolves no row.  Those need
;;   different fixes and look identical on screen.
;;
;;   Turns the handler trace ON and dumps the state it depends on.  Then click
;;   a LINE (a child, not a Type parent) and read the command line:
;;     nothing printed        -> the event is not reaching the handler
;;     printed, row=NIL       -> the key is not in the map (map= says whether
;;                               the map is even populated)
;;     printed, row=TYPE NAME -> the handler is fine; the fill is the problem
;;   A TOGGLE.  The flag is boundp-guarded, so neither a PFPALETTE re-toggle
;;   nor reloading the suite clears it -- an earlier version said otherwise and
;;   left the trace chattering on every click with no obvious way off.
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
  ;; COUNT THE KEYS, NOT THE ENTRIES.  pfp:fill-tree conses (ckey . row) for
  ;; every registry row regardless of what dcl-Tree-AddChild returned, so a
  ;; length of 66 is consistent with 66 SUCCESSFUL adds and with 66 silent
  ;; no-ops against a control that is not a TreeView.  Only the non-nil key
  ;; count tells them apart -- and a lookup can only ever succeed on a real key.
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

;; The full control roster from PALETTE-LAYOUT 4-6, wired and not.  Checking
;; the unwired ones too is the point: a (Name) that does not match is free to
;; fix now and expensive to find halfway through Phase 3.
(setq *pfp-controls*
  '("tabMain" "lblProject" "lblCounts" "btnRefresh" "btnHelp"
    "tvwLines" "metaList" "lvwLinkage"
    "btnPickCL" "btnPickINV" "btnPickTOP" "btnPickDESIGN" "btnPickEXIST"
    "btnAnchor" "btnEdit" "btnNew" "btnRemove" "btnZoom"
    "tarLines" "frmLabel" "optLabel" "frmTools" "optTools"
    "frmOptions" "optRun" "detailsList" "chkbxZoom" "btnClear" "btnRun"))

;; C:PFPDIAG -- name every control the project failed to define.
;;   Settles PALETTE-TESTING 1.5 (no duplicate/missing names) and the 2.3/2.4
;;   blank-label finding: a control that prints MISSING here is a (Name)
;;   mismatch between the .odcl and the code, and that is the one failure mode
;;   that produces NO error at runtime.
;;
;;   THE PALETTE MUST BE OPEN.  Field-tested 2026-07-27: closed -> 0 of 29,
;;   open -> 29 of 29.  Control symbols exist only while the form is realized;
;;   dcl-Form-Close DESTROYS the children and every symbol goes nil.  (The
;;   FORM symbol survives -- that is why C:PFPALETTE can call
;;   dcl-Form-IsActive on a closed palette.)  Without the guard below, running
;;   this closed reports all 29 MISSING, which is the exact wrong answer.
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
       ;; read -> the control symbol; eval -> its value, or nil if this form
       ;; never defined it.  nil IS the finding -- but only while open.
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
;;   MUST be checked before vl-catch-all-apply.  A "bad function" error --
;;   an unbound symbol in the function position -- is raised BEFORE the catch
;;   engages, so vl-catch-all-apply does NOT trap it and the whole command
;;   aborts on the first name that does not exist (field-tested 2026-07-27:
;;   PFPREAD died on dcl-Form-GetWidth, PFPNUDGE on dcl-Control-Update, both
;;   losing every result after that point).  Catching works for a bad
;;   ARGUMENT; it does not work for a bad FUNCTION.
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
;;   PFPDIAG proved lblProject/lblCounts exist (29 of 29) and Studio proved the
;;   rects are sane, yet both stayed blank.  What is left cannot be found by
;;   reading properties, so drive the controls directly and LOOK at the
;;   palette.  [A] is the control: btnHelp is provably visible and provably a
;;   caption-bearing control, so it tells us SetCaption itself works here.
;;   Read the results together -- see the matrix in PALETTE-TESTING 2.3/2.4.
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
     ;; [C] SetText removed 2026-07-27: these are Labels (Caption, no Text) and
     ;; the call raises a modal OpenDCL dialog LISP cannot catch.  Answered --
     ;; SetCaption is the correct setter.
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
  ;; NO GetText: these are Labels, which have Caption and no Text property, and
  ;; OpenDCL raises a MODAL error dialog for a missing property -- below LISP,
  ;; so vl-catch-all-apply cannot suppress it.  Probing a speculative property
  ;; name costs a dialog dismissal per control.  Only ask for what exists.
  (foreach g '("GetCaption" "GetVisible" "GetEnabled"
               "GetLeft" "GetTop" "GetWidth" "GetHeight")
    (prompt (strcat "\n      " g "  -> "
                    (pfp:ask (strcat "dcl-Control-" g) (list ctrl)))))
  (princ))

;; C:PFPREAD -- read the RUNTIME state of the blank controls.
;;   Field state 2026-07-27: lblProject resolves, takes SetCaption / SetText /
;;   SetVisible / SetForeColor all returning ok, has a correct rect in Studio,
;;   and paints NOTHING -- while the same SetCaption visibly repaints btnHelp.
;;   Writing to it has told us everything it can.  So read back:
;;     - caption/text comes back with the probe string -> the control HOLDS the
;;       value and simply is not painting: covered, wrong tab, or z-order.
;;     - comes back empty -> the setter is not sticking despite returning ok,
;;       and the symbol is not the control we think it is (duplicate (Name)).
;;     - a rect of 0 width/height, or one nowhere near Studio's values -> the
;;       RUNTIME rect is the fault, not the design rect.  Studio shows design
;;       values; anchoring computes the real ones, and 1.1/1.6c already say
;;       anchoring on this form misbehaves.
;;   btnHelp is dumped alongside as the control: it is provably painting, so
;;   its numbers show what a healthy control looks like on this form.
;;   RUN IT TWICE -- once DOCKED, once FLOATING -- and diff the two dumps.
;;   The 2026-07-27 report is that a GRAY BOX sits where the labels belong
;;   while docked, and goes away when the palette is dragged out.  A gray box
;;   is not a missing control; it is a control that did not paint, or a
;;   control covered by another one.  Either way the difference between the
;;   two dumps IS the bug, and nothing static (name, Studio rect, setter
;;   return) can show it because nothing static changes between the states.
;;   tabMain is dumped because the prime suspect for the box is tabMain's own
;;   background overlapping the footer band when docked.
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
;;   An empty Commands panel has two very different causes that look identical
;;   from the outside:
;;     1. tarLines#OnSelChanged never fires.  OpenDCL events are OPT-IN PER
;;        CONTROL (PALETTE-LAYOUT 7 -- "currently ticked: Close, Initialize,
;;        Size"), and an unticked event calls nothing and says nothing.  This
;;        is exactly how OnDocActivated went missing on 2026-07-27.
;;     2. The handler fires but pfa:target-counts yields nothing for that row.
;;   Calling the fill directly on the first ANCHORED row separates them:
;;   panel fills -> the code is sound, go tick the event in Studio.
;;   panel stays empty -> the fault is below the handler, and the row count
;;   printed here says how far it got.
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
;;   RUN IT DOCKED, with the gray box visible.  Each step re-sets the caption
;;   and then tries one nudge; watch the footer and note WHICH step makes text
;;   appear.  [1] is the enable-toggle -- the "old pfp:repaint hack" this file
;;   used to carry and that was deleted when populate-after-Show fixed the
;;   OnInitialize paint failure (root README 4a).  If [1] is what works, that
;;   hack was load-bearing for the DOCKED case and was removed on the evidence
;;   of floating-window tests only.
;;   If NOTHING here makes text appear, it is not a repaint fault -- the
;;   labels are covered, and PFPREAD's rects are the place to look.
;;   PAUSES between steps ON PURPOSE.  The first version fired all six nudges
;;   in a burst, so if one of them painted, the next five had already run and
;;   there was no way to tell which.  A burst can only ever report the FINAL
;;   state.  Each step now stops for you to look.
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
;;   PFPREAD 2026-07-27 established the labels are visible, enabled, correctly
;;   captioned (lblCounts held real registry counts) and sitting at Top ~630 --
;;   which is below tabMain's documented 606-tall client.  If their coordinates
;;   are in tabMain's space rather than the form's, they are positioned past
;;   the bottom of their own parent and clipped away.
;;   So move one somewhere that is legal in EITHER space and look:
;;     appears -> it was clipped/covered at its home position.  The rect is
;;                wrong for its parent, or the parent is wrong.
;;     stays hidden -> position is not the mechanism; escalate.
;;   Reversible: toggle PFPALETTE off/on.  Close destroys the controls and the
;;   next open rebuilds them from the .odcl.
;;   MAY POP MODAL OpenDCL DIALOGS -- SetLeft/SetTop are not attested in the
;;   samples, and a missing property raises a dialog LISP cannot catch.
;;   Dismiss them; the report still prints.
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

;; C:PFPINK -- DELETED 2026-07-27.  It read GetForeColor / GetBackColor off
;;   btnHelp, a Text Button, which the vendor documents for NEITHER -- four
;;   uncatchable modal dialogs per run.  It also called GetFontHeight and
;;   GetFontName, which do not exist under those names (the properties are
;;   Font and Font Size).  The question it was built to answer is answered:
;;   the labels carried Foreground Color -24 (Transparent) and Font Size 0.
;;   Its successor is 7 -- pfp:skin sets both, and C:PFPTHEME reads them back
;;   through pfp:type-can so a read can no longer land on a type that has no
;;   such property.

;; C:PFPDBMOD -- the write-free contract as a DELTA, not an absolute.
;;   PALETTE-TESTING 3 asked for DBMOD 0 and the field test read 5 on a
;;   freshly opened drawing, which blocked the whole section.  DBMOD 0 is not
;;   reachable in general -- opening a drawing can set it on its own -- and
;;   the contract was never about the absolute value.  What 5 must hold is
;;   that opening and driving the palette CHANGES NOTHING.  So: mark, act,
;;   re-run, compare.
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
;; PALETTE-LAYOUT 8 left colours "decision pending" between Tier 1 (set
;; nothing, inherit) and Tier 3 (read COLORTHEME and paint).  The vendor's
;; property reference settles it, and the answer is MOSTLY TIER 1 -- not by
;; preference, but because the controls that carry this palette's content
;; cannot be coloured at all:
;;
;;   Tree      -- NO colour property of any kind.  Font only.
;;   List View -- Background, but NO Foreground.
;;   Frame, Tab Strip -- neither.  Font only.
;;   Label, Option List, Check Box -- both.
;;
;; So a dark scheme is not reachable: tvwLines and tarLines would stay light
;; whatever it did, and the three List Views would take a dark background
;; under black text.  DARK COMES FROM THE WINDOWS THEME, which the Tree and
;; List common controls follow on their own.  What this section can do, and
;; does by default, is unify the FONT across all 29 controls, set the form
;; background, and give the two Labels a real foreground -- which is also the
;; runtime half of the blank-footer-label fix.
;;
;; The earlier revision of this section painted a chrome/data split invented
;; here rather than read off the applies-to lists.  It would have called a
;; missing property THIRTEEN times -- 6 on Frames, 4 on Trees, 3 on List
;; Views -- and each one raises a modal dialog below LISP that no catch can
;; suppress.  The capability table below is the correction, and the rule it
;; encodes is: check the property page's applies-to list, never infer a
;; property from a similar control.
;;
;; Everything here is UI-only -- no drawing write, the same class as
;; SetEnabled -- so it is modeless-legal.  Confirm with PFPDBMOD.
;;
;; RUNTIME FORMATTING DOES NOT PERSIST.  dcl-Form-Close destroys the controls
;; and the next open rebuilds them from the .odcl, so pfp:skin runs on EVERY
;; open, from C:PFPALETTE beside pfp:refresh.

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

;; STARTING VALUES, NOT A SPEC.  Autodesk publishes no RGB for palette chrome
;; -- the only documented dark value (33,40,48) is the drawing area, not the
;; frame.  Eyedropper a docked Properties palette and correct these.
;;
;; A DARK SCHEME CANNOT BE COMPLETED, and that is a vendor limit, not a gap
;; here:  Tree exposes NO colour property at all, and List View exposes
;; Background but not Foreground.  A dark pass therefore leaves tvwLines and
;; tarLines light, and gives the three List Views a dark background with
;; black text.  Dark has to come from the WINDOWS theme, which the common
;; controls follow by themselves.  These tables are kept because the light
;; side is harmless and the structure is where measured values would go.
(setq *pfp-scheme-dark*
  '((chrome-bg  55  55  55) (chrome-fg 220 220 220)
    (data-bg    43  43  43) (data-fg   220 220 220)))

(setq *pfp-scheme-light*
  '((chrome-bg 240 240 240) (chrome-fg   0   0   0)
    (data-bg   255 255 255) (data-fg     0   0   0)))

;; Font.  "MS Shell Dlg" is OpenDCL's own default and the standard dialog
;; font in every localized Windows -- more native than naming Segoe UI, which
;; is only correct on some of them.  Set either to nil to leave fonts alone.
;;   SIZE SIGN, from the vendor: NEGATIVE sizes in screen pixels, POSITIVE in
;;   points (1/72") computed from screen resolution and display size.  Points
;;   are the DPI-aware form, so a positive value is what tracks a monitor.
;;   A real size also cures the Studio-side `Font Size 0' that is half of the
;;   blank-footer-label bug (PALETTE-TESTING 2.3/2.4), for as long as the
;;   skin runs.
(setq *pfp-font-name* "MS Shell Dlg")
(setq *pfp-font-size* 9)

;; ---- the capability table -------------------------------------------------
;;
;; WHY THIS EXISTS:  a missing PROPERTY raises a modal OpenDCL dialog below
;; LISP that no catch can suppress, so a property may only be called on a
;; control whose type the vendor documents it for.  pfp:try guards a missing
;; FUNCTION; nothing guards this.  The applies-to lists are read off the
;; property reference pages and are the authority -- not the control pages,
;; and never a guess from what a similar control accepts.
;;
;;   Font / Font Size ... every type below.  This is the broadest of the four
;;                        and the reason 'font mode can cover all 29 controls.
;;   Background Color ... label list optlist check + the Palette form.
;;                        NOT tree, NOT frame, NOT tab, NOT button.
;;   Foreground Color ... label optlist check.
;;                        NOT list, NOT tree, NOT frame, NOT tab, NOT button.
;;
;; Two caveats behind 'full:
;;   -- List View takes a Background but no Foreground, so darkening it
;;      leaves black text on a dark pane.
;;   -- Check Box, Frame, Option Button, Tab Strip and Text Button carry
;;      `Use Visual Style', and the vendor says a visual style MAY OVERRIDE
;;      background and foreground.  So a colour set on those may silently do
;;      nothing -- and switching the style off to force it makes the control
;;      look less native, which is the opposite of the point.
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
    ("detailsList" . list) ("chkbxZoom" . check)
    ("btnClear" . button) ("btnRun" . button)))

;; Types that accept each colour, per the applies-to lists above.
(setq *pfp-can-backcolor* '(label list optlist check))
(setq *pfp-can-forecolor* '(label optlist check))

;; Types 'font mode is allowed to colour.  Label only: it is the one type
;; that takes BOTH colours, has no visual style to override it, and is the
;; type the blank-footer-label bug lives on.
(setq *pfp-font-mode-colour* '(label))

;; Which scheme row a type reads.  The Trees and List Views are the content
;; panes, so they would take `data' -- but the capability table blocks every
;; colour on a Tree and the foreground on a List View, so `data' only ever
;; reaches a List View background, and only in 'full mode.
(setq *pfp-data-types* '(list tree))

;; Design size, from PALETTE-LAYOUT 2.  Needed because there is no form-size
;; getter -- dcl-Form-GetWidth does not exist (it is what killed PFPREAD run
;; 1).  If Studio's form size changes, change it here too.
(setq *pfp-design-size* '(900 670))

;; Baseline rects for PFPSCALE, captured once per session so repeated scaling
;; compounds from the design layout instead of from the last scaled one.
(if (not (boundp '*pfp-rect-base*)) (setq *pfp-rect-base* nil))


;; (pfp:colour scheme key) -> Color value | nil
;;   A scheme row is (key r g b) or (key <negative logical>).  BOTH forms are
;;   documented Color values -- the vendor accepts "a list of three integers
;;   in the range 0-255" as well as an integer -- so the triple is passed
;;   through as a list and NOTHING here bit-packs a colour.  That is
;;   deliberate: the packed form's byte order is undocumented, and guessing
;;   it was going to be a live defect.
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
;;   THE GUARD THAT MATTERS, and it guards READS as much as writes -- a getter
;;   is a property accessor too, so dcl-Control-GetForeColor on a List View
;;   raises the same modal dialog the setter would.  pfp:try catches a missing
;;   FUNCTION; only this catches a missing PROPERTY.
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
;;   One control, every property its TYPE accepts and the mode allows.  Each
;;   call is also routed through pfp:try, so a setter this OpenDCL build does
;;   not have reports "no such function" instead of aborting the pass (a bad
;;   FUNCTION is raised before vl-catch-all-apply engages -- see
;;   pfp:callable-p).  The two guards cover different failures and both are
;;   needed.
(defun pfp:skin-one (nm bg fg size / c out p)
  (setq c   (eval (read (strcat "pfsuite/pfsPalette/" nm)))
        out '())
  (if (null c)
    (setq out (list (strcat "control is nil -- " nm)))
    ;; Function names are the vendor's, not inferred: the accessors live on
    ;; the PROPERTY pages, and the properties are Font and FontSize -- there
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
;;   29 controls give 29 copies of the same result line.  Collapse them, so
;;   the report is four lines when it works and names the outlier when it
;;   does not.
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
     ;; Every control in the roster, every time -- pfp:may decides what each
     ;; one actually receives, so there is no second membership list to drift
     ;; out of step with the type table.
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
;;   Needed because a palette is modeless: COLORTHEME can be flipped while it
;;   is open, and nothing tells the form.  A vlr-sysvar-reactor on COLORTHEME
;;   would automate this and is the documented next step -- deliberately not
;;   installed yet, because a reactor outlives the palette and this suite has
;;   exactly one planned reactor (PALETTE-LAYOUT 10).  Run this after a theme
;;   flip, or after editing the scheme tables above.
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
     ;; Read back a Label and a List View.  A setter that returns ok and a
     ;; getter that reports the old value is the difference between "the call
     ;; exists" and "the call took".  Each read is capability-gated for the
     ;; same reason the writes are -- GetForeColor on metaList would raise the
     ;; modal dialog, and printing `n/a' is the honest answer anyway.
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
;;   *pfp-font-size* is signed on purpose -- negative sizes are in screen
;;   pixels, positive in points -- and pfp:scale-to floors at 1, so scaling a
;;   negative size through it directly would return 1 and silently switch the
;;   font from pixels to points as well as resizing it.  Scale the magnitude,
;;   put the sign back.
(defun pfp:font-at (f)
  (if *pfp-font-size*
    (* (if (minusp *pfp-font-size*) -1 1)
       (pfp:scale-to f (abs *pfp-font-size*)))))

;; C:PFPSCALE -- geometry probe, X and Y independent.
;;   STUDIO OWNS THE GEOMETRY (PALETTE-LAYOUT, first line).  This does not
;;   change that: it is how you FIND the factors by looking at them, so the
;;   resulting rects can be typed into Studio, where they belong.  Nothing it
;;   does survives a palette toggle -- Close destroys the controls and the
;;   next open rebuilds from the .odcl, which is also the undo.
;;
;;   X AND Y ARE SEPARATE BECAUSE THE TWO AXES ARE NOT THE SAME PROBLEM.  A
;;   native palette is a NARROW, TALL strip: the useful experiment is X well
;;   under 1 with Y at or above 1, and a single uniform factor cannot express
;;   it.  Enter one factor and take the default on the second to get uniform.
;;     X scales Left and Width;  Y scales Top and Height.
;;
;;   WHAT X CANNOT REACH:  a ~300px strip means X ~= 0.33, and two things
;;   stop it.  The form has a 900px MIN WIDTH that is load-bearing
;;   (PALETTE-LAYOUT 2 -- it is what closed the vanishing-buttons issue by
;;   construction), so the runtime clamps the frame and only the controls
;;   move.  And the five fixed-width Registry button rows have no layout flow
;;   to redistribute into, so their captions clip long before 0.33 and the
;;   tree is unreadable.  Reflowing those rows is the named, unscheduled
;;   redesign.  Use this to trim 10-20% on X, not to reach 300px.
;;
;;   FONTS FOLLOW THE SMALLER FACTOR.  Glyphs do not stretch on one axis --
;;   the height comes from Y but the text still has to fit the X-narrowed
;;   box, so the min is the only choice that cannot clip.
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
         (if (< w 900)
           (prompt "\n  NOTE: below the 900 Min Width -- expect the frame to clamp."))
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
;;; A modeless handler may not write, so no button acts.  Each one records
;;; WHAT to do in *pfp-verb* and queues ONE command through pfp:defer;
;;; C:PFPVERB picks the ticket up in a real command context and runs it under
;;; pf:run-command, which is what installs the error hook and the echo
;;; save/restore.  One dispatcher rather than five commands because the
;;; CMDACTIVE gate, the ticket discipline and the refresh belong in one place
;;; (PALETTE-LAYOUT 9, Phase 3 -- decided).
;;;
;;; Anchor and Edit need NO typed fields: identity and the .cl come from the
;;; registry row, and scales + datum are prompted by pfsetup at the command
;;; line.  That is why this section needs nothing from the Edit/New tabs.

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
;;   state 'ANCHORED | 'STUB | nil (either).  Reports rather than no-ops --
;;   a button that does nothing silently is the palette's worst failure mode.
;;   TAKES THE ROW since 2026-07-29: the Commands tab (SECTION 9) needs the
;;   identical guard against its own selection, and the two tabs remember
;;   their selections separately (*pfp-sel* / *pfp-tar-sel*).
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

;; EDIT DOES NOT BUILD A RECORD, and that is the decision, not an omission.
;; Anchor can be promptable because everything it needs is already ON the
;; registry row -- identity, the .cl, the .pro pair AUTO bound -- so the only
;; missing pieces are three numbers.  Edit is the opposite: it exists to change
;; what is BOUND (material, the _INV/_TOP pair, the two surfaces), and there is
;; no prompt-shaped equivalent of a file picker with role validation.  So Edit
;; sends no preset and pfsetup opens pfsetup_main, seeded from the stored
;; record by pfs:anchor-init.

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
    (T (prompt (strcat "\nPFPVERB: unknown action " (vl-princ-to-string verb)))))
  ;; Belt to the read-and-clear brace: if anything above died between the setq
  ;; and the consumer, a live preset would reach the next COMMAND-LINE PFSETUP
  ;; and place someone else's record.  Costs nothing on the normal path.
  (setq *pfs-preset-res* nil)
  ;; the registry moved (or did not) -- either way the panels are now stale
  (pfp:refresh)
  (princ))

;; C:PFPVERB -- the ONE SendCommand target for every palette write.
;;   Additional to the frozen entry points, never a replacement: PFSETUP and
;;   PFREMOVE keep working untouched (PALETTE-LAYOUT 10).
(defun c:PFPVERB ()
  (pf:run-command "PFPVERB" nil 'pfp:verb-run))


;;; ---- the button handlers -------------------------------------------------
;;; Verbs defer.  btnRefresh is the ONE exception: pfp:refresh is a pure read,
;;; so it runs inline (PALETTE-LAYOUT 9, Phase 3).

(defun c:pfsuite/pfsPalette/btnAnchor#OnClicked ( / row)
  (if (setq row (pfp:need-sel 'STUB)) (pfp:fire 'anchor row))
  (princ))

(defun c:pfsuite/pfsPalette/btnEdit#OnClicked ( / row)
  (if (setq row (pfp:need-sel 'ANCHORED)) (pfp:fire 'edit row))
  (princ))

(defun c:pfsuite/pfsPalette/btnNew#OnClicked ()
  ;; No selection needed, and no record: pfs:place-one with no preset opens
  ;; the modal.  This IS the break-out-to-a-dialog path -- it has to be
  ;; deferred like any other verb, because start_dialog needs a command
  ;; context just as much as getpoint does.
  (pfp:fire 'new nil)
  (princ))

(defun c:pfsuite/pfsPalette/btnZoom#OnClicked ( / row)
  (if (setq row (pfp:need-sel 'ANCHORED)) (pfp:fire 'zoom row))
  (princ))

(defun c:pfsuite/pfsPalette/btnRefresh#OnClicked ()
  (pfp:refresh)
  (princ))


;;; ==========================================================================
;;; SECTION 9  --  Phase 4: the Commands tab  (one ticket, one dispatcher)
;;; ==========================================================================
;;; Twin of SECTION 8, deliberately.  btnRun cannot write, so it records WHAT
;;; to run in *pfp-order* and queues ONE command through pfp:defer; C:PFPRUN
;;; picks the ticket up in a real command context and hands it to the engine's
;;; documented entry point -- pflabel:run / pfi:run / pfxl:run, each of which
;;; already says in its header that the palette's deferred command is a caller.
;;;
;;; THE GATHER IS HERE, NOT IN THE HANDLER.  PALETTE-LAYOUT 6 put it in the
;;; click handler, which forced the Crossings special case: pfxl:discover is a
;;; writer and can never run modeless.  Gathering inside the dispatcher is
;;; already in a command context, so Crossings stops being special, and the
;;; numbers are read at RUN time rather than at click time.
;;;
;;; NO *pf-preset-target* GRAFT.  The dispatcher calls the engines directly
;;; with the anchor off the registry row, so it never enters pflabel:cmd and
;;; never reaches pfs:choose-or-place -- the function that graft existed to
;;; bypass.  A Registered row is refused outright instead (pfp:need-row
;;; 'ANCHORED), which closes the same accidental-placement hole with no edit to
;;; shared code.  PALETTE-LAYOUT 10 permits that graft; this path does not
;;; need it, so it stays unspent.
;;;
;;; TOOLS IS NOT WIRED.  frmTools/optTools are greyed and Label is permanently
;;; the active group, so SECTION 6's Label/Tools state machine does not exist
;;; yet.  It becomes real the day a Carlson command name lands here.

(if (not (boundp '*pfp-order*)) (setq *pfp-order* nil))   ; the RUN ticket

;;; ---- reading the radios and the check box --------------------------------
;;; NO Option List or Check Box has ever been READ in this suite, and neither
;;; getter is attested in the samples that ship with Studio -- PFPDIAG only
;;; ever probed control NAMES, and SECTION 7 only ever SET properties.  Calling
;;; a guessed name bare would raise an OpenDCL error inside a modeless handler,
;;; and PALETTE-TESTING 2.x records dcl-Control-GetText doing exactly that
;;; MODALLY, which locks the palette until the dialog is dismissed.
;;; So: try the candidates in order, take the first that answers, NAME the miss.
;;; C:PFPCTL prints the same table on demand -- one CAD run settles which name
;;; is real, and then the losers can be deleted from these lists.

;; SETTLED BY PFPCTL 2026-07-29: all eight per-class candidates missed.  The
;; accessor is GENERIC -- dcl_Control_GetValue, used on any control that
;; carries a value (Opendcl_Reference/AUBlockTool_Final.lsp:33-36 reads four
;; Slider Bars with it; :139/:147 write them back with SetValue).  There is no
;; dcl-OptionList-* or dcl-CheckBox-* family at all.  Hyphens first because
;; that is the spelling this build answers to everywhere else in the file; the
;; underscore form is what the vendor samples are written in and is kept as the
;; fallback rather than a guess.
;; CHECK BOX ONLY.  There is no Option List getter list any more, and adding
;; one back is a bug: dcl-Control-GetValue on an Option List raises the modal
;; "Property <Value> not found" AND returns nil to LISP.  That combination is
;; why it looked safe -- the first PFPCTL run printed six tidy nils, and every
;; one of them had put a dialog on screen first (field report 2026-07-29).
;; A Check Box does carry Value: chkbxZoom answers 0 unticked, no dialog.
(setq *pfp-chk-getters* '("dcl-Control-GetValue" "dcl_Control_GetValue"))

;; What an Option List calls its first item.  Still unconfirmed -- see
;; *pfp-opt-vals* below; the first observed event settles it, and C:PFPCTL
;; prints what came back.
(if (not (boundp '*pfp-opt-base*)) (setq *pfp-opt-base* 0))

;;; ---- Option Lists are read from their EVENT, not by a getter -------------
;;; MEASURED BY PFPCTL 2026-07-29: dcl-Control-GetValue answers 0 on chkbxZoom
;;; but nil on optLabel, optRun AND optTools.  It is real, and it does not
;;; apply to an Option List in this build.
;;;
;;; The vendor's own idiom is the answer.  Opendcl_Reference/AUBlockTool_Final
;;; .lsp:101 reads a Check Box as
;;;     (defun c:..._chkScaleRand_OnClicked (nValue /) (if (= nValue 0) ...))
;;; -- OpenDCL PASSES THE VALUE INTO THE HANDLER.  So the palette remembers what
;;; the control last reported, exactly as it already remembers tree selections
;;; in *pfp-sel* / *pfp-tar-sel*.  A plain setq; remembering touches nothing.
;;;
;;; STARTS EMPTY, AND AN UNOBSERVED GROUP REFUSES TO RUN.  Seeding it with "0 =
;;; Structures, whatever the .odcl shows" would be a guess about which pass to
;;; fire, and that is the one error this tab must never make -- it does not
;;; fail loudly, it labels the wrong thing.  One click on the radio costs a
;;; second and is exact.
(if (not (boundp '*pfp-opt-vals*)) (setq *pfp-opt-vals* '()))

;; (pfp:opt-remember nm Label Key) -> nil     stores (nm Label . Key)
;;   Keeps BOTH halves of what the event handed over.  Label is what actually
;;   dispatches (see *pfp-opt-captions*); Key is kept because it is the thing
;;   that would matter if a caption is ever renamed, and because PFPCTL showing
;;   both is what turns "it does not work" into one line of diagnosis.
(defun pfp:opt-remember (nm Label Key / cell)
  (setq *pfp-opt-vals*
          (if (setq cell (assoc nm *pfp-opt-vals*))
            (subst (list nm Label Key) cell *pfp-opt-vals*)
            (cons (list nm Label Key) *pfp-opt-vals*)))
  (princ))

;; WHICH ITEM IS WHICH, BY CAPTION -- not by index.
;;   The index base (0 or 1) was never established and cannot fail loudly: read
;;   wrong, it runs the wrong pass.  The caption cannot be read wrong.  Patterns
;;   rather than equality because the .odcl's captions are not trustworthy to
;;   the character -- btnClear's reads "CLear" -- and a wildcard survives a
;;   typo, a case change and a re-word that an (= s "Structures") would not.
(setq *pfp-opt-captions*
  '(("optLabel" ("*STRUCT*"   . 0) ("*INVERT*" . 1) ("*CROSS*" . 2))
    ("optRun"   ("*OUTSTAND*" . 1) ("*ALL*"    . 0) ("*SEL*"   . 2))))

;; SelChanged, confirmed in Studio 2026-07-29 -- an Option List offers NO
;; Clicked event, so the Check Box's OnClicked(nValue) shape is a precedent for
;; the value-in-the-handler idea and not for the name.
;;
;; ARITY IS THE RISK, not the name.  tvwLines#OnSelChanged in this same file
;; takes TWO arguments (Label Key), and a handler whose argument list does not
;; match what OpenDCL calls it with fails before its body runs -- so it would
;; record nothing and look exactly like an unticked event.  These take the one
;; argument an Option List should carry; if Studio's template shows a different
;; list, THIS is the line to correct, and pfp:opt-remember stores whatever
;; arrives so PFPCTL can show what it really was.
(defun c:pfsuite/pfsPalette/optLabel#OnSelChanged (nValue / )
  (pfp:opt-remember "optLabel" nValue) (princ))
(defun c:pfsuite/pfsPalette/optRun#OnSelChanged (nValue / )
  (pfp:opt-remember "optRun" nValue) (princ))

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

;; (pfp:opt-item ctrl label) -> item index, normalised to 0-based | nil
;;   READS NOTHING FROM THE CONTROL.  An earlier version tried GetValue first
;;   "in case a build answers it", which put a modal dialog on screen on every
;;   press of RUN.  The event value is the ONLY source; see *pfp-opt-vals*.
;;   ctrl is still taken, and still checked, because a control missing from the
;;   loaded project is a different fault with a different fix.
(defun pfp:opt-item (ctrl label / v)
  (cond
    ((null ctrl)
     (prompt (strcat "\nPFPALETTE: control \"" label "\" is not in the loaded"
                     " project -- check its (Name) in Studio."))
     nil)
    ((numberp (setq v (cdr (assoc label *pfp-opt-vals*))))
     (- (fix v) *pfp-opt-base*))
    (T
     (prompt (strcat "\nPFPALETTE: nothing has reported \"" label "\" yet."
                     "\n  This build's Option Lists do not answer GetValue, so the"
                     " palette learns the\n  selection from the control's own"
                     " event.  CLICK ONE ITEM in that group and\n  try RUN again."
                     "  (If clicking changes nothing, the event is not ticked in"
                     "\n  Studio -- see PFPAPI.)"))
     nil)))

;; (pfp:chk-on-p ctrl label) -> T | nil
;;   NOT (if v T nil).  GetValue is the generic numeric accessor, so an unticked
;;   box answers 0 -- and in AutoLISP 0 is TRUE.  Written the obvious way this
;;   reads every check box as ON, which for chkbxZoom means a zoom parade after
;;   every single run with no way to turn it off.  Compare against 0 explicitly.
;;   An unreadable box reads as OFF rather than refusing the run: Zoom To is a
;;   convenience, and killing a labeling pass because the palette cannot tell
;;   whether to parade afterwards is the wrong trade.  It says so once.
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

;; (pfp:order-mode cmd) -> "All" | "Out" | nil
;;   optRun is Label All / Label Outstanding / Label Selected, in that order.
;;   Selected is REFUSED rather than silently coerced to All: the palette has
;;   no item list to select from (detailsList is a per-target summary, SECTION
;;   5b), and quietly running a different pass than the one the operator picked
;;   is worse than sending them to the modal.
;;   Crossings ignores optRun entirely -- pfxl:run has no mode, and its own
;;   All already means "every crossing not yet labeled" (pfxlabel.lsp:432).
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
;;   defer is refused -- a ticket left behind after a refusal would fire on the
;;   NEXT run, against the row that was selected yesterday.  Same discipline as
;;   pfp:fire; same reason.
(defun pfp:order-fire ( / row i cmd mode)
  (cond
    ((null (setq row (pfp:need-row *pfp-tar-sel* 'ANCHORED))) nil)
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

;;; ---- the dispatcher ------------------------------------------------------

;; (pfp:order-gather anchor pass) -> (lines inlets pend status) | nil
;;   pflabel:run-dialog's gather (pflabel.lsp:257-264) minus the dialog.  Every
;;   call in it is a read, but it runs in a command context anyway, so the
;;   write-free constraint does not apply here -- unlike the SECTION 5b fill.
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
;;   Both engines take the identical ticket and both read the SAME 'sel key --
;;   mode only decides whether the previous pass is erased first
;;   (pflabel.lsp:573).  So Outstanding is mode "Sel" over the unlabeled subset,
;;   which is why it needed no engine edit.
(defun pfp:run-labels (cmd row mode / anchor pass g lines inlets pend status sel)
  (setq anchor (nth 3 row)
        pass   (if (eq cmd 'INVERT) *pfi-pass-name* "LABEL")
        g      (pfp:order-gather anchor pass))
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
;;   C:PFXLABEL's body (pfxlabel.lsp:412-435) minus the target pick and the
;;   dialog.  Its All branch already means "every crossing not yet labeled", so
;;   there is no Outstanding variant to build and no relabel confirm to answer
;;   -- the already-labeled ones are filtered out rather than duplicated.
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
  ;; READ AND CLEARED IN ONE setq -- the graft rule, PALETTE-LAYOUT 10.  A
  ;; ticket left behind would re-fire on a bare PFPRUN typed at the command
  ;; line, running yesterday's row against today's drawing.
  (setq ord        *pfp-order*
        *pfp-order* nil
        cmd        (cdr (assoc 'cmd  ord))
        row        (cdr (assoc 'row  ord))
        mode       (cdr (assoc 'mode ord)))
  ;; The Zoom To override rides the existing one-shot channel rather than the
  ;; ticket: pf:zoom-resolve reads AND clears it at the top of every engine run
  ;; (pftools-lib.lsp:1449), which is the same read-once discipline the ticket
  ;; would have to reimplement.  Routing it through rd instead would mean
  ;; editing all three engines; PALETTE-LAYOUT 6 wants that eventually.
  (setq *pf-zoom-to* (if (cdr (assoc 'zoom ord)) 'ON 'OFF))
  (if (eq cmd 'XING)
    (pfp:run-xings row)
    (pfp:run-labels cmd row mode))
  ;; Counts only -- NOT pfp:refresh.  A labeling pass cannot change the
  ;; registry, so rebuilding both trees would be wasted work AND would clear
  ;; *pfp-tar-sel*, blanking the panel the operator is reading their result
  ;; from.  The registry-changing verbs (SECTION 8) still take the full
  ;; refresh; these do not.
  (if *pfp-tar-sel* (pfp:fill-details *pfp-tar-sel*))
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
;;   Inline, not deferred: this touches the palette and nothing else.  The TREE
;;   selection is left where it is -- OpenDCL Trees have no attested "select
;;   nothing" call, and dropping the remembered row is what actually stops RUN
;;   firing, which is the point of the button.
(defun pfp:clear-target ()
  (setq *pfp-tar-sel* nil)
  (pfp:fill-details nil)
  (prompt "\nPFPALETTE: target cleared -- pick a line on the Commands tab.")
  (princ))

;; (pfp:cmd-init) -> nil
;;   Called from pfp:refresh and NOT from OnInitialize: that event fires before
;;   the window is realized and this file already carries the scar of writing
;;   there (SECTION 4).  Idempotent, unlike AddColumns, so a per-refresh call
;;   is free.
;;   IT DOES NOT TOUCH optRun.  An earlier version tried to nudge it to Label
;;   Outstanding with dcl-Control-SetValue, which raised a MODAL "Property
;;   <Value> not found" dialog on every palette open (field report 2026-07-29).
;;   An Option List has no Value property to write any more than it has one to
;;   read, and -- the part worth remembering -- **vl-catch-all-apply does NOT
;;   suppress an OpenDCL argument-validation error.** It is raised by the ARX
;;   as a modal box before LISP ever sees a return value, so wrapping a probe
;;   in a catch does not make it safe.  Getters degrade quietly to nil; setters
;;   do not degrade at all.  Discover with C:PFPAPI (a symbol-table read, no
;;   call) rather than by trial-calling anything against a live control.
;;   optRun's default item is therefore a STUDIO setting: set it to Label
;;   Outstanding there, because Label All ERASES this pass's previous output
;;   before redrawing (pflabel.lsp:573) and on the palette that is one click
;;   with no dialog in front of it.
(defun pfp:cmd-init ( / c)
  (foreach c (list (cons "frmTools" pfsuite/pfsPalette/frmTools)
                   (cons "optTools" pfsuite/pfsPalette/optTools))
    (if (cdr c)
      (vl-catch-all-apply 'dcl-Control-SetEnabled (list (cdr c) nil))))
  (princ))

(defun c:pfsuite/pfsPalette/btnRun#OnClicked ()
  (pfp:order-fire)
  (princ))

(defun c:pfsuite/pfsPalette/btnClear#OnClicked ()
  (pfp:clear-target)
  (princ))

;; C:PFPCTL -- what do the Commands tab's value controls actually return?
;;   The accessor NAME is settled (dcl_Control_GetValue, generic).  What is not
;;   settled is the Option List INDEX BASE, and that one cannot fail loudly: a
;;   1-based list read as 0-based runs Inverts when Structures is selected.
;;
;;   SO READ THE VALUES, not just the names.  Select Structures on the Commands
;;   tab, tick Zoom To, then run this:
;;     optLabel 0, chkbxZoom non-zero -> *pfp-opt-base* 0 is right, nothing to do
;;     optLabel 1                     -> set *pfp-opt-base* to 1
;;     optLabel "" or nil             -> GetValue is not the accessor after all
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
;;   Written after four rounds of guessing accessor names cost four CAD runs.
;;
;;   NO PROMPT.  The first version asked for a filter with getstring and was
;;   cancelled mid-read by a palette click -- a MODELESS FORM CAN INTERRUPT A
;;   COMMAND-LINE READ, and "Function cancelled" is what that looks like from
;;   the outside.  Nothing that prompts is safe while the palette is open.
;;   So it dumps the groups the Commands tab actually needs; for anything else,
;;   call the helper straight from the command line:
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

;;   IT NO LONGER PROBES THE OPTION LISTS.  Doing so was the diagnostic causing
;;   the fault it was meant to diagnose: six GetValue calls, six modal dialogs,
;;   six tidy nils in the report.  Option Lists are reported from what their
;;   events have said; only the Check Box is actually read.
(defun c:PFPCTL ( / f nm v)
  (cond
    ((not (dcl-Form-IsActive pfsuite/pfsPalette))
     (prompt "\nPFPCTL: run PFPALETTE first."))
    (T
     (prompt "\n=== PFPCTL -- Commands tab value controls ===")
     (prompt "\n  Option Lists (from their events -- NEVER read with GetValue):")
     (foreach nm '("optLabel" "optRun")
       (setq v (cdr (assoc nm *pfp-opt-vals*)))
       (prompt (strcat "\n    " nm " -> "
                       (cond
                         ((numberp v)
                          (strcat (itoa v) "  = item "
                                  (itoa (- (fix v) *pfp-opt-base*))
                                  " (base " (itoa *pfp-opt-base*) ")"))
                         ;; fired, but handed something that is not an index --
                         ;; the handler's argument list does not match the event
                         (v (strcat (vl-princ-to-string v)
                                    "  <-- NOT A NUMBER: the #OnSelChanged"
                                    " argument list is wrong"))
                         (T "NOTHING REPORTED YET -- click an item in that group")))))
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


(princ "\npfpalette.lsp loaded (V5 palette, milestone 2).  Command: PFPALETTE.")
(princ "\n  AFTER EVERY STUDIO SAVE:  PFPRELOAD   (else the .odcl is not re-read)")
(princ "\n  Diagnostics: PFPDIAG (names), PFPPROBE (setters), PFPREAD (rects),")
(princ "\n               PFPMOVE (clipping),")
(princ "\n               PFPNUDGE (repaint), PFPDBMOD (writes).")
(princ "\n  Native look: PFPTHEME (re-skin after a COLORTHEME flip), PFPSCALE.")
(princ "\n  Commands tab: PFPRUN (the RUN ticket), PFPCTL (control values),")
(princ "\n                PFPAPI (what dcl* functions this build registers).")
(princ)
;;; ==========================================================================
;;; end of pfpalette.lsp
;;; ==========================================================================
