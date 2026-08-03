# Superseded — nothing here is live

Parked 2026-08-02. Nothing loads any of it. Not maintained: if something needs
changing, change the live copy and leave these alone.

## `pf.sh`, `pfcheck.sh`

The bash tools as they stood before the PowerShell port. Replaced by
`.claude/skills/pf-find/pf.ps1` and `.claude/skills/pf-verify/pfcheck.ps1`,
which run on the work machine too (no bash, no installed binaries).

Kept as the known-good reference the port was verified against: every
subcommand and all six gates were diffed against these until the output was
byte-for-byte identical. Three differences were deliberate:

1. `_attic/` is excluded everywhere now. `pfcheck.sh` already skipped it;
   `pf.sh` did not, so `find` used to surface 20 retired symbols as live hits.
2. `refs` and `grep` output is sorted; these walk the tree in directory order.
3. The `show` error message says `pf find`, not `pf.sh find`.

`trim.sh` is NOT here — it was never ported and is still the live tool for
`pf-trim`, bash and home machine only.

## `pfsuite-skills-fork/`

A second copy of the skills that lived at `pfsuite/.claude/skills/`. Both it
and `V5/.claude/skills/` were loaded every session, and they had drifted: the
fork was missing `pf-trim` entirely, did not know about `pf2sew`, and its
`pfcheck.sh` still scanned `_attic/`.

It also could not have worked. `pf.sh` derives the tree three levels up from
itself, which from `pfsuite/.claude/skills/pf-find/` resolves to
`pfsuite/pfsuite/` — a directory that does not exist. What it was really doing
was making the documented relative path `.claude/skills/...` resolve from the
`pfsuite/` working directory. The PowerShell loader walks up to find `.claude`
instead, so nothing needs a second copy.

## `pfsuite-CLAUDE.md`

A near-duplicate of `V5/CLAUDE.md`; both loaded every session, costing ~40
duplicated lines per turn. Its only unique content — the `OPENDCL-WIRING.md`
pointer — was folded into `V5/CLAUDE.md` before this was parked.
