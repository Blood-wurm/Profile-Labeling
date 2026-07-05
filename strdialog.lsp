;;; ==========================================================================
;;; strdialog.lsp  --  STRLABEL settings dialog wiring  (Tab 1: Structure Labels)
;;; --------------------------------------------------------------------------
;;; Paired with strdialog.dcl.  Pure AutoLISP + DCL, no .NET / VBA.
;;;
;;; STANDALONE: this file does NOT modify or depend on strtools-lib.lsp or
;;; strlabel.lsp.  It is verified on its own (command STRLABELSET) and wired
;;; into C:STRLABEL later.
;;;
;;; --------------------------------------------------------------------------
;;; INTERFACE (how strlabel.lsp will read the collected values)
;;; --------------------------------------------------------------------------
;;;   Global  *strlabel-settings*   -- an alist of "key" -> "value" strings.
;;;   (strlabel:settings)           -- returns that alist, auto-loading the
;;;                                    last-used file (merged over defaults) if
;;;                                    the global has not been set yet.  This is
;;;                                    the single call the pipeline should use.
;;;   (strlabel:show-dialog)        -- opens the dialog; on OK it sets the
;;;                                    global, writes the last-used file, and
;;;                                    returns the alist; on Cancel returns nil
;;;                                    and leaves the global untouched.
;;;
;;;   Setting keys (all always present, all pre-valid on open):
;;;     sta_pre sta_val sta_suf     Station-line   prefix / value / suffix
;;;     con_pre con_val con_suf     Construction   prefix / value / suffix
;;;     gl_pre  gl_val  gl_suf      Ground-line    prefix / value / suffix
;;;     layer                       text layer name
;;;     style                       text style name
;;;
;;; --------------------------------------------------------------------------
;;; SETTINGS STORAGE
;;; --------------------------------------------------------------------------
;;;   Kept OFF the company drive, under the per-user profile:
;;;     %LOCALAPPDATA%\StrTools\strlabel-settings.txt   (last-used, auto)
;;;   Format is plain KEY=VALUE text, one per line (self-contained reader/
;;;   writer below -- no dependency on the engine).  The Load/Save Settings
;;;   buttons additionally browse named .txt files anywhere the user chooses.
;;; ==========================================================================

(vl-load-com)


;;; ==========================================================================
;;; SECTION 1  --  Defaults + settings keys
;;; ==========================================================================
;;; Seeded from STRLABEL's current hardcoded constants so the dialog opens
;;; pre-populated with valid values (never blank-as-default).

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

;; Last-used settings, populated on OK.  nil until first read/save.
(if (not (boundp '*strlabel-settings*)) (setq *strlabel-settings* nil))


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
;;; SECTION 3  --  Drawing lookups for the Layer / Style pickers
;;; ==========================================================================

;; (strlabel:layer-list) -> list of layer-name strings
;;   (layerlist) is the built-in; wrapped so the caller reads one source.
(defun strlabel:layer-list () (acad_strlsort (layerlist)))

;; (strlabel:style-list) -> list of text-style-name strings (no Carlson call
;;   exists, so we walk the STYLE symbol table ourselves)
(defun strlabel:style-list ( / e nm out)
  (setq e (tblnext "STYLE" T) out '())
  (while e
    (setq nm (cdr (assoc 2 e)))
    (if (and nm (/= nm "")) (setq out (cons nm out)))
    (setq e (tblnext "STYLE")))
  (acad_strlsort (reverse out)))


;;; ==========================================================================
;;; SECTION 4  --  Generic list picker (drives strlabel_pick)
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
;;   `res`/`items` are visible to the action callbacks via AutoLISP dynamic scope.
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
;;; SECTION 5  --  Tile population / harvesting
;;; ==========================================================================

(defun strlabel:populate-tiles (settings)
  (foreach k *strlabel-keys* (set_tile k (cdr (assoc k settings)))))

(defun strlabel:harvest-tiles ()
  (mapcar '(lambda (k) (cons k (get_tile k))) *strlabel-keys*))


;;; ==========================================================================
;;; SECTION 6  --  Named Load / Save actions (fired from within the dialog)
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
;;; SECTION 7  --  Dialog driver + command
;;; ==========================================================================

;; (strlabel:dcl-file) -> path to strdialog.dcl (support path, then tools dir)
(defun strlabel:dcl-file ()
  (cond
    ((findfile "strdialog.dcl"))
    ((and (boundp '*strtools-dir*) *strtools-dir*
          (findfile (strcat *strtools-dir* "strdialog.dcl"))))
    (T "strdialog.dcl")))

;; (strlabel:show-dialog) -> settings alist | nil
;;   dcl_id and cur are locals here; the action callbacks reach them via
;;   dynamic scope while start_dialog runs.
(defun strlabel:show-dialog ( / dcl_id cur result)
  (setq dcl_id (load_dialog (strlabel:dcl-file)))
  (if (< dcl_id 0)
    (progn (prompt "\nCould not load strdialog.dcl.") nil)
    (progn
      (setq cur (strlabel:settings))                 ; last-used, or defaults
      (if (not (new_dialog "strlabel_settings" dcl_id))
        (progn (unload_dialog dcl_id)
               (prompt "\nCould not open the settings dialog.") nil)
        (progn
          (strlabel:populate-tiles cur)
          ;; (tab_struct is the active tab -- no action; tab_invert/tab_cross disabled)
          (action_tile "pick_layer"
            "(set_tile \"layer\" (strlabel:pick-from-list dcl_id \"Select Layer\" (strlabel:layer-list) (get_tile \"layer\")))")
          (action_tile "pick_style"
            "(set_tile \"style\" (strlabel:pick-from-list dcl_id \"Select Text Style\" (strlabel:style-list) (get_tile \"style\")))")
          (action_tile "save_btn" "(strlabel:on-save)")
          (action_tile "load_btn" "(strlabel:on-load)")
          (action_tile "accept"   "(setq cur (strlabel:harvest-tiles)) (done_dialog 1)")
          (action_tile "cancel"   "(done_dialog 0)")
          (setq result (start_dialog))
          (unload_dialog dcl_id)
          (if (= result 1)
            (progn
              (setq *strlabel-settings* cur)
              (strlabel:write-settings (strlabel:auto-file) cur)
              (prompt "\nSTRLABEL settings saved.")
              cur)
            (progn (prompt "\nSTRLABEL settings unchanged.") nil)))))))

;; Standalone test / entry point until wired into STRLABEL.
(defun c:STRLABELSET ( ) (strlabel:show-dialog) (princ))

(princ "\nstrdialog.lsp loaded.  Command: STRLABELSET (settings dialog).")
(princ)
;;; ==========================================================================
;;; end of strdialog.lsp
;;; ==========================================================================
