// ==========================================================================
// strdialog.dcl  --  STRLABEL settings dialog  (Tab 1: Structure Labels)
// --------------------------------------------------------------------------
// Paired with strdialog.lsp.  Pure DCL -- the predefined tiles used here
// (ok_cancel, spacer) come from AutoCAD's auto-loaded base.dcl.
//
// This is Tab 1 of an eventual 3-tab dialog (Structure / Invert / Crossing).
// The tab bar is rendered now; Tabs 2 and 3 are disabled placeholders and
// carry no content -- they get their own boxed sections when built later.
// ==========================================================================


// ---- Reusable list picker (used for both the Layer and Text-Style pickers)
// The dialog carries key "pick_title" so the driver can retitle it per use
// via (set_tile "pick_title" <title>).
strlabel_pick : dialog {
  label = "Select";
  : text { key = "pick_title"; label = ""; }
  : list_box {
    key             = "items";
    width           = 34;
    height          = 14;
    multiple_select = false;
  }
  ok_cancel;
}


// ---- Main settings dialog -------------------------------------------------
strlabel_settings : dialog {
  label = "STRLABEL Settings";

  // Tab bar.  Only "Structure Labels" is active in this build; the other two
  // are disabled placeholders so the row reads as tabbed now without stubbing
  // their content.
  : row {
    : button { key = "tab_struct"; label = "Structure Labels"; is_enabled = true;  fixed_width = true; }
    : button { key = "tab_invert"; label = "Invert Labels";    is_enabled = false; fixed_width = true; }
    : button { key = "tab_cross";  label = "Crossing Labels";  is_enabled = false; fixed_width = true; }
  }
  spacer;

  // ---- Label text: three rows, each split into prefix / value / suffix ----
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
      : edit_box { key = "sta_pre"; edit_width = 10; }
      : edit_box { key = "sta_val"; edit_width = 18; }
      : edit_box { key = "sta_suf"; edit_width = 26; }
    }
    : row {
      : text     { label = "Construction:"; width = 13; fixed_width = true; }
      : edit_box { key = "con_pre"; edit_width = 10; }
      : edit_box { key = "con_val"; edit_width = 18; }
      : edit_box { key = "con_suf"; edit_width = 26; }
    }
    : row {
      : text     { label = "Ground:"; width = 13; fixed_width = true; }
      : edit_box { key = "gl_pre"; edit_width = 10; }
      : edit_box { key = "gl_val"; edit_width = 18; }
      : edit_box { key = "gl_suf"; edit_width = 26; }
    }
  }
  spacer;

  // ---- Text properties: layer + style, each with a Select picker ----------
  : boxed_column {
    label = "Text Properties";
    : row {
      : text     { label = "Layer:"; width = 13; fixed_width = true; }
      : edit_box { key = "layer"; edit_width = 30; }
      : button   { key = "pick_layer"; label = "Select..."; fixed_width = true; }
    }
    : row {
      : text     { label = "Style:"; width = 13; fixed_width = true; }
      : edit_box { key = "style"; edit_width = 30; }
      : button   { key = "pick_style"; label = "Select..."; fixed_width = true; }
    }
  }
  spacer;

  // ---- Named settings files (Carlson-style Load/Save) ---------------------
  : row {
    : button { key = "load_btn"; label = "Load Settings..."; fixed_width = true; }
    : button { key = "save_btn"; label = "Save Settings..."; fixed_width = true; }
  }
  spacer;

  ok_cancel;
}
