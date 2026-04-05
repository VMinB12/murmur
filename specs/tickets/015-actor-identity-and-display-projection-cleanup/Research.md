# Research: Actor Identity And Display Projection Cleanup

## Objective

Identify the next simplification step after ticket 014 that will reduce semantic ambiguity in runtime context and UI message projection.

## Findings

### 1. `sender_name` still means different things in different layers

- `JidoMurmur.Ingress.Metadata.tool_context/3` writes `sender_name` for the current agent and `origin_sender_name` for the upstream sender.
- `JidoMurmur.MessageInjector` still consumes `runtime_context[:sender_name]`, so the field name hides the fact that it refers to the current agent.
- Visible message payloads and UI rendering also use `sender_name` as a display label.

This is no longer a correctness bug after ticket 014, but it remains an architectural ambiguity.

### 2. UI projection still repairs mixed or incomplete message identity

- `JidoMurmur.UITurn` falls back across atom and string payload keys.
- `JidoMurmur.UITurn.infer_sender_name/1` derives actor identity from a `"[Name]:"` content prefix.
- UI components still treat `sender_name` as both identity and final display label, which leaks formatting choices into rendering semantics.

This means the UI layer still carries compatibility logic that the runtime slice has already started removing.

### 3. Human and agent sender labels are presentation-driven rather than model-driven

- Current UI behavior distinguishes `"You"`, `"You (human)"`, and agent names in multiple places.
- Message color and label selection depend on string comparisons rather than one canonical actor model.

That works today, but it makes future host-app customization harder than it should be.

## Recommendation

Create one cleanup ticket that:

- introduces explicit actor identity semantics for runtime context and visible messages
- defines one canonical display-message shape for UI projection
- removes sender-name inference and mixed payload fallback logic from `JidoMurmur.UITurn`
- confines sender label wording to presentation helpers instead of using raw runtime fields as final UI text