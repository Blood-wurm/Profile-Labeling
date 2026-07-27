;;; ==========================================================================
;;; pfpalette.lsp  --  PFTools V5 OpenDCL palette front-end (milestone 2,
;;;                    read-only).  Command: PFPALETTE.
;;; Load position 10 of 10: last; may depend on every file above it.
;;; Model, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfp-loaded*))   (setq *pfp-loaded* nil))
(if (not (boundp '*pfp-tree-map*)) (setq *pfp-tree-map* '())) ; (Key . reg-row)


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
(defun c:PFPALETTE ( / )
  (if (pfp:ensure)
    (if (dcl-Form-IsActive pfsuite/pfsPalette)
      (dcl-Form-Close pfsuite/pfsPalette)
      (progn
        (dcl-Form-Show pfsuite/pfsPalette)
        (pfp:refresh)))                     ; data fill AFTER the window exists
    (prompt "\nPFPALETTE: could not load the OpenDCL project."))
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
;;; SECTION 2  --  Cell formatting
;;; ==========================================================================

;; (pfp:file-cell p) -> "name.ext" | "(not set)"   (unbound reads explicit)
(defun pfp:file-cell (p)
  (if (and p (/= p ""))
    (strcat (vl-filename-base p) (vl-filename-extension p))
    "(not set)"))

;; (pfp:dash s) -> s | "-"   (a blank scalar reads as a dash, never "")
(defun pfp:dash (s) (if (and s (/= s "")) s "-"))


;;; ==========================================================================
;;; SECTION 3  --  OnInitialize  (columns once, seed labels, fill the tree)
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

;; (pfp:seed-labels reg) -> nil   (project root + registry tallies; all cheap)
(defun pfp:seed-labels (reg / root n placed)
  (setq root (pfset:root-get))
  (dcl-Control-SetCaption pfsuite/pfsPalette/lblProject
    (strcat "Project: " (if root root "(none)")))
  (setq n      (length reg)
        placed (length (vl-remove-if-not
                         '(lambda (r) (eq (caddr r) 'PLACED)) reg)))
  (dcl-Control-SetCaption pfsuite/pfsPalette/lblCounts
    (strcat (itoa n) " line" (if (= n 1) "" "s") "  ("
            (itoa placed) " anchored, "
            (itoa (- n placed)) " registered)"))
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
;;; SECTION 4  --  tvwLines selection -> fill metaList + lvwLinkage
;;; ==========================================================================
;;; Anchored (PLACED) lines read from the anchor block + ledger; registered
;;; (STUB) lines read from the stub row.  UI vocabulary is "Anchored" /
;;; "Registered" -- never "placed" / "stub".

;; (pfp:sel-row Key) -> reg-row | nil   (nil when Key is a Type parent)
(defun pfp:sel-row (key) (cdr (assoc key *pfp-tree-map*)))

;; (pfp:meta-rows row) -> list of (prop -1 value -1) rows for metaList
(defun pfp:meta-rows (row / type name ename at cl mat)
  (setq type (car row) name (cadr row))
  (cond
    ((eq (caddr row) 'PLACED)
     (setq ename (nth 3 row)
           at    (pfa:read-attribs ename)
           cl    (cdr (assoc 1 (pfa:meta-get ename)))
           mat   (cdr (assoc 5 (pfa:files-get ename))))
     (list (list "Type"       -1 type                          -1)
           (list "Line"       -1 name                          -1)
           (list "State"      -1 "Anchored"                    -1)
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
    ((eq (caddr row) 'PLACED)
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


(princ "\npfpalette.lsp loaded (V5 palette, milestone 2).  Command: PFPALETTE.")
(princ)
;;; ==========================================================================
;;; end of pfpalette.lsp
;;; ==========================================================================
