;;; ==========================================================================
;;; pfsettings.lsp  --  PFTools V4 user-state layer
;;; --------------------------------------------------------------------------
;;; Requires pftools-cfg.lsp, pftools-lib.lsp, pfanchor.lsp loaded first
;;; (the NOD helpers reuse pfanchor's generic xrecord machinery).
;;;
;;; THREE kinds of user state, three stores:
;;;   1. SETTINGS FILE  (%LOCALAPPDATA%\PFTools\pftools-settings.txt)
;;;      Plain KEY=VALUE text: label prefix/suffix strings, text layer/style,
;;;      plot-scale defaults.  Falls back to the v3 pflabel-settings.txt on
;;;      first read so nothing saved at the firm is orphaned.
;;;   2. SESSION GLOBALS  -- last-browsed directory per file type.
;;;   3. DRAWING DICTIONARY (NOD, "PFTOOLS")  -- drawing-wide state: the
;;;      project data root (set once), later the issue snapshot.
;;;
;;; Also home to the SHARED dialog helpers (list picker, name prompt,
;;; folder-scan checklist) and the layer/style lookups they feed.  Per-
;;; command dialog WIRING lives with each command, not here.
;;;
;;; This is the USER'S state.  The FIRM'S constants live in pftools-cfg.lsp.
;;; Don't let them bleed together.
;;; ==========================================================================

(vl-load-com)

;;; ==========================================================================
;;; SECTION 1  --  Defaults + keys
;;; ==========================================================================

(setq *pfset-def-settings*
  (list
    (cons "sta_pre" "STA.")
    (cons "sta_val" "X+XX.XX")
    (cons "sta_suf" "STORM LINE '[line]'")
    (cons "con_pre" "CONST.")
    (cons "con_val" "[size] [type] [ID]")
    (cons "con_suf" "")
    (cons "gl_pre"  "G.L.")
    (cons "gl_val"  "[elev]")
    (cons "gl_suf"  "")
    (cons "layer"      "STORM-TEXT_P")
    (cons "use_clayer" "0")
    (cons "style"      "L080")
    (cons "hscale"  "20.0")
    (cons "vscale"  "2.0")))

(if (not (boundp '*pfset-settings*)) (setq *pfset-settings* nil))

;; Session last-browsed directories, per file type.
(if (not (boundp '*pfset-dir-cl*))  (setq *pfset-dir-cl*  ""))
(if (not (boundp '*pfset-dir-pro*)) (setq *pfset-dir-pro* ""))
(if (not (boundp '*pfset-dir-tin*)) (setq *pfset-dir-tin* ""))
(if (not (boundp '*pfset-dir-txt*)) (setq *pfset-dir-txt* ""))


;;; ==========================================================================
;;; SECTION 2  --  Settings file I/O  (KEY=VALUE text)
;;; ==========================================================================

;; (pfset:dir) -> "...\PFTools\"   (created if missing)
(defun pfset:dir ( / base dir)
  (setq base (getenv "LOCALAPPDATA"))
  (if (or (null base) (= base "")) (setq base (getenv "TEMP")))
  (setq dir (strcat base "\\PFTools"))
  (if (not (vl-file-directory-p dir)) (vl-mkdir dir))
  (strcat dir "\\"))

(defun pfset:auto-file ()        (strcat (pfset:dir) *pfset-fname*))
(defun pfset:auto-file-legacy () (strcat (pfset:dir) *pfset-fname-legacy*))

;; (pfset:write-settings file alist) -> T | nil
(defun pfset:write-settings (file alist / f kv)
  (if (setq f (open file "w"))
    (progn
      (foreach kv alist (write-line (strcat (car kv) "=" (cdr kv)) f))
      (close f)
      T)))

;; (pfset:read-settings file) -> alist of "key" -> "value"
(defun pfset:read-settings (file / f line pos out)
  (setq out '())
  (if (and file (setq f (open file "r")))
    (progn
      (while (setq line (read-line f))
        (if (setq pos (vl-string-search "=" line))
          (setq out (cons (cons (substr line 1 pos)
                                (substr line (+ pos 2)))
                          out))))
      (close f)))
  (reverse out))

;; (pfset:merge base over) -> full alist over every key in `base`
(defun pfset:merge (base over)
  (mapcar
    '(lambda (kv)
       (cons (car kv)
             (if (assoc (car kv) over) (cdr (assoc (car kv) over)) (cdr kv))))
    base))

;; (pfset:settings) -> current settings alist
;;   Auto-loads the last-used file once; falls back to the v3 file name.
(defun pfset:settings ( / file)
  (if (null *pfset-settings*)
    (progn
      (setq file (cond ((findfile (pfset:auto-file)) (pfset:auto-file))
                       ((findfile (pfset:auto-file-legacy))
                        (pfset:auto-file-legacy))
                       (T nil)))
      (setq *pfset-settings*
            (pfset:merge *pfset-def-settings*
                         (if file (pfset:read-settings file) '())))))
  *pfset-settings*)

;; (pfset:put-setting key val) -> updated settings alist
(defun pfset:put-setting (key val / s)
  (setq s (pfset:settings))
  (setq *pfset-settings*
        (if (assoc key s)
          (subst (cons key val) (assoc key s) s)
          (append s (list (cons key val))))))

;; (pfset:save-auto) -> T | nil   (persist the in-memory settings)
(defun pfset:save-auto ()
  (pfset:write-settings (pfset:auto-file) (pfset:settings)))


;;; ==========================================================================
;;; SECTION 3  --  Browse wrappers  (per-type last-directory memory)
;;; ==========================================================================

;; (pfset:browse title dirvar ext) -> full path | nil
;;   dirvar is the QUOTED symbol of the session directory global.  When the
;;   session directory is empty the project data root (NOD) seeds it.
(defun pfset:browse (title dirvar ext / start f)
  (setq start (eval dirvar))
  (if (or (null start) (= start ""))
    (progn
      (setq start (pfset:root-get))
      (if (null start) (setq start ""))))
  (if (setq f (getfiled title start ext 0))
    (progn
      (set dirvar (strcat (vl-filename-directory f) "\\"))
      f)))


;;; ==========================================================================
;;; SECTION 4  --  Drawing dictionary (NOD)  --  drawing-wide state
;;; ==========================================================================
;;; Separate from anchors: holds what belongs to the DRAWING, not a profile.
;;; Reuses pfanchor's generic xrecord helpers on a soft-owned NOD dict.

;; (pfset:nod) -> PFTOOLS dictionary ename.  One implementation lives in
;;   pfanchor (the stub registry shares it); this is the settings-side name.
(defun pfset:nod () (pfa:nod-dict))

;; (pfset:root-get) -> project data root path | nil
(defun pfset:root-get ( / nod sub data v)
  (setq nod (namedobjdict))
  (if (setq sub (dictsearch nod *pfset-nod-name*))
    (progn
      (setq data (pfa:xrec-data (cdr (assoc -1 sub)) "ROOT")
            v    (if data (cdr (assoc 1 data))))
      (if (and v (/= v "")) v))))

;; (pfset:root-set path) -> nil
(defun pfset:root-set (path)
  (pfa:xrec-put (pfset:nod) "ROOT" (list (cons 1 path)))
  (princ))

;; C:PFROOT -- show / set the project data root for this drawing.
(defun c:PFROOT ( / cur f dir)
  (setq cur (pfset:root-get))
  (prompt (strcat "\nProject data root: " (if cur cur "<not set>")))
  (initget "Yes No")
  (if (= (getkword "\nSet it now? [Yes/No] <No>: ") "Yes")
    (progn
      (setq f (getfiled "Select ANY File in the Project Data Root Folder"
                        (if cur cur "") "" 0))
      (if f
        (progn
          (setq dir (strcat (vl-filename-directory f) "\\"))
          (pfset:root-set dir)
          (prompt (strcat "\nProject data root set: " dir)))
        (prompt "\nUnchanged."))))
  (princ))


;;; ==========================================================================
;;; SECTION 5  --  Drawing lookups for the pickers
;;; ==========================================================================

(defun pfset:layer-list ( / e nm out)
  (setq e (tblnext "LAYER" T) out '())
  (while e
    (setq nm (cdr (assoc 2 e)))
    (if (and nm (/= nm "")) (setq out (cons nm out)))
    (setq e (tblnext "LAYER")))
  (acad_strlsort (reverse out)))

(defun pfset:style-list ( / e nm out)
  (setq e (tblnext "STYLE" T) out '())
  (while e
    (setq nm (cdr (assoc 2 e)))
    (if (and nm (/= nm "")) (setq out (cons nm out)))
    (setq e (tblnext "STYLE")))
  (acad_strlsort (reverse out)))

;; (pfset:active-style) -> a usable text style name
;;   Settings choice -> firm default -> Standard -> "".
(defun pfset:active-style ( / st)
  (setq st (cdr (assoc "style" (pfset:settings))))
  (cond
    ((and st (/= st "") (tblsearch "STYLE" st)) st)
    ((tblsearch "STYLE" *pf-style-default*) *pf-style-default*)
    ((tblsearch "STYLE" "Standard") "Standard")
    (T "")))


;;; ==========================================================================
;;; SECTION 6  --  Shared nested dialogs  (pf_pick / pf_name / pf_scan)
;;; ==========================================================================

;; (pfset:dcl-file) -> path to pfdialog.dcl
(defun pfset:dcl-file ()
  (strcat *pftools-dir* "pfdialog.dcl"))

;; (pfset:pick-from-list dcl_id title items current) -> chosen string
;;   Returns `current` unchanged on Cancel or an empty list.
(defun pfset:pick-from-list (dcl_id title items current / idx res)
  (setq res current)
  (if (and items (new_dialog "pf_pick" dcl_id))
    (progn
      (set_tile "pick_title" title)
      (start_list "items")
      (foreach it items (add_list it))
      (end_list)
      (if (setq idx (pf:index-of current items)) (set_tile "items" (itoa idx)))
      (action_tile "items"   "(setq res (nth (atoi (get_tile \"items\")) items))")
      (action_tile "accept"  "(setq res (nth (atoi (get_tile \"items\")) items)) (done_dialog 1)")
      (action_tile "cancel"  "(done_dialog 0)")
      (if (/= 1 (start_dialog)) (setq res current))))
  res)

;; (pfset:ask-name dcl_id default) -> chosen string (default on Cancel/empty)
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


(princ "\npfsettings.lsp loaded (user state).  Command: PFROOT.")
(princ)
;;; ==========================================================================
;;; end of pfsettings.lsp
;;; ==========================================================================
