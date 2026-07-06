;;; ==========================================================================
;;; strtools-load.lsp  --  loads the structure-labeling toolset
;;; --------------------------------------------------------------------------
;;; Loads the engine and command by FULL path, so it works whether or not the
;;; folder is on AutoCAD's support search path.
;;;
;;; SET *strtools-dir* below to the folder holding these files. Use forward
;;; slashes and a trailing slash. (Alternatively, add that folder to
;;; Options > Files > Support File Search Path and the path here won't matter.)
;;; ==========================================================================

(setq *strtools-dir* "C:/Users/Guest01/Data/LIBRARY/LISP/.strlabel/V1/")

(progn
  (load (strcat *strtools-dir* "strtools-lib.lsp"))   ; engine -- loads first
  (load (strcat *strtools-dir* "strlabel.lsp"))       ; C:STRLABEL command
  (princ "\n----------------------------------------------")
  (princ "\nStructure-labeling tools loaded.")
  (princ "\n  Command:  STRLABEL")
  (princ "\n----------------------------------------------")
  (princ))
