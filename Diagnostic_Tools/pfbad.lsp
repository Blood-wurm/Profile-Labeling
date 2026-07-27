;;; pfbad.lsp -- list EVERY PF-NAME text and how the AUTO scan reads it.
;;; Same ssget filter and same parse calls pfs:scan-sheet-names uses, so what
;;; this prints is exactly what AUTO sees.  Leaves the unreadable ones in the
;;; active selection so they can be zoomed to.  Throwaway; read-only.

(defun c:PFBAD ( / ss i e ed s ty nm bad hnd)
  (setq ss  (ssget "_X" (list '(0 . "TEXT,MTEXT")
                              (cons 8 *pfg-name-layer*)
                              '(410 . "Model")))
        bad (ssadd)
        i   0)
  (if (null ss)
    (prompt (strcat "\nNo TEXT/MTEXT on layer " *pfg-name-layer* "."))
    (progn
      (prompt (strcat "\n" (itoa (sslength ss)) " PF-NAME text(s) on layer "
                      *pfg-name-layer* ":"))
      (while (< i (sslength ss))
        (setq e   (ssname ss i)
              ed  (entget e)
              s   (cdr (assoc 1 ed))
              hnd (cdr (assoc 5 ed))
              ty  (if s (pf:sheet-type s))
              nm  (if ty (pf:parse-sheet-name s ty)))
        (cond
          ((and ty nm)
           (prompt (strcat "\n  OK   <" hnd ">  " ty " '" nm "'"
                           (if (pfa:find-anchor nm ty)   "  [ANCHORED]"
                             (if (pfa:stub-get ty nm)    "  [stub]"
                                                         "  [NOT registered]"))
                           "   raw=[" s "]")))
          (ty
           (ssadd e bad)
           (prompt (strcat "\n  BAD  <" hnd ">  " ty
                           " -- name unreadable   raw=[" s "]")))
          (T
           (prompt (strcat "\n  --   <" hnd
                           ">  no utility type in text   raw=[" s "]"))))
        (if (assoc 3 ed)
          (prompt "\n       *** MTEXT group-3 chunks: AUTO reads the TAIL only ***"))
        (setq i (1+ i)))

      (if (> (sslength bad) 0)
        (progn
          (sssetfirst nil bad)
          (prompt (strcat "\n\n" (itoa (sslength bad))
                          " unreadable text(s) are now SELECTED -- zoom to"
                          " them, then fix or delete.")))
        (prompt "\n\nEvery PF-NAME text on this sheet parses."))))
  (princ))

(prompt "\nPFBAD loaded -- run PFBAD.")
(princ)
