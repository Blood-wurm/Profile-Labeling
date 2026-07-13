;;; ==========================================================================
;;; pftools-load.lsp  --  loads the profile-labeling toolset
;;; --------------------------------------------------------------------------
;;; Loads the engine, dialog, and command by FULL path, so it works whether or
;;; not the folder is on AutoCAD's support search path.
;;;
;;; SET *pftools-dir* below to the folder holding these files. Use forward
;;; slashes and a trailing slash. (Alternatively, add that folder to
;;; Options > Files > Support File Search Path and the path here won't matter.)
;;; ==========================================================================

(setq *pftools-dir* "C:/Users/Guest01/Data/LIBRARY/LISP/.strlabel/V3/")

(progn
  (load (strcat *pftools-dir* "pftools-lib.lsp"))   ; engine   -- loads first
  (load (strcat *pftools-dir* "pfdialog.lsp"))      ; settings + data dialogs
  (load (strcat *pftools-dir* "pflabel.lsp"))       ; C:PFLABEL command
  (load (strcat *pftools-dir* "pfcross.lsp"))       ; C:PFXFIND + C:PFXLABEL
  (princ "\n----------------------------------------------")
  (princ "\nProfile-labeling tools loaded.")
  (princ "\n  Command:  PFLABEL   (alias PFL)")
  (princ "\n----------------------------------------------")
  (princ))
