# Fakthis v1 — functional spec

This is the destination of [Fakthis v1: chart the way to a functional spec](https://github.com/TheClaessens/fakthis/issues/1). It is sharp enough to hand to an implementation session. It is not the app.

**Terms** live in [`CONTEXT.md`](../CONTEXT.md). Use them. Do not rename them.

**Why** lives in [`docs/adr/`](adr/). Do not relitigate an ADR in implementation. Window shape is ADR-0007.

**Detail** of each decision lives on its ticket (linked from the map). This spec is the index of behaviour, not a restatement of every argument.

v1 is measured against Thomas’s current `jira-ticket-writer` skill workflow. That skill is a starting point, not a constraint. (A local copy lives under `.scratch/`, gitignored; this repo is public.) The user is Thomas, dogfooding. **PM adoption is a deferred risk, not an addressed one.**

The app is **Fakthis**. The repo directory `facthis` is a typo we are living with, not a second name.

---

## 1. Hard rules

Carry these forward unchanged.

**Context / Scope split.** Catalog and Project terms may supply Context freely (domain vocabulary, epic placement, related ticket keys, naming conventions). They may never supply Scope (what the thing must do). Vague Scope becomes a chat question or stays blank plus the completeness marker. The agent may *ask* a Scope question sourced from a Catalog title (“FAK-231 is titled similarly; is this the same work?”). It never fills Scope silently, and it cannot read another issue’s body to do so.

**Never Invent Scope.** Restated per Ticket type: for a Bug, never invent the reproduction path or the cause. Missing repro is a chat question or a blank plus the marker, never a guess.

**Functional, not technical** applies to Story and Bug. Chores are technical by nature.

**House vocabulary is Definition of Done**, never “acceptance criteria.” It mirrors the description. It never introduces new Scope.

**Title convention is per Ticket type**, not global. Story: `As a {Persona} I want {scope} so that {problem}`. Bug: the broken behaviour. Chore: the action.

**Warn, never block Submit.** Completeness marker, structural check, duplicate interrupt, oversize Material, unreachable Catalog refresh: all warn. None of them prevent Submit.

**Jira is the system of record.** Fakthis is not a second ticket store and not a Jira client.

---

## 2. Runtime

Native **Swift / SwiftUI**, **macOS**, **Apple Silicon**, **one process**. ADR-0006.

FluidAudio (Parakeet TDT 0.6B v3 on the ANE) decided it. whisper.cpp `large-v3-turbo` links as a library, bundled fallback. Models ship **in the app bundle** (budget 350 MB–1.6 GB if both engines ship) and download nothing on first run. First launch pays a one-off ANE compile delay (CoreML’s cache, not Application Support).

**Out:** PWA, Electron, Tauri, a Swift sidecar, Intel Macs, Windows, iOS.

URLSession to Jira REST. Fakthis owns the agent loop and calls a model by API key. No process spawn. No browser `fetch`.

Packaging, notarization, and how Thomas installs are **not in this spec**. One user; still fog.

### Window

One window, in the Rail shape — rail, bounded Draft column with a fixed footer, conversation column. ADR-0007. Create, Batch and Rewrite are not modes; they are what the left rail holds. The Draft and conversation columns keep their shape across all three, which is why the Draft is designed once.

The Draft column is **bounded with a fixed footer**. Submit and the rewrite diff stay reachable at any window height and any description length.

**Before Generate** there is no rail. The window is the **front door**: one field sized to a spoken dump, Material as chips on the field, and Generate. Submit is **absent**, not disabled. The Ticket type control does not exist. The conversation column does not exist — not even as a collapsed spine. Batch and Rewrite are toolbar buttons until a Draft exists.

Once a Draft exists, the conversation column is **collapsible** (it collapses to a spine). Create and Batch open it for chat. Rewrite opens with it collapsed: Update does not require Generate.

**Measure.** The Draft's text is never measured narrower than **460pt**. Below that the description wraps too narrow to read the prose a developer picks the work up from, so this is the number "bounded column" is worth: the window's minimum width leaves the Draft 636pt with all three columns open, and anything that wants width — the signal panel is the only thing that does — trades against this floor, never through it.

**Appearance.** The window renders in light *and* dark, and dark is not a repaint of light. macOS gives `windowBackgroundColor`, `controlBackgroundColor` and `textBackgroundColor` the same near-black in dark appearance, so a design that layers one on another goes flat there while reading correctly in light. The window's layering is therefore its own rule, not two AppKit colours: **the three columns are one ground, and everything that reads as a step off a column — the front door's canvas, the Draft's fixed footer, the gutter, the signal panel, a Material chip, a conversation turn, the focused sibling — is the window ground**, which carries a dark value of its own. A surface built from `windowBackgroundColor` will disappear. Judge it by running in both appearances: a screenshot in one says nothing about the other.

---

## 3. Setup and the Project list

### First launch

1. ANE compile may stall here. Show that it is happening. Do not pretend the app is ready until it is.
2. Collect, once for the app:
   - Jira Cloud site hostname
   - Jira account email (Basic auth)
   - Jira API token → **Keychain Services**
   - Model provider + model id (see §14) and API key → **Keychain Services**
3. Two Keychain items, keyed off the bundle ID: Jira token, model key. Never in files. Never compiled into the `.app`. User #2 pastes **their** keys into **their** Keychain. No packaged company key.

Credentials are **app-level**. A Project is a Jira project key on that site, not a second token.

### Adding a Project

1. PM enters a Jira project key.
2. Fakthis calls `createmeta/{project}/issuetypes`, filters on `hierarchyLevel` and `subtask` (not on names), maps Story / Bug / Chore by name where a match exists, else the project’s default standard type. **Show the mapping for override.** Fakthis never creates a Jira issue type. Three Fakthis types on one Jira type is fine.
3. First Catalog pull. Empty Catalog is a **normal state** (new Jira project, or nothing returned). Generate still runs.
4. Project terms start **empty**. Biasing stays off while empty.
5. **One warning:** text Material goes to the model provider (ADR-0001). Setup-time only — at Project confirmation. It has no place in the Draft UI. No redaction pass in v1.

### Project list

Local Projects under Application Support. Each is a folder named by its Jira key. Open one to work. There is no Jira browser, no board, no sprint list.

Epics are optional and decided **per Draft** in chat. Nothing epic-related is pinned at Project level.

---

## 4. On disk

Root: `~/Library/Application Support/Fakthis/` — not Documents, not iCloud, not the bundle.

```
Fakthis/
  settings.json                 # site, email, provider, model id — no secrets
  projects/
    FAK/
      project.json              # Ticket-type mapping, Project terms
      catalog.json
      drafts/
        {id}/
          draft.json            # type, title, short label, open questions,
                                # key if this is a rewrite
          description.md
          transcript.jsonl
          material/
      batches/
        {id}.json               # sibling draft ids, `blocks` order, default epic
```

JSON for structure, Markdown for the description. **No SQLite.** The transcriber boost list is a **projection**, not a file.

A create Draft has no key until Submit. A rewrite Draft has the key in `draft.json` from the start. Once the Jira issue exists, that folder is an **upload queue plus the key**, not an editor. When media has succeeded or the PM skips a failure, delete the folder.

Drafts persist across restarts until Submit is done. No automatic GC. Manual delete only.

---

## 5. Catalog and Project terms

ADR-0005. Shallow snapshot, stuffed into the system prompt as the cacheable prefix. **The agent has no Jira tools and no Catalog tools.**

### Snapshot

- Every epic: key, name, status. **Not** the epic description.
- The 300 most recently created issues: key, Jira issue type, title, labels, parent epic key, status, created.
- Component names, if any.

**Out:** bodies, comments, people, reporter, assignee, priority, derived synopses. Jira’s `summary` is the title; generating a shorter one at pull time is silent invention.

~17K tokens. Shape: ids then `bulkfetch`.

### Refresh

- First pull at Project creation.
- On later open: refresh in the background if the last pull is older than an hour. **Generate is never blocked on a refresh.**
- After Submit: **insert locally immediately** (JQL is eventually consistent). Pass `reconcileIssues` if a pull happens to run in the same breath; local insert is the source of truth for that moment. Keep short label and Fakthis Ticket type on that row.
- Manual refresh for tickets written in Jira itself.
- Unreachable Jira: **serve the last pull.** Never-pulled and unreachable is the empty-Catalog case. A failed refresh is a Draft signal (§9), never a block.

The Catalog is **not browsable**. It is not a UI.

### Project terms

Handwritten canonical spellings on the Project. Empty by default. Never scraped from titles. Context for the agent (same prompt, as a glossary) and the top of the transcriber boost list.

### Transcriber projection

Project terms, then epic names, then component names. **Cap 100, hard stop 230.** Not issue titles, not people, not labels. Aliases are derived mechanically (hyphens, spaces, letter-spacing) plus whatever is typed next to a handwritten term. Biasing **off** while empty.

whisper.cpp fallback: the same list packed into 223 tokens, **highest-value last** (handwritten, then epics), because it truncates from the left.

---

## 6. Voice

Voice is an **input method into the same field as the keyboard**, not a pipe into the agent. The agent never receives a take the PM has not seen. The agent does not speak back. Keyboard is always fully available.

ADR-0003 for the engine. Interaction:

| | Brain-dump | Chat answer |
|---|---|---|
| Gesture | Toggle (press to start, press to stop) | Push-to-talk (hold) |
| Path | Batch pass with the Project-terms list | Same |
| Commit | Take **appends** into the field | Take **replaces** the field |
| Then | **Generate** is a separate press | **Send** is a separate press |

No voice-activity detection (it cuts a thinking pause; it also makes auto-send feel cheap). No auto-send. No streaming path in v1 — FluidAudio custom vocabulary is batch-mode only, and jargon-term recall is the primary metric.

**Correction:** type in the field. Re-speak is clear-then-another-take. After Generate or Send, a correction is another chat turn. No “fix the transcript” mode. Do not ask the agent to guess what the PM said.

**Self-corrections stay.** “no wait, actually…” remains in the transcript.

**Status:** a visual strip on **the field receiving the take** — listening / transcribing / agent thinking / your turn. Not a strip spanning the window as an app status bar. No TTS, no earcon.

Same engine both tiers. A two-engine split only if implementation measurement says the short-answer tier fails. Thomas’s accent and short-answer jargon-term recall are unmeasured; bake-off against `.scratch/fakthis/research/03-transcription-engine.md` §5. The engine is a seam; *local, bundled, on the ANE* does not move.

Fakthis ships **no** Project terms. Canned nouns in the throwaway prototype were stand-ins.

---

## 7. Create flow

One Draft, from empty to a live Ticket.

**Before Generate** the window is the front door: field, Material, Generate — and nothing else. The field is sized to a spoken dump; Material sits as chips **on** the field. **Submit is absent, not disabled.** **The Ticket type control does not exist.** The agent infers type at Generate; a Story/Bug/Chore control over an empty field turns that proposal into a correction.

1. **Brain-dump.** Speak (toggle) or type into the field. Attach Material (drag-drop, paste, file picker). No in-app capture.
2. **Generate.** Separate press. On the front door there is nothing else to press. Agent infers Ticket type, declares it as an editable control **inline with the short label** (the two things checked first; default Story if genuinely ambiguous). Type inference is classification of what the PM said, not Scope invention. Proposes title, short label (three to six words, no “As a”, from the PM’s nouns; else the title’s scope clause — never an invented name), description against the template, open questions.
3. **Definition of Done:** a **second pass** that reads **only** the finished description. Bullet list, not a tickable Jira checklist. If the PM later hand-edits the description, offer to regenerate the Definition of Done; do not do it silently. The offer sits **above** the description — attached to what changed, not orphaned below it — and **re-arms** after a later hand-edit: choosing Keep and then editing again offers it a second time.
4. **Chat.** Agent asks about missing Scope. Answers: speak (push-to-talk) or type; **Send** is a separate press. Changing Ticket type mid-chat reshapes the Draft against the new template; Material and answers already given stay.
5. **Review.** The Draft UI is the review. Structural check warns, never blocks, never writes the Jira label. Duplicate interrupt and related list: §10.
6. **Submit.** Creates the Jira issue immediately, returns the link. No Jira-side draft. Markdown → wiki markup, posted to `/rest/api/2/issue`. Mapped Jira issue type, optional epic (`fields.parent`), completeness marker if questions remain. Then upload media as a retryable step. Then the folder is a queue, then gone. Catalog inserts the shallow row.

Video is **not** sent to the model. Screenshots are. Text Material is (and never becomes a Jira attachment).

| | Generate (model) | Submit (Jira) |
|---|---|---|
| Brain-dump, chat, Draft fields | yes | title + description + mapped Jira issue type + epic + completeness marker |
| Text Material | yes | distilled into the description only |
| Screenshots | yes | attachments |
| Video | no | attachments |
| Short label | yes (Draft + Catalog) | not a Jira field |
| Secrets | never | never |

On add of media: read `attachment/meta`. Oversize, disabled, or unsupported: **warn, keep the file, do not block Generate.** On Submit the issue still creates; files that cannot upload are skipped and said so. If upload never succeeds: Ticket is live, queue remains, PM retries or skips, then the folder goes.

---

## 8. Templates

ADR-0004. Agent emits **Markdown**, never wiki markup. Fakthis converts at Submit.

Once a Draft exists, the Ticket type control sits **inline with the short label** — the two things checked first — not as template chrome. It does not exist before Generate (§7).

**Vocabulary:** paragraphs, bold, bullet list, ordered list, links, one horizontal rule. **No headings.**

**Story.** Title `As a {Persona} I want {scope} so that {problem}`. Required: context paragraph(s) opening the description, bold nouns on first mention, related ticket keys referenced in prose. Optional: Disclaimer. Then `---` and the Definition of Done.

**Bug.** Title states the broken behaviour. Required: one-line statement of what is broken, numbered **Steps to reproduce**, **Expected** against **Actual**, **Environment**. Optional: context paragraph, Disclaimer. Then `---` and the Definition of Done.

**Chore.** Title states the action. Required: one paragraph of what and why, then the Definition of Done. Nothing else.

**Forbidden in all three:** Requirements / Technical Notes / Dependencies / Out of Scope headings, numbered acceptance criteria, priority or label metadata in the description.

---

## 9. Completeness marker and structural check

### Completeness marker

Jira label **`fakthis-open-questions`**, applied with `update.labels.add` (and removed with `update.labels.remove`) so other labels are never clobbered. Read existing vocabulary with `GET /rest/api/3/label` rather than inventing blind — Jira’s no-spaces rule returns 400.

Section: a fixed one-line preamble that tells a developer these are questions the reporter skipped, then those questions as bullets, **verbatim**. Sits at the **foot of the description but above `---`**, so the Definition of Done stays the closer.

Label and section come on **together** when unanswered questions remain, and come off **together** when none remain. Fakthis replaces `fields.description` wholesale, so removal needs no parsing.

This label is **only** for skipped questions. It never means “the agent malformed its output.”

The open-questions section **is** the warning. It is not additionally a signal row. Listing it again restates what already sits at the foot of the description.

### Structural check

Deterministic, after Generate (and before Submit):

- title matches the Ticket type’s convention
- a Definition of Done exists with at least one bullet
- no forbidden heading
- Bug carries its four labels (broken statement, steps, expected/actual, environment)
- output stays inside the Markdown vocabulary
- description fits the field cap (1 MB)

**Warns, never blocks.** Stays inside Fakthis. Never applies `fakthis-open-questions`. Never grades content quality.

### Signals

The signals are not one class.

**Field signals** — the structural check, the Definition of Done regenerate offer — are anchored at the field they concern.

**Draft signals** — a failed Catalog refresh, oversize or disabled Material, failed uploads — rest as gutter marks down the Draft edge. The gutter is the resting state. Expanding it opens a panel that **displaces** rather than covers the Draft; Submit stays reachable. The panel’s height follows its content: a single signal does not open a full-height column, and is legible from the gutter mark without opening the panel.

A duplicate is not a Draft signal row — §10. The open-questions section is not a signal — it is part of the Draft. Nothing in the gutter blocks Submit.

---

## 10. Duplicate and related

Fakthis matches **itself** against the Catalog snapshot and this Project’s local Drafts. The agent does not search.

### Duplicate

Same unit of work, **same Fakthis Ticket type**. Creating it would split the work. High bar, **one** top hit.

- Short label when it exists (Fakthis-Submitted Catalog rows, local Drafts).
- Title tokens when it does not (Jira-pulled rows).
- Type filter skipped on Jira-pulled rows if this Project’s mapping is many-to-one.
- Labels and parent epic may rank relatedness; they do not make a duplicate on their own.
- **Done** is never a duplicate interrupt (related at most).
- Batch siblings are not duplicates of each other.
- The rewrite target is excluded.

**When:** after Generate, once title + short label + type exist. Re-run if type or short label changes. Re-run at Submit. Not while they speak.

**UI:** a **conversation event that leaves a gutter mark**. When it fires it is an interrupt in the conversation — “This looks like FAK-231. Continue, or work on that Ticket instead.” Continuing collapses it to a gutter mark. Never a signal row, never rendered in two places at once. Continue is always legal. Submit is never blocked. A local Draft hit is named by short label.

**Landing:** Jira key → rewrite loop (§12). Local Draft → focus that Draft. Batch sibling → that Draft leaves the Batch first (§11), then rewrite.

### Related

Lower bar, cap three, ignorable list on the focused Draft, **default off as a write**. If the PM ticks a key, that fact goes into the next turn as Context. Fakthis does not inject sentences into the description. v1 writes **no** Jira issue links for relatedness — prose only. `blocks` links are Batch-only.

Empty Catalog or no hit: no UI. Normal.

Similarity is token overlap. Exact scoring is an implementation choice; do not add embeddings.

---

## 11. Batch

Several full Drafts from one brain-dump, named by the **PM**. The agent never proposes a Batch. Fakthis holds the grouping.

### Naming

1. In the brain-dump, before first Generate.
2. In chat, after one Draft already exists.
3. A control that does not go through the agent (minimum two named Drafts). Before Generate that control is a toolbar button — there is no rail yet.

Reading “that’s three tickets: …” into an editable list is classification, same as type inference. The list is always editable.

### Screen

The Batch screen **is** the editor: the sibling list **is** the rail, and the Draft and conversation columns do not change. One control per sibling carries short label, Ticket type, epic, chain position and completeness, reordered in place. There is no separate `blocks` strip and no gallery. Submit sits on the Batch.

Chat and voice are with the **focused** Draft only. Each Generate is told: you are Draft *i* of *N*; siblings are these short labels and types; write this one. Sibling list is Context. Scope for each Draft comes from the dump and that Draft’s own chat.

Mixed types are normal.

### Mid-chat conversion

Existing Draft becomes Draft 1. Material, chat, answers kept. **Offer to regenerate Draft 1’s description, default on.** Silent rewrite is off. Drafts 2..N Generate from the original dump plus the “that’s three” turn.

### Add / remove

Same control. Add appends an empty Draft (needs its own Generate). Remove deletes after confirm. No merge-back into one Draft. Minimum two; removing the last extra dissolves the Batch into the remaining Draft.

### Epic and links

One **existing** epic as Batch default, override per Draft. Empty is legal. Fakthis does not author epics. No Subtask type.

`blocks` in the order the PM named them: proposed, editable, clearable. Independent is one action (“no links”), not the default. If they named three and said nothing about order, follow declaration order; they can clear it. Fakthis never invents a dependency the PM did not name.

These `blocks` links are the **only** Jira issue links v1 writes (`POST /issueLink`).

### Material

Text Material is visible to every Draft’s Generate. Screenshots and video default to the focused Draft; assignable to more than one (both Jira issues get that attachment).

### Duplicate

Match per Draft, siblings excluded, **one** interrupt for the Batch listing which Drafts hit which keys.

### Submit

**One Submit for the Batch.** No per-Draft Submit. Creates in `blocks` order (blocker first), writes each link as soon as both keys exist, **stops on first failure**. Already-created siblings stay live. Remaining Drafts persist; retry the rest.

Open questions: that Draft still Submits, with its own completeness marker.

Generate failure is per Draft: that one stays, retry it, others untouched.

After every sibling exists: each folder is an upload queue, then gone. Improving one later is a rewrite, not a second Batch. A Batch is **create-only**.

---

## 12. Rewrite (improve an existing Ticket)

Paste a key. Fetch live. Body + comments are **Material**. The Draft is a **new version**, not a seeded copy of the mess. Fakthis does the `GET`; the agent has no tools.

Two loops, one flow: a dev commented on FAK-231, or a colleague’s ticket is not pick-up-able.

### Landing

“Improve existing” is a **key field**, not a browser. Duplicate interrupt as in §10. Epic keys rejected. Other-project keys rejected. 404 is an error, not a create. Unreachable Jira: no fetch, no rewrite; once fetched, Draft persists and Update retries.

A rewrite is a new Draft bound to the key. The create folder (even as an upload queue) is not the editor. A leftover create Draft must not Submit over the live issue.

### Material

Live description and comments shown readable **beside** the Draft, in the rail — never above it in a scroll. Comments: this issue only, newest first, cap 50, say so if truncated. Fakthis **never writes a Jira comment**. Existing attachments stay; v1 does not download them — add a file if the model needs to see it.

Generate is a separate press. The PM sees the Material first.

- Empty field + Generate: reshape against the template from this Material, invent no Scope.
- Typed or spoken text is the ask.

Scope sources: live body, comments, what the PM says now. Catalog titles stay Context.

### Type and title

Infer Fakthis Ticket type from the Material. Jira issue type is a hint only when this Project maps exactly one Fakthis type to it. Never ask type as the opening question. **Never change the Jira issue type.**

Propose a title against that type. One action keeps the live title. Default to the proposal. Short label always proposed. Both editable, never blocking.

### Review and stale Jira

Ordinary Draft UI. At **Update**, a diff against the fetched live body is **visible on that screen**, at the foot of the Draft column, directly above the button that writes — guaranteed by the bounded column with a fixed footer. If Jira’s `updated` is newer than the fetch: warn, offer **re-fetch** (Material refreshes, Draft stays) or proceed and clobber. Re-fetch is the default. No auto-merge.

Rewrite opens with the conversation column **collapsed**. Update does not require Generate.

Rewrite target excluded from duplicate matching.

### Update

Button: **Update FAK-231**, with a one-line note that watchers are emailed. No ownership detection. No extra modal. Create stays **Submit**.

Writes **title, description, and the completeness-marker label — nothing else.** Not epic, Jira issue type, assignee, components, or other people’s labels.

Keyboard-only is legal: Update does not require Generate.

After Update: folder is an upload queue, then gone. Catalog upserts the shallow row with short label and Ticket type — that is how a Jira-pulled row gains both.

v1 does not rewrite a Batch of existing keys.

---

## 13. Agent loop

ADR-0001. Fakthis owns the loop. Provider-agnostic seam. Default a cheap tier — `gpt-5.6-luna` or Claude Haiku 4.5 — chosen by a **ticket-quality bake-off, not by cost**. Cost is not a design constraint (~1–7 cents per ticket). Pin the alias, not a snapshot.

System prompt carries: writing rules, the Catalog snapshot, Project terms. No tools.

Transcript stored as `transcript.jsonl` on the Draft.

Retries are Fakthis’s: a failed Generate leaves the Draft, the PM retries. Nothing is lost.

---

## 14. Jira I/O

ADR-0002. **REST for everything.** User-supplied API token, Basic auth (email + token). Query limits at runtime; do not assume Faktion’s admin settings.

| Need | Call |
|---|---|
| Issue types at setup | `createmeta/{project}/issuetypes` |
| Catalog pull | `search/jql` (cursor-paged) then `bulkfetch` |
| Attachment policy | `GET /rest/api/3/attachment/meta` |
| Create | `POST /rest/api/2/issue` (wiki markup description) |
| Update | `PUT` title + description; `update.labels.add` / `remove` for the marker only |
| Epic | `fields.parent` |
| `blocks` | `POST /issueLink` |
| Attachments | after the issue exists, `X-Atlassian-Token: no-check` |
| Rewrite fetch | `GET /issue/{key}` (Fakthis, not the agent) |
| Label vocabulary | `GET /rest/api/3/label` |

`notifyUsers=false` is ignored without admin permission. Every Update emails watchers. That fact sits on the button.

Field cap: 1 MB. Check it structurally before Submit.

Markdown → wiki is a v1 shortcut. ADF is deferred; keep the Markdown vocabulary small so the converter swap stays a converter swap.

---

## 15. Failure

| Situation | Behaviour |
|---|---|
| Unreachable Jira at Catalog refresh | Serve last pull. Generate is not blocked. Empty Catalog is normal. |
| Unreachable Jira at Submit / Update | Draft stays. Retry. |
| Unreachable Jira at rewrite fetch | No rewrite until fetch succeeds. |
| Model error mid-chat | Draft stays. Retry. |
| Ticket 2 of a Batch fails to create | Ticket 1 stays live. Stop. Retry remaining. |
| Attachment upload fails | Issue exists. Queue retries or PM skips. Then folder goes. |
| Mistranscription | Type over, or clear and re-speak, **before** Generate/Send. |
| Stale Jira at Update | Warn. Re-fetch default. Or clobber. |

---

## 16. What v1 does not do

Do not add these in the implementation session. They are out of scope for this spec.

- A PM-facing ticket-quality skill for people not using Fakthis
- Agent-initiated splitting (“this ticket is too big”)
- Slack or email intake (paste covers it)
- In-app screenshot annotation (arrow / box / crop)
- Embeddings or a vector index over issue bodies
- Jira client features: boards, sprints, transitions, browsing, search, assignee, components, issue-type conversion, epic authoring
- Server, SSO, hosted database
- Process-spawn of Claude Code / wrapping a subscription
- MCP
- OAuth 3LO
- A packaged model API key
- PWA / Electron / Tauri
- Intel, Windows, iOS
- Per-Draft Submit of a Batch
- Jira issue links except Batch `blocks`
- Writing Jira comments
- Downloading existing Jira attachments as Material
- Redaction of text Material
- Auto-send of voice, VAD, streaming transcription, TTS
- Tickable Jira checklists / ADF in v1
- Learning from the delta between generated Draft and submitted Ticket
- Packaging, auto-update, notarized distribution (one user)

---

## 17. Pointers

| What | Where |
|---|---|
| Glossary | [`CONTEXT.md`](../CONTEXT.md) |
| Map | [issue 1](https://github.com/TheClaessens/fakthis/issues/1) |
| Agent backend | ADR-0001 · [issue 2](https://github.com/TheClaessens/fakthis/issues/2) |
| Jira REST | ADR-0002 · [issue 3](https://github.com/TheClaessens/fakthis/issues/3) |
| Transcription | ADR-0003 · [issue 4](https://github.com/TheClaessens/fakthis/issues/4) |
| Ticket types | ADR-0004 · [issue 5](https://github.com/TheClaessens/fakthis/issues/5) |
| Voice interaction | [issue 6](https://github.com/TheClaessens/fakthis/issues/6) · prototype on `prototype/voice-everywhere` |
| Catalog | ADR-0005 · [issue 7](https://github.com/TheClaessens/fakthis/issues/7) |
| Duplicate / related | [issue 8](https://github.com/TheClaessens/fakthis/issues/8) |
| Disk / Material | [issue 9](https://github.com/TheClaessens/fakthis/issues/9) |
| Batch | [issue 10](https://github.com/TheClaessens/fakthis/issues/10) |
| Rewrite | [issue 11](https://github.com/TheClaessens/fakthis/issues/11) |
| Runtime | ADR-0006 · [issue 12](https://github.com/TheClaessens/fakthis/issues/12) |
| Window | ADR-0007 · [issue 29](https://github.com/TheClaessens/fakthis/issues/29) · [`Prototype/FINDINGS.md`](../Prototype/FINDINGS.md) |
| Research | `.scratch/fakthis/research/` |
