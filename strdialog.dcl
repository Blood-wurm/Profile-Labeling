// ==========================================================================
// strdialog.dcl  --  STRLABEL settings dialog  (Tab 1: Structure Labels)
// --------------------------------------------------------------------------
// Paired with strdialog.lsp.  Pure DCL -- the predefined tiles used here
// (spacer) come from AutoCAD's auto-loaded base.dcl.  OK/Cancel are now
// explicit buttons (TRI4 convention) rather than the ok_cancel cluster.
//
// Styled to match Carlson's TRI4.DCL conventions:
//   - in-tile label = on single-field edit boxes (no separate : text column)
//   - mnemonic / edit_limit on inputs
//   - width + fixed_width to right-justify and align edit fields
//   - explicit ok / cancel buttons with is_default / is_cancel
//
// This is Tab 1 of an eventual 3-tab dialog (Structure / Invert / Crossing).
// Tabs 2 and 3 are disabled placeholders and carry no content.
// ==========================================================================


// ---- Reusable list picker (used for both the Layer and Text-Style pickers)
// The driver retitles it per use via (set_tile "pick_title" <title>).
strlabel_pick : dialog {
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


// ---- Line-name prompt (nested from the CL "Add..." button) ----------------
// Same nesting pattern as strlabel_pick; keeps command-line getstring out of
// the modal dialog.
strlabel_name : dialog {
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


// ---- Main settings dialog -------------------------------------------------
strlabel_settings : dialog {
  label = "STRLABEL Settings";

  // Tab bar.  Only "Structure Labels" is active in this build.
  : row {
    : button { key = "tab_struct"; label = "Structure Labels"; is_enabled = true;  fixed_width = true; }
    : button { key = "tab_invert"; label = "Invert Labels";    is_enabled = false; fixed_width = true; }
    : button { key = "tab_cross";  label = "Crossing Labels";  is_enabled = false; fixed_width = true; }
  }
  spacer;

  // ---- Label text: three rows, each split into prefix / value / suffix ----
  // Kept as a header-row + edit-row grid (in-tile labels can't column-align),
  // with TRI4 cosmetics (edit_limit) on the inputs.
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
      : edit_box { key = "sta_val"; edit_width = 18; edit_limit = 64; }
      : edit_box { key = "sta_suf"; edit_width = 26; edit_limit = 64; }
    }
    : row {
      : text     { label = "Construction:"; width = 13; fixed_width = true; }
      : edit_box { key = "con_pre"; edit_width = 10; edit_limit = 32; }
      : edit_box { key = "con_val"; edit_width = 18; edit_limit = 64; }
      : edit_box { key = "con_suf"; edit_width = 26; edit_limit = 64; }
    }
    : row {
      : text     { label = "Ground:"; width = 13; fixed_width = true; }
      : edit_box { key = "gl_pre"; edit_width = 10; edit_limit = 32; }
      : edit_box { key = "gl_val"; edit_width = 18; edit_limit = 64; }
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

  // ---- Surface + centerlines ---------------------------------------------
  // TIN is one file (edit + Select).  CL is a list (Add.../Remove); each row
  // reads "NAME  (basename.cl)".  Both are transient run inputs, not persisted.
  : boxed_column {
    label = "Surface && Centerlines";
    : row {
      : edit_box { key = "tin_file"; label = "TIN Surface"; mnemonic = "T"; edit_limit = 256; edit_width = 24; width = 40; fixed_width = true; }
      : button   { key = "pick_tin"; label = "Select"; fixed_width = true; }
    }
    spacer;
    : text { label = "Centerlines (.cl):"; }
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

  // ---- Bottom button row (TRI4/curb style: OK / Cancel / Load / Save) -----
  : row {
    : button { key = "ok";       label = "OK";             mnemonic = "O"; is_default = true; alignment = "centered"; width = 14; }
    : button { key = "cancel";   label = "Cancel";         mnemonic = "C"; is_cancel  = true; alignment = "centered"; width = 14; }
    : button { key = "load_btn"; label = "Load Settings..."; fixed_width = true; }
    : button { key = "save_btn"; label = "Save Settings..."; fixed_width = true; }
  }
}