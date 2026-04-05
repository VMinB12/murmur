# Research: Runtime Metadata Boundary Cleanup

## Objective

Identify the smallest architectural change that fixes the current hop-count propagation bug, makes hop-limit policy publishable and configurable, and reduces repeated metadata plumbing across ingress, runner, and programmatic message producers.

## Findings

### Canonical ingress input is now the cleanest boundary in the runtime

Ticket 012 established a clear canonical input contract in `JidoMurmur.Ingress.Input` using `content`, `source`, `refs`, and optional `expected_request_id`.

This is the cleanest Murmur-owned contract in the current delivery path. It is already the place where direct and programmatic input semantics diverge intentionally.

### Runtime metadata is still projected inconsistently after ingress

`Runner.start_run/2` builds a hand-selected tool context map while also passing the full refs map as `extra_refs`.

That means Murmur effectively has two runtime metadata paths:

- projected tool context
- raw canonical refs

Those paths overlap but are not guaranteed to stay in sync.

### The hop-depth limit is documented but not fully propagated by the runtime

`TellAction` reads and validates `hop_count`, increments it, then delivers a programmatic message. However, the next action context does not clearly derive hop depth from one explicit projection contract.

This makes the 5-hop limit more fragile than the code and specs imply.

### Hop-limit policy should be configurable before package publication

The codebase currently treats the hop limit as a fixed runtime rule. Before package publication, that should become a documented package policy with a configurable value and a stable default.

This keeps Murmur from publishing an arbitrary hardcoded limit as a de facto permanent contract.

### Hop-limit exhaustion should be an informative tool outcome, not a crash-shaped failure

When a tell is blocked by hop policy, the calling agent should receive a clear explanation that the hop limit was reached.

The runtime should not force consumers to interpret this as an opaque failure or a crash-shaped outcome. The limit is part of normal routing policy and should be surfaced as such.

### Programmatic delivery logic is duplicated

`TellAction`, `AddTask`, and `WorkspaceLive` each follow the same broad sequence:

1. build a user-visible inbound message payload
2. broadcast `MessageReceived`
3. build canonical programmatic ingress input
4. deliver through ingress

The duplication is not large, but it increases the chance that metadata fields will diverge between producers.

## Options Considered

### Option 1: Fix hop-count only

Pros:

- smallest possible change
- resolves the immediate correctness issue quickly

Cons:

- leaves the duplicated metadata boundary intact
- makes future metadata fields likely to repeat the same problem
- still leaves hop-limit policy and failure semantics underspecified for package consumers

### Option 2: Define one explicit metadata projection boundary and fix the bug within that refactor

Pros:

- addresses the immediate bug and the underlying design pressure
- reduces repeated metadata lookup and ad hoc context assembly
- gives a clear place for future workflow metadata fields
- provides one clean place to attach configurable hop policy and informative limit handling

Cons:

- slightly larger change than a one-line bug fix
- requires touching ingress-adjacent runtime code in a few places

## Recommendation

Choose Option 2.

The codebase does not need another major architecture shift, but it does need one explicit rule: canonical ingress metadata is the source of truth, and downstream runtime context is projected from it exactly once.

That is enough to keep the ingress design lean while preventing more subtle metadata bugs, while also making hop-limit policy configurable and informative before the first package release.