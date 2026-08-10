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

;; pfxl:split and pfxl:scope-read MOVED to pfanchor 2026-07-30 as pfa:split /
;; pfa:scope-read, with the discovery scan itself (pfa:xing-scan).  They are
;; SCOPE-record knowledge, and pfanchor -- four load positions above this file
;; -- is the reader that now needs them.  No aliases left behind.
;; pfxl:src-files and pfxl:nz FOLLOWED THEM 2026-08-06, as pfa:src-files /
;; pfa:nz: the scan's .pro range filter needs a source line's _INV, and it
;; cannot call downward into position 9.  Same rule, no aliases.

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
      (pfa:pass-put *pfxl-run-anchor* *pfxl-pass-name* *pf-anno-layer* nil
                    (append oldh *pfxl-run-newh*))
      (setq *pfxl-run-newh* nil *pfxl-run-anchor* nil)))
  (princ))


;;; ==========================================================================
;;; SECTION 3  --  Discovery  (auto; registry-scoped; checksum short-circuit)
;;; ==========================================================================

;; (pfxl:discover anchor) -> nil   (merges into the ledger; rewrites SCOPE)
;;   Caller must hold an open undo group.
;;   THE FILING HALF ONLY.  The scan lives in pfa:xing-scan so the palette can
;;   run the SAME find read-only and show crossings before this command has ever
;;   been run against a line -- see that function's header for why it sits in
;;   pfanchor.  What is left here is the part that genuinely writes: merge each
;;   hit, rewrite SCOPE, report.
;;   IT STILL PASSES write-p T.  Inside the undo group the GEOM cache filing is
;;   wanted, and it is what makes the NEXT read-only preview cheap -- the two
;;   callers feed each other rather than competing.
;;   The scan's short-circuit means `found` holds only pairs whose .cl changed
;;   since the last run, so the counters report movement, not the size of the
;;   line set.
(defun pfxl:discover (anchor / res found newscope skips nnew nupd nmov
                             f st sk)
  (prompt "\nChecking for crossings...")
  ;; BEFORE the scan: retract rows filed before today's filters existed -- a
  ;; tie-in, or a hit past the end of the source's pipe.  The scan can only
  ;; decline to file one; the ledger is what the dialog reads, and nothing else
  ;; ever deletes from it.  Each row names its own grounds.
  ;; Reported here rather than beside the scan's skips: a retraction is a
  ;; record LEAVING the ledger and stands whether or not the scan then runs.
  (foreach sk (pfa:xing-sweep-shared anchor)
    (prompt (strcat "\n  Removed -- " (nth 3 sk) ": "
                    (car sk) " at " (pf:fmt-station (cadr sk))
                    " (source " (pf:fmt-station (caddr sk)) ").")))
  (if (null (setq res (pfa:xing-scan anchor T)))
    (prompt (strcat "\nTarget has no readable .cl on record"
                    " -- discovery skipped."))
    (progn
      (setq found    (car res)
            newscope (cadr res)
            skips    (caddr res)
            nnew 0 nupd 0 nmov 0)
      (foreach f found
        ;; Re-merged rather than trusting the scan's classification: merge is
        ;; the writer and owns the final say, and between the scan and here it
        ;; is the only thing that has touched the ledger.  Same call, same
        ;; classifier underneath (pfa:xing-classify), so the two cannot
        ;; disagree -- this just keeps the write path authoritative.
        (setq st (pfa:xing-merge anchor (car f)))
        (cond ((eq st 'NEW)   (setq nnew (1+ nnew)))
              ((eq st 'MOVED) (setq nmov (1+ nmov)))
              (T              (setq nupd (1+ nupd)))))
      (pfa:scope-put anchor newscope)
      ;; report only when the scan actually changed something -- a bare
      ;; "0 new, 0 updated, 0 moved" reads like nothing was labeled
      (if (> (+ nnew nupd nmov) 0)
        (prompt (strcat "\nDiscovery: " (itoa nnew) " new, " (itoa nupd)
                        " updated, " (itoa nmov) " moved.")))
      ;; NAMED, one line each, and unconditionally -- a skipped intersection is
      ;; the one case where the operator has to be able to tell "not a crossing"
      ;; from "missed a crossing", and what decides it is either a config value
      ;; (*pfx-terminus-tol*) or the station range of a .pro they authored.
      (foreach sk skips
        (prompt (strcat "\n  Skipped -- " (nth 3 sk) ": " (car sk)
                        " at " (pf:fmt-station (cadr sk))
                        " (source " (pf:fmt-station (caddr sk)) ").")))))
  (princ))


;;; ==========================================================================
;;; SECTION 4  --  Label one crossing on the TARGET grid
;;; ==========================================================================

;; (pfxl:label-one anchor xf e style sf ht toplines tverts)
;;   -> (handles . nil)  on success  |  (nil . "REASON")  on skip
;;   tverts is the TARGET's own invert vertices, read once per pass by pfxl:run.
(defun pfxl:label-one (anchor xf e style sf ht toplines tverts / srcfile ty nm sf3
                       invpro toppro mat pipe inv size tsta ssta x gtop ybot y
                       ycen ents en telev)
  (setq tsta    (pfa:xr-tsta e)
        ssta    (pfa:xr-ssta e)
        srcfile (pfa:xr-sfile e)
        ty      (pf:type-of srcfile)
        nm      (pf:name-of srcfile)
        sf3     (pfa:src-files ty nm))
  (cond
    ((null sf3)        (cons nil "SOURCE NOT REGISTERED"))
    ((null (car sf3))  (cons nil "NO INVERT .PRO BOUND"))
    (T
     (setq invpro (car sf3) toppro (cadr sf3) mat (caddr sf3)
           pipe   (pf:pipe-at invpro toppro ssta))
     (cond
       ;; the two ways pipe comes back nil are different facts and the operator
       ;; acts on them differently: one is a broken file, the other is a pipe
       ;; that legitimately does not reach this station.  Discovery already
       ;; declines to file the second, so reaching it here means a ledger row
       ;; that predates the filter, or a .pro shortened since.
       ((pf:pro-outside-p invpro ssta)
        (cons nil "NO PIPE ON THE SOURCE AT THAT STATION"))
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
           ;; station line (LWPOLYLINE on PF-ANNO with the rest of the output).
           ;; Recon still separates it from a STRUCTURE station line by geometry,
           ;; not by layer: this line's top vertex is the grid top, a structure
           ;; line's is its text-stack top, a full text height higher.  The
           ;; intended long-term marker is an XDATA tag, not either layer name.
           (if (setq en (pfd:station-line x ybot gtop (pfd:anno-layer)))
             (setq ents (cons en ents)))
           ;; vertical station text
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
           ;; size + material + standard line label, straddling the pipe CENTRE.
           ;; Half a nominal diameter is added as an ELEVATION so the transform
           ;; applies the same vscale the block insert above was given.
           (setq ycen (if size
                        (pf:elev->profile-y (+ inv (/ size 24.0)) xf)
                        y))
           (foreach en (pfd:label-pipe x ycen srcfile size mat sf ht style)
             (setq ents (cons en ents)))
           ;; persist: target invert (own .pro, sampled off the once-read
           ;; vertices) + source invert
           (setq telev (pf:pro-z-verts tverts tsta))
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

;; (pfxl:report-status anchor) -> nil
;;   PRINTS the crossings freshness verdict; STORES NOTHING.  STATUS_XING was
;;   retired 2026-08-01 (DATA-FLOW §4.1): it validated the TARGET .cl against
;;   META (301) through the same code as STATUS_LABEL -- identical inputs,
;;   identical verdict, so the record could never disagree with LABEL's and the
;;   Checks roll-up was counting one question twice.  Per-SOURCE freshness is
;;   SCOPE's job: it stores a <base>|<target-cksum>|<source-cksum> triple per
;;   pair and short-circuits discovery on it.
(defun pfxl:report-status (anchor / meta stored res state findings e)
  (setq meta   (pfa:meta-get anchor)
        stored (if (and meta (assoc 301 meta)) (cdr (assoc 301 meta)) "")
        res    (pfa:status-check anchor "XING"
                                 (if meta (cdr (assoc 1 meta))) stored)
        state  (car res)
        findings (cdr res))
  (prompt (strcat "\nPass complete.  Freshness: " (pfa:status-label state)))
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
(defun pfxl:run (anchor xf sel / style sf ht toplines tpro tverts res drawn
                                  skips oldh lay e)
  (setq style    (pfset:active-style)
        sf       (pf:xf-sf xf)
        ht       (* *pf-text-base-height* sf)
        toplines (pf:top-lines)
        drawn    0
        skips    '())
  ;; The target's own invert profile, read ONCE for the whole pass.  telev is a
  ;; per-station value but the .pro is ONE file: pf:pro-z asks the Road API per
  ;; crossing, and a missing file makes Carlson print an "unable to open file"
  ;; pair from C++ per call -- below LISP, where vl-catch-all-apply cannot reach
  ;; it (same defence as the corridor pre-filter: don't make the call).
  ;; pf:pro-verts is the file read, cached on path+checksum, and silent when the
  ;; file is gone, so the one honest line below is the only report.
  (setq tpro   (pf:xf-get 'pro-inv xf)
        tverts (if tpro (pf:pro-verts tpro)))
  (if (and tpro (null tverts))
    (prompt (strcat "\n  Target invert profile unreadable (" tpro
                    ") -- crossing elevations will not be stored.")))
  ;; run-scoped globals (not locals): the Esc flush ledgers the partial pass
  (setq *pfxl-run-anchor* anchor
        *pfxl-run-newh*   nil)
  (pf:zoom-resolve T)                  ; PFXLABEL parades by default (palette override wins)
  (pf:zoom-begin sf)                   ; snapshot the pre-run view + frame floor
  (foreach e sel
    (setq res (pfxl:label-one anchor xf e style sf ht toplines tverts))
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
      (setq oldh (pfa:pass-handles anchor *pfxl-pass-name*)
            lay  *pf-anno-layer*)
      (pfa:pass-put anchor *pfxl-pass-name* lay nil
                    (append oldh *pfxl-run-newh*))))
  (setq *pfxl-run-newh* nil *pfxl-run-anchor* nil)  ; normal exit: flush disarms
  ;; ---- input validation, printed only -----------------------------------
  ;; STATUS_XING retired 2026-08-01 (DATA-FLOW §4.1): the verdict duplicated
  ;; STATUS_LABEL exactly, so it is reported to the operator but not stored.
  ;; Source .cl checksums are per-pair and live in SCOPE.
  (pfxl:report-status anchor)
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
