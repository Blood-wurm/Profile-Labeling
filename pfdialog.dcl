// ==========================================================================
// pfdialog.dcl  --  PFTools v4 dialog definitions
// --------------------------------------------------------------------------
// Shared nested dialogs (pf_pick / pf_name / pf_scan) are driven from
// pfsettings.lsp.  pfsetup_main is wired in pfsetup.lsp; pflabel_settings
// in pflabel.lsp.  Predefined tiles (spacer, errtile) come from base.dcl.
//
// Styled to Carlson's TRI4.DCL conventions: in-tile labels, mnemonics,
// width + fixed_width to align edit fields, explicit ok/cancel buttons.
//
// The v3 pflabel_grid dialog (typed station/datum/scales) is GONE: PFSETUP
// owns grid registration now, station comes from the .cl and datum from
// the sheet's own elevation labels.
// ==========================================================================


// ---- Reusable list picker (Layer / Text-Style pickers) --------------------
pf_pick : dialog {
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


// ---- One-line name prompt -------------------------------------------------
pf_name : dialog {
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


// ---- Folder-scan checklist (multi-select) ---------------------------------
pf_scan : dialog {
  label = "Select From Folder";
  : text { label = "Check the files to include:"; }
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


// ---- PFSETUP: the anchor writer / editor ----------------------------------
// Type selects the block library (per type); Name is the record's IDENTITY
// KEY -- picked files VALIDATE against it.  Scales are PLOT scales per the
// Carlson convention (e.g. 20 and 2).  Extents are picked on screen AFTER
// this dialog closes; the datum is read from the grid's elevation labels.
pfsetup_main : dialog {
  label = "PFSETUP -- Profile Grid Record";

  : boxed_column {
    label = "Identity";
    : popup_list {
      key         = "s_type";
      label       = "Utility Type";
      mnemonic    = "T";
      width       = 34;
      fixed_width = true;
    }
    : edit_box {
      key         = "s_name";
      label       = "Line Name";
      mnemonic    = "N";
      edit_limit  = 64;
      edit_width  = 18;
      width       = 34;
      fixed_width = true;
    }
    : popup_list {
      key         = "s_mat";
      label       = "Material";
      mnemonic    = "M";
      width       = 34;
      fixed_width = true;
    }
    : row {
      : edit_box {
        key         = "s_hs";
        label       = "Horiz. Plot Scale";
        mnemonic    = "H";
        edit_limit  = 16;
        edit_width  = 8;
        width       = 30;
        fixed_width = true;
      }
      : edit_box {
        key         = "s_vs";
        label       = "Vert. Plot Scale";
        mnemonic    = "V";
        edit_limit  = 16;
        edit_width  = 8;
        width       = 30;
        fixed_width = true;
      }
    }
  }
  spacer;

  : boxed_column {
    label = "Alignment (.cl) -- station comes from this file, never typed";
    : row {
      : edit_box { key = "s_cl"; label = "Centerline"; edit_limit = 256; edit_width = 28; width = 44; fixed_width = true; is_enabled = false; }
      : button   { key = "s_cl_pick"; label = "Select"; mnemonic = "S"; fixed_width = true; }
    }
  }
  spacer;

  : boxed_column {
    label = "Profiles (.pro) -- one _INV (invert) + one _TOP (crown)";
    : list_box {
      key             = "s_pro";
      width           = 50;
      height          = 3;
      multiple_select = false;
    }
    : row {
      : button { key = "s_pro_add"; label = "Add...";  mnemonic = "A"; fixed_width = true; }
      : button { key = "s_pro_del"; label = "Remove";  mnemonic = "R"; fixed_width = true; }
    }
  }
  spacer;

  : boxed_column {
    label = "Surfaces (.tin) -- existing + DESIGN_* (proposed)";
    : list_box {
      key             = "s_tin";
      width           = 50;
      height          = 3;
      multiple_select = false;
    }
    : row {
      : button { key = "s_tin_add"; label = "Add...";  mnemonic = "d"; fixed_width = true; }
      : button { key = "s_tin_del"; label = "Remove";  mnemonic = "e"; fixed_width = true; }
    }
  }
  spacer;

  : text { label = "OK -> pick LOWER-LEFT + TOP-RIGHT (extents only), then type the datum."; }
  errtile;
  : row {
    : button { key = "accept"; label = "OK";     mnemonic = "O"; width = 11; is_default = true; }
    : button { key = "cancel"; label = "Cancel"; mnemonic = "C"; width = 11; is_cancel  = true; }
  }
}


// ---- PFLABELSET: label text + text properties -----------------------------
// Centerline pickers are GONE: the primary .cl comes from the anchor and
// the secondary set is the registry (every other anchor's .cl).
// Of the Prefix/Suffix fields: sta_pre / sta_suf / con_suf / gl_suf are
// LIVE; con_pre / gl_pre are DEAD (*pf-rule-table* owns those prefixes) --
// tiles left in place pending a per-type editor.  The layer tile persists
// but the run-time layer rule is Derived/CLayer (see pflabel.lsp).
pflabel_settings : dialog {
  label = "PFTools Label Settings";

  : boxed_column {
    label = "Label Text";
    : row {
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

  : boxed_column {
    label = "Text Properties";
    : row {
      : edit_box { key = "layer"; label = "Layer"; mnemonic = "L"; edit_limit = 64; edit_width = 24; width = 40; fixed_width = true; }
      : button   { key = "pick_layer"; label = "Select"; fixed_width = true; }
    }
    : toggle { key = "use_clayer"; label = "Use current layer"; mnemonic = "U"; }
    : row {
      : edit_box { key = "style"; label = "Style"; mnemonic = "S"; edit_limit = 64; edit_width = 24; width = 40; fixed_width = true; }
      : button   { key = "pick_style"; label = "Select"; fixed_width = true; }
    }
  }
  spacer;

  : row {
    : button { key = "ok";       label = "OK";     mnemonic = "O"; width = 7; is_default = true; }
    : button { key = "cancel";   label = "Cancel"; mnemonic = "C"; width = 7; is_cancel  = true; }
    : button { key = "load_btn"; label = "Load";   mnemonic = "d"; width = 7; }
    : button { key = "save_btn"; label = "Save";   mnemonic = "v"; width = 7; }
  }
}
