# Plan: Actor Identity And Display Projection Cleanup

## Approach

Implement ticket 015 in five layers so the actor and display boundary lands as one coherent contract rather than a series of partial renames.

1. Introduce one lightweight canonical actor model inside `jido_murmur` and project it exactly once from canonical ingress metadata and runtime context. The ingress contract from ticket 014 stays intact, but overloaded transport fields such as `sender_name` stop serving as the long-lived runtime and UI contract after that boundary.
2. Update runtime-owned consumers such as `Runner`, `MessageInjector`, programmatic delivery, and signal builders to consume explicit current-actor and origin-actor semantics while preserving observability metadata such as `interaction_id`, `sender_trace_id`, and hop depth.
3. Introduce one canonical display-message model for UI consumers and make the shared UI projection boundary responsible for producing it. `UITurn` should become the only place that translates thread entries and runtime payloads into display messages for the cleaned-up path.
4. Move label wording, grouping, and style decisions to presentation helpers in `jido_murmur_web` and `murmur_demo`. UI code should branch on canonical actor semantics rather than string heuristics such as `"You"` or content prefixes like `"[Alice]:"`.
5. Update optimistic local message creation, task and inter-agent notification rendering, documentation, and tests together so the actor/display contract changes atomically across runtime and UI.

This ticket should prefer structural clarity over compatibility shims. If older development data or fixtures need conversion, handle that once at the storage or test boundary instead of preserving runtime or UI repair logic in the shared path.

## Key Design Decisions

### 1. Keep the canonical ingress input contract from ticket 014

Do not reopen the ingress contract cleaned up in ticket 014.

`sender_name` and related fields may still arrive as part of the canonical input envelope, but Murmur should translate that transport data once into explicit actor semantics and stop reusing the transport field as a runtime and UI source of truth.

Rationale:

- keeps this ticket focused on the actor and display boundary instead of undoing ticket 014
- avoids another round of churn in ingress producers that are not part of the current problem
- gives Murmur one explicit internal projection point for cleaner semantics

### 2. Introduce one canonical actor model owned by `jido_murmur`

Define one lightweight actor representation that can express the semantics shared by runtime, observability, and UI projection: actor kind, stable identity, and current-versus-origin distinction where relevant.

Free-form display wording should not be the actor model itself.

Rationale:

- one actor concept should not be re-encoded differently in runner context, visible messages, and UI rendering
- explicit actor fields make `MessageInjector`, tell delivery, and observability easier to reason about
- the package boundary is still unpublished, so this is the right point to make the model explicit

### 3. Introduce one canonical display-message model

UI consumers should receive one primary display-message shape from the shared projection boundary, rather than a mix of thread-entry payloads, repaired maps, and view-local heuristics.

The display-message model should carry the actor semantics needed for labels, grouping, styling, and rendering of tool calls or thinking blocks without depending on mixed atom-versus-string payload access.

Rationale:

- removes repair logic from rendering components
- gives split and unified views the same source of truth
- lets host applications customize labels without changing message data contracts

### 4. Keep presentation wording at the edge

Human-facing labels such as `"You"`, `"You (human)"`, agent names, or system wording should be chosen by presentation helpers or host-facing rendering code.

The canonical actor and display-message models may expose default label inputs, but final wording and styling decisions belong at the rendering edge rather than in runtime metadata.

Rationale:

- decouples product language from runtime semantics
- makes host-app customization straightforward
- prevents style and grouping rules from depending on brittle raw string comparisons

### 5. Remove identity repair logic from the cleaned-up path

Do not preserve sender inference from formatted content or atom-versus-string payload fallback in the shared runtime-to-UI path once the new contract is in place.

If existing development fixtures or persisted local data need support during the transition, use one-time conversion, fixture updates, or reset guidance instead of permanent fallback code.

Rationale:

- fallback code would immediately weaken the value of ADR-004
- the codebase has not published this contract yet
- the current cleanup is specifically valuable because it removes ambiguous compatibility behavior

### 6. Preserve observability and inter-agent causation semantics

This ticket clarifies actor meanings; it does not remove the metadata needed for traces, causation, or inter-agent context.

Origin actor, current actor, interaction, trace, and hop semantics must remain available after the refactor under clearer names and clearer ownership.

Rationale:

- avoids regressions in debugging and conversation grouping
- keeps the identity cleanup aligned with the runtime metadata work from tickets 012 and 014

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Historical local thread data still uses old sender semantics and breaks when fallback logic is removed | Medium | Medium | Update fixtures and dev-data expectations together; if needed, add a one-time normalization step at the storage or loading boundary instead of keeping renderer fallback logic |
| Runtime refactors accidentally drop observability or inter-agent causation fields while renaming actor semantics | Medium | High | Add focused tests around current actor, origin actor, `interaction_id`, and `sender_trace_id` across metadata, tell, and projection paths |
| UI styling regresses because split and unified views previously depended on string comparisons such as `"You"` | Medium | Medium | Migrate shared styling helpers together with the display-message contract and cover both views with component and LiveView tests |
| The ticket expands into a general frontend redesign rather than a boundary cleanup | Medium | Medium | Keep layout and visual design changes out of scope; restrict the work to data contracts, rendering helpers, and their required template updates |
| The actor model becomes too abstract or too tied to one host app | Low | Medium | Keep the actor representation lightweight, package-owned, and limited to semantics already needed by runtime and UI consumers |
| Ticket 015 reopens decisions already settled in tickets 012, 013, or 014 | Low | Medium | Preserve the ingress contract, session-coordination model, and active-run steering rules; only clean up post-projection actor and display semantics |