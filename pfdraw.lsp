;;; ==========================================================================
;;; pfdraw.lsp  --  PFTools v4 drawing boundary  (the ONLY file that entmakes
;;;                 label output)
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg.lsp + pftools-lib.lsp loaded first.
;;;
;;; DEPENDENCY GUARDRAIL: like the lib, this file may NEVER know what an
;;; anchor is, read a record, or reference a dialog.  Callers hand it fully
;;; resolved values (layer, style, height); it draws and returns enames so
;;; the caller can ledger the handles.
;;;
;;; Every function returns the ename(s) it created (nil on entmake failure)
;;; -- handle capture is the caller's job, and it is what makes the v4
;;; erase-by-handle contract possible.  NO function here erases anything.
;;; ==========================================================================

(vl-load-com)

;; (pfd:ensure-layer name noplot) -> nil   (creates the layer if missing)
(defun pfd:ensure-layer (name noplot)
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

;; (pfd:label-pipe x y file size mat sf ht style) -> list of enames
;;   Row 1 (lower) = NN" MATERIAL, row 2 (upper) = the standard line label.
;;   mat is the SOURCE profile's material (resolved by the caller; may be "").
(defun pfd:label-pipe (x y file size mat sf ht style / la dx dy gap e ents)
  (setq la   (pf:text-layer file)
        dx   (* *pfx-text-dx* sf)
        dy   (* *pfx-row1-dy* sf)
        gap  (* *pfx-row-gap* sf)
        ents '())
  (pfd:ensure-layer la nil)
  (if size
    (progn
      (setq e (pfd:text (list (+ x dx) (+ y dy) 0.0)
                        (pf:size-rowtext size mat) la style ht 0.0 'ML))
      (if e (setq ents (cons e ents)))))
  (setq e (pfd:text (list (+ x dx) (+ y dy gap) 0.0)
                    (pf:std-label file) la style ht 0.0 'ML))
  (if e (setq ents (cons e ents)))
  ents)

;;; --------------------------------------------------------------------------
;;; Table-block primitives  (used by pfanchor's table renderer)
;;; --------------------------------------------------------------------------

;; (pfd:table-def name) -> vla block-definition, emptied and ready to refill
(defun pfd:table-def (name / blocks bdef objs o)
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

(defun pfd:table-text (bdef pt str layer style ht / o)
  (setq o (vla-addtext bdef str
                       (vlax-3d-point (list (car pt) (cadr pt) 0.0))
                       ht))
  (vla-put-layer o layer)
  (if (tblsearch "STYLE" style) (vla-put-stylename o style))
  o)

(defun pfd:table-row (bdef y cells cols layer style ht / i c)
  (setq i 0)
  (foreach c cells
    (if (and c (/= c ""))
      (pfd:table-text bdef (list (nth i cols) y) c layer style ht))
    (setq i (1+ i))))


(princ "\npfdraw.lsp loaded (drawing boundary).")
(princ)
;;; ==========================================================================
;;; end of pfdraw.lsp
;;; ==========================================================================
