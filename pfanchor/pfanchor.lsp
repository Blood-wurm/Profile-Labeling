;;; ==========================================================================
;;; pfanchor.lsp  --  PFTools record + registry (+ pf:run-command, PFREMOVE)
;;; Load position 4 of 10: after pfdraw, before pfsettings.
;;; Model, ledger schema, API, and the safety contract: see README.md
;;; beside this file.
;;; ==========================================================================

(vl-load-com)

;;; ==========================================================================
;;; SECTION 1  --  Pure helpers
;;; ==========================================================================

;; (pfa:sanitize s) -> s with block/dict-hostile characters replaced by "-"
(defun pfa:sanitize (s / bad i c out)
  (setq bad "\\/:*?\"<>|;,=` " out "" i 1)
  (while (<= i (strlen s))
    (setq c (substr s i 1))
    (setq out (strcat out (if (vl-string-search c bad) "-" c)))
    (setq i (1+ i)))
  out)

;; (pfa:att tag alist) -> value string ("" when absent; never nil)
(defun pfa:att (tag at / v)
  (if (setq v (cdr (assoc tag at))) v ""))

;;; --------------------------------------------------------------------------
;;; Crossing working-entry accessors.  Every crossing moves through the
;;; toolset as a 10-list: (key tfile tbase sfile sbase xy tsta ssta telev selev)
;;; --------------------------------------------------------------------------

(defun pfa:xr-key   (e) (nth 0 e))
;; xr-tfile / xr-tbase (nth 1 / nth 2) quarantined to _attic 2026-08-01:
;; X_* stores the SOURCE file/base only; the target fields are dropped at merge.
(defun pfa:xr-sfile (e) (nth 3 e))
(defun pfa:xr-sbase (e) (nth 4 e))
(defun pfa:xr-xy    (e) (nth 5 e))
(defun pfa:xr-tsta  (e) (nth 6 e))
(defun pfa:xr-ssta  (e) (nth 7 e))
;; KEEP though the dead-code gate names them: the reader half of pipe
;; clearance -- PFCHECK (Version 5.1.md §5) subtracts these two elevations,
;; filed by pfa:xing-put-elevs.  The writer landed before its consumer.
(defun pfa:xr-telev (e) (nth 8 e))
(defun pfa:xr-selev (e) (nth 9 e))

;; (pfa:xing-key sbase tsta) -> "X_<SBASE>_<round(tsta*100)>"
(defun pfa:xing-key (sbase tsta)
  (strcat "X_" (pfa:sanitize (strcase sbase)) "_"
          (itoa (fix (+ (* tsta 100.0) 0.5)))))


;;; ==========================================================================
;;; SECTION 2  --  Anchor block  (definition, write, find, read, update)
;;; ==========================================================================

;; (pfa:send-to-back e) -> nil   (anchor draws BEHIND everything else)
;;   The anchor is a backdrop marker and must never sit on top of the grid, the
;;   profile, or a label.  DRAWORDER is the only route to sort-ents from plain
;;   LISP, so this shells out with echo suppressed.  Draw order is cosmetic, so
;;   a failure is swallowed and the anchor is still valid.
;;   command-s, NOT command: `command` is a special form, so vl-catch-all-apply
;;   rejects it ("bad order function: COMMAND") and the error escapes the catch
;;   meant to contain it.
(defun pfa:send-to-back (e / echo)
  (if (and e (entget e))
    (progn
      (setq echo (getvar "CMDECHO"))
      (setvar "CMDECHO" 0)
      (vl-catch-all-apply 'command-s
        (list "_.DRAWORDER" (ssadd e) "" "_Back"))
      (setvar "CMDECHO" echo)))
  (princ))

;; (pfa:icon-scale hplot) -> real   UNIFORM insert scale for the anchor icon
;;   A fixed-size icon snapped to the datum, drawn at the size it should read on
;;   an H:*pfa-icon-ref-hplot* sheet.  Model size tracks plot scale to hold a
;;   constant size on paper, so the ratio applies to X, Y AND Z -- an icon must
;;   never distort, which is also why extents no longer ride on the scales.
(defun pfa:icon-scale (hplot)
  (if (and hplot (> hplot 0.0))
    (/ hplot *pfa-icon-ref-hplot*)
    1.0))

;; (pfa:attdef-tags name) -> list of upper-case ATTDEF tags in a block DEFINITION
(defun pfa:attdef-tags (name / e ed out)
  (setq out '())
  (if (setq e (tblobjname "BLOCK" name))
    (progn
      (setq e (entnext e))
      (while (and e (setq ed (entget e)) (/= (cdr (assoc 0 ed)) "ENDBLK"))
        (if (= (cdr (assoc 0 ed)) "ATTDEF")
          (setq out (cons (strcase (cdr (assoc 2 ed))) out)))
        (setq e (entnext e)))))
  out)

;; (pfa:sync-attdefs) -> count added
;;   The anchor block is hand-authored, so its definition may not carry the
;;   ATTDEFs the ledger depends on.  Anchors read correctly either way --
;;   pfa:write-anchor entmakes the ATTRIBs onto the insert regardless -- but a
;;   definition with no matching ATTDEFs is one ATTSYNC or block-editor
;;   round-trip away from losing every one of them, and those attributes ARE
;;   the anchor's geometric state.
;;   ADDITIVE ONLY: adds the missing tags, invisible, touching no geometry.
;;   Every ActiveX call is catch-wrapped, so a drawing that will not hand over
;;   its block collection still gets a working (un-synced) anchor.
(defun pfa:sync-attdefs ( / have blks blk n y mode)
  (setq n 0 mode 1)                     ; 1 = acAttributeModeInvisible
  (if (tblsearch "BLOCK" *pfa-block-name*)
    (progn
      (setq have (pfa:attdef-tags *pfa-block-name*)
            blks (vl-catch-all-apply
                   '(lambda ()
                      (vla-get-blocks
                        (vla-get-activedocument (vlax-get-acad-object))))
                   '()))
      (if (not (vl-catch-all-error-p blks))
        (progn
          (setq blk (vl-catch-all-apply 'vla-item (list blks *pfa-block-name*)))
          (if (not (vl-catch-all-error-p blk))
            (progn
              (setq y (- (* *pfa-att-height* *pfa-att-gap*)))
              (foreach tag *pfa-att-tags*
                (if (not (member (strcase tag) have))
                  (if (not (vl-catch-all-error-p
                             (vl-catch-all-apply
                               'vla-addattribute
                               (list blk *pfa-att-height* mode tag
                                     (vlax-3d-point 0.0 y 0.0) tag ""))))
                    (setq n (1+ n))))
                (setq y (- y (* *pfa-att-height* *pfa-att-gap*))))
              (if (> n 0)
                (prompt (strcat "\nAdded " (itoa n) " missing attribute "
                                "definition(s) to block '"
                                *pfa-block-name* "'.")))))))))
  n)

;; (pfa:ensure-anchor-block) -> nil   (anchor block is usable after this)
;;   The hand-authored PF-ANCHOR always wins: when the drawing already carries a
;;   definition this only tops up its ATTDEFs and leaves the artwork alone.
;;   What follows is the FALLBACK, entmade only in a drawing that has never seen
;;   one -- a PLACEHOLDER datum pointer, not a stand-in for the real icon.
;;   Deliberately small: the block no longer spans the grid, so nothing here is
;;   scaled to the extents.
(defun pfa:ensure-anchor-block ( / y)
  (cond
    ((tblsearch "BLOCK" *pfa-block-name*)
     (pfa:sync-attdefs))
    (T
     (entmake (list '(0 . "BLOCK") (cons 2 *pfa-block-name*)
                    '(70 . 2) '(10 0.0 0.0 0.0)))
     (entmake '((0 . "LINE") (8 . "0") (10  0.0 0.0 0.0) (11 -2.0 3.0 0.0)))
     (entmake '((0 . "LINE") (8 . "0") (10 -2.0 3.0 0.0) (11  2.0 3.0 0.0)))
     (entmake '((0 . "LINE") (8 . "0") (10  2.0 3.0 0.0) (11  0.0 0.0 0.0)))
     (entmake '((0 . "LINE") (8 . "0") (10 -3.0 0.0 0.0) (11  3.0 0.0 0.0)))
     (setq y (- (* *pfa-att-height* *pfa-att-gap*)))
     (foreach tag *pfa-att-tags*
       (entmake (list '(0 . "ATTDEF") '(8 . "0")
                      (list 10 0.0 y 0.0)
                      (cons 40 *pfa-att-height*)
                      '(1 . "") (cons 3 tag) (cons 2 tag)
                      '(70 . 9)))          ; 1 invisible + 8 preset
       (setq y (- y (* *pfa-att-height* *pfa-att-gap*))))
     (entmake '((0 . "ENDBLK") (8 . "0")))
     (prompt (strcat "\nDefined placeholder block '" *pfa-block-name* "'."))))
  (princ))

;; (pfa:extents anchor) -> (width height)   either element may be nil
;;   Stored RELATIVE to the insertion point (grid lower-left), so a window-move
;;   of grid + anchor carries both.  That is the design, and it is why
;;   pfa:corner-check cannot see such a move.
;;   Current anchors keep them in the WIDTH/HEIGHT attributes.  The scale-factor
;;   read is the LEGACY path only -- the block is a fixed-size icon now and its
;;   scales carry plot scale, so extents read off them would be nonsense (at
;;   H:200 the X-scale is 4.0).  The ABSENCE of WIDTH/HEIGHT is what identifies
;;   a pre-icon anchor; scale alone cannot tell the two apart.  The xs > 2.0
;;   sentinel (no real grid is 2 ft wide) still guards the legacy width.
(defun pfa:extents (anchor / at w h ed xs ys)
  (setq at (pfa:read-attribs anchor)
        w  (distof (pfa:att "WIDTH"  at) 2)
        h  (distof (pfa:att "HEIGHT" at) 2))
  (if (and h (> h 0.0))
    (list (if (and w (> w 0.0)) w) h)
    (progn
      (setq ed (entget anchor)
            xs (cdr (assoc 41 ed))
            ys (cdr (assoc 42 ed)))
      (list (if (and xs (> xs 2.0)) xs)
            (if (and ys (> ys 0.0)) ys)))))

;; (pfa:read-attribs anchor) -> alist ("TAG" . "value")
(defun pfa:read-attribs (anchor / e ed out)
  (setq e (entnext anchor) out '())
  (while (and e (setq ed (entget e)) (= (cdr (assoc 0 ed)) "ATTRIB"))
    (setq out (cons (cons (strcase (cdr (assoc 2 ed))) (cdr (assoc 1 ed)))
                    out))
    (setq e (entnext e)))
  (reverse out))

;; (pfa:find-anchor line util) -> anchor ename | nil
(defun pfa:find-anchor (line util / ss i e at res)
  (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 *pfa-block-names*)
                             '(410 . "Model")))     ; model space only
        i  0
        res nil)
  (if ss
    (while (and (< i (sslength ss)) (null res))
      (setq e (ssname ss i) at (pfa:read-attribs e))
      (if (and (= (strcase (pfa:att "LINE" at)) (strcase line))
               (= (strcase (pfa:att "UTIL" at)) (strcase util))
               (not (pfa:copy-p e)))            ; copies never resolve
        (setq res e))
      (setq i (1+ i))))
  res)

;; (pfa:all-anchors) -> list of anchor enames
(defun pfa:all-anchors ( / ss i out)
  (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 *pfa-block-names*)
                             '(410 . "Model")))     ; model space only
        i 0 out '())
  (if ss
    (while (< i (sslength ss))
      (setq out (cons (ssname ss i) out) i (1+ i))))
  (reverse out))

;; (pfa:anchor->xform anchor) -> xform ALIST | nil
;;   Core geometry from geometry + attributes; record keys (clfile, pro-*,
;;   tin-*, name, type) merged in from the ledger when present.
;;   'topy is NOMINAL -- top at max station.  Per-station top comes from
;;   pf:top-at, never from here.  Extents come from pfa:extents (WIDTH/HEIGHT
;;   attributes, legacy scale factors as fallback); 'rightx stays absent when
;;   no width was ever recorded.
;;   nil when the core numbers are unreadable.
(defun pfa:anchor->xform (anchor / ed ins ext wid hgt at sta0 datum hp vp xf
                          meta files)
  (setq ed  (entget anchor)
        ins (cdr (assoc 10 ed))
        ext (pfa:extents anchor)
        wid (car ext)
        hgt (cadr ext)
        at  (pfa:read-attribs anchor)
        sta0  (distof (pfa:att "STA0"  at) 2)
        datum (distof (pfa:att "DATUM" at) 2)
        hp    (distof (pfa:att "HPLOT" at) 2)
        vp    (distof (pfa:att "VPLOT" at) 2))
  (if (and ins hgt sta0 datum hp vp
           (> hp 0.0) (> vp 0.0) (> hgt 0.0))
    (progn
      (setq xf (pf:make-xform (car ins) sta0
                              (+ (cadr ins) hgt) (cadr ins)
                              datum (/ hp vp) hp vp))
      (setq xf (pf:xf-put 'name (pfa:att "LINE" at) xf)
            xf (pf:xf-put 'type (pfa:att "UTIL" at) xf))
      (if wid
        (setq xf (pf:xf-put 'rightx (+ (car ins) wid) xf)))
      (setq meta (pfa:meta-get anchor))
      (if (and meta (assoc 1 meta) (/= (cdr (assoc 1 meta)) ""))
        (setq xf (pf:xf-put 'clfile (cdr (assoc 1 meta)) xf)))
      (setq files (pfa:files-get anchor))
      (if files
        (progn
          (if (and (assoc 1 files) (/= (cdr (assoc 1 files)) ""))
            (setq xf (pf:xf-put 'pro-inv (cdr (assoc 1 files)) xf)))
          (if (and (assoc 2 files) (/= (cdr (assoc 2 files)) ""))
            (setq xf (pf:xf-put 'pro-top (cdr (assoc 2 files)) xf)))
          (if (and (assoc 3 files) (/= (cdr (assoc 3 files)) ""))
            (setq xf (pf:xf-put 'tin-exist (cdr (assoc 3 files)) xf)))
          (if (and (assoc 4 files) (/= (cdr (assoc 4 files)) ""))
            (setq xf (pf:xf-put 'tin-design (cdr (assoc 4 files)) xf)))
          (if (and (assoc 5 files) (/= (cdr (assoc 5 files)) ""))
            (setq xf (pf:xf-put 'material (cdr (assoc 5 files)) xf)))))
      xf)))

;; (pfa:write-anchor line util xform tfile) -> anchor ename
;;   xform should carry 'rightx (the top-right pick X); without it the WIDTH
;;   attribute is left blank and pfa:extents reports no width.  Extents are
;;   stored RELATIVE, in the WIDTH/HEIGHT attributes -- the insert's scale
;;   factors carry the ICON's plot scale and nothing else.  Caller must hold an
;;   open undo group.
(defun pfa:write-anchor (line util xform tfile / ins wid hgt isc vals y i
                         anchor)
  (pfd:ensure-layer-c *pfa-layer* T *pfa-layer-color*)
  (pfa:ensure-anchor-block)
  (setq ins (list (pf:xf-leftx xform) (pf:xf-basey xform) 0.0)
        wid (if (pf:xf-get 'rightx xform)
              (- (pf:xf-get 'rightx xform) (pf:xf-leftx xform)))
        hgt (- (pf:grid-top-y xform) (pf:xf-basey xform))
        isc (pfa:icon-scale (pf:xf-hplot xform)))
  (entmake (list '(0 . "INSERT") (cons 8 *pfa-layer*)
                 (cons 2 *pfa-block-name*) (cons 10 ins)
                 (cons 41 isc) (cons 42 isc) (cons 43 isc)
                 '(50 . 0.0) '(66 . 1)))
  (setq vals (list (strcase line) (strcase util)
                   (rtos (pf:xf-sta0 xform) 2 6)
                   (rtos (pf:xf-datum xform) 2 6)
                   (rtos (pf:xf-hplot xform) 2 6)
                   (rtos (/ (pf:xf-hplot xform) (pf:xf-vscale xform)) 2 6)
                   (if wid (rtos wid 2 6) "")
                   (rtos hgt 2 6))
        y    (- (cadr ins) (* *pfa-att-height* *pfa-att-gap*))
        i    0)
  (foreach tag *pfa-att-tags*
    (entmake (list '(0 . "ATTRIB") (cons 8 *pfa-layer*)
                   (cons 10 (list (car ins) y 0.0))
                   (cons 40 *pfa-att-height*)
                   (cons 1 (nth i vals))
                   (cons 2 tag)
                   (cons 70 *pfa-att-flags*)))
    (setq y (- y (* *pfa-att-height* *pfa-att-gap*))
          i (1+ i)))
  (entmake (list '(0 . "SEQEND") (cons 8 *pfa-layer*)))
  (setq anchor (entlast))
  (pfa:meta-put anchor tfile "")
  (pfa:stamp-self anchor)                 ; copy-detection baseline
  (pfa:send-to-back anchor)
  (prompt (strcat "\nRegistered grid anchor: " (strcase util)
                  " '" (strcase line) "'."))
  anchor)

;; (pfa:reanchor anchor xform) -> anchor   (update in place; ledger survives)
;;   Extents go back to whichever storage THIS anchor already uses.  One
;;   carrying a WIDTH attribute is current: extents to the attributes, scale
;;   factors to the icon scale.  One without is pre-icon and its extents ARE its
;;   scale factors -- writing the icon scale over them would silently shrink its
;;   grid to a few feet -- so it keeps the old storage and the old block.
;;   Attributes are only UPDATED here, never added: the ledger hangs off this
;;   insert and must survive in place.
(defun pfa:reanchor (anchor xform / ed at legacy ins wid hgt isc vals e sed
                     tag i y)
  (setq at     (pfa:read-attribs anchor)
        legacy (null (distof (pfa:att "WIDTH" at) 2))
        ins (list (pf:xf-leftx xform) (pf:xf-basey xform) 0.0)
        wid (if (pf:xf-get 'rightx xform)
              (- (pf:xf-get 'rightx xform) (pf:xf-leftx xform))
              (car (pfa:extents anchor)))
        hgt (- (pf:grid-top-y xform) (pf:xf-basey xform))
        isc (pfa:icon-scale (pf:xf-hplot xform))
        ed  (entget anchor)
        ed  (subst (cons 10 ins) (assoc 10 ed) ed))
  (if legacy
    (setq ed (subst (cons 41 (if wid wid (cdr (assoc 41 ed)))) (assoc 41 ed) ed)
          ed (subst (cons 42 hgt) (assoc 42 ed) ed))
    (setq ed (subst (cons 41 isc) (assoc 41 ed) ed)
          ed (subst (cons 42 isc) (assoc 42 ed) ed)
          ed (subst (cons 43 isc) (assoc 43 ed) ed)))
  (entmod ed)
  (setq vals (list nil nil                        ; LINE/UTIL untouched
                   (rtos (pf:xf-sta0 xform) 2 6)
                   (rtos (pf:xf-datum xform) 2 6)
                   (rtos (pf:xf-hplot xform) 2 6)
                   (rtos (/ (pf:xf-hplot xform) (pf:xf-vscale xform)) 2 6)
                   (if wid (rtos wid 2 6) "")
                   (rtos hgt 2 6))
        y    (- (cadr ins) (* *pfa-att-height* *pfa-att-gap*))
        e    (entnext anchor))
  (while (and e (setq sed (entget e)) (= (cdr (assoc 0 sed)) "ATTRIB"))
    (setq tag (strcase (cdr (assoc 2 sed)))
          i   (vl-position tag *pfa-att-tags*))
    (if i
      (progn
        (if (nth i vals)
          (setq sed (subst (cons 1 (nth i vals)) (assoc 1 sed) sed)))
        (setq sed (subst (cons 10 (list (car ins) y 0.0))
                         (assoc 10 sed) sed))
        ;; heals anchors written while (70) was PRESET, not INVISIBLE
        (setq sed (subst (cons 70 *pfa-att-flags*) (assoc 70 sed) sed))
        (entmod sed)))
    (setq y (- y (* *pfa-att-height* *pfa-att-gap*))
          e (entnext e)))
  (entupd anchor)
  (pfa:send-to-back anchor)     ; heals anchors written before back-ordering
  (prompt "\nGrid anchor updated in place (ledger preserved).")
  anchor)

;; (pfa:probe-corner pt) -> T | nil
;;   T when a grid LINE passes within tol of pt, or when the drawing has no
;;   grid-layer LINEs at all (nothing to assert against).  The PF-GRID-* layers
;;   are Carlson's own.
(defun pfa:probe-corner (pt / ss i ed ok)
  (setq ss (ssget "_X" (list '(0 . "LINE") (cons 8 *pfa-grid-layers*)
                             '(410 . "Model"))))    ; model space only
  (cond
    ((null ss) T)
    (T
     (setq i 0 ok nil)
     (while (and (< i (sslength ss)) (null ok))
       (setq ed (entget (ssname ss i)))
       (if (<= (pf:pt-seg-dist (list (car pt) (cadr pt))
                               (cdr (assoc 10 ed)) (cdr (assoc 11 ed)))
               *pfa-probe-tol*)
         (setq ok T))
       (setq i (1+ i)))
     ok)))

;; (pfa:corner-check anchor) -> list of finding strings ('() = no drift)
;;   Extents are stored RELATIVE, so a window-move of grid + anchor is
;;   invisible here BY DESIGN (both corners ride along).  What this catches:
;;     - grid moved WITHOUT its anchor (no grid LINE at the insertion)
;;     - grid stretched/re-drawn (probed top at the right edge no longer
;;       matches the registered top-right height)
(defun pfa:corner-check (anchor / ed ins ext wid hgt hp out x top)
  (setq ed  (entget anchor)
        ins (cdr (assoc 10 ed))
        ext (pfa:extents anchor)
        wid (car ext)
        hgt (cadr ext)
        hp  (distof (pfa:att "HPLOT" (pfa:read-attribs anchor)) 2)
        out '())
  (if (null hp) (setq hp *pf-ref-hplot*))
  (if (not (pfa:probe-corner ins))
    (setq out (cons "no grid LINE at the anchor corner (grid moved without its anchor?)"
                    out)))
  (if (and wid hgt)
    (progn
      (setq x   (- (+ (car ins) wid) 0.1)        ; just inside the right edge
            top (pf:top-at x (cadr ins)
                           (+ (cadr ins) hgt
                              (* *pfg-top-margin* (pf:scale-factor hp)))
                           (pf:top-lines)))
      (cond
        ((null top)
         (setq out (cons "no PF-GRID-MJR top found at the right edge" out)))
        ((> (abs (- top (+ (cadr ins) hgt))) *pfa-top-tol*)
         (setq out (cons "top at max station differs from registration (grid stretched or re-drawn?)"
                         out))))))
  (reverse out))


;;; ==========================================================================
;;; SECTION 3  --  Ledger machinery  (extension dictionary + Xrecords)
;;; ==========================================================================

;; (pfa:extdict-of ent) -> extension-dictionary ename | nil   (never creates)
(defun pfa:extdict-of (ent / in out pair)
  (setq in nil out nil)
  (foreach pair (entget ent)
    (cond
      ((and (= (car pair) 102) (= (cdr pair) "{ACAD_XDICTIONARY"))
       (setq in T))
      ((and in (= (car pair) 360) (null out))
       (setq out (cdr pair)))
      ((and (= (car pair) 102) (= (cdr pair) "}"))
       (setq in nil))))
  out)

;; (pfa:ledger-dict ent create) -> PFLEDGER dictionary ename | nil
;;   HARD-OWNED (280 . 1): erasing the entity erases its ledger.
;;   OWNER-AGNOSTIC -- an ANCHOR's ledger holds META / FILES / STATUS_* / SCOPE /
;;   PASS_* / X_*; a STRUCTURE's holds MEMB.  Hence `ent`, not `anchor`.
;;   LEGACY READ + HEAL: older drawings carry the ledger under
;;   *pfa-dict-legacy*.  Read it as-is and RENAME on the first write, so the
;;   fallback drains rather than being carried forever.  A READ must not rename
;;   -- the palette reads with create nil and may never touch the database --
;;   so the rename is gated on `create`.
(defun pfa:ledger-dict (ent create / xde sub)
  (setq xde (pfa:extdict-of ent))
  (if (and (null xde) create)
    (setq xde (vlax-vla-object->ename
                (vla-getextensiondictionary
                  (vlax-ename->vla-object ent)))))
  (if xde
    (cond
      ((setq sub (dictsearch xde *pfa-dict-name*))
       (cdr (assoc -1 sub)))
      ((setq sub (dictsearch xde *pfa-dict-legacy*))
       (if create (dictrename xde *pfa-dict-legacy* *pfa-dict-name*))
       (cdr (assoc -1 sub)))
      (create
       (dictadd xde *pfa-dict-name*
                (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary")
                            (280 . 1) (281 . 1)))))
      (T nil))))

;; (pfa:dict-keys dict) -> list of entry-name strings, dictionary order
(defun pfa:dict-keys (dict / out pending pair)
  (setq out '() pending nil)
  (foreach pair (entget dict)
    (cond
      ((= (car pair) 3) (setq pending (cdr pair)))
      ((and pending (member (car pair) '(350 360)))
       (setq out (cons pending out) pending nil))))
  (reverse out))

;; (pfa:xrec-data dict key) -> data groups | nil   (header groups stripped)
(defun pfa:xrec-data (dict key / cur tail)
  (if (setq cur (dictsearch dict key))
    (progn
      (setq tail (cdr (member (assoc 100 cur) cur)))
      (if (and tail (= (caar tail) 280)) (setq tail (cdr tail)))
      tail)))

;; (pfa:xrec-put dict key data) -> xrecord ename   (create-or-replace)
(defun pfa:xrec-put (dict key data / cur old)
  (if (setq cur (dictsearch dict key))
    (progn
      (setq old (cdr (assoc -1 cur)))
      (dictremove dict key)
      (entdel old)))
  (dictadd dict key
           (entmakex (append '((0 . "XRECORD") (100 . "AcDbXrecord"))
                             data))))

;; (pfa:xrec-del dict key) -> nil
(defun pfa:xrec-del (dict key / cur old)
  (if (setq cur (dictsearch dict key))
    (progn
      (setq old (cdr (assoc -1 cur)))
      (dictremove dict key)
      (entdel old))))

;; (pfa:rec-get anchor key) -> data | nil   (generic read, never creates)
(defun pfa:rec-get (anchor key / dict)
  (if (setq dict (pfa:ledger-dict anchor nil))
    (pfa:xrec-data dict key)))

;; (pfa:rec-put anchor key data) -> xrecord ename   (generic write)
(defun pfa:rec-put (anchor key data)
  (pfa:xrec-put (pfa:ledger-dict anchor T) key data))

;; (pfa:collect-300 data) -> list of every (300 . x) value, in order
(defun pfa:collect-300 (data / out p)
  (setq out '())
  (foreach p data
    (if (= (car p) 300) (setq out (cons (cdr p) out))))
  (reverse out))


;;; ==========================================================================
;;; SECTION 4  --  Schema-2 records
;;; ==========================================================================

;;; ---- META: (70 schema)(1 .cl path)(301 .cl checksum)(302 self-handle) ----
;;; nil for any arg preserves the stored value.  (300, the crossings-table
;;; handle, retired with the table -- old records may still carry it; it is
;;; simply no longer written or read.)

(defun pfa:meta-get (anchor) (pfa:rec-get anchor "META"))

(defun pfa:meta-put (anchor tfile tcksum / dict old self)
  (setq dict (pfa:ledger-dict anchor T)
        old  (pfa:xrec-data dict "META"))
  (if (null tfile)
    (setq tfile (if (assoc 1 old) (cdr (assoc 1 old)) "")))
  (if (null tcksum)
    (setq tcksum (if (assoc 301 old) (cdr (assoc 301 old)) "")))
  (setq self (if (assoc 302 old) (cdr (assoc 302 old)) ""))  ; preserved
  (pfa:xrec-put dict "META"
                (list (cons 70 *pfa-schema-ver*)
                      (cons 1 tfile)
                      (cons 301 tcksum)
                      (cons 302 self))))

;; (pfa:stamp-self anchor) -> nil
;;   Records the anchor's OWN handle in META (302).  Called once at creation,
;;   after the block exists.  meta-put preserves it thereafter.
(defun pfa:stamp-self (anchor / dict old data)
  (setq dict (pfa:ledger-dict anchor T)
        old  (pfa:xrec-data dict "META")
        data (vl-remove-if '(lambda (p) (= (car p) 302)) old))
  (pfa:xrec-put dict "META"
                (append data (list (cons 302 (cdr (assoc 5 (entget anchor))))))))

;; (pfa:copy-p anchor) -> T when this block is a COPY of another anchor.
;;   True iff a self-handle was stamped AND it no longer matches the block's
;;   live handle (a copy gets a fresh handle but clones the stamp).  Legacy
;;   anchors with no stamp return nil -- never false-flag an existing grid.
(defun pfa:copy-p (anchor / meta self)
  (setq meta (pfa:meta-get anchor)
        self (if (and meta (assoc 302 meta)) (cdr (assoc 302 meta))))
  (and self (/= self "")
       (/= self (cdr (assoc 5 (entget anchor))))))

;; (pfa:purge-copy anchor) -> T
;;   COPY-SAFE removal: erase the block (its extension dictionary dies with
;;   it, hard-owned) WITHOUT walking the cloned PASS handles -- those point at
;;   the ORIGINAL's entities and must never be erase-by-handled.  Copied
;;   linework, if any, is left for the user to erase.  Caller holds an undo
;;   group.
(defun pfa:purge-copy (anchor)
  (entdel anchor)
  T)

;;; ---- FILES: .pro / .tin bindings + content checksums ---------------------

(defun pfa:files-get (anchor) (pfa:rec-get anchor "FILES"))

;; (pfa:files-put anchor inv invck top topck tine tind mat)  -- "" for unbound
;;   code 5 = pipe material (asserted in PFSETUP; read by the crossing label).
(defun pfa:files-put (anchor inv invck top topck tine tind mat)
  (pfa:rec-put anchor "FILES"
               (list (cons 1 (if inv inv ""))
                     (cons 2 (if top top ""))
                     (cons 3 (if tine tine ""))
                     (cons 4 (if tind tind ""))
                     (cons 5 (if mat mat ""))
                     (cons 300 (if invck invck ""))
                     (cons 301 (if topck topck "")))))

;;; ---- STUBS: identity-only registry entries in the DRAWING dictionary -----
;;; AUTO registration writes these; USER placement promotes and deletes.
;;; Keys "STUB_<TYPE>_<NAME>" in the NOD "PFTOOLS" dictionary:
;;;   (1 .cl path)(2 type)(3 name)(4 INV .pro | "")(5 TOP .pro | "")

;; (pfa:nod-dict create) -> PFTOOLS drawing dictionary ename | nil
;;   Same contract as pfa:ledger-dict: create nil NEVER writes, so a read on a
;;   drawing with no PFTOOLS dictionary returns nil instead of creating one.
;;   This is the palette-safety seam -- pfa:registry runs from a modeless
;;   handler, and opening the palette must not dirty a clean drawing.
;;   Only genuine writers pass T.
(defun pfa:nod-dict (create / nod sub)
  (setq nod (namedobjdict))
  (cond
    ((setq sub (dictsearch nod *pfset-nod-name*))
     (cdr (assoc -1 sub)))
    (create
     (dictadd nod *pfset-nod-name*
              (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary")
                          (280 . 0) (281 . 1)))))
    (T nil)))

;; ty, NOT type, in all four: `type' is a subr, and a local of that name
;; shadows it for every callee for the length of the call (2026-08-06).
(defun pfa:stub-key (ty name)
  (strcat "STUB_" (pfa:sanitize (strcase ty))
          "_" (pfa:sanitize (strcase name))))

;; (pfa:stub-get ty name) -> data | nil   (pure read)
(defun pfa:stub-get (ty name / dict)
  (if (setq dict (pfa:nod-dict nil))
    (pfa:xrec-data dict (pfa:stub-key ty name))))

;; (pfa:stub-put ty name cl inv top) -> xrecord ename   (WRITE)
(defun pfa:stub-put (ty name cl inv top)
  (pfa:xrec-put (pfa:nod-dict T) (pfa:stub-key ty name)
                (list (cons 1 cl)
                      (cons 2 (strcase ty))
                      (cons 3 (strcase name))
                      (cons 4 (if inv inv ""))
                      (cons 5 (if top top "")))))

;; (pfa:stub-del ty name) -> nil   (no dict = nothing to delete)
(defun pfa:stub-del (ty name / dict)
  (if (setq dict (pfa:nod-dict nil))
    (pfa:xrec-del dict (pfa:stub-key ty name))))

;; (pfa:stub-list) -> list of (type name cl inv top)   (pure read)
(defun pfa:stub-list ( / dict out k d)
  (setq out '())
  (if (setq dict (pfa:nod-dict nil))
    (foreach k (pfa:dict-keys dict)
      (if (= (substr k 1 5) "STUB_")
        (progn
          (setq d (pfa:xrec-data dict k))
          (setq out (cons (list (cdr (assoc 2 d)) (cdr (assoc 3 d))
                                (cdr (assoc 1 d)) (cdr (assoc 4 d))
                                (cdr (assoc 5 d)))
                          out))))))
  (reverse out))

;;; ---- GEOM: drawing-wide cached .cl geometry (content-addressed) -----------
;;; One xrecord per .cl in the NOD "PFTOOLS" dict, key "GEOM_<cl-id>".
;;; Registration (AUTO name / USER place) captures a .cl's shape ONCE and files
;;; it here; label commands READ it instead of re-tracing every run.  The store
;;; is keyed by CANONICAL .cl IDENTITY (pf:cl-id), not by a stub or anchor:
;;; identity owns the registry record, this owns the geometry, so promotion
;;; moves nothing.  Self-validating -- each entry carries the .cl content
;;; checksum it was captured at; a reader re-checksums and re-samples on
;;; mismatch, so a .cl edited on disk heals on next use.
;;;   KIND: *pf-geom-exact*  = parsed .cl vertices (z slot = vertex station)
;;;         *pf-geom-sampled* = Road-API station walk (z slot = 0.0)
;;;   (1 .cl path)(300 checksum)(70 kind)(40 sta0)(41 sta1)(10 x y sta)*  verts repeat

;; Keyed by CANONICAL .cl identity (pf:cl-id): spelling variants of one path
;; collapse to one record, and two projects' same-basename .cl no longer alias.
(defun pfa:geom-key (clfile)
  (strcat "GEOM_" (pfa:sanitize (pf:cl-id clfile))))

;; (pfa:collect-10 data) -> list of (x y) from every (10 x y z) group, in order
(defun pfa:collect-10 (data / out p)
  (setq out '())
  (foreach p data
    (if (= (car p) 10) (setq out (cons (list (cadr p) (caddr p)) out))))
  (reverse out))

;; (pfa:collect-10-sta data) -> list of (x y sta) from every (10 x y sta) group.
;;   The z slot carries the vertex STATION for EXACT records; SAMPLED (and
;;   legacy) records store 0.0 there, so sta is meaningful only when KIND=EXACT.
(defun pfa:collect-10-sta (data / out p)
  (setq out '())
  (foreach p data
    (if (= (car p) 10)
      (setq out (cons (list (cadr p) (caddr p)
                            (if (cadddr p) (cadddr p) 0.0))
                      out))))
  (reverse out))

;; (pfa:geom-get clfile) -> (checksum (s0 s1) verts kind sta-verts) | nil
;;   First three elements are unchanged for existing callers; kind + stationed
;;   verts are appended.  Records without a (70) group are read as SAMPLED.
;;   Pure read (create nil): callable from a modeless handler.
(defun pfa:geom-get (clfile / dict d ck s0 s1 kind)
  (if (and (setq dict (pfa:nod-dict nil))
           (setq d (pfa:xrec-data dict (pfa:geom-key clfile))))
    (progn
      (setq ck   (cdr (assoc 300 d))
            s0   (cdr (assoc 40 d))
            s1   (cdr (assoc 41 d))
            kind (if (assoc 70 d) (cdr (assoc 70 d)) *pf-geom-sampled*))
      (if (and ck s0 s1)
        (list ck (list s0 s1) (pfa:collect-10 d) kind (pfa:collect-10-sta d))))))

;; (pfa:geom-put clfile checksum range verts kind) -> xrecord ename
;;   range=(s0 s1).  verts entries may be (x y) or (x y sta); the station (or
;;   0.0) is written into the (10 x y sta) z slot.  kind = *pf-geom-exact* |
;;   *pf-geom-sampled*.
(defun pfa:geom-put (clfile checksum range verts kind / data v)
  (setq data (list (cons 1 clfile)
                   (cons 300 checksum)
                   (cons 70 kind)
                   (cons 40 (car range))
                   (cons 41 (cadr range))))
  (foreach v verts
    (setq data (append data (list (list 10 (car v) (cadr v)
                                        (if (caddr v) (caddr v) 0.0))))))
  (pfa:xrec-put (pfa:nod-dict T) (pfa:geom-key clfile) data))   ; WRITE

;; (pfa:registry) -> merged sorted list of (type name state ename stub)
;;   state 'ANCHORED (ename set, stub nil) | 'STUB (ename nil, stub data).
;;   THE registry: anchors + stubs, sorted by "TYPE NAME".
(defun pfa:registry ( / out e at s keys k cell)
  (setq out '())
  (foreach e (pfa:all-anchors)
    (if (not (pfa:copy-p e))                 ; copies excluded (PFCHECK reports)
      (progn
        (setq at (pfa:read-attribs e))
        (setq out (cons (list (strcase (pfa:att "UTIL" at))
                              (strcase (pfa:att "LINE" at))
                              'ANCHORED e nil)
                        out)))))
  (foreach s (pfa:stub-list)
    ;; a stub shadowed by an anchor (shouldn't happen) yields to the anchor
    (if (not (vl-member-if
               '(lambda (r) (and (= (car r) (strcase (car s)))
                                 (= (cadr r) (strcase (cadr s)))))
               out))
      (setq out (cons (list (strcase (car s)) (strcase (cadr s))
                            'STUB nil s)
                      out))))
  ;; EMPTY REGISTRY IS LEGAL and must stay silent.  acad_strlsort rejects nil
  ;; with a "Usage: (acad_strlsort <list of strings>)" banner on the command
  ;; line, so a clean drawing printed a spurious error on every palette open.
  ;; Guarded, not reordered: non-empty behaviour is unchanged.
  (setq keys (if out
               (acad_strlsort
                 (mapcar '(lambda (r) (strcat (car r) " " (cadr r))) out))
               '()))
  (mapcar
    '(lambda (k)
       (setq cell (vl-member-if
                    '(lambda (r) (= (strcat (car r) " " (cadr r)) k))
                    out))
       (car cell))
    keys))

;; (pfa:entry-cl r) -> .cl path | nil    r = a pfa:registry row
;;   THE registry row -> .cl resolution, one home: anchors read META, stubs read
;;   the stub record; "" reads as nil.  Lives here rather than in pfxlabel so
;;   pflabel can call it without violating the depend-only-upward guardrail.
(defun pfa:entry-cl (r / cl)
  (setq cl (if (eq (caddr r) 'ANCHORED)
             (cdr (assoc 1 (pfa:meta-get (nth 3 r))))
             (nth 2 (nth 4 r))))
  (if (and cl (/= cl "")) cl))

;; (pfa:nz s) -> s | nil    "" reads as nil
(defun pfa:nz (s) (if (and s (/= s "")) s))

;; (pfa:src-files type name) -> (inv-pro top-pro material) | nil
;;   Anchor first (carries material), then stub (no material).  nz-guarded.
;;   WAS pfxl:src-files, moved here 2026-08-06 with the .pro range gate: the
;;   crossing scan needs a source line's _INV to tell a real crossing from a
;;   bare alignment intersection, and pfanchor is load position 4 to pfxlabel's
;;   9, so it cannot call upward for it.  No alias left behind.
;;   THE PARAMETER IS ty, NOT type.  `type' is an AutoLISP subr, and a local of
;;   that name shadows it for everything called from inside -- which reported
;;   `bad function: "STORM"' from a palette refresh the first time this ran off
;;   the modeless path.  pfxl:src-files carried the same name harmlessly only
;;   because it was reached from command paths alone.
(defun pfa:src-files (ty name / a f stub)
  (cond
    ((setq a (pfa:find-anchor name ty))
     (setq f (pfa:files-get a))
     (list (pfa:nz (cdr (assoc 1 f)))
           (pfa:nz (cdr (assoc 2 f)))
           (pfa:nz (cdr (assoc 5 f)))))
    ((setq stub (pfa:stub-get ty name))
     (list (pfa:nz (cdr (assoc 4 stub)))
           (pfa:nz (cdr (assoc 5 stub)))
           nil))
    (T nil)))

;;; ---- TWIN: drawn plan-centerline binding per .cl (handle only) ------------
;;; The membership PRE-FILTER reads the .cl's DRAWN centerline (exact PIs, no
;;; sampled corner-cut).  Matched ONCE at registration by endpoint pair and
;;; filed as a bare HANDLE; label runs entget it LIVE, so a moved or redrawn
;;; twin reads as-drawn and never cached stale.  Nothing to invalidate -- a
;;; purged twin resolves to nil and the reader re-matches or drops the
;;; pre-filter (cl_location_at_pt still governs membership).
;;;   key "TWIN_<cl-id>":  (1 . handle)(300 . cl-checksum-at-match)
;;; Keyed by CANONICAL .cl identity (pf:cl-id), not basename.  The checksum lets
;;; the witness step tell whether the twin still matches the current .cl.

(defun pfa:twin-key (clfile)
  (strcat "TWIN_" (pfa:sanitize (pf:cl-id clfile))))

;; (pfa:twin-get clfile) -> handle string | nil   (pure read)
(defun pfa:twin-get (clfile / dict d h)
  (if (and (setq dict (pfa:nod-dict nil))
           (setq d (pfa:xrec-data dict (pfa:twin-key clfile))))
    (progn
      (setq h (cdr (assoc 1 d)))
      (if (and h (/= h "")) h))))

;; pfa:twin-cksum quarantined to _attic 2026-08-01: the "witness step" it was
;; written for was never built, so the TWIN_* group-300 checksum has no reader.

;; (pfa:twin-put clfile handle) -> xrecord ename | nil   (WRITE)
;;   Stores the drawn-twin handle plus the .cl checksum at match time.
;;   nil / "" clears the binding (no drawn twin matched -> witness unavailable);
;;   clearing on a drawing with no dictionary is a no-op, not a create.
(defun pfa:twin-put (clfile handle / ck dict)
  (if (and handle (/= handle ""))
    (progn
      (setq ck (pf:checksum-file clfile))
      (pfa:xrec-put (pfa:nod-dict T) (pfa:twin-key clfile)
                    (list (cons 1 handle) (cons 300 (if ck ck "")))))
    (if (setq dict (pfa:nod-dict nil))
      (pfa:xrec-del dict (pfa:twin-key clfile)))))
;;; ---- STATUS_<PASS>: per-tool input verdict -------------------------------
;;; state: 0 unchecked / 1 passing / 2 failing / 3 stale.
;;; UNCHECKED NEVER RENDERS GREEN.
;;;
;;; ONE RECORD PER TOOL.  A single shared "STATUS" would be written by PFSETUP,
;;; PFLABEL and PFINVERT about THREE DIFFERENT FILES, so whichever ran last
;;; erased the others' verdict.  Keyed STATUS_<PASS> to match the PASS_<name>
;;; grammar beside it, so each command writes only its own and pfa:dict-keys
;;; enumerates the set.
;;;   LABEL  -> the .cl        INVERT -> the _INV .pro
;;;   XING   -> target + source .cl, whose checksums SCOPE already holds; that
;;;             record stays the source of truth and is not copied here.
;;;
;;; STORED: the input's checksum AT PASS TIME (301).  You cannot work out later
;;; what a file WAS when it was labeled, so this is real state and it is the
;;; whole basis of "stale".
;;; NOT STORED: how many structures are done out of how many.  A saved count
;;; reads 12-of-12 forever after someone erases a label; the live gather owns
;;; that number.

(defun pfa:status-key (pass) (strcat "STATUS_" (strcase pass)))

;; (pfa:status-get anchor pass) -> data | nil
;;   Falls back to the pre-split "STATUS" record so an older anchor reports
;;   something instead of reading UNCHECKED.  That record has no pass identity,
;;   so it answers for every pass -- as much as it ever knew.
(defun pfa:status-get (anchor pass / d)
  (if (setq d (pfa:rec-get anchor (pfa:status-key pass)))
    d
    (pfa:rec-get anchor "STATUS")))

;; (pfa:status-put anchor pass state cksum findings) -> xrecord ename
(defun pfa:status-put (anchor pass state cksum findings / data f)
  (setq data (list (cons 70 state)
                   (cons 1  (pf:timestamp))
                   (cons 301 (if cksum cksum ""))))
  (foreach f findings
    (setq data (append data (list (cons 300 f)))))
  (pfa:rec-put anchor (pfa:status-key pass) data))

;; (pfa:status-reset anchor passes findings) -> nil
;;   Back to UNCHECKED for the named passes only.  PER FILE, NOT BLANKET:
;;   re-binding the _INV .pro invalidates what PFINVERT knew and says nothing
;;   about the .cl, so it must not clear PFLABEL's verdict.
(defun pfa:status-reset (anchor passes findings / p)
  (foreach p passes (pfa:status-put anchor p 0 "" findings))
  (princ))

(defun pfa:status-label (state)
  (cond ((= state 1) "PASSING")
        ((= state 2) "FAILING")
        ((= state 3) "STALE")
        (T "UNCHECKED")))

;; (pfa:status-check anchor pass file stored) -> (state . findings)
;;   THE ONE COMPARISON, shared by every writer: the input file's checksum when
;;   the pass ran, against what it is now.  State 3 ("the file changed under
;;   you") is a different fact from state 2 ("the file cannot be read at all");
;;   collapsing them loses the difference.
(defun pfa:status-check (anchor pass file stored / cur)
  (setq cur (pf:checksum-file file))
  (cond
    ((or (null stored) (= stored ""))
     (cons 0 (list (strcat "no checksum on record for " pass
                           " -- run PFSETUP (edit)"))))
    ((null cur)
     (cons 2 (list (strcat "the " pass
                           " input on record could not be read for checksum"))))
    ((= stored cur) (cons 1 '()))
    (T
     (cons 3 (list (strcat "the " pass
                           " input CHANGED since the pass -- output may be"
                           " stale; re-run PFSETUP"))))))

;; (pfa:status-roll anchor) -> (state done total stale-inputs)
;;   THE OVERALL VALUE, worked out on the fly and never stored -- nothing would
;;   update a saved roll-up when a record beneath it moved.  Worst state wins,
;;   so a single failing input cannot read green.
;;   TWO passes, not three: STATUS_XING stored the same .cl-vs-META verdict as
;;   STATUS_LABEL through the same code, so counting it made one question count
;;   twice.  Old XING records are no longer read.
(defun pfa:status-roll (anchor / worst n d p st s)
  (setq worst 1 n 0 s '())
  (foreach p '("LABEL" "INVERT")
    (setq d  (pfa:status-get anchor p)
          st (if (and d (assoc 70 d)) (cdr (assoc 70 d)) 0))
    (if (= st 0) (setq n (1+ n)))
    (if (member st '(2 3)) (setq s (cons p s)))
    ;; 2 failing beats 3 stale beats 0 unchecked beats 1 passing
    (if (> (pfa:status-rank st) (pfa:status-rank worst)) (setq worst st)))
  (list worst (- 2 n) 2 (reverse s)))

;; (pfa:status-rank state) -> sort weight; higher is worse.
(defun pfa:status-rank (state)
  (cond ((= state 2) 3) ((= state 3) 2) ((= state 0) 1) (T 0)))

;; (pfa:status-why anchor pass) -> findings strings when STALE/FAILING, else nil
;;   The read-back half of pfa:status-put's group-300 findings: the sentence
;;   explaining a bad Checks cell.  States 0/1 need no explanation, so only 2
;;   (failing) and 3 (stale) answer.  Pure ledger read, so it is legal from a
;;   modeless palette handler.
(defun pfa:status-why (anchor pass / d out c)
  (setq d (pfa:status-get anchor pass))
  (if (and d (member (cdr (assoc 70 d)) '(2 3)))
    (progn
      (setq out '())
      (foreach c d (if (= (car c) 300) (setq out (cons (cdr c) out))))
      (reverse out))))

;;; ---- SCOPE: PFXFIND discovery scope --------------------------------------

(defun pfa:scope-get (anchor) (pfa:rec-get anchor "SCOPE"))

;; (pfa:split s d) -> list of substrings split on the string d
(defun pfa:split (s d / pos out)
  (setq out '())
  (while (setq pos (vl-string-search d s))
    (setq out (cons (substr s 1 pos) out)
          s   (substr s (+ pos 1 (strlen d)))))
  (reverse (cons s out)))

;; (pfa:scope-read anchor) -> list of (sbase target-cksum source-cksum pro-cksum)
;;   THE last discovery scan's checksum record, one entry per source line.
;;   Lives here, not in pfxlabel, because pfa:xing-scan needs it and a file may
;;   only depend on files above it -- a reader at load position 4 cannot reach
;;   position 9.  Pure read.
;;   FOUR FIELDS since 2026-08-06: the source's _INV .pro checksum joined the
;;   record when its station range became a discovery filter, because a pair
;;   whose .cl are both unchanged is otherwise never re-cut -- extending a pipe
;;   would not bring its crossing back.  A short record is DROPPED, not padded:
;;   that costs one full rescan on the first run after an upgrade and then
;;   self-heals, and a padded one would claim a .pro was checked when it never
;;   was.
;;   STORED WITH *pfx-scan-schema* IN FRONT, stripped here so callers see the
;;   four fields and nothing else.  A record from another schema is dropped
;;   whole: the short-circuit means a change to what the scan ANSWERS is
;;   otherwise invisible on an unchanged drawing -- the pair is never re-cut, so
;;   the old answer stands forever.  Bump the constant with any such change.
(defun pfa:scope-read (anchor / d out s parts)
  (setq out '())
  (if (setq d (pfa:scope-get anchor))
    (foreach s (pfa:collect-300 d)
      (setq parts (pfa:split s "|"))
      (if (and (= (length parts) 5) (= (car parts) *pfx-scan-schema*))
        (setq out (cons (cdr parts) out)))))
  out)

(defun pfa:scope-put (anchor files / data f)
  (setq data (list (cons 1 (pf:timestamp))))
  (foreach f files
    (setq data (append data (list (cons 300 f)))))
  (pfa:rec-put anchor "SCOPE" data))

;;; ---- PASS_<name>: per-pass handle ledger ---------------------------------
;;; Resolved layer is stored PER PASS, never collapsed to one anchor field.
;;; A CLAYER pass records timestamp + layer + flag but NO handles
;;; (fire-and-forget -- see handoff 4.11).

(defun pfa:pass-key (name) (strcat "PASS_" (strcase name)))

(defun pfa:pass-get (anchor name)
  (pfa:rec-get anchor (pfa:pass-key name)))

(defun pfa:pass-put (anchor name layer clayer-p handles / data h)
  (setq data (list (cons 1 (pf:timestamp))
                   (cons 8 layer)
                   (cons 70 (if clayer-p 1 0))))
  (if (not clayer-p)
    (foreach h handles
      (setq data (append data (list (cons 300 h))))))
  (pfa:rec-put anchor (pfa:pass-key name) data))

;; (pfa:pass-handles anchor name) -> list of handle strings on record
(defun pfa:pass-handles (anchor name / data)
  (if (setq data (pfa:pass-get anchor name))
    (pfa:collect-300 data)))

;; (pfa:pass-names anchor) -> list of pass names on record ("LABEL" ...)
(defun pfa:pass-names (anchor / dict out k)
  (setq out '())
  (if (setq dict (pfa:ledger-dict anchor nil))
    (foreach k (pfa:dict-keys dict)
      (if (= (substr k 1 5) "PASS_")
        (setq out (cons (substr k 6) out)))))
  (reverse out))

;; (pfa:erase-pass anchor name) -> count of entities erased
;;   The erase-by-handle contract: erases exactly the entities this pass
;;   drew (live handles only), then drops the pass record.  Caller must
;;   hold an open undo group.
(defun pfa:erase-pass (anchor name / hs h e n dict)
  (setq n 0)
  (foreach h (pfa:pass-handles anchor name)
    (if (and (setq e (handent h)) (entget e))
      (progn (entdel e) (setq n (1+ n)))))
  (if (setq dict (pfa:ledger-dict anchor nil))
    (pfa:xrec-del dict (pfa:pass-key name)))
  n)


;;; ==========================================================================
;;; SECTION 4b  --  The membership index  (structure -> lines, saved)
;;; ==========================================================================
;;; THE PROBLEM: PFLABEL, PFINVERT and PFREPORT each re-derive which structures
;;; sit on which lines, from scratch, on an unchanged drawing.  The facts are
;;; stable; nothing persisted them.
;;;
;;; THE RECORD IS THE RETURN SHAPE.  pf:lines-at-point takes a point and gives
;;; back the set of lines it falls on; that IS what is stored, in the order it
;;; came back (offset-ascending -- re-sorting on write would make the reader
;;; non-identical to the function it stands in for).  A set with more than one
;;; entry is a junction, with no cross-line read.
;;;
;;; IN: structure, line, station, and the stamps that say when to stop believing
;;; it.  OUT: anything needing a .pro -- inverts, cover, clearance, wall
;;; thickness.  Membership is stable and .pro churns through design, so caching
;;; the second would produce a record that is wrong most of the time.  Crossings
;;; are out too: X_* already persists them with additive merge.
;;;
;;; STAMPS.  A LINE stamp folds everything that can change one line's answer
;;; into one token: the .cl's CONTENT (pf:cl-id is a canonical PATH and cannot
;;; see an edit), the station range that gates a hit, the corridor width, and a
;;; hash of the pre-filter shape.  A ROSTER stamp folds every line's stamp into
;;; one.
;;;
;;; WHY A ROSTER STAMP, NOT PER-LINE STAMPS.  A record lists HITS and never says
;;; which lines were tested and missed, so per-line stamps cannot answer "was
;;; this worked out when the world looked like it does now" -- a structure that
;;; was off BA and is now on it would read clean forever, because its record
;;; never mentions BA.  One stamp over the whole roster does answer it: a match
;;; means the hits are complete AND the misses are still misses.  The cost is
;;; that any .cl edit stales every record; geometry does not churn, and a
;;; rebuild is one command.
;;;
;;; Documented in pfanchor/INDEX-PLAN.md; INDEX-DESIGN.md and INDEX-VALUES.md
;;; hold the reasoning that got here.

;;; ---- Registry + selection helpers ----------------------------------------
;;; Registry/selection knowledge rather than label knowledge, and the index
;;; writer at position 4 cannot reach up to pflabel at 7.  No alias left behind;
;;; same precedent as pfa:entry-cl.

;; (pfa:build-lines pairs) -> line table: (clfile name lo hi verts tol bbox)*
;;   GATHER-PATH PURITY: this runs from the run dialogs and setup, BEFORE any
;;   undo group (and from a modeless palette handler), so it must not write the
;;   drawing: pf:cl-geom is called read-only (a cache miss re-samples, never
;;   files) and a re-matched twin is USED for this run but NOT filed --
;;   persisting GEOM/TWIN belongs to PFSETUP registration and PFXLABEL
;;   discovery, which run in a command context.  Cost of an unfiled twin: one
;;   ssget scan per un-filed line per run.
;;   ONE EXCEPTION, and it is opt-in: PFINDEX Build binds *pfa-file-geom* T and
;;   opens its undo group FIRST, so the GEOM cache gets filed for every line
;;   while a U can still peel it.  Nothing else may set that flag.  The TWIN
;;   binding is still never filed here -- persisting a wrong polyline match is a
;;   quieter fault than an occasional extra scan.
;;   Publishes *pfa-roster* as a side effect -- see pfa:roster-set.
(setq *pfa-lentry-memo* '())      ; (file ck dbmod geom vhash) -- pfa:line-geom
;; T only inside PFINDEX Build, which binds it as a LOCAL so dynamic scope hands
;; it back on any exit, Esc included.  Nothing else may set it: it turns the
;; gather path into a WRITER, which is legal only inside an open undo group.
(setq *pfa-file-geom* nil)

;; (pfa:line-geom file) -> (lo hi verts tol bbox) | nil
;;   ONE line's derived geometry, cached per .cl.
;;   NOTHING HERE DEPENDS ON WHICH ANCHOR IS PRIMARY: pfa:registry-pairs returns
;;   every line of the same type, so target A and target B build the SAME rows
;;   out of the same files.  Clicking line to line therefore re-read every .cl
;;   and re-matched every twin from scratch, once per target -- a per-target
;;   memo cannot help that, because the key changes with the target.  This one
;;   is keyed on the FILE, so the second target pays nothing.
;;   The name is NOT cached: it is registry metadata, not derived work, and the
;;   primary's name comes off the anchor rather than the registry.
;;   ck covers the file; DBMOD covers the twin, which is drawing geometry and
;;   moves with no .cl edit.  Bounded by the registry, so no cap is needed --
;;   unlike the target-keyed memos, which grow without one.
(defun pfa:line-geom (file / ck dm cell geom rng vts tol h out)
  (setq ck   (pf:checksum-file file)
        dm   (getvar "DBMOD")
        ;; FILING BYPASSES THE MEMO BOTH WAYS: a hit would skip the pf:cl-geom
        ;; write that *pfa-file-geom* is FOR, and an entry stored during a Build
        ;; would be keyed on a DBMOD the write itself has already moved.
        cell (if *pfa-file-geom* nil (assoc file *pfa-lentry-memo*)))
  (cond
    ((and cell ck (equal (cadr cell) ck) (equal (caddr cell) dm))
     (cadddr cell))                            ; HIT -- no .cl read, no twin scan
    ((null (setq geom (pf:cl-geom file *pfa-file-geom*)))
     nil)
    (T
     (setq rng (car geom)
           ;; membership pre-filter = the DRAWN twin's LIVE verts (exact PIs,
           ;; no sampled corner-cut at deflections), read via the filed handle
           h   (pfa:twin-get file)
           vts (pf:twin-verts h)
           tol nil)                            ; exact shape -> exact corridor
     ;; twin missing from the store (pre-feature registry, New-placed line,
     ;; purged handle): re-match for THIS run only -- no pfa:twin-put here
     (if (null vts)
       (progn
         (setq h (pf:cl-twin-handle file *pf-corridor*))
         (if h (setq vts (pf:twin-verts h)))))
     ;; STILL nothing drawn to match -- registered-only lines never have a
     ;; twin, and they are exactly what pfa:registry-pairs adds.  Fall back
     ;; to the .cl's own SAMPLED shape from (cdr geom): a coarse corridor,
     ;; but a corridor.  Shipping nil turns the pre-filter OFF for those
     ;; lines, and every structure then reaches cl_location_at_pt -- the
     ;; "unable to locate point along centerline" parade.
     (if (and (null vts) (cdr geom))
       (setq vts (cdr geom)
             tol *pf-corridor-sampled*))       ; corner-cut allowance
     ;; bbox computed ONCE here; it is consulted per structure per line
     (setq out (list (car rng) (cadr rng) vts tol (pf:verts-bbox vts)))
     (if (and ck (null *pfa-file-geom*))
       (setq *pfa-lentry-memo*
               (cons (list file ck dm out (pf:verts-hash vts))
                     (vl-remove-if '(lambda (c) (= (car c) file))
                                   *pfa-lentry-memo*))))
     out)))

;; (pfa:vhash file verts) -> the verts hash, cached beside the geometry.
;;   pf:verts-hash walks every vertex, and pfa:roster-set asks for one PER LINE
;;   at the tail of every pfa:build-lines -- so a table built entirely from
;;   cached geometry still paid 68 full vertex walks.  That cost is what a
;;   per-target table memo used to hide; caching the hash here removes the need
;;   for one.  Validated exactly as pfa:line-geom keys, so a hit means the same
;;   .cl and the same drawing; anything else recomputes.
(defun pfa:vhash (file verts / cell)
  (setq cell (assoc file *pfa-lentry-memo*))
  (if (and cell
           (nth 4 cell)
           (equal (cadr cell) (pf:checksum-file file))
           (equal (caddr cell) (getvar "DBMOD")))
    (nth 4 cell)
    (pf:verts-hash verts)))

(defun pfa:build-lines (pairs / tbl file nm g entry p)
  (setq tbl '())
  (foreach p pairs
    (setq file (car p) nm (cdr p))
    (if (setq g (pfa:line-geom file))
      (progn
        (setq entry (list file nm (car g) (cadr g) (caddr g) (cadddr g)
                          (nth 4 g))
              tbl   (cons entry tbl))
        ;; PROGRESS: one line per line in the gather set.  Suppressed under
        ;; *pf-quiet* -- a palette click runs this same path.  The error below
        ;; is a FINDING and still prints.
        (pf:progress (strcat "\nLoaded line '" nm "' (Sta " (pf:fmt-station (car g))
                        " to " (pf:fmt-station (cadr g)) ")"
                        (cond
                          ((null (caddr g))
                           "  [no shape available -- pre-filter off, authored test only].")
                          ((cadddr g)
                           "  [no drawn centerline matched -- sampled .cl corridor].")
                          (T ".")))))
      (prompt (strcat "\nError: Could not read station range from " file))))
  (setq tbl (reverse tbl))
  (pfa:roster-set tbl nil)          ; the run's read-side stamp, memo-fast
  tbl)

;; (pfa:gather-inlets) -> block enames matching a *pf-rule-table* rule
;;   Model space only: a paper-space INSERT has sheet coordinates, which
;;   pf:lines-at-point would test against real-world stationing.
(defun pfa:gather-inlets ( / ss i e nm lst)
  (setq ss (ssget "_X" '((0 . "INSERT") (410 . "Model"))) lst '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq e  (ssname ss i)
            nm (cdr (assoc 2 (entget e))))
      (if (pf:rule-for nm *pf-rule-table*)
        (setq lst (cons e lst)))
      (setq i (1+ i))))
  (reverse lst))

;;; ---- Stamps --------------------------------------------------------------

(if (not (boundp '*pfa-roster*)) (setq *pfa-roster* nil))

;; (pfa:line-stamp entry write-p) -> string    one line, folded to one token.
;;   entry = a pfa:build-lines row.  write-p T takes the memo-BYPASSING
;;   checksum: a stamp about to be stored must not inherit pf:checksum-file's
;;   (path, mtime, size) shortcut, because that wrong answer would be persisted
;;   rather than dying with the session.
(defun pfa:line-stamp (entry write-p / ck vh)
  (setq ck (if write-p
             (pf:checksum-strict (car entry))
             (pf:checksum-file  (car entry)))
        ;; write-p bypasses the hash cache for the same reason it bypasses
        ;; pf:checksum-file: that cache is VALIDATED by the (mtime, size)
        ;; shortcut, and a stamp about to be PERSISTED must not inherit it.
        vh (if write-p
             (pf:verts-hash (nth 4 entry))
             (pfa:vhash (car entry) (nth 4 entry))))
  (strcat (cadr entry)
          "|" (if ck ck "?")
          "|" (rtos (nth 2 entry) 2 4)
          "|" (rtos (nth 3 entry) 2 4)
          "|" (if (nth 5 entry) (rtos (nth 5 entry) 2 4) "-")
          "|" (if vh vh "-")))

;; (pfa:roster-stamp lines write-p) -> string   the whole line table, folded.
;;   Sorted before folding so the stamp does not depend on table order, which
;;   varies with which line is primary.  The schema number rides in front: it is
;;   the only cover for *pf-offset-tol* / *pf-range-eps*, which are applied
;;   inside pf:lines-at-point where no per-line stamp can see them.
(defun pfa:roster-stamp (lines write-p / parts)
  (setq parts (mapcar '(lambda (e) (pfa:line-stamp e write-p)) lines))
  (strcat (itoa *pf-index-schema*) "/"
          (pf:hash-string (pf:join (if parts (acad_strlsort parts) '()) ";"))))

;; (pfa:roster-set lines write-p) -> the stamp   publishes *pfa-roster*.
;;   ONE assignment threads the roster through every reader instead of a new
;;   argument on eight call sites.  Run-scoped derived state, the same pattern
;;   as *pf-layer* / *pf-style* -- not a user option, which would belong in the
;;   order ticket (root README 6b).
(defun pfa:roster-set (lines write-p)
  (setq *pfa-roster* (pfa:roster-stamp lines write-p)))

;;; ---- The MEMB record -----------------------------------------------------
;;;   (10 x y 0.0)                    insertion point as indexed
;;;   (302 . roster-stamp)            what the lines looked like at the time
;;;   (300 . name)(40 . station)      repeating, in pf:lines-at-point order

(setq *pfa-memb-key* "MEMB")

;; (pfa:memb-put ent pt hits roster) -> xrecord ename   WRITE
;;   Caller must hold an open undo group.
(defun pfa:memb-put (ent pt hits roster / data h)
  (setq data (list (list 10 (car pt) (cadr pt) 0.0)
                   (cons 302 roster)))
  (foreach h hits
    (setq data (append data (list (cons 300 (car h)) (cons 40 (cadr h))))))
  (pfa:xrec-put (pfa:ledger-dict ent T) *pfa-memb-key* data))

;; (pfa:memb-get ent roster) -> (T . ((name sta) ...)) | nil    PURE READ
;;   The cons is not decoration: a structure genuinely on NO line has an empty
;;   hit list, and in AutoLISP nil and '() are the same object -- returning the
;;   list bare would make "no record" and "on nothing" indistinguishable, so
;;   every off-line structure would re-derive on every run forever.
;;   nil means: index off, no record, roster moved, or the structure moved.
(defun pfa:memb-get (ent roster / dict d pt live out nm cur)
  (if (and *pf-index-on*
           roster
           (setq dict (pfa:ledger-dict ent nil))       ; create nil: never writes
           (setq d    (pfa:xrec-data dict *pfa-memb-key*))
           (setq pt   (cdr (assoc 10 d)))
           (equal (cdr (assoc 302 d)) roster)
           (setq live (cdr (assoc 10 (entget ent))))
           (<= (distance (list (car pt) (cadr pt))
                         (list (car live) (cadr live)))
               *pfa-memb-move-tol*))
    (progn
      (setq out '() nm nil)
      (foreach cur d
        (cond
          ((= (car cur) 300) (setq nm (cdr cur)))
          ((and nm (= (car cur) 40))
           (setq out (cons (list nm (cdr cur)) out) nm nil))))
      (cons T (reverse out)))))

;; (pfa:lines-at ent pt lines) -> ((name station) ...)      THE READ SEAM.
;;   Serves the saved record when it is trustworthy; otherwise does exactly what
;;   every caller did before it existed.  NEVER WRITES, so it is legal on the
;;   gather path and from a modeless palette handler.  Reads *pfa-roster*, which
;;   pfa:build-lines published for this run.
(defun pfa:lines-at (ent pt lines / r)
  (if (setq r (pfa:memb-get ent *pfa-roster*))
    (cdr r)
    (pf:lines-at-point pt lines)))

;; (pfa:memb-sync ent pt lines roster) -> T when a record was written
;;   THE TOP-UP.  Engine-side only -- caller holds an open undo group.  Writes
;;   nothing when the record is already current, so a second run over the same
;;   structures is free.
;;   CATCH-WRAPPED ON PURPOSE: a structure on a locked layer refuses the
;;   dictadd, and a caching optimisation must never be able to kill a labeling
;;   run.  That structure simply goes uncached, and PFINDEX reports it.
(defun pfa:memb-sync (ent pt lines roster / r)
  (cond
    ((not *pf-index-on*) nil)
    ((null roster) nil)
    ((pfa:memb-get ent roster) nil)             ; already current
    (T
     (setq r (vl-catch-all-apply
               'pfa:memb-put
               (list ent pt (pf:lines-at-point pt lines) roster)))
     (not (vl-catch-all-error-p r)))))


;;; ==========================================================================
;;; SECTION 4c  --  The gather  (membership -> pending -> status)
;;; ==========================================================================
;;; Membership-and-ledger knowledge, not label knowledge: nothing here calls
;;; into pflabel, and each function reaches only pfanchor (position 4) or
;;; pftools-lib (position 2).
;;; It lives at 4 because the palette at 11 needs per-target counts: with the
;;; gather at 7 the palette would have to reach sideways into pflabel, and
;;; pfanchor -- which every module already depends on -- could not serve it,
;;; since 4 cannot reach up to 7.  The three label commands, pfreport and the
;;; palette now resolve membership through ONE path.
;;; ALL PURE READS -- the palette contract holds throughout.

(defun pfa:line-loaded-p (name lines)
  (car (vl-member-if '(lambda (e) (= (cadr e) name)) lines)))

;; (pfa:registry-pairs primary-cl) -> list of (path . name)
;;   Every OTHER registry entry's .cl -- anchors AND stubs.  The self-maintaining
;;   secondary set.  Stubs count because membership is plan-view station math and
;;   IDENTITY IS ENOUGH: a registered line still contributes to a junction's
;;   combined ID.
;;   SAME-UTILITY-TYPE only: a STORM profile's junctions are other STORM lines.
;;   A different type sharing a station is a CROSSING, which is PFXLABEL's job.
;;   ONE BUILDER: a thin filter over pfa:registry -- the merged, COPY-EXCLUDING,
;;   sorted walk -- resolved via pfa:entry-cl, self dropped by canonical identity
;;   (pf:cl-id).  Consumers: both setups, both run dialogs, pfreport, and
;;   pfa:target-counts.  PFLABEL and PFINVERT cannot disagree about a junction's
;;   line set by construction.
(defun pfa:registry-pairs (primary-cl / out r clf ptype pid)
  (setq out '() ptype (pf:type-of primary-cl) pid (pf:cl-id primary-cl))
  (foreach r (pfa:registry)
    (if (and (setq clf (pfa:entry-cl r))
             (/= (pf:cl-id clf) pid)                ; drop self
             (= (pf:type-of clf) ptype))            ; same type only
      (setq out (cons (cons clf (cadr r)) out))))
  (reverse out))

;; (pfa:idx-add-hits idx hits) -> idx, each hit's station filed under its line
(defun pfa:idx-add-hits (idx hits / h)
  (foreach h hits (setq idx (pf:idx-add idx (car h) (cadr h))))
  idx)

;; (pfa:idx-sort idx) -> the same index with every bucket ascending
(defun pfa:idx-sort (idx)
  (mapcar '(lambda (pair) (cons (car pair) (vl-sort (cdr pair) '<))) idx))

;; (pfa:index-stations inlets lines) -> ((name . sorted-stations) ...)
;;   The RANKING input: every station on every line, so pf:rank-on-line can count
;;   how many structures precede one.  Moved down from pflabel 2026-08-03 -- the
;;   palette at position 11 needs the ranked NAME and this file at 4 can serve it,
;;   and pfreport and pf2sew were already reaching across for it.
;;   THE PRIMARY-LINE PATHS DO NOT CALL THIS.  pfa:pending folds the same index
;;   out of the walk it was already making, so this standalone version is for the
;;   callers that have a line table but no single primary (pfreport, pf2sew).
(defun pfa:index-stations (inlets lines / idx e pt)
  (setq idx '())
  (foreach e inlets
    (setq pt  (cdr (assoc 10 (entget e)))
          idx (pfa:idx-add-hits idx (pfa:lines-at e pt lines))))
  (pfa:idx-sort idx))

;; (pfa:id-for-hits hits index) -> "AA-1/BB-2" | ""   ("" = on no named line)
;;   THE DRAWN NAME -- the combined ID that goes on the sheet, derived from the
;;   structure's line membership and its rank on each line.
;;   ONE COPY: pflabel:process-structure composed this inline until 2026-08-03
;;   and now calls here, so the palette's Item column, the run dialog's list and
;;   the text actually drawn cannot drift apart.
(defun pfa:id-for-hits (hits index / infos)
  (setq infos (pf:sort-line-infos-alpha hits))
  (if (null infos)
    ""
    (pf:combine-id
      (mapcar 'car infos)
      (mapcar '(lambda (li)
                 (pf:rank-on-line (cadr li) (cdr (assoc (car li) index))
                                  *pf-rank-ascending* *pf-range-eps*))
              infos))))

;; (pfa:pending inlets lines primary) -> (((sta ename blkname hits) ...) index)
;;   Every structure on the PRIMARY line sorted by station, AND the station index
;;   for every line -- ONE walk, because both are folds over the same membership
;;   hits.  Building the index separately meant a second inlets x lines product.
;;   EACH ROW CARRIES ITS HITS at position 3, so the name can be derived later
;;   without a second lines-at.  Nothing else reads position 3 of a pending row:
;;   pfi:merge-nodes builds its own list and puts the mates there.
(defun pfa:pending (inlets lines primary / out idx e pt hits ph)
  (setq out '() idx '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (pfa:lines-at e pt lines)
          idx  (pfa:idx-add-hits idx hits)
          ph   (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
    (if ph (setq out (cons (list (cadr ph) e (cdr (assoc 2 (entget e))) hits)
                           out))))
  (list (vl-sort out '(lambda (a b) (< (car a) (car b))))
        (pfa:idx-sort idx)))

;; (pfa:pass-xs anchor passname) -> (all-xs sta-xs)
;;   TWO LISTS OUT OF ONE WALK, because the two halves of status ask opposite
;;   questions.  [LABELED] asks whether ANY pass entity sits at a structure, so
;;   it takes everything.  DRIFT asks the reverse, and it cannot: a label
;;   stack's text columns straddle the station -- 1h left, then 1h, 2.5h, 4h
;;   right (pfdraw:75) -- while eps is 1.5h, so every stack of three rows or
;;   more read as an orphan and the Commands tab said Incorrect on every line.
;;   The station line is the one entity AT the station and there is exactly one
;;   per structure, so sta-xs counts stacks, not columns.
;;   LWPOLYLINE separates them with no ledger change -- pflabel:448 draws TEXT
;;   rows and one station line and nothing else, so drawings labeled before
;;   this read correctly too.  PFINVERT draws no station line, so its sta-xs is
;;   empty and its DRIFT echo goes quiet; at a 4h offset it was false positives.
(defun pfa:pass-xs (anchor passname / out sta h e ed p)
  (setq out '() sta '())
  (foreach h (pfa:pass-handles anchor passname)
    (if (and (setq e (handent h)) (setq ed (entget e))
             (setq p (cdr (assoc 10 ed))))
      (progn
        (setq out (cons (car p) out))
        (if (= (cdr (assoc 0 ed)) "LWPOLYLINE")
          (setq sta (cons (car p) sta))))))
  (list out sta))

;; (pfa:labeled-x-p x xs eps) -> T when a pass entity sits at this X
;;   Symmetric in its two arguments -- also used the other way round, to ask
;;   whether a STRUCTURE sits at a given pass entity's X (see orphan-xs).
(defun pfa:labeled-x-p (x xs eps / found v)
  (setq found nil)
  (foreach v xs
    (if (<= (abs (- v x)) eps) (setq found T)))
  found)

;; (pfa:cluster-xs xs eps) -> one representative X per eps-cluster
;;   Still needed now that drift reads station lines only: Pick mode APPENDS to
;;   the ledger, so a structure labeled twice leaves two station lines at one X
;;   and would otherwise count as two stranded labels.
(defun pfa:cluster-xs (xs eps / out v)
  (setq out '())
  (foreach v xs
    (if (not (pfa:labeled-x-p v out eps)) (setq out (cons v out))))
  (reverse out))

;; (pfa:orphan-xs pend sta-xs eps xf) -> station-line X ordinates with no structure
;;   THE DRIFT DETECTOR, the reverse of the [LABELED] test: labeled-x-p asks
;;   "does a label sit at this structure?", this asks "does a structure sit under
;;   this label?"  A no means the structure MOVED or was ERASED after labeling,
;;   and the label is now at a stale station.
;;   No stored position is needed -- THE DRAWN LABELS ARE THE RECORD of where the
;;   structures were, and the sheet is also the thing that is wrong.
;;   Degrades honestly: a moved structure reads Outstanding at its new station
;;   AND leaves an orphan at its old one.  Two signals, one event.
(defun pfa:orphan-xs (pend xs eps xf / sxs out v)
  (setq sxs (mapcar '(lambda (p) (pf:station->profile-x (car p) xf)) pend)
        out '())
  (foreach v (pfa:cluster-xs xs eps)
    (if (not (pfa:labeled-x-p v sxs eps)) (setq out (cons v out))))
  (reverse out))

;;; ---- The gather memo  (SESSION-scoped; not a drawing write) --------------
;;; The membership product is inlets x lines, and it was recomputed from scratch
;;; on every run, target switch and cancelled dialog.  This memoises ONLY that
;;; product.  build-lines still runs fresh each time -- it is O(lines) rather
;;; than O(lines x structures), and running it keeps the twin verts LIVE, so a
;;; moved plan centerline can never be served stale out of here.
;;;
;;; AutoLISP globals are per-document, so this is naturally per-drawing.  It
;;; touches no database: a LISP variable, legal from a modeless handler, and it
;;; survives a cancelled dialog -- the case that used to throw a gather away.
;;;
;;; THE KEY IS THE WHOLE INPUT SET, and every part of it is cheap.  This memo
;;; holds (pend index), so the key is exactly what pfa:pending reads:
;;;   primary                   which line is being asked about
;;;   inlet signature           (handle x y) per structure -- catches ADD, ERASE
;;;                             and MOVE, the full set of things that can change
;;;                             membership
;;;   line signature            per line: name, range, corridor tol, bbox and
;;;                             vertex count -- catches a re-bound .cl, a moved
;;;                             twin, a registry add/remove
;;; A stale entry cannot be served: anything that would change the answer is in
;;; the key.  Nothing is derived-and-trusted.
;;;
;;; NOT IN THE KEY -- anchor, pass name, pass X ordinates.  None are inputs to
;;; pending.  Status now recomputes every call (pfa:status-for), so drawing a
;;; label no longer throws away a walk it never invalidated.

;; PLAIN setq, not a boundp guard: the stored VALUE SHAPE changed on 2026-08-03
;; (pend -> (pend index)), so an entry left in a live session by the previous
;; load would be read with the wrong accessor and serve a pending ROW as the
;; whole list.  A cache that survives a reload of the file that defines its shape
;; is the bug; the cost of clearing it is one gather.
(setq *pfa-gather-memo* '())
(setq *pfa-memo-max* 8)        ; a few targets stay warm; no unbounded growth

;; (pfa:inlet-sig inlets) -> ((handle x y) ...)
(defun pfa:inlet-sig (inlets / out e ed p)
  (setq out '())
  (foreach e inlets
    (if (and (setq ed (entget e)) (setq p (cdr (assoc 10 ed))))
      (setq out (cons (list (cdr (assoc 5 ed)) (car p) (cadr p)) out))))
  (reverse out))

;; (pfa:lines-sig lines) -> ((name lo hi tol bbox nverts) ...)
;;   Derived from the table just built, so it costs a walk of a list already
;;   in hand.  bbox + vertex count catch a shape change; the range catches a
;;   re-bound .cl; the list itself catches a registry add or remove.
(defun pfa:lines-sig (lines / out e)
  (setq out '())
  (foreach e lines
    (setq out (cons (list (cadr e) (nth 2 e) (nth 3 e) (nth 5 e) (nth 6 e)
                          (length (nth 4 e)))
                    out)))
  (reverse out))

;; assoc by `equal` -- AutoLISP's assoc is not dependable on list keys
(defun pfa:memo-get (key memo / hit c)
  (foreach c memo (if (and (null hit) (equal (car c) key)) (setq hit c)))
  hit)

(defun pfa:memo-put (key val memo / out n)
  (setq out (list (cons key val)) n 1)
  (foreach c memo
    (if (and (< n *pfa-memo-max*) (not (equal (car c) key)))
      (setq out (cons c out) n (1+ n))))
  (reverse out))

;; (pfa:gather-for primary lines inlets) -> (pend index)
;;   THE EXPENSIVE HALF, split out of gather-compute so ONE walk serves MANY
;;   passes -- the Commands tab shows Structure and Invert counts side by side,
;;   and asking gather-compute twice meant two identical inlets x lines walks.
;;   Assumes primary is loaded in lines; gather-compute holds that guard.
(defun pfa:gather-for (primary lines inlets / key hit res)
  (setq key (list primary
                  (pfa:inlet-sig inlets)
                  (pfa:lines-sig lines)))
  (if (setq hit (pfa:memo-get key *pfa-gather-memo*))
    (cdr hit)                                 ; HIT -- no inlets x lines walk
    (progn
      (setq res (pfa:pending inlets lines primary)
            *pfa-gather-memo*
                 (pfa:memo-put key res *pfa-gather-memo*))
      res)))

;; (pfa:pend-for primary lines inlets) -> ((sta ename blkname hits) ...)
(defun pfa:pend-for (primary lines inlets)
  (car (pfa:gather-for primary lines inlets)))

;; (pfa:index-for primary lines inlets) -> ((name . sorted-stations) ...)
;;   The ranking index for the same walk, off the same memo entry -- so a caller
;;   that already has pend pays nothing for it.  It does not depend on primary;
;;   the key does only because pend does, and recomputing pend is what makes the
;;   index free in the first place.
(defun pfa:index-for (primary lines inlets)
  (cadr (pfa:gather-for primary lines inlets)))

;; (pfa:status-for anchor passname pend xform) -> (status orphans)
;;   THE CHEAP HALF: a handle walk (pass-xs) plus arithmetic per structure, so
;;   it is recomputed every call rather than memoised.  That is the point --
;;   status describes what is DRAWN RIGHT NOW, and a stored answer goes stale
;;   the moment a pass is drawn.  Call it once per pass over one shared pend.
;;   xs is pass-xs' PAIR: (car xs) every entity for [LABELED], (cadr xs) the
;;   station lines for drift.
(defun pfa:status-for (anchor passname pend xform / xs eps status p)
  (setq xs     (pfa:pass-xs anchor passname)
        eps    (max *pfa-recon-eps*
                    (* 1.5 (pf:text-height (pf:xf-hplot xform))))
        status '())
  (foreach p pend
    (setq status
          (append status
                  (list (pfa:labeled-x-p
                          (pf:station->profile-x (car p) xform) (car xs) eps)))))
  (list status (pfa:orphan-xs pend (cadr xs) eps xform)))

;; (pfa:gather-compute anchor passname primary lines inlets)
;;   -> (pend status orphans) | nil        nil = the primary line never loaded
;;
;;   THE ONE GATHER-COMPUTE, shared by PFLABEL and PFINVERT: both ask the
;;   identical question -- which structures are on this line, and which already
;;   carry a label from THIS pass -- and only the pass name varies, which was
;;   already a parameter.  `.pro` never enters here; PFINVERT's profile work is
;;   downstream in the engine.
;;   The dialog FILLS stay local to each command, because tile names belong to
;;   their own DCL.  Only the dialog-blind part is shared, which is what makes
;;   this callable from a modeless palette handler.
(defun pfa:gather-compute (anchor passname primary lines inlets
                            / pend xf so orphans stas res)
  (if (not (pfa:line-loaded-p primary lines))
    nil
    (progn
      (setq xf   (pfa:anchor->xform anchor)
            pend (pfa:pend-for primary lines inlets)
            so   (pfa:status-for anchor passname pend xf)
            res  (list pend (car so) (cadr so)))
      ;; DRIFT ECHO -- printed, never persisted, and printed on a memo HIT too:
      ;; it describes the DRAWING, not the freshness of this computation.
      ;; STATUS means "correct as of the last pass" and drift accumulates
      ;; BETWEEN passes, so a stored flag would read clean one command after it
      ;; stopped being true.  This is the command-line half of the live view.
      (if (setq orphans (caddr res))
        (progn
          (setq stas (mapcar '(lambda (v)
                                (pf:fmt-station (pf:profile-x->station v xf)))
                             orphans))
          ;; Advisory, and the palette renders the same fact in detailsList's
          ;; Drift row -- so under *pf-quiet* it is a DUPLICATE, not a loss.
          (pf:progress (strcat "\n  DRIFT: " (itoa (length orphans))
                          " label(s) with no structure -- something moved since"
                          " the last pass."
                          "\n         Sta " (pf:join stas ", ")
                          "\n         Re-run with Label All to replace the pass"
                          " (the anchor and the .cl are not implicated)."))))
      res)))

;; (pfa:line-table anchor) -> (primary lines) | nil
;;   THE target -> line-set resolution, one home.  Four call sites built this
;;   by hand (both setups, both run dialogs); they now all come here.
;;   nil = no xform on record, or no .cl bound.  Pure read.
;;   NOT memoised per target, deliberately: the caching lives one level down, on
;;   pfa:line-geom / pfa:vhash, which key on the .cl FILE.  A target-keyed memo
;;   duplicates every line's vertices once per cached target and still misses on
;;   the click that matters -- moving from line to line changes the key every
;;   time, which is the whole workload.
(defun pfa:line-table (anchor / xf cl primary pairs)
  (setq xf (pfa:anchor->xform anchor))
  (if (or (null xf) (null (setq cl (pf:xf-get 'clfile xf))))
    nil
    (progn
      (setq primary (pf:xf-get 'name xf)
            pairs   (pf:dedupe-pairs
                      (cons (cons cl primary) (pfa:registry-pairs cl))))
      (list primary (pfa:build-lines pairs)))))

;; (pfa:target-counts anchor) -> alist | nil       nil = not an anchored target
;;   THE per-target roll-up the palette's Commands tab reads.  Worked out on read
;;   and never stored, like pfa:status-roll: nothing would update a saved summary
;;   when a record beneath it moved.
;;   ONE pend walk serves BOTH label passes -- that is what pfa:pend-for is for.
;;   Crossings come off the ledger, so they are nearly free.
;;   Keys: primary lines structures label-done label-out invert-done invert-out
;;         crossings xing-done xing-out drift
;;   Pure reads throughout -- legal from a modeless handler.
(defun pfa:target-counts (anchor / lt primary lines inlets pend xf
                                   lab inv work recon n nd e)
  (setq lt (pfa:line-table anchor))
  (if (null lt)
    nil
    (progn
      (setq primary (car lt)
            lines   (cadr lt)
            xf      (pfa:anchor->xform anchor))
      (if (not (pfa:line-loaded-p primary lines))
        nil
        (progn
          (setq inlets (pfa:gather-inlets)
                pend   (pfa:pend-for primary lines inlets)
                lab    (pfa:status-for anchor "LABEL"  pend xf)
                inv    (pfa:status-for anchor "INVERT" pend xf)
                ;; SPLIT, not the raw ledger: the Crossings count and the
                ;; lvwCommand list are read side by side, and pfa:xing-find
                ;; re-tests its rows -- a raw count here would say 2 beside a
                ;; list of 1.  `inlets` is handed over so this costs no second
                ;; ssget.
                work   (car (pfa:xing-shared-split anchor (pfa:xing-list anchor)
                                                   nil inlets))
                recon  (if work (pfa:recon xf work) '())
                n      (length work)
                nd     0)
          (foreach e work
            (if (cdr (assoc (pfa:xr-key e) recon)) (setq nd (1+ nd))))
          (list (cons 'primary     primary)
                (cons 'lines       (length lines))
                (cons 'structures  (length pend))
                (cons 'label-done  (pfa:count-t (car lab)))
                (cons 'label-out   (- (length pend) (pfa:count-t (car lab))))
                (cons 'invert-done (pfa:count-t (car inv)))
                (cons 'invert-out  (- (length pend) (pfa:count-t (car inv))))
                (cons 'crossings   n)
                (cons 'xing-done   nd)
                (cons 'xing-out    (- n nd))
                (cons 'drift       (length (cadr lab)))))))))

;; (pfa:count-t lst) -> how many entries are non-nil
(defun pfa:count-t (lst / n v)
  (setq n 0)
  (foreach v lst (if v (setq n (1+ n))))
  n)

;; (pfa:sets-meet-p a b) -> T when the two name lists share a member
(defun pfa:sets-meet-p (a b / hit n)
  (setq hit nil)
  (foreach n a (if (member n b) (setq hit T)))
  hit)

;; (pfa:merge-into groups grp) -> groups, every group meeting `grp` folded in
;;   Groups are pairwise DISJOINT, which is what makes one pass enough: a group
;;   can only reach the growing union through `grp` itself, never through
;;   another group already absorbed.
;;   grp, NOT set: `set' is a subr (2026-08-06).
(defun pfa:merge-into (groups grp / keep merged g n)
  (setq keep '() merged grp)
  (foreach g groups
    (if (pfa:sets-meet-p g merged)
      (foreach n g (if (not (member n merged)) (setq merged (cons n merged))))
      (setq keep (cons g keep))))
  (cons merged (reverse keep)))

;; (pfa:line-systems rows) -> ((row ...) ...)   the registry rows, grouped
;;   ONE SYSTEM PER GROUP.  Two lines belong to the same hydraulic system when
;;   some structure sits on BOTH -- exactly the multi-line hit pfa:id-for-hits
;;   already turns into "AA-1/BB-2".  Union-find over those hits; a line sharing
;;   nothing is a system of one and is still returned, so every row offered in
;;   is offered back out.
;;
;;   MEMBERSHIP, NOT NODE COINCIDENCE.  pfa:lines-at decides on the corridor,
;;   the same test that put the structure on the sheet.  *pfr-node-tol* is 2.0 ft
;;   and far too loose to settle whether two lines truly meet at a structure.
;;
;;   ONE UTILITY TYPE PER SYSTEM: rows only merge with rows of the same type, so
;;   a structure shared by a storm and a sanitary line joins neither.  It appears
;;   in both systems and exports twice -- correct, they are two hydraulic models
;;   that happen to share a casting.
;;
;;   Pure read, palette-safe: pfa:build-lines files nothing, and pfa:lines-at
;;   falls back to a live corridor test when the roster holds no record.
(defun pfa:line-systems (rows / pairs seen r cl ty lines inlets names tymap
                                types groups pt hits h set out g members)
  ;; ---- 1. ONE line table over every candidate ------------------------------
  (setq pairs '() seen '() names '() tymap '() types '())
  (foreach r rows
    (if (setq cl (pfa:entry-cl r))
      (progn
        (setq pairs (cons (cons cl (cadr r)) pairs)
              names (cons (cadr r) names)
              tymap (cons (cons (cadr r) (car r)) tymap)
              ty    (pf:type-of cl))
        (if (not (member (car r) types)) (setq types (cons (car r) types)))
        (if (not (member ty seen))
          (setq seen  (cons ty seen)
                pairs (append (reverse (pfa:registry-pairs cl)) pairs))))))
  (setq lines (pfa:build-lines (pf:dedupe-pairs (reverse pairs))))
  ;; ---- 2. every structure that sits on two candidates joins them -----------
  (setq inlets (pfa:gather-inlets) groups '())
  (foreach h inlets
    (setq pt   (cdr (assoc 10 (entget h)))
          hits (pfa:lines-at h pt lines))
    (foreach ty types
      (setq set '())
      (foreach g hits
        (if (and (member (car g) names)
                 (= ty (cdr (assoc (car g) tymap)))
                 (not (member (car g) set)))
          (setq set (cons (car g) set))))
      (if (cdr set) (setq groups (pfa:merge-into groups set)))))
  ;; ---- 3. anything that joined nothing is a system of one ------------------
  (foreach r (reverse names)
    (setq g nil)
    (foreach set groups (if (member r set) (setq g T)))
    (if (null g) (setq groups (cons (list r) groups))))
  ;; ---- 4. back to rows, in the order they were offered ---------------------
  (setq out '())
  (foreach set groups
    (setq members '())
    (foreach r rows
      (if (member (cadr r) set) (setq members (cons r members))))
    (if members (setq out (cons (reverse members) out))))
  (reverse out))

;; (pfa:target-items anchor pass) -> (T . ((item station labeled-p) ...)) | nil
;;   pass = "LABEL" | "INVERT" | "XING"
;;
;;   THE ITEM-LEVEL TWIN of pfa:target-counts, for the palette's lvwCommand
;;   (pfpalette SECTION 5c).  Counts answer "how much is on this line"; this
;;   answers "which things, and where" -- the same question the modal run
;;   dialog's list answers (pflabel:rd-fill), minus the dialog.
;;
;;   ONE SHAPE FOR ALL THREE PASSES, because the control showing it has one
;;   set of columns: AddColumns is additive and runs once at OnInitialize, so
;;   it cannot be re-shaped per radio click.  A structure's item is its DRAWN
;;   NAME -- the combined ID pflabel puts on the sheet (pfa:id-for-hits), not
;;   the block name, which names the drafting symbol and not the structure.  A
;;   crossing's item stays the line that crosses, which is already the pipe's
;;   own ID.  Both have a station on the target and a labeled-yet flag, and that
;;   is the whole of what the list renders.  Elevations (pfa:xr-telev / -selev) are deliberately not here --
;;   there is no column for them at the 420px form width.
;;
;;   (T . rows) AND NOT rows.  nil and '() are the same object in AutoLISP, so
;;   a bare list cannot distinguish "no .cl bound / grid unreadable" from "read
;;   fine, nothing on this line" -- and those need different words on screen.
;;   Same reasoning, same idiom as pfa:memb-get.
;;
;;   Pure reads throughout -- legal from a modeless handler.  Structures and
;;   Inverts share pfa:pend-for's memo with target-counts, so the second call
;;   in one click is a memo hit, not a second inlets x lines walk.
;;
;;   CROSSINGS ARE WHAT IS ON RECORD, not what exists.  pfxl:discover is a
;;   writer, so nothing reachable from a palette read can find an undiscovered
;;   crossing; a line that has never had PFXLABEL run answers with an empty
;;   list.  The caller has to say "on record" and not "found" -- detailsList
;;   already does (pfpalette:492).
(defun pfa:target-items (anchor pass / lt primary lines inlets pend idx xf st
                                       res out i e)
  (setq xf (pfa:anchor->xform anchor))
  (cond
    ((null xf) nil)
    ((= pass "XING")
     ;; LIVE, not ledger-only: pfa:xing-find merges what is on record with what
     ;; pfa:xing-scan finds on the ground, so a line that has never had PFXLABEL
     ;; run still lists its crossings -- marked 'NEW.
     (if (setq res (pfa:xing-find anchor))
       (progn
         (setq out '())
         (foreach e (cdr res)
           (setq out (cons (list (pfa:xr-sbase (car e))
                                 (pfa:xr-tsta  (car e))
                                 (cadr e))
                           out)))
         (cons T (reverse out)))))
    ((null (setq lt (pfa:line-table anchor))) nil)
    (T
     (setq primary (car lt)
           lines   (cadr lt))
     (if (not (pfa:line-loaded-p primary lines))
       nil
       (progn
         (setq inlets (pfa:gather-inlets)
               pend   (pfa:pend-for primary lines inlets)
               ;; free -- the same memo entry pend just came out of
               idx    (pfa:index-for primary lines inlets)
               ;; car: status-for returns (status orphans); the orphan half is
               ;; the Drift row's business, and detailsList already renders it.
               st     (car (pfa:status-for anchor pass pend xf))
               out    '()
               i      0)
         ;; pend entries are (sta ename blkname hits); status is a list of
         ;; booleans PARALLEL to pend, not an alist, so the two are walked by
         ;; index.  The boolean becomes a SYMBOL here so every pass reports state
         ;; the same way -- Crossings has four states ('NEW / 'MOVED as well), and
         ;; a renderer switching on `pass` to interpret a bare T was the shape
         ;; that made adding them awkward.
         ;; The item is the DRAWN NAME, off the row's own hits -- no second
         ;; membership walk, so this stays a cheap read on every radio click.
         (foreach e pend
           (setq out (cons (list (pfa:id-for-hits (nth 3 e) idx) (car e)
                                 (if (nth i st) 'LABELED 'OUTSTANDING))
                           out)
                 i   (1+ i)))
         (cons T (reverse out)))))))


;;; ==========================================================================
;;; SECTION 5  --  Crossing records + reconciliation  (unchanged from v3)
;;; ==========================================================================

;; (pfa:xing-list anchor) -> list of working entries, sorted by target sta
(defun pfa:xing-list (anchor / dict meta tfile tbase out k d xy)
  (setq dict (pfa:ledger-dict anchor nil))
  (if dict
    (progn
      (setq meta  (pfa:xrec-data dict "META")
            tfile (if (assoc 1 meta) (cdr (assoc 1 meta)) "")
            tbase (if (= tfile "") "" (vl-filename-base tfile))
            out   '())
      (foreach k (pfa:dict-keys dict)
        (if (= (substr k 1 2) "X_")
          (progn
            (setq d  (pfa:xrec-data dict k)
                  xy (cdr (assoc 10 d)))
            (setq out (cons (list k tfile tbase
                                  (cdr (assoc 1 d)) (cdr (assoc 2 d))
                                  (if xy (list (car xy) (cadr xy)))
                                  (cdr (assoc 40 d)) (cdr (assoc 41 d))
                                  (cdr (assoc 42 d)) (cdr (assoc 43 d)))
                            out)))))
      (vl-sort out '(lambda (a b) (< (pfa:xr-tsta a) (pfa:xr-tsta b)))))))

;; (pfa:xing-classify dict e) -> (status existing-key | nil)
;;   status = 'NEW | 'UPDATED | 'MOVED
;;   The whole of pfa:xing-merge's decision and none of its writing, so the
;;   READ-ONLY scan can classify a found crossing without filing one:
;;   exact content key present -> UPDATED; else a same-source crossing within
;;   *pfa-key-tol* of this station -> MOVED (the station drifted, so the content
;;   key drifted with it); else NEW.
;;   PURE READ, and it takes the DICT rather than the anchor so the CALLER
;;   decides whether that dict was opened with create T.  A nil dict is legal
;;   and answers 'NEW -- no ledger yet means nothing is on record.
;;   Re-deriving this in the preview would be the real defect: two copies drift,
;;   and then the palette promises one thing while PFXLABEL does another.
(defun pfa:xing-classify (dict e / key d kdrift k)
  (setq key (pfa:xing-key (pfa:xr-sbase e) (pfa:xr-tsta e)))
  (cond
    ((null dict) (list 'NEW nil))
    ((dictsearch dict key) (list 'UPDATED key))
    (T
     (setq kdrift nil)
     (foreach k (pfa:dict-keys dict)
       (if (and (null kdrift) (= (substr k 1 2) "X_"))
         (progn
           (setq d (pfa:xrec-data dict k))
           (if (and (= (strcase (cdr (assoc 2 d)))
                       (strcase (pfa:xr-sbase e)))
                    (<= (abs (- (cdr (assoc 40 d)) (pfa:xr-tsta e)))
                        *pfa-key-tol*))
             (setq kdrift k)))))
     (if kdrift (list 'MOVED kdrift) (list 'NEW nil)))))

;; (pfa:xing-merge anchor e) -> 'NEW | 'UPDATED | 'MOVED
;;   Elevations already on record are PRESERVED; key drift renames.
;;   The DECISION is pfa:xing-classify's; this is the filing half only.
(defun pfa:xing-merge (anchor e / dict key cls status kdrift d old-t old-s data)
  (setq dict   (pfa:ledger-dict anchor T)
        key    (pfa:xing-key (pfa:xr-sbase e) (pfa:xr-tsta e))
        cls    (pfa:xing-classify dict e)
        status (car cls)
        kdrift (cadr cls)
        old-t  nil
        old-s  nil)
  ;; UPDATED and MOVED both carry an existing record whose ELEVATIONS have to
  ;; survive the rewrite (they are surveyed, not derived).  Only MOVED also
  ;; drops the old key: its station changed, so its content key changed with it.
  (if kdrift
    (setq d     (pfa:xrec-data dict kdrift)
          old-t (cdr (assoc 42 d))
          old-s (cdr (assoc 43 d))))
  (if (eq status 'MOVED) (pfa:xrec-del dict kdrift))
  (setq data (append
               (list (cons 1  (pfa:xr-sfile e))
                     (cons 2  (strcase (pfa:xr-sbase e)))
                     (cons 10 (list (car (pfa:xr-xy e))
                                    (cadr (pfa:xr-xy e)) 0.0))
                     (cons 40 (pfa:xr-tsta e))
                     (cons 41 (pfa:xr-ssta e)))
               (if old-t (list (cons 42 old-t)) '())
               (if old-s (list (cons 43 old-s)) '())))
  (pfa:xrec-put dict key data)
  status)

;; (pfa:xing-put-elevs anchor key telev selev) -> T | nil
;;   nil for either elevation PRESERVES the stored value.
(defun pfa:xing-put-elevs (anchor key telev selev / dict d data)
  (if (and key
           (setq dict (pfa:ledger-dict anchor nil))
           (setq d (pfa:xrec-data dict key)))
    (progn
      (if (null telev) (setq telev (cdr (assoc 42 d))))
      (if (null selev) (setq selev (cdr (assoc 43 d))))
      (setq data (vl-remove-if '(lambda (p) (member (car p) '(42 43))) d))
      (if telev (setq data (append data (list (cons 42 telev)))))
      (if selev (setq data (append data (list (cons 43 selev)))))
      (pfa:xrec-put dict key data)
      T)))

;; (pfa:xing-line-tbl tcl tname tgeom scl sname sgeom) -> 2-row cl-table | nil
;;   The pair being intersected, in pf:lines-at-point's table shape, so a
;;   structure can be asked which of these TWO lines it sits on.
;;   NOT pfa:build-lines: that one publishes *pfa-roster* and hunts drawn twins,
;;   both wrong here -- the scan runs from a palette click and must not disturb
;;   the roster a run is holding, and the sampled verts are already in hand.
;;   Sampled shape, so the corridor is *pf-corridor-sampled* (chords cut corners
;;   between station samples).  A missing range yields nil rather than a row
;;   with nil bounds, which pf:lines-at-point would compare arithmetically.
(defun pfa:xing-line-tbl (tcl tname tgeom scl sname sgeom / trng srng)
  (setq trng (car tgeom) srng (car sgeom))
  (if (and trng srng (car trng) (car srng))
    (list (list tcl tname (car trng) (cadr trng) (cdr tgeom)
                *pf-corridor-sampled*
                (if (cdr tgeom) (pf:verts-bbox (cdr tgeom))))
          (list scl sname (car srng) (cadr srng) (cdr sgeom)
                *pf-corridor-sampled*
                (if (cdr sgeom) (pf:verts-bbox (cdr sgeom)))))))

;; (pfa:struct-shared-p xy tbl inlets) -> T | nil    PURE READ
;;   T when a structure block sits at `xy` and lies on BOTH lines of `tbl`.
;;   THE TEST pf:shared-structure-p CANNOT MAKE.  That one reasons about where
;;   the two .cl files STOP, which answers only the tidy case: a branch drawn a
;;   few feet past the main intersects it mid-run, and two mains meeting through
;;   a junction box terminate nowhere near the joint at all.  Widening
;;   *pfx-terminus-tol* cannot reach either -- it is measuring the wrong thing.
;;   A shared structure is a physical object, so ask whether one is there.
;;   BOTH LINES, and that is the whole safety margin: a water line crossing
;;   UNDER a storm manhole is a genuine crossing, and that manhole is on the
;;   storm .cl only.  A junction manhole is on both.  "On" is pf:lines-at-point's
;;   *pf-offset-tol* (0.15 ft) -- the same seam pflabel uses to decide which line
;;   a structure belongs to, so the two passes cannot disagree about a joint.
;;   `tbl` holds exactly the two lines, so a second hit IS both; hence (cdr ...)
;;   rather than counting.
(defun pfa:struct-shared-p (xy tbl inlets / hit e p xy2)
  (setq hit nil)
  (if (and xy tbl inlets)
    (progn
      (setq xy2 (list (car xy) (cadr xy)))
      (foreach e inlets
        (if (and (null hit)
                 (setq p (cdr (assoc 10 (entget e))))
                 (<= (distance xy2 (list (car p) (cadr p))) *pfx-struct-tol*)
                 (cdr (pf:lines-at-point (list (car p) (cadr p)) tbl)))
          (setq hit T)))))
  hit)

;; (pfa:xing-shared-split anchor entries write-p) -> (keep ((entry . why) ...))
;;   Partitions xr-shaped LEDGER entries into the ones that are still crossings
;;   and the ones the not-a-crossing tests now reject, each with its reason --
;;   the caller reports it, and only this knows which test fired.
;;   THREE TESTS now, not two: the two shared-structure ones, plus the source
;;   .pro's station range (pf:pro-outside-p).  A pipe does not exist past the
;;   ends of its own profile, so an alignment that crosses out there is not a
;;   crossing; rows filed before that gate existed are retracted here.
;;   The name still says "shared" -- it is the ledger re-test, whatever the
;;   grounds for rejection.
;;   THE ONE PLACE A FILED RECORD IS RE-TESTED, and it exists because the read
;;   and the write have to give the same answer.  The scan's filters gate only
;;   what gets FILED; pfa:xing-find hands ledger rows straight to the palette,
;;   so before this split a tie-in on record showed as a crossing until PFXLABEL
;;   was run -- the exact preview/command disagreement the scan split was made
;;   to end.  Now the reader (pfa:xing-find) and the writer
;;   (pfa:xing-sweep-shared) partition through this and cannot drift.
;;   NO INTERSECTION IS RECOMPUTED.  The record already carries both stations
;;   and the intersection point; only the geometry is missing, so this is one
;;   pf:cl-geom per DISTINCT source, not per record.
;;   BOTH TESTS, in the scan's order -- cheap terminus band first, then
;;   pfa:struct-shared-p.  Running only the first leaves exactly the records
;;   that motivated the second: overshot branches and through-joints, which no
;;   terminus tolerance reaches.
;;   WRITE-P THREADS TO pf:cl-geom AND DECIDES NOTHING ELSE, same seam as the
;;   scan.  The palette passes nil; the sweep, inside its undo group, passes T.
;;   Nothing here writes the ledger either way -- rejecting is the caller's.
;;   INLETS IS AN IN-PARAMETER so a caller already holding the gather can spend
;;   one ssget instead of two -- pfa:target-counts does, and it is called on
;;   every tree click.  nil means "gather your own".  A drawing with no
;;   structures at all therefore re-gathers on each call and gets nil again:
;;   one wasted ssget, right answer, and not worth a third state to avoid.
;;   EMPTY ENTRIES COSTS NOTHING: the gather is skipped entirely, so a target
;;   with no crossings on record pays nothing for this on a click.
;;   UNREADABLE GEOMETRY REJECTS NOTHING -- pf:sta-at-end-p answers nil on a nil
;;   range and pfa:xing-line-tbl refuses to build a row without one, so a stale
;;   .cl path leaves survivors rather than silently eating real crossings.
(defun pfa:xing-shared-split (anchor entries write-p inlets / tcl tbase tgeom
                                     cache keep reject e sfile cell sgeom sinv)
  (setq tcl    (cdr (assoc 1 (pfa:meta-get anchor)))
        keep   '()
        reject '())
  (if (and entries tcl (/= tcl ""))
    (progn
      (setq tgeom  (pf:cl-geom tcl write-p)
            tbase  (vl-filename-base tcl)
            inlets (if inlets inlets (pfa:gather-inlets))
            cache  '())
      (foreach e entries
        (setq sfile (pfa:xr-sfile e)
              sgeom nil
              sinv  nil)
        ;; ONE cell per distinct source carries BOTH the geometry and the _INV
        ;; path: pfa:src-files runs a full-DB pfa:find-anchor scan, so resolving
        ;; it per record is the cost this cache exists to avoid.
        (if (and sfile (/= sfile ""))
          (if (setq cell (assoc sfile cache))
            (setq sgeom (cadr cell)
                  sinv  (caddr cell))
            (setq sgeom (pf:cl-geom sfile write-p)
                  sinv  (car (pfa:src-files (pf:type-of sfile)
                                            (pf:name-of sfile)))
                  cache (cons (list sfile sgeom sinv) cache))))
        ;; cheapest first: terminus arithmetic, then the cached .pro read, then
        ;; the structure probe
        (cond
          ((pf:shared-structure-p (car tgeom) (pfa:xr-tsta e)
                                  (car sgeom) (pfa:xr-ssta e))
           (setq reject (cons (cons e "shared structure, not a crossing")
                              reject)))
          ((pf:pro-outside-p sinv (pfa:xr-ssta e))
           (setq reject (cons (cons e "no pipe on the source at that station")
                              reject)))
          ((pfa:struct-shared-p
             (pfa:xr-xy e)
             (pfa:xing-line-tbl tcl tbase tgeom
                                sfile (pfa:xr-sbase e) sgeom)
             inlets)
           (setq reject (cons (cons e "shared structure, not a crossing")
                              reject)))
          (T (setq keep (cons e keep))))))
    (setq keep entries))
  (list (reverse keep) (reverse reject)))

;; (pfa:xing-sweep-shared anchor) -> ((sbase tsta ssta why) ...)  REMOVED records
;;   Makes the split above PERMANENT.  A WRITER -- never call it from a modeless
;;   handler.
;;   pfa:xing-find drops a rejected row from what it shows, but the record is
;;   still on the ledger and a rescan cannot retract it either: the checksum
;;   short-circuit skips any pair whose two .cl are unchanged, so the pair is
;;   never re-cut.  Only this deletes.
;;   Returns the same (sbase tsta ssta why) shape as the scan's skips so the
;;   caller can report both through one path.
(defun pfa:xing-sweep-shared (anchor / dict)
  (setq dict (pfa:ledger-dict anchor nil))
  (if (null dict)
    '()
    (mapcar '(lambda (r / e)
               ;; pfa:xing-list built its entries before any delete, so removing
               ;; inside this walk cannot disturb it
               (setq e (car r))
               (pfa:xrec-del dict (pfa:xr-key e))
               (list (pfa:xr-sbase e) (pfa:xr-tsta e) (pfa:xr-ssta e) (cdr r)))
            (cadr (pfa:xing-shared-split anchor (pfa:xing-list anchor)
                                         T nil)))))

;;; ---- Crossing DISCOVERY: the shared scan ---------------------------------
;;; THE FIND AND THE FILE ARE DIFFERENT JOBS.  While finding lived inside
;;; pfxl:discover, which found AND merged, the palette could only show what a
;;; previous PFXLABEL had written -- "0 crossings" on a line that has plenty.
;;; Nothing about FINDING a crossing needs a write: it is .cl geometry through
;;; pf:poly-x, and pf:cl-geom's `write-p` is exactly this read/write seam.  The
;;; writers were only ever pfa:xing-merge, pfa:scope-put, and pf:cl-geom's cache.
;;;
;;; IT LIVES IN PFANCHOR, not pfxlabel, for two reasons.  Load order: pfanchor
;;; is 4 and pfxlabel 9, so pfa:target-items could never call upward into pfxl:.
;;; Ownership: pfanchor already holds the whole crossing record layer --
;;; xing-key, xing-classify, xing-merge, xing-list, SCOPE.  pfxl:discover is the
;;; filing half and nothing else.
;;;
;;; ONE SCAN, TWO CALLERS, so a preview cannot disagree with what the command
;;; then does.  That is the point of the split, not a side effect.

(if (not (boundp '*pfa-xscan-memo*)) (setq *pfa-xscan-memo* '()))

;; (pfa:xing-scan anchor write-p) -> (found newscope skips) | nil
;;   found    = ((entry status existing-key) ...)   entry is xr-shaped, key nil
;;              status is pfa:xing-classify's: 'NEW | 'UPDATED | 'MOVED
;;   newscope = "schema|sbase|tgt-cksum|src-cksum|src-pro-cksum" strings, for
;;              pfa:scope-put; pfa:scope-read strips the schema back off
;;   skips    = ((sbase tsta ssta why) ...) -- intersections REJECTED as not
;;              crossings, reported not discarded; why is the operator-facing
;;              phrase, and only this knows which test fired
;;   nil = no xform, no .cl on record, or the .cl cannot be checksummed.
;;
;;   NON-CROSSINGS ARE FILTERED HERE, not in the caller: the split exists so
;;   a preview cannot disagree with the command, and filtering in pfxl:discover
;;   alone would have the palette showing tie-ins that Crossings then refuses.
;;   THREE TESTS, in cost order.
;;   pf:shared-structure-p reads where the two .cl files STOP, which only
;;   answers the tidy tie-in.  pf:pro-outside-p asks whether the SOURCE's _INV
;;   .pro even covers that station -- two centerlines cross wherever they cross,
;;   but a pipe exists only over its own profile, and profile_z will happily
;;   extend the end tangent to invent an invert out there.  pfa:struct-shared-p
;;   asks whether a structure block sits at the hit and lies on BOTH lines,
;;   which is the physical fact and needs no terminus at all; it runs last
;;   because it is the only one that costs an ssget.
;;   THE TARGET'S OWN RANGE IS DELIBERATELY NOT TESTED (2026-08-06): a label
;;   past the last structure on the target grid harms nothing today.  Adding it
;;   is one more pf:pro-outside-p call here, against the anchor's own _INV.
;;
;;   WRITE-P THREADS STRAIGHT THROUGH to pf:cl-geom and decides nothing else.
;;   nil is a pure read, legal from a modeless handler; T is discovery's scan and
;;   files the GEOM cache as it goes.  NOTHING here writes the ledger either way.
;;
;;   THE CHECKSUM SHORT-CIRCUIT IS WHAT MAKES THE PREVIEW AFFORDABLE.  A pair
;;   whose two .cl checksums match SCOPE was already intersected by the last
;;   discovery, and pf:poly-x is O(n x m) segment tests per pair.  Steady state
;;   therefore costs almost nothing; only new or changed lines are re-cut.
;;
;;   THE MEMO COVERS THE OTHER CASE: a target never discovered has no SCOPE, so
;;   nothing short-circuits and every pair is cut, on every tree and radio click.
;;   The memo keys on the anchor plus every checksum plus SCOPE, which together
;;   fully determine the answer.  Shares pfa:memo-get / pfa:memo-put.
;;
;;   READ-ONLY SCANS ONLY.  Discovery (write-p T) bypasses the memo: a hit would
;;   skip the pf:cl-geom filing that passing T is FOR, and a command that quietly
;;   declines to do its work is worse than a slow one.
(defun pfa:xing-scan (anchor write-p / xf ty nm tcl tck tgeom trng tverts
                                       reg dict e
                                       sources r scl sbase sck sinv newscope s
                                       lastsc mkey hit found skips triple
                                       sgeom srng sverts xy
                                       tsta ssta xy2 tsta2 ssta2 cls
                                       why inlets igot)
  (setq xf  (pfa:anchor->xform anchor)
        tcl (if xf (cdr (assoc 1 (pfa:meta-get anchor)))))
  (cond
    ((or (null xf) (null tcl) (= tcl "")) nil)
    ((null (setq tck (pf:checksum-file tcl))) nil)
    (T
     (setq ty      (strcase (pf:xf-get 'type xf))
           nm      (strcase (pf:xf-get 'name xf))
           reg     (pfa:registry)
           sources '())
     ;; PRE-PASS: every source line, its checksum, and its bound _INV .pro
     ;; (path + checksum).  Cheap beside an intersection, and it is what both
     ;; SCOPE and the memo key are built from -- so it has to happen before
     ;; either can be consulted.  The .pro is resolved HERE, once per line,
     ;; rather than at the hit: pfa:src-files runs a full-DB anchor scan.
     (foreach r reg
       (if (and (not (and (= (strcase (car r)) ty) (= (strcase (cadr r)) nm)))
                (setq scl (pfa:entry-cl r)))
         (setq sinv    (car (pfa:src-files (car r) (cadr r)))
               sources (cons (list scl (vl-filename-base scl)
                                   (pf:checksum-file scl)
                                   sinv
                                   (if sinv (pf:checksum-file sinv)))
                             sources))))
     (setq sources  (reverse sources)
           newscope '())
     (foreach s sources
       (setq newscope (cons (strcat *pfx-scan-schema* "|" (cadr s) "|" tck "|"
                                    (if (caddr s) (caddr s) "") "|"
                                    (if (nth 4 s) (nth 4 s) ""))
                            newscope)))
     (setq newscope (reverse newscope)
           lastsc   (pfa:scope-read anchor)   ; NOT `last' -- shadows the subr
           ;; 'X3 is a VALUE-SHAPE tag, not decoration: *pfa-xscan-memo*
           ;; survives a hot .lsp reload by design, so an old-shape entry would
           ;; be read as current -- X2's skips are triples and X3's carry a
           ;; reason.  A new tag never matches old entries, so they age out
           ;; untouched.
           mkey     (list 'X3 (cdr (assoc 5 (entget anchor))) newscope lastsc)
           hit      (if write-p nil (pfa:memo-get mkey *pfa-xscan-memo*)))
     (cond
       (hit (list (car (cdr hit)) newscope (cadr (cdr hit))))
       (T
        ;; pf:cl-geom returns (range . verts) and the scan wants BOTH halves:
        ;; the range is what tells a shared structure from a crossing, and it is
        ;; already in hand.
        (setq tgeom  (pf:cl-geom tcl write-p)
              trng   (car tgeom)
              tverts (cdr tgeom)
              ;; create nil ALWAYS: classification only reads, and a preview
              ;; must not bring a ledger dictionary into being.  Discovery's
              ;; own pfa:xing-merge opens it with T when it files.
              dict   (pfa:ledger-dict anchor nil)
              found  '()
              skips  '())
        (if tverts
          (foreach s sources
            (setq scl    (car s)
                  sbase  (cadr s)
                  sck    (caddr s)
                  triple (car (vl-member-if
                                '(lambda (x) (= (car x) sbase)) lastsc)))
            ;; short-circuit: both .cl AND the source _INV .pro unchanged since
            ;; the last scan.  The .pro is in the test because its station range
            ;; now decides whether a hit is a crossing at all -- on .cl alone,
            ;; extending a pipe run would never bring its crossing back.
            (if (not (and triple (= (cadr triple) tck) (= (caddr triple) sck)
                          (= (cadddr triple) (if (nth 4 s) (nth 4 s) ""))))
              (if (setq sgeom  (pf:cl-geom scl write-p)
                        srng   (car sgeom)
                        sverts (cdr sgeom))
                ;; EVERY intersection with this source, not the first.  Two
                ;; lines crossing twice is ordinary, and the old single hit was
                ;; direction-dependent -- the outer walk is the target's, so
                ;; each line's list showed a different one of the two and both
                ;; looked incomplete.
                (foreach xy (pf:poly-x-all tverts sverts)
                  (progn
                    (setq tsta (pf:sta-at tcl xy)
                          ssta (pf:sta-at scl xy))
                    (if (and tsta ssta
                             (setq xy2 (pf:refine-x tcl tsta scl ssta)))
                      (progn
                        (setq tsta2 (pf:sta-at tcl xy2)
                              ssta2 (pf:sta-at scl xy2))
                        (if (and tsta2 ssta2)
                          (setq xy xy2 tsta tsta2 ssta ssta2))))
                    ;; AFTER refinement, deliberately: the terminus test is a
                    ;; station comparison and the structure test measures from
                    ;; xy, so both want the best the scan has rather than the
                    ;; coarse sampled one.
                    (if (and tsta ssta)
                      (progn
                        ;; TERMINUS FIRST -- it is arithmetic on two numbers
                        ;; already in hand, and every hit it takes is a
                        ;; structure lookup not done.
                        (setq why (if (pf:shared-structure-p trng tsta srng ssta)
                                    "shared structure, not a crossing"))
                        ;; THEN the source's own profile.  A pipe does not exist
                        ;; past the ends of its .pro, so two centerlines that
                        ;; cross out there cross no pipe.  Ahead of the
                        ;; structure probe: a checksum-cached file read beats an
                        ;; ssget and a distance walk.
                        (if (and (null why) (pf:pro-outside-p (nth 3 s) ssta))
                          (setq why "no pipe on the source at that station"))
                        (if (null why)
                          (progn
                            ;; ONE ssget for the whole scan, and only once a
                            ;; pair has actually intersected -- the common case
                            ;; (every pair short-circuited on checksums) never
                            ;; reaches here and never pays for it.
                            (if (null igot)
                              (setq inlets (pfa:gather-inlets) igot T))
                            (if (pfa:struct-shared-p
                                  xy
                                  (pfa:xing-line-tbl
                                    tcl (vl-filename-base tcl) tgeom
                                    scl sbase sgeom)
                                  inlets)
                              (setq why "shared structure, not a crossing"))))
                      (if why
                        (setq skips (cons (list sbase tsta ssta why) skips))
                        (progn
                          (setq e   (list nil tcl (vl-filename-base tcl)
                                          scl sbase (list (car xy) (cadr xy))
                                          tsta ssta nil nil)
                                cls (pfa:xing-classify dict e))
                          (setq found (cons (list e (car cls) (cadr cls))
                                            found))))))))))))
        (setq found (reverse found)
              skips (reverse skips))
        (if (not write-p)
          (setq *pfa-xscan-memo*
                  (pfa:memo-put mkey (list found skips) *pfa-xscan-memo*)))
        (list found newscope skips))))))

;; (pfa:xing-find anchor) -> (T . ((entry state) ...)) | nil    PURE READ
;;   state = 'LABELED | 'OUTSTANDING | 'NEW | 'MOVED
;;   WHAT IS ON THIS LINE, whether or not PFXLABEL has ever run: the ledger
;;   supplies what is on record, pfa:xing-scan what is on the ground, and the two
;;   are merged so the palette can show a crossing BEFORE it is discovered.
;;   'NEW    -- found by the live scan, not in the ledger.  Running Crossings
;;              is what puts it there.
;;   'MOVED  -- on record, but the scan puts it at a different station.  The
;;              stale ledger row is dropped rather than shown twice;
;;              pfa:xing-merge renames it on the next run.
;;   'UPDATED is NOT a separate row -- same crossing, same key, and the ledger
;;              row is the better one because it carries surveyed elevations.
;;   LEDGER ROWS GO THROUGH pfa:xing-shared-split FIRST.  "On record" is a claim
;;   made by whatever run filed it, under whatever filters existed then; it is
;;   not the same claim as "is a crossing".  Re-testing here is what stops a
;;   tie-in filed by an older run from showing until PFXLABEL is next run.
;;   (T . rows), not bare rows: nil and '() are the same object, so an empty list
;;   must stay distinguishable from an unreadable target.  Same idiom as
;;   pfa:memb-get and pfa:target-items.
(defun pfa:xing-find (anchor / xf merged scan found drop out f e recon)
  (setq xf (pfa:anchor->xform anchor))
  (if (null xf)
    nil
    (progn
      ;; LEDGER ROWS ARE RE-TESTED, not trusted.  The scan's filters gate only
      ;; what gets filed, and these rows were filed by some earlier run -- for a
      ;; ledger written before a filter existed, or before its tolerance moved,
      ;; "on record" is not the same claim as "is a crossing".  Same split the
      ;; sweep deletes by, so what the palette shows is what PFXLABEL would keep.
      ;; write-p nil: a click must not file a GEOM cache entry.
      (setq merged (car (pfa:xing-shared-split anchor (pfa:xing-list anchor)
                                               nil nil))
            scan   (pfa:xing-scan anchor nil)
            found  (if scan (car scan) '())
            recon  (if merged (pfa:recon xf merged) '())
            drop   '())
      (foreach f found
        (if (and (eq (cadr f) 'MOVED) (caddr f))
          (setq drop (cons (caddr f) drop))))
      (setq out '())
      (foreach e merged
        (if (not (member (pfa:xr-key e) drop))
          (setq out (cons (list e (if (cdr (assoc (pfa:xr-key e) recon))
                                    'LABELED
                                    'OUTSTANDING))
                          out))))
      (foreach f found
        (if (member (cadr f) '(NEW MOVED))
          (setq out (cons (list (car f) (cadr f)) out))))
      (cons T (vl-sort out '(lambda (a b) (< (pfa:xr-tsta (car a))
                                             (pfa:xr-tsta (car b)))))))))

;;; ---- Reconciliation (read-only; TWO scans per call) ----------------------
;;; STEPPED TOPS: a crossing station line is drawn to the grid top AT ITS
;;; STATION (the top-of-grid probe), so the "labeled" signature is
;;; per-station too: exact X match AND top vertex at pf:top-at for that X.
;;; The SAME lookup feeds the draw and this check -- if the grid is
;;; unchanged the two values are bit-identical; if the grid was re-drawn,
;;; the old label honestly reads outstanding.

;; (pfa:station-line-tops) -> list of (x . ytop): each crossing station
;;   line's TOP vertex.  One scan.
;;   Scans PF-ANNO, so STRUCTURE station lines (pflabel) come back too.  That is
;;   harmless and deliberate: pfa:top-labeled-p keeps only tops that match the
;;   grid-top probe within *pfa-recon-eps* (1e-4, a float round-trip tolerance),
;;   and a structure line's top vertex sits a text height above the grid top.
(defun pfa:station-line-tops ( / ss i ed p bx by out)
  (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *pf-anno-layer*)
                             '(410 . "Model")))     ; model space only
        out '()
        i 0)
  (if ss
    (while (< i (sslength ss))
      (setq ed (entget (ssname ss i)) bx nil by nil)
      (foreach p ed
        (if (= (car p) 10)
          (if (or (null by) (> (cadr (cdr p)) by))
            (setq bx (car (cdr p)) by (cadr (cdr p))))))
      (if bx (setq out (cons (cons bx by) out)))
      (setq i (1+ i))))
  out)

;; (pfa:top-labeled-p x etop tops) -> T | nil
;;   etop = expected top at x (probe result); nil etop can never match.
(defun pfa:top-labeled-p (x etop tops / found v)
  (setq found nil)
  (if etop
    (foreach v tops
      (if (and (<= (abs (- (car v) x)) *pfa-recon-eps*)
               (<= (abs (- (cdr v) etop)) *pfa-recon-eps*))
        (setq found T))))
  found)

;; (pfa:recon xform work) -> alist (key . labeled?)
(defun pfa:recon (xform work / tops mjr ylo yhi out e x etop)
  (setq tops (pfa:station-line-tops)
        mjr  (pf:top-lines)
        ylo  (pf:xf-basey xform)
        yhi  (+ (pf:grid-top-y xform)
                (* *pfg-top-margin* (pf:xf-sf xform)))
        out  '())
  (foreach e work
    (setq x    (pf:station->profile-x (pfa:xr-tsta e) xform)
          etop (pf:top-at x ylo yhi mjr))
    (setq out (cons (cons (pfa:xr-key e) (pfa:top-labeled-p x etop tops))
                    out)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 6  --  Anchor picking  (shared command-line helpers)
;;; ==========================================================================

;; (pfa:anchor-title anchor) -> "STORM 'LINEA'"
(defun pfa:anchor-title (anchor / at)
  (setq at (pfa:read-attribs anchor))
  (strcat (pfa:att "UTIL" at) " '" (pfa:att "LINE" at) "'"))

;; (pfa:pick-anchor msg) -> anchor ename | nil   (nil = Enter / cancel)
;;   entsel loop that only accepts an insert named in *pfa-block-names*.
(defun pfa:pick-anchor (msg / sel e ed done res)
  (setq done nil res nil)
  (while (not done)
    (setq sel (entsel msg))
    (cond
      ((null sel) (setq done T))                    ; Enter / miss = done
      (T
       (setq e (car sel) ed (entget e))
       (if (and (= (cdr (assoc 0 ed)) "INSERT")
                (member (strcase (cdr (assoc 2 ed)))
                        (pf:split (strcase *pfa-block-names*) ",")))
         (setq res e done T)
         (prompt (strcat "\n  Not a " *pfa-block-name*
                         " -- pick the anchor block, or Enter."))))))
  res)

;; (pfa:choose-anchor) -> anchor ename | nil
;;   List-dialog pick from every anchor in the drawing (for when the anchor
;;   isn't on screen).  pfset:pick-index lives in pfsettings (runtime-only
;;   dependency -- load order is unaffected).
(defun pfa:choose-anchor ( / anchors pick)
  (setq anchors (pfa:all-anchors))
  (cond
    ((null anchors)
     (prompt (strcat "\nNo " *pfa-block-name*
                     " anchors in this drawing -- run PFSETUP."))
     nil)
    ((= (length anchors) 1)
     (prompt (strcat "\nUsing the only registered profile: "
                     (pfa:anchor-title (car anchors))))
     (car anchors))
    (T
     (setq pick (pfset:pick-index "Select the profile:"
                                  (mapcar 'pfa:anchor-title anchors) nil))
     (if pick (nth pick anchors)))))

;;; --------------------------------------------------------------------------
;;; The shared command wrapper  (pf:run-command)
;;; --------------------------------------------------------------------------
;;; ONE copy of the prologue/epilogue every PF command used to carry: *error*
;;; save/install, echo off/on, the undo-group flag pattern, and the error-path
;;; teardown.  Lives here because every command already depends on pfanchor.
;;;
;;; The FLUSH hook is per-command (pflabel:flush-pass, pfi:flush-pass,
;;; pfxl:flush-pass): on an Esc mid-run it writes the pass ledger for whatever
;;; was drawn before the interrupt, INSIDE the still-open undo group
;;; (entmakex/dictadd are *error*-legal).  Partial output is therefore ON the
;;; ledger -- pfa:erase-pass, PFREMOVE and recon account for it -- and one U
;;; still peels the whole run.

;; Per-command undo-group flags.  Each command file also boundp-inits its
;; own; these guards make the wrapper safe to call in any load order.
(if (not (boundp '*pfs-undo-open*))      (setq *pfs-undo-open* nil))
(if (not (boundp '*pflabel-undo-open*))  (setq *pflabel-undo-open* nil))
(if (not (boundp '*pfxl-undo-open*))     (setq *pfxl-undo-open* nil))
(if (not (boundp '*pfinvert-undo-open*)) (setq *pfinvert-undo-open* nil))

;; Wrapper run state (set by pf:run-command, read by pf:run-error).
(if (not (boundp '*pf-run-name*))       (setq *pf-run-name* nil))
(if (not (boundp '*pf-run-flush*))      (setq *pf-run-flush* nil))
(if (not (boundp '*pf-run-prev-error*)) (setq *pf-run-prev-error* nil))

;; (pf:undo-begin flag-sym) / (pf:undo-end flag-sym) -> nil
;;   The per-command undo-group pattern, one home: open/close the group and
;;   track it in the command's *pfX-undo-open* flag (pass the QUOTED symbol).
(defun pf:undo-begin (flag)
  (command "_.UNDO" "_Begin")
  (set flag T)
  (princ))

(defun pf:undo-end (flag)
  (command "_.UNDO" "_End")
  (set flag nil)
  (princ))

;; (pf:group-open-p) -> T when any pf command's undo group is open.
;;   At most one ever is, but the OWNER may not be the command whose *error*
;;   fired: an Esc inside a NESTED flow (on-the-fly placement from a label
;;   command) lands in the caller's handler while pfs's group is open.
(defun pf:group-open-p ()
  (or *pfs-undo-open* *pflabel-undo-open* *pfxl-undo-open*
      *pfinvert-undo-open* *pfrem-undo-open* *pfadopt-undo-open*))

;; (pf:run-error msg) -> nil   THE *error* handler for every wrapped command.
;;   Error-path order (locked): ledger-flush hook -> close undo group ->
;;   pf:zoom-onerror -> restore *error*.  The flush runs only while a group
;;   is still open (its own flag+ctx guards make it a no-op for a nested
;;   group it does not own) and is catch-wrapped: an error INSIDE an *error*
;;   handler must never propagate.
(defun pf:run-error (msg)
  (if (and msg
           (/= msg "Function cancelled")
           (/= msg "quit / exit abort"))
    (prompt (strcat "\n" (if *pf-run-name* *pf-run-name* "PFTOOLS")
                    " error: " msg)))
  ;; 1. per-command ledger flush, INSIDE the still-open group
  (if (and *pf-run-flush* (pf:group-open-p))
    (vl-catch-all-apply *pf-run-flush* '()))
  ;; 2. close whichever pf group is open; no path may leak a group
  (if (pf:group-open-p) (command-s "_.UNDO" "_End"))
  (setq *pfs-undo-open*      nil
        *pflabel-undo-open*  nil
        *pfxl-undo-open*     nil
        *pfinvert-undo-open* nil
        *pfrem-undo-open*    nil
        *pfadopt-undo-open*  nil)
  (pf:echo-on)                       ; error path always restores CMDECHO
  ;; 2b. and always restores the console VOLUME.  The palette binds *pf-quiet*
  ;; around gather paths inside a wrapped command, so an error thrown mid-gather
  ;; jumps here and skips that caller's reset -- leaving the suite mute for the
  ;; session, silently.  Same class as pf:echo-on: the error path hands back
  ;; whatever console state was borrowed.
  (setq *pf-quiet* nil)
  ;; 3. Esc mid-parade: restore the pre-run view (no-op when the parade is off)
  (pf:zoom-onerror)
  ;; 4. restore the caller's *error*
  (setq *error*        *pf-run-prev-error*
        *pf-run-name*  nil
        *pf-run-flush* nil)
  (princ))

;; (pf:run-command name flush work) -> nil   THE shared prologue/epilogue.
;;   name  = command name for error reports ("PFLABEL")
;;   flush = the command's Esc ledger-flush hook (QUOTED symbol) | nil
;;   work  = the command body (QUOTED symbol, no args) -- gather + engine
;;   The body still opens/closes its own undo group (via pf:undo-begin/end) at
;;   the point its writes start -- gather stays OUTSIDE the group.
;;
;;   API LOADING IS PART OF THE PROLOGUE.  As the first line of each command
;;   BODY it was forgettable, and C:PFPVERB forgot: the palette's anchor verb
;;   calls pfs:place-one directly, so in a session where no other PFTools
;;   command had run, btnAnchor prompted for scales and then died on the first
;;   centerline read with "bad function: CF:ROAD_API".  What EVERY entry point
;;   needs belongs to the ONE wrapper.  scload is idempotent and catch-wrapped,
;;   so repeats cost nothing, and it sits AFTER echo-off to suppress the chatter.
;;
;;   THE CONSOLE STARTS AUDIBLE.  *pf-quiet* is bound by palette read paths and
;;   every one resets it -- but a reset can be skipped by a throw, and the
;;   failure is session-long and silent.  Clearing it here and in pf:run-error
;;   means no command can INHERIT a mute, which makes the flag safe to bind from
;;   anywhere without every caller having to be perfect.
(defun pf:run-command (name flush work)
  (setq *pf-run-prev-error* *error*
        *pf-run-name*       name
        *pf-run-flush*      flush
        *pf-quiet*          nil
        *error*             pf:run-error)
  (pf:echo-off)
  (pf:load-apis)
  (apply work '())
  (pf:echo-on)
  (setq *error*        *pf-run-prev-error*
        *pf-run-name*  nil
        *pf-run-flush* nil)
  (princ))


;;; ==========================================================================
;;; SECTION 7  --  Teardown + C:PFREMOVE
;;; ==========================================================================
;;; V4 teardown: walk every PASS_* handle ledger -> erase those entities ->
;;; erase the anchor (the ledger dies with it, hard-owned).  Entities never
;;; handle-tracked (CLAYER passes, hand-drawn work) are NEVER touched.

;; (pfa:teardown-counts anchor) -> (tracked-entities crossings passes)
(defun pfa:teardown-counts (anchor / n nm h e)
  (setq n 0)
  (foreach nm (pfa:pass-names anchor)
    (foreach h (pfa:pass-handles anchor nm)
      (if (and (setq e (handent h)) (entget e))
        (setq n (1+ n)))))
  (list n (length (pfa:xing-list anchor)) (length (pfa:pass-names anchor))))

;; (pfa:teardown anchor) -> count of entities erased
;;   Caller must hold an open undo group.
(defun pfa:teardown (anchor / nm n)
  (setq n 0)
  ;; 1. every tracked pass entity, by handle
  (foreach nm (pfa:pass-names anchor)
    (setq n (+ n (pfa:erase-pass anchor nm))))
  ;; 2. the anchor itself -- ledger dies with it
  (entdel anchor)
  n)

(if (not (boundp '*pfrem-undo-open*)) (setq *pfrem-undo-open* nil))

;; (pfrem:remove-anchor anchor) -> nil   Confirm + tear down ONE anchor.
;;   Split out of pfrem:cmd so the palette's btnRemove can hand in the anchor
;;   the user already selected instead of re-asking.  A SPLIT, NOT A GRAFT: no
;;   palette-only global reaches into a path the command line runs, so
;;   C:PFREMOVE is unchanged -- same pick, confirm, undo group and messages.
;;   Caller runs under pf:run-command; the undo group opens HERE, which is why
;;   the *pfrem-undo-open* reset lives here and not in the pick phase.
(defun pfrem:remove-anchor (anchor / counts n)
  (setq *pfrem-undo-open* nil)
  (cond
    ;; a COPY's ledger points at ANOTHER grid's entities -- teardown would
    ;; erase-by-handle the original's labels.  Offer copy-safe purge instead.
    ((pfa:copy-p anchor)
     (prompt (strcat "\n" (pfa:anchor-title anchor)
                     " is a COPY of another grid -- its ledger is not its own."
                     "\n  (Pasted in from another drawing?  PFADOPT takes"
                     " ownership instead of removing it.)"))
     (if (pfset:confirm
           (strcat (pfa:anchor-title anchor) " is a COPY of another grid.")
           '("Its ledger points at the ORIGINAL grid's entities, so a"
             "full teardown would erase the original's labels."
             ""
             "Pasted in from another drawing?  Cancel and run PFADOPT."
             ""
             "Purge just this copied anchor block (safe)?"))
       (progn
         (pf:undo-begin '*pfrem-undo-open*)
         (pfa:purge-copy anchor)
         (pf:undo-end '*pfrem-undo-open*)
         (prompt "\nCopied anchor purged (its cloned ledger died with it). "))
       (prompt "\nNothing removed.")))
    (T
      (setq counts (pfa:teardown-counts anchor))
      (if (not (pfset:confirm
                 (strcat "Remove " (pfa:anchor-title anchor) "?")
                 (list (strcat "Erases " (itoa (car counts))
                               " tracked entit"
                               (if (= (car counts) 1) "y" "ies")
                               ", " (itoa (cadr counts)) " crossing record(s), "
                               (itoa (caddr counts)) " pass record(s),")
                       "the anchor, and its ledger."
                       ""
                       "Manual work by the user is NOT touched.")))
        (prompt "\nNothing removed.")
        (progn
          (pf:undo-begin '*pfrem-undo-open*)
          (setq n (pfa:teardown anchor))
          (pf:undo-end '*pfrem-undo-open*)
          (prompt (strcat "\nRemoved anchor + ledger + " (itoa n)
                          " entit" (if (= n 1) "y" "ies")
                          ".  (One U reverses it.)"))))))
  (princ))

;; (pfrem:cmd) -> nil   The command body, run under pf:run-command.
;;   Finds a target, then hands it to pfrem:remove-anchor.  Nothing else.
(defun pfrem:cmd ( / anchor)
  (setq anchor (pfa:pick-anchor
                 "\nSelect grid anchor to REMOVE (Enter to list): "))
  (if (null anchor) (setq anchor (pfa:choose-anchor)))
  (if (null anchor)
    (prompt "\nNothing removed.")
    (pfrem:remove-anchor anchor))
  (princ))

(defun c:PFREMOVE ()
  (pf:run-command "PFREMOVE" nil 'pfrem:cmd))


;;; ==========================================================================
;;; SECTION 8  --  C:PFINDEX  (build / verify / report the membership index)
;;; ==========================================================================
;;; Nothing in normal use walks every structure -- the engine top-up only
;;; refreshes what it labeled -- so a drawing never indexed, or one where a line
;;; was just added, needs this.  The cold build is ALLOWED to be slow: run one
;;; pays, run two onward is nearly free.
;;;
;;; VERIFY is the point of the command.  Every acceptance test here is "same
;;; labels, faster", and nothing else compares the two answers.  This reads the
;;; saved record AND does the arithmetic the old way, then names the
;;; disagreements -- the only thing that turns a quiet wrong answer into a
;;; visible one.

;; (pfa:index-lines) -> the full same-type line table for every registered line
;;   The index is drawing-wide, so the table is every registry entry that
;;   resolves to a .cl -- not one profile's same-type subset.  Read-only.
(defun pfa:index-lines ( / pairs r clf)
  (setq pairs '())
  (foreach r (pfa:registry)
    (if (setq clf (pfa:entry-cl r))
      (setq pairs (cons (cons clf (cadr r)) pairs))))
  (pfa:build-lines (pf:dedupe-pairs (reverse pairs))))

;; (pfa:index-build lines inlets roster) -> (written skipped)
;;   Rewrites every structure's record against `roster`.  Caller holds an open
;;   undo group.  A refused write (locked layer, read-only xref) is counted,
;;   never fatal.
(defun pfa:index-build (lines inlets roster / nw ns e pt r)
  (setq nw 0 ns 0)
  (foreach e inlets
    (setq pt (cdr (assoc 10 (entget e))))
    (setq r (vl-catch-all-apply
              'pfa:memb-put
              (list e pt (pf:lines-at-point pt lines) roster)))
    (if (vl-catch-all-error-p r) (setq ns (1+ ns)) (setq nw (1+ nw))))
  (list nw ns))

;; (pfa:index-scan lines inlets roster) -> (current stale absent)
;;   Pure read: how much of the index is usable right now.
(defun pfa:index-scan (lines inlets roster / nc nst na e dict)
  (setq nc 0 nst 0 na 0)
  (foreach e inlets
    (cond
      ((pfa:memb-get e roster) (setq nc (1+ nc)))
      ((and (setq dict (pfa:ledger-dict e nil))
            (pfa:xrec-data dict *pfa-memb-key*))
       (setq nst (1+ nst)))                     ; a record, but not trustworthy
      (T (setq na (1+ na)))))                   ; no record at all
  (list nc nst na))

;; (pfa:index-verify lines inlets roster) -> list of disagreement strings
;;   THE PROOF.  For every structure holding a usable record, compute membership
;;   the old way and compare.  An empty list is the only evidence that the saved
;;   answers are the same answers.
(defun pfa:index-verify (lines inlets roster / out e pt saved live sv lv)
  (setq out '())
  (foreach e inlets
    (if (setq saved (pfa:memb-get e roster))
      (progn
        (setq pt   (cdr (assoc 10 (entget e)))
              live (pf:lines-at-point pt lines)
              sv   (mapcar '(lambda (h) (strcat (car h) "@"
                                                (rtos (cadr h) 2 3)))
                           (cdr saved))
              lv   (mapcar '(lambda (h) (strcat (car h) "@"
                                                (rtos (cadr h) 2 3)))
                           live))
        (if (not (equal (acad_strlsort (if sv sv '("-")))
                        (acad_strlsort (if lv lv '("-")))))
          (setq out (cons (strcat (cdr (assoc 2 (entget e)))
                                  " handle " (pf:handle e)
                                  ":  saved [" (pf:join sv ",")
                                  "]  live [" (pf:join lv ",") "]")
                          out))))))
  (reverse out))

;; (pfa:index-repair) -> (written skipped current stale) | nil
;;   PFSETUP's registration tail: write a MEMB record only where NO record
;;   exists; a STALE one is left for the engine top-up or an explicit PFINDEX
;;   Build.  That keeps registering n lines roughly linear, where a rebuild per
;;   registration would be O(n^2).  Caller holds an open undo group.
;;   nil when the index is off.
(defun pfa:index-repair ( / lines inlets roster nw ns nc nst e pt dict r)
  (if *pf-index-on*
    (progn
      (setq lines  (pfa:index-lines)
            inlets (pfa:gather-inlets)
            roster (pfa:roster-stamp lines T)
            nw 0 ns 0 nc 0 nst 0)
      (foreach e inlets
        (cond
          ((pfa:memb-get e roster) (setq nc (1+ nc)))
          ((and (setq dict (pfa:ledger-dict e nil))
                (pfa:xrec-data dict *pfa-memb-key*))
           (setq nst (1+ nst)))                 ; stale: not this repair's to touch
          (T
           (setq pt (cdr (assoc 10 (entget e)))
                 r  (vl-catch-all-apply
                      'pfa:memb-put
                      (list e pt (pf:lines-at-point pt lines) roster)))
           (if (vl-catch-all-error-p r) (setq ns (1+ ns)) (setq nw (1+ nw))))))
      (list nw ns nc nst))))

;; (pfindex:cmd) -> nil   The command body, run under pf:run-command.
;;   BORROWS *pfs-undo-open* deliberately.  pf:group-open-p checks a FIXED list
;;   of five flags, so a sixth of its own would be invisible to pf:run-error and
;;   an Esc mid-Build would leak an open undo group.  PFINDEX and PFSETUP cannot
;;   run at once, so sharing the flag is the safe option, not the lazy one.
(defun pfindex:cmd ( / lines inlets roster act res scan bad *pfa-file-geom*)
  (setq *pfs-undo-open* nil)
  (initget "Build Verify Report")
  (setq act (getkword "\nPFINDEX [Build/Verify/Report] <Report>: "))
  (if (null act) (setq act "Report"))
  (prompt "\nReading the registry...")
  ;; BUILD FILES THE GEOM CACHE AS IT READS, which is what makes every later
  ;; session's first palette click cheap -- the gather path can never fill that
  ;; cache itself.  So the undo group opens BEFORE the line build, not around
  ;; pfa:index-build alone: one U still peels the whole run.  It closes at the
  ;; tail, because the early-exit branches would otherwise leak it.
  ;; *pfa-file-geom* is a LOCAL -- dynamic scope hands it back even on Esc.
  (if (= act "Build")
    (progn (pf:undo-begin '*pfs-undo-open*)
           (setq *pfa-file-geom* T)))
  (setq lines  (pfa:index-lines)
        inlets (pfa:gather-inlets)
        roster (pfa:roster-stamp lines (= act "Build"))
        *pfa-file-geom* nil)
  (cond
    ((null lines)
     (prompt "\nNo registered lines -- nothing to index."))
    ((null inlets)
     (prompt "\nNo structure blocks match a label rule -- nothing to index."))
    ((not *pf-index-on*)
     (prompt "\nThe membership index is switched OFF (*pf-index-on* nil).")
     (prompt "\n  Records are neither read nor trusted; every command computes")
     (prompt "\n  membership the long way.  Turn it on in pftools-cfg.lsp."))
    ((= act "Build")
     (setq res (pfa:index-build lines inlets roster))
     (prompt (strcat "\nPFINDEX build: " (itoa (car res)) " structure(s) indexed"
                     (if (> (cadr res) 0)
                       (strcat ", " (itoa (cadr res))
                               " skipped (locked layer or read-only entity)")
                       "")
                     ".  (One U reverses it.)")))
    ((= act "Verify")
     (prompt (strcat "\nChecking " (itoa (length inlets))
                     " structure(s) BOTH ways -- this is the slow one..."))
     (setq bad (pfa:index-verify lines inlets roster))
     (if (null bad)
       (prompt "\nPFINDEX verify: every saved record matches a fresh computation.")
       (progn
         (prompt (strcat "\nPFINDEX verify: " (itoa (length bad))
                         " DISAGREEMENT(S) -- the index is not trustworthy."))
         (prompt "\n  Run PFINDEX Build, and if it recurs set *pf-index-on* nil.")
         (foreach res bad (prompt (strcat "\n  " res))))))
    (T
     (setq scan (pfa:index-scan lines inlets roster))
     (prompt (strcat "\nPFINDEX  " (itoa (length lines)) " line(s), "
                     (itoa (length inlets)) " structure(s):"))
     (prompt (strcat "\n  " (itoa (car scan))   " current"
                     "\n  " (itoa (cadr scan))  " stale (a record, but the lines moved under it)"
                     "\n  " (itoa (caddr scan)) " not indexed"))
     (prompt (strcat "\n  roster " roster))
     (if (> (+ (cadr scan) (caddr scan)) 0)
       (prompt "\n  PFINDEX Build refreshes the lot."))))
  (if *pfs-undo-open* (pf:undo-end '*pfs-undo-open*))
  (princ))

(defun c:PFINDEX ()
  (pf:run-command "PFINDEX" nil 'pfindex:cmd))


;;; ==========================================================================
;;; SECTION 9  --  C:PFADOPT  (take ownership of anchors pasted from elsewhere)
;;; ==========================================================================
;;; A pasted anchor arrives with its ledger intact -- the extension dictionary
;;; is hard-owned by the block -- but gets a FRESH handle, so META's 302 stamp
;;; no longer matches and pfa:copy-p reads T.  The suite then ignores it:
;;; pfa:registry drops it and pfa:find-anchor refuses to resolve it.
;;;
;;; That guard cannot tell a duplicate grid in THIS drawing from an anchor
;;; brought in from another one.  This command makes the distinction it cannot
;;; -- an anchor is adoptable only when no live non-copy anchor already holds
;;; its UTIL+LINE -- and re-stamps the ones that are legitimately new here.
;;;
;;; KEPT: META (.cl path + checksum) and FILES (.pro / .tin / material).  Both
;;; are paths and checksums, so both are portable, and re-keying them by hand is
;;; the whole cost this command exists to avoid.
;;;
;;; DROPPED: everything else in the ledger.  That is a SAFETY REQUIREMENT, not
;;; tidiness -- STATUS_*, PASS_* and X_* record ENTITY HANDLES, and handles are
;;; per-drawing.  Carried across they name unrelated objects in the new file,
;;; where PFREMOVE's teardown erases by handle (see pfrem:remove-anchor).
;;; WHITELIST, NOT BLACKLIST: a record type added later is dropped by default
;;; rather than silently carried into a drawing it does not describe.
;;;
;;; Adoption does not re-discover anything.  Crossings and the membership index
;;; are rebuilt by PFXLABEL and PFINDEX afterwards, which is why nothing here
;;; tries to preserve them.

(if (not (boundp '*pfadopt-undo-open*)) (setq *pfadopt-undo-open* nil))

;; (pfa:adopt-keep) -> the ledger keys an adopted anchor keeps
;;   ONE HOME for the whitelist: pfa:adopt drops by it and the confirm text
;;   describes it, so the two cannot drift.
(defun pfa:adopt-keep () '("META" "FILES"))

;; (pfa:adopt-test anchor) -> 'OK | 'NOTCOPY | 'SHADOWED    PURE READ
;;   'NOTCOPY  -- already this drawing's own; nothing to do.
;;   'SHADOWED -- a live non-copy anchor here already holds this UTIL+LINE, so
;;                adopting would give the drawing two anchors for one line and
;;                pfa:find-anchor would resolve to whichever it met first.
;;   pfa:find-anchor already excludes copies, so it returns the incumbent or nil
;;   -- exactly the test needed, and no second walk of the drawing.
(defun pfa:adopt-test (anchor / at)
  (cond
    ((not (pfa:copy-p anchor)) 'NOTCOPY)
    (T
     (setq at (pfa:read-attribs anchor))
     (if (pfa:find-anchor (pfa:att "LINE" at) (pfa:att "UTIL" at))
       'SHADOWED
       'OK))))

;; (pfa:adopt-cl-ok anchor) -> T when META's .cl resolves on this machine
;;   META stores an ABSOLUTE path, so a drawing adopted into a different project
;;   folder binds to files that are not there.  Reported, never refused: the
;;   binding is two clicks in PFSETUP (edit), and refusing would send the user
;;   back to re-anchoring, which is the thing being avoided.
(defun pfa:adopt-cl-ok (anchor / cl)
  (setq cl (cdr (assoc 1 (pfa:meta-get anchor))))
  (and cl (/= cl "") (findfile cl) T))

;; (pfa:adopt anchor) -> count of ledger records dropped
;;   Caller must hold an open undo group and must have tested with
;;   pfa:adopt-test -- this does no checking of its own.
;;   pfa:dict-keys is read ONCE up front, so the walk is over a snapshot and the
;;   deletions cannot disturb it.
(defun pfa:adopt (anchor / dict keep n k)
  (setq dict (pfa:ledger-dict anchor nil)
        keep (pfa:adopt-keep)
        n    0)
  (if dict
    (foreach k (pfa:dict-keys dict)
      (if (not (member k keep))
        (progn
          (pfa:xrec-del dict k)
          (setq n (1+ n))))))
  (pfa:stamp-self anchor)          ; 302 -> this block's own live handle
  n)

;; (pfadopt:candidates) -> every anchor in the drawing that reads as a copy
(defun pfadopt:candidates ( / out e)
  (setq out '())
  (foreach e (pfa:all-anchors)
    (if (pfa:copy-p e) (setq out (cons e out))))
  (reverse out))

;; (pfadopt:cmd) -> nil   The command body, run under pf:run-command.
;;   Reports the whole verdict BEFORE the confirm.  A pick-one loop is the wrong
;;   ergonomics here -- the reason to copy anchors at all is that there are
;;   dozens of them -- so the command works on every copy in the drawing and the
;;   command line carries the per-line detail the dialog cannot hold.
(defun pfadopt:cmd ( / cands ok shadow nofile e r dropped)
  (setq cands (pfadopt:candidates))
  (cond
    ((null cands)
     (prompt "\nPFADOPT: no copied anchors in this drawing -- nothing to adopt."))
    (T
     (setq ok '() shadow '() nofile '())
     (foreach e cands
       (setq r (pfa:adopt-test e))
       (if (eq r 'SHADOWED)
         (setq shadow (cons e shadow))
         (progn
           (setq ok (cons e ok))
           (if (not (pfa:adopt-cl-ok e)) (setq nofile (cons e nofile))))))
     (setq ok     (reverse ok)
           shadow (reverse shadow)
           nofile (reverse nofile))
     (prompt (strcat "\n=== PFADOPT -- " (itoa (length cands))
                     " copied anchor(s) ==="))
     (foreach e ok
       (prompt (strcat "\n  adopt    " (pfa:anchor-title e)
                       (if (member e nofile) "   (.cl NOT FOUND)" ""))))
     (foreach e shadow
       (prompt (strcat "\n  REFUSE   " (pfa:anchor-title e)
                       " -- already anchored in this drawing")))
     (cond
       ((null ok)
        (prompt "\nNothing to adopt."))
       ((not (pfset:confirm
               (strcat "Adopt " (itoa (length ok)) " anchor(s)?")
               (list "Keeps the .cl / .pro / .tin bindings."
                     ""
                     "CLEARS label state, pass records and crossing records --"
                     "those name entities in the drawing they came from."
                     ""
                     "Re-run PFXLABEL and PFINDEX afterwards.")))
        (prompt "\nNothing adopted."))
       (T
        (pf:undo-begin '*pfadopt-undo-open*)
        (setq dropped 0)
        (foreach e ok (setq dropped (+ dropped (pfa:adopt e))))
        (pf:undo-end '*pfadopt-undo-open*)
        (prompt (strcat "\nAdopted " (itoa (length ok)) " anchor(s); dropped "
                        (itoa dropped) " stale ledger record(s)."
                        "  (One U reverses it.)"))
        (if nofile
          (prompt (strcat "\n  " (itoa (length nofile))
                          " have a .cl that does not resolve here"
                          " -- rebind in PFSETUP (edit).")))
        (prompt "\n  Run PFXLABEL and PFINDEX to rebuild what was dropped.")))))
  (princ))

(defun c:PFADOPT ()
  (pf:run-command "PFADOPT" nil 'pfadopt:cmd))


(princ "\npfanchor.lsp loaded (V4 record + registry).  Commands: PFREMOVE, PFINDEX, PFADOPT.")
(princ)
;;; ==========================================================================
;;; end of pfanchor.lsp
;;; ==========================================================================
