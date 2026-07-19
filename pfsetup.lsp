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
;;;     dialog (identity override, scales, file bindings) ->
;;;     pick LOWER-LEFT (datum line = transform origin) ->
;;;     pick TOP-RIGHT (EXTENTS ONLY -- no scale is measured from either
;;;     pick; stored RELATIVE as the insert's X/Y scale) ->
;;;     type DATUM elevation (the one value a pick can't give).
;;;   Vertical scale = declared H/V.  Per-station top = the probe.
;;;   ONE datum per grid, anchored at the lower-left; steps in the run do
;;;   not matter.  (Settled.  Do not revisit.)
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
  (if *pfs-undo-open*
    (progn (command-s "_.UNDO" "_End") (setq *pfs-undo-open* nil)))
  (setq *error* *pfs-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 1  --  Dialog wiring  (pfsetup_main)
;;; ==========================================================================
;;; d-cl / d-pro / d-tin / d-res live in pfs:show-dialog and are reached by
;;; the action callbacks via dynamic scope while start_dialog runs.

(defun pfs:file-display (f)
  (strcat (vl-filename-base f) (vl-filename-extension f)))

(defun pfs:pro-display (f / pr)
  (setq pr (pf:parse-pro-name f))
  (strcat (pfs:file-display f)
          (if (cdr pr) (strcat "   [" (cdr pr) "]") "   [NO ROLE -- ERROR]")))

(defun pfs:tin-display (f)
  (strcat (pfs:file-display f)
          (if (eq (pf:tin-role f) 'DESIGN) "   [PROPOSED]" "   [EXISTING]")))

(defun pfs:fill-list (key items disp / it)
  (start_list key)
  (foreach it items (add_list (apply disp (list it))))
  (end_list)
  (princ))

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

(defun pfs:on-pro-add ( / f)
  (if (setq f (pfset:browse "Select Profile (.PRO) File -- pick _INV and _TOP"
                            '*pfset-dir-pro* "pro"))
    (if (member (strcase f) (mapcar 'strcase d-pro))
      (set_tile "error" "That .pro is already in the list.")
      (progn
        (setq d-pro (append d-pro (list f)))
        (pfs:fill-list "s_pro" d-pro 'pfs:pro-display)
        (set_tile "error" "")))))

(defun pfs:on-pro-del ( / sel)
  (if (and (setq sel (get_tile "s_pro")) (/= sel ""))
    (progn
      (setq d-pro (pf:remove-nth (atoi sel) d-pro))
      (pfs:fill-list "s_pro" d-pro 'pfs:pro-display))))

(defun pfs:on-tin-add ( / f)
  (if (setq f (pfset:browse "Select Surface (.TIN) File -- existing + DESIGN_*"
                            '*pfset-dir-tin* "tin"))
    (if (member (strcase f) (mapcar 'strcase d-tin))
      (set_tile "error" "That surface is already in the list.")
      (progn
        (setq d-tin (append d-tin (list f)))
        (pfs:fill-list "s_tin" d-tin 'pfs:tin-display)
        (set_tile "error" "")))))

(defun pfs:on-tin-del ( / sel)
  (if (and (setq sel (get_tile "s_tin")) (/= sel ""))
    (progn
      (setq d-tin (pf:remove-nth (atoi sel) d-tin))
      (pfs:fill-list "s_tin" d-tin 'pfs:tin-display))))

;; OK: validate everything the dialog CAN validate.  Name is the identity
;; key -- picked files VALIDATE against it, they never resolve it.
(defun pfs:ok ( / nm hs vs ty msgs roles r inv top cnt mlist mat)
  (setq nm   (strcase (pf:trim (get_tile "s_name")))
        hs   (distof (get_tile "s_hs"))
        vs   (distof (get_tile "s_vs"))
        ty   (nth (atoi (get_tile "s_type")) *pf-types*)
        msgs nil)
  (cond
    ((or (null d-cl) (= d-cl ""))
     (setq msgs "Select the .cl file -- station comes from it."))
    ((= nm "") (setq msgs "Line name is empty."))
    ((not (and hs vs (> hs 0.0) (> vs 0.0)))
     (setq msgs "Plot scales must be positive numbers (e.g. 20 and 2.)"))
    (T
     ;; ---- .pro pair: both roles present, both names matching Name --------
     (cond
       ((= (length d-pro) 0))                       ; allowed; noted at write
       ((/= (length d-pro) 2)
        (setq msgs "Exactly TWO .pro files (one _INV, one _TOP) -- or none."))
       (T
        (setq roles (mapcar 'pf:parse-pro-name d-pro) inv nil top nil)
        (foreach r roles
          (cond
            ((null (cdr r))
             (setq msgs (strcat "'" (car r)
                                "' has no _INV / _TOP role suffix.")))
            ((= (cdr r) "INV") (setq inv r))
            ((= (cdr r) "TOP") (setq top r))))
        (if (null msgs)
          (cond
            ((or (null inv) (null top))
             (setq msgs "Need one _INV and one _TOP .pro (not two of a kind)."))
            ((/= (car inv) nm)
             (setq msgs (strcat "INV .pro is for '" (car inv)
                                "' but Name says '" nm "'.")))
            ((/= (car top) nm)
             (setq msgs (strcat "TOP .pro is for '" (car top)
                                "' but Name says '" nm "'.")))))))
     ;; ---- .tin pair: exactly one DESIGN_* (the inverse rule, guarded) ----
     (if (null msgs)
       (cond
         ((= (length d-tin) 0))                     ; allowed; noted at write
         ((/= (length d-tin) 2)
          (setq msgs "Exactly TWO surfaces (existing + DESIGN_*) -- or none."))
         (T
          (setq cnt 0)
          (foreach r d-tin
            (if (eq (pf:tin-role r) 'DESIGN) (setq cnt (1+ cnt))))
          (if (/= cnt 1)
            (setq msgs "Exactly ONE surface must be DESIGN_* (proposed).")))))))
  (if msgs
    (set_tile "error" msgs)
    (progn
      (setq mlist (pfs:mat-list ty)
            mat   (if mlist (nth (atoi (get_tile "s_mat")) mlist) ""))
      (setq d-res (list (cons 'type ty) (cons 'name nm)
                        (cons 'hs hs) (cons 'vs vs)
                        (cons 'cl d-cl)
                        (cons 'pro d-pro) (cons 'tin d-tin)
                        (cons 'material mat)))
      (done_dialog 1))))

;; (pfs:show-dialog init) -> result alist | nil
;;   init: same keys as the result, prefills the tiles (nil = blank form).
(defun pfs:show-dialog (init / dcl_id d-cl d-pro d-tin d-res s idx result
                        ity imat)
  (setq dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfsetup_main" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the PFSETUP dialog.") nil)
      (progn
        (setq s     (pfset:settings)
              d-cl  (cdr (assoc 'cl init))
              d-pro (if (assoc 'pro init) (cdr (assoc 'pro init)) '())
              d-tin (if (assoc 'tin init) (cdr (assoc 'tin init)) '())
              d-res nil)
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
        (if d-cl (set_tile "s_cl" (pfs:file-display d-cl)))
        (pfs:fill-list "s_pro" d-pro 'pfs:pro-display)
        (pfs:fill-list "s_tin" d-tin 'pfs:tin-display)
        (action_tile "s_type"    "(pfs:on-type-change)")
        (action_tile "s_cl_pick" "(pfs:on-cl-pick)")
        (action_tile "s_pro_add" "(pfs:on-pro-add)")
        (action_tile "s_pro_del" "(pfs:on-pro-del)")
        (action_tile "s_tin_add" "(pfs:on-tin-add)")
        (action_tile "s_tin_del" "(pfs:on-tin-del)")
        (action_tile "accept"    "(pfs:ok)")
        (action_tile "cancel"    "(done_dialog 0)")
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

;; (pfs:ask-datum current) -> datum | nil
;;   Default: stored value (edit) or the session's last-typed.
(defun pfs:ask-datum (current / p d)
  (setq p (cond (current (rtos current 2 2))
                (*pfs-datum-last* (rtos *pfs-datum-last* 2 2))
                (T nil)))
  (setq d (getreal (strcat "\nDatum elevation"
                           (if p (strcat " <" p ">") "") ": ")))
  (cond
    (d (setq *pfs-datum-last* d) d)
    (p (distof p 2))
    (T nil)))

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
       ((null (setq datum (pfs:ask-datum nil)))
        (prompt "\nNo datum -- cancelled.")
        nil)
       (T
        (setq ll (car pts) tr (cadr pts))
        (command "_.UNDO" "_Begin")
        (setq *pfs-undo-open* T)
        (setq xf     (pfs:build-xform res ll tr datum)
              anchor (pfa:write-anchor nm ty xf cl))
        (pfa:meta-put anchor cl nil (pf:checksum-file cl))
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
(defun pfs:anchor-init (anchor / at meta files hp vp init v)
  (setq at    (pfa:read-attribs anchor)
        meta  (pfa:meta-get anchor)
        files (pfa:files-get anchor)
        hp    (distof (pfa:att "HPLOT" at) 2)
        vp    (distof (pfa:att "VPLOT" at) 2)
        init  (list (cons 'type (pfa:att "UTIL" at))
                    (cons 'name (pfa:att "LINE" at))))
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
           ;; extents: re-pick, or rebuild from the stored relative geometry
           (initget "Yes No")
           (if (= (getkword "\nRe-pick the grid extents? [Yes/No] <No>: ")
                  "Yes")
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
           (cond
             ((null pts) (prompt "\nEdit cancelled -- nothing written."))
             ((null (setq datum (pfs:ask-datum
                                  (distof (pfa:att "DATUM" at) 2))))
              (prompt "\nNo datum -- cancelled."))
             (T
              (command "_.UNDO" "_Begin")
              (setq *pfs-undo-open* T)
              (setq xf (pfs:build-xform res (car pts) (cadr pts) datum))
              (pfa:reanchor anchor xf)
              (pfa:meta-put anchor (cdr (assoc 'cl res)) nil
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

(defun pfs:print-registry (reg / i r)
  (prompt "\nRegistered profiles:")
  (setq i 0)
  (foreach r reg
    (setq i (1+ i))
    (prompt (strcat "\n  " (itoa i) ".  " (car r) " '" (cadr r) "'   "
                    (if (eq (caddr r) 'PLACED) "[PLACED]" "[unplaced]"))))
  (princ))

;; (pfs:choose-or-place) -> anchor | nil
;;   Registry pick for the label commands: a PLACED profile returns its
;;   anchor; an unplaced one offers on-the-fly placement (single-target
;;   path -- All-mode batch skipping lives in the callers).
(defun pfs:choose-or-place ( / reg pick r)
  (setq reg (pfa:registry))
  (cond
    ((null reg)
     (prompt "\nNothing registered -- run PFSETUP.")
     nil)
    (T
     (pfs:print-registry reg)
     (initget 6)
     (setq pick (getint (strcat "\nProfile <1-" (itoa (length reg)) ">: ")))
     (cond
       ((not (and (numberp pick) (>= pick 1) (<= pick (length reg)))) nil)
       (T
        (setq r (nth (1- pick) reg))
        (if (eq (caddr r) 'PLACED)
          (nth 3 r)
          (progn
            (initget "Yes No")
            (if (/= (getkword (strcat "\n" (car r) " '" (cadr r)
                                      "' is unplaced -- place it now? "
                                      "[Yes/No] <Yes>: "))
                    "No")
              (pfs:place-one (nth 4 r))
              nil))))))))


;;; ==========================================================================
;;; SECTION 5  --  C:PFSETUP
;;; ==========================================================================

(defun c:PFSETUP ( / dir reg going pick r e)
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
        (setq reg (pfa:registry))
        (cond
          ((null reg)
           (prompt "\nNothing registered.")
           (initget "Refresh New")
           (setq pick (getkword "\n[Refresh/New] or Enter to quit: "))
           (cond
             ((= pick "Refresh") (pfs:auto dir))
             ((= pick "New") (pfs:place-one nil))
             (T (setq going nil))))
          (T
           (pfs:print-registry reg)
           (initget 6 "All Edit Refresh New")
           (setq pick
             (getint (strcat "\nPlace grid [All-unplaced/Edit/Refresh/New] "
                             "<1-" (itoa (length reg))
                             ">, Enter to finish: ")))
           (cond
             ((null pick) (setq going nil))
             ((= pick "Refresh") (pfs:auto dir))
             ((= pick "New") (pfs:place-one nil))
             ((= pick "All")
              (foreach r reg
                (if (eq (caddr r) 'STUB)
                  (progn
                    (prompt (strcat "\n== " (car r) " '" (cadr r) "' =="))
                    (pfs:place-one (nth 4 r))))))
             ((= pick "Edit")
              (setq e (pfa:pick-anchor
                        "\nSelect anchor to edit (Enter to list): "))
              (if (null e) (setq e (pfa:choose-anchor)))
              (if e (pfs:edit-one e)))
             ((and (numberp pick) (>= pick 1) (<= pick (length reg)))
              (setq r (nth (1- pick) reg))
              (if (eq (caddr r) 'PLACED)
                (pfs:edit-one (nth 3 r))
                (pfs:place-one (nth 4 r))))
             (T (prompt "\nInvalid pick."))))))))
  (setq *error* *pfs-prev-error*)
  (princ))


(princ "\npfsetup.lsp loaded.  Command: PFSETUP (AUTO names, USER places).")
(princ)
;;; ==========================================================================
;;; end of pfsetup.lsp
;;; ==========================================================================
