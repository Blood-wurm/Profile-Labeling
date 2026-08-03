;;; ==========================================================================
;;; pfp-proof.lsp  --  PHASE 1: prove the deferred fire.  TEMPORARY.
;;; --------------------------------------------------------------------------
;;; NOT loaded by pftools-load.lsp.  Load it by hand AFTER the suite:
;;;
;;;     (load (strcat *pftools-dir* "pfpalette/pfp-proof.lsp"))
;;;
;;; WHAT IT PROVES
;;;   A modeless OpenDCL handler cannot call (command), (entsel) or (getpoint),
;;;   so every palette verb has to QUEUE a real command instead of doing the
;;;   work itself.  This fires vla-SendCommand and checks that what lands on
;;;   the other side is a real command context.
;;;
;;;   Phase 1 PASSED.  The channel itself now ships in pfpalette.lsp SECTION 2;
;;;   what is left here is the exercise (Sections 2/3) and the lifecycle
;;;   handlers (Section 4, still open).
;;;
;;;   Tests [1] and [2] were the palette-click half and cannot be re-run from a
;;;   keyboard -- btnHelp is real Help now.  [3]-[5] still run and still answer
;;;   the question that matters on a re-run.
;;;
;;; HOW TO RUN
;;;   1. Open a drawing.  Load the suite, then load this file.
;;;   2. PFPTEST at the command line.  Answer the one point prompt.
;;;   3. Read the [3]-[5] lines.
;;;   4. Type U once.  The proof line must vanish in ONE undo step.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfpt-sent*))   (setq *pfpt-sent*   nil)) ; click -> send stamp
(if (not (boundp '*pfpt-ent*))    (setq *pfpt-ent*    nil)) ; the line we drew
(if (not (boundp '*pfpt-undo-open*)) (setq *pfpt-undo-open* nil))
(if (not (boundp '*pfp-was-open*))   (setq *pfp-was-open*   nil)) ; SURVIVES (S4)


;;; ==========================================================================
;;; SECTION 1  --  The defer channel  --  PROMOTED, NO LONGER HERE
;;; ==========================================================================
;;; pfp:cmd-idle-p and pfp:defer live in pfpalette.lsp SECTION 2, which loads
;;; before this file.  Deliberately not duplicated: two copies of the gate would
;;; let the proof pass against a definition the palette does not use.


;;; ==========================================================================
;;; SECTION 2  --  The palette side  --  RETIRED, NO LONGER HERE
;;; ==========================================================================
;;; btnHelp#OnClicked fired tests [1] and [2]; both passed, and the handler was
;;; deleted when btnHelp became real Help.  The suite may hold exactly one defun
;;; of that name, and pfpalette.lsp SECTION 10 is now it.
;;; Re-proving [1] and [2] needs a click, so it needs a spare wired control.
;;; There isn't one, and inventing one costs a Studio round trip.


;;; ==========================================================================
;;; SECTION 3  --  The command side: what the defer lands in
;;; ==========================================================================

;; (pfpt:body) -> nil   Runs under pf:run-command, i.e. the real wrapper the
;;   deferred C:PF*RUN commands will use.
(defun pfpt:body ( / before pt)
  (prompt (strcat "\n[command] CMDACTIVE=" (itoa (getvar "CMDACTIVE"))
                  "  CMDNAMES=\"" (getvar "CMDNAMES") "\""))
  (prompt (if *pfpt-sent*
            "\n  [3] PASS  arrived from the palette click, not the keyboard."
            "\n  [3] ----  run directly (no palette click) -- context test only."))

  ;; TEST 4 -- (command) must draw here.  One undo group, so a single U
  ;; peels the whole proof (the pf:undo-begin/end pattern every verb uses).
  (setq before (entlast))
  (pf:undo-begin '*pfpt-undo-open*)
  (command "._LINE" '(0.0 0.0 0.0) '(120.0 90.0 0.0) "")
  (pf:undo-end '*pfpt-undo-open*)
  (setq *pfpt-ent* (entlast))
  (prompt (if (equal before *pfpt-ent*)
            "\n  [4] FAIL  (command) drew nothing in the deferred context."
            "\n  [4] PASS  (command) drew inside one undo group -- type U once to verify."))

  ;; TEST 5 -- interactive input.  getpoint is illegal modeless; if it
  ;; returns here, this is unambiguously a real command context.
  (setq pt (getpoint "\n  [5] Pick any point to prove interactive input: "))
  (prompt (if pt
            "\n  [5] PASS  getpoint returned -- real command context confirmed."
            "\n  [5] ----  getpoint cancelled (Esc) -- inconclusive, re-run."))

  ;; The "hand the palette back" step was a SetEnabled on btnHelp.  Gone with
  ;; the handler -- this file must not touch a control it no longer owns.
  (setq *pfpt-sent* nil)
  (prompt "\n=== end of proof ===")
  (princ))

;; The deferred target.  Same shape as the C:PF*RUN commands Phase 2 adds:
;; a thin command that reads state and calls a body under pf:run-command.
(defun c:PFPTEST ()
  (pf:run-command "PFPTEST" nil 'pfpt:body))

;; Clear the proof's state after an error left it half-set.  It does not
;; re-enable btnHelp: that button belongs to Help now.
(defun c:PFPTESTRESET ()
  (setq *pfpt-sent* nil *pfpt-undo-open* nil)
  (prompt "\nPFPTESTRESET: proof state cleared.")
  (princ))


;;; ==========================================================================
;;; SECTION 4  --  Lifecycle  (Phase 5 brought forward; THESE TWO SURVIVE)
;;; ==========================================================================
;;; Tick "DocActivated" and "EnteringNoDocState" on pfsPalette (form level, not
;;; a control) while you are in Studio.
;;;
;;; STILL OPEN, and the blocker is NAMESPACE, not form state.  AutoLISP
;;; namespaces are per-document, so these defuns exist only where
;;; pftools-load.lsp ran -- the event DOES fire on the incoming document, and
;;; the handler is not there to receive it.  Activating into an unloaded drawing
;;; therefore throws a visible error rather than being silent.
;;;
;;; Neither dcl-Form-Hide nor a vlr-docmanager-reactor fixes a handler that does
;;; not exist in the document being activated into.  The candidate fix is
;;; per-document autoload (acaddoc.lsp), deferred behind Phase 2.  Until then
;;; these two handlers are EXERCISE-ONLY -- do not ship them as the fix.

;; DocActivated -> the drawing-switch refresh signal (root README 4a).
;;   pfp:refresh is already vl-catch-all-apply wrapped, so a hostile drawing
;;   cannot take the palette down from here.
(defun c:pfsuite/pfsPalette#OnDocActivated ( / )
  (prompt (strcat "\n[lifecycle] OnDocActivated -- doc \""
                  (getvar "DWGNAME") "\""))
  (if *pfp-was-open*
    (progn
      (setq *pfp-was-open* nil)
      (prompt "\n  [L3] PASS  fired on a CLOSED form -- re-showing.")
      (vl-catch-all-apply
        '(lambda () (dcl-Form-Show pfsuite/pfsPalette)) '())))
  (pfp:refresh)
  (princ))

;; EnteringNoDocState -> the start-screen fix.  Remember that we were open so
;;   DocActivated can put it back, the way native palettes behave.
(defun c:pfsuite/pfsPalette#OnEnteringNoDocState ( / )
  (prompt "\n[lifecycle] OnEnteringNoDocState -- closing the palette.")
  (setq *pfp-was-open* T)
  (vl-catch-all-apply
    '(lambda () (dcl-Form-Close pfsuite/pfsPalette)) '())
  (princ))


(princ "\npfp-proof.lsp loaded (PHASE 1, TEMPORARY).")
(princ "\n  Studio: tick pfsPalette \"DocActivated\" and")
(princ "\n          \"EnteringNoDocState\".  Then PFPALETTE.")
(princ "\n  Defer test:     PFPTEST, read [3]-[5], then type U once.")
(princ "\n                  ([1]/[2] retired with btnHelp -- it is Help now.)")
(princ "\n  Lifecycle test: L1 switch drawings, L2 close all, L3 reopen one.")
(princ)
;;; ==========================================================================
;;; end of pfp-proof.lsp
;;; ==========================================================================
