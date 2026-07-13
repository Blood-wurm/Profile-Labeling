# Profile-Labeling Toolset (PFTools)

AutoLISP/DCL tools for annotating utility **profile drawings** in Carlson Civil
running on AutoCAD Map 3D. The suite labels drainage/utility structures and
pipe crossings on storm, sanitary, and water profiles to the firm's drafting
standard — work that Carlson's native profile workflows don't cover to spec.

> \*\*How to read this document.\*\* Sections 1–4 are the plain-language overview.
> Section 5 onward is implementation detail for anyone maintaining the code.

\---

## 1\. What it does

A profile sheet shows a utility line in section: horizontal axis is *station*
(distance along the line), vertical axis is *elevation*. Every structure and
every pipe crossing on that line needs a label placed at the correct station,
carrying the right identifier, ground elevation, and — for crossings — invert
elevation and pipe size.

Placing those labels by hand is slow and error-prone because the numbers behind
each one aren't visible in the drawing. They have to be computed from the
alignment geometry (station math), the surface model (ground elevation), and
the crossing geometry (where two lines actually intersect in plan). This toolset
computes those values from Carlson's own data and draws the labels.

It produces three things:

* **Structure labels** at the top of the grid — station, combined structure ID,
and ground-line elevation.
* **Crossing detection** — finds every point where other utility lines cross the
profiled line, with the exact station on each.
* **Crossing labels** — draws the crossing pipes at their true inverts on both
grids, with size and standard line labels, plus a summary crossings table.

## 2\. At a glance

|Command|Alias|What it does|
|-|-|-|
|`PFLABEL`|`PFL`|Labels structures at the top of a profile grid.|
|`PFXFIND`|—|Finds crossings on a target line (plan only, no grids). Run first.|
|`PFXLABEL`|—|Labels one crossing across its two grids. Run after `PFXFIND`.|
|`PFLABELSET`|—|Opens the settings dialog standalone (for testing/config only).|

`PFXFIND` and `PFXLABEL` are a **chained pair**: `PFXFIND` discovers crossings
and stashes them for the session; `PFXLABEL` labels them one at a time. They
must run in the same session.

## 3\. Why build this instead of using Carlson's native commands

The guiding rule was: **automate only where there is genuine geometric work the
user cannot reasonably do by hand.** A tool that just wraps two picks the drafter
already makes natively isn't worth the maintenance cost.

That bar is why an invert-labeling command (INVLABEL) was **shelved** — it would
have wrapped two manual picks and added nothing. It's also why the three
commands that *were* built each carry real computation the drafter can't do
manually: membership logic (which lines a structure sits on), surface elevations
from the TIN, station math, and crossing geometry on curved alignments.

## 4\. Architecture in one picture

```
pftools-load.lsp      loader — sets the install folder, loads the rest in order
      │
      ▼
pftools-lib.lsp       SHARED ENGINE — Carlson API wrappers, geometry, math,
      │               label composition, drawing primitives
      ├──────────────► pfdialog.lsp / .dcl    settings + grid-parameter dialogs
      ├──────────────► pflabel.lsp            C:PFLABEL
      └──────────────► pfcross.lsp            C:PFXFIND + C:PFXLABEL
```

One engine library, multiple thin command files. **This is a deliberate choice,
not an accident of growth — see §7.1 for why it isn't a single tabbed dialog.**

\---

## 5\. File map (engineer detail)

**`pftools-load.lsp`** — Loader. Sets `\*pftools-dir\*` to the install folder and
loads the four files in dependency order (engine → dialog → label → cross).
Loads by *full path* so it works whether or not the folder is on AutoCAD's
support search path.

**`pftools-lib.lsp`** — The shared engine. All pure functions except the Carlson
API wrappers and the drawing boundary. Organized in sections:

* Carlson API loading + error-trapped wrappers (Road API for stationing, DTM
API for surface elevation).
* Corridor geometry — point-to-polyline distance, used for pre-filtering.
* Multi-line membership \& stationing — decides which centerlines a point is
"on" and at what station.
* Profile transform — the `xform` seam that converts station/elevation to
world X/Y on a specific grid.
* String, formatting, and label-composition helpers.
* Drawing boundary — the only functions that create geometry.
* Corridor matching — binds each `.cl` file to its drawn polyline at setup.

**`pfdialog.lsp` / `pfdialog.dcl`** — Two dialogs: the main settings dialog
(text properties, TIN surface, primary + secondary centerlines, label
prefix/suffix) and the grid-parameters dialog (start station, datum, plot
scales). Handles settings persistence and the layer/style/centerline pickers.

**`pflabel.lsp`** — `C:PFLABEL`. Top-of-grid structure labeling.

**`pfcross.lsp`** — `C:PFXFIND` (crossing finder) and `C:PFXLABEL` (crossing
labeler).

## 6\. How each command runs

### PFLABEL

Follows the Carlson pattern — **dialogs first, graphic picks last:**

1. **Main dialog** — text layer/style, TIN surface, primary centerline,
secondary centerlines, and the label prefix/suffix text.
2. **Grid dialog** — start station, datum elevation, horizontal and vertical
plot scales.
3. **Graphic picks** — grid lower-left corner, then a point on the top border.
4. **All / Pick** prompt on the command line.
5. **Label run**, wrapped in a single undo group (one `U` reverses the pass).

Label composition rules:

* **Station rows** — profiled line first, remaining lines alphabetical.
* **Combined ID** — alphabetical by line name, so a junction structure gets the
*same* ID on every profile it appears in.
* **Ground line** — elevation sampled from the TIN at the structure's X,Y.
* User prefix/suffix text from the dialog wraps the engine-generated values; the
`\[line]` token in the station suffix is substituted per row.

Inverts are **not** drawn by PFLABEL — that was scoped as a separate pass (see
§3 on INVLABEL).

### PFXFIND (plan only)

Pick the target `.cl`, then check off candidate crossing `.cl` files from the
target's folder. The tool samples each alignment directly from its `.cl` file
and intersects them segment-by-segment to find every real crossing. For each
hit it reads *both* stations off the Road API and stores the result in the
session global `\*pfx-crossings\*` for `PFXLABEL`.

### PFXLABEL (one crossing per run, two grids)

Pick a crossing from PFXFIND's list, then define the **source** grid (the
crossing line's grid) and the **target** grid via corner picks + the grid
dialog. Then, for each grid, the tool:

1. Probes vertically at the crossing station to read the pipe's invert (lowest
bore line) and size (bore spacing).
2. Draws a station line, vertical station text, and both pipes as `PF-PIPE\_NN`
blocks at their true elevations, each with a two-row label.
3. Rebuilds the crossings table on the `PF-TABLE` layer.

\---

## 7\. Key design decisions \& why

This is the part worth walking through — each of these was a deliberate call
with a reason behind it.

### 7.1 Multiple commands sharing one library — *not* a tabbed dialog

The ideal UX would be one dialog with tabs (Structure / Invert / Crossing).
That isn't reachable from AutoLISP: **Carlson's tabbed dialogs are compiled MFC
controls inside ARX modules**, and DCL — the only native LISP dialog language —
has no tab tile. The one LISP path to tab controls is OpenDCL, which requires
shipping a third-party runtime to every workstation. Rather than take on that
dependency, the design is several commands sharing one engine library. The
in-progress unified launcher (§11) recovers most of the single-entry-point feel
without the runtime.

### 7.2 Corridor pre-filtering before Road-API calls

Asking the Road API to project a point onto a centerline it isn't near produces
two problems: false membership hits and a flood of "unable to locate point along
centerline" messages in the console. The fix: bind each `.cl` to its drawn
polyline at setup, and **skip the API call entirely unless the point is within a
tight distance of that polyline**. Clean output, correct membership.

### 7.3 Sample the `.cl`, don't read the drawn polyline (crossings)

Crossing detection originally read vertices off the drawn plan polyline. On
**arc alignments that breaks** — a polyline segment reads a curve as a straight
chord, which both *misses* real crossings on the inside of a curve and *reports*
false ones where chords intersect but the true arcs don't. The tool now samples
each alignment directly from its `.cl` file (2 ft steps, refined to \~0.1 ft near
a hit), so it follows true arc geometry regardless of what's drawn.

### 7.4 Lowest surviving vertical probe hit = invert

Pipes are drawn as two parallel bore lines, not a single line. An earlier
"exactly one hit" rule was wrong and failed on real pipes. The rule is now
**take the lowest surviving hit** after grid/reference layers are excluded from
the probe — that's the invert, and the spacing between the two bore lines gives
the pipe size. Polylines are excluded from the vertical probe by entity

### 7.5 Layer discipline: PF-TEMP vs PF-TABLE

Two tool-owned layers with opposite rules, by design:

* **`PF-TEMP`** holds output that must *survive* re-runs — invert ticks and
elevation text. It is **never erased** by the tool.
* **`PF-TABLE`** holds the crossings table, which is **blanket-cleared and
rebuilt** every run so it always reflects the current record.

Keeping them separate lets the table refresh cleanly without wiping
hand-verified invert marks. **Rule: put nothing else on either layer.**

### 7.6 Dialogs first, graphics last; one undo group per run

Setup values are collected in dialogs before any on-screen picks, matching
Carlson's native command feel. Each command run is wrapped in a single undo
group so one `U` cleanly reverses the whole pass, and an error handler unwinds
the TIN load and undo group on Esc or error.

### 7.7 What persists vs. what doesn't

Settings storage mirrors what actually stays constant:

* **Persisted** (firm standard): text layer/style, label prefix/suffix, plot
scales.
* **Session-only** (per profile): start station, datum elevation — re-filled on
the next run so re-labeling the same profile is quick.
* **Transient** (per run, never saved): TIN surface, primary + secondary
centerlines.

## 8\. Layer conventions

|Layer|Owner|Behavior|
|-|-|-|
|`PF-GRID-MJR`|drawing|Excluded from the vertical probe.|
|`PF-GRID-MNR`|drawing|Excluded from the vertical probe.|
|`PF-HBOX`|drawing|Excluded from the vertical probe.|
|`PF-TEMP`|tool|Invert ticks + elevation text. **Never erased.**|
|`PF-TABLE`|tool|Crossings table. **Cleared and rebuilt every run.**|
|`ALIGN-\*\_P`|derived|A grid's own pipe block, by utility type.|
|`<TYPE>\_P` / `<TYPE>-TEXT\_P`|derived|Crossing pipe + its text, by utility type.|

## 9\. Operating notes \& known failure modes

* **Keep `.cl` files current.** A structure the tool missed once traced to a
`.cl` whose recorded endpoints no longer matched the drawn alignment. The fix
was **regenerating the `.cl` from Carlson**, not a code change. If results look
wrong, regenerate the centerline files before suspecting the tool.
* **Structures must be snapped to their centerlines.** Membership uses a tight
offset tolerance; a structure that's visibly off its line will read as
off-line.
* **Data handoff is session-global.** `PFXFIND` must run before `PFXLABEL` in
the same drawing session — the crossings live in memory, not a file (yet).

## 10\. Current status

**None of the commands has been run in a live production drawing yet.** The code
is written and reviewed; the next step is testing each command on scratch copies
before any production use. Each file's header carries a matching "test on a
scratch copy first" note.

## 11\. Roadmap

**Unified dialog launcher.** A single entry point that routes between the two
labeling flows — Structure Labels (`PFLABEL`) and Crossing Labels
(`PFXFIND` → `PFXLABEL`, run as one chained operation). Its value is
**routing/dispatch**, not merging fields — the two flows keep their own settings.

**Output options for PFXLABEL.** PFXLABEL currently has no options dialog. It
will gain configurable crossing-table output and, potentially, the option to
pick both grid sides.

**Prefix/suffix parity for crossing labels.** PFLABEL's labels are already
configurable via dialog prefix/suffix text. Crossing labels are still driven by
hardcoded per-type templates. Adding prefix/suffix fields to PFXLABEL brings
crossing-label text composition to parity with structure labels. 

