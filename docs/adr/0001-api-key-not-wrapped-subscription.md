---
status: accepted
---

# Reach the model by API key, not by wrapping a Claude subscription

Fakthis is a local app whose users already pay for Claude subscriptions, so the obvious move is to drive a locally installed, already-authenticated Claude Code as a subprocess and pay nothing per ticket. We are not doing that. Fakthis owns its own agent loop and calls a model API with a user-supplied key, behind a provider-agnostic seam.

## Considered Options

**Wrapping a Claude subscription via `claude -p`.** Mechanically this works — verified: with inherited environment and no TTY it returns clean JSON, and `--session-id`/`--resume` maintains multi-turn state across processes with automatic prompt caching. It was rejected for two reasons. First, the legal position is *conditional* rather than permissive: Thomas is on a Team plan governed by Anthropic's Commercial Terms, which carry no automation clause, and the Claude Code legal page carves out an end user signing in to the unmodified binary with their own subscription — but that permission evaporates at user #2, since a PM on a Pro plan falls under the Consumer Terms, which do ban automated access. A permission that expires precisely as the app succeeds is a bad foundation. Second, `--bare` is the officially recommended scripting mode, never reads OAuth credentials or the keychain, and is slated to become the default for `-p`.

**API key.** Chosen. At roughly 1–7 cents per ticket depending on model tier, the cost the subscription path was meant to avoid does not exist at this scale.

## Consequences

- **Process spawn is not a runtime requirement.** This is the surprising part and the reason to write it down: an early draft of the design ruled out PWA and treated native Swift as painful *because* of the subprocess assumption. That constraint is gone. The runtime is now decided by transcription and Jira access instead.
- **Fakthis owns the loop**, rather than being a UI over someone else's agent session. It controls its own prompt prefix, retries, caching strategy, and transcript storage.
- **The model is swappable by design.** Provider choice should be settled by a ticket-quality bake-off, not by price.
- **Key distribution becomes a real problem at user #2.** One personal install with one key is fine; a distributed desktop app carrying an API key is not. Deferred, not solved.

Full research with citations: `.scratch/fakthis/research/01-agent-backend.md`. Decision ticket: https://github.com/TheClaessens/fakthis/issues/2
