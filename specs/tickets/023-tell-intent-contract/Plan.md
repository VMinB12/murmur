# Plan: Tell Intent Contract

## Approach

Implement the new `tell.intent` contract as an advisory extension of `JidoMurmur.TellAction` rather than as a new delivery protocol.

The implementation should do three things:

1. Extend the public `tell` tool contract with a required `intent` enum that accepts only the intents defined in this ticket.
2. Embed the LLM-facing intent matrix directly into the `tell` tool description so the sending agent has the full semantic guidance at tool-selection time.
3. Make the selected intent visible to the receiving agent through a reserved HTML comment envelope at the top of the tell message body, and render tell-generated chat messages through markdown so MDEx omits that envelope from user-visible output while direct human messages remain raw text.

This keeps the runtime model simple: `tell` still returns only delivery status, ingress still decides idle-start versus busy `steer` or `inject`, Murmur does not attempt to verify that the receiving agent actually follows the requested behavior, and no long-lived intent metadata path is introduced in the initial slice.

## Key Design Decisions

### 1. `intent` is required and there is no compatibility fallback

All tell call sites should be updated together. We do not need a compatibility fallback for omitted `intent`, and clearing existing persisted tell history is acceptable for this change.

### 2. `intent` should be implemented as a real enum constraint

The first implementation should accept only:

- `notify`
- `request`
- `delegate`
- `handoff`
- `reply`
- `ack`
- `progress`
- `complete`
- `decline`
- `error`
- `cancel`

Using a closed set gives the tool description a stable vocabulary and lets the action reject invalid values early.

At the tool interface level this will still be represented as a JSON string parameter, but with enum constraints rather than a free-form string. In the action schema this should be expressed directly as `type: {:in, [...]}` or an equivalent closed-enum construct.

### 3. Tell metadata should use a hidden HTML comment envelope

The receiving agent reasons over raw message text. MDEx rendering happens only at the UI layer.

Because the recipient does not consume a structured tell-specific metadata channel inside its prompt context, the implementation should adopt one canonical HTML comment envelope for tell content that includes sender identity and intent. The exact string format should be concise, unambiguous, and stable across idle-start and busy-inject delivery paths.

### 4. YAML front matter is not viable, but HTML comments are

Verified MDEx behavior in this repo shows:

- HTML comments are omitted from rendered output by default.
- YAML front matter is not omitted and therefore cannot serve as a hidden envelope.

That makes HTML comments a viable transport for tell-only hidden metadata once tell messages are rendered through markdown.

### 5. Direct human messages should stay raw text in this ticket

If direct human-authored messages are also rendered as markdown, they could include HTML comments that stay hidden in the UI while remaining visible to the LLM.

To avoid creating a general hidden-input channel in this slice, the implementation should keep direct human-authored messages as raw text and scope markdown rendering to tell-generated messages only.

### 6. Delivery behavior remains unchanged

`intent` must not change:

- whether a tell is asynchronous
- whether the originating tool call waits for a downstream reply
- whether ingress uses fresh-run start, `steer`, or `inject`
- hop-limit behavior

Those semantics stay owned by existing ingress and runner code.

## Data Model And Contract Impact

This ticket affects Murmur's public tool contract, tell-message content convention, and markdown rendering behavior for tell-generated messages.

### Public tool contract

`JidoMurmur.TellAction` becomes:

- `target_agent`: required string
- `message`: required string
- `intent`: required string enum constrained to the approved intent set

The `tell` description becomes the canonical LLM-facing description of the intent taxonomy.

### Tell-message content contract

Tell-generated messages should adopt one canonical HTML comment envelope that includes sender identity and intent in a form the recipient LLM can read while the UI omits it.

This ticket does not require a new long-lived ingress metadata field for intent.

### Markdown rendering contract

Tell-generated chat messages should be rendered through the markdown renderer so the hidden HTML comment envelope is omitted from user-visible output.

Direct human-authored messages should remain raw text in this ticket.

### Compatibility policy

- All tell callers are updated together to pass `intent` explicitly.
- Existing persisted tell history may be discarded or ignored as part of rollout.
- Existing routing behavior remains unchanged.
- Existing tests and fixtures that assert the old tell text shape will need to move to the new comment-envelope format and markdown-rendered output.

## Risks And Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| The recipient still cannot reliably infer intent if intent is only stored outside the message body. | High | Put intent into the tell message body as a hidden HTML comment envelope. |
| YAML front matter leaks into rendered output. | Medium | Do not use front matter; use HTML comments only. |
| If markdown rendering later expands to direct human messages, a hidden user-to-LLM channel could be introduced. | Medium | Keep this ticket tell-only; add explicit normalization in any future human-markdown change. |
| `intent` accidentally leaks into routing logic and grows into a hidden protocol. | Medium | Keep validation and formatting in `TellAction`; do not branch ingress delivery logic on intent. |
| Public docs and generated profile examples drift from the new tool contract. | Medium | Update package README, architecture docs, and any tool-shape tests in the same change set. |
| Existing integration tests assert the legacy tell text shape. | Medium | Replace brittle legacy assertions with checks for the canonical intent-aware tell envelope and unchanged async delivery semantics. |