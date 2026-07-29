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

;; (pfa:ledger-dict ent create) -> PFLEDGER dictionary ename | nil
;;   HARD-OWNED (280 . 1): erasing the entity erases its ledger.
;;   OWNER-AGNOSTIC, and always was -- nothing below ever looked at the anchor.
;;   An ANCHOR's ledger holds META / FILES / STATUS_* / SCOPE / PASS_* / X_*;
;;   a STRUCTURE's holds MEMB.  The parameter was renamed from `anchor` to
;;   `ent` 2026-07-27 to stop the name implying a constraint the code does not
;;   have.
;;
;;   LEGACY READ + HEAL: drawings registered before the rename carry the ledger
;;   under *pfa-dict-legacy*.  Read it as-is, and RENAME it on the first write
;;   so the fallback drains instead of being carried forever.  A read must NOT
;;   rename -- the palette reads with create nil and may never touch the
;;   database (the write-free contract), so the rename is gated on `create`.
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
;;; ---- STATUS_<PASS>: per-tool input verdict -------------------------------
;;; state: 0 unchecked / 1 passing / 2 failing / 3 stale.
;;; UNCHECKED NEVER RENDERS GREEN.
;;;
;;; ONE RECORD PER TOOL, split 2026-07-27.  There used to be a single "STATUS",
;;; written by PFSETUP, PFLABEL and PFINVERT about THREE DIFFERENT FILES -- so
;;; whichever ran last erased the others' verdict, and running PFLABEL then
;;; PFINVERT silently discarded everything known about the .cl.  Keyed
;;; STATUS_<PASS> to match the PASS_<name> grammar beside it, so each command
;;; writes only its own and pfa:dict-keys enumerates the set.
;;;   LABEL  -> the .cl        INVERT -> the _INV .pro
;;;   XING   -> target + source .cl, whose checksums SCOPE already holds; that
;;;             record stays the source of truth and is not copied here.
;;;
;;; WHAT IS AND IS NOT STORED.  Stored: the input's checksum AT PASS TIME (301).
;;; You cannot work out later what a file WAS when it was labeled, so this is
;;; real state and it is the whole basis of "stale".  NOT stored: how many
;;; structures are done out of how many.  A saved count reads 12-of-12 forever
;;; after someone erases a label; the live gather owns that number (see the
;;; drift-echo note in pfa:gather-compute, which makes the same argument).

(defun pfa:status-key (pass) (strcat "STATUS_" (strcase pass)))

;; (pfa:status-get anchor pass) -> data | nil
;;   Falls back to the pre-split "STATUS" record so an anchor written before
;;   2026-07-27 still reports something instead of reading UNCHECKED.  That old
;;   record has no pass identity, so it answers for every pass -- which is
;;   exactly as much as it ever knew.
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
;;   about the .cl, so it must not clear PFLABEL's verdict.  The old single
;;   record could only be reset wholesale, which is why an edit used to throw
;;   away checks it had not invalidated.
(defun pfa:status-reset (anchor passes findings / p)
  (foreach p passes (pfa:status-put anchor p 0 "" findings))
  (princ))

(defun pfa:status-label (state)
  (cond ((= state 1) "PASSING")
        ((= state 2) "FAILING")
        ((= state 3) "STALE")
        (T "UNCHECKED")))

;; (pfa:status-check anchor pass file stored) -> (state . findings)
;;   THE ONE COMPARISON, shared by every writer: what the input file's checksum
;;   was when the pass ran, against what it is now.  State 3 finally has a
;;   writer -- "the file changed under you" is a different fact from state 2,
;;   "the file cannot be read at all", and collapsing them lost the difference.
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
;;   ever update a saved roll-up when one of the three beneath it moved.  Worst
;;   state wins, so a single failing input cannot read green.  done/total are
;;   the caller's to supply from a live gather; this reports only what the
;;   stored records know.
(defun pfa:status-roll (anchor / worst n d p st s)
  (setq worst 1 n 0 s '())
  (foreach p '("LABEL" "INVERT" "XING")
    (setq d  (pfa:status-get anchor p)
          st (if (and d (assoc 70 d)) (cdr (assoc 70 d)) 0))
    (if (= st 0) (setq n (1+ n)))
    (if (member st '(2 3)) (setq s (cons p s)))
    ;; 2 failing beats 3 stale beats 0 unchecked beats 1 passing
    (if (> (pfa:status-rank st) (pfa:status-rank worst)) (setq worst st)))
  (list worst (- 3 n) 3 (reverse s)))

;; (pfa:status-rank state) -> sort weight; higher is worse.
(defun pfa:status-rank (state)
  (cond ((= state 2) 3) ((= state 3) 2) ((= state 0) 1) (T 0)))

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
;;; SECTION 4b  --  The membership index  (structure -> lines, saved)
;;; ==========================================================================
;;; THE PROBLEM: PFLABEL re-derives, from scratch, which structures sit on
;;; which lines -- including the work it did five seconds earlier on an
;;; unchanged drawing.  PFINVERT does it again.  PFREPORT does it again.  The
;;; facts are stable; nothing persisted them.
;;;
;;; THE RECORD IS THE RETURN SHAPE.  pf:lines-at-point takes a point and gives
;;; back the set of lines it falls on; that IS what gets stored, in the order it
;;; came back (offset-ascending -- re-sorting on write would make the reader
;;; non-identical to the function it stands in for).  A structure whose set has
;;; more than one entry is a junction, with no cross-line read.
;;;
;;; WHAT IT HOLDS AND WHAT IT DOES NOT.  In: structure, line, station, and the
;;; stamps that say when to stop believing it.  Out: everything that needs a
;;; .pro -- inverts, cover, clearance, wall thickness.  Membership is stable and
;;; .pro churns through design, so caching the second would produce a record
;;; that is wrong most of the time.  Crossings are out too: X_* above already
;;; persists them, with additive merge and key-drift renaming.
;;;
;;; STAMPS.  A LINE stamp folds everything that can change one line's answer
;;; into one token: the .cl's CONTENT (pf:cl-id is a canonical PATH and cannot
;;; see an edit), the station range that gates a hit, the corridor width, and a
;;; real hash of the pre-filter shape.  A ROSTER stamp folds every registered
;;; line's stamp into one.
;;;
;;; WHY THE ROSTER STAMP AND NOT PER-LINE STAMPS.  A record lists HITS.  Nothing
;;; in it says which lines were tested and missed.  So per-line stamps cannot
;;; answer the question that actually matters -- "was this worked out when the
;;; world looked like it does now" -- and a structure that was off BA and is now
;;; on it would read clean forever, because its record never mentions BA.  One
;;; stamp covering the whole roster does answer it: match means the hits are
;;; complete AND the misses are still misses.  The cost is coarser: any .cl edit
;;; stales every record.  Geometry does not churn, and a rebuild is one command.
;;;
;;; Documented in pfanchor/INDEX-PLAN.md; INDEX-DESIGN.md / INDEX-VALUES.md hold
;;; the reasoning that got here.

;;; ---- Registry + selection helpers (moved from pflabel 2026-07-27) ---------
;;; Both were always registry/selection knowledge rather than label knowledge,
;;; and the index writer -- position 4 -- cannot reach up to pflabel at 7.  No
;;; alias left behind; same precedent as pfa:entry-cl.

;; (pfa:build-lines pairs) -> line table: (clfile name lo hi verts tol bbox)*
;;   GATHER-PATH PURITY: this runs from the run dialogs and setup, BEFORE any
;;   undo group (and from a modeless palette handler), so it must not write the
;;   drawing: pf:cl-geom is called read-only (a cache miss re-samples, never
;;   files) and a re-matched twin is USED for this run but NOT filed --
;;   persisting GEOM/TWIN belongs to PFSETUP registration and PFXLABEL
;;   discovery, which run in a command context.  Cost of an unfiled twin: one
;;   ssget scan per un-filed line per run.
;;   Publishes *pfa-roster* as a side effect -- see pfa:roster-set.
(defun pfa:build-lines (pairs / tbl file nm geom rng vts tol h entry p)
  (setq tbl '())
  (foreach p pairs
    (setq file (car p) nm (cdr p))
    (if (setq geom (pf:cl-geom file nil))      ; READ-ONLY: never files from a gather
      (progn
        (setq rng (car geom)
              ;; membership pre-filter = the DRAWN twin's LIVE verts (exact PIs,
              ;; no sampled corner-cut at deflections), read via the filed handle
              h   (pfa:twin-get file)
              vts (pf:twin-verts h)
              tol nil)                         ; exact shape -> exact corridor
        ;; twin missing from the store (pre-feature registry, New-placed line,
        ;; purged handle): re-match for THIS run only -- no pfa:twin-put here
        (if (null vts)
          (progn
            (setq h (pf:cl-twin-handle file *pf-corridor*))
            (if h (setq vts (pf:twin-verts h)))))
        ;; STILL nothing drawn to match -- registered-only lines never have a
        ;; twin, and they are exactly what pfa:registry-pairs adds.  Fall
        ;; back to the .cl's own SAMPLED shape, which pf:cl-geom already
        ;; returned in (cdr geom): a coarse corridor, but a corridor.  Shipping
        ;; nil here turned the pre-filter OFF for those lines, and every
        ;; structure in the drawing then reached cl_location_at_pt -- the
        ;; "unable to locate point along centerline" parade (see
        ;; pf:lines-at-point).
        (if (and (null vts) (cdr geom))
          (setq vts (cdr geom)
                tol *pf-corridor-sampled*))    ; corner-cut allowance
        ;; bbox computed ONCE here; it is consulted per structure per line
        (setq entry (list file nm (car rng) (cadr rng) vts tol
                          (pf:verts-bbox vts))
              tbl   (cons entry tbl))
        ;; PROGRESS: one line per line in the gather set.  Suppressed under
        ;; *pf-quiet* -- a palette click runs this same path and does not want
        ;; a six-line preamble.  The error below is a FINDING and still prints.
        (pf:progress (strcat "\nLoaded line '" nm "' (Sta " (pf:fmt-station (car rng))
                        " to " (pf:fmt-station (cadr rng)) ")"
                        (cond
                          ((null vts)
                           "  [no shape available -- pre-filter off, authored test only].")
                          (tol
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
        vh (pf:verts-hash (nth 4 entry)))
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
;;; MOVED DOWN FROM pflabel 2026-07-29, completing the migration begun on
;;; 2026-07-27 with pfa:build-lines / pfa:gather-inlets.  Every function here
;;; is membership-and-ledger knowledge rather than label knowledge: not one of
;;; them called anything in pflabel, and each reaches only pfanchor (position 4)
;;; or pftools-lib (position 2).
;;;
;;; The forcing reason is the palette.  pfpalette sits at position 11 and needs
;;; per-target counts; with the gather at 7 it would have had to reach sideways
;;; into pflabel, and pfanchor -- which every module already depends on --
;;; could never have served them, because 4 cannot reach up to 7.  Now the
;;; three label commands, pfreport and the palette all resolve membership
;;; through ONE path.  Same precedent as pfa:entry-cl (out of pfxlabel,
;;; 2026-07-26) and the build-lines/gather-inlets move.
;;;
;;; ALL PURE READS -- the palette contract holds throughout, so a modeless
;;; handler may call any of it.

(defun pfa:line-loaded-p (name lines)
  (car (vl-member-if '(lambda (e) (= (cadr e) name)) lines)))

;; (pfa:registry-pairs primary-cl) -> list of (path . name): every
;;   OTHER registry entry's .cl -- anchors AND stubs.  The self-maintaining
;;   secondary set.  Stubs count because membership is plan-view station
;;   math: IDENTITY IS ENOUGH -- a registered line still contributes to a
;;   junction's combined ID.  (This closes the old silently-shorter-ID gap.)
;;   Secondaries are SAME-UTILITY-TYPE only: a STORM profile's junctions are
;;   other STORM lines.  A different type sharing a station is a CROSSING, not
;;   a junction -- that's PFXLABEL's job, not a combined-ID contributor here.
;;
;;   ONE BUILDER (audit #12): a thin filter over pfa:registry -- the one
;;   merged, COPY-EXCLUDING, sorted walk -- resolved via pfa:entry-cl, self
;;   dropped by canonical identity (pf:cl-id).  Consumers: both setups, both
;;   run dialogs, pfreport, and pfa:target-counts.  PFLABEL and PFINVERT can
;;   no longer disagree about a junction's line set by construction.
(defun pfa:registry-pairs (primary-cl / out r clf ptype pid)
  (setq out '() ptype (pf:type-of primary-cl) pid (pf:cl-id primary-cl))
  (foreach r (pfa:registry)
    (if (and (setq clf (pfa:entry-cl r))
             (/= (pf:cl-id clf) pid)                ; drop self
             (= (pf:type-of clf) ptype))            ; same type only
      (setq out (cons (cons clf (cadr r)) out))))
  (reverse out))

;; (pfa:pending inlets lines primary) -> ((sta ename blkname) ...)
;;   Every structure on the PRIMARY line, sorted by station.
(defun pfa:pending (inlets lines primary / out e pt hits ph)
  (setq out '())
  (foreach e inlets
    (setq pt   (cdr (assoc 10 (entget e)))
          hits (pfa:lines-at e pt lines)
          ph   (car (vl-member-if '(lambda (h) (= (car h) primary)) hits)))
    (if ph (setq out (cons (list (cadr ph) e (cdr (assoc 2 (entget e))))
                           out))))
  (vl-sort out '(lambda (a b) (< (car a) (car b)))))

;; (pfa:pass-xs anchor passname) -> X ordinates of the pass's entities
(defun pfa:pass-xs (anchor passname / out h e ed p)
  (setq out '())
  (foreach h (pfa:pass-handles anchor passname)
    (if (and (setq e (handent h)) (setq ed (entget e))
             (setq p (cdr (assoc 10 ed))))
      (setq out (cons (car p) out))))
  out)

;; (pfa:labeled-x-p x xs eps) -> T when a pass entity sits at this X
;;   Symmetric in its two arguments -- also used the other way round, to ask
;;   whether a STRUCTURE sits at a given pass entity's X (see orphan-xs).
(defun pfa:labeled-x-p (x xs eps / found v)
  (setq found nil)
  (foreach v xs
    (if (<= (abs (- v x)) eps) (setq found T)))
  found)

;; (pfa:cluster-xs xs eps) -> one representative X per eps-cluster
;;   A label STACK is many entities at one X (every row, plus the station
;;   line), so a raw count of pass entities would report one moved structure
;;   as five.  Collapse to stations before counting anything.
(defun pfa:cluster-xs (xs eps / out v)
  (setq out '())
  (foreach v xs
    (if (not (pfa:labeled-x-p v out eps)) (setq out (cons v out))))
  (reverse out))

;; (pfa:orphan-xs pend xs eps xf) -> pass X ordinates with no structure
;;   THE DRIFT DETECTOR, and the reverse of the [LABELED] test.  labeled-x-p
;;   asks "does a label sit at this structure?"; this asks "does a structure
;;   sit under this label?"  A no means the structure MOVED or was ERASED
;;   after it was labeled, and the label is now at a stale station.
;;
;;   No stored position is needed for this: the DRAWN LABELS ARE THE RECORD of
;;   where the structures were.  The sheet is the baseline, which is also the
;;   thing that is actually wrong when they disagree.
;;
;;   Degrades honestly -- a moved structure reads Outstanding at its new
;;   station AND leaves an orphan at its old one.  Two signals, one event.
(defun pfa:orphan-xs (pend xs eps xf / sxs out v)
  (setq sxs (mapcar '(lambda (p) (pf:station->profile-x (car p) xf)) pend)
        out '())
  (foreach v (pfa:cluster-xs xs eps)
    (if (not (pfa:labeled-x-p v sxs eps)) (setq out (cons v out))))
  (reverse out))

;;; ---- The gather memo  (SESSION-scoped; not a drawing write) --------------
;;; The membership product is inlets x lines and it was recomputed from
;;; scratch on every run, every target switch, and every cancelled dialog.
;;; This memoises ONLY that product.  build-lines still runs fresh each time,
;;; because it is O(lines) rather than O(lines x structures) and running it
;;; keeps the twin verts LIVE -- so a moved plan centerline can never be
;;; served stale out of here.
;;;
;;; AutoLISP globals are per-document, so this is naturally per-drawing.
;;; Nothing here touches the database: it is a LISP variable, legal from a
;;; modeless handler, and it survives a cancelled dialog (which is precisely
;;; the case that used to throw a full gather away).
;;;
;;; THE KEY IS THE WHOLE INPUT SET of the thing memoised, and every part of it
;;; is cheap.  Since the 2026-07-29 split this memo holds PEND ONLY, so the key
;;; is exactly what pfa:pending reads:
;;;   primary                   which line is being asked about
;;;   inlet signature           (handle x y) per structure -- catches ADD,
;;;                             ERASE and MOVE, which is the full set of
;;;                             things that can change membership
;;;   line signature            per line: name, range, corridor tol, bbox and
;;;                             vertex count -- catches a re-bound .cl, a
;;;                             moved twin, a registry add/remove
;;; A stale entry cannot be served: anything that would change the answer is
;;; in the key.  Nothing is derived-and-trusted.
;;;
;;; NOT IN THE KEY -- anchor, pass name, pass X ordinates.  None are inputs to
;;; pending.  The ordinates were there only because the entry used to carry
;;; status and orphans too; status now recomputes every call (pfa:status-for),
;;; so drawing a label no longer throws away a walk it never invalidated.

(if (not (boundp '*pfa-gather-memo*)) (setq *pfa-gather-memo* '()))
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

;; (pfa:pend-for primary lines inlets) -> ((sta ename blkname) ...)
;;   THE EXPENSIVE HALF, split out of gather-compute 2026-07-29 so ONE walk can
;;   serve MANY passes -- the Commands tab shows Structure and Invert counts
;;   side by side, and asking gather-compute twice used to mean two identical
;;   inlets x lines walks.
;;   Assumes primary is loaded in lines -- gather-compute holds that guard.
(defun pfa:pend-for (primary lines inlets / key hit pend)
  (setq key (list primary
                  (pfa:inlet-sig inlets)
                  (pfa:lines-sig lines)))
  (if (setq hit (pfa:memo-get key *pfa-gather-memo*))
    (cdr hit)                                 ; HIT -- no inlets x lines walk
    (progn
      (setq pend (pfa:pending inlets lines primary)
            *pfa-gather-memo*
                 (pfa:memo-put key pend *pfa-gather-memo*))
      pend)))

;; (pfa:status-for anchor passname pend xform) -> (status orphans)
;;   THE CHEAP HALF: a handle walk (pass-xs) plus arithmetic per structure, so
;;   it is recomputed every call rather than memoised.  That is the point --
;;   status describes what is DRAWN RIGHT NOW, and a stored answer goes stale
;;   the moment a pass is drawn.  Call it once per pass over one shared pend.
(defun pfa:status-for (anchor passname pend xform / xs eps status p)
  (setq xs     (pfa:pass-xs anchor passname)
        eps    (max *pfa-recon-eps*
                    (* 1.5 (pf:text-height (pf:xf-hplot xform))))
        status '())
  (foreach p pend
    (setq status
          (append status
                  (list (pfa:labeled-x-p
                          (pf:station->profile-x (car p) xform) xs eps)))))
  (list status (pfa:orphan-xs pend xs eps xform)))

;; (pfa:gather-compute anchor passname primary lines inlets)
;;   -> (pend status orphans) | nil        nil = the primary line never loaded
;;
;;   THE ONE GATHER-COMPUTE, shared by PFLABEL and PFINVERT.  Both commands ask
;;   the identical question -- which structures are on this line, and which
;;   already carry a label from THIS pass -- and the only thing that varied
;;   between the two copies was the pass name, which was already a parameter.
;;   `.pro` never entered here: PFINVERT's profile work is downstream, in the
;;   engine (pfi:invert-bracket / pf:pro-verts), not in the gather.
;;
;;   The dialog FILLS stay local to each command, because tile names belong to
;;   their own DCL dialog.  Only the dialog-blind part is shared -- so this is
;;   callable from a modeless palette handler too (pure reads throughout).
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
      ;; BETWEEN passes, so a stored flag would always read clean one command
      ;; after it stopped being true.  The live view owns "correct right now";
      ;; this is its command-line half, and it sits with the other
      ;; warn-loudly-let-the-user-decide findings.
      (if (setq orphans (caddr res))
        (progn
          (setq stas (mapcar '(lambda (v)
                                (pf:fmt-station (pf:profile-x->station v xf)))
                             orphans))
          ;; Advisory, and the palette renders the same fact in detailsList's
          ;; Drift row -- so under *pf-quiet* it is a DUPLICATE, not a loss.
          ;; On the command line (flag nil) it prints exactly as before.
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
;;   THE per-target roll-up the palette's Commands tab reads.  Worked out on
;;   read and never stored, for the same reason pfa:status-roll is: nothing
;;   would update a saved summary when one of the records beneath it moved.
;;
;;   ONE pend walk serves BOTH label passes -- that is what pfa:pend-for exists
;;   for.  Crossings come off the ledger, which is why they are nearly free.
;;
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
                work   (pfa:xing-list anchor)
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
;;
;;   API LOADING IS PART OF THE PROLOGUE, 2026-07-29.  It used to be the first
;;   line of each command BODY, and six of the nine entry points remembered it.
;;   C:PFPVERB did not: the palette's anchor verb calls pfs:place-one directly
;;   rather than pfs:cmd, so in a session where no other PFTools command had run
;;   yet, btnAnchor prompted for scales and datum and then died on the first
;;   centerline read -- "bad function: CF:ROAD_API".  It read as working because
;;   testing a palette button almost always follows a command-line run that has
;;   already scloaded eworks.  Same class as audit #9: what EVERY entry point
;;   needs belongs to the ONE wrapper, not to the discipline of whoever writes
;;   the next command.  scload is idempotent and catch-wrapped, so repeat calls
;;   cost nothing, and it sits AFTER echo-off so the load chatter is suppressed.
(defun pf:run-command (name flush work)
  (setq *pf-run-prev-error* *error*
        *pf-run-name*       name
        *pf-run-flush*      flush
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


;;; ==========================================================================
;;; SECTION 8  --  C:PFINDEX  (build / verify / report the membership index)
;;; ==========================================================================
;;; Nothing in normal use walks every structure -- the engine top-up only
;;; refreshes what it labeled -- so a drawing that has never been indexed, or
;;; one where a line was just added, needs this.  The cold build is ALLOWED to
;;; be slow: run one pays, run two onward is nearly free.
;;;
;;; VERIFY is the point of the whole command.  Every acceptance test for this
;;; feature is "same labels, faster", and nothing else compares the two answers.
;;; This does: read the saved record AND do the arithmetic the old way, then
;;; name the disagreements.  It is the only thing that turns a quiet wrong
;;; answer into a visible one.

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

;; (pfindex:cmd) -> nil   The command body, run under pf:run-command.
;;   BORROWS *pfs-undo-open* deliberately.  pf:group-open-p checks a FIXED list
;;   of five flags, so a sixth of its own would be invisible to pf:run-error and
;;   an Esc mid-Build would leak an open undo group.  PFINDEX and PFSETUP cannot
;;   run at once, so sharing the flag is the safe option, not the lazy one.
(defun pfindex:cmd ( / lines inlets roster act res scan bad)
  (setq *pfs-undo-open* nil)
  (initget "Build Verify Report")
  (setq act (getkword "\nPFINDEX [Build/Verify/Report] <Report>: "))
  (if (null act) (setq act "Report"))
  (prompt "\nReading the registry...")
  (setq lines  (pfa:index-lines)
        inlets (pfa:gather-inlets)
        roster (pfa:roster-stamp lines (= act "Build")))
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
     (pf:undo-begin '*pfs-undo-open*)
     (setq res (pfa:index-build lines inlets roster))
     (pf:undo-end '*pfs-undo-open*)
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
  (princ))

(defun c:PFINDEX ()
  (pf:run-command "PFINDEX" nil 'pfindex:cmd))


(princ "\npfanchor.lsp loaded (V4 record + registry).  Commands: PFREMOVE, PFINDEX.")
(princ)
;;; ==========================================================================
;;; end of pfanchor.lsp
;;; ==========================================================================
