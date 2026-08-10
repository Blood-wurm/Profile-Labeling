;;; ==========================================================================
;;; pfxall.lsp  --  C:PFXALL : label every crossing on every profile
;;;                 No dialog.  No target prompt.  No parade.
;;; Load position 10 of 15: after pfxlabel, whose engine it drives unchanged.
;;; Model, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  The plan  (pure read; runs before the first undo group)
;;; ==========================================================================
;;; Filter one of two: a profile whose .cl is not ON DISK is dropped whole,
;;; before the sweep touches it.
;;;
;;; WHY THE .cl AND ONLY THE .cl.  A path on record but missing from disk is the
;;; one failure mode that cannot be caught from LISP: Carlson's Road API prints
;;; an "unable to open file" pair from C++, below where vl-catch-all-apply can
;;; reach.  The target's .cl is the one file this command hands the Road API
;;; unguarded -- pfa:xing-scan needs it or there is no discovery at all -- so it
;;; is gated here.  Both .pro reads are already guarded at their own level:
;;; pf:pro-range and pf:pro-verts checksum the file first and return nil without
;;; making the call.
;;;
;;; NEITHER .pro IS GATED ON THE TARGET (2026-08-07, Jake).  A crossing label's
;;; elevation comes from the SOURCE's _INV via pf:pipe-at; the target's _INV
;;; feeds only the ledgered telev, and its _TOP is never read at all (the grid
;;; top comes from the DRAWN grid, pf:top-lines).  So a profile with no .pro of
;;; its own still carries every crossing whose SOURCE has one, and pfxl:run
;;; degrades to "elevations will not be stored" rather than refusing.  The
;;; converse is per-crossing and lives in pfxl:label-one: a source with no _INV
;;; bound is skipped by name, on whatever grid it crosses.

;; (pfxa:label xf anchor) -> "STORM 'LINE-A'" | "anchor <handle>"
;;   Naming for the report.  Falls back to the handle so a profile whose record
;;   will not read still gets named in the skip list -- an unnamed skip is not
;;   actionable.
(defun pfxa:label (xf anchor / ty nm)
  (if (and xf
           (setq ty (pf:xf-get 'type xf))
           (setq nm (pf:xf-get 'name xf)))
    (strcat ty " '" nm "'")
    (strcat "anchor " (cdr (assoc 5 (entget anchor))))))

;; (pfxa:plan) -> (ok . skipped)
;;   ok      = ((anchor xf label) ...)   readable .cl, ready to sweep
;;   skipped = ((label . reason) ...)    each naming its own grounds
;;   PURE READ throughout -- no discovery, no writes, no undo group.  Built in
;;   full before anything draws so the operator sees the shape of the run
;;   (how many profiles, how many dropped and why) before it commits.
(defun pfxa:plan ( / ok dropped anchor xf lbl cl why)
  (setq ok '() dropped '())
  (foreach anchor (pfa:all-anchors)
    (setq xf   (pfa:anchor->xform anchor)
          lbl  (pfxa:label xf anchor)
          cl   (if xf (pf:xf-get 'clfile  xf))
          why  (cond
                 ((null xf)   "grid record unreadable -- run PFSETUP on it")
                 ((null cl)   "no .cl on record")
                 ((null (findfile cl))   (strcat ".cl not on disk: " cl))))
    (if why
      (setq dropped (cons (cons lbl why) dropped))
      (setq ok      (cons (list anchor xf lbl) ok))))
  (cons (reverse ok) (reverse dropped)))


;;; ==========================================================================
;;; SECTION 2  --  One profile's share of the sweep
;;; ==========================================================================

;; (pfxa:one anchor xf) -> count attempted | nil when nothing new
;;   Runs INSIDE the caller's undo group, which is what lets it call the
;;   writer half of discovery.  Filter two of two lives here: recon reports
;;   which ledger rows are already drawn on this grid and they come out of the
;;   selection, so the sweep is idempotent -- re-running after an interruption
;;   resumes and cannot draw a duplicate.  That is also why nothing here can
;;   ask a question: PFXLABEL's relabel confirmation only guards the
;;   hand-picked path, and a sweep that stalls on a modal prompt halfway
;;   through a sheet is worse than one that skips.
;;
;;   THE PARADE IS FORCED OFF.  pfxl:run resolves the zoom per pass off
;;   *pf-zoom-to* (pf:zoom-resolve), which is the documented override seam, so
;;   setting it here needs no change to the engine.  Left on, a whole-drawing
;;   sweep is one framed zoom and pause PER CROSSING.
(defun pfxa:one (anchor xf / work recon sel)
  (pfxl:discover anchor)
  (setq work (pfa:xing-list anchor))
  (cond
    ((null work) nil)
    (T
     (setq recon (pfa:recon xf work)
           sel   (vl-remove-if
                   '(lambda (x) (cdr (assoc (pfa:xr-key x) recon)))
                   work))
     (cond
       ((null sel) nil)
       (T
        (setq *pf-zoom-to* 'OFF)      ; consumed by pf:zoom-resolve in pfxl:run
        (pfxl:run anchor xf sel)      ; the engine, unchanged; prints its own
        (length sel))))))             ; per-pass labeled/skipped line


;;; ==========================================================================
;;; SECTION 3  --  C:PFXALL
;;; ==========================================================================

;; (pfxa:cmd) -> nil   The command body, run under pf:run-command.
;;   ONE UNDO GROUP PER PROFILE, and each profile's work wrapped in
;;   vl-catch-all-apply.  Both exist for the same reason: an unexpected error
;;   anywhere in a whole-drawing sweep would otherwise reach pf:run-error,
;;   which flushes and unwinds the ONE open group -- and with a single group
;;   around the sweep that is every profile already finished.  Caught per
;;   profile, a failure costs that profile, says so by name, and the sweep
;;   carries on.  pfxl:flush-pass is called on that path for the same job it
;;   does on Esc: ledger the handles that drew before the error, inside the
;;   still-open group, so nothing is left in the drawing untracked.
;;
;;   Per-profile groups also mean U undoes one profile, not the sheet.
(defun pfxa:cmd ( / plan ok dropped row r nprof ndraw nfail)
  (setq plan    (pfxa:plan)
        ok      (car plan)
        dropped (cdr plan)
        nprof 0 ndraw 0 nfail 0)
  (prompt (strcat "\n== PFXALL: " (itoa (length ok)) " profile(s) to sweep, "
                  (itoa (length dropped)) " dropped (no usable .cl) =="))
  (foreach row dropped
    (prompt (strcat "\n  DROPPED  " (car row) "  -- " (cdr row))))
  (foreach row ok
    (prompt (strcat "\n\n-- " (caddr row) " --"))
    (pf:undo-begin '*pfxl-undo-open*)
    (setq r (vl-catch-all-apply 'pfxa:one (list (car row) (cadr row))))
    (cond
      ((vl-catch-all-error-p r)
       (setq nfail (1+ nfail))
       (pfxl:flush-pass)
       (prompt (strcat "\n  FAILED  " (caddr row) "  -- "
                       (vl-catch-all-error-message r))))
      ((null r) (prompt "\n  Nothing new to label."))
      (T (setq nprof (1+ nprof)
               ndraw (+ ndraw r))))
    (if *pfxl-undo-open* (pf:undo-end '*pfxl-undo-open*)))
  ;; A profile that failed between the setq and pf:zoom-resolve would leave the
  ;; override pending and mute the NEXT command's parade.  It is a one-shot
  ;; global; clear it on the way out rather than trusting every path.
  (setq *pf-zoom-to* nil)
  (prompt (strcat "\n\n== PFXALL complete: " (itoa ndraw)
                  " crossing(s) attempted on " (itoa nprof) " profile(s), "
                  (itoa (length dropped)) " dropped, "
                  (itoa nfail) " failed =="))
  (prompt "\n   Per-profile labeled/skipped counts are in the lines above.")
  (princ))

(defun c:PFXALL ()
  (pf:run-command "PFXALL" 'pfxl:flush-pass 'pfxa:cmd))

(defun c:PFXA () (c:PFXALL))


(princ "\npfxall.lsp loaded.  Command: PFXALL (alias PFXA).")
(princ)
;;; ==========================================================================
;;; end of pfxall.lsp
;;; ==========================================================================
