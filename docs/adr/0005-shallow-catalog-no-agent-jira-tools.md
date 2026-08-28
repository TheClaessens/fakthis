---
status: accepted
---

# The Catalog is a shallow stuffed snapshot; the agent has no Jira tools

The Catalog is the feature that makes Fakthis better than the skill rather than merely faster, so the obvious move in an agent-driven app is to give the agent Jira tools and let it fetch whatever Context it wants. We are not doing that. v1 stuffs a **shallow snapshot** — epic names, recent titles, labels, components — into the system prompt, and Fakthis itself fetches the one issue being rewritten. The agent cannot `GET` another ticket's body, which is how Scope would leak in.

## Considered Options

**Deep catalog (full bodies, maybe comments).** Rejected. Three hundred descriptions are ~120K tokens, which blows the cost model that made the API-key path cheap and, more importantly, puts other tickets' Scope in front of the agent on every Generate. Embeddings over full bodies are already out of scope for v1.

**Shallow snapshot plus agent fetch tools.** Rejected for the leak, not for capability. REST can fetch one issue cheaply; the standing Context/Scope rule cannot survive an agent that is free to read FAK-231's description and copy from it. Duplicate and related matching run against the local snapshot in Fakthis, not as an agent search.

**Shallow snapshot, stuffed, no agent Jira tools.** Chosen. ~17K tokens, cacheable as a stable prefix. Rewrite obtains one full body because Fakthis fetched it when the PM pointed at a ticket, and that body arrives as session input — not as Catalog content. Comments stay out of the Catalog entirely.

## Consequences

- **Jira's `summary` is the title.** There is no one-line synopsis to pull. Generating one at refresh time would be silent invention, so the Catalog does not.
- **Epic descriptions stay out.** They are usually the Scope of the epic; stuffing them into every Draft is the Context/Scope leak in a different costume. Epic *names* are Context and are included, every epic, always.
- **After Submit, insert locally.** JQL is eventually consistent; a refresh that waited on search would drop the issue Fakthis just wrote. Local insert is also how the **short label** — which Jira does not have — lands on Catalog entries Fakthis originated.
- **Project terms are a sibling of the Catalog, not a row in it.** Handwritten canonical spellings live on the Project. They are Context for the agent and the seed of the transcriber's boost list, which also projects epic and component names from the Catalog. An empty list means biasing stays off.
- **Unreachable Jira is not a failed Generate.** Serve the last pull. An empty Catalog (new Project, or never pulled) is a normal state: Generate runs, tickets sound like the skill, no fake history.

Decision ticket: https://github.com/TheClaessens/fakthis/issues/7
