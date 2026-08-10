;;; ==========================================================================
;;; _attic.lsp  --  QUARANTINED CODE.  NOT IN THE LOAD ORDER.  NEVER LOADED.
;;; ==========================================================================
;;; Dead defuns moved here 2026-08-01 per the DATA-FLOW audit (§5): this tree
;;; is not under version control, so deletion is unrecoverable -- quarantine
;;; is the standing rule (Jake, 2026-07-31).  Each entry keeps its original
;;; comment plus a one-line note on where it lived and why it left.
;;; The static gates skip this folder (pfcheck.sh excludes /_attic/).
;;; To revive one: move the defun back to its module, re-run pf-verify.

;;; ---- from pfanchor.lsp ---------------------------------------------------

;; pfa:xr-tfile / pfa:xr-tbase -- crossing-entry accessors (nth 1 / nth 2).
;; WHY HERE: X_* records store the SOURCE file/base only; the target fields
;; are dropped at merge, so these two slots are never populated.
(defun pfa:xr-tfile (e) (nth 1 e))
(defun pfa:xr-tbase (e) (nth 2 e))

;; (pfa:twin-cksum clfile) -> .cl checksum stored at match time | nil
;;   Lets the witness step detect a twin recorded against an older .cl.
;;   Pure read.
;; WHY HERE: the "witness step" it was written for was never built; the
;; TWIN_* group-300 checksum has no reader (DATA-FLOW §4.0 home #3).
(defun pfa:twin-cksum (clfile / dict d)
  (if (and (setq dict (pfa:nod-dict nil))
           (setq d (pfa:xrec-data dict (pfa:twin-key clfile))))
    (cdr (assoc 300 d))))

;;; ---- from pfsettings.lsp -------------------------------------------------

;; (pfset:nod create) -> PFTOOLS dictionary ename | nil.
;; WHY HERE: one-line passthrough to pfa:nod-dict with no caller -- every
;; reader already calls pfa:nod-dict directly.
(defun pfset:nod (create) (pfa:nod-dict create))

;; (pfset:ask-name dcl_id default) -> chosen string (default on Cancel/empty)
;; WHY HERE: no .lsp caller and no .dcl reaches it by name (the gate scans
;; .dcl/.odcl too); its pf_name dialog went unused.
(defun pfset:ask-name (dcl_id default / res)
  (setq res default)
  (if (new_dialog "pf_name" dcl_id)
    (progn
      (set_tile "name" default)
      (action_tile "accept" "(setq res (get_tile \"name\")) (done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")
      (if (/= 1 (start_dialog)) (setq res default))))
  (if (= res "") default res))

;; (pfset:scan-dialog dcl_id files presel) -> list of selected indices | nil
;;   Multi-select checklist over `files`.  presel = 0-based index | nil.
;; WHY HERE: same as pfset:ask-name -- no caller, pf_scan dialog unused.
(defun pfset:scan-dialog (dcl_id files presel / sel res)
  (if (new_dialog "pf_scan" dcl_id)
    (progn
      (start_list "scan_list")
      (foreach f files (add_list f))
      (end_list)
      (if presel (set_tile "scan_list" (itoa presel)))
      (action_tile "accept" "(setq sel (get_tile \"scan_list\")) (done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")
      (setq res (start_dialog))
      (if (and (= res 1) sel (/= sel ""))
        (read (strcat "(" sel ")"))))))

;;; ---- from pftools-lib.lsp ------------------------------------------------
;;; WHY HERE (all of them): generic utilities with no caller anywhere in the
;;; suite -- pftools-lib is the engine, not a toolbox.  NOT quarantined with
;;; them: pf:text-layer / pf:align-layer (kept in-module as the documented
;;; revert path to per-type layers) and pf:tin-load/-unload/-z (Version 5.1
;;; Track B consumer named).

;; pf:pro-range RETURNED to pftools-lib 2026-08-06 -- pf:pro-outside-p needs a
;; station range in the Road API's domain, which the .pro file's own vertex
;; stations are not.  Quarantining it is what left that gate reaching for the
;; vertex list, where it dropped legitimate crossings on any line whose .pro
;; does not start at its .cl's start station.

;; (pf:remove-nth idx lst) -> lst with element idx dropped
(defun pf:remove-nth (idx lst / i out)
  (setq i 0 out '())
  (foreach x lst
    (if (/= i idx) (setq out (cons x out)))
    (setq i (1+ i)))
  (reverse out))

;; Alias kept for the dialog code's vocabulary.  (The dialog never called it.)
(defun pf:parse-line-name (file) (pf:name-of file))

;; (pf:name-prefix name) -> leading alpha prefix of a block name
(defun pf:name-prefix (name / i c out)
  (setq i 1 out "")
  (while (and (<= i (strlen name))
              (setq c (substr name i 1))
              (/= c "_")
              (/= c "-")
              (not (pf:digit-p c)))
    (setq out (strcat out c) i (1+ i)))
  out)

;; (pf:fmt-elev elev prec) -> elevation string
(defun pf:fmt-elev (elev prec) (rtos elev 2 prec))

;; (pf:get-verts clfile) -> list of (x y) vertices | nil
;;   Geometry source order, best first: .cl sampling -> drawn polyline
;;   (chords!) -> endpoint chord (loud warnings on the fallbacks).
(defun pf:get-verts (clfile / pts rng entry verts ends)
  (cond
    ((setq pts (pf:sample-cl clfile)) pts)
    ((setq rng (pf:cl-range clfile))
     (setq entry (pf:attach-corridor
                   (list clfile (pf:basename clfile) (car rng) (cadr rng)))
           verts (nth 4 entry))
     (if (and verts (> (length verts) 1))
       (progn
         (prompt (strcat "\n  Warning: .cl sampling failed for "
                         (pf:basename clfile)
                         " -- using drawn polyline vertices (arcs read as chords)."))
         (mapcar 'pf:pt2 verts))
       (if (setq ends (pf:cl-endpoints clfile))
         (progn
           (prompt (strcat "\n  Warning: using straight endpoint CHORD for "
                           (pf:basename clfile)
                           " -- crossings on curves may be missed or false."))
           (list (pf:pt2 (car ends)) (pf:pt2 (cadr ends)))))))))

;; (pf:bbox e) -> (minx miny maxx maxy) | nil
(defun pf:bbox (e / o mn mx r)
  (setq o (vlax-ename->vla-object e))
  (setq r (vl-catch-all-apply 'vla-getboundingbox (list o 'mn 'mx)))
  (if (not (vl-catch-all-error-p r))
    (progn
      (setq mn (vlax-safearray->list mn)
            mx (vlax-safearray->list mx))
      (list (car mn) (cadr mn) (car mx) (cadr mx)))))

;; (pf:text-pos ed) -> insertion point honoring justification
(defun pf:text-pos (ed / j1 j2)
  (setq j1 (cdr (assoc 72 ed))
        j2 (cdr (assoc 73 ed)))
  (if (and (assoc 11 ed)
           (or (and j1 (/= j1 0)) (and j2 (/= j2 0))))
    (cdr (assoc 11 ed))
    (cdr (assoc 10 ed))))

;; (pf:ss->list ss) -> list of enames
(defun pf:ss->list (ss / i out)
  (setq out '() i 0)
  (if ss
    (while (< i (sslength ss))
      (setq out (cons (ssname ss i) out) i (1+ i))))
  (reverse out))

;; (pf:on-layer-p e la) -> T when e sits on layer la
;; WHY HERE: cascade -- its only caller was pf:filter-layer, below.
(defun pf:on-layer-p (e la)
  (= (strcase (cdr (assoc 8 (entget e)))) (strcase la)))

;; (pf:filter-layer ents la) -> ents on layer la
(defun pf:filter-layer (ents la)
  (vl-remove-if-not '(lambda (e) (pf:on-layer-p e la)) ents))

;; (pf:sample-cl clfile) -> list of (x y) | nil   (true alignment, arcs followed)
;; WHY HERE: cascade -- only caller was pf:get-verts (pf:sample-range is the
;; live sampler on the gather path).
(defun pf:sample-cl (clfile / rng sta0 stan sta pts r)
  (if (setq rng (pf:cl-range clfile))
    (progn
      (setq sta0 (car rng) stan (cadr rng) sta sta0 pts '())
      (while (< sta stan)
        (setq r (vl-catch-all-apply *pf-road-fn*
                  (list "cl_location_at_sta" clfile sta)))
        (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
          (setq pts (cons (pf:pt2 (car r)) pts)))
        (setq sta (+ sta *pfx-sample-step*)))
      (setq r (vl-catch-all-apply *pf-road-fn*
                (list "cl_location_at_sta" clfile stan)))
      (if (and (not (vl-catch-all-error-p r)) (listp r) (listp (car r)))
        (setq pts (cons (pf:pt2 (car r)) pts)))
      (if (> (length pts) 1) (reverse pts)))))

;; (pf:find-cl-polyline p0 pn tol) -> verts | nil
;; WHY HERE: cascade -- only caller was pf:attach-corridor, below.
;; pf:match-twin-ename is the live equivalent (returns the ename instead).
(defun pf:find-cl-polyline (p0 pn tol / ss i e vs verts a b)
  (setq ss (ssget "_X" '((0 . "LWPOLYLINE,LINE,POLYLINE") (410 . "Model"))) i 0)
  (if ss
    (while (and (< i (sslength ss)) (null verts))
      (setq e  (ssname ss i)
            vs (pf:poly-verts e))
      (if (and vs (> (length vs) 1))
        (progn
          (setq a (car vs) b (last vs))
          (if (or (and (pf:pt2d-near a p0 tol) (pf:pt2d-near b pn tol))
                  (and (pf:pt2d-near a pn tol) (pf:pt2d-near b p0 tol)))
            (setq verts vs))))
      (setq i (1+ i))))
  verts)

;; (pf:attach-corridor entry) -> (clfile name start end verts)
;; WHY HERE: cascade -- only caller was pf:get-verts (pfa:build-lines matches
;; drawn twins through pfa:twin-get / pf:match-twin-ename instead).
(defun pf:attach-corridor (entry / ends verts)
  (if (setq ends (pf:cl-endpoints (car entry)))
    (setq verts (pf:find-cl-polyline (car ends) (cadr ends) *pf-corridor*)))
  (append entry (list verts)))

(princ "\n_attic.lsp is quarantine -- it should never be loaded.")
(princ)
