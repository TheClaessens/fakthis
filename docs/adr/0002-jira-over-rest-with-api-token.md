---
status: accepted
---

# Talk to Jira over REST with an API token, not MCP

The original design assumed Fakthis would connect to Jira through the Atlassian MCP server during setup, since Fakthis is an agent-driven app and MCP is the agent-native way to reach Jira. We are using the Jira Cloud REST API directly instead, authenticated with a user-supplied API token over Basic auth.

## Considered Options

**MCP (Rovo MCP Server).** Rejected on capability, not preference: its published Jira tool set has no attachment upload and no issue-link creation. Media attachments and `blocks` links between batched tickets are both settled requirements, so MCP cannot serve the write path at all. A split — read via MCP, write via REST — would mean maintaining two auth stories and two mental models to avoid writing a handful of read calls we need anyway.

**OAuth 2.0 (3LO).** Rejected as unavailable rather than undesirable. Atlassian documents `client_secret` as required at token exchange, and documents no PKCE or loopback redirect flow. A desktop app distributed to colleagues has nowhere safe to keep that secret.

**API token + Basic auth.** Chosen. It works on every endpoint Fakthis needs, requires no registered application, and is exempt from Atlassian's points-based rate limits that cap OAuth apps at a pool shared across all tenants.

## Consequences

- **Faktion's admin settings are invisible to us and must be queried, never assumed.** Attachment limits, whether attachments are enabled, available issue types and required fields, and per-project create permissions all vary. `attachment/meta` and `createmeta/{project}/issuetypes` are cheap, need no elevated permission, and turn invisible configuration into checkable values.
- **v1 posts wiki markup to the v2 endpoint rather than building ADF.** Jira v3 requires ADF, there is no Markdown conversion endpoint, and Atlassian ships builders only. This is a deliberate deferral: when ADF becomes necessary, it is a known and bounded piece of work.
- **Attachment upload is a separate step after the issue exists**, and is retryable, so a large video cannot fail a Submit.
- **Editing a ticket notifies its watchers.** `notifyUsers=false` is ignored without admin permission, which makes rewriting a colleague's ticket socially visible by construction.

Full research with citations: `.scratch/fakthis/research/02-jira-integration-surface.md`. Decision ticket: https://github.com/TheClaessens/fakthis/issues/3
