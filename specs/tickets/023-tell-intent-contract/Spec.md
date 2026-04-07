# Spec: Tell Intent Contract

## User Stories

### US-1: Distinguish notifications from response-seeking inter-agent messages (Priority: P1)

**As a** Murmur agent author, **I want** `tell` to express whether a message is one-way or expects follow-up behavior, **so that** agents can coordinate intentionally instead of relying on prompt conventions.

**Independent test**: Read this ticket's proposed contract and verify it clearly distinguishes `notify` from response-bearing intents such as `request` and `delegate`.

### US-2: Define a complete lifecycle for inter-agent exchanges (Priority: P1)

**As a** Murmur maintainer, **I want** the `tell` contract to cover the main semantic modes of inter-agent communication, **so that** notifications, requests, delegations, handoffs, replies, and status messages follow one stable vocabulary rather than ad hoc conventions.

**Independent test**: Read the intent matrix and verify it covers one-way notifications, response-seeking messages, ownership-oriented messages, replies, and status-oriented follow-ups.

### US-3: Keep communication intent separate from delivery mechanics (Priority: P1)

**As a** Murmur architect, **I want** the `tell` contract to model communication semantics rather than idle-versus-busy routing details, **so that** ingress delivery policy and inter-agent meaning remain separate and maintainable.

**Independent test**: Verify the spec states that ingress still owns ask-versus-steer or inject routing, while the new field only defines exchange intent and reply expectations.

### US-4: Keep intent advisory and fully asynchronous (Priority: P1)

**As a** Murmur maintainer, **I want** `intent` to remain an advisory contract rather than an enforced protocol, **so that** Murmur can add useful communication semantics now without adding exchange tracking or blocking behavior.

**Independent test**: Verify the spec explicitly states that Murmur will not track whether recipients honor the stated intent and that `tell` remains asynchronous regardless of the chosen intent.

## Acceptance Criteria

- [ ] The proposal recommends `intent` as the field name instead of `type` and explains why that name is the better semantic fit.
- [ ] The proposal defines a closed initial intent taxonomy for `tell` consisting of `notify`, `request`, `delegate`, `handoff`, `reply`, `ack`, `progress`, `complete`, `decline`, `error`, and `cancel`.
- [ ] The proposal makes `intent` required and does not introduce a backward-compatible omission path.
- [ ] The proposal models `intent` as a real closed enum at the tool schema layer rather than as a free-form string.
- [ ] The proposal defines the expected follow-up behavior for every intent, including when a response is required or not required.
- [ ] The proposal states that `tell` remains asynchronous and that response-bearing intents do not make the originating tool call block awaiting a downstream reply.
- [ ] The proposal states that Murmur will not track or enforce whether the recipient behaves according to the expressed intent in the initial scope.
- [ ] The proposal treats `intent` as prompt-level guidance for the recipient agent rather than as a tracked exchange state machine.
- [ ] The proposal states that delivery mechanics such as idle fresh-run starts versus busy `steer` or `inject` follow-up remain owned by ingress and are not encoded by `intent`.
- [ ] The proposal clearly distinguishes `delegate` from `handoff` by describing delegation as a bounded work request and handoff as a transfer of conversational initiative or ownership.
- [ ] The intent matrix is phrased in direct LLM-facing language so it can be copied into the `tell` tool description with minimal or no rewriting.
- [ ] The proposal uses an HTML comment envelope that MDEx omits from rendered output so the LLM sees tell metadata while the user sees only the human-facing message body.
- [ ] The proposal states that YAML front matter is not used because MDEx does not suppress it in rendered output.
- [ ] The proposal scopes markdown rendering to tell-generated messages and keeps direct human-authored messages as raw text.
- [ ] The proposal keeps the enum exhaustive at the protocol layer without introducing domain-specific values for every business verb.

## Proposed Contract

### Recommended Field Name

Use `intent`.

`type` is too generic in a codebase that already has signal types, message kinds, and source kinds. `intent` communicates that the field exists to describe the exchange semantics of a `tell`, not its transport or storage representation.

### Required Enum Shape

`intent` should be required.

At the tool boundary, `intent` should be a string-valued enum constrained to the approved intent set. In the action schema, this should be expressed as a closed enum validation rather than as an unconstrained string parameter.

### Initial Non-Goals

The initial contract should not add:

- runtime tracking of whether a response ever arrives
- protocol enforcement that a `request`, `delegate`, or `handoff` must be answered
- synchronous waiting for another agent's reply
- exchange identifiers or correlation rules unless a future ticket proves they are necessary

### Asynchrony And Delivery Semantics

- `tell` should remain an asynchronous tool call whose immediate result is delivery status, not a downstream agent's semantic reply.
- Ingress continues to choose whether a target session starts a fresh run or receives `steer` or `inject` input when already active.
- `intent` expresses why the message exists and what follow-up behavior the recipient should infer.
- Murmur does not check whether the recipient actually follows that inferred behavior.

## Recipient-Visible Format

Tell intent should be conveyed through a reserved HTML comment envelope at the top of tell-generated markdown content.

The recipient LLM sees that envelope because it is part of the raw message text. The end user does not see it because MDEx omits raw HTML comments from rendered output under the current markdown helper.

YAML front matter should not be used because MDEx does not hide it in rendered output.

This ticket should render tell-generated messages through markdown so the hidden envelope stays out of the UI, while direct human-authored messages remain raw text.

## Intent Matrix

This wording is intentionally LLM-facing so it can be copied into the `tell` tool description.

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

## Scope

### In Scope

- Defining a stable semantic field for `tell` that conveys inter-agent exchange intent
- Proposing the initial protocol-level intent taxonomy and its expected behaviors
- Making `intent` required with a closed enum validation shape
- Clarifying the boundary between communication intent and ingress delivery behavior
- Writing the intent matrix in wording suitable for direct reuse in the `tell` tool description
- Defining an MDEx-skipped HTML comment envelope for tell metadata
- Rendering tell-generated chat messages as markdown so the HTML comment envelope is omitted from user-visible output
- Keeping direct human-authored messages as raw text in this ticket

### Out of Scope

- Implementing the new `tell` contract in runtime code or UI
- Making `tell` a synchronous tool that waits for another agent's reply
- Designing domain-specific structured payload schemas for individual intents
- Changing ingress ownership of ask-versus-steer or inject routing
- Creating business-specific enum values for every possible coordination verb
- Moving direct human-authored messages to markdown rendering