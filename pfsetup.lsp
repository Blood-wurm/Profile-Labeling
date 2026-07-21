;;; ==========================================================================
;;; pfsetup.lsp  --  C:PFSETUP : two-tier registration (AUTO names, USER places)
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg, pftools-lib, pfdraw, pfanchor, pfsettings loaded
;;; first.  Dialog definition: pfsetup_main in pfdialog.dcl.
;;;
;;; REGISTRATION SPLITS IN TWO:
;;;
;;;   AUTO (identity) -- fires when the drawing has no registry.  Scans
;;;   PF-NAME text sheet-wide (names only -- the sheet-geometry parser is
;;;   dead), resolves each to Type_Name.cl by convention, auto-binds the
;;;   _INV/_TOP .pro pair, writes NOD STUBS.  No matching .cl, ambiguous
;;;   match, or a .cl with no grid name = REPORTED AND SKIPPED, never
;;;   guessed.  Identity alone is enough to DISCOVER -- the whole sheet is
;;;   a crossing-matrix candidate set the moment AUTO runs.
;;;
;;;   USER (placement) -- promotes stub -> anchor, per grid:
;;;     dialog (identity override, scales, file bindings, DATUM typed) ->
;;;     pick LOWER-LEFT (datum line = transform origin) ->
;;;     pick TOP-RIGHT (EXTENTS ONLY -- no scale is measured from either
;;;     pick; stored RELATIVE as the insert's X/Y scale).
;;;   Vertical scale = declared H/V.  Per-station top = the probe.
;;;   ONE datum per grid, anchored at the lower-left; steps in the run do
;;;   not matter.  (Settled.  Do not revisit.)
;;;   The registry menu is the pfsetup_registry DIALOG; the extent picks
;;;   are the only command-line steps left in the whole flow.
;;;
;;; Entry points for placement: this command (deliberate/batch) and
;;; pfs:place-one / pfs:choose-or-place called on the fly by the label
;;; commands when they hit an unplaced grid.
;;;
;;; UNDO: one group PER GRID placement -- U peels one grid, not the batch.
;;;
;;; EDIT-MODE INVALIDATION (unchanged):
;;;   .pro swap            cheap -- record updated, derived output stale
;;;   scales / extents     everything redraws
;;;   .cl, same range      full regeneration
;;;   .cl, different range REFUSED -- new anchor; PFREMOVE first
;;;   identity (type/name) REFUSED -- PFREMOVE + fresh placement
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfs-undo-open*))  (setq *pfs-undo-open* nil))
(if (not (boundp '*pfs-datum-last*)) (setq *pfs-datum-last* nil))
(if (not (boundp '*pfs-mat-last*))   (setq *pfs-mat-last* '())) ; (TYPE . material)

(defun pfs:*error* (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFSETUP error: " msg)))
  (pfa:undo-cleanup)                ; closes ANY pf group, incl. a nested one
  (setq *error* *pfs-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 1  --  Dialog wiring  (pfsetup_main)
;;; ==========================================================================
;;; d-cl / d-pro / d-tin / d-res live in pfs:show-dialog and are reached by
;;; the action callbacks via dynamic scope while start_dialog runs.

(defun pfs:file-display (f)
  (strcat (vl-filename-base f) (vl-filename-extension f)))

;; (pfs:mat-list type) -> materials for this type | nil
(defun pfs:mat-list (type) (cdr (assoc (strcase type) *pf-materials*)))

;; (pfs:fill-materials type sel) -> nil
;;   Repopulate the Material popup for TYPE; select SEL (name) or the default
;;   (first entry).  Empty list leaves the popup empty (label falls back).
(defun pfs:fill-materials (type sel / mats idx)
  (setq mats (pfs:mat-list type))
  (start_list "s_mat")
  (foreach m mats (add_list m))
  (end_list)
  (if mats
    (progn
      (setq idx (if (and sel (pf:index-of sel mats)) (pf:index-of sel mats) 0))
      (set_tile "s_mat" (itoa idx))))
  (princ))

;; s_type change: materials follow the utility type (last-used per type wins).
(defun pfs:on-type-change ( / ty)
  (setq ty (nth (atoi (get_tile "s_type")) *pf-types*))
  (pfs:fill-materials ty (cdr (assoc (strcase ty) *pfs-mat-last*))))

;; .cl Select: sets the path and auto-fills identity from the filename.
(defun pfs:on-cl-pick ( / f idx)
  (if (setq f (pfset:browse "Select Centerline (.CL) File"
                            '*pfset-dir-cl* "cl"))
    (progn
      (setq d-cl f)
      (set_tile "s_cl" (pfs:file-display f))
      (if (= (pf:trim (get_tile "s_name")) "")
        (set_tile "s_name" (pf:name-of f)))
      (if (setq idx (pf:index-of (pf:type-of f) *pf-types*))
        (progn
          (set_tile "s_type" (itoa idx))
          (pfs:on-type-change)))     ; materials follow the derived type
      (set_tile "error" ""))))

;; .pro slot picks: each button owns a ROLE; a picked file must carry it.
;; The slot pattern is the Carlson file-row idiom (named button + path).
(defun pfs:on-pro-pick (role / f pr)
  (if (setq f (pfset:browse
                (strcat "Select the _" role " Profile (.PRO) File")
                '*pfset-dir-pro* "pro"))
    (progn
      (setq pr (pf:parse-pro-name f))
      (if (/= (cdr pr) role)
        (set_tile "error" (strcat "'" (pfs:file-display f)
                                  "' is not a _" role " .pro."))
        (progn
          (if (= role "INV") (setq d-inv f) (setq d-top f))
          (set_tile (if (= role "INV") "s_inv" "s_top") (pfs:file-display f))
          (set_tile "error" ""))))))

;; .tin slot picks: DESIGN_* goes in the Design slot, anything else in Exist.
(defun pfs:on-tin-pick (design-p / f)
  (if (setq f (pfset:browse
                (if design-p
                  "Select the DESIGN_* (proposed) Surface (.TIN) File"
                  "Select the EXISTING Ground Surface (.TIN) File")
                '*pfset-dir-tin* "tin"))
    (cond
      ((and design-p (not (eq (pf:tin-role f) 'DESIGN)))
       (set_tile "error" (strcat "'" (pfs:file-display f)
                                 "' is not a DESIGN_* surface.")))
      ((and (not design-p) (eq (pf:tin-role f) 'DESIGN))
       (set_tile "error" (strcat "'" (pfs:file-display f)
                                 "' is DESIGN_* -- pick the existing ground.")))
      (design-p
       (setq d-tind f)
       (set_tile "s_tind" (pfs:file-display f))
       (set_tile "error" ""))
      (T
       (setq d-tine f)
       (set_tile "s_tine" (pfs:file-display f))
       (set_tile "error" "")))))

;; Pair-level clears (the pairs bind both-or-neither, so they clear together).
(defun pfs:on-pro-clear ()
  (setq d-inv nil d-top nil)
  (set_tile "s_inv" "")
  (set_tile "s_top" "")
  (set_tile "error" ""))

(defun pfs:on-tin-clear ()
  (setq d-tine nil d-tind nil)
  (set_tile "s_tine" "")
  (set_tile "s_tind" "")
  (set_tile "error" ""))

;; OK: validate everything the dialog CAN validate.  Name is the identity
;; key -- picked files VALIDATE against it, they never resolve it.  The
;; slots already guarantee roles; what remains is pairing + name match.
(defun pfs:ok ( / nm hs vs ty datum msgs mlist mat)
  (setq nm    (strcase (pf:trim (get_tile "s_name")))
        hs    (distof (get_tile "s_hs"))
        vs    (distof (get_tile "s_vs"))
        datum (distof (get_tile "s_datum"))
        ty    (nth (atoi (get_tile "s_type")) *pf-types*)
        msgs  nil)
  (cond
    ((or (null d-cl) (= d-cl ""))
     (setq msgs "Select the .cl file -- station comes from it."))
    ((= nm "") (setq msgs "Line name is empty."))
    ((not (and hs vs (> hs 0.0) (> vs 0.0)))
     (setq msgs "Plot scales must be positive numbers (e.g. 20 and 2)."))
    ((null datum)
     (setq msgs "Type the datum elevation (the lower-left grid corner)."))
    ;; ---- .pro pair: both or neither, both names matching Name ------------
    ((and d-inv (null d-top))
     (setq msgs "Crown _TOP .pro missing -- bind both .pro files or neither."))
    ((and d-top (null d-inv))
     (setq msgs "Invert _INV .pro missing -- bind both .pro files or neither."))
    ((and d-inv (/= (car (pf:parse-pro-name d-inv)) nm))
     (setq msgs (strcat "INV .pro is for '" (car (pf:parse-pro-name d-inv))
                        "' but Name says '" nm "'.")))
    ((and d-top (/= (car (pf:parse-pro-name d-top)) nm))
     (setq msgs (strcat "TOP .pro is for '" (car (pf:parse-pro-name d-top))
                        "' but Name says '" nm "'.")))
    ;; ---- .tin pair: both or neither (roles guaranteed by the slots) ------
    ((and d-tine (null d-tind))
     (setq msgs "DESIGN_* surface missing -- bind both surfaces or neither."))
    ((and d-tind (null d-tine))
     (setq msgs "Existing surface missing -- bind both surfaces or neither.")))
  (if msgs
    (set_tile "error" msgs)
    (progn
      (setq mlist (pfs:mat-list ty)
            mat   (if mlist (nth (atoi (get_tile "s_mat")) mlist) "")
            *pfs-datum-last* datum)
      (setq d-res (list (cons 'type ty) (cons 'name nm)
                        (cons 'hs hs) (cons 'vs vs)
                        (cons 'cl d-cl)
                        (cons 'pro (if d-inv (list d-inv d-top) '()))
                        (cons 'tin (if d-tine (list d-tine d-tind) '()))
                        (cons 'material mat)
                        (cons 'datum datum)
                        (cons 'repick (= (get_tile "s_repick") "1"))))
      (done_dialog 1))))

;; (pfs:show-dialog init) -> result alist | nil
;;   init: same keys as the result, prefills the tiles (nil = blank form).
;;   'edit enables the re-pick toggle; 'datum prefills (else session-last).
(defun pfs:show-dialog (init / dcl_id d-cl d-inv d-top d-tine d-tind d-res
                        s idx result ity imat f)
  (setq dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfsetup_main" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the PFSETUP dialog.") nil)
      (progn
        (setq s     (pfset:settings)
              d-cl  (cdr (assoc 'cl init))
              d-res nil)
        ;; route the init .pro / .tin lists into their role slots
        (foreach f (cdr (assoc 'pro init))
          (if (= (cdr (pf:parse-pro-name f)) "INV")
            (setq d-inv f) (setq d-top f)))
        (foreach f (cdr (assoc 'tin init))
          (if (eq (pf:tin-role f) 'DESIGN)
            (setq d-tind f) (setq d-tine f)))
        (start_list "s_type")
        (foreach ty *pf-types* (add_list ty))
        (end_list)
        (setq idx (if (assoc 'type init)
                    (pf:index-of (cdr (assoc 'type init)) *pf-types*)))
        (set_tile "s_type" (itoa (if idx idx 0)))
        (setq ity  (nth (if idx idx 0) *pf-types*)
              imat (if (assoc 'material init)
                     (cdr (assoc 'material init))
                     (cdr (assoc (strcase ity) *pfs-mat-last*))))
        (pfs:fill-materials ity imat)
        (set_tile "s_name" (if (assoc 'name init) (cdr (assoc 'name init)) ""))
        (set_tile "s_hs"
          (if (assoc 'hs init) (rtos (cdr (assoc 'hs init)) 2 2)
                               (cdr (assoc "hscale" s))))
        (set_tile "s_vs"
          (if (assoc 'vs init) (rtos (cdr (assoc 'vs init)) 2 2)
                               (cdr (assoc "vscale" s))))
        (if d-cl   (set_tile "s_cl"   (pfs:file-display d-cl)))
        (if d-inv  (set_tile "s_inv"  (pfs:file-display d-inv)))
        (if d-top  (set_tile "s_top"  (pfs:file-display d-top)))
        (if d-tine (set_tile "s_tine" (pfs:file-display d-tine)))
        (if d-tind (set_tile "s_tind" (pfs:file-display d-tind)))
        ;; datum: stored value (edit) or the session's last-typed
        (cond
          ((cdr (assoc 'datum init))
           (set_tile "s_datum" (rtos (cdr (assoc 'datum init)) 2 2)))
          (*pfs-datum-last*
           (set_tile "s_datum" (rtos *pfs-datum-last* 2 2))))
        ;; the re-pick toggle only means something on Edit
        (set_tile "s_repick" "0")
        (if (not (assoc 'edit init)) (mode_tile "s_repick" 1))
        (action_tile "s_type"      "(pfs:on-type-change)")
        (action_tile "s_cl_pick"   "(pfs:on-cl-pick)")
        (action_tile "s_inv_pick"  "(pfs:on-pro-pick \"INV\")")
        (action_tile "s_top_pick"  "(pfs:on-pro-pick \"TOP\")")
        (action_tile "s_tine_pick" "(pfs:on-tin-pick nil)")
        (action_tile "s_tind_pick" "(pfs:on-tin-pick T)")
        (action_tile "s_pro_clr"   "(pfs:on-pro-clear)")
        (action_tile "s_tin_clr"   "(pfs:on-tin-clear)")
        (action_tile "accept"      "(pfs:ok)")
        (action_tile "cancel"      "(done_dialog 0)")
        (action_tile "help"
          (strcat "(pfset:help \"PFSETUP records a profile grid.\\n\\n"
                  "Name is the identity key -- picked files validate "
                  "against it.\\nBind the .cl (station source), the "
                  "_INV/_TOP .pro pair, and the existing + DESIGN_* "
                  "surfaces (each pair both-or-neither).\\n\\nType the "
                  "datum elevation (lower-left grid corner), then OK: "
                  "pick LOWER-LEFT, then TOP-RIGHT (extents only -- no "
                  "scale is measured from the picks).\")"))
        (setq result (vl-catch-all-apply 'start_dialog '()))
        (unload_dialog dcl_id)
        (cond
          ((vl-catch-all-error-p result)
           (prompt (strcat "\nDialog error: "
                           (vl-catch-all-error-message result)))
           nil)
          ((= result 1)
           ;; the scales the user confirmed become the new defaults
           (pfset:put-setting "hscale" (rtos (cdr (assoc 'hs d-res)) 2 2))
           (pfset:put-setting "vscale" (rtos (cdr (assoc 'vs d-res)) 2 2))
           ;; remember the material per type for the next placement of that type
           (if (and (cdr (assoc 'material d-res))
                    (/= (cdr (assoc 'material d-res)) ""))
             (setq *pfs-mat-last*
                   (cons (cons (strcase (cdr (assoc 'type d-res)))
                               (cdr (assoc 'material d-res)))
                         (vl-remove-if
                           '(lambda (p)
                              (= (car p) (strcase (cdr (assoc 'type d-res)))))
                           *pfs-mat-last*))))
           (pfset:save-auto)
           d-res)
          (T nil))))))


;;; ==========================================================================
;;; SECTION 2  --  AUTO registration  (identity, sheet-wide, never guesses)
;;; ==========================================================================

;; (pfs:scan-sheet-names) -> list of (type . name), deduped
;;   PF-NAME text only -- names, not geometry.
(defun pfs:scan-sheet-names ( / ss i ed s ty nm out key seen)
  (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 8 *pfg-name-layer*)))
        out '() seen '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq ed (entget (ssname ss i))
            s  (cdr (assoc 1 ed))
            ty (if s (pf:sheet-type s))
            nm (if ty (pf:parse-sheet-name s ty)))
      (if (and ty nm)
        (progn
          (setq key (strcat ty "|" nm))
          (if (not (member key seen))
            (setq seen (cons key seen)
                  out  (cons (cons ty nm) out)))))
      (setq i (1+ i))))
  (reverse out))

;; (pfs:cl-lookup dir type name) -> path | 'AMBIG | nil
(defun pfs:cl-lookup (dir type name / files f base pos ty nm matches)
  (setq files (vl-directory-files dir "*.cl" 1) matches '())
  (foreach f files
    (setq base (vl-filename-base f)
          pos  (vl-string-search "_" base))
    (if pos
      (progn
        (setq ty (strcase (substr base 1 pos))
              nm (strcase (substr base (+ pos 2))))
        (if (and (= ty (strcase type)) (= nm (strcase name)))
          (setq matches (cons (strcat dir f) matches))))))
  (cond ((null matches) nil)
        ((cdr matches) 'AMBIG)
        (T (car matches))))

;; (pfs:pro-lookup dir type name role) -> path | nil   (exact, case-insens)
(defun pfs:pro-lookup (dir type name role / want found f)
  (setq want  (strcase (strcat type "_" name "_" role ".PRO"))
        found nil)
  (foreach f (vl-directory-files dir "*.pro" 1)
    (if (and (null found) (= (strcase f) want))
      (setq found (strcat dir f))))
  found)

;; (pfs:auto dir) -> nil
;;   Names every profile the sheet declares; loud-skips both directions.
;;   Idempotent -- placed profiles and existing stubs pass through.
(defun pfs:auto (dir / names pair ty nm m inv top new f base pos)
  (prompt "\nAUTO registration: naming profiles sheet-wide...")
  (setq names (pfs:scan-sheet-names) new 0)
  (if (null names)
    (prompt (strcat "\n  No PF-NAME text found on layer "
                    *pfg-name-layer* "."))
    (progn
      (foreach pair names
        (setq ty (car pair) nm (cdr pair))
        (cond
          ((pfa:find-anchor nm ty))            ; placed -- nothing to do
          ((pfa:stub-get ty nm))               ; already named
          (T
           (setq m (pfs:cl-lookup dir ty nm))
           (cond
             ((null m)
              (prompt (strcat "\n  SKIPPED " ty " '" nm "' -- no "
                              ty "_" nm ".cl in the project folder.")))
             ((eq m 'AMBIG)
              (prompt (strcat "\n  SKIPPED " ty " '" nm
                              "' -- multiple .cl files match; never guessed.")))
             (T
              (setq inv (pfs:pro-lookup dir ty nm "INV")
                    top (pfs:pro-lookup dir ty nm "TOP"))
              (pfa:stub-put ty nm m inv top)
              ;; file the .cl shape ONCE, now -- label commands read it later
              ;; instead of re-tracing the line every run
              (pf:cl-geom m)
              (setq new (1+ new))
              (prompt (strcat "\n  Named " ty " '" nm "'  ("
                              (pfs:file-display m)
                              (cond ((and inv top) " + INV/TOP pro")
                                    ((or inv top)  " + ONE pro only")
                                    (T             " -- no .pro pair"))
                              ")")))))))
      ;; reverse direction: a .cl with no grid name on the sheet
      (foreach f (vl-directory-files dir "*.cl" 1)
        (setq base (vl-filename-base f)
              pos  (vl-string-search "_" base))
        (if pos
          (progn
            (setq ty (strcase (substr base 1 pos))
                  nm (strcase (substr base (+ pos 2))))
            (if (and (member ty *pf-types*)
                     (null (pfa:find-anchor nm ty))
                     (null (pfa:stub-get ty nm)))
              (prompt (strcat "\n  NOTE: " f
                              " has no grid name on the sheet."))))))
      (prompt (strcat "\n  " (itoa new) " profile(s) named."))))
  (princ))


;;; ==========================================================================
;;; SECTION 3  --  Placement  (the per-grid unit; both entry points land here)
;;; ==========================================================================

;; (pfs:pick-extents) -> (ll tr) | nil
(defun pfs:pick-extents ( / ll tr)
  (setq ll (getpoint "\nPick grid LOWER-LEFT corner (on the datum line): "))
  (cond
    ((null ll) (prompt "\nNo point picked -- cancelled.") nil)
    (T
     (setq tr (getcorner ll "\nPick grid TOP-RIGHT corner (extents only): "))
     (cond
       ((null tr) (prompt "\nNo point picked -- cancelled.") nil)
       ((or (<= (car tr) (car ll)) (<= (cadr tr) (cadr ll)))
        (prompt "\nTop-right must be above and right of lower-left -- cancelled.")
        nil)
       (T (list ll tr))))))

;; (pfs:ask-datum is GONE -- the datum is typed in the pfsetup_main dialog;
;;  the only command-line steps left are the two extent picks.)

;; (pfs:bind-files anchor res) -> list of notes
;;   FILES record + checksums from the dialog result.
(defun pfs:bind-files (anchor res / r inv top tine tind notes)
  (setq inv nil top nil tine nil tind nil notes '())
  (foreach r (cdr (assoc 'pro res))
    (if (= (cdr (pf:parse-pro-name r)) "INV") (setq inv r) (setq top r)))
  (foreach r (cdr (assoc 'tin res))
    (if (eq (pf:tin-role r) 'DESIGN) (setq tind r) (setq tine r)))
  (pfa:files-put anchor
                 inv (if inv (pf:checksum-file inv))
                 top (if top (pf:checksum-file top))
                 tine tind (cdr (assoc 'material res)))
  (if (null (cdr (assoc 'pro res)))
    (setq notes (cons "no .pro pair bound (INV/TOP)" notes)))
  (if (null (cdr (assoc 'tin res)))
    (setq notes (cons "no surfaces bound (existing/DESIGN)" notes)))
  notes)

;; (pfs:build-xform res ll tr datum) -> xform alist (rightx included)
(defun pfs:build-xform (res ll tr datum / hs vs xf)
  (setq hs (cdr (assoc 'hs res))
        vs (cdr (assoc 'vs res))
        xf (pf:make-xform (car ll)
                          (car (pf:cl-range (cdr (assoc 'cl res))))
                          (cadr tr) (cadr ll)
                          datum (/ hs vs) hs vs))
  (pf:xf-put 'rightx (car tr) xf))

;; (pfs:place-one stub) -> anchor | nil
;;   stub = (type name cl inv top) | nil (blank form).  Dialog -> picks ->
;;   typed datum -> write, ONE undo group.  Promotion deletes the stub
;;   under its ORIGINAL key, so a dialog override re-keys cleanly.
(defun pfs:place-one (stub / init pro res ty nm cl rng pts ll tr datum xf
                       anchor notes r)
  (setq init '())
  (if stub
    (progn
      (setq init (list (cons 'type (car stub))
                       (cons 'name (cadr stub))
                       (cons 'cl (caddr stub)))
            pro  '())
      (if (and (nth 3 stub) (/= (nth 3 stub) ""))
        (setq pro (append pro (list (nth 3 stub)))))
      (if (and (nth 4 stub) (/= (nth 4 stub) ""))
        (setq pro (append pro (list (nth 4 stub)))))
      (if pro (setq init (cons (cons 'pro pro) init)))))
  (setq res (pfs:show-dialog init))
  (cond
    ((null res) (prompt "\nPlacement cancelled.") nil)
    (T
     (setq ty (cdr (assoc 'type res))
           nm (cdr (assoc 'name res))
           cl (cdr (assoc 'cl res)))
     (cond
       ((pfa:find-anchor nm ty)
        (prompt (strcat "\n" ty " '" nm "' is already PLACED -- use Edit."))
        nil)
       ((null (setq rng (pf:cl-range cl)))
        (prompt (strcat "\nREFUSED -- could not read a station range from "
                        (pfs:file-display cl)
                        ".  Regenerate the .cl from Carlson."))
        nil)
       ((null (setq pts (pfs:pick-extents))) nil)
       (T
        (setq datum (cdr (assoc 'datum res))    ; typed in the dialog
              ll    (car pts)
              tr    (cadr pts))
        (command "_.UNDO" "_Begin")
        (setq *pfs-undo-open* T)
        (setq xf     (pfs:build-xform res ll tr datum)
              anchor (pfa:write-anchor nm ty xf cl))
        (pfa:meta-put anchor cl (pf:checksum-file cl))
        ;; file the .cl shape now (no-op if AUTO already did) so a directly
        ;; placed profile is cached too -- label commands never re-trace it
        (pf:cl-geom cl)
        (setq notes (pfs:bind-files anchor res))
        (pfa:status-put anchor 0 notes)
        (if stub (pfa:stub-del (car stub) (cadr stub)))
        (command "_.UNDO" "_End")
        (setq *pfs-undo-open* nil)
        (prompt (strcat "\n  Placed.  Sta " (pf:fmt-station (car rng))
                        " to " (pf:fmt-station (cadr rng))
                        ", datum " (rtos datum 2 2)
                        ".  (One U reverses this grid.)"))
        (foreach r notes (prompt (strcat "\n  NOTE: " r)))
        anchor)))))

;; (pfs:range-match cl-old cl-new) -> T | nil | 'UNKNOWN
(defun pfs:range-match (cl-old cl-new / r1 r2)
  (cond
    ((or (null cl-old) (= cl-old "")) 'UNKNOWN)
    ((= (strcase cl-old) (strcase cl-new)) T)
    (T
     (setq r1 (pf:cl-range cl-old)
           r2 (pf:cl-range cl-new))
     (cond
       ((or (null r1) (null r2)) 'UNKNOWN)
       ((and (<= (abs (- (car r1) (car r2))) 0.01)
             (<= (abs (- (cadr r1) (cadr r2))) 0.01)) T)
       (T nil)))))

;; (pfs:anchor-init anchor) -> dialog init alist from the stored record
;;   'edit marks the dialog as an edit session (enables the re-pick toggle).
(defun pfs:anchor-init (anchor / at meta files hp vp dt init v)
  (setq at    (pfa:read-attribs anchor)
        meta  (pfa:meta-get anchor)
        files (pfa:files-get anchor)
        hp    (distof (pfa:att "HPLOT" at) 2)
        vp    (distof (pfa:att "VPLOT" at) 2)
        dt    (distof (pfa:att "DATUM" at) 2)
        init  (list (cons 'edit T)
                    (cons 'type (pfa:att "UTIL" at))
                    (cons 'name (pfa:att "LINE" at))))
  (if dt (setq init (cons (cons 'datum dt) init)))
  (if hp (setq init (cons (cons 'hs hp) init)))
  (if vp (setq init (cons (cons 'vs vp) init)))
  (if (and meta (assoc 1 meta) (/= (cdr (assoc 1 meta)) ""))
    (setq init (cons (cons 'cl (cdr (assoc 1 meta))) init)))
  (setq v '())
  (if files
    (progn
      (if (and (assoc 1 files) (/= (cdr (assoc 1 files)) ""))
        (setq v (append v (list (cdr (assoc 1 files))))))
      (if (and (assoc 2 files) (/= (cdr (assoc 2 files)) ""))
        (setq v (append v (list (cdr (assoc 2 files))))))))
  (if v (setq init (cons (cons 'pro v) init)))
  (setq v '())
  (if files
    (progn
      (if (and (assoc 3 files) (/= (cdr (assoc 3 files)) ""))
        (setq v (append v (list (cdr (assoc 3 files))))))
      (if (and (assoc 4 files) (/= (cdr (assoc 4 files)) ""))
        (setq v (append v (list (cdr (assoc 4 files))))))))
  (if v (setq init (cons (cons 'tin v) init)))
  (if (and files (assoc 5 files) (/= (cdr (assoc 5 files)) ""))
    (setq init (cons (cons 'material (cdr (assoc 5 files))) init)))
  init)

;; (pfs:edit-one anchor) -> nil
(defun pfs:edit-one (anchor / init res at old-cl rm pts ed ins xs ys datum
                      xf notes r)
  (prompt (strcat "\nEditing " (pfa:anchor-title anchor) "."))
  (foreach r (pfa:corner-check anchor)
    (prompt (strcat "\n  DRIFT: " r)))
  (setq init (pfs:anchor-init anchor)
        res  (pfs:show-dialog init))
  (cond
    ((null res) (prompt "\nEdit cancelled -- nothing written."))
    (T
     (setq at (pfa:read-attribs anchor))
     (cond
       ;; identity is the record's KEY
       ((or (/= (strcase (pfa:att "LINE" at))
                (strcase (cdr (assoc 'name res))))
            (/= (strcase (pfa:att "UTIL" at))
                (strcase (cdr (assoc 'type res)))))
        (prompt (strcat "\nREFUSED -- identity change.  That is a NEW "
                        "record: PFREMOVE " (pfa:anchor-title anchor)
                        ", then place it fresh.")))
       ((null (pf:cl-range (cdr (assoc 'cl res))))
        (prompt (strcat "\nREFUSED -- could not read a station range from "
                        (pfs:file-display (cdr (assoc 'cl res))) ".")))
       (T
        (setq old-cl (cdr (assoc 1 (pfa:meta-get anchor)))
              rm     (pfs:range-match old-cl (cdr (assoc 'cl res))))
        (cond
          ((null rm)
           (prompt (strcat "\nREFUSED -- the new .cl has a DIFFERENT "
                           "station range: that is a rebuild, not a swap.  "
                           "PFREMOVE " (pfa:anchor-title anchor)
                           ", then place it fresh.")))
          (T
           (if (eq rm 'UNKNOWN)
             (if (and old-cl (/= old-cl "")
                      (/= (strcase old-cl)
                          (strcase (cdr (assoc 'cl res)))))
               (prompt "\n  NOTE: old .cl unreadable -- range match not verified.")))
           ;; extents: the dialog's re-pick toggle, or rebuild from the
           ;; stored relative geometry
           (if (cdr (assoc 'repick res))
             (setq pts (pfs:pick-extents))
             (progn
               (setq ed  (entget anchor)
                     ins (cdr (assoc 10 ed))
                     xs  (cdr (assoc 41 ed))
                     ys  (cdr (assoc 42 ed)))
               (if (and xs (> xs 2.0))
                 (setq pts (list (list (car ins) (cadr ins))
                                 (list (+ (car ins) xs)
                                       (+ (cadr ins) ys))))
                 (progn
                   (prompt "\n  No width on record (legacy anchor) -- re-picking.")
                   (setq pts (pfs:pick-extents))))))
           (setq datum (cdr (assoc 'datum res)))   ; typed in the dialog
           (cond
             ((null pts) (prompt "\nEdit cancelled -- nothing written."))
             (T
              (command "_.UNDO" "_Begin")
              (setq *pfs-undo-open* T)
              (setq xf (pfs:build-xform res (car pts) (cadr pts) datum))
              (pfa:reanchor anchor xf)
              (pfa:meta-put anchor (cdr (assoc 'cl res))
                            (pf:checksum-file (cdr (assoc 'cl res))))
              (setq notes (pfs:bind-files anchor res))
              (pfa:status-put anchor 0 notes)     ; edits invalidate checks
              (command "_.UNDO" "_End")
              (setq *pfs-undo-open* nil)
              (prompt "\n  Updated in place (ledger preserved; status UNCHECKED).")
              (foreach r notes (prompt (strcat "\n  NOTE: " r))))))))))))


;;; ==========================================================================
;;; SECTION 4  --  Registry display + the on-the-fly entry point
;;; ==========================================================================

;; (pfs:reg-item r) -> one column-formatted registry row for the list "grids"
(defun pfs:reg-item (r)
  (strcat (pfset:pad (car r) 12)
          (pfset:pad (strcat "'" (cadr r) "'") 28)
          (if (eq (caddr r) 'PLACED) "[PLACED]" "[unplaced]")))

;; (pfs:choose-or-place) -> anchor | nil
;;   Registry pick for the label commands (pf_pick dialog): a PLACED profile
;;   returns its anchor; choosing an unplaced one IS consent to place it --
;;   no confirm (single-target path; All-mode batch skipping lives in the
;;   callers).
(defun pfs:choose-or-place ( / reg pick r)
  (setq reg (pfa:registry))
  (cond
    ((null reg)
     (prompt "\nNothing registered -- run PFSETUP.")
     nil)
    (T
     (setq pick (pfset:pick-index "Select the target profile:"
                                  (mapcar 'pfs:reg-item reg) nil))
     (cond
       ((null pick) nil)
       (T
        (setq r (nth pick reg))
        (if (eq (caddr r) 'PLACED)
          (nth 3 r)
          (pfs:place-one (nth 4 r))))))))


;;; ==========================================================================
;;; SECTION 5  --  The registry manager dialog + C:PFSETUP
;;; ==========================================================================
;;; The dialog closes for any verb that needs the drawing (placement picks),
;;; then the command loop reopens it -- the standard DCL round-trip.

;; (pfs:rd-sel) -> selected 0-based index | nil
(defun pfs:rd-sel ()
  (if (/= (get_tile "reg_list") "") (atoi (get_tile "reg_list"))))

;; Button handlers validate IN the dialog (errtile) before closing.
;; r-reg / r-idx live in pfs:registry-dialog, reached by dynamic scope.
(defun pfs:rd-place ( / i)
  (setq i (pfs:rd-sel))
  (cond
    ((null i) (set_tile "error" "Select a profile first."))
    ((eq (caddr (nth i r-reg)) 'PLACED)
     (set_tile "error" "Already placed -- use Edit."))
    (T (setq r-idx i) (done_dialog 2))))

(defun pfs:rd-edit ( / i)
  (setq i (pfs:rd-sel))
  (cond
    ((null i) (set_tile "error" "Select a profile first."))
    ((not (eq (caddr (nth i r-reg)) 'PLACED))
     (set_tile "error" "Not placed yet -- use Place."))
    (T (setq r-idx i) (done_dialog 4))))

(defun pfs:rd-all ()
  (if (vl-member-if '(lambda (r) (eq (caddr r) 'STUB)) r-reg)
    (done_dialog 3)
    (set_tile "error" "Nothing unplaced.")))

;; Double-click is the smart verb: place an unplaced row, edit a placed one.
(defun pfs:rd-dbl ( / i)
  (if (setq i (pfs:rd-sel))
    (progn
      (setq r-idx i)
      (done_dialog (if (eq (caddr (nth i r-reg)) 'PLACED) 4 2)))))

;; (pfs:registry-dialog r-reg) -> (verb . idx) | nil (Close)
;;   verbs: 'place 'place-all 'edit 'new 'refresh; idx 0-based (or nil).
(defun pfs:registry-dialog (r-reg / dcl_id r-idx code r)
  (setq dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfsetup_registry" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the registry dialog.") nil)
      (progn
        (start_list "reg_list")
        (foreach r r-reg (add_list (pfs:reg-item r)))
        (end_list)
        (if r-reg
          (set_tile "reg_list" "0")
          (progn (mode_tile "reg_place" 1)
                 (mode_tile "reg_all"   1)
                 (mode_tile "reg_edit"  1)))
        (action_tile "reg_list"  "(if (= $reason 4) (pfs:rd-dbl))")
        (action_tile "reg_place" "(pfs:rd-place)")
        (action_tile "reg_all"   "(pfs:rd-all)")
        (action_tile "reg_edit"  "(pfs:rd-edit)")
        (action_tile "reg_new"   "(done_dialog 5)")
        (action_tile "reg_scan"  "(done_dialog 6)")
        (action_tile "accept"    "(done_dialog 0)")
        (action_tile "help"
          (strcat "(pfset:help \"The registry is every profile this drawing "
                  "knows: AUTO-named stubs and placed anchors.\\n\\n"
                  "Place    anchor an unplaced profile's grid (dialog, two "
                  "corner picks).\\nPlace All  every unplaced profile in "
                  "turn.\\nEdit     rebind files / scales / datum on a "
                  "placed grid.\\nNew      a profile the sheet scan "
                  "missed.\\nRefresh  re-scan the sheet's PF-NAME text.\")"))
        (setq code (start_dialog))
        (unload_dialog dcl_id)
        (cond
          ((= code 2) (cons 'place r-idx))
          ((= code 3) (cons 'place-all nil))
          ((= code 4) (cons 'edit r-idx))
          ((= code 5) (cons 'new nil))
          ((= code 6) (cons 'refresh nil))
          (T nil))))))

(defun c:PFSETUP ( / dir reg going act r)
  (setq *pfs-prev-error* *error*
        *error*          pfs:*error*
        *pfs-undo-open*  nil)
  (pf:load-apis)
  ;; project data root (NOD; set once)
  (setq dir (pfset:root-get))
  (if (null dir)
    (progn
      (setq dir (pfset:browse "Select ANY .cl in the Project Data Folder"
                              '*pfset-dir-cl* "cl"))
      (if dir
        (progn
          (setq dir (strcat (vl-filename-directory dir) "\\"))
          (pfset:root-set dir)
          (prompt (strcat "\nProject data root set: " dir))))))
  (if (null dir)
    (prompt "\nNo project data folder -- cancelled.")
    (progn
      ;; AUTO fires when the drawing has no registry
      (if (null (pfa:registry)) (pfs:auto dir))
      (setq going T)
      (while going
        (setq reg (pfa:registry)
              act (pfs:registry-dialog reg))
        (cond
          ((null act) (setq going nil))
          ((eq (car act) 'refresh) (pfs:auto dir))
          ((eq (car act) 'new)     (pfs:place-one nil))
          ((eq (car act) 'place-all)
           (foreach r reg
             (if (eq (caddr r) 'STUB)
               (progn
                 (prompt (strcat "\n== " (car r) " '" (cadr r) "' =="))
                 (pfs:place-one (nth 4 r))))))
          ((eq (car act) 'place)
           (pfs:place-one (nth 4 (nth (cdr act) reg))))
          ((eq (car act) 'edit)
           (pfs:edit-one (nth 3 (nth (cdr act) reg))))))))
  (setq *error* *pfs-prev-error*)
  (princ))


(princ "\npfsetup.lsp loaded.  Command: PFSETUP (AUTO names, USER places).")
(princ)
;;; ==========================================================================
;;; end of pfsetup.lsp
;;; ==========================================================================
