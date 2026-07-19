;;; ==========================================================================
;;; pftools-load.lsp  --  loads the PFTools V4 suite
;;; --------------------------------------------------------------------------
;;; Loads by FULL path in dependency order.  Each file may only depend on
;;; files above it (the V4 guardrail):
;;;
;;;   cfg -> lib -> draw -> anchor -> settings -> setup -> label -> xlabel
;;;   -> invert  (pfinvert reuses pflabel's walk + pfxlabel's registry
;;;   resolution, so it loads last)
;;;
;;; SET *pftools-dir* below to the folder holding these files.  Forward
;;; slashes, trailing slash.
;;;
;;; RETIRED from the load (v3 files kept in _v3\ for reference):
;;;   pfdialog.lsp  -- split into pfsettings.lsp + per-command wiring
;;;   pfcross.lsp   -- SUPERSEDED by pfxlabel.lsp (target-only, .pro-driven
;;;                    inverts; the v3 vertical bore probe is gone).  v3 copy
;;;                    kept in _v3\ for reference only.
;;; ==========================================================================

(setq *pftools-dir* "C:/Users/Guest01/Data/LIBRARY/LISP/.strlabel/V4/")

(progn
  (load (strcat *pftools-dir* "pftools-cfg.lsp"))   ; constants      -- first
  (load (strcat *pftools-dir* "pftools-lib.lsp"))   ; pure engine
  (load (strcat *pftools-dir* "pfdraw.lsp"))        ; drawing boundary
  (load (strcat *pftools-dir* "pfanchor.lsp"))      ; record + registry
  (load (strcat *pftools-dir* "pfsettings.lsp"))    ; user state + NOD
  (load (strcat *pftools-dir* "pfsetup.lsp"))       ; C:PFSETUP
  (load (strcat *pftools-dir* "pflabel.lsp"))       ; C:PFLABEL
  (load (strcat *pftools-dir* "pfxlabel.lsp"))      ; C:PFXLABEL
  (load (strcat *pftools-dir* "pfinvert.lsp"))      ; C:PFINVERT
  (princ "\n----------------------------------------------")
  (princ "\nPFTools V4 loaded.")
  (princ "\n  Grid records:      PFSETUP (register/edit), PFREMOVE (teardown)")
  (princ "\n  Structure labels:  PFLABEL  (alias PFL)")
  (princ "\n  Crossings:         PFXLABEL (alias PFX)")
  (princ "\n  Inverts:           PFINVERT (alias PFI)")
  (princ "\n  Settings:          PFLABELSET, PFROOT (project data root)")
  (princ "\n  Coming this cycle: PFCHECK")
  (princ "\n----------------------------------------------")
  (princ))
