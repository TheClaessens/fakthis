# Fakthis

Fakthis is a local desktop app for writing Jira tickets. A PM speaks or types a brain-dump, attaches the raw material that produced it, and works with an agent until the ticket is good enough for a developer to pick up. Jira is the system of record; Fakthis is not a second ticket store.

## Language

### The work

**Ticket**:
A single unit of work as it exists in Jira. Never a Fakthis-local object — once it is a Ticket, it lives in Jira.
_Avoid_: issue, story (when you mean any ticket), item, card

**Ticket type**:
Fakthis's own category for a Ticket — which template shapes it and what the description must carry. The set is fixed: **Story**, **Bug**, **Chore**. It is mapped onto whatever the Jira project happens to expose, which is always called a **Jira issue type** and never confused with this. Epic is a Jira issue type but not a Ticket type: Fakthis places Tickets under epics and does not write them.
_Avoid_: issue type (when you mean Fakthis's), kind, category, flavour

**Brain-dump**:
The PM's initial spoken or typed account of the work, before the first Generate. Later chat answers are not a brain-dump.
_Avoid_: prompt, utterance (when you mean the whole account), request

**Generate**:
The act of sending the current field to the agent so it can produce or revise a Draft — first the brain-dump, later a chat answer. Not Submit, which writes the Jira issue.
_Avoid_: run, prompt, ask the model

**Draft**:
A Ticket-in-progress inside Fakthis, before Submit. The Draft is the only draft state there is; Jira has none. It survives a restart. A create Draft stops being editable once the Jira issue exists; a rewrite is a new Draft bound to that key, with the live body as Material.
_Avoid_: pending ticket, unsaved ticket

**Submit**:
The act of creating or updating the Jira issue from a Draft. Immediate — there is no queue and no approval step. Media upload may still be in flight after the issue exists.
_Avoid_: push, publish, sync

**Scope**:
What the Ticket requires — the thing that must be built. Only ever supplied by the PM. Fakthis may ask about missing Scope but must never fill it in. For a Bug, Scope is expressed as the reproduction path and the gap between expected and actual, so inventing a repro step or a suspected cause is the same violation as inventing a requirement.
_Avoid_: requirements, the ask

**Context**:
What a person who knows this project would already know — domain vocabulary, epic placement, related ticket keys, naming conventions. Supplied freely by the Catalog and by Project terms. The line between Context and Scope is the project's central rule.
_Avoid_: background (when you mean this specifically)

**Material**:
The raw input that produced the Scope: client emails, support tickets, screenshots, screen recordings, and — on a rewrite — the live description and comments. Lives with the Draft. In a Batch, text Material is visible to every Draft's Generate; media is assigned per Draft. Media Material is attached to the Jira issue on Submit; text Material is distilled into the description and is never an attachment. After Submit, the Draft folder (and its text Material) is gone.
_Avoid_: attachments (that word means only the Jira-side files), sources, evidence

**Definition of Done**:
The checklist closing every Ticket description, mirroring the deliverables already stated above it. Never introduces new Scope.
_Avoid_: acceptance criteria, DoD in prose (fine as a heading), success criteria

### The app

**Project**:
A Fakthis-local workspace mapped 1:1 to a Jira project key. Holds its Drafts, its Material, its Catalog, and its Project terms.
_Avoid_: workspace, board, space

**Catalog**:
The Project's local cache of its Jira history — every epic's key and name, recent ticket titles, labels, and component names — pulled so the agent can supply Context. Never holds issue bodies. Not a Jira mirror and not browsable. Rows Fakthis has Submitted — create or rewrite — also keep the short label and the Ticket type, which Jira does not have.
_Avoid_: index, cache, sync, backlog

**Project terms**:
Canonical spellings of this Project's domain nouns, handwritten on the Project. Context for the agent, and the nouns the transcriber is biased to hear. Distinct from the Catalog, which is pulled from Jira. Fakthis ships none — each Project has its own list, empty by default.
_Avoid_: glossary, dictionary, custom vocabulary, jargon list

**Short label**:
Fakthis's own scannable name for a Ticket, held alongside the title. Proposed by the agent, always editable, and present on every Ticket regardless of Ticket type — a field that exists conditionally is worse for list views and duplicate matching than a little redundancy. Exists because a Story title begins "As a...", which makes it useless for both.
_Avoid_: slug, nickname, summary

**Completeness marker**:
The Jira label plus open-questions section applied when a Ticket is Submitted with the agent's questions unanswered. The section sits at the foot of the description but before the Definition of Done, which stays the closer. It warns; it never blocks Submit.
_Avoid_: quality score, validation, warning flag

**Batch**:
Several Drafts from one brain-dump, named by the PM, Submitted together. Each Draft is full — own Ticket type, chat, completeness marker. They share a proposed `blocks` order and a default existing epic; both are editable. The agent never proposes a Batch.
_Avoid_: split, decomposition, breakdown
