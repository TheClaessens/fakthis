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

**Draft**:
A Ticket-in-progress inside Fakthis, before Submit. The Draft is the only draft state there is; Jira has none.
_Avoid_: pending ticket, unsaved ticket

**Submit**:
The act of creating or updating the Jira issue from a Draft. Immediate — there is no queue and no approval step.
_Avoid_: push, publish, sync

**Scope**:
What the Ticket requires — the thing that must be built. Only ever supplied by the PM. Fakthis may ask about missing Scope but must never fill it in. For a Bug, Scope is expressed as the reproduction path and the gap between expected and actual, so inventing a repro step or a suspected cause is the same violation as inventing a requirement.
_Avoid_: requirements, the ask

**Context**:
What a person who knows this project would already know — domain vocabulary, epic placement, related ticket keys, naming conventions. Supplied freely by the Catalog. The line between Context and Scope is the project's central rule.
_Avoid_: background (when you mean this specifically)

**Material**:
The raw input that produced the Scope: client emails, support tickets, screenshots, screen recordings. Media Material is attached to the Jira issue; text Material is distilled into the description and the raw stays on the machine.
_Avoid_: attachments (that word means only the Jira-side files), sources, evidence

**Definition of Done**:
The checklist closing every Ticket description, mirroring the deliverables already stated above it. Never introduces new Scope.
_Avoid_: acceptance criteria, DoD in prose (fine as a heading), success criteria

### The app

**Project**:
A Fakthis-local workspace mapped 1:1 to a Jira project key. Holds its Drafts, its Material, and its Catalog.
_Avoid_: workspace, board, space

**Catalog**:
The Project's local cache of its Jira history — epics, recent ticket titles and summaries — pulled so the agent can supply Context. Not a Jira mirror and not browsable.
_Avoid_: index, cache, sync, backlog

**Short label**:
Fakthis's own scannable name for a Ticket, held alongside the title. Proposed by the agent, always editable, and present on every Ticket regardless of Ticket type — a field that exists conditionally is worse for list views and duplicate matching than a little redundancy. Exists because a Story title begins "As a...", which makes it useless for both.
_Avoid_: slug, nickname, summary

**Completeness marker**:
The Jira label plus open-questions section applied when a Ticket is Submitted with the agent's questions unanswered. The section sits at the foot of the description but before the Definition of Done, which stays the closer. It warns; it never blocks Submit.
_Avoid_: quality score, validation, warning flag

**Batch**:
Several Drafts produced from one brain-dump and Submitted together, with their epic and blocking relationships set. Always initiated by the PM in v1 — the agent never proposes a split.
_Avoid_: split, decomposition, breakdown
