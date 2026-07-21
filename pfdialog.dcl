// ==========================================================================
// pfdialog.dcl  --  PFTools V4 dialog definitions
// --------------------------------------------------------------------------
// Styled to the native-Carlson contract (see the screenshots in
// "Dialog examples\"):
//   - bottom row is OK / Cancel / Help (OK far left); verb-rich dialogs
//     stack an all-buttons action row above it
//   - file bindings are a picker button on the LEFT named for the thing,
//     with the bound path as plain text to its right; inapplicable
//     pickers stay visible but greyed
//   - sub-picks are a small "Set" button right of the field
//   - popup_lists even for tiny enumerations; dead tiles greyed, never
//     removed; boxed_column sparingly; a Hints line on complex dialogs
//   - grids = header text row + list_box of column-formatted strings
// No tabs, no images: that is Carlson's own engine, not DCL.
//
// Command line across the suite keeps ONLY screen picks (grid extents,
// anchor entsel).  Every choice, confirm, and typed value lives here.
//
// Shared drivers (pf_pick / pf_name / pf_scan / pf_confirm / pick-index)
// live in pfsettings.lsp.  Per-command wiring lives with each command.
// ==========================================================================


// ---- Reusable list picker (layer / style / registry pickers) --------------
pf_pick : dialog {
  label = "Select";
  : text { key = "pick_title"; label = ""; width = 40; }
  : list_box {
    key             = "items";
    width           = 40;
    height          = 14;
    multiple_select = false;
  }
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { label = "OK";     key = "accept"; is_default = true; width = 11; }
    : button { label = "Cancel"; key = "cancel"; is_cancel  = true; width = 11; }
  }
}


// ---- One-line name prompt -------------------------------------------------
pf_name : dialog {
  label = "Line Name";
  : edit_box {
    key        = "name";
    label      = "Line Name";
    mnemonic   = "N";
    edit_limit = 64;
    edit_width = 24;
  }
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { label = "OK";     key = "accept"; is_default = true; width = 11; }
    : button { label = "Cancel"; key = "cancel"; is_cancel  = true; width = 11; }
  }
}


// ---- Folder-scan checklist (multi-select) ---------------------------------
pf_scan : dialog {
  label = "Select From Folder";
  : text { label = "Check the files to include:"; }
  : list_box {
    key             = "scan_list";
    width           = 44;
    height          = 14;
    multiple_select = true;
  }
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { label = "OK";     key = "accept"; is_default = true; width = 11; }
    : button { label = "Cancel"; key = "cancel"; is_cancel  = true; width = 11; }
  }
}


// ---- Shared Yes/No confirm ------------------------------------------------
// No is BOTH the default and the cancel: Enter and Esc are the safe path,
// Yes is always a deliberate click.  Up to four message lines.
pf_confirm : dialog {
  label = "PFTools";
  : text { key = "c_title"; label = ""; width = 64; }
  spacer;
  : text { key = "c_l1"; label = ""; width = 64; }
  : text { key = "c_l2"; label = ""; width = 64; }
  : text { key = "c_l3"; label = ""; width = 64; }
  : text { key = "c_l4"; label = ""; width = 64; }
  spacer;
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { label = "Yes"; key = "yes"; width = 11; }
    : button { label = "No";  key = "no";  width = 11;
               is_default = true; is_cancel = true; }
  }
}


// ---- PFSETUP: the registry manager ----------------------------------------
// Replaces the command-line registry menu.  The list is THE registry
// (anchors + stubs); every verb is a button.  The dialog closes for any
// verb that needs the drawing (picks), then the command loop reopens it.
pfsetup_registry : dialog {
  label = "PFSETUP - Profile Registry";
  : text { label = "AUTO names profiles from the sheet; placing one anchors its grid."; }
  spacer;
  : text { key = "reg_head"; label = "  Type        Line                        Status"; width = 56; }
  : list_box {
    key             = "reg_list";
    width           = 56;
    height          = 12;
    multiple_select = false;
  }
  : text { label = "Double-click: place an unplaced profile, edit a placed one."; }
  errtile;
  : row {
    fixed_width = true;
    : button { key = "reg_place"; label = "Place";              mnemonic = "P"; width = 13; }
    : button { key = "reg_all";   label = "Place All";          mnemonic = "A"; width = 13; }
    : button { key = "reg_edit";  label = "Edit";               mnemonic = "E"; width = 13; }
    : button { key = "reg_new";   label = "New...";             mnemonic = "N"; width = 13; }
    : button { key = "reg_scan";  label = "Refresh";            mnemonic = "R"; width = 13; }
  }
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { key = "accept"; label = "Close"; is_default = true; is_cancel = true; width = 11; }
    : button { key = "help";   label = "Help";  width = 11; }
  }
}


// ---- PFSETUP: the anchor writer / editor ----------------------------------
// Name is the record's IDENTITY KEY -- picked files VALIDATE against it.
// Scales are PLOT scales per the Carlson convention (e.g. 20 and 2).
// File rows are Carlson-native: named picker button LEFT, bound path RIGHT.
// The datum is typed HERE (one lower-left datum per grid -- settled); the
// only command-line steps left are the two extent picks after OK.
pfsetup_main : dialog {
  label = "PFSETUP - Profile Grid Record";

  : boxed_column {
    label = "Identity";
    : popup_list {
      key         = "s_type";
      label       = "Utility Type";
      mnemonic    = "T";
      width       = 38;
      fixed_width = true;
    }
    : edit_box {
      key         = "s_name";
      label       = "Line Name";
      mnemonic    = "N";
      edit_limit  = 64;
      edit_width  = 18;
      width       = 38;
      fixed_width = true;
    }
    : popup_list {
      key         = "s_mat";
      label       = "Material";
      mnemonic    = "M";
      width       = 38;
      fixed_width = true;
    }
    : row {
      : edit_box {
        key         = "s_hs";
        label       = "Horizontal Scale";
        mnemonic    = "H";
        edit_limit  = 16;
        edit_width  = 8;
        width       = 30;
        fixed_width = true;
      }
      : edit_box {
        key         = "s_vs";
        label       = "Vertical Scale";
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
    label = "Project Files";
    : row {
      : button { key = "s_cl_pick";   label = "Centerline";   width = 15; fixed_width = true; }
      : text   { key = "s_cl";   label = ""; width = 44; }
    }
    : row {
      : button { key = "s_inv_pick";  label = "Invert .pro";  width = 15; fixed_width = true; }
      : text   { key = "s_inv";  label = ""; width = 44; }
    }
    : row {
      : button { key = "s_top_pick";  label = "Crown .pro";   width = 15; fixed_width = true; }
      : text   { key = "s_top";  label = ""; width = 44; }
    }
    : row {
      : button { key = "s_tine_pick"; label = "Exist .tin";   width = 15; fixed_width = true; }
      : text   { key = "s_tine"; label = ""; width = 44; }
    }
    : row {
      : button { key = "s_tind_pick"; label = "Design .tin";  width = 15; fixed_width = true; }
      : text   { key = "s_tind"; label = ""; width = 44; }
    }
    : row {
      fixed_width = true;
      : button { key = "s_pro_clr"; label = "Clear Profiles"; width = 16; }
      : button { key = "s_tin_clr"; label = "Clear Surfaces"; width = 16; }
    }
  }
  spacer;

  : boxed_column {
    label = "Placement";
    : edit_box {
      key         = "s_datum";
      label       = "Datum Elevation";
      mnemonic    = "D";
      edit_limit  = 16;
      edit_width  = 10;
      width       = 38;
      fixed_width = true;
    }
    : toggle {
      key      = "s_repick";
      label    = "Re-pick grid extents on OK";
      mnemonic = "R";
    }
  }
  spacer;

  : text { label = "OK closes this dialog, then: pick grid LOWER-LEFT, then TOP-RIGHT."; }
  errtile;
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { key = "accept"; label = "OK";     mnemonic = "O"; width = 11; is_default = true; }
    : button { key = "cancel"; label = "Cancel"; mnemonic = "C"; width = 11; is_cancel  = true; }
    : button { key = "help";   label = "Help";   width = 11; }
  }
}


// ---- PFLABEL: the run dialog ----------------------------------------------
// Pick-first now: the target is chosen by pfs:choose-or-place BEFORE this
// opens (PFXLABEL idiom), so there is NO target popup -- this dialog lists a
// single target's structures.  Multi-select; [LABELED] marked from the
// drawing itself.  Wrong target -> Cancel and rerun.
pf_run : dialog {
  label = "PFTools - Structure Labels";
  : text { key = "run_title"; label = ""; width = 62; }
  spacer;
  : text { key = "run_head"; label = "  Structure             Station          Status"; width = 62; }
  : list_box {
    key             = "run_list";
    width           = 62;
    height          = 12;
    multiple_select = true;
  }
  : text { key = "run_count"; label = ""; width = 62; }
  errtile;
  : row {
    fixed_width = true;
    : button { key = "run_sel";  label = "Label Selected"; mnemonic = "L"; width = 16; is_default = true; }
    : button { key = "run_all";  label = "Label All";      mnemonic = "A"; width = 16; }
    : button { key = "run_set";  label = "Settings...";    mnemonic = "S"; width = 16; }
  }
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { key = "cancel"; label = "Cancel"; is_cancel = true; width = 11; }
    : button { key = "help";   label = "Help";   width = 11; }
  }
}


// ---- PFINVERT: its own run dialog (pfi_run) -------------------------------
// Same shape as pf_run but a separate definition by design -- a home for
// invert-specific fields later without disturbing PFLABEL.  Tile keys are
// pi_* so the pfi: handlers stay independent.  Pick-first, no target popup.
pfi_run : dialog {
  label = "PFINVERT - Invert Labels";
  : text { key = "pi_title"; label = ""; width = 62; }
  spacer;
  : text { key = "pi_head"; label = "  Structure             Station          Status"; width = 62; }
  : list_box {
    key             = "pi_list";
    width           = 62;
    height          = 12;
    multiple_select = true;
  }
  : text { key = "pi_count"; label = ""; width = 62; }
  errtile;
  : row {
    fixed_width = true;
    : button { key = "pi_sel";  label = "Label Selected"; mnemonic = "L"; width = 16; is_default = true; }
    : button { key = "pi_all";  label = "Label All";      mnemonic = "A"; width = 16; }
    : button { key = "pi_set";  label = "Settings...";    mnemonic = "S"; width = 16; }
  }
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { key = "cancel"; label = "Cancel"; is_cancel = true; width = 11; }
    : button { key = "help";   label = "Help";   width = 11; }
  }
}


// ---- PFXLABEL: the crossings dialog ---------------------------------------
// The ledger IS the list; recon marks each row LABELED / OUTSTANDING from
// the drawing.  "Label Outstanding" is the everyday verb.  Change Target
// clears the sticky target and ends the run (rerun to choose).
pfxl_run : dialog {
  label = "PFXLABEL - Pipe Crossings";
  : text { key = "xl_tgt"; label = ""; width = 66; }
  spacer;
  : text { key = "xl_head"; label = "  Source          Target Sta      Source Sta      Status"; width = 66; }
  : list_box {
    key             = "xl_list";
    width           = 66;
    height          = 12;
    multiple_select = true;
  }
  errtile;
  : row {
    fixed_width = true;
    : button { key = "xl_out";  label = "Label Outstanding"; mnemonic = "O"; width = 18; is_default = true; }
    : button { key = "xl_sel";  label = "Label Selected";    mnemonic = "L"; width = 18; }
    : button { key = "xl_tgtb"; label = "Change Target";     mnemonic = "T"; width = 18; }
  }
  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { key = "cancel"; label = "Cancel"; is_cancel = true; width = 11; }
    : button { key = "help";   label = "Help";   width = 11; }
  }
}


// ---- PFLABELSET: label text + text properties -----------------------------
// Of the Prefix/Suffix fields: sta_pre / sta_suf / con_suf / gl_suf are
// LIVE; con_pre / gl_pre are DEAD (*pf-rule-table* owns those prefixes) --
// greyed in place per the Carlson convention, pending a per-type editor.
// The layer tile persists but the run-time layer rule is Derived/CLayer.
pflabel_settings : dialog {
  label = "PFTools - Label Settings";

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
      : edit_box { key = "con_pre"; edit_width = 10; edit_limit = 32; is_enabled = false; }
      : edit_box { key = "con_val"; edit_width = 18; edit_limit = 64; is_enabled = false; }
      : edit_box { key = "con_suf"; edit_width = 26; edit_limit = 64; }
    }
    : row {
      : text     { label = "Ground:"; width = 13; fixed_width = true; }
      : edit_box { key = "gl_pre"; edit_width = 10; edit_limit = 32; is_enabled = false; }
      : edit_box { key = "gl_val"; edit_width = 18; edit_limit = 64; is_enabled = false; }
      : edit_box { key = "gl_suf"; edit_width = 26; edit_limit = 64; }
    }
  }
  spacer;

  : boxed_column {
    label = "Text Properties";
    : row {
      : edit_box { key = "layer"; label = "Layer"; mnemonic = "L"; edit_limit = 64; edit_width = 24; width = 42; fixed_width = true; }
      : button   { key = "pick_layer"; label = "Set"; width = 8; fixed_width = true; }
    }
    : toggle { key = "use_clayer"; label = "Use current layer"; mnemonic = "U"; }
    : row {
      : edit_box { key = "style"; label = "Style"; mnemonic = "S"; edit_limit = 64; edit_width = 24; width = 42; fixed_width = true; }
      : button   { key = "pick_style"; label = "Set"; width = 8; fixed_width = true; }
    }
  }
  spacer;

  : row {
    fixed_width = true;
    alignment   = "centered";
    : button { key = "ok";       label = "OK";     mnemonic = "O"; width = 9; is_default = true; }
    : button { key = "cancel";   label = "Cancel"; mnemonic = "C"; width = 9; is_cancel  = true; }
    : button { key = "load_btn"; label = "Load";   mnemonic = "d"; width = 9; }
    : button { key = "save_btn"; label = "Save";   mnemonic = "v"; width = 9; }
    : button { key = "help";     label = "Help";   width = 9; }
  }
}
