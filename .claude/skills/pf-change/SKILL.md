---
name: pf-change
description: Orientation and rules for changing anything in the pfsuite AutoLISP/OpenDCL suite — which module owns a prefix, the load-order guardrail, the palette write-free contract, the pf:run-command wrapper, and which of the fifteen .md files to open for a given question. Read this before editing a .lsp, .dcl or .odcl, or before opening any project doc, so you consult 30 lines instead of 3000.
---

# Changing pfsuite

Tree root is `pfsuite/`. Use `pf-find` to locate code and `pf-verify` to check
an edit. This skill is the map.

## Prefix → owner

| prefix | module | |
|---|---|---|
| `pf:` | `pftools-lib` | pure engine; also `pf:run-command`/`pf:undo-*` in pfanchor |
| `pfa:` | `pfanchor` | record + registry + ledger |
| `pfd:` | `pfdraw` | the only drawing boundary |
| **`pfset:`** | **`pfsettings`** | user state, NOD, shared dialogs |
| **`pfs:`** | **`pfsetup`** | `C:PFSETUP` |
| `pflabel:` | `pflabel` | `pfxl:` `pfxlabel` · `pfi:` `pfinvert` · `pfr:` `pfreport` · `pfp:` `pfpalette` · `pfrem:` PFREMOVE (in pfanchor) |

`pfset:` and `pfs:` are different modules four load positions apart. Confusing
them is the easiest mistake to make here — check with `pf.sh find` first.

## Load order is law

`pftools-cfg → pftools-lib → pfdraw → pfanchor → pfsettings → pfsetup →
pflabel → pfxlabel → pfinvert → pfreport → pfpalette`

A file may only depend on files above it. Four documented exceptions resolve
at call time and are baselined; adding a fifth needs a README note first.
`pftools-load.lsp` stays at root and is the source of truth for the order.

## Contracts that outrank convenience

**Write-free palette reads.** Modeless OpenDCL handlers may only call provably
read-only code. Gather paths (run dialogs, setup, anchor handlers) pass
`write-p` nil — a cache miss there costs one re-sample, never a drawing write.
`pfa:nod-dict` / `pfa:ledger-dict` with `create` nil never write. Verified in
CAD, and re-verified by `PFPDBMOD` delta.

**Commands run under `pf:run-command`** (`pfanchor`, ~line 1161): it installs
`pf:run-error`, the Esc ledger-flush hook, and echo save/restore. Do not
reintroduce a per-command `*error*` handler — five of them were deliberately
deleted in the 2026-07-26 restructure. The body still opens its own undo group
at the point its writes start; gather stays outside the group.

**Verbs are deferred-fired, reads are direct.** Palette handlers may call
reads inline; anything that writes goes through `pfp:defer`.

**`*pftools-dir*` is hardcoded to the deployment machine's path.** It is a
known open issue, not a bug to fix in passing.

## One home per fact

Each `.lsp` lives in its own folder with a `README.md` beside it holding the
narrative contract — What it owns / Public API / Invariants / Open issues. The
`.lsp` header is a pointer, not a duplicate. **When behaviour changes, update
that README in the same edit**; when a fact would fit two places, it belongs in
exactly one. `pf-verify`'s API-drift check catches the easy half of this.

## Which doc to open

Don't read these speculatively — they total ~3600 lines. Route:

| question | file |
|---|---|
| what a module does / its API / its invariants | `pfsuite/<module>/README.md` — **always try this first** |
| status, structure, milestones, OpenDCL constraints | `pfsuite/README.md` (§1 status, §2 structure, §5 OpenDCL, §6 paths into commands) |
| known bugs, per-command | `pfsuite-md/OPEN-ISSUES.md` (headed by command) |
| low-priority backlog | `pfsuite-md/Low_Priority_issues.md` (11 lines) |
| manual CAD test steps | `pfsuite-md/TESTING.md` (§0 load … §8 free-swing attacks) |
| palette structure, anchoring, events, wiring plan | `pfsuite-odcl/PALETTE-LAYOUT.md` |
| palette shakedown + recorded results | `pfsuite-odcl/PALETTE-TESTING.md` (§6 results, §7 triage) |
| engine extraction / order ticket | `pfsuite-md/REFACTOR-PLAN.md` |
| the membership-index design (not yet built) | `pfanchor/INDEX-DESIGN.md`, `INDEX-VALUES.md` |
| how the restructure was done | `pfsuite-md/RESTRUCTURE-PROMPT.md` — historical, completed |

Prefer `pf.sh api <module>` over reading a whole README, and a heading-anchored
`Read` with `offset` over a whole project doc.

## Editing mechanics

- Anchor `Edit` on unique surrounding text; AutoLISP repeats short forms constantly.
- Keep the `;; (name args) -> result` comment above every new defun — the
  symbol index harvests that line, and a missing one costs future lookups.
- Keep `;;; SECTION n --` banners accurate; `pf.sh outline` is built on them.
- After any `.odcl` edit, the change does not reach the runtime until
  `PFPRELOAD`. Say so whenever you hand back an `.odcl` change.
- Run `pf-verify` before reporting done, and name any CAD gate you could not run.
