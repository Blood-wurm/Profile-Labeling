;;; ==========================================================================
;;; pfxlabel.lsp  --  C:PFXLABEL : pipe-crossing discovery + labeling
;;;                   Dialog: pfxl_run.
;;; Load position 8 of 10: after pflabel, before pfinvert.
;;; Model, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfxl-undo-open*)) (setq *pfxl-undo-open* nil))
(if (not (boundp '*pfxl-last*))      (setq *pfxl-last* nil))  ; (type . name)
                                     ; The verification zoom+pause is now the
                                     ; shared pf:zoom-* facility (pftools-lib 15);
                                     ; the pre-run view lives in the global
                                     ; *pf-zoom-view-save* so the *error* handler
                                     ; can restore it on an Esc mid-parade.

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

;; (registry row -> .cl resolution is pfa:entry-cl, pfanchor SECTION 4 --
;;  moved there 2026-07-26 so pflabel shares the single resolver.)

;; (pfxl:handle-of ename) -> handle string | nil
(defun pfxl:handle-of (e) (cdr (assoc 5 (entget e))))


;;; ==========================================================================
;;; SECTION 2  --  Esc ledger flush  (error handling lives in pf:run-command)
;;; ==========================================================================

;; Run-scoped state for the flush: the engine's handle accumulator lives in a
;; GLOBAL (not a pfxl:run local) precisely so an Esc can ledger the partial
;; crossing handles; the target anchor rides beside it.
(if (not (boundp '*pfxl-run-anchor*)) (setq *pfxl-run-anchor* nil))
(if (not (boundp '*pfxl-run-newh*))   (setq *pfxl-run-newh* nil))

;; (pfxl:flush-pass) -> nil   The Esc ledger flush (pf:run-command hook).
;;   Appends the handles drawn before the Esc to the XING pass ledger, INSIDE
;;   the still-open undo group.  The engine clears both globals after its own
;;   normal-exit append, so this fires only on a mid-run interrupt.
(defun pfxl:flush-pass ( / oldh)
  (if (and *pfxl-undo-open* *pfxl-run-anchor* *pfxl-run-newh*)
    (progn
      (setq oldh (pfa:pass-handles *pfxl-run-anchor* *pfxl-pass-name*))
      (pfa:pass-put *pfxl-run-anchor* *pfxl-pass-name* *pfa-xing-layer* nil
                    (append oldh *pfxl-run-newh*))
      (setq *pfxl-run-newh* nil *pfxl-run-anchor* nil)))
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
    ((null (setq tverts (cdr (pf:cl-geom tcl T))))   ; in-group: filing allowed
     (prompt "\nCould not read target .cl geometry -- discovery skipped."))
    (T
     (setq tck      (pf:checksum-file tcl)
           reg      (pfa:registry)
           last     (pfxl:scope-read anchor)
           newscope '() nnew 0 nupd 0 nmov 0)
     (foreach r reg
       (if (not (and (= (strcase (car r)) ty) (= (strcase (cadr r)) nm)))
         (if (setq scl (pfa:entry-cl r))
           (progn
             (setq sck    (pf:checksum-file scl)
                   sbase  (vl-filename-base scl)
                   triple (car (vl-member-if
                                 '(lambda (x) (= (car x) sbase)) last)))
             ;; record current state for the next scan regardless
             (setq newscope (cons (strcat sbase "|" tck "|" sck) newscope))
             ;; short-circuit: both .cl unchanged since last scan
             (if (not (and triple (= (cadr triple) tck) (= (caddr triple) sck)))
               (if (setq sverts (cdr (pf:cl-geom scl T)))  ; in-group: filing allowed
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
           ;; station line (LWPOLYLINE on PF-XING -- recon scans this).  THE
           ;; one piece of label output that does NOT go to PF-ANNO: this layer
           ;; is a data channel, not styling.  pfa:station-line-tops finds a
           ;; crossing's "labeled" mark by scanning PF-XING BY NAME, so the line
           ;; has to stay where that scan looks.
           (if (setq en (pfd:station-line x ybot gtop *pfa-xing-layer*))
             (setq ents (cons en ents)))
           ;; vertical station text -- PF-ANNO like every other label (moved off
           ;; PF-XING 2026-07-29).  Recon never read it: that scan filters
           ;; (0 . "LWPOLYLINE"), so text was invisible to it on either layer.
           (if (setq en (pfd:text (list x ybot 0.0)
                                  (strcat (pf:fmt-station tsta) " "
                                          (pf:cross-desc srcfile))
                                  (pfd:anno-layer) style ht
                                  (/ pi 2.0) 'MR))
             (setq ents (cons en ents)))
           ;; the crossing pipe at its invert elevation
           (setq y (pf:elev->profile-y inv xf))
           (if (setq en (pfd:insert-pipe (list x y) size
                                         (pfd:anno-layer)
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
;;   Session-last continues silently when still anchored; else the registry
;;   picker (which anchors a registered pick on the fly).
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

;; (pfxl:write-status anchor) -> nil
;;   The crossings half of the four-way STATUS split.  Validates the TARGET .cl
;;   against the checksum META recorded at setup -- the same comparison PFLABEL
;;   makes, because a crossing's target station comes off the same alignment.
;;   Per-SOURCE freshness is SCOPE's job: it already stores a
;;   <base>|<target-cksum>|<source-cksum> triple per pair and short-circuits
;;   discovery on it, so duplicating those here would be a fifth copy of a fact
;;   that already has an owner.
(defun pfxl:write-status (anchor / meta stored res state findings e)
  (setq meta   (pfa:meta-get anchor)
        stored (if (and meta (assoc 301 meta)) (cdr (assoc 301 meta)) "")
        res    (pfa:status-check anchor "XING"
                                 (if meta (cdr (assoc 1 meta))) stored)
        state  (car res)
        findings (cdr res))
  (pfa:status-put anchor "XING" state stored findings)
  (prompt (strcat "\nPass recorded.  Status: " (pfa:status-label state)))
  (foreach e findings (prompt (strcat "\n  FINDING: " e)))
  (princ))

;; (pfxl:zoom-to xf e sf) -> nil
;;   Verification zoom+pause on one just-drawn crossing (boss ask): frame the
;;   station line (grid top down to the line extension) and hand off to the
;;   shared parade (pf:zoom-item, pftools-lib 15).  This wrapper is only the
;;   crossing-specific FRAME; the gate, view math, and DELAY are all shared.
(defun pfxl:zoom-to (xf e sf)
  (pf:zoom-item (pf:station->profile-x (pfa:xr-tsta e) xf)
                (- (pf:xf-basey xf) (* *pfx-line-ext* sf))   ; ylo: below the base
                (pf:grid-top-y xf)))                          ; yhi: the grid top

;; (pfxl:run anchor xf sel) -> nil
;;   The ENGINE: draws the resolved crossing selection on the sheet.  Discovery,
;;   recon and the run dialog build `sel` on the GATHER side (discovery also
;;   writes the ledger under the caller's undo group), so they stay in the
;;   command; this is only the sheet-drawing pass -- the piece a modeless palette
;;   cannot do itself and will reuse via its deferred command.  style/sf/ht/
;;   toplines derive here from xf.  Caller owns the *error*/echo wrapper and the
;;   undo group; body is unchanged from the old inline loop.
(defun pfxl:run (anchor xf sel / style sf ht toplines res drawn skips
                                  oldh lay e)
  (setq style    (pfset:active-style)
        sf       (pf:xf-sf xf)
        ht       (* *pf-text-base-height* sf)
        toplines (pf:top-lines)
        drawn    0
        skips    '())
  ;; run-scoped globals (not locals): the Esc flush ledgers the partial pass
  (setq *pfxl-run-anchor* anchor
        *pfxl-run-newh*   nil)
  (pf:zoom-resolve T)                  ; PFXLABEL parades by default (palette override wins)
  (pf:zoom-begin sf)                   ; snapshot the pre-run view + frame floor
  (foreach e sel
    (setq res (pfxl:label-one anchor xf e style sf ht toplines))
    (if (car res)
      (progn
        (setq *pfxl-run-newh* (append *pfxl-run-newh* (car res))
              drawn (1+ drawn))
        (pfxl:zoom-to xf e sf))       ; verification zoom+pause
      (setq skips (cons (list (pfa:xr-key e) (pfa:xr-sbase e)
                              (pfa:xr-tsta e) (cdr res))
                        skips))))
  (pf:zoom-end)                        ; restore the pre-run view after the parade
  ;; append this pass's handles to the crossing pass ledger
  (if *pfxl-run-newh*
    (progn
      ;; The pass now SPANS two layers -- station lines on PF-XING, everything
      ;; else on PF-ANNO -- and the record holds one DXF 8.  It stays PF-XING:
      ;; the field is informational (erase is by handle, always was), and the
      ;; station line is what identifies a crossing pass.
      (setq oldh (pfa:pass-handles anchor *pfxl-pass-name*)
            lay  *pfa-xing-layer*)
      (pfa:pass-put anchor *pfxl-pass-name* lay nil
                    (append oldh *pfxl-run-newh*))))
  (setq *pfxl-run-newh* nil *pfxl-run-anchor* nil)  ; normal exit: flush disarms
  ;; ---- input validation -> STATUS_XING ----------------------------------
  ;; NEW 2026-07-27: PFXLABEL wrote no status at all, so a crossings pass left
  ;; nothing behind saying whether its inputs were sound.  The input here is the
  ;; TARGET .cl -- the source .cl checksums are per-pair and already live in
  ;; SCOPE, which stays the source of truth for them rather than being copied.
  (pfxl:write-status anchor)
  ;; pass report
  (prompt (strcat "\n== PFXLABEL: " (itoa drawn)
                  " labeled, " (itoa (length skips))
                  " skipped =="))
  (foreach e (reverse skips)
    (prompt (strcat "\n  SKIPPED  " (cadr e) " @ tgt sta "
                    (pf:fmt-station (caddr e)) "  -- "
                    (nth 3 e))))
  (princ))

;; (pfxl:cmd) -> nil   The command body, run under pf:run-command.
(defun pfxl:cmd ( / anchor xf work recon act ndup allmode sel)
  (setq *pfxl-undo-open* nil)
  (setq anchor (pfxl:resolve-target))
  (if (null anchor)
    (prompt "\nNo target -- cancelled.")
    (if (null (setq xf (pfa:anchor->xform anchor)))
      (prompt "\nTarget grid record unreadable -- cannot label.")
      (progn
        (setq *pfxl-last* (cons (strcase (pf:xf-get 'type xf))
                                (strcase (pf:xf-get 'name xf))))
        (pf:undo-begin '*pfxl-undo-open*)

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
                (T (pfxl:run anchor xf sel)))))))    ; resolved -> sheet engine
        (if *pfxl-undo-open*
          (pf:undo-end '*pfxl-undo-open*)))))
  (princ))

(defun c:PFXLABEL ()
  (pf:run-command "PFXLABEL" 'pfxl:flush-pass 'pfxl:cmd))

(defun c:PFX () (c:PFXLABEL))


(princ "\npfxlabel.lsp loaded.  Command: PFXLABEL (alias PFX).")
(princ)
;;; ==========================================================================
;;; end of pfxlabel.lsp
;;; ==========================================================================
