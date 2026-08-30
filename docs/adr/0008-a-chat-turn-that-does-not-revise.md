---
status: proposed
---

# A chat turn that does not revise the Draft

Chat in Fakthis runs one way. The agent asks about missing Scope, the PM answers, and the answer revises the Draft — `sendInstruction` says so in as many words, and every turn comes back as a full Draft JSON. `recordTurn` completes the shape from the other side: the agent's only voice in the transcript is its open questions, because everything else it produces is the Draft.

That holds right up until the PM asks the agent something. "What is this ticket still missing?" is not an answer, but it is sent through the only press there is, and the model has nowhere to put a reply except the fields it is allowed to return. The description is the roomiest of them. The PM asks a question and their prose is rewritten.

So the agent needs a turn that **returns prose and leaves the Draft untouched**. The decision is not whether to have one — it is who decides which kind of turn a given press is, because that is where the failure lands.

The two failures are not symmetric, and that asymmetry settles the rest of this ADR. An answer misread as a question applies nothing: the Draft is unchanged, the PM sees no revision and presses again. A question misread as an answer rewrites work the PM did not offer up. With no discard (#42) and no undo, that is the expensive direction. **The agent may reply without revising; it may never revise without being asked to.**

## Considered Options

**Prompt the model to answer in prose when the turn is a question.** Rejected. It does not change the response schema, so "answering in prose" means answering *inside* `description` — exactly the reported behaviour. The fields are the problem; instructions about how to fill them are not a fix.

**The agent classifies the turn and returns either a Draft or a reply.** Rejected as the primary mechanism, and rejected on the asymmetry above. A classifier that is wrong in the cheap direction costs a second press; wrong in the expensive direction it silently rewrites the description, which is the bug this ADR exists to close. It also puts the decision in the one place the PM cannot see or correct before it fires.

**Two presses in the composer — Answer and Ask.** Rejected. The composer already carries Speak, Send, and a Generate that swaps in for Send; §7.4 fought for Send being its own press precisely so the PM knows what a press costs. A fourth control makes the PM classify their own sentence every time, including the overwhelmingly common case where they are just answering the question above.

**One press. The agent may reply instead of revising; only the PM's own presses revise.** Chosen. `Send` keeps its meaning and its keyboard shortcut. The response gains a way to say *I have something to tell you and nothing to change* — a reply, with the Draft fields absent rather than restated. When the agent replies, the Draft is not written at all: not re-rendered, not re-persisted, not diffed. Revision stays reachable from a press the PM aimed at the Draft.

The cheap failure stays cheap: if the agent replies where the PM wanted a revision, the Draft is intact and one more press gets it. The expensive failure is structurally unavailable, because a reply carries no fields to write.

## Consequences

- **A revision is something the PM asks for.** The agent can decline to revise; it cannot revise unasked. Every seam that writes the Draft from a model response inherits this.
- **`recordTurn`'s invariant is replaced, not extended.** "The agent's turn is its open questions" stops being true. The transcript, `transcript.jsonl` and the restart path all carry a second kind of agent turn, and open questions keep their own de-duplication — an unanswered question coming back unchanged is still not a new turn.
- **A reply is never Scope.** It is conversation. It is not written into the description, the completeness marker does not read it, and nothing about it reaches Jira. This is ADR-0005's line in a new place: the agent may say what it notices; only the PM supplies what the Ticket requires.
- **`CONTEXT.md` gains a term.** The glossary names **Generate** and names the chat answer; it has no word for the PM asking or for the agent replying. The gap is real rather than a synonym for something already there, so `/domain-modeling` settles it before either name lands in code.
- **The response schema is no longer one shape.** Everything that decodes a Draft JSON has to tolerate a reply, and a reply that arrives where a Draft was required — a Generate — is a model failure, not a turn.

Reported from early use. Decision ticket: https://github.com/TheClaessens/fakthis/issues/43
