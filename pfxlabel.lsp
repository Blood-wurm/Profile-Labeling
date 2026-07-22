;;; ==========================================================================
;;; pfxlabel.lsp  --  C:PFXLABEL : pipe-crossing discovery + labeling
;;; --------------------------------------------------------------------------
;;; Requires cfg, lib, draw, anchor, settings, setup loaded first.
;;;
;;; ONE command, TARGET-DIRECTED.  The v3 trio (PFXFIND / PFXLABEL / PFXGRID)
;;; collapses: discovery auto-runs here, grid registration is PFSETUP's job.
;;;
;;; MODEL (V4 pivot):
;;;   - TARGET-ONLY draw.  A run labels ONLY the target grid; the crossing
;;;     pipe is drawn from the SOURCE profile's authored .pro (never a probe
;;;     of any drawn grid).  A source contributes as a pure file reference --
;;;     it needs its .pro BOUND, not its grid PLACED.  Reciprocal annotation
;;;     comes from running PFXLABEL with that profile as the target.
;;;   - Invert + size are READ from .pro via the Road API (profile z):
;;;     invert = flowline elevation; size = nearest nominal to (TOP-INV)x12.
;;;   - Material is the SOURCE profile's, asserted in PFSETUP -> NN" <MAT>.
;;;
;;; DISCOVERY: the target .cl is intersected against every OTHER registered
;;; profile's .cl (anchors AND stubs).  Per source pair a SCOPE checksum
;;; short-circuit skips pairs whose two .cl files are unchanged since the last
;;; scan.  Merges are additive (elevations preserved; never destructive).
;;;
;;; COMPLETENESS: a crossing is "labeled" when its station line stands on the
;;; target grid at the per-station top (pf:top-at) -- see pfanchor SECTION 5.
;;; The crossings DIALOG (pfxl_run) is the surface: Label Outstanding draws
;;; every unlabeled row; Label Selected relabels only after a deliberate
;;; confirm (duplicates).
;;;
;;; UNDO: one group wraps the whole pass (discovery + labels).  Esc is
;;; unwound by the handler.  Erase-by-handle only (handles ledgered as PASS).
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfxl-undo-open*)) (setq *pfxl-undo-open* nil))
(if (not (boundp '*pfxl-last*))      (setq *pfxl-last* nil))  ; (type . name)
(if (not (boundp '*pfxl-view-save*)) (setq *pfxl-view-save* nil)) ; (ctr . size)
                                     ; global, NOT a command local: the *error*
                                     ; handler must reach it to restore the
                                     ; view on Esc mid-zoom-parade

(setq *pfxl-pass-name* "XING")   ; the crossing pass in the handle ledger


;;; ==========================================================================
;;; SECTION 1  --  Pure helpers
;;; ==========================================================================

(defun pfxl:nz (s) (if (and s (/= s "")) s))

;; (pfxl:split s d) -> list of substrings split on the string d
(defun pfxl:split (s d / pos out)
  (setq out '())
  (while (setq pos (vl-string-search d s))
    (setq out (cons (substr s 1 pos) out)
          s   (substr s (+ pos 1 (strlen d)))))
  (reverse (cons s out)))

;; (pfxl:src-files type name) -> (inv-pro top-pro material) | nil
;;   Anchor first (carries material), then stub (no material).  nz-guarded.
(defun pfxl:src-files (type name / a f stub)
  (cond
    ((setq a (pfa:find-anchor name type))
     (setq f (pfa:files-get a))
     (list (pfxl:nz (cdr (assoc 1 f)))
           (pfxl:nz (cdr (assoc 2 f)))
           (pfxl:nz (cdr (assoc 5 f)))))
    ((setq stub (pfa:stub-get type name))
     (list (pfxl:nz (cdr (assoc 4 stub)))
           (pfxl:nz (cdr (assoc 5 stub)))
           nil))
    (T nil)))

;; (pfxl:entry-cl r) -> .cl path | nil   ; r = (type name state ename stub)
(defun pfxl:entry-cl (r)
  (if (eq (caddr r) 'PLACED)
    (pfxl:nz (cdr (assoc 1 (pfa:meta-get (nth 3 r)))))
    (pfxl:nz (nth 2 (nth 4 r)))))

;; (pfxl:handle-of ename) -> handle string | nil
(defun pfxl:handle-of (e) (cdr (assoc 5 (entget e))))


;;; ==========================================================================
;;; SECTION 2  --  Error handler
;;; ==========================================================================

(defun pfxl:*error* (msg / cw)
  (if (and msg (/= msg "Function cancelled") (/= msg "quit / exit abort"))
    (prompt (strcat "\nPFXLABEL error: " msg)))
  (pfa:undo-cleanup)                ; closes ANY pf group, incl. a nested one
  ;; Esc mid-zoom-parade: put the view back where the run started (after the
  ;; group closes, so the restore itself isn't part of the undo group)
  (if *pfxl-view-save*
    (progn
      (setq cw (pfxl:zoom-corners (car *pfxl-view-save*)
                                  (cdr *pfxl-view-save*)))
      (command-s "_.ZOOM" "_Window" (car cw) (cadr cw))
      (setq *pfxl-view-save* nil)))
  (setq *error* *pfxl-prev-error*)
  (princ))


;;; ==========================================================================
;;; SECTION 3  --  Discovery  (auto; registry-scoped; checksum short-circuit)
;;; ==========================================================================

;; (pfxl:scope-read anchor) -> list of (sbase tck sck)
(defun pfxl:scope-read (anchor / d out s parts)
  (setq out '())
  (if (setq d (pfa:scope-get anchor))
    (foreach s (pfa:collect-300 d)
      (setq parts (pfxl:split s "|"))
      (if (= (length parts) 3) (setq out (cons parts out)))))
  out)

;; (pfxl:discover anchor) -> nil   (merges into the ledger; rewrites SCOPE)
;;   Caller must hold an open undo group.
(defun pfxl:discover (anchor / xf ty nm tcl tck tverts reg last newscope
                      nnew nupd nmov r scl sck sbase triple sverts xy tsta ssta
                      xy2 tsta2 ssta2 st)
  (setq xf  (pfa:anchor->xform anchor)
        ty  (strcase (pf:xf-get 'type xf))
        nm  (strcase (pf:xf-get 'name xf))
        tcl (pfxl:nz (cdr (assoc 1 (pfa:meta-get anchor)))))
  (prompt "\nChecking for crossings...")
  (cond
    ((null tcl)
     (prompt "\nTarget has no .cl on record -- discovery skipped."))
    ((null (setq tverts (cdr (pf:cl-geom tcl))))
     (prompt "\nCould not read target .cl geometry -- discovery skipped."))
    (T
     (setq tck      (pf:checksum-file tcl)
           reg      (pfa:registry)
           last     (pfxl:scope-read anchor)
           newscope '() nnew 0 nupd 0 nmov 0)
     (foreach r reg
       (if (not (and (= (strcase (car r)) ty) (= (strcase (cadr r)) nm)))
         (if (setq scl (pfxl:entry-cl r))
           (progn
             (setq sck    (pf:checksum-file scl)
                   sbase  (vl-filename-base scl)
                   triple (car (vl-member-if
                                 '(lambda (x) (= (car x) sbase)) last)))
             ;; record current state for the next scan regardless
             (setq newscope (cons (strcat sbase "|" tck "|" sck) newscope))
             ;; short-circuit: both .cl unchanged since last scan
             (if (not (and triple (= (cadr triple) tck) (= (caddr triple) sck)))
               (if (setq sverts (cdr (pf:cl-geom scl)))
                 (if (setq xy (pf:poly-x tverts sverts))
                   (progn
                     (setq tsta (pf:sta-at tcl xy)
                           ssta (pf:sta-at scl xy))
                     (if (and tsta ssta
                              (setq xy2 (pf:refine-x tcl tsta scl ssta)))
                       (progn
                         (setq tsta2 (pf:sta-at tcl xy2)
                               ssta2 (pf:sta-at scl xy2))
                         (if (and tsta2 ssta2)
                           (setq xy xy2 tsta tsta2 ssta ssta2))))
                     (if (and tsta ssta)
                       (progn
                         (setq st (pfa:xing-merge anchor
                                    (list nil tcl (vl-filename-base tcl)
                                          scl sbase (list (car xy) (cadr xy))
                                          tsta ssta nil nil)))
                         (cond ((eq st 'NEW)   (setq nnew (1+ nnew)))
                               ((eq st 'MOVED) (setq nmov (1+ nmov)))
                               (T              (setq nupd (1+ nupd))))))))))))))
     (pfa:scope-put anchor (reverse newscope))
     ;; report only when the scan actually changed something -- a bare
     ;; "0 new, 0 updated, 0 moved" reads like nothing was labeled
     (if (> (+ nnew nupd nmov) 0)
       (prompt (strcat "\nDiscovery: " (itoa nnew) " new, " (itoa nupd)
                       " updated, " (itoa nmov) " moved.")))))
  (princ))


;;; ==========================================================================
;;; SECTION 4  --  Label one crossing on the TARGET grid
;;; ==========================================================================

;; (pfxl:label-one anchor xf e style sf ht toplines)
;;   -> (handles . nil)  on success  |  (nil . "REASON")  on skip
(defun pfxl:label-one (anchor xf e style sf ht toplines / srcfile ty nm sf3
                       invpro toppro mat pipe inv size tsta ssta x gtop ybot y
                       ents en telev)
  (setq tsta    (pfa:xr-tsta e)
        ssta    (pfa:xr-ssta e)
        srcfile (pfa:xr-sfile e)
        ty      (pf:type-of srcfile)
        nm      (pf:name-of srcfile)
        sf3     (pfxl:src-files ty nm))
  (cond
    ((null sf3)        (cons nil "SOURCE NOT REGISTERED"))
    ((null (car sf3))  (cons nil "NO INVERT .PRO BOUND"))
    (T
     (setq invpro (car sf3) toppro (cadr sf3) mat (caddr sf3)
           pipe   (pf:pipe-at invpro toppro ssta))
     (cond
       ((null pipe) (cons nil "SOURCE INVERT UNREADABLE (profile z)"))
       (T
        (setq inv  (car pipe)
              size (cdr pipe)
              x    (pf:station->profile-x tsta xf)
              gtop (pf:top-at x (pf:xf-basey xf)
                              (+ (pf:grid-top-y xf) (* *pfg-top-margin* sf))
                              toplines))
        (cond
          ((null gtop) (cons nil "NO GRID TOP AT STATION (probe miss)"))
          (T
           (setq ybot (- (pf:xf-basey xf) (* *pfx-line-ext* sf))
                 ents '())
           (pfd:ensure-layer *pfa-xing-layer* nil)
           (pfd:ensure-layer (pf:sym-layer srcfile) nil)
           ;; station line (LWPOLYLINE on PF-XING -- recon scans this)
           (if (setq en (pfd:station-line x ybot gtop *pfa-xing-layer*))
             (setq ents (cons en ents)))
           ;; vertical station text on PF-XING (recon selects LWPOLYLINE only,
           ;; so text on this layer is never mistaken for a station line)
           (if (setq en (pfd:text (list x ybot 0.0)
                                  (strcat (pf:fmt-station tsta) " "
                                          (pf:cross-desc srcfile))
                                  *pfa-xing-layer* style ht
                                  (/ pi 2.0) 'MR))
             (setq ents (cons en ents)))
           ;; the crossing pipe at its invert elevation
           (setq y (pf:elev->profile-y inv xf))
           (if (setq en (pfd:insert-pipe (list x y) size
                                         (pf:sym-layer srcfile)
                                         (pf:xf-vscale xf) sf))
             (setq ents (cons en ents)))
           ;; size + material + standard line label
           (foreach en (pfd:label-pipe x y srcfile size mat sf ht style)
             (setq ents (cons en ents)))
           ;; persist: target invert (own .pro) + source invert
           (setq telev (if (pf:xf-get 'pro-inv xf)
                         (pf:pro-z (pf:xf-get 'pro-inv xf) tsta)))
           (pfa:xing-put-elevs anchor (pfa:xr-key e) telev inv)
           (cons (mapcar 'pfxl:handle-of ents) nil))))))))


;;; ==========================================================================
;;; SECTION 5  --  The crossings dialog + target resolution
;;; ==========================================================================
;;; The ledger IS the list; recon marks each row from the drawing.  The
;;; dialog replaces the old printed list + [All/Target] <n> prompt.  x-work /
;;; x-recon / x-res live in pfxl:run-dialog, reached by dynamic scope.

(defun pfxl:rd-item (e recon)
  (strcat (pfset:pad (pfa:xr-sbase e) 18)
          (pfset:pad (pf:fmt-station (pfa:xr-tsta e)) 16)
          (pfset:pad (pf:fmt-station (pfa:xr-ssta e)) 16)
          (if (cdr (assoc (pfa:xr-key e) recon))
            "[LABELED]" "[OUTSTANDING]")))

(defun pfxl:rd-out ()
  (if (vl-member-if
        '(lambda (x) (not (cdr (assoc (pfa:xr-key x) x-recon))))
        x-work)
    (progn (setq x-res '(all)) (done_dialog 1))
    (set_tile "error" "All crossings are already labeled.")))

(defun pfxl:rd-selbtn ( / s out i)
  (setq s (get_tile "xl_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select crossings in the list first.")
    (progn
      (setq out '())
      (foreach i (read (strcat "(" s ")"))
        (setq out (cons (nth i x-work) out)))
      (setq x-res (cons 'sel (reverse out)))
      (done_dialog 1))))

;; (pfxl:run-dialog x-work x-recon tgtline)
;;   -> ('all) | ('sel . entries) | ('target) | nil
(defun pfxl:run-dialog (x-work x-recon tgtline / dcl_id x-res code e ndone)
  (setq dcl_id (load_dialog (pfset:dcl-file)) x-res nil)
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfxl_run" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the crossings dialog.") nil)
      (progn
        (setq ndone 0)
        (foreach e x-work
          (if (cdr (assoc (pfa:xr-key e) x-recon)) (setq ndone (1+ ndone))))
        (set_tile "xl_tgt"
                  (strcat tgtline "   --   " (itoa (length x-work))
                          " crossing(s), "
                          (itoa (- (length x-work) ndone)) " outstanding"))
        (start_list "xl_list")
        (foreach e x-work (add_list (pfxl:rd-item e x-recon)))
        (end_list)
        (action_tile "xl_out"  "(pfxl:rd-out)")
        (action_tile "xl_sel"  "(pfxl:rd-selbtn)")
        (action_tile "xl_tgtb" "(setq x-res '(target)) (done_dialog 1)")
        (action_tile "cancel"  "(done_dialog 0)")
        (action_tile "help"
          (strcat "(pfset:help \"Crossings come from discovery: the target "
                  ".cl intersected with every other registered profile's "
                  ".cl.  The pipe is drawn from the SOURCE profile's "
                  "authored .pro.\\n\\nLabel Outstanding draws every "
                  "unlabeled row (the everyday verb).  Label Selected "
                  "draws exactly the highlighted rows -- relabeling a "
                  "[LABELED] row draws duplicates and asks first.\\n\\n"
                  "Change Target clears the sticky target; run PFXLABEL "
                  "again to choose another profile.\")"))
        (setq code (start_dialog))
        (unload_dialog dcl_id)
        (if (= code 1) x-res nil)))))

;; (pfxl:resolve-target) -> anchor | nil
;;   Session-last continues silently when still placed; else the registry
;;   picker (which places an unplaced pick on the fly).
(defun pfxl:resolve-target ( / a)
  (cond
    ((and *pfxl-last*
          (setq a (pfa:find-anchor (cdr *pfxl-last*) (car *pfxl-last*))))
     (prompt (strcat "\nTarget: " (car *pfxl-last*) " '" (cdr *pfxl-last*)
                     "'   (Change Target in the dialog switches profiles)."))
     a)
    (T (pfs:choose-or-place))))


;;; ==========================================================================
;;; SECTION 6  --  C:PFXLABEL
;;; ==========================================================================

;; (pfxl:zoom-corners ctr h) -> (p1 p2)
;;   Window corners reproducing a center+height view at the current screen
;;   aspect.  ZOOM _Center <pt> <height> miscomputes in this Carlson/Map
;;   build (fails "No Center found for specified point"); ZOOM _Window is
;;   the robust equivalent, so every view change routes through here.  The
;;   framed area is identical -- height drives, width follows viewport aspect.
(defun pfxl:zoom-corners (ctr h / scr asp w)
  (setq scr (getvar "SCREENSIZE")
        asp (/ (car scr) (cadr scr))
        w   (* h asp))
  (list (list (- (car ctr) (* 0.5 w)) (- (cadr ctr) (* 0.5 h)))
        (list (+ (car ctr) (* 0.5 w)) (+ (cadr ctr) (* 0.5 h)))))

;; (pfxl:zoom-cwh ctr h) -> nil   window zoom in NORMAL command context.
;;   The *error* handler must NOT use this (command is illegal there) -- it
;;   issues its own command-s zoom off pfxl:zoom-corners.
(defun pfxl:zoom-cwh (ctr h / cw)
  (setq cw (pfxl:zoom-corners ctr h))
  (command "_.ZOOM" "_Window" (car cw) (cadr cw)))

;; (pfxl:zoom-to xf e sf) -> nil
;;   Verification zoom+pause on one just-drawn crossing (boss ask): frame the
;;   station line (grid top down to the line extension) and DELAY.  No-op when
;;   *pfx-zoom-pause* is 0.  Caller saves/restores the pre-run view.
(defun pfxl:zoom-to (xf e sf / x ylo yhi)
  (if (> *pfx-zoom-pause* 0.0)
    (progn
      (setq x   (pf:station->profile-x (pfa:xr-tsta e) xf)
            ylo (- (pf:xf-basey xf) (* *pfx-line-ext* sf))
            yhi (pf:grid-top-y xf))
      (pfxl:zoom-cwh (list x (* 0.5 (+ ylo yhi)) 0.0)
                     (* 1.4 (- yhi ylo)))
      (command "_.DELAY" (fix (* *pfx-zoom-pause* 1000.0))))))

(defun c:PFXLABEL ( / anchor xf style sf ht toplines work recon act ndup
                    allmode sel e drawn skips res oldh newh lay)
  (setq *pfxl-prev-error* *error*
        *error*           pfxl:*error*
        *pfxl-undo-open*  nil)
  (pf:echo-off)
  (pf:load-apis)
  (setq anchor (pfxl:resolve-target))
  (if (null anchor)
    (prompt "\nNo target -- cancelled.")
    (if (null (setq xf (pfa:anchor->xform anchor)))
      (prompt "\nTarget grid record unreadable -- cannot label.")
      (progn
        (setq *pfxl-last* (cons (strcase (pf:xf-get 'type xf))
                                (strcase (pf:xf-get 'name xf)))
              style (pfset:active-style)
              sf    (pf:xf-sf xf)
              ht    (* *pf-text-base-height* sf)
              drawn 0
              skips '())
        (command "_.UNDO" "_Begin")
        (setq *pfxl-undo-open* T)

        ;; ---- discovery (additive) + working list ------------------------
        (pfxl:discover anchor)
        (setq work  (pfa:xing-list anchor)
              recon (pfa:recon xf work))
        (cond
          ((null work)
           (prompt "\nNo crossings found for this target."))
          (T
           (setq act (pfxl:run-dialog work recon
                       (strcat "Target: " (car *pfxl-last*) " '"
                               (cdr *pfxl-last*) "'")))
           (setq allmode (and act (eq (car act) 'all)))
           (cond
             ((null act) (prompt "\nCancelled -- nothing drawn."))
             ((eq (car act) 'target)
              (setq *pfxl-last* nil)
              (prompt "\nTarget cleared -- run PFXLABEL again to choose."))
             (T
              (if allmode
                (setq sel (vl-remove-if
                            '(lambda (x) (cdr (assoc (pfa:xr-key x) recon)))
                            work))
                (progn
                  (setq sel  (cdr act)
                        ndup (length (vl-remove-if-not
                                       '(lambda (x)
                                          (cdr (assoc (pfa:xr-key x) recon)))
                                       sel)))
                  ;; relabeling draws duplicates -- deliberate Yes required
                  (if (and (> ndup 0)
                           (not (pfset:confirm
                                  "Label already-labeled crossings?"
                                  (list (strcat (itoa ndup)
                                                " selected crossing(s) are "
                                                "already labeled.")
                                        "Labeling again draws DUPLICATE entities."
                                        "Proceed?"))))
                    (setq sel nil))))
              (cond
                ((null sel)
                 (prompt (if allmode
                           "\nAll crossings already labeled -- nothing to do."
                           "\nCancelled.")))
                (T
                 (setq toplines (pf:top-lines))
                 (if (> *pfx-zoom-pause* 0.0)
                   (setq *pfxl-view-save*
                         (cons (getvar "VIEWCTR") (getvar "VIEWSIZE"))))
                 (foreach e sel
                   (setq res (pfxl:label-one anchor xf e style sf ht toplines))
                   (if (car res)
                     (progn
                       (setq newh (append newh (car res))
                             drawn (1+ drawn))
                       (pfxl:zoom-to xf e sf))       ; verification zoom+pause
                     (setq skips (cons (list (pfa:xr-key e) (pfa:xr-sbase e)
                                             (pfa:xr-tsta e) (cdr res))
                                       skips))))
                 ;; restore the pre-run view after the verification zooms
                 (if (and *pfxl-view-save* (> drawn 0))
                   (pfxl:zoom-cwh (car *pfxl-view-save*)
                                  (cdr *pfxl-view-save*)))
                 (setq *pfxl-view-save* nil)
                 ;; append this pass's handles to the crossing pass ledger
                 (if newh
                   (progn
                     (setq oldh (pfa:pass-handles anchor *pfxl-pass-name*)
                           lay  *pfa-xing-layer*)
                     (pfa:pass-put anchor *pfxl-pass-name* lay nil
                                   (append oldh newh))))
                 ;; pass report
                 (prompt (strcat "\n== PFXLABEL: " (itoa drawn)
                                 " labeled, " (itoa (length skips))
                                 " skipped =="))
                 (foreach e (reverse skips)
                   (prompt (strcat "\n  SKIPPED  " (cadr e) " @ tgt sta "
                                   (pf:fmt-station (caddr e)) "  -- "
                                   (nth 3 e))))))))))
        (if *pfxl-undo-open*
          (progn (command "_.UNDO" "_End") (setq *pfxl-undo-open* nil))))))
  (pf:echo-on)
  (setq *error* *pfxl-prev-error*)
  (princ))

(defun c:PFX () (c:PFXLABEL))


(princ "\npfxlabel.lsp loaded.  Command: PFXLABEL (alias PFX).")
(princ)
;;; ==========================================================================
;;; end of pfxlabel.lsp
;;; ==========================================================================
