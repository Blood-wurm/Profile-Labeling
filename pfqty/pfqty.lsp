;;; ==========================================================================
;;; pfqty.lsp  --  C:PFQTY : material quantities takeoff (.txt)
;;;                Dialog: pfqty_run.
;;; Load position 13 of 14: after pf2sew, before pfpalette.
;;; Model, API, and invariants: see README.md beside this file.
;;;
;;; SYSTEM-scoped and READ-ONLY on the drawing, like PFREPORT -- the .txt is
;;; the only write, so no undo group, no pass ledger, no STATUS update.
;;;
;;; THREE DELIBERATE DIFFERENCES from PFREPORT, all of them the same point:
;;; a takeoff is not a hydraulic model.
;;;   1. NO GRAPH.  No outfall rule, no ordering, no connectivity validation.
;;;      Four disconnected lines are a legitimate takeoff.
;;;   2. STUBS COUNT.  PFREPORT excludes them because a stub has no grid and
;;;      therefore no rim elevations to read; quantities read no rims.
;;;   3. NO RIM READS.  Which also keeps this command clear of PFLABEL's
;;;      dropped-structure bug (OPEN-ISSUES) -- there is no elevation row to
;;;      be missing.
;;;
;;; It reuses pfreport's decomposition (pfr:groups), its structure lookups
;;; (pfr:struct-at / pfr:struct-id), its plan read (pfr:xy), its alist
;;; accessors (pfr:g / pfr:p / pfr:set-nth), its node matcher (pfr:node-index),
;;; its line table and its findings machinery.  What it does NOT reuse is
;;; pfr:node-of / pfr:line-pipes, which read rims: the two short replacements
;;; below are that path minus the rim.  When the pf2sew.md section 8 step 1
;;; gather hoist happens, all three collapse into one pf: engine walk.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Structure identity  (THE SEAM)
;;; ==========================================================================
;;; Type and size are resolved ATTRIBUTE FIRST.  Nothing in the drawing carries
;;; *pfq-attr-type* / *pfq-attr-size* today, so every lookup falls through to
;;; *pf-rule-table* -- but the day the firm's blocks are retagged, or a block
;;; is hard-coded with those attributes, the report starts reading them with no
;;; code change.  That is the whole reason this is a function and not an inline
;;; (pf:rule-type (pf:rule-for ...)).

;; (pfq:str v) -> v if it is a non-empty string, else nil
;;   EVERY value this report reads out of a drawing record goes through here
;;   before it reaches strcase, strcat or /=, all three of which hard-error on
;;   a non-string in AutoLISP rather than returning nil.  A takeoff must never
;;   abort because a record holds something unexpected -- the whole contract is
;;   that a gap SHOWS UP on the sheet, as UNSPECIFIED / UNKNOWN / UNIDENTIFIED.
(defun pfq:str (v) (if (and v (eq (type v) 'STR) (/= v "")) v))

;; (pfq:text v) -> a printable string for ANY value
;;   Sort keys and report cells are DERIVED strings.  Building them with strcat
;;   over data that might not be a string is what turned one odd record into an
;;   aborted report; vl-princ-to-string accepts anything, so a value nobody
;;   expected prints itself in the column instead of killing the run.  That is
;;   strictly better than a guard: the report becomes its own diagnosis.
(defun pfq:text (v) (if (pfq:str v) v (vl-princ-to-string v)))

;; (pfq:safe fn args why) -> the call's value, or nil after a named warning
;;   ONE structure's identity must never be able to kill a whole takeoff --
;;   the same reason pfa:memb-sync is catch-wrapped.  The warning carries the
;;   station, the block name, the STAGE and AutoLISP's own message, so the
;;   REPORT says which call failed on which record.  A diagnosis that arrives
;;   in the deliverable costs nobody a CAD session; one that needs a
;;   command-line probe costs one, and can strand the session at (_>.
(defun pfq:safe (fn args why / r)
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r)
    (progn
      (pfr:warn (strcat why " -- " (vl-catch-all-error-message r)))
      nil)
    r))

;; (pfq:attr ename tag) -> the attribute's value | nil
;;   Case-insensitive tag match over the INSERT's ATTRIB sub-entities.  An
;;   empty value reads as absent -- an unfilled attribute is not an assertion.
(defun pfq:attr (ename tag / has e ed val up)
  (setq up  (if (pfq:str tag) (strcase tag))
        val nil)
  (if (and ename up)
    (progn
      (setq has (cdr (assoc 66 (entget ename))))
      (if (and has (= has 1))
        (progn
          (setq e (entnext ename))
          (while (and e
                      (setq ed (entget e))
                      (/= (cdr (assoc 0 ed)) "SEQEND"))
            (if (and (= (cdr (assoc 0 ed)) "ATTRIB")
                     (pfq:str (cdr (assoc 2 ed)))
                     (= (strcase (cdr (assoc 2 ed))) up))
              (setq val (cdr (assoc 1 ed))))
            (setq e (entnext e)))))))
  (pfq:str val))

;; (pfq:struct-info st) -> (type . size)   st = pfr:struct-at's (sta ename blk)
;;   size stays nil unless something ASSERTS one; the report prints
;;   *pfq-size-unknown* rather than inventing a diameter.  A group with no
;;   block within a structure width is *pfq-struct-unknown* -- it is still a
;;   structure (the .pro says so), it just has no identity yet.
;;   Every sub-call is staged through pfq:safe under its own label, so a
;;   failure names the CALL, not just the structure.  Cheap insurance on a
;;   path that reads four different records through three other modules.
(defun pfq:struct-info (st / e blk rule ty sz w)
  (if (null st)
    (cons *pfq-struct-unknown* nil)
    (progn
      (setq e    (cadr st)
            blk  (pfq:str (caddr st))
            w    (strcat "block " (if blk blk "(unnamed)"))
            rule (if blk
                   (pfq:safe 'pf:rule-for (list blk *pf-rule-table*)
                             (strcat w ": stage RULE")))
            ty   (cond
                   ((pfq:safe 'pfq:attr (list e *pfq-attr-type*)
                              (strcat w ": stage ATTR-TYPE")))
                   ((and rule
                         (pfq:str (pfq:safe 'pf:rule-type (list rule)
                                            (strcat w ": stage RULE-TYPE")))))
                   (blk)
                   (T *pfq-struct-unknown*))
            sz   (cond
                   ((pfq:safe 'pfq:attr (list e *pfq-attr-size*)
                              (strcat w ": stage ATTR-SIZE")))
                   ((and blk rule
                         (pfq:str (pfq:safe 'pf:rule-size (list blk rule)
                                            (strcat w ": stage RULE-SIZE")))))))
      (cons (if (pfq:str ty) (strcase ty) *pfq-struct-unknown*) sz))))


;;; ==========================================================================
;;; SECTION 2  --  One profile -> its pipes
;;; ==========================================================================
;;; PFINVERT's vertex bracket through pfr:groups: every _INV.pro vertex is an
;;; invert, adjacent vertices within *pfi-struct-width-max* are ONE structure,
;;; and the gaps between the groups are the pipes.
;;;
;;; LENGTH IS OUT TO OUT OF THE STRUCTURES: a pipe spans from the outside wall
;;; of one structure to the outside wall of the next, which is exactly the two
;;; .pro vertices bracketing the gap.  Structures therefore contribute no LF at
;;; all, which is what makes the per-line subtotals add up to the grand total
;;; with no adjustment for shared junctions.  It is the along-alignment length
;;; (the station difference), not the slope distance -- same figure PFREPORT
;;; writes as Line Length, and the convention a plan quantity is measured in.

;; (pfq:node-of grp clfile pending lines index) -> node alist
;;   pfr:node-of minus the rim.  Node identity is unchanged -- the structure's
;;   CENTRE station and the plan point there -- so pfq:build-nodes merges a
;;   shared junction on exactly the coincidence rule the .stm graph uses.
;;   Both identity reads are catch-wrapped: a structure whose type or ID cannot
;;   be resolved still counts as a structure (the .pro says it is there), it
;;   just counts as UNIDENTIFIED and says why.
(defun pfq:node-of (grp clfile pending lines index / mid xy st bn info id where)
  (setq mid   (pfr:grp-mid grp)
        xy    (if clfile (pfr:xy clfile mid))
        st    (pfr:struct-at pending mid)
        bn    (if st (pfq:str (caddr st)))
        where (strcat "Sta " (pf:fmt-station mid)
                      (if bn (strcat " (block " bn ")") ""))
        info  (pfq:safe 'pfq:struct-info (list st)
                        (strcat where ": structure type/size unreadable"))
        id    (if st
                (pfq:safe 'pfr:struct-id (list (cadr st) lines index)
                          (strcat where ": structure ID could not be composed"))))
  (list (cons 'sta mid)
        (cons 'xy  xy)
        (cons 'id  (if (pfq:str id) id ""))
        (cons 'blk bn)
        (cons 'ent (if st (cadr st)))     ; node identity -- pfr:node-index
        (cons 'sty (if info (car info) *pfq-struct-unknown*))
        (cons 'ssz (if info (cdr info)))))

;; (pfq:line-pipes r lines index inlets) -> list of pipe records | nil
;;   A missing or unreadable .cl is a WARNING here, not the fatal it is in
;;   PFREPORT: lengths and structure stations both come off the _INV .pro, so
;;   the only thing lost is the plan coincidence that merges a junction shared
;;   with another selected line.  Since 2026-08-05 that fallback is second:
;;   a junction WITH a structure block still merges on identity, so the double
;;   count is now confined to a shared node that has no block at all.  Named on
;;   the command line either way -- not a wrong quantity.
(defun pfq:line-pipes (r lines index inlets
                       / name ty clfile sf3 inv top mat verts grps pending
                         nodes out i n span q1 q3 s1 s3 lo hi mid size pipe
                         noxy g)
  (setq name    (cadr r)
        ty      (if (pfq:str (car r)) (strcase (car r)) "?")
        clfile  (pfq:str (pfa:entry-cl r))
        sf3     (pfa:src-files (car r) name)
        inv     (pfq:str (car sf3))
        top     (pfq:str (cadr sf3))
        mat     (if (pfq:str (caddr sf3))
                  (strcase (caddr sf3))
                  *pfq-material-unknown*)
        verts   (if inv (pf:pro-verts inv))
        grps    (if verts (pfr:groups verts))
        pending (pfa:pend-for name lines inlets))
  (cond
    ((null verts)
     (pfr:fatal (strcat "'" name "': the _INV .pro has no readable vertices.")))
    ((< (length grps) 2)
     (pfr:fatal (strcat "'" name "': the _INV .pro holds "
                        (itoa (length grps))
                        " structure(s) -- no pipe run to take off.")))
    (T
     (if (null clfile)
       (pfr:warn (strcat "'" name "' has no .cl on record -- its structures "
                         "cannot be matched to another line's, so a shared "
                         "junction would be counted twice.")))
     ;; one node per structure group, built once and shared by both its pipes
     (setq nodes '() noxy 0)
     (foreach g grps
       (setq nodes (cons (pfq:node-of g clfile pending lines index) nodes)))
     (setq nodes (reverse nodes))
     (foreach g nodes
       (if (null (pfr:g 'xy g)) (setq noxy (1+ noxy))))
     (if (and clfile (> noxy 0))
       (pfr:warn (strcat "'" name "': the .cl returned no plan coordinate at "
                         (itoa noxy) " of " (itoa (length nodes))
                         " structure(s) -- those cannot be merged with a "
                         "neighbouring line's.  Re-bind the .cl with PFSETUP.")))
     (setq out '() i 0 n (length grps))
     (while (< i (1- n))
       ;; the pipe runs from group i's HIGH-station vertex to group i+1's
       ;; LOW-station vertex -- the outside walls of the two structures
       (setq lo   (pfr:grp-hi (nth i grps))
             hi   (pfr:grp-lo (nth (1+ i) grps))
             span (- (car hi) (car lo))
             mid  (* 0.5 (+ (car lo) (car hi)))
             size (cdr (pf:pipe-at inv top mid)))
       ;; Size is asserted to change only AT a structure, so the midpoint
       ;; sample is the segment's true size rather than an approximation.
       ;; The quarter points cost two more .pro reads and turn that assertion
       ;; into a checked one: disagreement means the profile breaks it.
       (setq q1 (cdr (pf:pipe-at inv top (+ (car lo) (* 0.25 span))))
             q3 (cdr (pf:pipe-at inv top (+ (car lo) (* 0.75 span))))
             s1 (if q1 q1 size)
             s3 (if q3 q3 size))
       (if (and size (or (/= s1 size) (/= s3 size)))
         (pfr:warn (strcat "'" name "' Sta " (pf:fmt-station (car lo)) " to "
                           (pf:fmt-station (car hi))
                           ": the pipe changes size BETWEEN structures ("
                           (itoa s1) "\" / " (itoa size) "\" / " (itoa s3)
                           "\") -- the whole length is taken off at the "
                           "midpoint size.")))
       (if (null size)
         (pfr:warn (strcat "'" name "' Sta " (pf:fmt-station (car lo)) " to "
                           (pf:fmt-station (car hi))
                           ": no pipe size (no _TOP .pro bound, or it is "
                           "unreadable there) -- reported as UNKNOWN.")))
       (setq pipe (list (cons 'line   name)
                        (cons 'type   ty)
                        (cons 'mat    mat)
                        (cons 'lo-sta (car lo))
                        (cons 'hi-sta (car hi))
                        (cons 'len    (abs span))
                        (cons 'size   size)
                        (cons 'dn-nd  (nth i nodes))
                        (cons 'up-nd  (nth (1+ i) nodes))
                        (cons 'idx    0))
             out  (cons pipe out)
             i    (1+ i)))
     (pf:progress (strcat "\n  '" name "': " (itoa (length out)) " pipe(s), "
                          (itoa n) " structure(s)."))
     (reverse out))))


;;; ==========================================================================
;;; SECTION 3  --  The node table
;;; ==========================================================================
;;; NODE: (xy id sta lines type size)
;;;   `lines` is the LIST of selected lines that touch this structure, in
;;;   first-seen order.  That list is the whole shared-junction answer: the
;;;   structure appears under every line it serves and is tallied ONCE, so the
;;;   per-line blocks and the grand total cannot disagree.
;;; Merge order matches pfr:build-nodes -- whichever line first knows an ID, a
;;; type or a size contributes it.
;;;
;;; XY MUST STAY AT INDEX 0 AND THE STRUCTURE BLOCK AT INDEX 6: pfr:node-index
;;; reads a table entry through pfr:nd-xy (nth 0) and pfr:nd-ent (nth 6).  Those
;;; two shared columns are the whole reason this table can borrow pfreport's
;;; matcher instead of carrying a second copy of it.  Only the columns pfqty
;;; actually reads have accessors here; xy, sta and the block are positional.

(defun pfq:nd-id    (nd) (nth 1 nd))
(defun pfq:nd-lines (nd) (nth 3 nd))
(defun pfq:nd-type  (nd) (nth 4 nd))
(defun pfq:nd-size  (nd) (nth 5 nd))

;; (pfq:build-nodes pipes) -> (pipes . node-table)
;;   Stamps 'idx and 'dn-node / 'up-node onto every pipe.  The index is taken
;;   AT INSERT, never re-looked-up: a node with neither a plan coordinate nor a
;;   block can never match pfr:node-index, so re-searching would stamp nil.
;;   IDENTITY carries the junction now, so the ".cl unreadable = possible double
;;   count" caveat below only bites where the structure has no block either.
(defun pfq:build-nodes (pipes / tbl out p i k nd idx e ln di ui)
  (setq tbl '() out '() i 0 di nil ui nil)
  (foreach p pipes
    (setq ln (pfr:g 'line p))
    (foreach k '(dn-nd up-nd)
      (setq nd  (pfr:g k p)
            idx (if (or (pfr:g 'xy nd) (pfr:g 'ent nd))
                  (pfr:node-index tbl (pfr:g 'xy nd) (pfr:g 'ent nd))))
      (if (null idx)
        (setq idx (length tbl)
              tbl (append tbl
                    (list (list (pfr:g 'xy nd) (pfr:g 'id nd) (pfr:g 'sta nd)
                                (list ln) (pfr:g 'sty nd) (pfr:g 'ssz nd)
                                (pfr:g 'ent nd)))))
        (progn                                  ; merge what this line knows
          (setq e (nth idx tbl))
          (if (and (= (pfq:nd-id e) "") (/= (pfr:g 'id nd) ""))
            (setq e (pfr:set-nth 1 (pfr:g 'id nd) e)))
          (if (and (= (pfq:nd-type e) *pfq-struct-unknown*)
                   (/= (pfr:g 'sty nd) *pfq-struct-unknown*))
            (setq e (pfr:set-nth 4 (pfr:g 'sty nd) e)))
          (if (and (null (pfq:nd-size e)) (pfr:g 'ssz nd))
            (setq e (pfr:set-nth 5 (pfr:g 'ssz nd) e)))
          (if (not (member ln (pfq:nd-lines e)))
            (setq e (pfr:set-nth 3 (append (pfq:nd-lines e) (list ln)) e)))
          (if (and (null (pfr:nd-ent e)) (pfr:g 'ent nd))
            (setq e (pfr:set-nth 6 (pfr:g 'ent nd) e)))
          (setq tbl (pfr:set-nth idx e tbl))))
      (if (eq k 'dn-nd) (setq di idx) (setq ui idx)))
    (setq p   (pfr:p 'idx i p)
          p   (pfr:p 'dn-node di p)
          p   (pfr:p 'up-node ui p)
          out (cons p out)
          i   (1+ i)))
  (cons (reverse out) tbl))


;;; ==========================================================================
;;; SECTION 4  --  Tallies
;;; ==========================================================================
;;; A row is (key count length).  `key` is a LIST, so assoc/subst compare it
;;; with equal -- which is why the utility type rides IN the pipe key: 12" RCP
;;; on a storm line and 12" RCP on a sanitary line are two bid items.  The
;;; structure key carries no utility type on purpose: a structure is shared by
;;; plan coincidence, and a junction between a storm and a sanitary line is
;;; still one structure.

;; (pfq:bump key n lf tbl) -> tbl with key's count and length increased
(defun pfq:bump (key n lf tbl / cell)
  (if (setq cell (assoc key tbl))
    (subst (list key (+ (cadr cell) n) (+ (caddr cell) lf)) cell tbl)
    (append tbl (list (list key n lf)))))

(defun pfq:row-key   (row) (nth 0 row))
(defun pfq:row-count (row) (nth 1 row))
(defun pfq:row-len   (row) (nth 2 row))

;; (pfq:pipe-tally pipes) -> (((type size mat) count lf) ...)
(defun pfq:pipe-tally (pipes / tbl p)
  (setq tbl '())
  (foreach p pipes
    (setq tbl (pfq:bump (list (pfr:g 'type p) (pfr:g 'size p) (pfr:g 'mat p))
                        1 (pfr:g 'len p) tbl)))
  (pfq:sort-rows tbl 'pfq:pipe-sortkey))

;; (pfq:struct-tally nodes) -> (((type size) count 0.0) ...)
;;   ONE row per node, so a junction shared by two lines is counted once.
(defun pfq:struct-tally (nodes / tbl nd)
  (setq tbl '())
  (foreach nd nodes
    (setq tbl (pfq:bump (list (pfq:nd-type nd) (pfq:nd-size nd)) 1 0.0 tbl)))
  (pfq:sort-rows tbl 'pfq:struct-sortkey))

;; (pfq:num-key n) -> a fixed-width string that sorts numerically; nil last
(defun pfq:num-key (n)
  (if n
    (strcat (if (< (abs n) 100) "0" "") (if (< (abs n) 10) "0" "")
            (itoa (fix n)))
    "ZZZ"))

(defun pfq:pipe-sortkey (row / k)
  (setq k (pfq:row-key row))
  (strcat (pfq:text (nth 0 k)) " " (pfq:num-key (nth 1 k)) " "
          (pfq:text (nth 2 k))))

(defun pfq:struct-sortkey (row / k)
  (setq k (pfq:row-key row))
  (strcat (pfq:text (nth 0 k)) " "
          (if (nth 1 k) (pfq:text (nth 1 k)) "ZZZ")))

(defun pfq:sort-rows (tbl keyfn)
  (vl-sort tbl
    (function (lambda (a b)
                (< (apply keyfn (list a)) (apply keyfn (list b)))))))

;; (pfq:total-len tbl) / (pfq:total-count tbl)
(defun pfq:total-len (tbl / s r)
  (setq s 0.0) (foreach r tbl (setq s (+ s (pfq:row-len r)))) s)

(defun pfq:total-count (tbl / s r)
  (setq s 0) (foreach r tbl (setq s (+ s (pfq:row-count r)))) s)


;;; ==========================================================================
;;; SECTION 5  --  Rendering
;;; ==========================================================================

(defun pfq:lpad (s w)
  (if (null s) (setq s ""))
  (while (< (strlen s) w) (setq s (strcat " " s)))
  s)

(defun pfq:lf (v) (rtos (float v) 2 *pfq-lf-decimals*))

;; (pfq:pipe-size-text n) -> "12\"" | *pfq-size-unknown*
(defun pfq:pipe-size-text (n)
  (cond ((numberp n) (strcat (itoa (fix n)) "\""))
        ((null n)    *pfq-size-unknown*)
        (T           (pfq:text n))))       ; show it rather than hide it

(defun pfq:struct-size-text (s)
  (cond ((pfq:str s) s)
        ((null s)    *pfq-size-unknown*)
        (T           (pfq:text s))))

;; (pfq:pipe-block tbl indent) -> list of report lines (header, rows, total)
(defun pfq:pipe-block (tbl indent / out k r)
  (setq out (list (strcat indent (pfset:pad "Type" 10) (pfset:pad "Size" 8)
                          (pfset:pad "Material" 16) (pfq:lpad "Pipes" 7)
                          (pfq:lpad "Length (LF)" 15))
                  (strcat indent (substr *pfq-rule* 1 56))))
  (foreach r tbl
    (setq k (pfq:row-key r)
          out (cons (strcat indent
                            (pfset:pad (pfq:text (nth 0 k)) 10)
                            (pfset:pad (pfq:pipe-size-text (nth 1 k)) 8)
                            (pfset:pad (pfq:text (nth 2 k)) 16)
                            (pfq:lpad (itoa (pfq:row-count r)) 7)
                            (pfq:lpad (pfq:lf (pfq:row-len r)) 15))
                    out)))
  (reverse
    (cons (strcat indent (pfset:pad "TOTAL" 34)
                  (pfq:lpad (itoa (pfq:total-count tbl)) 7)
                  (pfq:lpad (pfq:lf (pfq:total-len tbl)) 15))
          (cons (strcat indent (substr *pfq-rule* 1 56)) out))))

;; (pfq:struct-block tbl indent) -> list of report lines
(defun pfq:struct-block (tbl indent / out k r)
  (setq out (list (strcat indent (pfset:pad "Type" 24) (pfset:pad "Size" 10)
                          (pfq:lpad "Count" 7))
                  (strcat indent (substr *pfq-rule* 1 41))))
  (foreach r tbl
    (setq k (pfq:row-key r)
          out (cons (strcat indent
                            (pfset:pad (pfq:text (nth 0 k)) 24)
                            (pfset:pad (pfq:struct-size-text (nth 1 k)) 10)
                            (pfq:lpad (itoa (pfq:row-count r)) 7))
                    out)))
  (reverse
    (cons (strcat indent (pfset:pad "TOTAL" 34)
                  (pfq:lpad (itoa (pfq:total-count tbl)) 7))
          (cons (strcat indent (substr *pfq-rule* 1 41)) out))))

;; (pfq:now) -> "YYYY-MO-DD HH:MM" | ""
(defun pfq:now ( / r)
  (setq r (vl-catch-all-apply
            'menucmd (list "M=$(edtime,$(getvar,date),YYYY-MO-DD HH:MM)")))
  (if (vl-catch-all-error-p r) "" r))

;; (pfq:line-nodes nodes name) -> the nodes this line touches
(defun pfq:line-nodes (nodes name / out nd)
  (setq out '())
  (foreach nd nodes
    (if (member name (pfq:nd-lines nd)) (setq out (cons nd out))))
  (reverse out))

;; (pfq:shared-count nds) -> how many of them serve more than one line
(defun pfq:shared-count (nds / n nd)
  (setq n 0)
  (foreach nd nds (if (cdr (pfq:nd-lines nd)) (setq n (1+ n))))
  n)

;; (pfq:by-line sel pipes nodes) -> the BY LINE section
(defun pfq:by-line (sel pipes nodes / out r name mine nds sh l)
  (setq out '())
  (foreach r sel
    (setq name (cadr r)
          mine (vl-remove-if-not
                 (function (lambda (p) (= (pfr:g 'line p) name))) pipes)
          nds  (pfq:line-nodes nodes name)
          sh   (pfq:shared-count nds))
    (setq out (cons "" out))
    (setq out (cons (strcat "  " (strcase (car r)) " '" name "'  --  "
                            (itoa (length mine)) " pipe(s), "
                            (pfq:lf (pfq:total-len (pfq:pipe-tally mine)))
                            " LF, " (itoa (length nds)) " structure(s)")
                    out))
    (if mine
      (foreach l (pfq:pipe-block (pfq:pipe-tally mine) "      ")
        (setq out (cons l out))))
    (setq out (cons "" out))
    (if nds
      (foreach l (pfq:struct-block (pfq:struct-tally nds) "      ")
        (setq out (cons l out))))
    (if (> sh 0)
      (setq out (cons (strcat "      * " (itoa sh) " of these structure(s) "
                              "also serve another selected line.  They are "
                              "listed here and counted ONCE in the totals "
                              "above.")
                      out))))
  (reverse out))

;; (pfq:compose sel pipes nodes) -> the whole report, as a list of lines
(defun pfq:compose (sel pipes nodes / out r names l)
  (setq names '())
  (foreach r sel
    (setq names (cons (strcat (strcase (car r)) " '" (cadr r) "'") names)))
  (setq out
    (list *pfq-rule*
          "PFTOOLS  --  QUANTITIES REPORT"
          *pfq-rule*
          (strcat "Drawing : " (getvar "DWGPREFIX") (getvar "DWGNAME"))
          (strcat "Written : " (pfq:now))
          (strcat "Lines   : " (pf:join (reverse names) ", "))
          (strcat "Measure : pipe length is out to out of the structures it "
                  "spans,")
          "          along the alignment; structures add no LF."
          *pfq-rule*
          ""
          "PIPE"))
  (foreach l (pfq:pipe-block (pfq:pipe-tally pipes) "  ")
    (setq out (append out (list l))))
  (setq out (append out (list "" "STRUCTURES")))
  (foreach l (pfq:struct-block (pfq:struct-tally nodes) "  ")
    (setq out (append out (list l))))
  (setq out (append out (list "" *pfq-rule* "BY LINE" *pfq-rule*)))
  (setq out (append out (pfq:by-line sel pipes nodes)))
  ;; the findings ride IN the file: the .txt is the deliverable, and a note
  ;; that only reached the command line is a note nobody keeps
  (if (or *pfr-warn* *pfr-fatal*)
    (progn
      (setq out (append out (list "" *pfq-rule* "NOTES" *pfq-rule*)))
      (foreach l (reverse *pfr-warn*)
        (setq out (append out (list (strcat "  NOTE:  " l)))))
      (foreach l (reverse *pfr-fatal*)
        (setq out (append out (list (strcat "  ERROR: " l)))))))
  (append out (list "" *pfq-rule* "end of report" *pfq-rule*)))

;; (pfq:write file sel pipes nodes) -> T | nil
(defun pfq:write (file sel pipes nodes / f l)
  (if (null (setq f (open file "w")))
    (progn (prompt (strcat "\nCould not open " file " for writing.")) nil)
    (progn
      (foreach l (pfq:compose sel pipes nodes) (write-line l f))
      (close f)
      T)))


;;; ==========================================================================
;;; SECTION 6  --  Candidates + the dialog
;;; ==========================================================================
;;; SYSTEM-scoped: the list is the REGISTRY.  Looser than pfr:candidates by
;;; design -- see the header.  All a takeoff needs is an _INV .pro on disk.

;; (pfq:candidates) -> registry rows usable for a takeoff
(defun pfq:candidates ( / out r sf3)
  (setq out '())
  (foreach r (pfa:registry)
    (cond
      ((null (car (setq sf3 (pfa:src-files (car r) (cadr r)))))
       (prompt (strcat "\n  Not offered: " (car r) " '" (cadr r)
                       "' has no _INV .pro bound -- every pipe length and "
                       "structure station comes from it.")))
      ((null (findfile (car sf3)))
       (prompt (strcat "\n  Not offered: " (car r) " '" (cadr r)
                       "' -- _INV .pro not found on disk: " (car sf3))))
      (T (setq out (cons r out)))))
  (reverse out))

;; (pfq:row r) -> the column-formatted list row
(defun pfq:row (r / sf3)
  (setq sf3 (pfa:src-files (car r) (cadr r)))
  (strcat (pfset:pad (car r) 10)
          (pfset:pad (cadr r) 12)
          (pfset:pad (if (eq (caddr r) 'ANCHORED) "yes" "stub") 8)
          (pfset:pad (if (cadr sf3) "yes" "NO") 8)
          (if (caddr sf3) (caddr sf3) "-")))

(defun pfq:rd-sel ( / s idxs i out)
  (setq s (get_tile "qt_list"))
  (if (or (null s) (= s ""))
    (set_tile "error" "Select the lines to take off.")
    (progn
      (setq idxs (read (strcat "(" s ")")) out '())
      (foreach i idxs (setq out (cons (nth i qt-rows) out)))
      (setq qt-res (reverse out))
      (done_dialog 1))))

(defun pfq:rd-all ()
  (setq qt-res qt-rows)
  (done_dialog 1))

;; (pfq:run-dialog qt-rows) -> list of chosen registry rows | nil
(defun pfq:run-dialog (qt-rows / dcl_id qt-res r result)
  (setq qt-res nil dcl_id (load_dialog (pfset:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pfqty_run" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the quantities dialog.") nil)
      (progn
        (set_tile "qt_title" "PFQTY -- material quantities takeoff (.txt)")
        (start_list "qt_list")
        (foreach r qt-rows (add_list (pfq:row r)))
        (end_list)
        (set_tile "qt_count"
                  (strcat (itoa (length qt-rows))
                          " profile(s) ready.  Pick everything to be counted."))
        (set_tile "error" "")
        (action_tile "qt_sel" "(pfq:rd-sel)")
        (action_tile "qt_all" "(pfq:rd-all)")
        (action_tile "cancel" "(done_dialog 0)")
        (action_tile "help"
          (strcat "(pfset:help \"Pick the registered lines to take off.  They "
                  "need NOT connect and they need not be one system -- this "
                  "builds no network, so disconnected lines and stubs are "
                  "all legitimate.\\n\\nPipe lengths and structure positions "
                  "come from each line's bound _INV .pro; pipe sizes from its "
                  "_TOP .pro (the Crown column); the material from the "
                  "anchor.\\n\\nA structure shared by two picked lines is "
                  "listed under both and counted ONCE in the totals.  Nothing "
                  "is defaulted: an unbound material reads UNSPECIFIED and a "
                  "pipe with no _TOP reads UNKNOWN, so a gap in the record "
                  "shows up on the sheet instead of being guessed.\")"))
        (setq result (vl-catch-all-apply 'start_dialog '()))
        (unload_dialog dcl_id)
        (cond
          ((vl-catch-all-error-p result)
           (prompt (strcat "\nDialog error: "
                           (vl-catch-all-error-message result)))
           nil)
          ((= result 1) qt-res)
          (T nil))))))


;;; ==========================================================================
;;; SECTION 7  --  The engine + C:PFQTY
;;; ==========================================================================

;; (pfq:default-path sel) -> the save dialog's starting path
(defun pfq:default-path (sel / dir)
  (setq dir (cond ((pfset:root-get)) (T (pfset:dir))))
  (strcat dir (strcase (car (car sel))) "_" (cadr (car sel)) "_QTY"))

;; (pfq:run sel) -> nil    THE ENGINE.  Read-only; the .txt is the only write.
(defun pfq:run (sel / lines index inlets pipes r built nodes file ptbl stbl)
  (setq *pfr-fatal* '() *pfr-warn* '())
  (prompt "\nBuilding the line table...")
  (setq lines  (pfr:line-table sel)
        inlets (pfa:gather-inlets)
        index  (pfa:index-stations inlets lines)
        pipes  '())
  (prompt (strcat "\n" (itoa (length inlets)) " structure block(s) in model space."))
  (foreach r sel
    (if (setq built (pfq:line-pipes r lines index inlets))
      (setq pipes (append pipes built))))
  (cond
    (*pfr-fatal*
     (prompt "\n\nPFQTY ABORTED -- a selected profile could not be read:")
     (pfr:report))
    ((null pipes)
     (prompt "\nNothing to take off -- no pipe runs were found.")
     (pfr:report))
    (T
     (setq built (pfq:build-nodes pipes)
           pipes (car built)
           nodes (cdr built)
           ptbl  (pfq:pipe-tally pipes)
           stbl  (pfq:struct-tally nodes))
     (pfr:report)
     (prompt (strcat "\n\n" (itoa (length pipes)) " pipe(s), "
                     (pfq:lf (pfq:total-len ptbl)) " LF total, across "
                     (itoa (length nodes)) " structure(s) in "
                     (itoa (length stbl)) " type(s)."))
     (setq file (getfiled "Write Quantities Report"
                          (pfq:default-path sel) "txt" 1))
     (cond
       ((null file) (prompt "\nCancelled -- no file chosen."))
       ((pfq:write file sel pipes nodes)
        (prompt (strcat "\nWrote " file))))))
  (princ))

;; (pfq:cmd) -> nil   The command body, run under pf:run-command.
(defun pfq:cmd ( / rows sel)
  (setq rows (pfq:candidates))
  (if (null rows)
    (prompt (strcat "\nNothing to take off.  PFQTY needs a registry entry "
                    "with an _INV .pro bound and on disk -- run PFSETUP."))
    (progn
      (setq sel (pfq:run-dialog rows))
      (if (null sel)
        (prompt "\nPFQTY cancelled.")
        (pfq:run sel))))
  (princ))

(defun c:PFQTY ()
  (pf:run-command "PFQTY" nil 'pfq:cmd))

(defun c:PFQ () (c:PFQTY))

(princ "\npfqty.lsp loaded (quantities takeoff).  Command: PFQTY (alias PFQ).")
(princ)
;;; ==========================================================================
;;; end of pfqty.lsp
;;; ==========================================================================
