# Implementing a Fakthis window ticket

Paste-able prompt for #29–#40, the tickets that build the Fakthis window. One ticket per
fresh context window, blockers first.

## The prompt

> Implement issue #NN in this repo.
>
> Read first, in this order: `gh issue view NN --comments`; the parent spec issue #14;
> `docs/fakthis-v1.md` for the sections that ticket names; `CONTEXT.md` for every noun you
> are about to type; `docs/adr/` for anything you are tempted to argue with; and
> `Prototype/FINDINGS.md` for why the window has the shape it has.
>
> Then read `docs/agents/implement-ui-ticket.md` — the invariants, the seam, and the house
> rules below — and follow it.
>
> Build only what #NN's acceptance criteria ask for. When every box is genuinely ticked,
> run `/code-review` against the branch point, commit, and close the issue with a comment
> saying what shipped and anything you learned that the spec should carry.

Replace `NN`. Nothing else changes between tickets.

## Window invariants

Settled by the UI-shell prototype and folded into the spec by #29. They are decisions, not
preferences: do not re-open them, and do not quietly violate one to make a ticket easier.

1. **One window, three columns**: rail, Draft, conversation. Create, Batch and Rewrite are
   not modes — they are what the **rail** holds. The Draft and conversation columns keep
   their shape across all three, which is why the Draft is designed once.
2. **Before Generate there is only the front door**: one field sized to a spoken dump,
   Material as chips **on** the composer, and Generate. Submit is **absent, not disabled** —
   a disabled Submit still answers "can I submit yet?"; absence never raises the question.
   No Ticket type control (the agent infers type at Generate; a control pre-empts the
   proposal). No conversation column, and no collapsed spine either.
3. **The Draft column is bounded with a fixed footer.** Submit and the rewrite diff must be
   reachable at any window height and any description length. This is the single constraint
   that chose the window shape; everything else was downstream of it.
4. **Signals are two classes, never one list.** Field signals (structural check, the
   Definition of Done offer) anchor at the field they concern. Draft signals (catalog
   refresh failure, oversize Material, failed uploads) rest as gutter marks.
5. **The gutter is the resting state; the panel displaces, never overlays**, and its height
   follows its content. A panel that covers the Draft is the modal you were avoiding.
6. **A duplicate is a conversation event that leaves a gutter mark.** Never a signal row,
   never on screen in two places at once.
7. **The conversation column collapses to a spine.** Rewrite opens with it collapsed —
   Update does not require Generate.
8. **In Rewrite the live body and comments sit in the rail, beside the Draft.** Above is not
   next to: above pushes the Draft down and still loses the diff below the fold.
9. **The sibling list *is* the `blocks` chain** — one control carrying short label, Ticket
   type, epic, chain position and completeness, reordered in place. Not a list plus a strip.
10. **Ticket type renders inline with the short label** once a Draft exists. They are the
    two things checked first.
11. **The voice status strip renders on the field receiving the take**, not spanning the
    window, where it reads as an app status bar instead of "this field is listening".
12. **The Definition of Done offer sits above the description and re-arms** after a later
    hand-edit.
13. **The text-Material provider disclosure is setup-time only.** It has no place in the
    Draft UI; every attempt to put one there was noise.

## The seam

`Session` is the actor and the only owner of state. The window sends intents and renders
`state()`. It never keeps a second copy of the Draft, and it never reimplements a rule that
belongs behind the actor — if a ticket seems to need one, the gap is in `Session` and the
fix goes there.

Logic tests attach at `Session`, with the fakes the test target already has. Layout is not
unit-tested: build it, run the app, and look at it. If you cannot judge a criterion without
seeing it, run the app rather than reasoning about it.

## House rules

- **Vocabulary is `CONTEXT.md`.** Ticket, Ticket type, Draft, Scope, Context, Material,
  short label, Catalog, Project terms, Batch. The avoid-lists in that file are binding in
  code, in comments, and in UI strings.
- **Never invent Scope.** It applies to the app and to you: if a ticket is underspecified,
  ask, or state the assumption in the closing comment. Do not fill the gap silently.
- **Do not relitigate ADRs.** Native Swift on Apple Silicon, Jira over REST, local
  transcription on the ANE, Fakthis owns its ticket types, shallow Catalog with no agent
  Jira tools. If one genuinely blocks the ticket, stop and say so — that is a new ADR, not
  an implementation decision.
- **Stay inside the ticket.** Do not build the next surface because the layout suggests it.
  A ticket that could absorb its successor should say so in its closing comment instead.
- **`Prototype/` is a record, not code.** #40 retired the target and its Swift sources;
  `FINDINGS.md` and the screenshot folders stay as the reasoning the window's shape came from.
  Do not add to them, and do not treat a screenshot as newer than the app.
- **No new dependencies** without saying why in the closing comment.

## Order

The frontier is whatever has no open blocker: `gh issue view NN --json title` plus the
`blocked_by` dependency list, or the graph in #14. #29 gates everything. #29 is
documentation — an ADR and spec edits — so drive it with `/domain-modeling` rather than
`/tdd`. After it, #30 and #31 are independent and can run in either order. The app target
does not exist until #31, so nothing that draws pixels can start before it.
