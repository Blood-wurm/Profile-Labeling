// ==========================================================================
// pfdialog.dcl  --  PFLABEL dialogs  (main settings + grid parameters)
// --------------------------------------------------------------------------
// Paired with pfdialog.lsp.  Pure DCL -- the predefined tiles used here
// (spacer, errtile) come from AutoCAD's auto-loaded base.dcl.
//
// Styled to match Carlson's TRI4.DCL conventions:
//   - in-tile label = on single-field edit boxes (no separate : text column)
//   - mnemonic / edit_limit on inputs
//   - width + fixed_width to right-justify and align edit fields
//   - explicit ok / cancel buttons with is_default / is_cancel
//   - bottom row per the curb dialog: OK / Cancel / Load / Save, width 7
//
// In the Label Text grid the Value column is display-only (engine-generated).
// Of the Prefix/Suffix fields:
//   sta_pre / sta_suf / con_suf / gl_suf  -- LIVE
//   con_pre / gl_pre                      -- DEAD.  *pf-rule-table* now owns
//     both construction and elevation prefixes per block type.  The tiles are
//     left in place pending a decision on a per-type editor.
//
// This is Tab 1 of an eventual 3-tab dialog (Structure / Invert / Crossing).
// Tabs 2 and 3 are disabled placeholders and carry no content.
// ==========================================================================


// ---- Reusable list picker (used for both the Layer and Text-Style pickers)
// The driver retitles it per use via (set_tile "pick_title" <title>).
pflabel_pick : dialog {
  label = "Select";
  : text { key = "pick_title"; label = ""; }
  : list_box {
    key             = "items";
    width           = 34;
    height          = 14;
    multiple_select = false;
  }
  : row {
    : button { label = "OK";     key = "accept"; is_default = true; alignment = "centered"; width = 11; }
    : button { label = "Cancel"; key = "cancel"; is_cancel  = true; alignment = "centered"; width = 11; }
  }
}


// ---- Line-name prompt (nested from the primary / secondary Select buttons)
// Same nesting pattern as pflabel_pick; keeps command-line getstring out of
// the modal dialog.
pflabel_name : dialog {
  label = "Line Name";
  : edit_box {
    key        = "name";
    label      = "Line name";
    mnemonic   = "N";
    edit_limit = 64;
    edit_width = 24;
  }
  : row {
    : button { label = "OK";     key = "accept"; is_default = true; alignment = "centered"; width = 11; }
    : button { label = "Cancel"; key = "cancel"; is_cancel  = true; alignment = "centered"; width = 11; }
  }
}


// ---- Centerline folder scan (nested from the secondary Add... button) ----
// Multi-select checklist of every .cl in the browsed folder; check off the
// whole profile's lines in one pass.  Names default to the filenames.
pflabel_clscan : dialog {
  label = "Add Centerlines From Folder";
  : text { label = "Check the centerlines to add:"; }
  : list_box {
    key             = "scan_list";
    width           = 40;
    height          = 14;
    multiple_select = true;
  }
  : row {
    : button { label = "OK";     key = "accept"; is_default = true; alignment = "centered"; width = 11; }
    : button { label = "Cancel"; key = "cancel"; is_cancel  = true; alignment = "centered"; width = 11; }
  }
}


// ---- Grid parameters (opens after the main dialog, before graphic picks) --
// Carlson pattern: numeric setup in a dialog, point picks on screen after.
// H/V are PLOT scales (vertical exaggeration = H / V, usually 10).
// Scales persist to the settings file; station + datum are session-only.
pflabel_grid : dialog {
  label = "Profile Grid Parameters";
  : edit_box {
    key         = "g_sta";
    label       = "Starting Station";
    mnemonic    = "S";
    edit_limit  = 32;
    edit_width  = 11;
    width       = 34;
    fixed_width = true;
  }
  : edit_box {
    key         = "g_datum";
    label       = "Datum Elevation";
    mnemonic    = "D";
    edit_limit  = 32;
    edit_width  = 11;
    width       = 34;
    fixed_width = true;
  }
  : edit_box {
    key         = "g_hs";
    label       = "Horizontal Plot Scale";
    mnemonic    = "H";
    edit_limit  = 32;
    edit_width  = 11;
    width       = 34;
    fixed_width = true;
  }
  : edit_box {
    key         = "g_vs";
    label       = "Vertical Plot Scale";
    mnemonic    = "V";
    edit_limit  = 32;
    edit_width  = 11;
    width       = 34;
    fixed_width = true;
  }
  : text { label = "Plot scales, per Carlson convention (e.g. 50 and 5)."; }
  errtile;
  : row {
    : button { label = "OK";     key = "accept"; mnemonic = "O"; is_default = true; alignment = "centered"; width = 11; }
    : button { label = "Cancel"; key = "cancel"; mnemonic = "C"; is_cancel  = true; alignment = "centered"; width = 11; }
  }
}


// ---- Main settings dialog -------------------------------------------------
pflabel_settings : dialog {
  label = "PFLABEL Settings";

  // Tab bar.  Only "Structure Labels" is active in this build.
  : row {
    : button { key = "tab_struct"; label = "Structure Labels"; is_enabled = true;  fixed_width = true; }
    : button { key = "tab_invert"; label = "Invert Labels";    is_enabled = false; fixed_width = true; }
    : button { key = "tab_cross";  label = "Crossing Labels";  is_enabled = false; fixed_width = true; }
  }
  spacer;

  // ---- Label text: three rows, each split into prefix / value / suffix ----
  // The Value column is display-only (engine-generated).  sta_pre, sta_suf,
  // con_suf and gl_suf wrap the engine values; con_pre and gl_pre are DEAD --
  // *pf-rule-table* supplies those prefixes per block type.
  // [line] in the Station suffix is replaced per row with the line name.
  : boxed_column {
    label = "Label Text";

    : row {                                    // column headers
      : text { label = "";       width = 13; fixed_width = true; }
      : text { label = "Prefix"; width = 10; fixed_width = true; }
      : text { label = "Value";  width = 18; fixed_width = true; }
      : text { label = "Suffix"; width = 26; fixed_width = true; }
    }
    : row {
      : text     { label = "Station:"; width = 13; fixed_width = true; }
      : edit_box { key = "sta_pre"; edit_width = 10; edit_limit = 32; }
      : edit_box { key = "sta_val"; edit_width = 18; edit_limit = 64; is_enabled = false; }
      : edit_box { key = "sta_suf"; edit_width = 26; edit_limit = 64; }
    }
    : row {
      : text     { label = "Construction:"; width = 13; fixed_width = true; }
      : edit_box { key = "con_pre"; edit_width = 10; edit_limit = 32; }
      : edit_box { key = "con_val"; edit_width = 18; edit_limit = 64; is_enabled = false; }
      : edit_box { key = "con_suf"; edit_width = 26; edit_limit = 64; }
    }
    : row {
      : text     { label = "Ground:"; width = 13; fixed_width = true; }
      : edit_box { key = "gl_pre"; edit_width = 10; edit_limit = 32; }
      : edit_box { key = "gl_val"; edit_width = 18; edit_limit = 64; is_enabled = false; }
      : edit_box { key = "gl_suf"; edit_width = 26; edit_limit = 64; }
    }
  }
  spacer;

  // ---- Text properties: layer + style, each with a Select picker ----------
  // In-tile labels, equal width + fixed_width so the edit fields align.
  : boxed_column {
    label = "Text Properties";
    : row {
      : edit_box { key = "layer"; label = "Layer"; mnemonic = "L"; edit_limit = 64; edit_width = 24; width = 40; fixed_width = true; }
      : button   { key = "pick_layer"; label = "Select"; fixed_width = true; }
    }
    : row {
      : edit_box { key = "style"; label = "Style"; mnemonic = "S"; edit_limit = 64; edit_width = 24; width = 40; fixed_width = true; }
      : button   { key = "pick_style"; label = "Select"; fixed_width = true; }
    }
  }
  spacer;

  // ---- Centerlines --------------------------------------------------------
  // Primary is one .cl (display + Select); Select browses the file then
  // prompts for the line name.  Secondaries are a list (Add.../Remove); each
  // row reads "NAME  (basename.cl)".  Both are transient run inputs, not
  // persisted.
  //
  // No TIN picker: PFLABEL no longer reads a surface -- every elevation row
  // is now a XXX.XX placeholder supplied by the rule table.
  : boxed_column {
    label = "Centerlines";
    : row {
      : edit_box { key = "primary_file"; label = "Primary Line"; mnemonic = "P"; edit_limit = 256; edit_width = 24; width = 40; fixed_width = true; is_enabled = false; }
      : button   { key = "pick_primary"; label = "Select"; fixed_width = true; }
    }
    spacer;
    : text { label = "Secondary Centerlines (.cl):"; }
    : list_box {
      key             = "cl_list";
      width           = 46;
      height          = 5;
      multiple_select = false;
    }
    : row {
      : button { key = "cl_add";    label = "Add...";  mnemonic = "A"; fixed_width = true; }
      : button { key = "cl_remove"; label = "Remove";  mnemonic = "R"; fixed_width = true; }
    }
  }
  spacer;

  // ---- Bottom button row (curb pattern: OK / Cancel / Load / Save) --------
  : row {
    : button { key = "ok";       label = "OK";     mnemonic = "O"; width = 7; is_default = true; }
    : button { key = "cancel";   label = "Cancel"; mnemonic = "C"; width = 7; is_cancel  = true; }
    : button { key = "load_btn"; label = "Load";   mnemonic = "L"; width = 7; }
    : button { key = "save_btn"; label = "Save";   mnemonic = "S"; width = 7; }
  }
}
