# Spec: Retire Legacy UITurn Projection

## User Stories

### US-1: Canonical read-model ownership (Priority: P1)

**As a** Murmur maintainer, **I want** the canonical conversation read path to project persisted and live conversation state without depending on `UITurn`, **so that** package ownership is clear and future cleanup does not have to preserve a legacy adapter.

**Independent test**: Inspect the canonical read-model entry points and verify persisted-entry projection no longer delegates to `UITurn.project_entries/1`.

### US-2: Canonical tool-call types (Priority: P1)

**As a** Murmur maintainer, **I want** canonical turn and display types to use a tool-call struct owned by the canonical conversation namespace, **so that** read-model code does not depend on a legacy nested type.

**Independent test**: Inspect `ConversationReadModel`, `Turn`, and `DisplayMessage` and verify none of them alias or reference `UITurn.ToolCall`.

### US-3: Behavior-preserving cleanup (Priority: P2)

**As a** workspace user, **I want** the cleanup to preserve current message, actor, and tool-call rendering behavior, **so that** removing the legacy adapter does not change the visible conversation output.

**Independent test**: Run regression coverage for persisted-history projection and live turn updates and verify the rendered canonical messages remain equivalent before and after the cleanup.

## Acceptance Criteria

- [ ] `ConversationReadModel.from_entries/2` no longer delegates persisted-entry projection to `UITurn.project_entries/1`.
- [ ] Canonical conversation code no longer depends on `UITurn.ToolCall`.
- [ ] Any replacement tool-call type is owned by `jido_murmur` under the canonical conversation or display-message namespace.
- [ ] The remaining persisted-entry projection logic is colocated with the canonical conversation read boundary.
- [ ] The cleanup removes `UITurn` rather than preserving a transitional adapter or compatibility wrapper.
- [ ] If removing `UITurn` requires breaking backwards compatibility in internal APIs, the cleanup prefers the smaller long-term surface over compatibility shims.
- [ ] Tests cover persisted-history projection, tool-call reconstruction, and actor metadata preservation after the cleanup.
- [ ] Documentation reflects the removal of `UITurn` from the canonical read path if ownership or public architecture descriptions change.

## Scope

### In Scope

- Moving persisted-entry projection into canonical conversation modules
- Moving tool-call value types out of `UITurn`
- Deleting the legacy `UITurn` surface once replacement code lands
- Updating call sites, tests, and architecture docs affected by the ownership change

### Out of Scope

- Redefining canonical conversation ordering semantics beyond any minimal adjustments needed for the cleanup
- Redesigning chat rendering components
- Changing artifact-update projection boundaries