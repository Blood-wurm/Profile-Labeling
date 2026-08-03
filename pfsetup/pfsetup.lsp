;;; ==========================================================================
;;; pfsetup.lsp  --  C:PFSETUP : two-tier registration (AUTO names, USER
;;;                  places).  Dialogs: pfsetup_main / pfsetup_registry.
;;; Load position 6 of 10: after pfsettings, before pflabel.
;;; Model, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfs-undo-open*))  (setq *pfs-undo-open* nil))
(if (not (boundp '*pfs-datum-last*)) (setq *pfs-datum-last* nil))
(if (not (boundp '*pfs-mat-last*))   (setq *pfs-mat-last* '())) ; (TYPE . material)
;; *pfs-preset-res* -- a placement record supplied by a caller INSTEAD of the
;; modal (the palette's Edit/New tabs).  nil on every command-line run, and
;; READ AND CLEARED IN ONE setq at the top of pfs:place-one / pfs:edit-one:
;; a ticket that survived a failed run would silently place the NEXT
;; command-line record with someone else's input.  See PALETTE-LAYOUT.md §10.
(if (not (boundp '*pfs-preset-res*)) (setq *pfs-preset-res* nil))
;; Error handling lives in pf:run-command (pfanchor); PFSETUP has no pass
;; ledger to flush, so its hook is nil.  An Esc inside a group (AUTO scan or
;; a placement -- including one nested under a label command) is closed by
;; pf:run-error via the *pfs-undo-open* flag.


;;; ==========================================================================
;;; SECTION 1  --  The placement record  (seeds / validate / remember /
;;;                prompts) + the pfsetup_main dialog wiring
;;; ==========================================================================
;;; d-cl / d-pro / d-tin / d-res live in pfs:show-dialog and are reached by the
;;; action callbacks via dynamic scope while start_dialog runs.
;;; The record (the `res` alist) is the unit every writer below consumes, and the
;;; modal is only ONE way to build one.  The seed chain, the refusal cascade and
;;; the session memory live out here so a record built anywhere else gets the
;;; same treatment.  pfs:show-dialog fills a record; it decides nothing.

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
  ;; Route to company standard folder before opening dialog
  (setq *pfset-dir-cl* (pfset:get-company-dir "cl"))
  
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
  ;; Route to company standard folder before opening dialog
  (setq *pfset-dir-pro* (pfset:get-company-dir "pro"))
  
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
  ;; Route to company standard folder before opening dialog
  (setq *pfset-dir-tin* (pfset:get-company-dir "tin"))
  
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
;; (pfs:seed-hs init) -> scale string   |   (pfs:seed-vs init) -> scale string
;;   Stored value (Edit) wins; else the NATIVE sv:sm / sv:vs; else the
;;   last-used setting.  ONE chain, read by the dialog tiles AND by the
;;   command-line prompts, so the value Enter accepts is the value the modal
;;   would have shown.
(defun pfs:seed-hs (init)
  (cond ((assoc 'hs init) (rtos (cdr (assoc 'hs init)) 2 2))
        ((pfset:native-scale 'sv:sm))
        (T (cdr (assoc "hscale" (pfset:settings))))))

(defun pfs:seed-vs (init)
  (cond ((assoc 'vs init) (rtos (cdr (assoc 'vs init)) 2 2))
        ((pfset:native-scale 'sv:vs))
        (T (cdr (assoc "vscale" (pfset:settings))))))

;; (pfs:seed-datum init) -> elevation string | nil
;;   Stored value (Edit), else the session's last-typed.  nil = no seed, and
;;   the caller must require a value.
(defun pfs:seed-datum (init)
  (cond ((cdr (assoc 'datum init)) (rtos (cdr (assoc 'datum init)) 2 2))
        (*pfs-datum-last* (rtos *pfs-datum-last* 2 2))))

;; (pfs:validate res) -> refusal message | nil
;;   THE refusal cascade for a placement record, in the order the modal has
;;   always reported them.  Both input sources land here -- so a record built
;;   without the dialog cannot skip a check the dialog would have made.
;;
;;   The two NUMERIC clauses are checked only when their key is PRESENT.  The
;;   dialog always supplies hs / vs / datum (parsed from tiles, possibly nil,
;;   which is exactly the failure these clauses catch); a caller that leaves
;;   them out is declaring they will be prompted for later, where initget
;;   enforces the same rule at the point of entry.
;;
;;   Roles come from the FILE NAMES, never from list position: an init-shaped
;;   'pro list holds whichever of the pair exists, in either slot.
(defun pfs:validate (res / nm cl inv top tine tind r)
  (setq nm (cdr (assoc 'name res))
        cl (cdr (assoc 'cl res)))
  (foreach r (cdr (assoc 'pro res))
    (if (= (cdr (pf:parse-pro-name r)) "INV") (setq inv r) (setq top r)))
  (foreach r (cdr (assoc 'tin res))
    (if (eq (pf:tin-role r) 'DESIGN) (setq tind r) (setq tine r)))
  (cond
    ((or (null cl) (= cl ""))
     "Select the .cl file -- station comes from it.")
    ((or (null nm) (= nm "")) "Line name is empty.")
    ((and (assoc 'hs res)
          (not (and (cdr (assoc 'hs res)) (cdr (assoc 'vs res))
                    (> (cdr (assoc 'hs res)) 0.0)
                    (> (cdr (assoc 'vs res)) 0.0))))
     "Plot scales must be positive numbers (e.g. 20 and 2).")
    ((and (assoc 'datum res) (null (cdr (assoc 'datum res))))
     "Type the datum elevation (the lower-left grid corner).")
    ;; ---- .pro pair: both or neither, both names matching Name ------------
    ((and inv (null top))
     "Crown _TOP .pro missing -- bind both .pro files or neither.")
    ((and top (null inv))
     "Invert _INV .pro missing -- bind both .pro files or neither.")
    ((and inv (/= (car (pf:parse-pro-name inv)) nm))
     (strcat "INV .pro is for '" (car (pf:parse-pro-name inv))
             "' but Name says '" nm "'."))
    ((and top (/= (car (pf:parse-pro-name top)) nm))
     (strcat "TOP .pro is for '" (car (pf:parse-pro-name top))
             "' but Name says '" nm "'."))
    ;; ---- .tin pair: both or neither (roles guaranteed by the slots) ------
    ((and tine (null tind))
     "DESIGN_* surface missing -- bind both surfaces or neither.")
    ((and tind (null tine))
     "Existing surface missing -- bind both surfaces or neither.")))

(defun pfs:ok ( / ty mlist mat res msgs)
  ;; distof MODE 2 pinned: without it the parse follows the drawing's LUNITS,
  ;; and an Architectural/Fractional drawing rejects plain decimals.  Every
  ;; other numeric read in the suite pins mode 2 -- these three now match.
  (setq ty    (nth (atoi (get_tile "s_type")) *pf-types*)
        mlist (pfs:mat-list ty)
        mat   (if mlist (nth (atoi (get_tile "s_mat")) mlist) "")
        res   (list (cons 'type ty)
                    (cons 'name (strcase (pf:trim (get_tile "s_name"))))
                    (cons 'hs (distof (get_tile "s_hs") 2))
                    (cons 'vs (distof (get_tile "s_vs") 2))
                    (cons 'cl d-cl)
                    ;; compacted: validation is what guarantees both-or-neither,
                    ;; so a half-filled pair must survive long enough to be
                    ;; REPORTED rather than being dropped on the way in
                    (cons 'pro (vl-remove nil (list d-inv d-top)))
                    (cons 'tin (vl-remove nil (list d-tine d-tind)))
                    (cons 'material mat)
                    (cons 'datum (distof (get_tile "s_datum") 2))
                    (cons 'repick (= (get_tile "s_repick") "1")))
        msgs  (pfs:validate res))
  (if msgs
    (set_tile "error" msgs)
    (progn (setq d-res res) (done_dialog 1))))

;; (pfs:show-dialog init) -> result alist | nil
;;   init: same keys as the result, prefills the tiles (nil = blank form).
;;   'edit enables the re-pick toggle; 'datum prefills (else session-last).
(defun pfs:show-dialog (init / dcl_id d-cl d-inv d-top d-tine d-tind d-res
                        idx result ity imat f v)
  (setq dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfsetup_main" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the PFSETUP dialog.") nil)
      (progn
        (setq d-cl  (cdr (assoc 'cl init))
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
        ;; scale seed: pfs:seed-hs/vs -- the same chain the prompts use.
        ;; The field stays editable either way.
        (set_tile "s_hs" (pfs:seed-hs init))
        (set_tile "s_vs" (pfs:seed-vs init))
        (if d-cl   (set_tile "s_cl"   (pfs:file-display d-cl)))
        (if d-inv  (set_tile "s_inv"  (pfs:file-display d-inv)))
        (if d-top  (set_tile "s_top"  (pfs:file-display d-top)))
        (if d-tine (set_tile "s_tine" (pfs:file-display d-tine)))
        (if d-tind (set_tile "s_tind" (pfs:file-display d-tind)))
        ;; datum: stored value (edit) or the session's last-typed
        (if (setq v (pfs:seed-datum init)) (set_tile "s_datum" v))
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
          ;; The record, and nothing else.  The session memory that used to be
          ;; updated here now lives in pfs:remember, which BOTH input sources
          ;; reach -- see the note there.
          ((= result 1) d-res)
          (T nil))))))


;; (pfs:remember res) -> nil
;;   The three session-memory effects of a CONFIRMED record: the scales become
;;   the next placement's defaults, the material is remembered per type, and the
;;   datum seeds the next prompt.
;;   Out here rather than inside the modal, because a record built anywhere else
;;   would stop updating them SILENTLY, freezing every default at the last time
;;   someone used the dialog.  Called from pfs:complete-res, at the same point in
;;   the flow the dialog used to do it: input confirmed, before the extent picks.
(defun pfs:remember (res / ty mat)
  (setq ty  (strcase (cdr (assoc 'type res)))
        mat (cdr (assoc 'material res)))
  (pfset:put-setting "hscale" (rtos (cdr (assoc 'hs res)) 2 2))
  (pfset:put-setting "vscale" (rtos (cdr (assoc 'vs res)) 2 2))
  (setq *pfs-datum-last* (cdr (assoc 'datum res)))
  (if (and mat (/= mat ""))
    (setq *pfs-mat-last*
          (cons (cons ty mat)
                (vl-remove-if '(lambda (p) (= (car p) ty)) *pfs-mat-last*))))
  (pfset:save-auto)
  nil)

;; (pfs:ask-number label default positive-p) -> real
;;   Enter takes the default; with no default a value is REQUIRED.  Esc is not
;;   handled here -- it unwinds to pf:run-error like every other command-line
;;   step, and nothing is written until after the picks that follow.
(defun pfs:ask-number (label default positive-p / v)
  (initget (+ (if default 0 1) (if positive-p 6 0)))
  (setq v (getreal (strcat label
                           (if default (strcat " <" (rtos default 2 2) ">") "")
                           ": ")))
  (if v v default))

;; (pfs:ask-scales res init) -> res carrying 'hs and 'vs
;;   getreal, not getdist: a plot scale is a RATIO, so it is unit-free and the
;;   Architectural/Fractional parse hazard that pins distof mode 2 on the tiles
;;   cannot arise.  initget 6 enforces the positive-number refusal at the point
;;   of entry, which is why pfs:validate skips it for a prompted record.
(defun pfs:ask-scales (res init / v hs vs)
  (setq v  (pfs:seed-hs init)
        hs (pfs:ask-number "\nHorizontal plot scale" (if v (distof v 2)) T)
        v  (pfs:seed-vs init)
        vs (pfs:ask-number "\nVertical plot scale"   (if v (distof v 2)) T))
  (cons (cons 'hs hs) (cons (cons 'vs vs) res)))

;; (pfs:ask-datum res init) -> res carrying 'datum
;;   RESTORED 2026-07-28.  It was deleted when the datum moved into the modal
;;   (the tombstone stood in SECTION 3).  The palette carries no numeric entry
;;   by decision, so the typed datum comes back to the command line -- one
;;   prompt immediately before the two extent picks, which is where the user is
;;   already looking at the grid.  Zero and negative are legal elevations, so
;;   only a null is refused.
(defun pfs:ask-datum (res init / v)
  (setq v (pfs:seed-datum init))
  (cons (cons 'datum
              (pfs:ask-number "\nDatum elevation (lower-left grid corner)"
                              (if v (distof v 2)) nil))
        res))

;; (pfs:complete-res res init) -> res | nil
;;   THE finalize step both input sources land on.  Prompt for whatever the
;;   record is missing -- a preset carries no numbers -- then remember what was
;;   confirmed.  Runs BEFORE the extent picks, so the modal's timing is
;;   unchanged: a record accepted and then abandoned at the picks still leaves
;;   its scales behind as the next default, exactly as it always has.
(defun pfs:complete-res (res init)
  (cond
    ((null res) nil)
    (T
     (if (null (assoc 'hs res))    (setq res (pfs:ask-scales res init)))
     (if (null (assoc 'datum res)) (setq res (pfs:ask-datum res init)))
     (pfs:remember res)
     res)))


;;; ==========================================================================
;;; SECTION 2  --  AUTO registration  (identity, sheet-wide, never guesses)
;;; ==========================================================================

;; (pfs:scan-sheet-names) -> list of (type . name), deduped
;;   PF-NAME text only -- names, not geometry.  A text that names a utility
;;   TYPE but whose line name cannot be parsed (no 'NAME' in straight quotes
;;   -- backticks or curly quotes are the known offenders) is REPORTED, never
;;   silently dropped: the naming convention is load-bearing, so the fix is
;;   on the sheet, and the drafter has to be told which text to fix.
(defun pfs:scan-sheet-names ( / ss i ed s ty nm out key seen)
  (setq ss (ssget "_X" (list '(0 . "TEXT,MTEXT") (cons 8 *pfg-name-layer*)
                             '(410 . "Model")))     ; model space only
        out '() seen '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq ed (entget (ssname ss i))
            s  (cdr (assoc 1 ed))
            ty (if s (pf:sheet-type s))
            nm (if ty (pf:parse-sheet-name s ty)))
      (cond
        ((and ty nm)
         (setq key (strcat ty "|" nm))
         (if (not (member key seen))
           (setq seen (cons key seen)
                 out  (cons (cons ty nm) out))))
        (ty                                  ; type named, name unreadable
         (prompt (strcat "\n  SKIPPED, NOT REGISTERED: \"" s
                         "\" -- line name not readable; the convention "
                         "expects 'NAME' in straight quotes."))))
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

;; (pfs:nz s) -> s | nil     ("" and nil both read as UNBOUND)
;;   The records store an absent binding as "", not nil (see pfa:files-put /
;;   pfa:stub-put).  Every rebind decision below turns on "is this slot
;;   empty", so both spellings have to collapse to one before testing.
(defun pfs:nz (s) (if (and s (/= s "")) s))

;;; ---- late .pro binding (Refresh re-checks an already-registered line) ----
;;; A grid is routinely registered BEFORE its profiles exist -- the .cl lands
;;; first and the _INV/_TOP pair is cut later.  Without this that pair stays
;;; invisible forever, because AUTO's idempotence meant "already known = skip
;;; entirely" and Refresh re-scanned only for NEW names.
;;; The rule is FILL-EMPTY-ONLY, in both stores: a bound slot is never
;;; overwritten and never re-pointed, even if a different file now matches the
;;; naming convention.  Refresh therefore cannot silently undo a deliberate
;;; binding made in the setup/Edit dialog -- rebinding an occupied slot stays
;;; that dialog's job.  Filling an empty one is what first registration would
;;; have done, so it guesses nothing new.

;; (pfs:rebind-stub ty nm stub proDir) -> 1 if a slot was filled, else 0
(defun pfs:rebind-stub (ty nm stub proDir / inv top ninv ntop)
  (setq inv  (pfs:nz (cdr (assoc 4 stub)))
        top  (pfs:nz (cdr (assoc 5 stub)))
        ninv nil ntop nil)
  (if (and proDir (null inv)) (setq ninv (pfs:pro-lookup proDir ty nm "INV")))
  (if (and proDir (null top)) (setq ntop (pfs:pro-lookup proDir ty nm "TOP")))
  (cond
    ((or ninv ntop)
     (pfa:stub-put ty nm (cdr (assoc 1 stub))
                   (if inv inv ninv) (if top top ntop))
     (pfs:report-fill ty nm ninv ntop "registered")
     1)
    (T 0)))

;; (pfs:rebind-anchor ty nm anchor proDir) -> 1 if a slot was filled, else 0
;;   Read-modify-write: FILES also carries the TIN pair, the material and the
;;   per-.pro checksums, so the untouched codes are read back and re-written
;;   verbatim.  A newly bound .pro gets its checksum computed now, which is
;;   what the PFINVERT drift check reads later.
(defun pfs:rebind-anchor (ty nm anchor proDir / files inv top ninv ntop)
  (setq files (pfa:files-get anchor)
        inv   (pfs:nz (cdr (assoc 1 files)))
        top   (pfs:nz (cdr (assoc 2 files)))
        ninv  nil ntop nil)
  (if (and proDir (null inv)) (setq ninv (pfs:pro-lookup proDir ty nm "INV")))
  (if (and proDir (null top)) (setq ntop (pfs:pro-lookup proDir ty nm "TOP")))
  (cond
    ((or ninv ntop)
     (pfa:files-put anchor
                    (if inv inv ninv)
                    (if inv (pfs:nz (cdr (assoc 300 files)))
                            (pf:checksum-file ninv))
                    (if top top ntop)
                    (if top (pfs:nz (cdr (assoc 301 files)))
                            (pf:checksum-file ntop))
                    (pfs:nz (cdr (assoc 3 files)))
                    (pfs:nz (cdr (assoc 4 files)))
                    (pfs:nz (cdr (assoc 5 files))))
     (pfs:report-fill ty nm ninv ntop "anchored")
     1)
    (T 0)))

;; (pfs:report-fill ty nm ninv ntop state) -> nil   (loud, like every AUTO line)
;;   Reports only the slots this pass FILLED.  A role that is absent here was
;;   either already bound or still has no file -- either way this pass did not
;;   touch it, so it is not named.
(defun pfs:report-fill (ty nm ninv ntop state)
  (prompt (strcat "\n  Bound " ty " '" nm "' (" state ")"
                  (if ninv (strcat " + INV " (pfs:file-display ninv)) "")
                  (if ntop (strcat " + TOP " (pfs:file-display ntop)) ""))))

;; (pfs:auto) -> nil
;;   Names every profile the sheet declares; loud-skips both directions.
;;   Idempotent -- a anchored profile or an existing stub is never re-named,
;;   but both are re-checked for .pro files that appeared since (fill-empty
;;   only; see the rebind helpers above).
;;   ONE undo group wraps the whole scan's writes (stubs + GEOM + TWIN
;;   records): a U after AUTO peels the entire registration, and an Esc
;;   mid-scan is closed by pf:run-error via the *pfs-undo-open* flag.
(defun pfs:auto ( / names pair ty nm m inv top new fill a st f base pos
                    clDir proDir)
  (prompt "\nAUTO registration: naming profiles sheet-wide...")

  ;; Fetch standard directories independently
  (setq clDir  (pfset:get-company-dir "cl")
        proDir (pfset:get-company-dir "pro")
        names  (pfs:scan-sheet-names)
        new    0
        fill   0)

  (if (null clDir)
    (prompt "\n  Cannot auto-register: Centerline directory not found.")
    (if (null names)
      (prompt (strcat "\n  No PF-NAME text found on layer " *pfg-name-layer* "."))
      (progn
        (pf:undo-begin '*pfs-undo-open*)
        (foreach pair names
          (setq ty (car pair) nm (cdr pair))
          (cond
            ;; anchored / already named -- never re-named, but a .pro pair that
            ;; landed after registration is picked up into the empty slots
            ((setq a (pfa:find-anchor nm ty))
             (setq fill (+ fill (pfs:rebind-anchor ty nm a proDir))))
            ((setq st (pfa:stub-get ty nm))
             (setq fill (+ fill (pfs:rebind-stub ty nm st proDir))))
            (T
             ;; Route centerline lookup to clDir
             (setq m (pfs:cl-lookup clDir ty nm))
             (cond
               ((null m)
                (prompt (strcat "\n  SKIPPED " ty " '" nm "' -- no "
                                ty "_" nm ".cl in the alignments folder.")))
               ((eq m 'AMBIG)
                (prompt (strcat "\n  SKIPPED " ty " '" nm
                                "' -- multiple .cl files match; never guessed.")))
               (T
                ;; Route profile lookups to proDir
                (setq inv (if proDir (pfs:pro-lookup proDir ty nm "INV") nil)
                      top (if proDir (pfs:pro-lookup proDir ty nm "TOP") nil))
                (pfa:stub-put ty nm m inv top)
                ;; file the .cl shape ONCE, now -- label commands read it later
                (pf:cl-geom m T)                    ; in-group: filing allowed
                (pfa:twin-put m (pf:cl-twin-handle m *pf-corridor*)) ; file the drawn twin once
                (setq new (1+ new))
                (prompt (strcat "\n  Named " ty " '" nm "'  ("
                                (pfs:file-display m)
                                (cond ((and inv top) " + INV/TOP pro")
                                      ((or inv top)  " + ONE pro only")
                                      (T             " -- no .pro pair"))
                                ")")))))))
        (pf:undo-end '*pfs-undo-open*)
        ;; reverse direction: a .cl with no grid name on the sheet (pure read)
        (foreach f (vl-directory-files clDir "*.cl" 1)
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
        (prompt (strcat "\n  " (itoa new) " profile(s) named, "
                        (itoa fill) " late .pro binding(s) added."))
        (if (and (null proDir) (> (length names) 0))
          (prompt (strcat "\n  NOTE: no Profile directory configured -- "
                          ".pro binding was not attempted."))))))
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

;; (pfs:ask-datum came BACK on 2026-07-28 and now lives in SECTION 1 beside
;;  the other record builders.  The modal still types its datum; a record that
;;  did not come from the modal is prompted for it here, just before the picks.)

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
;;   stub = (type name cl inv top) | nil (blank form).  Record -> prompts ->
;;   picks -> write, ONE undo group.  The record comes from the modal, or from
;;   *pfs-preset-res* when a caller supplied one.  Promotion deletes the stub
;;   under its ORIGINAL key, so an identity override re-keys cleanly.
(defun pfs:place-one (stub / init pro preset vmsg res ty nm cl rng pts ll tr
                       datum xf anchor notes idx r)
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
  ;; READ ONCE, CLEARED -- the pf:zoom-resolve pattern (pftools-lib.lsp).  One
  ;; setq, no window: a preset that outlived a failed run would place the NEXT
  ;; command-line record with stale input, silently.
  (setq preset           *pfs-preset-res*
        *pfs-preset-res* nil
        vmsg             (if preset (pfs:validate preset)))
  (cond
    (vmsg (prompt (strcat "\nREFUSED -- " vmsg)) nil)
    ((null (setq res (pfs:complete-res
                       (if preset preset (pfs:show-dialog init)) init)))
     (prompt "\nPlacement cancelled.") nil)
    (T
     (setq ty (cdr (assoc 'type res))
           nm (cdr (assoc 'name res))
           cl (cdr (assoc 'cl res)))
     (cond
       ((pfa:find-anchor nm ty)
        (prompt (strcat "\n" ty " '" nm "' is already ANCHORED -- use Edit."))
        nil)
       ((null (setq rng (pf:cl-range cl)))
        (prompt (strcat "\nREFUSED -- could not read a station range from "
                        (pfs:file-display cl)
                        ".  Regenerate the .cl from Carlson."))
        nil)
       ((null (setq pts (pfs:pick-extents))) nil)
       (T
        (setq datum (cdr (assoc 'datum res))    ; typed in the dialog, or asked
              ll    (car pts)
              tr    (cadr pts))
        (pf:undo-begin '*pfs-undo-open*)
        (setq xf     (pfs:build-xform res ll tr datum)
              anchor (pfa:write-anchor nm ty xf cl))
        ;; checksum! not checksum: this value is WRITTEN, and every later
        ;; staleness verdict is measured against it, so it must not inherit the
        ;; (path, mtime, size) shortcut whose wrong answer would be persisted.
        (pfa:meta-put anchor cl (pf:checksum-strict cl))
        ;; file the .cl shape now (no-op if AUTO already did) so a directly
        ;; anchored profile is cached too -- label commands never re-trace it
        (pf:cl-geom cl T)                          ; in-group: filing allowed
        (pfa:twin-put cl (pf:cl-twin-handle cl *pf-corridor*)) ; file the drawn twin
        (setq notes (pfs:bind-files anchor res))
        ;; a brand-new anchor has run no pass at all: both UNCHECKED
        ;; (STATUS_XING retired 2026-08-01, DATA-FLOW §4.1)
        (pfa:status-reset anchor '("LABEL" "INVERT") notes)
        (if stub (pfa:stub-del (car stub) (cadr stub)))
        ;; DATA-FLOW §6 (decided 2026-08-01): registration REPAIRS the
        ;; membership index in-group -- absent records only; stale ones are
        ;; the engine top-up's or PFINDEX Build's to refresh.
        (setq idx (pfa:index-repair))
        (pf:undo-end '*pfs-undo-open*)
        (prompt (strcat "\n  Anchored.  Sta " (pf:fmt-station (car rng))
                        " to " (pf:fmt-station (cadr rng))
                        ", datum " (rtos datum 2 2)
                        ".  (One U reverses this grid.)"))
        (if idx
          (prompt (strcat "\n  Index: " (itoa (car idx))
                          " structure(s) newly indexed"
                          (if (> (nth 3 idx) 0)
                            (strcat ", " (itoa (nth 3 idx))
                                    " stale (PFINDEX Build refreshes)")
                            "")
                          ".")))
        (foreach r notes (prompt (strcat "\n  NOTE: " r)))
        anchor)))))

;; (pfs:touched-passes anchor old-cl res) -> list of pass names to reset
;;   Which of the four STATUS records this edit actually invalidated.  The .cl
;;   feeds PFLABEL (stations) and PFXLABEL (crossing target stations); the _INV
;;   .pro feeds PFINVERT.  Re-binding one must not blank the other's verdict --
;;   that is the whole reason the single shared record was split.
;;   A pass whose input did not move keeps its state, its timestamp and its
;;   findings untouched.
(defun pfs:touched-passes (anchor old-cl res / out new-cl old-inv new-inv files r)
  (setq out '() new-cl (cdr (assoc 'cl res)))
  (if (or (null old-cl) (= old-cl "")
          (/= (pf:cl-id old-cl) (pf:cl-id new-cl)))
    (setq out '("LABEL")))          ; STATUS_XING retired 2026-08-01 (§4.1)
  (setq files   (pfa:files-get anchor)
        old-inv (if (and files (assoc 1 files)) (cdr (assoc 1 files)) ""))
  (foreach r (cdr (assoc 'pro res))
    (if (= (cdr (pf:parse-pro-name r)) "INV") (setq new-inv r)))
  (if (or (null new-inv) (= old-inv "")
          (/= (pf:cl-id old-inv) (pf:cl-id new-inv)))
    (setq out (cons "INVERT" out)))
  out)

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
(defun pfs:edit-one (anchor / init preset vmsg res at old-cl rm pts ed ins ext
                      xs ys datum xf notes touched idx r)
  (prompt (strcat "\nEditing " (pfa:anchor-title anchor) "."))
  (foreach r (pfa:corner-check anchor)
    (prompt (strcat "\n  DRIFT: " r)))
  ;; read once, cleared -- see the note in pfs:place-one
  (setq init             (pfs:anchor-init anchor)
        preset           *pfs-preset-res*
        *pfs-preset-res* nil
        vmsg             (if preset (pfs:validate preset))
        res              (if vmsg
                           nil
                           (pfs:complete-res
                             (if preset preset (pfs:show-dialog init)) init)))
  (cond
    (vmsg (prompt (strcat "\nREFUSED -- " vmsg)))
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
                           ", then anchor it fresh.")))
          (T
           (if (eq rm 'UNKNOWN)
             (if (and old-cl (/= old-cl "")
                      (/= (strcase old-cl)
                          (strcase (cdr (assoc 'cl res)))))
               (prompt "\n  NOTE: old .cl unreadable -- range match not verified.")))
           ;; extents: the record's re-pick flag, or rebuild from the
           ;; stored relative geometry
           (if (cdr (assoc 'repick res))
             (setq pts (pfs:pick-extents))
             (progn
               (setq ed  (entget anchor)
                     ins (cdr (assoc 10 ed))
                     ext (pfa:extents anchor)   ; attributes, or legacy scales
                     xs  (car ext)
                     ys  (cadr ext))
               (if (and xs ys)
                 (setq pts (list (list (car ins) (cadr ins))
                                 (list (+ (car ins) xs)
                                       (+ (cadr ins) ys))))
                 (progn
                   (prompt "\n  No width on record (legacy anchor) -- re-picking.")
                   (setq pts (pfs:pick-extents))))))
           (setq datum (cdr (assoc 'datum res)))   ; typed in the dialog, or asked
           (cond
             ((null pts) (prompt "\nEdit cancelled -- nothing written."))
             (T
              (pf:undo-begin '*pfs-undo-open*)
              (setq xf (pfs:build-xform res (car pts) (cadr pts) datum))
              (pfa:reanchor anchor xf)
              (pfa:meta-put anchor (cdr (assoc 'cl res))
                            (pf:checksum-strict (cdr (assoc 'cl res))))
              ;; THE RESET FOLLOWS THE FILE, not the edit.  An edit used to
              ;; blank one shared record, throwing away checks it had not
              ;; invalidated: re-binding the _INV .pro says nothing about the
              ;; .cl, so it must not clear what PFLABEL knew.  pfs:touched-passes
              ;; names only the passes whose own input actually moved.
              ;; ORDER IS LOAD-BEARING: it compares against the OLD FILES
              ;; record, so it must run BEFORE pfs:bind-files overwrites it.
              (setq touched (pfs:touched-passes anchor old-cl res)
                    notes   (pfs:bind-files anchor res))
              (pfa:status-reset anchor touched notes)
              ;; DATA-FLOW §6: repair the membership index in-group -- a
              ;; re-bound .cl changes the roster, so absent records get filed
              ;; against the NEW stamp; stale ones wait for top-up/Build.
              (setq idx (pfa:index-repair))
              (pf:undo-end '*pfs-undo-open*)
              (prompt "\n  Updated in place (ledger preserved; status UNCHECKED).")
              (if (and idx (> (+ (car idx) (nth 3 idx)) 0))
                (prompt (strcat "\n  Index: " (itoa (car idx))
                                " structure(s) newly indexed, " (itoa (nth 3 idx))
                                " stale (PFINDEX Build refreshes).")))
              (foreach r notes (prompt (strcat "\n  NOTE: " r))))))))))))


;;; ==========================================================================
;;; SECTION 4  --  Registry display + the on-the-fly entry point
;;; ==========================================================================

;; (pfs:reg-item r) -> one column-formatted registry row for the list "grids"
(defun pfs:reg-item (r)
  (strcat (pfset:pad (car r) 12)
          (pfset:pad (strcat "'" (cadr r) "'") 28)
          (if (eq (caddr r) 'ANCHORED) "[ANCHORED]" "[registered]")))

;; (pfs:choose-or-place) -> anchor | nil
;;   Registry pick for the label commands (pf_pick dialog): an ANCHORED profile
;;   returns its anchor; choosing a registered one IS consent to anchor it --
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
        (if (eq (caddr r) 'ANCHORED)
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
    ((eq (caddr (nth i r-reg)) 'ANCHORED)
     (set_tile "error" "Already anchored -- use Edit."))
    (T (setq r-idx i) (done_dialog 2))))

(defun pfs:rd-edit ( / i)
  (setq i (pfs:rd-sel))
  (cond
    ((null i) (set_tile "error" "Select a profile first."))
    ((not (eq (caddr (nth i r-reg)) 'ANCHORED))
     (set_tile "error" "Not ANCHORED yet -- use Anchor."))
    (T (setq r-idx i) (done_dialog 4))))

;; Anchor All was REMOVED 2026-07-28.  Every grid needs its own scales, datum
;; and two picks, so a batch was always a dialog parade with no way to pause --
;; the open issue it carried is closed as removed, not fixed.  Anchor one at a
;; time, from here or from the palette.

;; Double-click is the smart verb: anchor a registered row, edit an anchored one.
(defun pfs:rd-dbl ( / i)
  (if (setq i (pfs:rd-sel))
    (progn
      (setq r-idx i)
      (done_dialog (if (eq (caddr (nth i r-reg)) 'ANCHORED) 4 2)))))

;; (pfs:registry-dialog r-reg) -> (verb . idx) | nil (Close)
;;   verbs: 'place 'edit 'new 'refresh; idx 0-based (or nil).
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
                 (mode_tile "reg_edit"  1)))
        (action_tile "reg_list"  "(if (= $reason 4) (pfs:rd-dbl))")
        (action_tile "reg_place" "(pfs:rd-place)")
        (action_tile "reg_edit"  "(pfs:rd-edit)")
        (action_tile "reg_new"   "(done_dialog 5)")
        (action_tile "reg_scan"  "(done_dialog 6)")
        (action_tile "accept"    "(done_dialog 0)")
        (action_tile "help"
          (strcat "(pfset:help \"The registry is every profile this drawing "
                  "knows: AUTO-named stubs and anchored profiles.\\n\\n"
                  "Anchor      anchor a registered profile's grid (dialog, two "
                  "corner picks).\\nEdit        rebind files / scales / datum "
                  "on an anchored grid.\\nNew         a profile the sheet scan "
                  "missed.\\nRefresh     re-scan the sheet's PF-NAME text, and "
                  "re-check every registered line for .pro files that "
                  "appeared since (empty slots only -- an existing binding "
                  "is never overwritten).\")"))
        (setq code (start_dialog))
        (unload_dialog dcl_id)
        (cond
          ((= code 2) (cons 'place r-idx))
          ((= code 4) (cons 'edit r-idx))
          ((= code 5) (cons 'new nil))
          ((= code 6) (cons 'refresh nil))
          (T nil))))))

;; (pfs:cmd) -> nil   The command body, run under pf:run-command.
(defun pfs:cmd ( / rootDir reg going act)
  (setq *pfs-undo-open* nil)

  ;; Project root is NATIVE (Carlson tmpdir$).  Only when there's no active
  ;; project does the one-shot browse seed a session fallback.
  (setq rootDir (pfset:root-get))
  (if rootDir
    (prompt (strcat "\nProject data folder: " rootDir
                    (if (pfset:tmpdir) "  (Carlson project)" "  (session)")))
    (progn
      (setq rootDir (pfset:browse
                      "No active Carlson project -- select ANY file in the Project Data Folder"
                      '*pfset-dir-cl* "cl"))
      (if rootDir
        (progn
          (setq rootDir (strcat (vl-filename-directory rootDir) "\\"))
          (pfset:root-set rootDir)
          (prompt (strcat "\nProject data folder (session): " rootDir))))))

  ;; AUTO fires when the drawing has no registry
  (if (null (pfa:registry)) (pfs:auto))
  
  (setq going T)
  (while going
    (setq reg (pfa:registry)
          act (pfs:registry-dialog reg))
    (cond
      ((null act) (setq going nil))
      ((eq (car act) 'refresh) (pfs:auto))
      ((eq (car act) 'new)     (pfs:place-one nil))
      ((eq (car act) 'place)
       (pfs:place-one (nth 4 (nth (cdr act) reg))))
      ((eq (car act) 'edit)
       (pfs:edit-one (nth 3 (nth (cdr act) reg))))))
  (princ))

(defun c:PFSETUP ()
  (pf:run-command "PFSETUP" nil 'pfs:cmd))


(princ "\npfsetup.lsp loaded.  Command: PFSETUP (AUTO names, USER places).")
(princ)
;;; ==========================================================================
;;; end of pfsetup.lsp
;;; ==========================================================================
