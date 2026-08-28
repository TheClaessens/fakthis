# Fakthis

A local desktop app for writing Jira tickets. A PM speaks or types a brain-dump, attaches the raw material that produced it, and works with an agent until the ticket is good enough for a developer to pick up.

Read `CONTEXT.md` for the domain glossary before naming anything.

## Agent skills

### Issue tracker

Issues live as GitHub issues in `TheClaessens/fakthis`, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, label strings equal to their names. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
