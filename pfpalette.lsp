;;; ==========================================================================
;;; pfpalette.lsp  --  PFTools V5 OpenDCL palette front-end (loader + M2)
;;; --------------------------------------------------------------------------
;;; Loaded LAST by pftools-load.lsp.  May depend on every file above it; reads
;;; the registry through pfanchor's pfa: API and the project root through
;;; pfsettings' pfset: API.  New palette code carries a pfp: prefix.
;;;
;;; MILESTONE 2 -- READ-ONLY.  Every #On... handler runs in a MODELESS context
;;; (outside a command): no entsel / getpoint / command / undo group in a
;;; handler, ever.  This pass only READS the drawing (registry scan, anchor
;;; attribute + ledger reads) and never writes it -- so it cannot damage a
;;; sheet while it is wrong.  Labeled/outstanding and every derived status is
;;; deliberately NOT computed here (that is the deferred status pane).
;;;
;;; PROJECT PREFIX is `pfsuite/` -- the .odcl project node is named pfsuite
;;; (the file was renamed from pfsetup.odcl).  Control paths are three
;;; segments: pfsuite/pfsPalette/<control>.
;;;
;;; UNVERIFIED IN CAD -- nothing in this file has ever been executed.  Two
;;; spellings could not be proven from the shipped samples and need CAD:
;;;   (a) image index -1 = "no image" in Tree/ListView adds (controls carry
;;;       no image list); (b) dcl-Tree-AddChild returns the new child Key.
;;; See the test steps in the wiring notes.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfp-loaded*))   (setq *pfp-loaded* nil))
(if (not (boundp '*pfp-tree-map*)) (setq *pfp-tree-map* '())) ; (Key . reg-row)


;;; ==========================================================================
;;; SECTION 1  --  Loader + C:PFPALETTE toggle
;;; ==========================================================================

;; (pfp:odcl-path) -> full path to the project file, derived from *pftools-dir*
;;   The ONE path lives in pftools-load.lsp; never hardcode a second copy.
(defun pfp:odcl-path () (strcat *pftools-dir* "pfsuite.odcl"))

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
;;   and Close re-runs OnInitialize on the next open, which re-reads the
;;   registry -- exactly the derived-never-cached contract this suite lives by.
(defun c:PFPALETTE ( / )
  (if (pfp:ensure)
    (if (dcl-Form-IsActive pfsuite/pfsPalette)
      (dcl-Form-Close pfsuite/pfsPalette)
      (progn
        (dcl-Form-Show pfsuite/pfsPalette)
        (pfp:repaint)))                     ; force the deferred first paint
    (prompt "\nPFPALETTE: could not load the OpenDCL project."))
  (princ))

;; (pfp:repaint) -> nil
;;   Docked-palette deferred-paint workaround.  OnInitialize populates the
;;   controls BEFORE the window is fully realized, so nothing draws until a
;;   window event forces it (undock/float or resize does it by hand).  Must
;;   run AFTER dcl-Form-Show -- toggling the form's enable state forces the
;;   redraw without the user having to touch the palette.
(defun pfp:repaint ()
  (dcl-Form-Enable pfsuite/pfsPalette nil)
  (dcl-Form-Enable pfsuite/pfsPalette T)
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

(defun c:pfsuite/pfsPalette#OnInitialize ( / reg)
  ;; Columns are a RUNTIME add and belong here ONLY -- AddColumns is additive,
  ;; so calling it from a refresh would stack duplicate columns (README 4).
  (dcl-ListView-AddColumns pfsuite/pfsPalette/metaList
    (list (list "Property" 0 110) (list "Value" 0 410)))
  (dcl-ListView-AddColumns pfsuite/pfsPalette/lvwLinkage
    (list (list "Item" 0 90) (list "File" 0 440)))
  ;; The registry read can fail on a hostile drawing; never let that stop the
  ;; palette from opening -- milestone 1 must always be able to dock.
  (vl-catch-all-apply
    '(lambda ( / reg)
       (setq reg (pfa:registry))
       (pfp:seed-labels reg)
       (pfp:fill-tree reg)))
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
