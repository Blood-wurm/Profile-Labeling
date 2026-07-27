;;; pfdump.lsp -- one-shot diagnostic for the AUTO name-scan skip.
;;; Dumps the EXACT bytes of DXF group 1 for a picked PF-NAME text, so we can
;;; see which character is standing in for the delimiter.  Throwaway; not part
;;; of the suite.  APPLOAD this after the suite is loaded, then run PFDUMP.

(defun c:PFDUMP ( / e ed s ty nm codes line)
  (setq e (car (entsel "\nPick the PF-NAME text that got skipped: ")))
  (if (null e)
    (prompt "\nNothing picked.")
    (progn
      (setq ed (entget e)
            s  (cdr (assoc 1 ed)))

      (prompt (strcat "\n  Entity type : " (cdr (assoc 0 ed))))
      (prompt (strcat "\n  Layer       : " (cdr (assoc 8 ed))))
      (prompt (strcat "\n  Group 1 raw : [" (if s s "<none>") "]"))

      ;; MTEXT longer than 250 chars keeps earlier chunks in group 3.  The
      ;; scanner reads group 1 only, so flag it if chunks exist.
      (if (assoc 3 ed)
        (prompt "\n  *** MTEXT has group-3 chunks -- group 1 is only the TAIL. ***"))

      (if s
        (progn
          (prompt (strcat "\n  Length      : " (itoa (strlen s))))
          (setq codes (vl-string->list s) line "")
          (foreach c codes
            (setq line (strcat line (itoa c) " ")))
          (prompt (strcat "\n  Char codes  : " line))

          ;; what the scanner actually concludes
          (setq ty (pf:sheet-type s))
          (prompt (strcat "\n  sheet-type  : " (if ty ty "nil")))
          (setq nm (if ty (pf:parse-sheet-name s ty)))
          (prompt (strcat "\n  parsed name : " (if nm nm "nil  <-- the skip")))

          ;; delimiter forensics
          (prompt "\n  Delimiters found:")
          (if (vl-string-search "'"  s) (prompt "\n    39    ' straight apostrophe  (EXPECTED)"))
          (if (vl-string-search "`"  s) (prompt "\n    96    ` backtick             (rejected)"))
          (if (vl-string-search "\"" s) (prompt "\n    34    \" straight double      (rejected)"))
          (if (vl-string-search "\\" s) (prompt "\n    92    \\ backslash -- text may hold a \\U+XXXX escape (rejected)"))
          (if (member 8216 codes) (prompt "\n    8216  left curly single      (rejected)"))
          (if (member 8217 codes) (prompt "\n    8217  right curly single     (rejected)"))
          (if (member 8220 codes) (prompt "\n    8220  left curly double      (rejected)"))
          (if (member 8221 codes) (prompt "\n    8221  right curly double     (rejected)"))
          (if (member 180  codes) (prompt "\n    180   acute accent           (rejected)"))
          (if (member 145  codes) (prompt "\n    145   cp1252 left curly      (rejected)"))
          (if (member 146  codes) (prompt "\n    146   cp1252 right curly     (rejected)"))))))
  (princ))

(prompt "\nPFDUMP loaded -- run PFDUMP and pick the skipped text.")
(princ)