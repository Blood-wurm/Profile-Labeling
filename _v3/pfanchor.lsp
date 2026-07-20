;;; ==========================================================================
;;; pfanchor.lsp  --  Profile anchor + work ledger + crossings-table renderer
;;; --------------------------------------------------------------------------
;;; Requires pftools-lib.lsp loaded first.  Loads BEFORE pfdialog / pflabel /
;;; pfcross (see pftools-load.lsp).  No dialogs here -- grid picks and the
;;; grid dialog stay in pfcross/pfdialog; this module is persistence +
;;; rendering only.
;;;
;;; THE MODEL (the drawing is truth; the ledger is an index of it):
;;;
;;;   ANCHOR   One PF-GRIDANCHOR block per profile, keyed LINE + UTIL.
;;;            Insertion point = grid lower-left corner.
;;;            Insert Y-scale  = grid height  (top-Y is position-derived:
;;;            the block's unit-height spine stretches to the top border).
;;;            Attributes      = LINE / UTIL / STA0 / DATUM / HPLOT / VPLOT.
;;;
;;;   LEDGER   Extension dictionary "PFXLEDGER" hard-owned by the anchor:
;;;              "META"    (70 schema-ver)(1 target .cl path)(300 table handle)
;;;              "X_..."   one Xrecord per crossing, CONTENT-KEYED:
;;;                        key  = X_<SBASE>_<round(tsta*100)>
;;;                        data = (1 sfile)(2 sbase)(10 xy)(40 tsta)(41 ssta)
;;;                               (42 telev)(43 selev)  [42/43 absent until
;;;                               probed; preserved across re-discovery]
;;;            Erase the anchor and the ledger dies with it (hard owner).
;;;
;;;   DERIVED  Labeled/outstanding is NEVER stored.  It is re-read from the
;;;            drawing on every touch: one ssget of station lines on the
;;;            crossing layer, matched to each crossing's exact station X.
;;;
;;; SAFETY CONTRACT (every function here):
;;;   - Reads are pure.  Writes happen only inside caller-opened undo groups.
;;;   - NO layer-scoped erases.  The table is replaced BY HANDLE only;
;;;     PF-TABLE is a plain display layer and is never cleared.
;;;   - Nothing touches shared dictionaries or Carlson/AutoCAD structures;
;;;     all state hangs off the anchor block.
;;;   - No reactors, no background execution.
;;;
;;; KNOWN CAVEATS (bulletproofing pass deferred, per session notes):
;;;   - Do NOT run ATTSYNC / BATTMAN on PF-GRIDANCHOR: attribute positions
;;;     are placed absolutely by this tool; syncing to the (Y-scaled) block
;;;     definition would scatter them.  Harmless to data, ugly on screen.
;;;   - Negative stations are not supported by the content key (never occur
;;;     in current practice).
;;;   - Stretching a grid does not stretch its anchor (INSERTs move, they
;;;     don't stretch); the corner probe catches the drift and offers a
;;;     re-pick.
;;;
;;; STATUS: new module -- test on a scratch copy first.
;;; ==========================================================================

(vl-load-com)

;;; --------------------------------------------------------------------------
;;; TUNABLES  --  the honest assumptions; change here, nowhere else.
;;; --------------------------------------------------------------------------

(setq *pfa-block-name*  "PF-GRIDANCHOR")  ; anchor block definition name
(setq *pfa-layer*       "PF-ANCHOR")      ; anchor layer (created NO-PLOT)
(setq *pfa-dict-name*   "PFXLEDGER")      ; extension-dictionary name
(setq *pfa-schema-ver*  1)                ; ledger schema version (META 70)
(setq *pfa-att-tags*    '("LINE" "UTIL" "STA0" "DATUM" "HPLOT" "VPLOT"))
(setq *pfa-att-height*  0.8)              ; anchor attribute text height
(setq *pfa-att-gap*     1.6)              ; attribute line spacing, x height

;; Reconciliation: a crossing is "labeled" when a station line on the
;; crossing layer stands at its exact station X with its top vertex on this
;; grid's top border.  eps covers float round-trip only -- the X math is
;; deterministic (registration round-trips through the anchor, so draw-time
;; and recon-time xforms are identical).
(setq *pfa-xing-layer*  "PF-XING")        ; shared with pfcross draw code
(setq *pfa-recon-eps*   1.0e-4)

;; Content-key drift: a re-discovered crossing from the same source whose
;; refined target station moved within this tolerance is the SAME crossing
;; (elevations preserved, key renamed).  Bounded by the PFXFIND sample step.
(setq *pfa-key-tol*     2.0)

;; Anchor sanity probe: a grid LINE must pass within this distance of the
;; anchor's insertion point, else the grid likely moved without its anchor.
;; If the drawing has NO entities on these layers, the probe cannot assert
;; anything and passes silently.
(setq *pfa-probe-tol*   0.05)
(setq *pfa-grid-layers* "PF-GRID-MJR,PF-GRID-MNR,PF-HBOX")

;; Crossings table -- rendered as ONE BLOCK per profile, replaced by handle.
(setq *pfa-table-layer*  "PF-TABLE")      ; display layer only; NEVER cleared
(setq *pfa-table-margin* 2.0)             ; offset from grid top-left (base)
(setq *pfa-table-step*   3.20)            ; row spacing (base scalar)
(setq *pfa-table-cols*   '(0.0 8.0 32.0 68.0 96.0 120.0 148.0))
        ; #  LINE  TGT STATION  TGT INV ELEV  SRC STA  SRC INV ELEV  STATUS


;;; ==========================================================================
;;; SECTION 1  --  Pure helpers
;;; ==========================================================================

;; xform accessors beyond the lib's seven (8th element = horizontal plot
;; scale, appended by the grid-capture code; drives the sf scale factor).
(defun pfa:xf-hplot (xf) (nth 7 xf))
(defun pfa:xf-sf    (xf) (/ (pfa:xf-hplot xf) 20.0))

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

;; (pfa:ensure-layer name noplot) -> nil   (creates the layer if missing)
(defun pfa:ensure-layer (name noplot)
  (if (null (tblsearch "LAYER" name))
    (progn
      (entmake (append
                 (list '(0 . "LAYER")
                       '(100 . "AcDbSymbolTableRecord")
                       '(100 . "AcDbLayerTableRecord")
                       (cons 2 name)
                       '(70 . 0)
                       '(62 . 7)
                       (cons 6 "Continuous"))
                 (if noplot '((290 . 0)) '())))
      (prompt (strcat "\nCreated layer '" name "'"
                      (if noplot " (no-plot)." "."))))))

;;; --------------------------------------------------------------------------
;;; Working-entry accessors.  Every crossing moves through the toolset as a
;;; 10-list:  (key tfile tbase sfile sbase xy tsta ssta telev selev)
;;; key is a pure function of sbase+tsta, so pending (unpersisted) entries
;;; carry real keys too.
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
;;   Unit-height spine (0,0)->(0,1) + end ticks: the insert's Y-scale
;;   stretches the spine to the grid height, so the anchor visually overlays
;;   the left grid border and the top-Y is readable from geometry alone.
(defun pfa:ensure-anchor-block ( / y)
  (if (null (tblsearch "BLOCK" *pfa-block-name*))
    (progn
      (entmake (list '(0 . "BLOCK") (cons 2 *pfa-block-name*)
                     '(70 . 2) '(10 0.0 0.0 0.0)))
      (entmake '((0 . "LINE") (8 . "0") (10 0.0 0.0 0.0) (11 0.0 1.0 0.0)))
      (entmake '((0 . "LINE") (8 . "0") (10 -1.0 0.0 0.0) (11 1.0 0.0 0.0)))
      (entmake '((0 . "LINE") (8 . "0") (10 -1.0 1.0 0.0) (11 1.0 1.0 0.0)))
      ;; ATTDEF placement is nominal -- ATTRIBs are entmade at absolute
      ;; positions by pfa:write-anchor.  (Do NOT run ATTSYNC on these.)
      (setq y -1.0)
      (foreach tag *pfa-att-tags*
        (entmake (list '(0 . "ATTDEF") '(8 . "0")
                       (list 10 2.0 y 0.0)
                       (cons 40 *pfa-att-height*)
                       '(1 . "") (cons 3 tag) (cons 2 tag)
                       '(70 . 8)))              ; preset: never prompts
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
               (= (strcase (pfa:att "UTIL" at)) (strcase util)))
        (setq res e))
      (setq i (1+ i))))
  res)

;; (pfa:anchor->xform anchor) -> 8-element xform | nil
;;   (left-x sta0 hscale top-y base-y datum v-scale hplot)
;;   corner + top-Y come from geometry (insertion point + Y-scale);
;;   the four numbers come from attributes.  nil when anything is unreadable.
(defun pfa:anchor->xform (anchor / ed ins ys at sta0 datum hp vp)
  (setq ed  (entget anchor)
        ins (cdr (assoc 10 ed))
        ys  (cdr (assoc 42 ed))
        at  (pfa:read-attribs anchor)
        sta0  (distof (pfa:att "STA0"  at) 2)
        datum (distof (pfa:att "DATUM" at) 2)
        hp    (distof (pfa:att "HPLOT" at) 2)
        vp    (distof (pfa:att "VPLOT" at) 2))
  (if (and ins ys sta0 datum hp vp
           (> hp 0.0) (> vp 0.0) (> ys 0.0))
    (list (car ins) sta0 *pf-hscale-fixed*
          (+ (cadr ins) ys) (cadr ins) datum
          (/ hp vp) hp)))

;; (pfa:write-anchor line util xform tfile) -> anchor ename
;;   entmakes the INSERT + six ATTRIBs + SEQEND, then seeds META.
;;   Caller must hold an open undo group.
(defun pfa:write-anchor (line util xform tfile / ins hgt vals y i anchor)
  (pfa:ensure-layer *pfa-layer* T)
  (pfa:ensure-anchor-block)
  (setq ins (list (pf:xf-leftx xform) (pf:xf-basey xform) 0.0)
        hgt (- (pf:grid-top-y xform) (pf:xf-basey xform)))
  (entmake (list '(0 . "INSERT") (cons 8 *pfa-layer*)
                 (cons 2 *pfa-block-name*) (cons 10 ins)
                 '(41 . 1.0) (cons 42 hgt) '(43 . 1.0)
                 '(50 . 0.0) '(66 . 1)))
  (setq vals (list (strcase line) (strcase util)
                   (rtos (pf:xf-sta0 xform) 2 6)
                   (rtos (pf:xf-datum xform) 2 6)
                   (rtos (pfa:xf-hplot xform) 2 6)
                   (rtos (/ (pfa:xf-hplot xform) (pf:xf-vscale xform)) 2 6))
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
  (prompt (strcat "\nRegistered grid anchor: " (strcase util)
                  " '" (strcase line) "'."))
  anchor)

;; (pfa:reanchor anchor xform) -> anchor   (update in place; ledger survives)
;;   Moves the insert, resets the Y-scale, refreshes the four numeric
;;   attributes.  Identity (LINE/UTIL) never changes.
(defun pfa:reanchor (anchor xform / ed ins hgt vals e sed tag i y)
  (setq ins (list (pf:xf-leftx xform) (pf:xf-basey xform) 0.0)
        hgt (- (pf:grid-top-y xform) (pf:xf-basey xform))
        ed  (entget anchor)
        ed  (subst (cons 10 ins) (assoc 10 ed) ed)
        ed  (subst (cons 42 hgt) (assoc 42 ed) ed))
  (entmod ed)
  (setq vals (list nil nil                        ; LINE/UTIL untouched
                   (rtos (pf:xf-sta0 xform) 2 6)
                   (rtos (pf:xf-datum xform) 2 6)
                   (rtos (pfa:xf-hplot xform) 2 6)
                   (rtos (/ (pfa:xf-hplot xform) (pf:xf-vscale xform)) 2 6))
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
;;   T when a grid LINE passes within *pfa-probe-tol* of pt, or when the
;;   drawing has no grid-layer LINEs at all (nothing to assert against).
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


;;; ==========================================================================
;;; SECTION 3  --  Ledger  (extension dictionary + Xrecords)
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
;;   The dictionary is HARD-OWNED (280 . 1): erasing the anchor erases the
;;   ledger and every record in it.
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

;; (pfa:xrec-put dict key data) -> xrecord ename
;;   Create-or-replace.  The replaced xrecord is entdel'd so nothing is
;;   left ownerless in the database.
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

;;; --------------------------------------------------------------------------
;;; META  --  (70 schema-ver)(1 target .cl path)(300 table-block handle)
;;; The handle is stored as a STRING (group 300) and resolved via handent:
;;; predictable dangle detection in plain AutoLISP, no pointer semantics.
;;; --------------------------------------------------------------------------

(defun pfa:meta-get (anchor / dict)
  (if (setq dict (pfa:ledger-dict anchor nil))
    (pfa:xrec-data dict "META")))

;; (pfa:meta-put anchor tfile thandle)  --  nil for either arg preserves the
;;   stored value, so callers can update one field without knowing the other.
(defun pfa:meta-put (anchor tfile thandle / dict old)
  (setq dict (pfa:ledger-dict anchor T)
        old  (pfa:xrec-data dict "META"))
  (if (null tfile)
    (setq tfile (if (assoc 1 old) (cdr (assoc 1 old)) "")))
  (if (null thandle)
    (setq thandle (if (assoc 300 old) (cdr (assoc 300 old)) "")))
  (pfa:xrec-put dict "META"
                (list (cons 70 *pfa-schema-ver*)
                      (cons 1 tfile)
                      (cons 300 thandle))))

;;; --------------------------------------------------------------------------
;;; Crossing records
;;; --------------------------------------------------------------------------

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
;;   Merge one working entry into the ledger.  Geometry (stations, XY) is
;;   refreshed from the incoming entry; ELEVATIONS ALREADY ON RECORD ARE
;;   PRESERVED.  Key drift (refined station moved within *pfa-key-tol* for
;;   the same source) renames the record instead of duplicating it.
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
;;   nil for either elevation PRESERVES the stored value (a failed target
;;   probe never erases a previously read invert).
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


;;; ==========================================================================
;;; SECTION 4  --  Reconciliation  (read-only; ONE scan per call)
;;; ==========================================================================

;; (pfa:station-line-xs xform) -> list of X for crossing station lines whose
;;   top vertex sits on THIS grid's top border.  One ssget, database-wide,
;;   display-independent.
(defun pfa:station-line-xs (xform / topy ss i ed p hit out)
  (setq topy (pf:grid-top-y xform)
        ss   (ssget "_X" (list '(0 . "LWPOLYLINE")
                               (cons 8 *pfa-xing-layer*)))
        out  '()
        i    0)
  (if ss
    (while (< i (sslength ss))
      (setq ed (entget (ssname ss i)) hit nil)
      (foreach p ed
        (if (and (= (car p) 10) (null hit)
                 (<= (abs (- (cadr (cdr p)) topy)) *pfa-recon-eps*))
          (setq hit (car (cdr p)))))
      (if hit (setq out (cons hit out)))
      (setq i (1+ i))))
  out)

;; (pfa:x-labeled-p x xs) -> T | nil
(defun pfa:x-labeled-p (x xs / found)
  (setq found nil)
  (foreach v xs
    (if (<= (abs (- v x)) *pfa-recon-eps*) (setq found T)))
  found)

;; (pfa:recon xform work) -> alist (key . labeled?)   -- one scan total
(defun pfa:recon (xform work / xs out e x)
  (setq xs (pfa:station-line-xs xform) out '())
  (foreach e work
    (setq x (pf:station->profile-x (pfa:xr-tsta e) xform))
    (setq out (cons (cons (pfa:xr-key e) (pfa:x-labeled-p x xs)) out)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 5  --  Crossings table  (one BLOCK per profile, replaced by
;;;                HANDLE -- no layer-scoped erase exists in this toolset)
;;; ==========================================================================

(defun pfa:table-blockname (util line)
  (strcat "PF-TABLE_" (pfa:sanitize (strcase util))
          "_" (pfa:sanitize (strcase line))))

;; (pfa:table-def name) -> vla block-definition, emptied and ready to refill
;;   ActiveX empty-and-refill: deterministic in-place redefinition (existing
;;   instances keep their user-chosen position and show the new contents).
(defun pfa:table-def (name / blocks bdef objs o)
  (setq blocks (vla-get-blocks
                 (vla-get-activedocument (vlax-get-acad-object)))
        bdef   (vl-catch-all-apply 'vla-item (list blocks name)))
  (if (vl-catch-all-error-p bdef)
    (setq bdef (vla-add blocks (vlax-3d-point '(0.0 0.0 0.0)) name))
    (progn
      (setq objs '())
      (vlax-for o bdef (setq objs (cons o objs)))
      (foreach o objs (vl-catch-all-apply 'vla-delete (list o)))))
  bdef)

(defun pfa:table-text (bdef pt str layer style ht / o)
  (setq o (vla-addtext bdef str
                       (vlax-3d-point (list (car pt) (cadr pt) 0.0))
                       ht))
  (vla-put-layer o layer)
  (if (tblsearch "STYLE" style) (vla-put-stylename o style))
  o)

(defun pfa:table-row (bdef y cells cols layer style ht / i c)
  (setq i 0)
  (foreach c cells
    (if (and c (/= c ""))
      (pfa:table-text bdef (list (nth i cols) y) c layer style ht))
    (setq i (1+ i))))

;; (pfa:rebuild-table anchor xform style skips) -> nil
;;   Renders the FULL ledger with derived status per row:
;;     LABELED / OUTSTANDING / SKIPPED: <reason>   (skips are pass-transient:
;;   list of (key sbase tsta reason); next pass re-derives fresh).
;;   Instance handling: META handle -> handent -> live INSERT of the right
;;   block -> entupd (user placement respected).  Dangling or absent ->
;;   fresh instance at the grid top-left + margin, handle recorded.
(defun pfa:rebuild-table (anchor xform style skips / at line util name recs
                          recon sf ht step cols total done e sk stat bdef
                          nrows y i meta thandle inst ied)
  (setq at    (pfa:read-attribs anchor)
        line  (pfa:att "LINE" at)
        util  (pfa:att "UTIL" at)
        name  (pfa:table-blockname util line)
        recs  (pfa:xing-list anchor)
        recon (pfa:recon xform recs)
        sf    (pfa:xf-sf xform)
        ht    (* 1.60 sf)
        step  (* *pfa-table-step* sf)
        cols  (mapcar '(lambda (x) (* x sf)) *pfa-table-cols*)
        total (length recs)
        done  0)
  (foreach e recs
    (if (cdr (assoc (pfa:xr-key e) recon)) (setq done (1+ done))))
  (pfa:ensure-layer *pfa-table-layer* nil)
  (setq bdef  (pfa:table-def name)
        nrows (+ total 2)
        y     (* (1- nrows) step))
  (pfa:table-row bdef y
    (list (strcat "CROSSINGS -- TARGET " (strcase util)
                  " '" (strcase line) "' -- "
                  (itoa done) " OF " (itoa total) " LABELED"
                  (if skips
                    (strcat ", " (itoa (length skips)) " SKIPPED THIS PASS")
                    "")))
    cols *pfa-table-layer* style ht)
  (setq y (- y step))
  (pfa:table-row bdef y
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
    (pfa:table-row bdef y
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
    (entupd inst)                         ; live: show the new definition
    (progn                                ; first run / dangling: fresh one
      (entmake (list '(0 . "INSERT") (cons 8 *pfa-table-layer*)
                     (cons 2 name)
                     (cons 10 (list (+ (pf:xf-leftx xform)
                                       (* *pfa-table-margin* sf))
                                    (+ (pf:grid-top-y xform)
                                       (* *pfa-table-margin* sf))
                                    0.0))
                     '(41 . 1.0) '(42 . 1.0) '(43 . 1.0) '(50 . 0.0)))
      (setq inst (entlast))
      (pfa:meta-put anchor nil (cdr (assoc 5 (entget inst))))))
  (princ))


;;; ==========================================================================
;;; SECTION 6  --  C:PFXPURGE   (enumerable, removable footprint)
;;; ==========================================================================
;;; Erases a profile's anchor (its ledger dies with it, hard-owned) and its
;;; table instance + definition.  LABELS ARE NEVER TOUCHED -- purge removes
;;; tool STATE, not drawn output.  One undo group; one U reverses it.

(defun pfa:all-anchors ( / ss i out)
  (setq ss (ssget "_X" (list '(0 . "INSERT") (cons 2 *pfa-block-name*)))
        i 0 out '())
  (if ss
    (while (< i (sslength ss))
      (setq out (cons (ssname ss i) out) i (1+ i))))
  (reverse out))

(defun c:PFXPURGE ( / anchors i e at n pick picks nm meta th inst blocks bdef)
  (setq anchors (pfa:all-anchors))
  (if (null anchors)
    (prompt "\nNo PF-GRIDANCHOR anchors in this drawing.")
    (progn
      (prompt "\nRegistered profiles:")
      (setq i 0)
      (foreach e anchors
        (setq i (1+ i) at (pfa:read-attribs e))
        (prompt (strcat "\n  " (itoa i) ".  " (pfa:att "UTIL" at)
                        " '" (pfa:att "LINE" at) "'")))
      (setq n (length anchors))
      (initget 6 "All")
      (setq pick (getint (strcat "\nPurge which profile [All] <1-"
                                 (itoa n) ">: ")))
      (cond
        ((null pick) (prompt "\nNothing purged."))
        ((and (/= pick "All") (or (not (numberp pick)) (> pick n)))
         (prompt "\nInvalid pick -- nothing purged."))
        (T
         (setq picks (if (= pick "All")
                       anchors
                       (list (nth (1- pick) anchors))))
         (initget "Yes No")
         (if (/= (getkword
                   (strcat "\nErase " (itoa (length picks))
                           " anchor(s) + ledger(s) + table block(s)?  "
                           "Drawn labels are NOT touched. [Yes/No] <No>: "))
                 "Yes")
           (prompt "\nNothing purged.")
           (progn
             (command "_.UNDO" "_Begin")
             (foreach e picks
               (setq at   (pfa:read-attribs e)
                     nm   (pfa:table-blockname (pfa:att "UTIL" at)
                                               (pfa:att "LINE" at))
                     meta (pfa:meta-get e)
                     th   (if (assoc 300 meta) (cdr (assoc 300 meta)) "")
                     inst (if (/= th "") (handent th)))
               (if (and inst (entget inst)) (entdel inst))
               (entdel e)                 ; ledger dies with the anchor
               (setq blocks (vla-get-blocks
                              (vla-get-activedocument (vlax-get-acad-object)))
                     bdef   (vl-catch-all-apply 'vla-item (list blocks nm)))
               (if (not (vl-catch-all-error-p bdef))
                 (vl-catch-all-apply 'vla-delete (list bdef)))
               (prompt (strcat "\n  Purged " (pfa:att "UTIL" at)
                               " '" (pfa:att "LINE" at) "'."))
             )
             (command "_.UNDO" "_End")
             (prompt "\nDone.  (One U reverses the purge.)")
           )
         )
        )
      )
    )
  )
  (princ)
)


(princ "\npfanchor.lsp loaded (anchors + ledger + table).  Command: PFXPURGE.")
(princ)
;;; ==========================================================================
;;; end of pfanchor.lsp
;;; ==========================================================================
