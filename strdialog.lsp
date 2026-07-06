;;; ==========================================================================
;;; strdialog.lsp  --  STRLABEL settings dialog wiring  (Tab 1: Structure Labels)
;;; --------------------------------------------------------------------------
;;; Paired with strdialog.dcl.  Pure AutoLISP + DCL, no .NET / VBA.
;;;
;;; Loaded alongside the engine + command.  Verifiable on its own (command
;;; STRLABELSET) and called by C:STRLABEL via (strlabel:show-dialog).
;;;
;;; --------------------------------------------------------------------------
;;; INTERFACE (how strlabel.lsp reads the collected values)
;;; --------------------------------------------------------------------------
;;;   (strlabel:show-dialog)   -- opens the dialog; on OK it sets the settings
;;;                               global + the transient run inputs (TIN / CL),
;;;                               writes the last-used settings file, and returns
;;;                               the settings alist; on Cancel returns nil.
;;;   (strlabel:settings)      -- settings alist, auto-loading last-used file
;;;                               (merged over defaults) on first read.
;;;   (strlabel:tin)           -- selected .tin path string | nil   (transient)
;;;   (strlabel:cl-pairs)      -- list of (path . name) for the .cl files chosen
;;;                               in the dialog | nil                (transient)
;;;
;;;   PERSISTED settings keys (the 11 below).  TIN + CL are per-run and are
;;;   deliberately NOT persisted and NOT part of *strlabel-keys*:
;;;     sta_pre sta_val sta_suf     Station-line   prefix / value / suffix
;;;     con_pre con_val con_suf     Construction   prefix / value / suffix
;;;     gl_pre  gl_val  gl_suf      Ground-line    prefix / value / suffix
;;;     layer                       text layer name
;;;     style                       text style name
;;;
;;; --------------------------------------------------------------------------
;;; SETTINGS STORAGE
;;; --------------------------------------------------------------------------
;;;   %LOCALAPPDATA%\StrTools\strlabel-settings.txt   (last-used, auto)
;;;   Plain KEY=VALUE text, one per line.  Load/Save buttons browse named .txt
;;;   files anywhere the user chooses.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Defaults + settings keys
;;; ==========================================================================

(setq *strlabel-def-settings*
  (list
    (cons "sta_pre" "STA.")
    (cons "sta_val" "X+XX.XX")
    (cons "sta_suf" "STORM LINE 'XX'")
    (cons "con_pre" "CONST.")
    (cons "con_val" "[size] [type]")
    (cons "con_suf" "[ID]")
    (cons "gl_pre"  "G.L.")
    (cons "gl_val"  "[elev]")
    (cons "gl_suf"  "")
    (cons "layer"   "STORM-TEXT_P")
    (cons "style"   "L080")))

;; Iteration order for populate/harvest -- must match the tile keys in the .dcl.
(setq *strlabel-keys*
  '("sta_pre" "sta_val" "sta_suf"
    "con_pre" "con_val" "con_suf"
    "gl_pre"  "gl_val"  "gl_suf"
    "layer"   "style"))

;; Persisted settings, populated on OK.  nil until first read/save.
(if (not (boundp '*strlabel-settings*)) (setq *strlabel-settings* nil))

;; Transient per-run inputs, populated on OK.  NOT persisted.
(if (not (boundp '*strlabel-tin*)) (setq *strlabel-tin* nil))   ; .tin path | nil
(if (not (boundp '*strlabel-cl*))  (setq *strlabel-cl*  nil))   ; ((path . name) ...)


;;; ==========================================================================
;;; SECTION 2  --  Settings file I/O  (KEY=VALUE text, self-contained)
;;; ==========================================================================

;; (strlabel:settings-dir) -> "...\StrTools\"   (created if missing)
(defun strlabel:settings-dir ( / base dir)
  (setq base (getenv "LOCALAPPDATA"))
  (if (or (null base) (= base "")) (setq base (getenv "TEMP")))
  (setq dir (strcat base "\\StrTools"))
  (if (not (vl-file-directory-p dir)) (vl-mkdir dir))
  (strcat dir "\\"))

;; (strlabel:auto-file) -> full path of the auto last-used settings file
(defun strlabel:auto-file ()
  (strcat (strlabel:settings-dir) "strlabel-settings.txt"))

;; (strlabel:write-settings file alist) -> T | nil
(defun strlabel:write-settings (file alist / f)
  (if (setq f (open file "w"))
    (progn
      (foreach kv alist (write-line (strcat (car kv) "=" (cdr kv)) f))
      (close f)
      T)))

;; (strlabel:read-settings file) -> alist of "key" -> "value" (raw file contents)
(defun strlabel:read-settings (file / f line pos out)
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

;; (strlabel:merge base over) -> full alist over every key in `base`, taking
;;   `over`'s value where present.  Guarantees all keys exist and stay valid.
(defun strlabel:merge (base over)
  (mapcar
    '(lambda (kv)
       (cons (car kv)
             (if (assoc (car kv) over) (cdr (assoc (car kv) over)) (cdr kv))))
    base))

;; (strlabel:settings) -> current settings alist (auto-loads last-used once)
(defun strlabel:settings ( / file)
  (if (null *strlabel-settings*)
    (setq *strlabel-settings*
          (strlabel:merge *strlabel-def-settings*
                          (if (findfile (setq file (strlabel:auto-file)))
                            (strlabel:read-settings file)
                            '()))))
  *strlabel-settings*)


;;; ==========================================================================
;;; SECTION 3  --  Transient run-input accessors  (read by strlabel.lsp)
;;; ==========================================================================

(defun strlabel:tin ()      *strlabel-tin*)
(defun strlabel:cl-pairs () *strlabel-cl*)


;;; ==========================================================================
;;; SECTION 4  --  Drawing lookups for the Layer / Style pickers
;;; ==========================================================================

;; (strlabel:layer-list) -> list of layer-name strings
(defun strlabel:layer-list ( / e nm out)
  (setq e (tblnext "LAYER" T) out '())
  (while e
    (setq nm (cdr (assoc 2 e)))
    (if (and nm (/= nm "")) (setq out (cons nm out)))
    (setq e (tblnext "LAYER")))
  (acad_strlsort (reverse out)))

;; (strlabel:style-list) -> list of text-style-name strings
(defun strlabel:style-list ( / e nm out)
  (setq e (tblnext "STYLE" T) out '())
  (while e
    (setq nm (cdr (assoc 2 e)))
    (if (and nm (/= nm "")) (setq out (cons nm out)))
    (setq e (tblnext "STYLE")))
  (acad_strlsort (reverse out)))


;;; ==========================================================================
;;; SECTION 5  --  Generic list picker (drives strlabel_pick)
;;; ==========================================================================

;; (strlabel:index-of item lst) -> 0-based index | nil
(defun strlabel:index-of (item lst / i found)
  (setq i 0 found nil)
  (foreach x lst
    (if (and (null found) (= x item)) (setq found i))
    (setq i (1+ i)))
  found)

;; (strlabel:pick-from-list dcl_id title items current) -> chosen string
;;   Returns `current` unchanged on Cancel or an empty list.
(defun strlabel:pick-from-list (dcl_id title items current / idx res)
  (setq res current)
  (if (and items (new_dialog "strlabel_pick" dcl_id))
    (progn
      (set_tile "pick_title" title)
      (start_list "items")
      (foreach it items (add_list it))
      (end_list)
      (if (setq idx (strlabel:index-of current items)) (set_tile "items" (itoa idx)))
      (action_tile "items"   "(setq res (nth (atoi (get_tile \"items\")) items))")
      (action_tile "accept"  "(setq res (nth (atoi (get_tile \"items\")) items)) (done_dialog 1)")
      (action_tile "cancel"  "(done_dialog 0)")
      (if (/= 1 (start_dialog)) (setq res current))))
  res)


;;; ==========================================================================
;;; SECTION 6  --  Line-name prompt (drives strlabel_name)
;;; ==========================================================================

;; (strlabel:ask-name dcl_id default) -> chosen string
;;   Returns `default` on Cancel or an empty entry.  Nested modal dialog, so
;;   no command-line getstring is needed while the main dialog is up.
(defun strlabel:ask-name (dcl_id default / res)
  (setq res default)
  (if (new_dialog "strlabel_name" dcl_id)
    (progn
      (set_tile "name" default)
      (action_tile "accept" "(setq res (get_tile \"name\")) (done_dialog 1)")
      (action_tile "cancel" "(done_dialog 0)")
      (if (/= 1 (start_dialog)) (setq res default))))
  (if (= res "") default res))


;;; ==========================================================================
;;; SECTION 7  --  CL list model + rendering
;;; ==========================================================================

;; (strlabel:cl-display pair) -> "NAME  (basename.cl)"
(defun strlabel:cl-display (pair / f nm)
  (setq f (car pair) nm (cdr pair))
  (strcat nm "  (" (vl-filename-base f) (vl-filename-extension f) ")"))

;; (strlabel:fill-cl-list pairs) -> nil   (repaints the cl_list tile)
(defun strlabel:fill-cl-list (pairs)
  (start_list "cl_list")
  (foreach p pairs (add_list (strlabel:cl-display p)))
  (end_list)
  (princ))

;; (strlabel:remove-nth idx lst) -> lst with element idx dropped
(defun strlabel:remove-nth (idx lst / i out)
  (setq i 0 out '())
  (foreach x lst
    (if (/= i idx) (setq out (cons x out)))
    (setq i (1+ i)))
  (reverse out))


;;; ==========================================================================
;;; SECTION 8  --  Tile population / harvesting
;;; ==========================================================================

(defun strlabel:populate-tiles (settings)
  (foreach k *strlabel-keys* (set_tile k (cdr (assoc k settings)))))

(defun strlabel:harvest-tiles ()
  (mapcar '(lambda (k) (cons k (get_tile k))) *strlabel-keys*))


;;; ==========================================================================
;;; SECTION 9  --  Named Load / Save actions (fired from within the dialog)
;;; ==========================================================================

(defun strlabel:on-save ( / f cur)
  (setq cur (strlabel:harvest-tiles))
  (if (setq f (getfiled "Save STRLABEL Settings" (strlabel:settings-dir) "txt" 1))
    (progn (strlabel:write-settings f cur)
           (prompt (strcat "\nSaved settings to " f)))))

(defun strlabel:on-load ( / f loaded)
  (if (setq f (getfiled "Load STRLABEL Settings" (strlabel:settings-dir) "txt" 0))
    (progn
      (setq loaded (strlabel:merge *strlabel-def-settings* (strlabel:read-settings f)))
      (strlabel:populate-tiles loaded)
      (prompt (strcat "\nLoaded settings from " f)))))


;;; ==========================================================================
;;; SECTION 10  --  Surface / centerline actions (fired from within the dialog)
;;; ==========================================================================
;;; These mutate `cllist`, the live (path . name) model held by show-dialog and
;;; reachable here via AutoLISP dynamic scope while start_dialog runs.

;; TIN Select: browse one .tin, drop the path into the tin_file tile.
(defun strlabel:on-tin-pick ( / f)
  (if (setq f (getfiled "Select Carlson Surface (.TIN) File" "" "tin" 0))
    (set_tile "tin_file" f)))

;; CL Add...: browse one .cl, ask its line name (basename default), append.
(defun strlabel:on-cl-add (dcl_id / f base nm)
  (if (setq f (getfiled "Select Carlson Centerline (.CL) File" "" "cl" 0))
    (progn
      (setq base (strcase (vl-filename-base f)))
      (setq nm   (strcase (strlabel:ask-name dcl_id base)))
      (setq cllist (append cllist (list (cons f nm))))
      (strlabel:fill-cl-list cllist))))

;; CL Remove: drop the selected row.
(defun strlabel:on-cl-remove ( / sel)
  (if (and (setq sel (get_tile "cl_list")) (/= sel ""))
    (progn
      (setq cllist (strlabel:remove-nth (atoi sel) cllist))
      (strlabel:fill-cl-list cllist))))


;;; ==========================================================================
;;; SECTION 11  --  Dialog driver + command
;;; ==========================================================================

;; (strlabel:dcl-file) -> path to strdialog.dcl
(defun strlabel:dcl-file ()
  (strcat *strtools-dir* "strdialog.dcl"))

;; (strlabel:show-dialog) -> settings alist | nil
;;   dcl_id, cur, cllist and tinsel are locals here; the action callbacks reach
;;   them via dynamic scope while start_dialog runs.
(defun strlabel:show-dialog ( / dcl_id cur cllist tinsel result)
  (setq dcl_id (load_dialog (strlabel:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load strdialog.dcl.") nil)
    (progn
      (setq cur    (strlabel:settings)    ; last-used settings, or defaults
            cllist (strlabel:cl-pairs))   ; last-used CL pairs (transient), or nil
      (if (not (new_dialog "strlabel_settings" dcl_id))
        (progn (unload_dialog dcl_id)
               (prompt "\nCould not open the settings dialog.") nil)
        (progn
          (strlabel:populate-tiles cur)
          (set_tile "tin_file" (if *strlabel-tin* *strlabel-tin* ""))
          (strlabel:fill-cl-list cllist)
          ;; Pickers (nested dialogs) --------------------------------------
          (action_tile "pick_layer"
            "(set_tile \"layer\" (strlabel:pick-from-list dcl_id \"Select Layer\" (strlabel:layer-list) (get_tile \"layer\")))")
          (action_tile "pick_style"
            "(set_tile \"style\" (strlabel:pick-from-list dcl_id \"Select Text Style\" (strlabel:style-list) (get_tile \"style\")))")
          ;; Surface + centerlines -----------------------------------------
          (action_tile "pick_tin"   "(strlabel:on-tin-pick)")
          (action_tile "cl_add"     "(strlabel:on-cl-add dcl_id)")
          (action_tile "cl_remove"  "(strlabel:on-cl-remove)")
          ;; Named settings I/O --------------------------------------------
          (action_tile "save_btn"   "(strlabel:on-save)")
          (action_tile "load_btn"   "(strlabel:on-load)")
          ;; OK / Cancel  (capture tile state before unload) ---------------
          (action_tile "ok"
            "(setq cur (strlabel:harvest-tiles) tinsel (get_tile \"tin_file\")) (done_dialog 1)")
          (action_tile "cancel"     "(done_dialog 0)")
          (setq result (start_dialog))
          (unload_dialog dcl_id)
          (if (= result 1)
            (progn
              (setq *strlabel-settings* cur)
              (setq *strlabel-tin* (if (= tinsel "") nil tinsel))
              (setq *strlabel-cl*  cllist)
              (strlabel:write-settings (strlabel:auto-file) cur)
              (prompt "\nSTRLABEL settings saved.")
              cur)
            (progn (prompt "\nSTRLABEL settings unchanged.") nil)))))))

;; Standalone test / entry point (settings only; STRLABEL calls show-dialog).
(defun c:STRLABELSET ( ) (strlabel:show-dialog) (princ))

(princ "\nstrdialog.lsp loaded.  Command: STRLABELSET (settings dialog).")
(princ)
;;; ==========================================================================
;;; end of strdialog.lsp
;;; ==========================================================================