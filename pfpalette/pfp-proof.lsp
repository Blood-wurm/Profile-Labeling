;;; ==========================================================================
;;; pfp-proof.lsp  --  PHASE 1: prove the deferred fire.  TEMPORARY.
;;; --------------------------------------------------------------------------
;;; NOT loaded by pftools-load.lsp.  Load it by hand AFTER the suite:
;;;
;;;     (load (strcat *pftools-dir* "pfpalette/pfp-proof.lsp"))
;;;
;;; DELETE THIS FILE once Phase 1 passes.  Section 1 is the only part that
;;; survives -- it gets promoted into pfpalette.lsp as the real defer channel.
;;;
;;; WHAT IT PROVES
;;;   A modeless OpenDCL handler cannot call (command), (entsel) or (getpoint)
;;;   -- root README 5.  Every palette verb therefore has to QUEUE a real
;;;   command instead of doing the work itself.  vla-SendCommand is the
;;;   candidate mechanism.  This file fires it from a genuine palette click
;;;   and checks that what lands on the other side is a real command context.
;;;
;;; ONE STUDIO STEP FIRST
;;;   btnHelp is the trigger (form-level, unwired, visible on every tab -- so
;;;   no new control is needed).  Select btnHelp in Studio, open its Events
;;;   tab, and tick "Clicked".  A handler with the event unticked never fires.
;;;
;;; HOW TO RUN
;;;   1. Open a drawing.  Load the suite, then load this file.
;;;   2. PFPALETTE to show the palette.
;;;   3. Click Help.  Answer the one point prompt when asked.
;;;   4. Read the five PASS/FAIL lines.
;;;   5. Type U once.  The proof line must vanish in ONE undo step.
;;;   6. PFPTESTRESET if the Help button is left disabled by an error.
;;; ==========================================================================

(vl-load-com)

(if (not (boundp '*pfpt-sent*))   (setq *pfpt-sent*   nil)) ; click -> send stamp
(if (not (boundp '*pfpt-ent*))    (setq *pfpt-ent*    nil)) ; the line we drew
(if (not (boundp '*pfpt-undo-open*)) (setq *pfpt-undo-open* nil))
(if (not (boundp '*pfp-was-open*))   (setq *pfp-was-open*   nil)) ; SURVIVES (S4)


;;; ==========================================================================
;;; SECTION 1  --  The defer channel  (THE PART THAT SURVIVES)
;;; ==========================================================================
;;; Promote this section into pfpalette.lsp once the proof passes.  Every
;;; palette verb -- the Registry dispatcher, btnRun on the Commands tab --
;;; goes through pfp:defer and nothing else.

;; (pfp:cmd-idle-p) -> T | nil
;;   The gate root README 5 requires before ANY palette-initiated write.
;;   CMDACTIVE alone is not enough: a dialog or a grip edit can leave
;;   CMDNAMES populated with CMDACTIVE at 0.
(defun pfp:cmd-idle-p ()
  (and (= 0 (getvar "CMDACTIVE"))
       (= "" (getvar "CMDNAMES"))))

;; (pfp:defer cmdline) -> T | nil
;;   Queue a command from a modeless handler.  SendCommand returns
;;   immediately -- the command runs after the handler unwinds, in a real
;;   command context.  The trailing newline is what executes it; without it
;;   the text sits on the command line unexecuted.
;;   Refuses (and says so) when the command line is busy, rather than
;;   stacking input behind whatever is already running.
(defun pfp:defer (cmdline / doc)
  (cond
    ((not (pfp:cmd-idle-p))
     (prompt (strcat "\nPFPALETTE: command line busy (" (getvar "CMDNAMES")
                     ") -- finish it and try again."))
     nil)
    (T
     (setq doc (vla-get-ActiveDocument (vlax-get-acad-object)))
     (vla-SendCommand doc (strcat cmdline "\n"))
     T)))


;;; ==========================================================================
;;; SECTION 2  --  The palette side: a modeless handler that defers
;;; ==========================================================================

;; Handler naming follows the working convention (tvwLines#OnSelChanged):
;; path segments with "/", event with "#".
;;   Disabling the button before the send is the "palette disabled while a
;;   command runs" rule from root README 5.  C:PFPTEST re-enables it.
(defun c:pfsuite/pfsPalette/btnHelp#OnClicked ( / )
  (prompt "\n=== PHASE 1 deferred-fire proof ===")
  (prompt (strcat "\n[handler] CMDACTIVE=" (itoa (getvar "CMDACTIVE"))
                  "  CMDNAMES=\"" (getvar "CMDNAMES") "\""))
  ;; TEST 1 -- the negative control.  This (command) call is issued from a
  ;; modeless handler and MUST fail to draw.  If a circle appears, the
  ;; modeless restriction is not what we think it is and the whole
  ;; defer design needs revisiting.
  (setq *pfpt-ent* (entlast))
  (vl-catch-all-apply '(lambda () (command "._CIRCLE" '(0.0 0.0 0.0) 1.0)) '())
  (prompt (if (equal *pfpt-ent* (entlast))
            "\n  [1] PASS  (command) from the handler drew nothing, as expected."
            "\n  [1] FAIL  (command) DREW from a modeless handler -- investigate."))
  ;; Now the real thing: queue a command instead of running one.
  (setq *pfpt-sent* T)
  (vl-catch-all-apply
    '(lambda () (dcl-Control-SetEnabled pfsuite/pfsPalette/btnHelp nil)) '())
  (if (pfp:defer "PFPTEST")
    (prompt "\n  [2] SENT  PFPTEST queued -- watch for its report below.")
    (prompt "\n  [2] FAIL  pfp:defer refused (command line busy)."))
  (princ))


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

  ;; Hand the palette back.  Proves the command side can talk to the form.
  (vl-catch-all-apply
    '(lambda () (dcl-Control-SetEnabled pfsuite/pfsPalette/btnHelp T)) '())
  (setq *pfpt-sent* nil)
  (prompt "\n=== end of proof ===")
  (princ))

;; The deferred target.  Same shape as the C:PF*RUN commands Phase 2 adds:
;; a thin command that reads state and calls a body under pf:run-command.
(defun c:PFPTEST ()
  (pf:run-command "PFPTEST" nil 'pfpt:body))

;; Re-enable the Help button if an error left it disabled.
(defun c:PFPTESTRESET ()
  (vl-catch-all-apply
    '(lambda () (dcl-Control-SetEnabled pfsuite/pfsPalette/btnHelp T)) '())
  (setq *pfpt-sent* nil *pfpt-undo-open* nil)
  (prompt "\nPFPTESTRESET: Help button re-enabled.")
  (princ))


;;; ==========================================================================
;;; SECTION 4  --  Lifecycle  (Phase 5 brought forward; THESE TWO SURVIVE)
;;; ==========================================================================
;;; Tick "DocActivated" and "EnteringNoDocState" on pfsPalette (form level,
;;; not a control) while you are in Studio for btnHelp.
;;;
;;; THE OPEN QUESTION these answer:
;;;   EnteringNoDocState closing the palette is the start-screen fix.  But a
;;;   CLOSED form may not receive events at all -- if so, nothing can reopen
;;;   it when a drawing comes back, and the palette stays dead until someone
;;;   types PFPALETTE.  That is worse than the stale-data behaviour we have
;;;   now.  Test L3 below is the whole point of this section.
;;;
;;;   If L3 fails, the fallbacks are (a) dcl-Form-Hide instead of Close --
;;;   unattested in the samples, so it needs its own check -- or (b) a
;;;   vlr-docmanager-reactor, which lives outside the form and always fires.

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
(princ "\n  Studio: tick btnHelp \"Clicked\"; tick pfsPalette \"DocActivated\"")
(princ "\n          and \"EnteringNoDocState\".  Then PFPALETTE.")
(princ "\n  Defer test:     click Help, read [1]-[5], then type U once.")
(princ "\n  Lifecycle test: L1 switch drawings, L2 close all, L3 reopen one.")
(princ)
;;; ==========================================================================
;;; end of pfp-proof.lsp
;;; ==========================================================================
