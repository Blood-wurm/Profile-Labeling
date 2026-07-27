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
(defun pfa:xr-tfile (e) (nth 1 e))
(defun pfa:xr-tbase (e) (nth 2 e))
(defun pfa:xr-sfile (e) (nth 3 e))
(defun pfa:xr-sbase (e) (nth 4 e))
(defun pfa:xr-xy    (e) (nth 5 e))
(defun pfa:xr-tsta  (e) (nth 6 e))
(defun pfa:xr-ssta  (e) (nth 7 e))
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
;;   The anchor is a backdrop marker: it must never sit on top of the grid,
;;   the profile, or a label.  DRAWORDER is the only route to sort-ents from
;;   plain LISP, so this shells out with echo suppressed.  Draw order is
;;   cosmetic, never structural -- a failure here is swallowed, and the anchor
;;   it was called on is still a valid, readable anchor.
;;   command-s, NOT command: `command` is a special form, so vl-catch-all-apply
;;   rejects it outright ("bad order function: COMMAND") and the error escapes
;;   the very catch meant to contain it.  Same applicable form pf:zoom-onerror
;;   already uses for its guarded ZOOM.
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
;;   The block is a fixed-size icon snapped to the datum, drawn at the size it
;;   should read on an H:*pfa-icon-ref-hplot* sheet.  Model size must track the
;;   plot scale to hold a constant size on paper, so the factor is a plain
;;   ratio and is applied to X, Y AND Z -- an icon must never distort, which is
;;   also why the extents no longer ride on the scale factors (see pfa:extents).
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
;;   ATTDEFs the ledger depends on.  pfa:write-anchor entmakes the ATTRIBs onto
;;   the insert regardless (the (66 . 1) route), so anchors read correctly
;;   either way -- but a definition with no matching ATTDEFs is one ATTSYNC or
;;   block-editor round-trip away from losing every one of them, and those
;;   attributes ARE the anchor's geometric state.  ADDITIVE ONLY: adds just the
;;   missing tags, invisible, and touches no existing geometry.  AddAttribute
;;   does not back-propagate to placed inserts, and ours already carry their own
;;   ATTRIBs, so nothing on screen changes.
;;   Every ActiveX call is catch-wrapped -- a drawing that will not hand over
;;   its block collection still gets a working anchor, just an un-synced block.
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
;;   The hand-authored PF-ANCHOR always wins: when the drawing already carries
;;   a definition this only tops up its ATTDEFs and leaves the artwork alone.
;;   What follows is the FALLBACK, entmade only in a drawing that has never
;;   seen one -- a PLACEHOLDER datum pointer (apex on the insertion point,
;;   roughly text-height at H:50), not a stand-in for the real icon.  It is
;;   deliberately small: the block no longer spans the grid, so nothing here
;;   is scaled to the extents.
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
;;   Extents are stored RELATIVE to the insertion point (grid lower-left), so a
;;   window-move of grid + anchor carries both -- that is the design, and it is
;;   why pfa:corner-check cannot see such a move.
;;   CURRENT anchors keep them in the WIDTH/HEIGHT attributes.  They used to be
;;   the insert's X/Y scale factors, back when the block SPANNED the grid; the
;;   block is a fixed-size icon now and its scales carry plot scale, so reading
;;   extents off them would be nonsense (at H:200 the X-scale is 4.0).
;;   The scale-factor read survives ONLY as the legacy path, and the ABSENCE of
;;   the WIDTH/HEIGHT attributes is exactly what identifies a pre-icon anchor --
;;   scale alone cannot tell the two apart.  The old xs > 2.0 sentinel (no real
;;   grid is 2 ft wide) still guards the legacy width, which legacy anchors
;;   only carried when the top-right had been picked.
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
  (pfd:ensure-layer *pfa-layer* T)
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
;;   Extents go back to whichever storage THIS anchor already uses.  An anchor
;;   carrying a WIDTH attribute is a current one: extents to the attributes,
;;   scale factors to the icon scale.  One without is pre-icon, and its extents
;;   ARE its scale factors -- writing the icon scale over them would silently
;;   shrink its grid to a few feet, so that anchor keeps the old storage and
;;   the old block.  Attributes are only ever UPDATED here, never added: the
;;   ledger hangs off this insert, so it must survive in place.
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
;;   grid-layer LINEs at all (nothing to assert against).  The PF-GRID-*
;;   layers are Carlson's own grid layers (confirmed 2026-07-17).
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

;; (pfa:ledger-dict anchor create) -> PFXLEDGER dictionary ename | nil
;;   HARD-OWNED (280 . 1): erasing the anchor erases the ledger.
(defun pfa:ledger-dict (anchor create / xde sub)
  (setq xde (pfa:extdict-of anchor))
  (if (and (null xde) create)
    (setq xde (vlax-vla-object->ename
                (vla-getextensiondictionary
                  (vlax-ename->vla-object anchor)))))
  (if xde
    (cond
      ((setq sub (dictsearch xde *pfa-dict-name*))
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
;;   Same contract as pfa:ledger-dict: create nil NEVER writes -- a read on a
;;   drawing that has no PFTOOLS dictionary returns nil instead of creating
;;   one.  This is the palette-safety seam: pfa:registry runs from a MODELESS
;;   handler, and merely opening the palette must not dirty a clean drawing
;;   (or write to the DB mid-command).  Only genuine writers pass T.
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

(defun pfa:stub-key (type name)
  (strcat "STUB_" (pfa:sanitize (strcase type))
          "_" (pfa:sanitize (strcase name))))

;; (pfa:stub-get type name) -> data | nil   (pure read)
(defun pfa:stub-get (type name / dict)
  (if (setq dict (pfa:nod-dict nil))
    (pfa:xrec-data dict (pfa:stub-key type name))))

;; (pfa:stub-put type name cl inv top) -> xrecord ename   (WRITE)
(defun pfa:stub-put (type name cl inv top)
  (pfa:xrec-put (pfa:nod-dict T) (pfa:stub-key type name)
                (list (cons 1 cl)
                      (cons 2 (strcase type))
                      (cons 3 (strcase name))
                      (cons 4 (if inv inv ""))
                      (cons 5 (if top top "")))))

;; (pfa:stub-del type name) -> nil   (no dict = nothing to delete)
(defun pfa:stub-del (type name / dict)
  (if (setq dict (pfa:nod-dict nil))
    (pfa:xrec-del dict (pfa:stub-key type name))))

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
  ;; line, so a clean drawing -- no anchors, no stubs -- printed a spurious
  ;; error every time the palette opened (found by PALETTE-TESTING 3, which is
  ;; the first test ever run against a drawing that had never seen PFTOOLS).
  ;; Guarded, not reordered: behaviour for a non-empty registry is unchanged.
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
;;   THE registry row -> .cl resolution, one home: anchors read META, stubs
;;   read the stub record; "" reads as nil.  Moved here from pfxlabel (it is
;;   pure registry knowledge) so pflabel can call it without violating the
;;   depend-only-upward guardrail.  Pure read.
(defun pfa:entry-cl (r / cl)
  (setq cl (if (eq (caddr r) 'ANCHORED)
             (cdr (assoc 1 (pfa:meta-get (nth 3 r))))
             (nth 2 (nth 4 r))))
  (if (and cl (/= cl "")) cl))

;;; ---- TWIN: drawn plan-centerline binding per .cl (handle only) ------------
;;; The membership PRE-FILTER reads the .cl's DRAWN centerline (exact PIs, no
;;; sampled corner-cut).  Matched ONCE at registration by endpoint pair and
;;; filed here as a bare HANDLE; label runs entget it LIVE, so a moved/redrawn
;;; twin reads as-drawn, never cached stale.  Nothing to invalidate -- a
;;; purged/erased twin resolves to nil and the reader re-matches or drops the
;;; pre-filter (the authored cl_location_at_pt test still governs membership).
;;;   key "TWIN_<cl-id>":  (1 . handle)(300 . cl-checksum-at-match)
;;; Keyed by CANONICAL .cl identity (pf:cl-id), not basename.  The .cl checksum
;;; at match time is stored so the witness step can tell whether the recorded
;;; twin still corresponds to the current .cl.

(defun pfa:twin-key (clfile)
  (strcat "TWIN_" (pfa:sanitize (pf:cl-id clfile))))

;; (pfa:twin-get clfile) -> handle string | nil   (pure read)
(defun pfa:twin-get (clfile / dict d h)
  (if (and (setq dict (pfa:nod-dict nil))
           (setq d (pfa:xrec-data dict (pfa:twin-key clfile))))
    (progn
      (setq h (cdr (assoc 1 d)))
      (if (and h (/= h "")) h))))

;; (pfa:twin-cksum clfile) -> .cl checksum stored at match time | nil
;;   Lets the witness step detect a twin recorded against an older .cl.
;;   Pure read.
(defun pfa:twin-cksum (clfile / dict d)
  (if (and (setq dict (pfa:nod-dict nil))
           (setq d (pfa:xrec-data dict (pfa:twin-key clfile))))
    (cdr (assoc 300 d))))

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
;;; ---- STATUS: state + timestamp + findings --------------------------------
;;; state: 0 unchecked / 1 passing / 2 failing / 3 stale.
;;; UNCHECKED NEVER RENDERS GREEN.

(defun pfa:status-get (anchor) (pfa:rec-get anchor "STATUS"))

(defun pfa:status-put (anchor state findings / data f)
  (setq data (list (cons 70 state) (cons 1 (pf:timestamp))))
  (foreach f findings
    (setq data (append data (list (cons 300 f)))))
  (pfa:rec-put anchor "STATUS" data))

(defun pfa:status-label (state)
  (cond ((= state 1) "PASSING")
        ((= state 2) "FAILING")
        ((= state 3) "STALE")
        (T "UNCHECKED")))

;;; ---- SCOPE: PFXFIND discovery scope --------------------------------------

(defun pfa:scope-get (anchor) (pfa:rec-get anchor "SCOPE"))

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

;; (pfa:xing-merge anchor e) -> 'NEW | 'UPDATED | 'MOVED
;;   Elevations already on record are PRESERVED; key drift renames.
(defun pfa:xing-merge (anchor e / dict key d old-t old-s kdrift k status data)
  (setq dict   (pfa:ledger-dict anchor T)
        key    (pfa:xing-key (pfa:xr-sbase e) (pfa:xr-tsta e))
        status 'NEW
        old-t  nil
        old-s  nil)
  (cond
    ((dictsearch dict key)
     (setq d      (pfa:xrec-data dict key)
           old-t  (cdr (assoc 42 d))
           old-s  (cdr (assoc 43 d))
           status 'UPDATED))
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
     (if kdrift
       (progn
         (setq d      (pfa:xrec-data dict kdrift)
               old-t  (cdr (assoc 42 d))
               old-s  (cdr (assoc 43 d))
               status 'MOVED)
         (pfa:xrec-del dict kdrift)))))
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

;;; ---- Reconciliation (read-only; TWO scans per call) ----------------------
;;; STEPPED TOPS: a crossing station line is drawn to the grid top AT ITS
;;; STATION (the top-of-grid probe), so the "labeled" signature is
;;; per-station too: exact X match AND top vertex at pf:top-at for that X.
;;; The SAME lookup feeds the draw and this check -- if the grid is
;;; unchanged the two values are bit-identical; if the grid was re-drawn,
;;; the old label honestly reads outstanding.

;; (pfa:station-line-tops) -> list of (x . ytop): each crossing station
;;   line's TOP vertex.  One scan.
(defun pfa:station-line-tops ( / ss i ed p bx by out)
  (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *pfa-xing-layer*)
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
;;; The shared command wrapper  (pf:run-command -- audit #9)
;;; --------------------------------------------------------------------------
;;; ONE copy of the prologue/epilogue every PF command used to carry four
;;; times over: *error* save/install, echo-off/on, the undo-group flag
;;; pattern, and the error-path teardown.  Replaces pfa:undo-cleanup's
;;; transitional role.  Lives here because every command already depends on
;;; pfanchor; it is also the future home caller for the deferred C:PF*RUN
;;; commands (Tab 2).
;;;
;;; The FLUSH hook is per-command (pflabel:flush-pass, pfi:flush-pass,
;;; pfxl:flush-pass): on an Esc mid-run it writes the pass ledger for
;;; whatever was drawn before the interrupt, INSIDE the still-open undo group
;;; (entmakex/dictadd are *error*-legal).  Partial output is therefore ON the
;;; ledger -- pfa:erase-pass, PFREMOVE and recon account for it -- and one U
;;; still peels the whole run (the flush's record writes die with the group).

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
      *pfinvert-undo-open* *pfrem-undo-open*))

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
        *pfrem-undo-open*    nil)
  (pf:echo-on)                       ; error path always restores CMDECHO
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
;;   The body still opens/closes its own undo group (via pf:undo-begin/end)
;;   at the point its writes start -- gather stays OUTSIDE the group.
(defun pf:run-command (name flush work)
  (setq *pf-run-prev-error* *error*
        *pf-run-name*       name
        *pf-run-flush*      flush
        *error*             pf:run-error)
  (pf:echo-off)
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

;; (pfrem:cmd) -> nil   The command body, run under pf:run-command.
(defun pfrem:cmd ( / anchor counts n)
  (setq *pfrem-undo-open* nil)
  (setq anchor (pfa:pick-anchor
                 "\nSelect grid anchor to REMOVE (Enter to list): "))
  (if (null anchor) (setq anchor (pfa:choose-anchor)))
  (cond
    ((null anchor)
     (prompt "\nNothing removed."))
    ;; a COPY's ledger points at ANOTHER grid's entities -- teardown would
    ;; erase-by-handle the original's labels.  Offer copy-safe purge instead.
    ((pfa:copy-p anchor)
     (prompt (strcat "\n" (pfa:anchor-title anchor)
                     " is a COPY of another grid -- its ledger is not its own."))
     (if (pfset:confirm
           (strcat (pfa:anchor-title anchor) " is a COPY of another grid.")
           '("Its ledger points at the ORIGINAL grid's entities, so a"
             "full teardown would erase the original's labels."
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
                       "Untracked work (hand-drawn, CLAYER passes) is NOT touched.")))
        (prompt "\nNothing removed.")
        (progn
          (pf:undo-begin '*pfrem-undo-open*)
          (setq n (pfa:teardown anchor))
          (pf:undo-end '*pfrem-undo-open*)
          (prompt (strcat "\nRemoved anchor + ledger + " (itoa n)
                          " entit" (if (= n 1) "y" "ies")
                          ".  (One U reverses it.)"))))))
  (princ))

(defun c:PFREMOVE ()
  (pf:run-command "PFREMOVE" nil 'pfrem:cmd))


(princ "\npfanchor.lsp loaded (V4 record + registry).  Command: PFREMOVE.")
(princ)
;;; ==========================================================================
;;; end of pfanchor.lsp
;;; ==========================================================================
