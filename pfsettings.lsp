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
    (cons "sta_suf" "[util] LINE '[line]'")
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
;;   NATIVE first: Carlson's usrdir$ (its program-settings/temp folder).  Falls
;;   back to LOCALAPPDATA, then TEMP, so it works with or without Carlson.
(defun pfset:dir ( / base dir)
  (setq base (cond ((and (boundp 'usrdir$) (= (type usrdir$) 'STR)
                         (/= usrdir$ "")) usrdir$)
                   ((getenv "LOCALAPPDATA"))
                   ((getenv "TEMP"))
                   (T "")))
  (setq dir (strcat (vl-string-right-trim "\\/" base) "\\PFTools"))
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
;;   session directory is empty the native project data root (tmpdir$) seeds it.
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

;;; ---- Project data root: NATIVE (Carlson tmpdir$) --------------------------
;;; Carlson binds tmpdir$ to the active project data folder, so the root is
;;; read live -- no per-drawing NOD record, no PFROOT command.  When tmpdir$
;;; is unbound/empty (no active project) a one-shot browse seeds a SESSION
;;; fallback (pfset:root-set), which lasts until the drawing is closed.

(if (not (boundp '*pfset-root-fallback*)) (setq *pfset-root-fallback* nil))

;; (pfset:dir-norm d) -> d with exactly one trailing backslash
(defun pfset:dir-norm (d)
  (if (member (substr d (strlen d) 1) '("\\" "/")) d (strcat d "\\")))

;; (pfset:tmpdir) -> Carlson's current project data folder | nil
(defun pfset:tmpdir ()
  (if (and (boundp 'tmpdir$) (= (type tmpdir$) 'STR) (/= tmpdir$ ""))
    (pfset:dir-norm tmpdir$)))

;; (pfset:root-get) -> project data root | nil    tmpdir$ first, then the
;;   session browse-fallback.  No NOD read -- the drawing stores no root.
(defun pfset:root-get ()
  (cond ((pfset:tmpdir))
        ((and *pfset-root-fallback* (/= *pfset-root-fallback* ""))
         *pfset-root-fallback*)
        (T nil)))

;; (pfset:root-set path) -> nil   session fallback only (no persistence)
(defun pfset:root-set (path)
  (setq *pfset-root-fallback* (if path (pfset:dir-norm path) nil))
  (princ))

;; (pfset:find-std-dir start subfolder) -> existing dir (trailing \) | nil
;;   Walks UP from start (0..*pfset-std-search-depth* parent levels) testing
;;   start+subfolder at each; returns the first that exists.  Self-calibrating:
;;   works whether tmpdir$ is the base project, a data subfolder, or deeper.
(defun pfset:find-std-dir (start subfolder / base lvl cand hit)
  (setq base (vl-string-right-trim "\\/" start) lvl 0 hit nil)
  (while (and (null hit) (<= lvl *pfset-std-search-depth*) base (/= base ""))
    (setq cand (strcat base "\\" subfolder))
    (if (vl-file-directory-p cand)
      (setq hit (strcat cand "\\"))
      (setq base (vl-filename-directory base) lvl (1+ lvl))))
  hit)

;; (pfset:get-company-dir fileType) -> routed directory path | nil
;;   Firm-standard subfolder under the native root (searched up), else the
;;   session's last-used dir for that type, else the root itself.
(defun pfset:get-company-dir (fileType / ft root sub std cached)
  (setq ft   (strcase fileType t)
        root (pfset:root-get)
        sub  (cdr (assoc ft *pfset-std-subfolders*))
        std  (if (and root sub) (pfset:find-std-dir root sub))
        cached (cond ((= ft "cl")  *pfset-dir-cl*)
                     ((= ft "pro") *pfset-dir-pro*)
                     ((= ft "tin") *pfset-dir-tin*)
                     (T nil)))
  (cond
    (std std)
    ((and cached (vl-file-directory-p (vl-string-right-trim "\\/" cached)))
     cached)
    ((and root (vl-file-directory-p (vl-string-right-trim "\\/" root)))
     root)
    (T nil)))

;; (pfset:native-scale sym) -> formatted scale string | nil
;;   Reads a Carlson scale global (sv:sm = horizontal, sv:vs = vertical) to
;;   SEED the setup dialog's plot-scale fields.  nil when unbound/nonpositive
;;   so the caller falls back to the last-used setting; the field stays fully
;;   editable, so a wrong native read costs one keystroke, never correctness.
(defun pfset:native-scale (sym / v)
  (if (and (boundp sym) (numberp (setq v (eval sym))) (> v 0.0))
    (rtos v 2 2)))


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

;; (pfset:load-dcl) -> dcl_id | nil   (loud on failure)
(defun pfset:load-dcl ( / id)
  (setq id (load_dialog (pfset:dcl-file)))
  (if (< id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    id))

;; (pfset:help text) -> nil   (the Help button everywhere)
(defun pfset:help (text) (alert text) (princ))

;; (pfset:pad s w) -> s space-padded to at least w characters
;;   Column formatting for the list_box "grids" (header text row + rows).
(defun pfset:pad (s w)
  (if (null s) (setq s ""))
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; (pfset:confirm title lines) -> T | nil
;;   The shared Yes/No dialog (pf_confirm).  No is the default AND the Esc
;;   path -- Yes is always a deliberate click.  `lines` = up to 4 strings.
;;   Falls back to a command-line keyword only if the .dcl cannot load.
(defun pfset:confirm (title lines / dcl_id res i k)
  (setq res nil)
  (if (setq dcl_id (pfset:load-dcl))
    (progn
      (if (new_dialog "pf_confirm" dcl_id)
        (progn
          (set_tile "c_title" title)
          (setq i 1)
          (foreach k '("c_l1" "c_l2" "c_l3" "c_l4")
            (set_tile k (if (nth (1- i) lines) (nth (1- i) lines) ""))
            (setq i (1+ i)))
          (action_tile "yes" "(setq res T) (done_dialog 1)")
          (action_tile "no"  "(done_dialog 0)")
          (start_dialog)))
      (unload_dialog dcl_id))
    (progn                                  ; last-resort fallback
      (initget "Yes No")
      (setq res (= (getkword (strcat "\n" title " [Yes/No] <No>: ")) "Yes"))))
  res)

;; (pfset:pick-index title items presel) -> 0-based index | nil
;;   Self-loading single-select list dialog (pf_pick).  Returns nil on
;;   Cancel.  presel = 0-based index | nil.
(defun pfset:pick-index (title items presel / dcl_id res)
  (setq res nil)
  (if (and items (setq dcl_id (pfset:load-dcl)))
    (progn
      (if (new_dialog "pf_pick" dcl_id)
        (progn
          (set_tile "pick_title" title)
          (start_list "items")
          (foreach it items (add_list it))
          (end_list)
          (set_tile "items" (itoa (if presel presel 0)))
          (action_tile "items"
            "(setq res (atoi (get_tile \"items\"))) (if (= $reason 4) (done_dialog 1))")
          (action_tile "accept"
            "(setq res (atoi (get_tile \"items\"))) (done_dialog 1)")
          (action_tile "cancel" "(setq res nil) (done_dialog 0)")
          (if (/= 1 (start_dialog)) (setq res nil))))
      (unload_dialog dcl_id)))
  res)

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


(princ "\npfsettings.lsp loaded (user state).  Project root: native (tmpdir$).")
(princ)
;;; ==========================================================================
;;; end of pfsettings.lsp
;;; ==========================================================================
