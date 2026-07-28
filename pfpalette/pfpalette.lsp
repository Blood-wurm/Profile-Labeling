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
  (setq res (vl-catch-all-apply
              '(lambda ( / reg)
                 (setq reg (pfa:registry))
                 (pfp:seed-labels reg)
                 (pfp:fill-tree reg))
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

;; (pfp:fill-tree reg) -> nil
;;   Two levels: distinct utility Type as parents, Line as children.  The
;;   registry arrives sorted by "TYPE NAME", so a type break is a new parent.
;;   Records (childKey . reg-row) in *pfp-tree-map* for OnSelChanged.
(defun pfp:fill-tree (reg / cur-type pkey ckey first r)
  (dcl-Tree-Clear pfsuite/pfsPalette/tvwLines)
  (setq *pfp-tree-map* '() cur-type nil pkey nil first nil)
  (foreach r reg
    (if (not (equal (car r) cur-type))
      (setq cur-type (car r)
            pkey (dcl-Tree-AddParent pfsuite/pfsPalette/tvwLines
                                     cur-type -1 -1 -1)))
    (if (null first) (setq first pkey))     ; remember the first parent
    (setq ckey (dcl-Tree-AddChild pfsuite/pfsPalette/tvwLines
                                  pkey (cadr r) -1 -1 -1)
          *pfp-tree-map* (cons (cons ckey r) *pfp-tree-map*)))
  (if first (dcl-Tree-SelectItem pfsuite/pfsPalette/tvwLines first))
  (princ))


;;; ==========================================================================
;;; SECTION 5  --  tvwLines selection -> fill metaList + lvwLinkage
;;; ==========================================================================
;;; Anchored lines read from the anchor block + ledger; registered (STUB)
;;; lines read from the stub row.  UI vocabulary is "Anchored" / "Registered"
;;; -- never "placed" / "stub".

;; (pfp:sel-row Key) -> reg-row | nil   (nil when Key is a Type parent)
(defun pfp:sel-row (key) (cdr (assoc key *pfp-tree-map*)))

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

(defun c:pfsuite/pfsPalette/tvwLines#OnSelChanged (Label Key / row)
  (setq row (pfp:sel-row Key))
  ;; A Type parent has no row -- clear both panels; a Line fills them.
  (dcl-ListView-FillList pfsuite/pfsPalette/metaList
    (if row (pfp:meta-rows row) '()))
  (pfp:fill-linkage row)
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


(princ "\npfpalette.lsp loaded (V5 palette, milestone 2).  Command: PFPALETTE.")
(princ "\n  AFTER EVERY STUDIO SAVE:  PFPRELOAD   (else the .odcl is not re-read)")
(princ "\n  Diagnostics: PFPDIAG (names), PFPPROBE (setters), PFPREAD (rects),")
(princ "\n               PFPMOVE (clipping),")
(princ "\n               PFPNUDGE (repaint), PFPDBMOD (writes).")
(princ "\n  Native look: PFPTHEME (re-skin after a COLORTHEME flip), PFPSCALE.")
(princ)
;;; ==========================================================================
;;; end of pfpalette.lsp
;;; ==========================================================================
