---
status: accepted
---

# Fakthis is one window, in the Rail shape

The UI-shell prototype asked what the Fakthis window is, and the answer is not a preference. Fakthis is **one window**: a left rail, a bounded Draft column with a fixed footer, and a conversation column. Create, Batch and Rewrite are not modes of that window; they are what the rail holds. Two constraints settle it, and they settle the same way.

## Considered Options

**Separate windows (one vertical scroll each).** Rejected. The three surfaces are never usefully seen at once — you do not rewrite while batching. The only capability multi-window would buy is two Drafts side by side, and §11 already forbids that ("No gallery"). What it costs is a Project-home surface, window management, and a duplicated field, for no remaining argument.

**A single scroll.** Rejected by Rewrite. §12 requires a diff against the live body visible on that screen at Update. In one scroll the diff is structurally below the fold: any content above it can grow, so no amount of ordering can *guarantee* the diff sits next to the button that writes. Only a bounded Draft column with a fixed footer can promise that.

**One window, two panes, surfaces as a toolbar segmented control.** Rejected by Batch. §11 says the Batch screen *is* the editor. Bolting a sibling list onto Create as a fourth column leaves the conversation hollow, and Batch still looks like Create plus a list.

**One window, Rail shape.** Chosen. Rewrite gets the live body and comments in the rail, the diff at the foot of the Draft, and Update directly beneath — guaranteed at any height. Batch gets the sibling list *as* the rail, and the Draft and conversation columns do not change at all.

## Consequences

- **The Draft is designed once.** Its column and the conversation column keep their shape across Create, Batch and Rewrite. The rail is what changes.
- **Before Generate there is no rail**, so there is no Batch or Rewrite surface to hang off it. Those two are toolbar buttons until a Draft exists. The window itself is the front door: field, Material, Generate.
- **No gallery is what kills multi-window**, not a taste for fewer windows. Once two Drafts cannot sit side by side, separate windows buy nothing the Rail does not already have.

Prototype and findings: `Prototype/FINDINGS.md`. Decision ticket: https://github.com/TheClaessens/fakthis/issues/29
