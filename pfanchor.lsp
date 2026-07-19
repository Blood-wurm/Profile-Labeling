;;; ==========================================================================
;;; pfanchor.lsp  --  PFTools V4 record + registry
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg.lsp, pftools-lib.lsp, pfdraw.lsp loaded first.
;;;
;;; V4 MODEL: the anchor IS the grid record; crossings are one field among
;;; many.  PFSETUP creates the record; every other command reads/updates it.
;;;
;;;   STUB     AUTO registration writes identity-only stubs to the DRAWING
;;;            dictionary (NOD "PFTOOLS", keys STUB_<TYPE>_<NAME>): profile
;;;            exists, maps to its .cl (+ auto-resolved .pro pair), NO
;;;            placement.  A stub cannot be an anchor -- an anchor IS a
;;;            placement.  USER registration (PFSETUP or on-the-fly from a
;;;            label command) promotes stub -> anchor and deletes the stub.
;;;            Identity alone is enough to DISCOVER; placement is required
;;;            only to DRAW.
;;;
;;;   ANCHOR   One PF-GRIDANCHOR block per PLACED profile, keyed LINE+UTIL.
;;;            Insertion point = grid lower-left (datum + lower-left =
;;;            transform origin).  EXTENTS ARE RELATIVE (locked): X-scale =
;;;            width to the top-right pick, Y-scale = height to it.  Never
;;;            an absolute corner -- a window-move carries both corners.
;;;            The stored top means "top at max station" ONLY; per-station
;;;            top-Y comes from the top-of-grid probe (pf:top-at), because
;;;            grid tops STEP.
;;;            Attributes = LINE / UTIL / STA0 / DATUM / HPLOT / VPLOT.
;;;
;;;   LEDGER   Extension dictionary "PFXLEDGER" hard-owned by the anchor.
;;;            Schema 3 records (all optional except META):
;;;              "META"     (70 schema)(1 .cl path)(300 table handle)
;;;                         (301 .cl content checksum)(302 self-handle:
;;;                         the anchor's OWN handle at creation, stored as a
;;;                         plain string so a COPY -- which gets a new handle
;;;                         but clones this value -- is detectable, see
;;;                         pfa:copy-p.  A handle-typed field would be
;;;                         translated by the clone and defeat detection.)
;;;              "FILES"    (1 INV .pro)(2 TOP .pro)(3 existing .tin)
;;;                         (4 DESIGN .tin)(5 pipe material)
;;;                         (300 INV cksum)(301 TOP cksum)
;;;              "STATUS"   (70 state: 0 unchecked 1 passing 2 failing
;;;                         3 stale)(1 timestamp) + repeated (300 finding)
;;;              "SCOPE"    (1 timestamp) + repeated (300 candidate file)
;;;                         -- crossing-discovery scope
;;;              "PASS_*"   one per labeling pass: (1 timestamp)(8 resolved
;;;                         layer)(70 clayer-flag) + repeated (300 handle)
;;;                         -- the erase-by-handle ledger.  CLAYER passes
;;;                         record timestamp + layer but NO handles.
;;;              "X_*"      one per crossing, CONTENT-KEYED (unchanged from
;;;                         v3): key X_<SBASE>_<round(tsta*100)>, data
;;;                         (1 sfile)(2 sbase)(10 xy)(40 tsta)(41 ssta)
;;;                         (42 telev)(43 selev)
;;;
;;;   DERIVED  Labeled/outstanding is NEVER stored -- re-read from the
;;;            drawing on every touch (see SECTION 5).
;;;
;;; SAFETY CONTRACT (unchanged from v3):
;;;   - Reads are pure.  Writes happen only inside caller-opened undo groups.
;;;   - NO layer-scoped erases.  Erase happens BY HANDLE only.
;;;   - All state hangs off the anchor block; erase the anchor and the
;;;     ledger dies with it (hard owner).
;;;   - No reactors, no background execution.
;;;
;;; CAVEATS: do NOT run ATTSYNC / BATTMAN on PF-GRIDANCHOR (attribute
;;; positions are placed absolutely).  Negative stations are not supported
;;; by the crossing content key.
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

;; (pfa:ensure-anchor-block) -> nil   (defines PF-GRIDANCHOR once per dwg)
;;   UNIT L: spine (0,0)->(0,1) + base (0,0)->(1,0).  The insert's X-scale
;;   is the grid WIDTH and Y-scale the height to the top-right pick, so the
;;   spine overlays the left border and the base overlays the datum line.
;;   No top line in the definition -- tops STEP, a scaled flat top would lie.
(defun pfa:ensure-anchor-block ( / y)
  (if (null (tblsearch "BLOCK" *pfa-block-name*))
    (progn
      (entmake (list '(0 . "BLOCK") (cons 2 *pfa-block-name*)
                     '(70 . 2) '(10 0.0 0.0 0.0)))
      (entmake '((0 . "LINE") (8 . "0") (10 0.0 0.0 0.0) (11 0.0 1.0 0.0)))
      (entmake '((0 . "LINE") (8 . "0") (10 0.0 0.0 0.0) (11 1.0 0.0 0.0)))
      (setq y -1.0)
      (foreach tag *pfa-att-tags*
        (entmake (list '(0 . "ATTDEF") '(8 . "0")
                       (list 10 2.0 y 0.0)
                       (cons 40 *pfa-att-height*)
                       '(1 . "") (cons 3 tag) (cons 2 tag)
                       '(70 . 8)))
        (setq y (- y 1.5)))
      (entmake '((0 . "ENDBLK") (8 . "0")))
      (prompt (strcat "\nDefined block '" *pfa-block-name* "'.")))))

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
  (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 *pfa-block-name*)))
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
  (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 *pfa-block-name*)))
        i 0 out '())
  (if ss
    (while (< i (sslength ss))
      (setq out (cons (ssname ss i) out) i (1+ i))))
  (reverse out))

;; (pfa:anchor->xform anchor) -> xform ALIST | nil
;;   Core geometry from geometry + attributes; record keys (clfile, pro-*,
;;   tin-*, name, type) merged in from the ledger when present.
;;   'topy is NOMINAL -- top at max station.  Per-station top comes from
;;   pf:top-at, never from here.  'rightx derives from the X-scale (the
;;   relative top-right); absent on a legacy anchor (X-scale 1.0).
;;   nil when the core numbers are unreadable.
(defun pfa:anchor->xform (anchor / ed ins xs ys at sta0 datum hp vp xf meta
                          files)
  (setq ed  (entget anchor)
        ins (cdr (assoc 10 ed))
        xs  (cdr (assoc 41 ed))
        ys  (cdr (assoc 42 ed))
        at  (pfa:read-attribs anchor)
        sta0  (distof (pfa:att "STA0"  at) 2)
        datum (distof (pfa:att "DATUM" at) 2)
        hp    (distof (pfa:att "HPLOT" at) 2)
        vp    (distof (pfa:att "VPLOT" at) 2))
  (if (and ins ys sta0 datum hp vp
           (> hp 0.0) (> vp 0.0) (> ys 0.0))
    (progn
      (setq xf (pf:make-xform (car ins) sta0
                              (+ (cadr ins) ys) (cadr ins)
                              datum (/ hp vp) hp vp))
      (setq xf (pf:xf-put 'name (pfa:att "LINE" at) xf)
            xf (pf:xf-put 'type (pfa:att "UTIL" at) xf))
      (if (and xs (> xs 2.0))                    ; legacy anchors carry 1.0
        (setq xf (pf:xf-put 'rightx (+ (car ins) xs) xf)))
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
;;   xform must carry 'rightx (the top-right pick X) -- extents are stored
;;   RELATIVE: X-scale = width, Y-scale = height.  Caller must hold an open
;;   undo group.
(defun pfa:write-anchor (line util xform tfile / ins wid hgt vals y i anchor)
  (pfd:ensure-layer *pfa-layer* T)
  (pfa:ensure-anchor-block)
  (setq ins (list (pf:xf-leftx xform) (pf:xf-basey xform) 0.0)
        wid (if (pf:xf-get 'rightx xform)
              (- (pf:xf-get 'rightx xform) (pf:xf-leftx xform))
              1.0)
        hgt (- (pf:grid-top-y xform) (pf:xf-basey xform)))
  (entmake (list '(0 . "INSERT") (cons 8 *pfa-layer*)
                 (cons 2 *pfa-block-name*) (cons 10 ins)
                 (cons 41 wid) (cons 42 hgt) '(43 . 1.0)
                 '(50 . 0.0) '(66 . 1)))
  (setq vals (list (strcase line) (strcase util)
                   (rtos (pf:xf-sta0 xform) 2 6)
                   (rtos (pf:xf-datum xform) 2 6)
                   (rtos (pf:xf-hplot xform) 2 6)
                   (rtos (/ (pf:xf-hplot xform) (pf:xf-vscale xform)) 2 6))
        y    (- (cadr ins) (* *pfa-att-height* *pfa-att-gap*))
        i    0)
  (foreach tag *pfa-att-tags*
    (entmake (list '(0 . "ATTRIB") (cons 8 *pfa-layer*)
                   (cons 10 (list (car ins) y 0.0))
                   (cons 40 *pfa-att-height*)
                   (cons 1 (nth i vals))
                   (cons 2 tag)
                   '(70 . 8)))
    (setq y (- y (* *pfa-att-height* *pfa-att-gap*))
          i (1+ i)))
  (entmake (list '(0 . "SEQEND") (cons 8 *pfa-layer*)))
  (setq anchor (entlast))
  (pfa:meta-put anchor tfile "")
  (pfa:stamp-self anchor)                 ; copy-detection baseline
  (prompt (strcat "\nRegistered grid anchor: " (strcase util)
                  " '" (strcase line) "'."))
  anchor)

;; (pfa:reanchor anchor xform) -> anchor   (update in place; ledger survives)
(defun pfa:reanchor (anchor xform / ed ins wid hgt vals e sed tag i y)
  (setq ins (list (pf:xf-leftx xform) (pf:xf-basey xform) 0.0)
        wid (if (pf:xf-get 'rightx xform)
              (- (pf:xf-get 'rightx xform) (pf:xf-leftx xform))
              (cdr (assoc 41 (entget anchor))))
        hgt (- (pf:grid-top-y xform) (pf:xf-basey xform))
        ed  (entget anchor)
        ed  (subst (cons 10 ins) (assoc 10 ed) ed)
        ed  (subst (cons 41 wid) (assoc 41 ed) ed)
        ed  (subst (cons 42 hgt) (assoc 42 ed) ed))
  (entmod ed)
  (setq vals (list nil nil                        ; LINE/UTIL untouched
                   (rtos (pf:xf-sta0 xform) 2 6)
                   (rtos (pf:xf-datum xform) 2 6)
                   (rtos (pf:xf-hplot xform) 2 6)
                   (rtos (/ (pf:xf-hplot xform) (pf:xf-vscale xform)) 2 6))
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
        (entmod sed)))
    (setq y (- y (* *pfa-att-height* *pfa-att-gap*))
          e (entnext e)))
  (entupd anchor)
  (prompt "\nGrid anchor updated in place (ledger preserved).")
  anchor)

;; (pfa:probe-corner pt) -> T | nil
;;   T when a grid LINE passes within tol of pt, or when the drawing has no
;;   grid-layer LINEs at all (nothing to assert against).  The PF-GRID-*
;;   layers are Carlson's own grid layers (confirmed 2026-07-17).
(defun pfa:probe-corner (pt / ss i ed ok)
  (setq ss (ssget "_X" (list '(0 . "LINE") (cons 8 *pfa-grid-layers*))))
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
(defun pfa:corner-check (anchor / ed ins xs ys hp out x top)
  (setq ed  (entget anchor)
        ins (cdr (assoc 10 ed))
        xs  (cdr (assoc 41 ed))
        ys  (cdr (assoc 42 ed))
        hp  (distof (pfa:att "HPLOT" (pfa:read-attribs anchor)) 2)
        out '())
  (if (null hp) (setq hp *pf-ref-hplot*))
  (if (not (pfa:probe-corner ins))
    (setq out (cons "no grid LINE at the anchor corner (grid moved without its anchor?)"
                    out)))
  (if (and xs (> xs 2.0) ys)
    (progn
      (setq x   (- (+ (car ins) xs) 0.1)         ; just inside the right edge
            top (pf:top-at x (cadr ins)
                           (+ (cadr ins) ys
                              (* *pfg-top-margin* (pf:scale-factor hp)))
                           (pf:top-lines)))
      (cond
        ((null top)
         (setq out (cons "no PF-GRID-MJR top found at the right edge" out)))
        ((> (abs (- top (+ (cadr ins) ys))) *pfa-top-tol*)
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

;;; ---- META: (70 schema)(1 .cl path)(300 table handle)(301 .cl checksum) ---
;;; nil for any arg preserves the stored value.

(defun pfa:meta-get (anchor) (pfa:rec-get anchor "META"))

(defun pfa:meta-put (anchor tfile thandle tcksum / dict old self)
  (setq dict (pfa:ledger-dict anchor T)
        old  (pfa:xrec-data dict "META"))
  (if (null tfile)
    (setq tfile (if (assoc 1 old) (cdr (assoc 1 old)) "")))
  (if (null thandle)
    (setq thandle (if (assoc 300 old) (cdr (assoc 300 old)) "")))
  (if (null tcksum)
    (setq tcksum (if (assoc 301 old) (cdr (assoc 301 old)) "")))
  (setq self (if (assoc 302 old) (cdr (assoc 302 old)) ""))  ; preserved
  (pfa:xrec-put dict "META"
                (list (cons 70 *pfa-schema-ver*)
                      (cons 1 tfile)
                      (cons 300 thandle)
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

;; (pfa:nod-dict) -> PFTOOLS drawing dictionary ename (created on demand)
(defun pfa:nod-dict ( / nod sub)
  (setq nod (namedobjdict))
  (if (setq sub (dictsearch nod *pfset-nod-name*))
    (cdr (assoc -1 sub))
    (dictadd nod *pfset-nod-name*
             (entmakex '((0 . "DICTIONARY") (100 . "AcDbDictionary")
                         (280 . 0) (281 . 1))))))

(defun pfa:stub-key (type name)
  (strcat "STUB_" (pfa:sanitize (strcase type))
          "_" (pfa:sanitize (strcase name))))

;; (pfa:stub-get type name) -> data | nil
(defun pfa:stub-get (type name)
  (pfa:xrec-data (pfa:nod-dict) (pfa:stub-key type name)))

;; (pfa:stub-put type name cl inv top) -> xrecord ename
(defun pfa:stub-put (type name cl inv top)
  (pfa:xrec-put (pfa:nod-dict) (pfa:stub-key type name)
                (list (cons 1 cl)
                      (cons 2 (strcase type))
                      (cons 3 (strcase name))
                      (cons 4 (if inv inv ""))
                      (cons 5 (if top top "")))))

(defun pfa:stub-del (type name)
  (pfa:xrec-del (pfa:nod-dict) (pfa:stub-key type name)))

;; (pfa:stub-list) -> list of (type name cl inv top)
(defun pfa:stub-list ( / dict out k d)
  (setq dict (pfa:nod-dict) out '())
  (foreach k (pfa:dict-keys dict)
    (if (= (substr k 1 5) "STUB_")
      (progn
        (setq d (pfa:xrec-data dict k))
        (setq out (cons (list (cdr (assoc 2 d)) (cdr (assoc 3 d))
                              (cdr (assoc 1 d)) (cdr (assoc 4 d))
                              (cdr (assoc 5 d)))
                        out)))))
  (reverse out))

;; (pfa:registry) -> merged sorted list of (type name state ename stub)
;;   state 'PLACED (ename set, stub nil) | 'STUB (ename nil, stub data).
;;   THE registry: anchors + stubs, sorted by "TYPE NAME".
(defun pfa:registry ( / out e at s keys k cell)
  (setq out '())
  (foreach e (pfa:all-anchors)
    (if (not (pfa:copy-p e))                 ; copies excluded (PFCHECK reports)
      (progn
        (setq at (pfa:read-attribs e))
        (setq out (cons (list (strcase (pfa:att "UTIL" at))
                              (strcase (pfa:att "LINE" at))
                              'PLACED e nil)
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
  (setq keys (acad_strlsort
               (mapcar '(lambda (r) (strcat (car r) " " (cadr r))) out)))
  (mapcar
    '(lambda (k)
       (setq cell (vl-member-if
                    '(lambda (r) (= (strcat (car r) " " (cadr r)) k))
                    out))
       (car cell))
    keys))

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
  (setq ss (ssget "_X" (list '(0 . "LWPOLYLINE") (cons 8 *pfa-xing-layer*)))
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
;;; SECTION 6  --  Crossings table  (one BLOCK per profile, BY HANDLE)
;;; ==========================================================================

(defun pfa:table-blockname (util line)
  (strcat "PF-TABLE_" (pfa:sanitize (strcase util))
          "_" (pfa:sanitize (strcase line))))

;; (pfa:rebuild-table anchor xform style skips) -> nil
;;   Renders the FULL ledger with derived status per row.  Instance replaced
;;   BY HANDLE only (user placement respected; dangles self-heal).
(defun pfa:rebuild-table (anchor xform style skips / at line util name recs
                          recon sf ht step cols total done e sk stat bdef
                          nrows y i meta thandle inst ied)
  (setq at    (pfa:read-attribs anchor)
        line  (pfa:att "LINE" at)
        util  (pfa:att "UTIL" at)
        name  (pfa:table-blockname util line)
        recs  (pfa:xing-list anchor)
        recon (pfa:recon xform recs)
        sf    (pf:xf-sf xform)
        ht    (* *pf-text-base-height* sf)
        step  (* *pfa-table-step* sf)
        cols  (mapcar '(lambda (x) (* x sf)) *pfa-table-cols*)
        total (length recs)
        done  0)
  (foreach e recs
    (if (cdr (assoc (pfa:xr-key e) recon)) (setq done (1+ done))))
  (pfd:ensure-layer *pfa-table-layer* nil)
  (setq bdef  (pfd:table-def name)
        nrows (+ total 2)
        y     (* (1- nrows) step))
  (pfd:table-row bdef y
    (list (strcat "CROSSINGS -- TARGET " (strcase util)
                  " '" (strcase line) "' -- "
                  (itoa done) " OF " (itoa total) " LABELED"
                  (if skips
                    (strcat ", " (itoa (length skips)) " SKIPPED THIS PASS")
                    "")))
    cols *pfa-table-layer* style ht)
  (setq y (- y step))
  (pfd:table-row bdef y
    (list "#" "LINE" "TGT STATION" "TGT INV ELEV"
          "SRC STA" "SRC INV ELEV" "STATUS")
    cols *pfa-table-layer* style ht)
  (setq i 0)
  (foreach e recs
    (setq i (1+ i)
          y (- y step)
          stat (cond
                 ((setq sk (assoc (pfa:xr-key e) skips))
                  (strcat "SKIPPED: " (nth 3 sk)))
                 ((cdr (assoc (pfa:xr-key e) recon)) "LABELED")
                 (T "OUTSTANDING")))
    (pfd:table-row bdef y
      (list (itoa i)
            (pfa:xr-sbase e)
            (pf:fmt-station (pfa:xr-tsta e))
            (if (pfa:xr-telev e) (rtos (pfa:xr-telev e) 2 2) "--")
            (pf:fmt-station (pfa:xr-ssta e))
            (if (pfa:xr-selev e) (rtos (pfa:xr-selev e) 2 2) "--")
            stat)
      cols *pfa-table-layer* style ht))
  ;; ---- instance: replace BY HANDLE only ----------------------------------
  (setq meta    (pfa:meta-get anchor)
        thandle (if (assoc 300 meta) (cdr (assoc 300 meta)) "")
        inst    (if (/= thandle "") (handent thandle)))
  (if (and inst (setq ied (entget inst))
           (= (cdr (assoc 0 ied)) "INSERT")
           (= (strcase (cdr (assoc 2 ied))) (strcase name)))
    (entupd inst)
    (progn
      (entmake (list '(0 . "INSERT") (cons 8 *pfa-table-layer*)
                     (cons 2 name)
                     (cons 10 (list (+ (pf:xf-leftx xform)
                                       (* *pfa-table-margin* sf))
                                    (+ (pf:grid-top-y xform)
                                       (* *pfa-table-margin* sf))
                                    0.0))
                     '(41 . 1.0) '(42 . 1.0) '(43 . 1.0) '(50 . 0.0)))
      (setq inst (entlast))
      (pfa:meta-put anchor nil (cdr (assoc 5 (entget inst))) nil)))
  (princ))


;;; ==========================================================================
;;; SECTION 7  --  Anchor picking  (shared command-line helpers)
;;; ==========================================================================

;; (pfa:anchor-title anchor) -> "STORM 'LINEA'"
(defun pfa:anchor-title (anchor / at)
  (setq at (pfa:read-attribs anchor))
  (strcat (pfa:att "UTIL" at) " '" (pfa:att "LINE" at) "'"))

;; (pfa:pick-anchor msg) -> anchor ename | nil   (nil = Enter / cancel)
;;   entsel loop that only accepts a PF-GRIDANCHOR insert.
(defun pfa:pick-anchor (msg / sel e ed done res)
  (setq done nil res nil)
  (while (not done)
    (setq sel (entsel msg))
    (cond
      ((null sel) (setq done T))                    ; Enter / miss = done
      (T
       (setq e (car sel) ed (entget e))
       (if (and (= (cdr (assoc 0 ed)) "INSERT")
                (= (strcase (cdr (assoc 2 ed))) (strcase *pfa-block-name*)))
         (setq res e done T)
         (prompt "\n  Not a PF-GRIDANCHOR -- pick the anchor block, or Enter.")))))
  res)

;; (pfa:choose-anchor) -> anchor ename | nil
;;   Numbered pick from every anchor in the drawing (for when the anchor
;;   isn't on screen).
(defun pfa:choose-anchor ( / anchors i e pick)
  (setq anchors (pfa:all-anchors))
  (cond
    ((null anchors)
     (prompt "\nNo PF-GRIDANCHOR anchors in this drawing -- run PFSETUP.")
     nil)
    ((= (length anchors) 1)
     (prompt (strcat "\nUsing the only registered profile: "
                     (pfa:anchor-title (car anchors))))
     (car anchors))
    (T
     (prompt "\nRegistered profiles:")
     (setq i 0)
     (foreach e anchors
       (setq i (1+ i))
       (prompt (strcat "\n  " (itoa i) ".  " (pfa:anchor-title e))))
     (initget 6)
     (setq pick (getint (strcat "\nProfile <1-" (itoa (length anchors)) ">: ")))
     (if (and (numberp pick) (>= pick 1) (<= pick (length anchors)))
       (nth (1- pick) anchors)
       nil))))


;;; ==========================================================================
;;; SECTION 8  --  Teardown + C:PFREMOVE
;;; ==========================================================================
;;; V4 teardown: walk every PASS_* handle ledger -> erase those entities ->
;;; erase the table instance + definition -> erase the anchor (the ledger
;;; dies with it, hard-owned).  Entities never handle-tracked (CLAYER
;;; passes, hand-drawn work) are NEVER touched.

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
(defun pfa:teardown (anchor / at nm n meta th inst blocks bdef tname)
  (setq at (pfa:read-attribs anchor) n 0)
  ;; 1. every tracked pass entity, by handle
  (foreach nm (pfa:pass-names anchor)
    (setq n (+ n (pfa:erase-pass anchor nm))))
  ;; 2. table instance (by handle) + definition
  (setq meta  (pfa:meta-get anchor)
        th    (if (assoc 300 meta) (cdr (assoc 300 meta)) "")
        inst  (if (/= th "") (handent th))
        tname (pfa:table-blockname (pfa:att "UTIL" at) (pfa:att "LINE" at)))
  (if (and inst (entget inst)) (progn (entdel inst) (setq n (1+ n))))
  (setq blocks (vla-get-blocks
                 (vla-get-activedocument (vlax-get-acad-object)))
        bdef   (vl-catch-all-apply 'vla-item (list blocks tname)))
  (if (not (vl-catch-all-error-p bdef))
    (vl-catch-all-apply 'vla-delete (list bdef)))
  ;; 3. the anchor itself -- ledger dies with it
  (entdel anchor)
  n)

(defun c:PFREMOVE ( / anchor counts n)
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
     (initget "Yes No")
     (if (= (getkword
              "\nPurge just this copied anchor block (safe)? [Yes/No] <No>: ")
            "Yes")
       (progn
         (command "_.UNDO" "_Begin")
         (pfa:purge-copy anchor)
         (command "_.UNDO" "_End")
         (prompt "\nCopied anchor purged (its cloned ledger died with it). "))
       (prompt "\nNothing removed.")))
    (T
      (setq counts (pfa:teardown-counts anchor))
      (initget "Yes No")
      (if (/= (getkword
                (strcat "\nRemove " (pfa:anchor-title anchor) " -- "
                        (itoa (car counts)) " tracked entit"
                        (if (= (car counts) 1) "y" "ies") ", "
                        (itoa (cadr counts)) " crossing(s), "
                        (itoa (caddr counts)) " pass record(s)?  "
                        "Untracked work is NOT touched. [Yes/No] <No>: "))
              "Yes")
        (prompt "\nNothing removed.")
        (progn
          (command "_.UNDO" "_Begin")
          (setq n (pfa:teardown anchor))
          (command "_.UNDO" "_End")
          (prompt (strcat "\nRemoved anchor + ledger + " (itoa n)
                          " entit" (if (= n 1) "y" "ies")
                          ".  (One U reverses it.)"))))))
  (princ))


(princ "\npfanchor.lsp loaded (V4 record + registry).  Command: PFREMOVE.")
(princ)
;;; ==========================================================================
;;; end of pfanchor.lsp
;;; ==========================================================================
