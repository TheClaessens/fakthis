---
status: accepted
---

# Fakthis owns its Ticket types, decoupled from Jira's issue types

Fakthis writes into Jira, and Jira already has issue types, so the obvious move is to read a project's issue types and template against those. We are not doing that. Fakthis has a fixed set of three **Ticket types** of its own — Story, Bug, Chore — each with its own description template and title convention, mapped onto whatever **Jira issue types** a project happens to expose at Project setup.

## Considered Options

**Template against the project's Jira issue types.** Rejected on two counts. Jira issue types are per-project and admin-configured, their names are localisable, and `hierarchyLevel`/`subtask` are the only reliable discriminators — so Fakthis cannot assume a project has a "Story" type, and the set it would be templating against is not knowable until a project is connected. More fundamentally, a Jira issue type carries no opinion about what a good description looks like, which is the only thing a template encodes. Deriving Fakthis's writing rules from an administrative taxonomy means the writing rules change when an admin edits a scheme.

**A fixed set of three, mapped at setup.** Chosen. Fakthis discovers the project's issue types, maps by name where a match exists, falls back to the project's default standard type where none does, and shows the mapping for override. It never creates a Jira issue type — it has no admin rights and should not want them.

**Epic as a fourth type.** Rejected. Fakthis places Tickets under existing epics but does not author them: an epic description is a different writing job, and nothing in the brain-dump flow produces one. This deliberately narrows the `jira-ticket-writer` skill, which creates epics on request.

## Consequences

- **Several Ticket types may map to one Jira issue type, and that is not a degraded state.** A project with a single standard type still gets three distinct templates. The template is Fakthis's business; the Jira issue type is Jira's.
- **The title convention is per Ticket type, not global.** Charting settled `As a {Persona} I want {scope} so that {problem}` as a standing rule; it is now Story-only. Bug titles state the broken behaviour, Chore titles state the action. Forcing a persona onto a dependency upgrade produces the canonical anti-pattern.
- **`Never Invent Scope` had to be restated per type rather than inherited.** For a Bug, Scope is expressed as the reproduction path and the gap between expected and actual, so an invented repro step is the same violation as an invented requirement — and an invented root cause is worse, because it sends the developer somewhere specific. "Functional, not technical" narrows to Story and Bug, since chores are technical by nature.
- **Type inference is not Scope invention.** The agent reads the type from the brain-dump and declares it rather than asking, because asking is the friction the app exists to remove. Classifying what the PM said is a different act from filling in what they did not say, and the two look adjacent enough that the distinction needs writing down.
- **Adding a fourth type is now a deliberate act with a cost**: a template, a title convention, a mapping rule, and a line in the structural check. That friction is the point — it is what stops the type set drifting toward Jira's.

Decision ticket: https://github.com/TheClaessens/fakthis/issues/5
