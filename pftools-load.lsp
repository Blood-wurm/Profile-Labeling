;;; ==========================================================================
;;; pftools-load.lsp  --  loads the PFTools V5 suite (self-contained copy)
;;; --------------------------------------------------------------------------
;;; Loads by FULL path in dependency order.  Each file may only depend on files
;;; above it (the load-order guardrail):
;;;
;;;   cfg -> lib -> draw -> anchor -> settings -> setup -> pro -> label ->
;;;   xlabel -> xall -> invert -> report -> 2sew -> qty -> palette
;;;
;;; pfxall is the batch form of pfxlabel and drives pfxl:run unchanged, so it
;;; sits directly below it and nothing else depends on it.
;;;
;;; pfpro needs only lib + anchor + settings and nothing draws it, so it sits
;;; above the label engines; pfinvert reuses pflabel's walk and pfxlabel's
;;; registry resolution; pfreport reuses all three.  pf2sew and pfqty both
;;; reuse pfreport's gather and neither depends on the other, so their order
;;; between report and palette is free.
;;;
;;; SET *pftools-dir* below to the pfsuite ROOT -- each .lsp lives in its own
;;; subfolder with a README.md beside it, and the loader adds the subfolder
;;; segment.  Forward slashes, trailing slash.
;;; ==========================================================================

;; Points at THIS folder.  Set to wherever it is deployed -- must match the
;; actual install path (still hardcoded; the known open issue).
(setq *pftools-dir* "C:/Users/Guest01/Data/LIBRARY/LISP/.strlabel/V5/pfsuite/")

(progn
  (load (strcat *pftools-dir* "pftools-cfg/pftools-cfg.lsp"))   ; constants      -- first
  (load (strcat *pftools-dir* "pftools-lib/pftools-lib.lsp"))   ; pure engine
  (load (strcat *pftools-dir* "pfdraw/pfdraw.lsp"))             ; drawing boundary
  (load (strcat *pftools-dir* "pfanchor/pfanchor.lsp"))         ; record + registry
  (load (strcat *pftools-dir* "pfsettings/pfsettings.lsp"))     ; user state + NOD
  (load (strcat *pftools-dir* "pfsetup/pfsetup.lsp"))           ; C:PFSETUP
  (load (strcat *pftools-dir* "pfpro/pfpro.lsp"))               ; C:PFPROINV/TOP
  (load (strcat *pftools-dir* "pflabel/pflabel.lsp"))           ; C:PFLABEL
  (load (strcat *pftools-dir* "pfxlabel/pfxlabel.lsp"))         ; C:PFXLABEL
  (load (strcat *pftools-dir* "pfxall/pfxall.lsp"))             ; C:PFXALL
  (load (strcat *pftools-dir* "pfinvert/pfinvert.lsp"))         ; C:PFINVERT
  (load (strcat *pftools-dir* "pfreport/pfreport.lsp"))         ; C:PFREPORT
  (load (strcat *pftools-dir* "pf2sew/pf2sew.lsp"))             ; C:PF2SEW
  (load (strcat *pftools-dir* "pfqty/pfqty.lsp"))               ; C:PFQTY
  (load (strcat *pftools-dir* "pfpalette/pfpalette.lsp"))       ; C:PFPALETTE  -- last
  (princ "\n----------------------------------------------")
  (princ "\nPFTools V5 loaded.")
  (princ "\n  Grid records:      PFSETUP (register/edit), PFREMOVE (teardown)")
  (princ "\n  Cut a .pro:        PFPROINV / PFPROTOP")
  (princ "\n  Structure labels:  PFLABEL  (alias PFL)")
  (princ "\n  Crossings:         PFXLABEL (alias PFX)")
  (princ "\n  Crossings, all:    PFXALL   (alias PFXA) -- every profile, no dialog")
  (princ "\n  Inverts:           PFINVERT (alias PFI)")
  (princ "\n  Hydraflow export:  PFREPORT (alias PFR)  -- .stm, system-scoped")
  (princ "\n  Quantities:        PFQTY    (alias PFQ)  -- .txt takeoff")
  (princ "\n  Settings:          PFLABELSET   (project root: native tmpdir$)")
  (princ "\n  Palette:           PFPALETTE    (V5 read-only, milestone 2)")
  (princ "\n----------------------------------------------")
  (princ))
