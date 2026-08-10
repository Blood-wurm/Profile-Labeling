;;; ==========================================================================
;;; pfdraw.lsp  --  PFTools drawing boundary (the ONLY file that entmakes
;;;                 label output)
;;; Load position 3 of 10: after pftools-lib, before pfanchor.
;;; Contract, API, and invariants: see README.md beside this file.
;;; ==========================================================================

(vl-load-com)

;; (pfd:ensure-layer-c name noplot color) -> nil   (creates the layer if missing)
;;   CREATE-ONLY: an existing layer is never recoloured, so a drawing where
;;   someone set this layer by hand keeps that colour.  COLOR therefore only
;;   reaches a drawing that has never carried the layer.
(defun pfd:ensure-layer-c (name noplot color)
  (if (null (tblsearch "LAYER" name))
    (progn
      (entmake (append
                 (list '(0 . "LAYER")
                       '(100 . "AcDbSymbolTableRecord")
                       '(100 . "AcDbLayerTableRecord")
                       (cons 2 name)
                       '(70 . 0)
                       (cons 62 color)
                       (cons 6 "Continuous"))
                 (if noplot '((290 . 0)) '())))
      (prompt (strcat "\nCreated layer '" name "'"
                      (if noplot " (no-plot)." "."))))))

;; (pfd:ensure-layer name noplot) -> nil   (creates the layer if missing, colour 7)
(defun pfd:ensure-layer (name noplot)
  (pfd:ensure-layer-c name noplot 7))

;; (pfd:anno-layer) -> "PF-ANNO"   ensures the layer, then names it
;;   THE annotation layer for every label pass -- callers ask for it, they do
;;   not build a layer name.  Create-only, per pfd:ensure-layer-c.
(defun pfd:anno-layer ()
  (pfd:ensure-layer-c *pf-anno-layer* T *pf-anno-layer-color*)
  *pf-anno-layer*)

;; (pfd:style-or-fallback style) -> a style that exists in this drawing
(defun pfd:style-or-fallback (style)
  (cond
    ((and style (/= style "") (tblsearch "STYLE" style)) style)
    ((tblsearch "STYLE" *pf-style-default*)
     (prompt (strcat "\n  Warning: style '" (if style style "")
                     "' not found -- using " *pf-style-default* "."))
     *pf-style-default*)
    ((tblsearch "STYLE" "Standard")
     (prompt (strcat "\n  Warning: style '" (if style style "")
                     "' not found -- using Standard."))
     "Standard")
    (T "")))

;; (pfd:text pt str layer style ht rot just) -> ename | nil
;;   just: 'ML = middle-left (the label-stack default)
;;         'MR = middle-right (rot pi/2: alignment point at the string END,
;;               so the text hangs BELOW the anchor -- see handoff 6.6)
(defun pfd:text (pt str layer style ht rot just / j1)
  (setq style (pfd:style-or-fallback style)
        j1    (if (eq just 'MR) 2 0))
  (entmakex
    (list '(0 . "TEXT") (cons 8 layer) (cons 7 style)
          (cons 10 pt) (cons 11 pt) (cons 40 ht)
          (cons 1 str) (cons 50 rot) (cons 72 j1) (cons 73 2))))

;; (pfd:draw-label-stack line-x base-y rows layer style ht offset gapn just)
;;   -> (line-top . enames)
;;   Columns straddle the station line at line-x (row 1 left, rows 2+ right);
;;   all share base-y, reading upward.  line-top = base-y + length of row 1
;;   with any trailing " =" stripped.
(defun pfd:draw-label-stack (line-x base-y rows layer style ht offset gapn just
                             / x i rot line-top e ents str)
  (setq i 0 rot (/ pi 2.0) line-top base-y ents '())
  (foreach str rows
    (setq x (if (= i 0)
              (- line-x offset)
              (+ line-x offset (* (1- i) gapn))))
    (setq e (pfd:text (list x base-y 0.0) str layer style ht rot just))
    (if e
      (setq ents (cons e ents))
      (prompt (strcat "\n  Warning: entmakex failed drawing text '" str "'.")))
    (if (= i 0)
      (setq line-top
            (+ base-y
               (pf:text-length (pf:strip-trailing-eq str) style ht))))
    (setq i (1+ i)))
  (cons line-top ents))

;; (pfd:station-line x ybot ytop layer) -> ename | nil
(defun pfd:station-line (x ybot ytop layer)
  (entmakex
    (list '(0 . "LWPOLYLINE") '(100 . "AcDbEntity") (cons 8 layer)
          '(100 . "AcDbPolyline") '(90 . 2) '(70 . 0)
          (cons 10 (list x ybot)) (cons 10 (list x ytop)))))

;; (pfd:circle pt r layer) -> ename | nil
(defun pfd:circle (pt r layer)
  (entmakex
    (list '(0 . "CIRCLE") (cons 8 layer)
          (cons 10 (list (car pt) (cadr pt) 0.0)) (cons 40 r))))

;; (pfd:insert-pipe pt size layer yscale sf) -> ename | nil
;;   size nil or block undefined -> placeholder circle (with a warning).
(defun pfd:insert-pipe (pt size layer yscale sf / bname)
  (cond
    ((null size)
     (pfd:circle pt (* *pfx-circle-radius* sf) layer))
    ((null (tblsearch "BLOCK" (setq bname (pf:size-blockname size))))
     (prompt (strcat "\n  Warning: block '" bname
                     "' not defined in this drawing -- circle placeholder."))
     (pfd:circle pt (* *pfx-circle-radius* sf) layer))
    (T
     (entmakex
       (list '(0 . "INSERT") (cons 8 layer) (cons 2 bname)
             (cons 10 (list (car pt) (cadr pt) 0.0))
             (cons 41 1.0) (cons 42 yscale) (cons 43 1.0)
             (cons 50 0.0))))))

;; (pfd:label-pipe x ycen file size mat sf ht style) -> list of enames
;;   Row 1 (lower) = NN" MATERIAL, row 2 (upper) = the standard line label.
;;   ycen is the PIPE CENTRE, not the invert: the two rows straddle it by half
;;   the row gap, so their midpoint lands on the centre of the block.  The gap
;;   is plotted units (sf only) while the block grows with the vertical
;;   exaggeration -- a large pipe at a high vscale swallows both rows.
;;   mat is the SOURCE profile's material (resolved by the caller; may be "").
(defun pfd:label-pipe (x ycen file size mat sf ht style / la dx half e ents)
  (setq la   (pfd:anno-layer)
        dx   (* *pfx-text-dx* sf)
        half (/ (* *pfx-row-gap* sf) 2.0)
        ents '())
  (if size
    (progn
      (setq e (pfd:text (list (+ x dx) (- ycen half) 0.0)
                        (pf:size-rowtext size mat (pf:type-of file))
                        la style ht 0.0 'ML))
      (if e (setq ents (cons e ents)))))
  (setq e (pfd:text (list (+ x dx) (+ ycen half) 0.0)
                    (pf:std-label file) la style ht 0.0 'ML))
  (if e (setq ents (cons e ents)))
  ents)

(princ "\npfdraw.lsp loaded (drawing boundary).")
(princ)
;;; ==========================================================================
;;; end of pfdraw.lsp
;;; ==========================================================================
