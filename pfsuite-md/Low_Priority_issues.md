LOW — hygiene and drift
README is substantially stale. §1 says "LISP wiring: None… Run in CAD: Never" and §2 says the project is pfsetup.odcl with a pfsetup/ prefix. Reality: pfpalette.lsp exists, is loaded, and uses pfsuite/. §8 still lists lblProject/lblCounts as having "no home yet" — but pfp:seed-labels writes to both. OPEN-ISSUES.md is still titled "V4".
.odcl control names are unverifiable statically. pfsuite.odcl is binary and byte-identical to the parent's. I could not confirm pfsPalette, tvwLines, metaList, lvwLinkage, lblProject, lblCounts exist in it. Given README §8, lblProject/lblCounts are the likely failures — and once you fix #2, they will no longer be swallowed by the catch.
*pf-preset-target* (README §6a) was never implemented. No occurrence anywhere.
The extracted engines have no consumer. pflabel:run / pfi:run / pfxl:run are called only by their own C:PF*. There is no C:PF*RUN, no deferred-fire, no Tab 2 — matching REFACTOR-PLAN's "NOT done" list, but worth stating plainly: the refactor is currently inert.
pf:echo-off/pf:echo-on are not re-entrant (pftools-lib.lsp:36-44). Nested calls lose the user's original CMDECHO and default it to 1. No nesting path exists today (only c: prologues call it), so this is latent — but the deferred-fire work in Tab 2 is exactly the thing that would create one.
Session directory memory is clobbered. pfsetup.lsp:92, :111, :129 overwrite *pfset-dir-cl/pro/tin* with the company folder on every pick, so the "last-browsed directory" feature in pfsettings §3 never takes effect.
The XING pass ledger only appends (pfxlabel.lsp:367-372); dead and duplicate handles accumulate across relabels.
pf:fmt-station (pftools-lib.lsp:605-607) produces 0+-50.00 for negative stations (documented caveat) and 0+100.00 for 99.999 (rounding at the boundary).
Dead API surface: pf:tin-load / pf:tin-unload / pf:tin-z are never called — the existing/DESIGN_ .tin bindings are collected, checksummed and stored but never consumed by anything. Also unused: pf:bbox, pf:get-verts, pf:pro-range, pf:y->elev, pf:text-pos, pf:remove-nth, pf:align-layer, pf:filter-layer, pfa:status-get, pfa:twin-cksum, and four pfa:xr-* accessors.

