# What is the Fakthis window?

Throwaway prototype, branch `prototype/ui-shell`. Three radically different window shapes bound
to the real `Session` actor, five scenes each, fifteen screenshots in `Shots/`.

```
swift run FakthisPrototype           # the window; ⌘[ / ⌘] switch variant, scene buttons drive it
swift run FakthisPrototype --shoot   # re-render Shots/
```

The variants:

| | shape | surfaces | signals |
|---|---|---|---|
| **A** Workbench | one window, two panes (conversation ‖ Draft) | segmented control in the toolbar | docked tray under the Draft |
| **B** Desk | separate windows, one vertical scroll each | a window each, opened from Project home | anchored inline at the thing they concern |
| **C** Rail | one window, three columns (rail ‖ Draft ‖ conversation) | what the left rail holds | gutter marks down the Draft edge, expand in place |

---

## The answer: one window, in Variant C's shape

Not because C is prettier — because two of the sub-questions are load-bearing and they both
rule the same way.

**Rewrite settles it.** §12 requires a diff against the live body **visible on that screen** at
Update. In a single scroll (B) the diff is structurally below the fold: `b-5-rewrite.png` has
the Update button on screen and the diff nowhere near it, and no amount of ordering fixes that
— any content above it can grow. Only a bounded Draft column with a fixed footer can *guarantee*
the diff sits next to the button that writes. `c-5-rewrite.png` shows it working: live body and
comments in the rail, diff at the foot of the Draft, `Update FAK-231` directly beneath. That
kills the one-scroll shape, and with it the main argument for separate windows.

**Batch settles the rest.** §11 says "the Batch screen **is** the editor". In C that is free:
the sibling list *is* the left rail, and the centre and right columns do not change at all
(`c-4-batch.png`). In A, Batch is the Create window with a fourth column bolted on, and the
chat column goes ~60% empty (`a-4-batch.png`) — visibly "Create plus a list". B needs a whole
header band that pushes the Draft down.

**Separate windows buy nothing.** The three surfaces are never usefully seen at once — you do
not rewrite while batching. The only thing multi-window would buy is two Drafts side by side,
and §11 rules that out explicitly ("No gallery"). B's separate windows cost a Project-home
surface, window management, and a duplicated composer, for no capability.

So: **one window. Create, Batch and Rewrite are not modes of it — they are what the left rail
holds.** The Draft column and the conversation column keep their shape throughout, which is
also why the Draft only has to be designed once.

### But steal from the other two

- **A's brain-dump field.** `a-1-braindump.png` gives the dump a tall dedicated field with
  Generate under it. B and C push it into a chat composer, where a 150-word spoken dump renders
  as one truncated line (`b-1`, `c-1`). Pre-Generate, the field is the primary object and should
  be sized like it.
- **B's chain cards.** `b-4-batch.png` makes one card carry short label, Ticket type, epic,
  chain position and completeness — the sibling list and the `blocks` strip as a single control.
  See finding 6.

---

## What the prototype changed my mind about

Folding-back candidates for `docs/fakthis-v1.md` and the UI tickets that do not exist yet.

**1. There is no pre-Generate state, and Submit is live without a Draft.**
`a-1`, `b-1` and `c-1` all show an enabled Submit against an empty Draft. §7 starts at
"brain-dump" and jumps to "Generate", and never says what the window *is* in between. It needs
a defined first state: field, Material, Generate — and nothing else. B is the sharp version of
the bug: `b-1-braindump.png` has **Generate and Submit side by side, both primary blue**, on a
blank document.

**2. "Warns, never blocks" is a placement problem, and the six signals are not one class.**
`a-3` shows the tray displaying 3 of 8. `c-3` shows all 8 but the panel *covers the Draft* —
the exact failure mode of the modal we were avoiding. `b-3` anchored inline reads best of the
three, but still loses two of eight below the fold.
The lesson is that they split in two: signals about **a specific field** (structural check, the
DoD offer) belong anchored at that field, B-style; signals about **the Draft as a whole**
(duplicate, catalog refresh, oversize Material, failed uploads) belong in a persistent gutter,
C-style. One undifferentiated list is wrong at any size. §9 and §10 currently imply one class.

**3. The completeness marker is not a warning — it is part of the Draft.**
In every variant the "open questions" signal restates the open-questions section sitting right
above it. The section itself, carrying `marked fakthis-open-questions at Submit`, is the entire
UI (`c-2-draft.png`). Listing it again as a warning is pure noise and inflates every signal
count by one. §9 should say the section *is* the warning.

**4. The duplicate interrupt has no home in a list.**
§10 calls it a "dismissible interrupt", but it is also a standing fact until dismissed, so
`c-2`/`c-3` render it twice — once in the conversation, once in the signal panel. It should be
one object: an interrupt in the conversation at the moment it fires, collapsing to a gutter mark
once continued. Not a tray row.

**5. Rewrite makes the conversation column dead weight.**
`c-5-rewrite.png`: the right third is empty, because §12 explicitly allows "keyboard-only …
Update does not require Generate". The three-column layout needs the conversation column to be
collapsible, and Rewrite should open with it collapsed.

**6. The sibling list and the `blocks` chain are the same object.**
§11 asks for a list showing "position in the `blocks` chain" *and* separately "an editable
strip". `b-4-batch.png` shows one control doing both jobs — and C's rail does it vertically with
inline arrows (`c-4-batch.png`). That is one fewer control, and it makes reordering obvious
instead of requiring you to map a strip onto a list. Spec should merge them.

**7. "Next to the editor" in §12 should be read strictly.**
B put the live body and comments *above* the Draft in the scroll: it pushed the Draft down and
still failed to get the diff on screen. C put them in the rail, beside the editor, and both fit.
Above ≠ next to.

**8. The DoD regenerate offer works, and needs no modal.** Confirmed in all three (`a-3`, `b-3`,
`c-3`) as an inline bar. Two refinements: it must sit **above** the description (attached to what
changed, not orphaned below it), and it needs to **re-arm** — right now choosing "Keep" and then
editing again should offer it a second time. §7.3 should say both.

**9. Voice status belongs on the field, not on the window.**
In A and C the strip sits over the conversation column and reads as "this field is listening"
(`a-1`, `c-1`). In B it spans the window bottom and reads as an app status bar. §6 says "a
visual strip"; it should say a strip on **the field receiving the take**.

**10. Ticket type reads better inline with the short label.**
A and C put the type control in the Draft pane header, away from the short label; B puts them
side by side (`b-2-draft.png`) and that is the better scan — type and short label are the two
things you check first. Cheap to get right before it is built.

**11. `Session.State` is missing most of what a window needs.**
I had to fake six things in the prototype layer: the **chat transcript** (Session persists one
but does not expose it — every variant needs it on screen), **voice phase**, **duplicate and
related hits**, **catalog-refresh failure**, **Batch**, **Rewrite**. Batch (#27) and Rewrite
(#26) are known. The transcript and the refresh-failure flag are not, and neither is tracked.
*(`Domain.swift` gained `DuplicateHit`/`RelatedHit` while this prototype was being built, so
§10 is already moving.)*

**12. `textMaterialWarning` has no place in the window.**
"Text Material is sent to the model provider" is set once at project confirmation. There is no
point in the Draft UI where showing it is not noise — I tried and dropped it from all three
variants. It is a setup-time disclosure and belongs in first launch, not on the Draft.

---

## What this prototype did not test

Typing and scrolling feel, dark mode, resizing below 1240pt, a Batch of more than five Drafts,
a description long enough to make the Draft column itself scroll, and the mid-chat Batch
conversion (§11). All of `Batch` and `Rewrite` state is faked in the prototype layer.

## How it is wired

Real `Session` actor, driven through `perform(_:)` with the test fakes copied into
`Prototype/Fakes.swift` (a test target is not importable from an executable target). The
bootstrap walks the real credential → project-key → confirm-project path, so every screenshot is
of a Draft that a real `Session` produced, including the real structural check. Only the
prototype-layer fakes listed in finding 11 are invented.

`ImageRenderer` cannot draw AppKit-backed controls, so every control here is hand-drawn SwiftUI
and identical in the app and in the shots. The two exceptions are `LineField` and `BodyField`,
which are a real `TextField`/`TextEditor` live and a `Text` with the same metrics under
`\.shooting`, and `Scroll`, which clips instead of scrolling under `\.shooting`.
