# Wiring an OpenDCL control to LISP

**What this is.** Everything measured in CAD about how a control on `pfsuite.odcl`
actually talks to `pfpalette.lsp` — event names, handler argument lists, which
accessors exist, and which calls put an uncatchable modal dialog on screen.

**Why it exists.** Wiring the Commands tab cost eight CAD round trips, and seven
of them were spent rediscovering things that are not in the vendor samples and
cannot be checked statically. Nothing here is inferable from the code. Read it
before wiring any new control.

Layout and anchoring: [`PALETTE-LAYOUT.md`](PALETTE-LAYOUT.md). Shakedown
procedure and recorded results: [`PALETTE-TESTING.md`](PALETTE-TESTING.md). The
palette's own contract: [`../pfpalette/README.md`](../pfpalette/README.md).

Everything in the tables below is **measured 2026-07-29** unless marked
*assumed*. Correct a row when a run disagrees with it; do not add an unmeasured
row without marking it.

---

## 1. The failure layers

A call can fail in several independent ways, and the guards are different:

| Failure | Symptom | Guard |
|---|---|---|
| The **function** does not exist | `no such function` from `pfp:try` | `pfp:callable-p` / `pfp:try` |
| The **property** does not exist on that control type | **modal dialog** | `pfp:type-can` — and nothing else |
| The **control name** is wrong | symbol is `nil`; the call does nothing, **silently** | a `null` test that names the control |
| The **control type** is wrong | **modal dialog**, `Invalid argument type`, `Argument: 0` | **none exists** — see below |

### Wrong name and wrong type look nothing alike

Measured 2026-07-30, and worth knowing by heart — the two have opposite
symptoms and unrelated fixes:

```
Error: Invalid argument type
Function: dcl-ListView-AddColumns
Argument: 0
```

**`Argument: 0` is the control itself, and the complaint is its TYPE.** A
*wrong name* leaves the symbol unbound → `nil` → the call does nothing and says
nothing, so you guard it with a `null` test (`pfp:caption`, `pfp:fill-items`).
A *wrong type* leaves the symbol **bound**, so every `null` guard passes, and
the call raises the uncatchable modal instead — then **aborts its caller**.
`lvwCommand` was declared as a List View in `pfpalette.lsp`, wasn't one in the
`.odcl`, and took `OnInitialize` down with it on the first open.

**There is no guard for this one, and there cannot be.** Nothing in LISP can
ask a control its type without making a type-specific call at it, and that call
*is* the fault. The only safe posture is not to call until Studio's Properties
tab has been read — which is why `*pfp-items-mode*` is a switch rather than a
probe. (It shipped `nil`, then `'listbox`; it is `'listview` again since the
control was rebuilt in Studio 2026-07-30. **The switch is a plain `setq`, not a
`boundp` guard** — under a guard, a session that had already loaded the suite
would keep the stale mode through a re-load and start making the *previous*
type's calls at the rebuilt control, which is this same modal reached by
editing a file correctly.)

Corollary: **put the riskiest `AddColumns` last** in `OnInitialize`. The three
that ran before the bad one kept their columns.

**`vl-catch-all-apply` does NOT suppress the second one.** OpenDCL raises it
from the ARX as a modal box *before LISP sees a return value*, so wrapping a
probe in a catch does not make it safe. This is the single most expensive fact
in this document.

```
An OpenDCL function argument processing exception has occurred!
Error: Invalid argument
Function: dcl-Control-GetValue
Property <Value> not found
```

Worse, the call **still returns `nil` to LISP afterwards**. So a probe loop
looks like it degraded gracefully while having put one dialog on screen per
candidate. The first `PFPCTL` printed six tidy `nil`s and had raised six boxes.

---

## 2. Handler naming

```
c:<project>/<form>/<control>#On<Event>
c:pfsuite/pfsPalette/optRun#OnSelChanged
```

The control path plus `#On<Event>` — the same three-segment path used to
reference the control itself. There is no tab segment.

**Studio writes the stub for you:** *Tools → Write Events to Lisp File*, tick
the event, *Add to File*. Point it at a scratch file and read the generated
`defun` line — that is the authoritative name **and argument list**, and it is
faster than any of the ways this document was worked out.

---

## 3. Events, by control type

| Control | Event | Handler arguments | |
|---|---|---|---|
| Palette (form) | `Initialize` | `()` | fires **before the window is realized** — see §5 |
| Palette (form) | `Close` | `()` | destroys controls; runtime formatting does not survive |
| Button | `Clicked` | `()` | |
| Check Box | `Clicked` | `(nValue)` | vendor sample, `AUBlockTool_Final.lsp:101` |
| Tree View | `SelChanged` | **`(Label Key)`** | label first |
| Option List | `SelChanged` | **`(nIndex sLabel)`** | **index first — reversed vs the tree** |
| Option List | `Clicked` | — | **does not exist**; Studio offers only `SelChanged` |
| List View | `SelChanged` | **`(ItemIndexOrCount Value)`** | index first, like the Option List. **Read §4's List View note before using `Value`** |

### The reversal is real

`tvwLines#OnSelChanged` takes `(Label Key)`. `optLabel#OnSelChanged` takes
`(nIndex sLabel)`. Same event name, opposite order. **Do not "make them
consistent"** — a future cleanup that aligns them will silently break dispatch.

### An arity mismatch is invisible

A handler whose argument list does not match fails **before its body runs**:

```
Command: too many arguments :error#2
```

It records nothing, so it looks exactly like an event that was never ticked in
Studio. If a handler appears dead, suspect arity before suspecting the tick.

### Every dispatch prints `*Cancel*`

One `*Cancel*` per event dispatch, on the command line, unavoidable. Not an
error. It is why a handler that chatters is worse than no handler.

---

## 4. Reading a value

| Control | Call | Result |
|---|---|---|
| Check Box | `dcl-Control-GetValue` | **works** — `0` unticked, non-zero ticked |
| Option List | `dcl-Control-GetValue` | **`nil` + modal dialog — never call** |
| Option List | anything else | no accessor exists; **use the event** |
| Label | `dcl-Control-SetCaption` | works (`SetText` raises — Labels have Caption, not Text) |
| Text Box | `dcl-Control-GetText` | works |
| List Box | `dcl-ListBox-GetCurSel` / `GetText ctrl index` | works — vendor sample |
| List Box | `dcl-ListBox-Clear` / `AddList ctrl <list of strings>` | works — vendor sample; **`AddList` is ADDITIVE, `Clear` first** |
| List View | use the **event**, `SelChanged` | reports the selection; no getter needed for the single-select case |

### The whole List Box family, attested

All four come from the sample and tutorial that ship with Studio — none is
inferred, and none needed a probe:

| Call | Source |
|---|---|
| `dcl_ListBox_Clear ctrl` | `AUBlockTool_Final.lsp:11` |
| `dcl_LISTBOX_ADDLIST ctrl <list of strings>` | `AUBlockTool_Final.lsp:12` |
| `dcl_ListBox_GetCurSel ctrl` → index | `AUBlockTool_Final.lsp:31` |
| `dcl_ListBox_GetText ctrl index` → string | `AUBlockTool_Final.lsp:32` |
| handler `(nSelection sSelText)` | `OpenDCL Tutorial.txt:343` |

`Clear` **then** `AddList` is the vendor's own idiom, and it is not decoration:
`AddList` appends, exactly like `ListView-AddColumns`, so a refill without the
`Clear` stacks the previous target's rows under the current one.

**A List Box has no columns** — fake them with `pfset:pad`, as
`pflabel:rd-fill` already does for the modal run dialog. Alignment is only
approximate while `pfp:skin` paints a proportional font over every control.

### A list's selection comes from its event — with one trap

Measured off the Studio Events panel, 2026-07-30. The vendor's own description,
which is the authority here:

> For a **single** selection list, `ItemIndexOrCount` is the **index** of the
> newly selected item, and `Value` is the **item text**. For a **multiple**
> selection list, `ItemIndexOrCount` is the **number** of selected items, and
> `Value` is an **empty string**.

So the same handler means two different things depending on a Studio property,
and **neither half is checkable from LISP**. The trap is the multi-select case:
it reports *how many* rows are selected and never *which*, so an event-only
design cannot build a selection list — the exact thing multi-select would be
turned on for. Enumerating selected rows needs a getter that is still unproven;
`C:PFPAPI` with `*LIST*` is the safe way to look for one.

**Consequence:** treat a list as single-select unless something has proven
otherwise, and re-read this row before changing the control's selection mode —
flipping that property in Studio silently changes what the handler receives.

For a **List Box** this matters less than it looks: `GetCurSel` / `GetText` let
you read the selection at the moment you need it, so prefer that over trusting
a remembered event argument. Enumerating *several* selected rows is still
unproven — `GetCurSel` is singular, and `C:PFPAPI *LIST*` is the safe way to
look for a sibling that returns a set.

`Control_GetValue` / `SetValue` is a **generic** accessor for controls carrying
a `Value` property — sliders and check boxes. There is no `dcl-OptionList-*` or
`dcl-CheckBox-*` family; eight such names were probed and none exists.

Both spellings resolve — `dcl-Control-GetValue` and `dcl_Control_GetValue`.
Hyphens are what this suite uses; the vendor samples are written with
underscores.

### `0` is TRUE in AutoLISP

`GetValue` is numeric, so an unticked Check Box answers `0` — and only `nil` is
false in LISP. Written the obvious way:

```lisp
(if (dcl-Control-GetValue ctrl) T nil)      ; WRONG -- always T
(/= 0 (fix (dcl-Control-GetValue ctrl)))    ; right
```

Read the obvious way, `chkbxZoom` reports ON permanently and the zoom parade
cannot be turned off.

### Never probe a setter

Getters degrade to `nil` (plus a dialog). **Setters do not degrade at all** —
`dcl-Control-SetValue` on an Option List raised the modal on every palette
open until the call was removed. Discover with `C:PFPAPI`, which reads the
symbol table and calls nothing.

**A control's default state is a Studio setting, not a runtime call.**

---

## 5. Rules that outrank convenience

**A handler is modeless.** No `command`, `getpoint`, `entsel`, `getstring`,
`start_dialog` or undo group, ever. Work that writes goes through `pfp:defer`
into a real command context. See the palette README's defer channel.

**Nothing that prompts is safe while the palette is open.** A modeless form
interrupts a command-line read — `C:PFPAPI`'s first version asked for a filter
with `getstring` and was cancelled mid-read by a palette click:

```
Function cancelled :error#2
```

Diagnostics that prompt must take their input another way.

**`OnInitialize` fires before the window is realized.** Data written there does
not paint. It is for `AddColumns` and nothing else — and `AddColumns` is
additive, so calling it from a refresh stacks duplicate columns. Data fill
belongs in `pfp:refresh`, after `dcl-Form-Show` returns.

**The Carlson APIs are not loaded in a handler.** `pf:run-command` calls
`pf:load-apis` at every command prologue, but a modeless read never goes
through that wrapper — anything reaching a centerline dies with
`bad function: CF:ROAD_API`. Call `pf:load-apis` first; it is two catch-wrapped
`scload` calls, idempotent, and writes nothing.

**Runtime formatting does not survive a toggle.** `Close` destroys the
controls; the next open rebuilds them from the `.odcl`. That is why `pfp:skin`
runs on every open.

**After any Studio save, `PFPRELOAD`.** It re-reads the `.odcl` — and **only**
the `.odcl`. New LISP needs:

```lisp
(load (strcat *pftools-dir* "pfpalette/pfpalette.lsp"))
```

Editing a `.lsp` and running `PFPRELOAD` tests the *old* code against the new
form, which is its own confusing failure.

---

## 6. Checklist — wiring one new control

1. **Studio → Events tab**, tick the event. Read the template `defun` at the
   bottom of the window, or *Tools → Write Events to Lisp File → Add to File*
   into a scratch file. **Copy the argument list exactly.**
2. Write the handler in `pfpalette.lsp` with that name and that arity. Keep the
   body to recording state or calling a read; anything that writes defers.
3. Save the project → `PFPRELOAD` → `(load …/pfpalette.lsp)`.
4. Click the control. Nothing happening means the event is unticked **or** the
   arity is wrong — check the command line for `too many arguments`.
5. Never add a value getter without checking §4 first.

### Prefer the event over a getter

Dispatch on what the event hands you. `pfp:opt-item` reads nothing from its
control: `*pfp-opt-vals*` remembers what `SelChanged` last reported. That is
stateful, but it is the only Option List route that does not raise a dialog,
and it removes an index-base question entirely.

### Prefer the caption over the index

`*pfp-opt-captions*` matches item captions by wildcard rather than trusting an
index:

```lisp
("optLabel" ("*STRUCT*" . 0) ("*INVERT*" . 1) ("*CROSS*" . 2))
```

A caption cannot be off by one, and a pattern survives a typo or re-word — the
`.odcl`'s captions are not reliable to the character (`btnClear` reads
`CLear`). An unmatched caption is named by `PFPCTL` and fixed by adding a
pattern, not by changing code. The index is kept as a fallback;
`*pfp-opt-base*` is **0**, measured.

---

## 7. Diagnostics

| Command | Answers |
|---|---|
| `PFPAPI` | **What `dcl*` functions does this build register?** `atoms-family` filtered — a symbol-table read, calls nothing, always safe. Start here. |
| `PFPCTL` | What have the Option Lists reported, and what does the Check Box read? Never probes an Option List. |
| `PFPDIAG` | Which control **names** resolve in the loaded project? |
| `PFPPROBE` | Which **setters** work on a Label? |
| `PFPTREES` | Runtime rects — is one control covering another? |
| `PFPDETAIL` | Fill `detailsList` without the event, to bisect an empty panel. |
| `PFPDBMOD` | Did anything write to the drawing? The write-free contract as a delta. |

A control symbol that the loaded project never defined **evaluates to `nil`
rather than erroring** — AutoLISP returns `nil` for an unbound symbol. A call
on `nil` then does nothing and says nothing. That is why `pfp:caption` names
the miss instead of trusting the call, and why "the label is blank" was once a
silent failure.

---

## 8. What is still unmeasured

- Whether an Option List can be **written** at all (its default item is set in
  Studio; no runtime setter is known and probing for one raises a dialog).
- Whether `Font` / `Font Size` are valid on an Option List, Check Box or Frame.
  `pfp:skin` writes them in the default `'font` mode and no dialog has been
  reported — good evidence, not proof.
- `dcl-Form-SetBackColor` reports `no such function` on this build; the form
  background is therefore unpainted and the correct name is unknown. `PFPAPI`
  with `*FORM*` would settle it.
- Whether `Close` and `Size`, ticked in Studio with no handler defined, are
  harmless. Believed yes; never confirmed.
- ~~Whether a List View's SELECTION can be read.~~ **ANSWERED 2026-07-30 — via
  the EVENT, not a getter.** See §3 and §4. What is *still* unmeasured is
  narrower: **whether the selected rows of a MULTI-select List View can be
  enumerated at all.** The event gives only a count there, and no getter is
  attested. `C:PFPAPI` with `*LIST*` answers it from the symbol table, calling
  nothing — **do not probe a live control**, that is the call class that raises
  the uncatchable modal. This is what now gates `Label Selected`
  (PALETTE-LAYOUT §6).
- `dcl-Form-Resize` — **`C:PFPSCALE` only, and deliberately.** Documented for a
  form, so it cannot raise the property-not-found modal; still wrapped in
  `pfp:try` because a missing *function* is a failure it can have.
  **It cannot beat `Min Width` / `Min Height`** — the runtime clamps up to the
  floor — it cannot exceed `Max`, and it does not size a **docked** palette,
  whose width belongs to the dock. A `pfp:size-to-design` called it on every
  open for part of 2026-07-30 and was **deleted the same day**: the palette
  opened too big because Studio's `Min Width` exceeded its `Width`, and a
  runtime call cannot argue with a floor. **A form-rect complaint is a Studio
  answer** — and note there is no form-size *getter* (`dcl-Form-GetWidth` does
  not exist), so LISP cannot even read the rect it would be correcting.
