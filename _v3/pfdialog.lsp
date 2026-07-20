;;; ==========================================================================
;;; pfdialog.lsp  --  PFLABEL dialog wiring  (main settings + grid dialogs)
;;; --------------------------------------------------------------------------
;;; Paired with pfdialog.dcl.  Pure AutoLISP + DCL, no .NET / VBA.
;;;
;;; Loaded alongside the engine + command.  Verifiable on its own (command
;;; PFLABELSET) and called by C:PFLABEL via (pflabel:show-dialog) and
;;; (pflabel:show-grid-dialog).
;;;
;;; --------------------------------------------------------------------------
;;; INTERFACE (how pflabel.lsp reads the collected values)
;;; --------------------------------------------------------------------------
;;;   (pflabel:show-dialog)      -- main dialog; on OK commits settings +
;;;                                  transient run inputs and returns the
;;;                                  settings alist; on Cancel returns nil.
;;;   (pflabel:show-grid-dialog) -- grid-parameters dialog; on OK returns
;;;                                  (sta0 datum hplot vplot) as REALS --
;;;                                  H/V are PLOT scales (e.g. 50 and 5),
;;;                                  matching Carlson native commands --
;;;                                  persists the scales, session-remembers
;;;                                  station + datum; on Cancel returns nil.
;;;   (pflabel:settings)         -- settings alist, auto-loading last-used
;;;                                  file (merged over defaults) on first read.
;;;   (pflabel:primary-pair)     -- (path . name) for the PRIMARY centerline
;;;                                  | nil                          (transient)
;;;   (pflabel:cl-pairs)         -- list of (path . name) for the SECONDARY
;;;                                  centerlines | nil              (transient)
;;;
;;;   PERSISTED settings keys (13).  Primary / secondaries are per-run and are
;;;   deliberately NOT persisted.  There is no TIN input: PFLABEL no longer
;;;   reads a surface -- elevation rows are XXX.XX placeholders.
;;;     sta_pre sta_val sta_suf     Station-line   prefix / value / suffix
;;;     con_pre con_val con_suf     Construction   prefix / value / suffix
;;;     gl_pre  gl_val  gl_suf      Ground-line    prefix / value / suffix
;;;       The three *_val fields are display-only (engine-generated).
;;;       LIVE : sta_pre, sta_suf, con_suf, gl_suf -- they wrap engine values.
;;;              [line] in sta_suf is replaced per row with the line name.
;;;       DEAD : con_pre, gl_pre -- *pf-rule-table* (pftools-lib.lsp) now owns
;;;              the construction and elevation prefixes per block type.  The
;;;              tiles are still shown, harvested and persisted; the engine
;;;              simply ignores them (see pflabel:label-fmt).
;;;     layer                       text layer name
;;;     style                       text style name
;;;     hscale vscale               PLOT scales (edited in the GRID dialog)
;;;
;;;   SESSION-ONLY (not persisted): start station + datum elevation, kept as
;;;   the last-typed strings so re-runs on the same profile pre-fill.
;;;
;;; --------------------------------------------------------------------------
;;; SETTINGS STORAGE
;;; --------------------------------------------------------------------------
;;;   %LOCALAPPDATA%\PFTools\pflabel-settings.txt   (last-used, auto)
;;;   Plain KEY=VALUE text, one per line.  Load/Save buttons browse named .txt
;;;   files anywhere the user chooses (all 13 keys written; a loaded file's
;;;   scale keys take effect immediately since their tiles live in the grid
;;;   dialog, not this one).
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Defaults + settings keys
;;; ==========================================================================

(setq *pflabel-def-settings*
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
    (cons "layer"   "STORM-TEXT_P")
    (cons "style"   "L080")
    (cons "hscale"  "1.0")
    (cons "vscale"  "1.0")))

;; Main-dialog tile keys (populate/harvest order) -- a SUBSET of the persisted
;; keys; hscale/vscale have no tiles in the main dialog.
(setq *pflabel-keys*
  '("sta_pre" "sta_val" "sta_suf"
    "con_pre" "con_val" "con_suf"
    "gl_pre"  "gl_val"  "gl_suf"
    "layer"   "style"))

;; Persisted settings, populated on OK.  nil until first read/save.
(if (not (boundp '*pflabel-settings*)) (setq *pflabel-settings* nil))

;; Transient per-run inputs, populated on OK.  NOT persisted.
(if (not (boundp '*pflabel-primary*)) (setq *pflabel-primary* nil)) ; (path . name) | nil
(if (not (boundp '*pflabel-cl*))      (setq *pflabel-cl*      nil)) ; ((path . name) ...)

;; Session-only grid inputs (last-typed strings; NOT persisted).
(if (not (boundp '*pflabel-sta0-str*))  (setq *pflabel-sta0-str*  nil))
(if (not (boundp '*pflabel-datum-str*)) (setq *pflabel-datum-str* nil))

;; Session-only last-browsed directories per file type (getfiled reopens
;; where the user last was instead of AutoCAD's default).
(if (not (boundp '*pflabel-dir-cl*))  (setq *pflabel-dir-cl*  ""))

;; (pflabel:browse title dirvar ext) -> full path | nil
;;   getfiled wrapper that remembers the last directory per file type.
;;   dirvar is the QUOTED symbol of the session directory global.
(defun pflabel:browse (title dirvar ext / f)
  (if (setq f (getfiled title (eval dirvar) ext 0))
    (progn
      (set dirvar (strcat (vl-filename-directory f) "\\"))
      f)))


;;; ==========================================================================
;;; SECTION 2  --  Settings file I/O  (KEY=VALUE text, self-contained)
;;; ==========================================================================

;; (pflabel:settings-dir) -> "...\PFTools\"   (created if missing)
(defun pflabel:settings-dir ( / base dir)
  (setq base (getenv "LOCALAPPDATA"))
  (if (or (null base) (= base "")) (setq base (getenv "TEMP")))
  (setq dir (strcat base "\\PFTools"))
  (if (not (vl-file-directory-p dir)) (vl-mkdir dir))
  (strcat dir "\\"))

;; (pflabel:auto-file) -> full path of the auto last-used settings file
(defun pflabel:auto-file ()
  (strcat (pflabel:settings-dir) "pflabel-settings.txt"))

;; (pflabel:write-settings file alist) -> T | nil
(defun pflabel:write-settings (file alist / f)
  (if (setq f (open file "w"))
    (progn
      (foreach kv alist (write-line (strcat (car kv) "=" (cdr kv)) f))
      (close f)
      T)))

;; (pflabel:read-settings file) -> alist of "key" -> "value" (raw file contents)
(defun pflabel:read-settings (file / f line pos out)
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

;; (pflabel:merge base over) -> full alist over every key in `base`, taking
;;   `over`'s value where present.  Guarantees all keys exist and stay valid.
(defun pflabel:merge (base over)
  (mapcar
    '(lambda (kv)
       (cons (car kv)
             (if (assoc (car kv) over) (cdr (assoc (car kv) over)) (cdr kv))))
    base))

;; (pflabel:settings) -> current settings alist (auto-loads last-used once)
(defun pflabel:settings ( / file)
  (if (null *pflabel-settings*)
    (setq *pflabel-settings*
          (pflabel:merge *pflabel-def-settings*
                          (if (findfile (setq file (pflabel:auto-file)))
                            (pflabel:read-settings file)
                            '()))))
  *pflabel-settings*)

;; (pflabel:put-setting key val) -> updated settings alist
(defun pflabel:put-setting (key val / s)
  (setq s (pflabel:settings))
  (setq *pflabel-settings*
        (if (assoc key s)
          (subst (cons key val) (assoc key s) s)
          (append s (list (cons key val))))))


;;; ==========================================================================
;;; SECTION 3  --  Transient run-input accessors  (read by pflabel.lsp)
;;; ==========================================================================

(defun pflabel:primary-pair () *pflabel-primary*)
(defun pflabel:cl-pairs ()     *pflabel-cl*)


;;; ==========================================================================
;;; SECTION 4  --  Drawing lookups for the Layer / Style pickers
;;; ==========================================================================

;; (pflabel:layer-list) -> list of layer-name strings
(defun pflabel:layer-list ( / e nm out)
  (setq e (tblnext "LAYER" T) out '())
  (while e
    (setq nm (cdr (assoc 2 e)))
    (if (and nm (/= nm "")) (setq out (cons nm out)))
    (setq e (tblnext "LAYER")))
  (acad_strlsort (reverse out)))

;; (pflabel:style-list) -> list of text-style-name strings
(defun pflabel:style-list ( / e nm out)
  (setq e (tblnext "STYLE" T) out '())
  (while e
    (setq nm (cdr (assoc 2 e)))
    (if (and nm (/= nm "")) (setq out (cons nm out)))
    (setq e (tblnext "STYLE")))
  (acad_strlsort (reverse out)))


;;; ==========================================================================
;;; SECTION 5  --  Generic list picker (drives pflabel_pick)
;;; ==========================================================================

;; (pflabel:index-of item lst) -> 0-based index | nil
(defun pflabel:index-of (item lst / i found)
  (setq i 0 found nil)
  (foreach x lst
    (if (and (null found) (= x item)) (setq found i))
    (setq i (1+ i)))
  found)

;; (pflabel:pick-from-list dcl_id title items current) -> chosen string
;;   Returns `current` unchanged on Cancel or an empty list.
(defun pflabel:pick-from-list (dcl_id title items current / idx res)
  (setq res current)
  (if (and items (new_dialog "pflabel_pick" dcl_id))
    (progn
      (set_tile "pick_title" title)
      (start_list "items")
      (foreach it items (add_list it))
      (end_list)
      (if (setq idx (pflabel:index-of current items)) (set_tile "items" (itoa idx)))
      (action_tile "items"   "(setq res (nth (atoi (get_tile \"items\")) items))")
      (action_tile "accept"  "(setq res (nth (atoi (get_tile \"items\")) items)) (done_dialog 1)")
      (action_tile "cancel"  "(done_dialog 0)")
      (if (/= 1 (start_dialog)) (setq res current))))
  res)


;;; ==========================================================================
;;; SECTION 6  --  Line-name prompt (drives pflabel_name)
;;; ==========================================================================

;; (pflabel:ask-name dcl_id default) -> chosen string
;;   Returns `default` on Cancel or an empty entry.  Nested modal dialog, so
;;   no command-line getstring is needed while the main dialog is up.
(defun pflabel:ask-name (dcl_id default / res)
  (setq res default)
  (if (new_dialog "pflabel_name" dcl_id)
    (progn
      (set_tile "name" default)
      (action_tile "accept" "(setq res (get_tile \"name\")) (done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")
      (if (/= 1 (start_dialog)) (setq res default))))
  (if (= res "") default res))


;;; ==========================================================================
;;; SECTION 7  --  CL list model + rendering
;;; ==========================================================================

;; (pflabel:parse-line-name file) -> line name parsed from the filename
;;   "Type_Name.cl" -> "NAME" (everything after the FIRST underscore, upper-
;;   cased, dashes and all: Sanitary_BEi-NashvilleInterceptor -> 
;;   BEI-NASHVILLEINTERCEPTOR).  No underscore -> the full basename.
(defun pflabel:parse-line-name (file / base pos)
  (setq base (vl-filename-base file))
  (if (setq pos (vl-string-search "_" base))
    (strcase (substr base (+ pos 2)))
    (strcase base)))

;; (pflabel:cl-display pair) -> "NAME  (basename.cl)"
(defun pflabel:cl-display (pair / f nm)
  (setq f (car pair) nm (cdr pair))
  (strcat nm "  (" (vl-filename-base f) (vl-filename-extension f) ")"))

;; (pflabel:fill-cl-list pairs) -> nil   (repaints the cl_list tile)
(defun pflabel:fill-cl-list (pairs)
  (start_list "cl_list")
  (foreach p pairs (add_list (pflabel:cl-display p)))
  (end_list)
  (princ))

;; (pflabel:remove-nth idx lst) -> lst with element idx dropped
(defun pflabel:remove-nth (idx lst / i out)
  (setq i 0 out '())
  (foreach x lst
    (if (/= i idx) (setq out (cons x out)))
    (setq i (1+ i)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 8  --  Tile population / harvesting
;;; ==========================================================================

(defun pflabel:populate-tiles (settings)
  (foreach k *pflabel-keys* (set_tile k (cdr (assoc k settings)))))

(defun pflabel:harvest-tiles ()
  (mapcar '(lambda (k) (cons k (get_tile k))) *pflabel-keys*))


;;; ==========================================================================
;;; SECTION 9  --  Named Load / Save actions (fired from within the dialog)
;;; ==========================================================================

;; Save writes ALL persisted keys: main-dialog tiles as currently shown,
;; merged over the stored settings (which carry the grid-dialog scales).
(defun pflabel:on-save ( / f cur)
  (setq cur (pflabel:merge (pflabel:settings) (pflabel:harvest-tiles)))
  (if (setq f (getfiled "Save PFLABEL Settings" (pflabel:settings-dir) "txt" 1))
    (progn (pflabel:write-settings f cur)
           (prompt (strcat "\nSaved settings to " f)))))

;; Load repaints the main-dialog tiles; scale keys (no tiles here) are applied
;; to the stored settings immediately so the grid dialog picks them up.
(defun pflabel:on-load ( / f loaded)
  (if (setq f (getfiled "Load PFLABEL Settings" (pflabel:settings-dir) "txt" 0))
    (progn
      (setq loaded (pflabel:merge *pflabel-def-settings* (pflabel:read-settings f)))
      (pflabel:populate-tiles loaded)
      (pflabel:put-setting "hscale" (cdr (assoc "hscale" loaded)))
      (pflabel:put-setting "vscale" (cdr (assoc "vscale" loaded)))
      (prompt (strcat "\nLoaded settings from " f)))))


;;; ==========================================================================
;;; SECTION 10  --  Centerline actions (fired from within the dialog)
;;; ==========================================================================
;;; These mutate `cllist` / `primsel`, the live models held by show-dialog and
;;; reachable here via AutoLISP dynamic scope while start_dialog runs.

;; Primary Select: browse one .cl, ask its line name, set the primary slot.
(defun pflabel:on-primary-pick (dcl_id / f base nm)
  (if (setq f (pflabel:browse "Select Primary Centerline (.CL) File"
                              '*pflabel-dir-cl* "cl"))
    (progn
      (setq base (pflabel:parse-line-name f))
      (setq nm   (strcase (pflabel:ask-name dcl_id base)))
      (setq primsel (cons f nm))
      (set_tile "primary_file" (pflabel:cl-display primsel)))))

;; (pflabel:scan-dialog dcl_id files presel) -> list of selected indices | nil
;;   Multi-select checklist over `files` (display names).  presel is the
;;   0-based index to preselect, or nil.  Nested modal, same pattern as
;;   pflabel_pick.  Returns nil on Cancel.
(defun pflabel:scan-dialog (dcl_id files presel / sel res)
  (if (new_dialog "pflabel_clscan" dcl_id)
    (progn
      (start_list "scan_list")
      (foreach f files (add_list f))
      (end_list)
      (if presel (set_tile "scan_list" (itoa presel)))
      (action_tile "accept" "(setq sel (get_tile \"scan_list\")) (done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")
      (setq res (start_dialog))
      (if (and (= res 1) sel (/= sel ""))
        ;; get_tile on a multi-select list returns space-delimited indices
        (read (strcat "(" sel ")")))))) 

;; Secondary Add...: browse to ONE .cl, then check off any set of the .cl
;; files in that folder in a single pass.  Every .cl in the folder is shown;
;; names are parsed from the filenames (text after the first underscore).
;; Duplicates of paths already in the list are skipped.
(defun pflabel:on-cl-add (dcl_id / f dir files presel chosen path nm)
  (if (setq f (pflabel:browse "Select a Centerline (.CL) in the Profile's Folder"
                              '*pflabel-dir-cl* "cl"))
    (progn
      (setq dir   (strcat (vl-filename-directory f) "\\")
            files (acad_strlsort (vl-directory-files dir "*.cl" 1)))
      (setq presel (pflabel:index-of
                     (strcase (strcat (vl-filename-base f) ".CL"))
                     (mapcar 'strcase files)))
      (setq chosen (pflabel:scan-dialog dcl_id files presel))
      (foreach i chosen
        (setq path (strcat dir (nth i files))
              nm   (pflabel:parse-line-name (nth i files)))
        (if (not (assoc path cllist))
          (setq cllist (append cllist (list (cons path nm))))))
      (pflabel:fill-cl-list cllist))))

;; Secondary Remove: drop the selected row.
(defun pflabel:on-cl-remove ( / sel)
  (if (and (setq sel (get_tile "cl_list")) (/= sel ""))
    (progn
      (setq cllist (pflabel:remove-nth (atoi sel) cllist))
      (pflabel:fill-cl-list cllist))))


;;; ==========================================================================
;;; SECTION 11  --  Main dialog driver + command
;;; ==========================================================================

;; (pflabel:dcl-file) -> path to pfdialog.dcl
(defun pflabel:dcl-file ()
  (strcat *pftools-dir* "pfdialog.dcl"))

;; (pflabel:show-dialog) -> settings alist | nil
;;   dcl_id, cur, cllist and primsel are locals here; the action callbacks
;;   reach them via dynamic scope while start_dialog runs.
;;   start_dialog is wrapped in vl-catch-all so a callback error can never
;;   leave the dialog loaded.
(defun pflabel:show-dialog ( / dcl_id cur cllist primsel result)
  (setq dcl_id (load_dialog (pflabel:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (progn
      (setq cur     (pflabel:settings)      ; last-used settings, or defaults
            cllist  (pflabel:cl-pairs)      ; last-used secondaries, or nil
            primsel (pflabel:primary-pair)) ; last-used primary, or nil
      (if (not (new_dialog "pflabel_settings" dcl_id))
        (progn (unload_dialog dcl_id)
               (prompt "\nCould not open the settings dialog.") nil)
        (progn
          (pflabel:populate-tiles cur)
          (set_tile "primary_file" (if primsel (pflabel:cl-display primsel) ""))
          (pflabel:fill-cl-list cllist)
          ;; Pickers (nested dialogs) --------------------------------------
          (action_tile "pick_layer"
            "(set_tile \"layer\" (pflabel:pick-from-list dcl_id \"Select Layer\" (pflabel:layer-list) (get_tile \"layer\")))")
          (action_tile "pick_style"
            "(set_tile \"style\" (pflabel:pick-from-list dcl_id \"Select Text Style\" (pflabel:style-list) (get_tile \"style\")))")
          ;; Centerlines ---------------------------------------------------
          (action_tile "pick_primary" "(pflabel:on-primary-pick dcl_id)")
          (action_tile "cl_add"       "(pflabel:on-cl-add dcl_id)")
          (action_tile "cl_remove"    "(pflabel:on-cl-remove)")
          ;; Named settings I/O --------------------------------------------
          (action_tile "save_btn"     "(pflabel:on-save)")
          (action_tile "load_btn"     "(pflabel:on-load)")
          ;; OK / Cancel  (capture tile state before unload) ---------------
          (action_tile "ok"
            "(setq cur (pflabel:harvest-tiles)) (done_dialog 1)")
          (action_tile "cancel"       "(done_dialog 0)")
          (setq result (vl-catch-all-apply 'start_dialog '()))
          (unload_dialog dcl_id)
          (cond
            ((vl-catch-all-error-p result)
             (prompt (strcat "\nDialog error: "
                             (vl-catch-all-error-message result)))
             nil)
            ((= result 1)
             ;; Commit: merge harvested tiles over stored settings so the
             ;; grid-dialog scale keys survive the write.
             (setq *pflabel-settings* (pflabel:merge (pflabel:settings) cur))
             (setq *pflabel-primary* primsel)
             (setq *pflabel-cl*      cllist)
             (pflabel:write-settings (pflabel:auto-file) *pflabel-settings*)
             (prompt "\nPFLABEL settings saved.")
             *pflabel-settings*)
            (T (prompt "\nPFLABEL settings unchanged.") nil)))))))


;;; ==========================================================================
;;; SECTION 12  --  Grid-parameters dialog driver
;;; ==========================================================================

;; (pflabel:grid-ok)  --  OK callback: validate the four fields; on success
;;   stash reals + raw strings (dynamic scope) and close; else show errtile.
(defun pflabel:grid-ok ( / sta datum hs vs)
  (setq sta   (distof (get_tile "g_sta"))
        datum (distof (get_tile "g_datum"))
        hs    (distof (get_tile "g_hs"))
        vs    (distof (get_tile "g_vs")))
  (cond
    ((not (and sta datum hs vs))
     (set_tile "error" "All four fields must be valid numbers."))
    ((or (<= hs 0.0) (<= vs 0.0))
     (set_tile "error" "Scales must be greater than zero."))
    (T
     (setq gridvals (list sta datum hs vs)
           gridstrs (list (get_tile "g_sta") (get_tile "g_datum")
                          (get_tile "g_hs")  (get_tile "g_vs")))
     (done_dialog 1))))

;; (pflabel:show-grid-dialog) -> (sta0 datum hplot vplot) as REALS | nil
;;   Pre-fills: station + datum from session strings, scales from settings.
;;   On OK: session-remembers station + datum, persists the scales.
(defun pflabel:show-grid-dialog ( / dcl_id s gridvals gridstrs result)
  (setq dcl_id (load_dialog (pflabel:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load pfdialog.dcl.") nil)
    (if (not (new_dialog "pflabel_grid" dcl_id))
      (progn (unload_dialog dcl_id)
             (prompt "\nCould not open the grid dialog.") nil)
      (progn
        (setq s (pflabel:settings))
        (set_tile "g_sta"   (if *pflabel-sta0-str*  *pflabel-sta0-str*  "0"))
        (set_tile "g_datum" (if *pflabel-datum-str* *pflabel-datum-str* ""))
        (set_tile "g_hs"    (cdr (assoc "hscale" s)))
        (set_tile "g_vs"    (cdr (assoc "vscale" s)))
        (action_tile "accept" "(pflabel:grid-ok)")
        (action_tile "cancel" "(done_dialog 0)")
        (setq result (vl-catch-all-apply 'start_dialog '()))
        (unload_dialog dcl_id)
        (cond
          ((vl-catch-all-error-p result)
           (prompt (strcat "\nGrid dialog error: "
                           (vl-catch-all-error-message result)))
           nil)
          ((and (= result 1) gridvals)
           ;; Session-remember station + datum (raw strings, re-fill next run).
           (setq *pflabel-sta0-str*  (nth 0 gridstrs)
                 *pflabel-datum-str* (nth 1 gridstrs))
           ;; Persist the scales (firm standard).
           (pflabel:put-setting "hscale" (nth 2 gridstrs))
           (pflabel:put-setting "vscale" (nth 3 gridstrs))
           (pflabel:write-settings (pflabel:auto-file) (pflabel:settings))
           gridvals)
          (T nil))))))


;; Standalone test / entry point (settings only; PFLABEL calls show-dialog).
(defun c:PFLABELSET ( ) (pflabel:show-dialog) (princ))

(princ "\npfdialog.lsp loaded.  Command: PFLABELSET (settings dialog).")
(princ)
;;; ==========================================================================
;;; end of pfdialog.lsp
;;; ==========================================================================
