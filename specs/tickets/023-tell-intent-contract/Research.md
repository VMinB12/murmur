# Research: Tell Intent Contract

## Objective

Define a stable inter-agent communication contract for `tell` that can express response expectations and broader coordination semantics as advisory intent hints, without conflating communication intent with Murmur's ingress delivery behavior or introducing stateful reply tracking, while determining whether tell-only markdown rendering can hide tell metadata from the UI but still expose it to the LLM.

## Findings

### Current `tell` is a fire-and-forget notify path

- `JidoMurmur.TellAction` currently accepts only `target_agent` and `message`.
- The current architecture and package docs describe `tell` as fire-and-forget inter-agent messaging.
- The tool returns an immediate delivery outcome, not a downstream reply from the target agent.
- The current behavior maps cleanly to a future `notify` intent.

### Delivery mode and communication intent are different concerns

- `JidoMurmur.Ingress` and its per-session coordinator already own idle-versus-busy delivery behavior.
- The target session may start a fresh run when idle or receive `steer` or `inject` follow-up input when busy.
- The new field should not encode transport or delivery mode. It should only express why the sender is communicating and what exchange behavior is expected.

### Initial scope should not track whether intent is actually followed

- The user-facing need is for one agent to convey intent to another agent, not for Murmur to police whether the recipient behaves accordingly.
- It is acceptable for an agent to send a `request` and never receive a follow-up message.
- The initial implementation should therefore treat `intent` as advisory guidance interpreted by the LLM and prompts, not as a state machine Murmur enforces.
- The initial implementation should therefore treat `intent` as advisory guidance interpreted by the LLM and prompts, not as a state machine Murmur enforces.
- If Murmur later needs reliable multi-step protocol behavior, correlation and exchange state can be added as a separate follow-on design.

### Jido.Action can enforce a closed enum directly

- `Jido.Action` schemas support NimbleOptions enum validation through `type: {:in, [...]}`.
- That means `intent` does not need to be a free-form string with manual validation.
- At the tool boundary this still appears as a string-valued JSON parameter, but with enum constraints rather than an unconstrained string type.

### MDEx can hide tell metadata when it is encoded as an HTML comment

- Murmur's markdown helper currently calls `MDEx.to_html!/1` with default options.
- In MDEx, raw HTML is omitted by default.
- Verified behavior in the app environment:
	- `<!-- murmur: intent=request sender=Alice -->\nHello` renders as `<!-- raw HTML omitted -->\n<p>Hello</p>`, which means the comment is not visible in the UI.
	- YAML front matter such as `---\nintent: request\n---` does not disappear; it renders as a thematic break and heading content.
- Therefore, an HTML comment is a viable hidden envelope for tell metadata when tell messages are rendered through markdown, but YAML front matter is not.

### Keeping direct human messages as raw text avoids the hidden-channel risk

- If direct human-authored user messages are rendered as markdown with the same MDEx defaults, users could also include HTML comments that the UI hides while the LLM still sees them.
- That would create a prompt-visible but user-invisible channel for direct human input.
- Keeping direct human-authored messages as raw text avoids introducing that channel in this ticket.
- Therefore, markdown rendering should be scoped to tell-generated messages only.

### `type` is too overloaded for this boundary

- Murmur and Jido already use `type`, `kind`, `source.kind`, and signal types in multiple places.
- `mode` would collide conceptually with ingress delivery mode.
- `intent` is more precise because it answers why this message exists and what behavioral contract it opens.

### The core enum should be exhaustive at the semantic layer, not the business layer

- The contract should cover all generic inter-agent communication intents Murmur needs.
- It should not create a new enum value for every business verb such as review, approval, escalation, or ping.
- Business-specific meaning should stay in message content or future structured payloads layered on top of a stable protocol-level intent taxonomy.

### `delegate` and `handoff` communicate different ownership expectations

- `delegate` means "please do this piece of work for me" while the sender still implicitly owns the broader thread or objective.
- `handoff` means "you take the lead from here" and signals an ownership transfer at the conversational level.
- Even though Murmur will not enforce either behavior initially, the distinction is still useful guidance for prompt interpretation.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Keep a binary split such as `notify` versus `request` | Smallest surface area and directly answers the immediate "response expected" question | Under-specifies delegation, handoff, progress, cancellation, and failure-oriented communication; likely to fragment quickly into ad hoc conventions |
| Add a broad `type` enum | Leaves room for more than two behaviors | `type` is too overloaded in a codebase that already uses type and kind across multiple boundaries |
| Introduce an advisory `intent` field with a broader semantic taxonomy | Separates communication semantics from delivery mode, supports richer prompt guidance, and avoids premature protocol enforcement | Gives less machine-verifiable structure than a tracked exchange model, so behavior depends on prompt quality and LLM cooperation |

## Recommendation

Choose the third option.

Use `intent` as the field name and treat it as an advisory semantic contract for `tell`. Keep `tell` fully asynchronous: the originating tool call should still return a delivery outcome rather than block awaiting another agent, and Murmur should not track whether the recipient actually follows the expressed intent. Make `intent` a required closed enum at the tool schema level, expose it to the recipient through a reserved HTML comment envelope that MDEx omits from rendered output, render tell-generated messages through markdown, and keep direct human messages as raw text.

## Proposed Intent Matrix

This wording is intentionally written so it can be copied into the `tell` tool description with little or no rewriting. The wording is normative for the LLM, even though Murmur does not enforce compliance in code.

| Intent | Use when | Recipient should |
|--------|----------|------------------|
| `notify` | You only need to inform another agent. | Treat the message as one-way information. No response is required. |
| `request` | You need information, analysis, or a decision from another agent. | Send a response. |
| `delegate` | You want another agent to complete a bounded piece of work while you remain responsible for the broader goal. | Send a response and, if you accept the work, carry it out. |
| `handoff` | You want another agent to take over ownership or lead the next phase of work. | Send a response and, if you accept the handoff, act as the new owner or lead. |
| `reply` | You are answering a previous `request`, `delegate`, or `handoff`. | Treat the message as the requested answer or result. |
| `ack` | You want to confirm receipt, understanding, or acceptance. | Treat the message as confirmation, not a final result. |
| `progress` | You want to report ongoing work that is not yet finished. | Treat the message as an interim update. |
| `complete` | You want to report that requested, delegated, or handed-off work is finished. | Treat the message as the final completion or result. |
| `decline` | You cannot or will not take on the requested or delegated work. | Treat the message as an explicit refusal. |
| `error` | You attempted the work but failed to complete it. | Treat the message as a failure report. |
| `cancel` | You want another agent to stop, ignore, or abandon previously requested work. | Stop or abandon that work if possible. |

## References

- `specs/PRD.md`
- `specs/Architecture/README.md`
- `specs/Architecture/data-contracts.md`
- `specs/Architecture/jido-murmur.md`
- `apps/jido_murmur/lib/jido_murmur/tell_action.ex`
- `apps/jido_murmur/lib/jido_murmur/ingress.ex`
- `apps/jido_murmur/lib/jido_murmur/ingress/input.ex`
- `apps/jido_murmur/lib/jido_murmur/ingress/coordinator.ex`