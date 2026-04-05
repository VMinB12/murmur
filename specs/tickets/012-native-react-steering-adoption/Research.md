# Native ReAct Steering Adoption

## Objective

Determine whether Murmur should switch from its custom pending-message injection flow to the native `steer/3` and `inject/3` controls introduced in `jido_ai` 2.1, with emphasis on two goals:

1. reducing Murmur-owned runtime code and contracts
2. aligning more closely with native `jido_ai` behavior so future upstream features are easier to adopt

This analysis assumes Murmur is still in development and can make breaking refactors where the net architecture improves.

## Findings

### 1. Murmur currently solves two different problems with one transformer

Murmur's current request transformation path is doing both of the following:

- injecting dynamic workspace and roster instructions into the system prompt via `JidoMurmur.TeamInstructions`
- routing busy-agent follow-up messages into the next LLM turn via a Murmur-owned delivery path and `JidoMurmur.MessageInjector`

That split matters because only the second concern overlaps with native `jido_ai` steering.

Relevant code:

- `apps/jido_murmur/lib/jido_murmur/message_injector.ex`
- `apps/jido_murmur/lib/jido_murmur/team_instructions.ex`
- `apps/jido_sql/lib/jido_sql/request_transformer.ex`

Implication: even if Murmur adopts native `steer/3` and `inject/3`, Murmur still needs request-transformer support for dynamic prompt enrichment and package-specific context injection such as SQL schema hints.

### 2. Murmur's current delivery model is session-scoped, not run-scoped

At the start of this investigation, all inbound messages went through a session-scoped delivery path, which:

- stored the message envelope in a Murmur-managed ETS ingress buffer
- starts a single drain loop per agent session if one is not already running
- drains queued envelopes into one `ask/await` cycle when idle
- relies on `MessageInjector` to surface queued follow-up messages during an active ReAct run

The current queue is keyed by session id, not request id. It therefore covers both:

- pre-run ingress for idle agents
- mid-run ingress for busy agents

Relevant code:

- `apps/jido_murmur/lib/jido_murmur/runner.ex`
- `apps/jido_murmur/lib/jido_murmur/pending_queue.ex`
- `apps/jido_murmur/lib/jido_murmur/tell_action.ex`

Implication: Murmur's queue currently acts as a general ingress buffer. Native `jido_ai` steering only covers the busy-agent half of that behavior.

### 3. `jido_ai` 2.1 steering is a separate control path for active ReAct runs only

In `jido_ai` 2.1, `ask/await` remains the request API. `steer/3` and `inject/3` are separate control calls that target the currently active ReAct run.

Observed upstream behavior:

- `steer/3` and `inject/3` do not create a new request handle
- both reject idle agents with `{:error, {:rejected, :idle}}`
- both can reject with `{:error, {:rejected, :request_mismatch}}` when `expected_request_id` does not match the active run
- accepted input is queued in a per-run `PendingInputServer`
- queued input is drained into `AIContext.append_user/3` before LLM steps and also after a tentative final answer if pending input exists
- queued input is best-effort only and can be dropped if the run seals before it is drained

Relevant upstream code:

- `deps/jido_ai/lib/jido_ai/reasoning/react.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/pending_input.ex`
- `deps/jido_ai/lib/jido_ai/pending_input_server.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex`
- `deps/jido_ai/guides/user/request_lifecycle_and_concurrency.md`

Implication: upstream now provides a native mid-run control queue, but not a general-purpose Murmur ingress queue.

### 4. Upstream steering overlaps strongly with Murmur's custom mid-run queueing

The overlap is real and substantial. Murmur's custom path currently exists largely because older `jido_ai` could not add user-style messages to an already-running ReAct loop.

That gap is now closed upstream.

What native `jido_ai` now gives Murmur for free:

- a runtime-owned queue scoped to the active ReAct request
- explicit busy versus idle rejection semantics
- optional request correlation via `expected_request_id`
- native lifecycle handling at the ReAct runtime layer instead of a custom transformer hook
- event emission when queued input is actually injected into the run

Implication: keeping Murmur's custom busy-agent injection path as the primary implementation would duplicate functionality that now exists natively upstream.

### 5. Native steering does not replace Murmur's delivery protocol

This is the main limit.

Native `steer/3` and `inject/3` only solve the in-flight part of delivery. They do not answer who decides whether a new input should become:

- a fresh `ask/await` run
- a `steer/3` call against the current run
- an `inject/3` call against the current run

Murmur still needs one coordination point that owns that decision.

The important distinction is that this coordination point should not be a semantic mailbox or product-level queue. It should be a per-agent ingress coordinator actor that serializes the delivery protocol.

That actor receives canonical ingress input and then decides:

- if the agent is idle, start a new `ask/await` run immediately
- if the agent is busy, route the input through `steer/3` or `inject/3`
- if the active run changed while the decision was in flight, re-read current state and retry against the new reality

This is different from Murmur's earlier custom delivery design:

- the current queue is a first-class session-level ingress buffer that feeds both idle and busy delivery
- the proposed coordinator is just the single actor that owns routing decisions so callers do not make stale ask-versus-steer choices outside the actor boundary

Implication: Murmur should not keep a semantic ingress queue as the main abstraction. It should replace it with a single ingress coordinator actor that delegates actual in-flight queueing to `jido_ai` and only retains transient actor-mailbox buffering as an implementation detail.

### 6. The actor model removes races only when one actor owns the whole protocol

At first glance it may seem like the actor model already makes these races impossible because an agent processes messages sequentially. That is only true for decisions made inside the same actor.

The race Murmur needs to solve lives outside the agent when multiple producers independently decide whether to call `ask`, `steer`, or `inject` based on a stale snapshot of the agent state.

Examples:

- two producers both observe an idle agent and both choose `ask`
- a producer observes an active request, chooses `steer`, and the run finishes before the call is handled

In both cases the agent itself remains perfectly sequential and internally consistent. The race exists because the routing decision happened outside the actor that owns the runtime state.

The single ingress coordinator actor fixes this by making one actor own the whole delivery protocol for a session.

Implication: the best long-term design is not "no Murmur coordination". It is "one Murmur coordination actor per session, but no separate semantic queue abstraction."

### 7. Murmur's current message envelope is richer than upstream pending input

Murmur uses a message envelope that includes:

- `id`
- `content`
- `role`
- `kind`
- `interaction_id`
- `sender_name`
- `sender_trace_id`

Upstream pending input items support:

- `id`
- `content`
- `source`
- `refs`
- `at_ms`

That is enough to carry the same information, but not in the same shape.

The most natural contract mapping is:

- `content` stays `content`
- visible origin semantics move into `source`
- Murmur metadata such as `interaction_id`, `sender_name`, `sender_trace_id`, workspace causation, and any delivery annotations move into `refs`
- any optional run correlation moves into `expected_request_id`

The long-term-benefit approach is to make Murmur's canonical ingress input structurally match `jido_ai`'s control payloads as closely as possible:

- `content`
- `source`
- `refs`
- `expected_request_id` when relevant

Any Murmur-specific data should live inside `refs` rather than in a parallel envelope shape.

Implication: Murmur should retire the current custom session-envelope contract in favor of a jido_ai-aligned ingress input contract.

### 8. Adopting native steering would reduce code, but not as much as a superficial reading suggests

What Murmur could likely remove or simplify:

- custom mid-run queue draining in `MessageInjector`
- some older custom-delivery usage and the tests that exist only to validate busy-agent injection semantics
- some bespoke runtime reasoning around how follow-up messages reach the next LLM turn

What Murmur would still own:

- a per-session ingress coordinator actor that owns delivery decisions
- direct `ask/await` orchestration for new runs
- team instruction injection
- SQL schema injection and any future package-specific request shaping
- observability and conversation metadata mapping
- race handling around run completion

Implication: the right comparison is not "custom code versus zero code". The real comparison is "session queue plus transformer workaround" versus "single coordinator actor plus native jido_ai control path."

### 9. The migration surface is manageable and well bounded

The main places coupled to the current design are:

- `apps/jido_murmur/lib/jido_murmur/runner.ex`
- `apps/jido_murmur/lib/jido_murmur/pending_queue.ex`
- `apps/jido_murmur/lib/jido_murmur/message_injector.ex`
- `apps/jido_murmur/lib/jido_murmur/tell_action.ex`
- `apps/jido_murmur/lib/jido_murmur/composable_request_transformer.ex`
- `apps/jido_sql/lib/jido_sql/request_transformer.ex`
- agent profile modules in `apps/murmur_demo/lib/murmur/agents/profiles/`
- runner and transformer tests in `apps/jido_murmur/test/` and `apps/murmur_demo/test/`

This is a meaningful refactor, but it is not spread randomly across the entire umbrella.

### 10. There is already some spec and dependency drift worth capturing

The workspace is already locked to `jido_ai` `2.1.0` in `mix.lock`, while app dependency declarations still say `~> 2.0` and architecture docs still describe the ecosystem as `jido_ai ~> 2.0`.

Relevant files:

- `mix.lock`
- `apps/jido_murmur/mix.exs`
- `apps/jido_sql/mix.exs`
- `specs/Architecture/jido-murmur.md`

Implication: if Murmur decides to rely on `steer/3` and `inject/3`, the code and specs should explicitly document `jido_ai` 2.1 as a meaningful architectural dependency rather than treating it as an incidental lockfile update.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Keep Murmur's previous runtime workaround + MessageInjector flow | No refactor now; preserves current semantics exactly | Maintains a custom runtime path that now overlaps with upstream; keeps Murmur coupled to a workaround that `jido_ai` 2.1 was designed to replace |
| Caller-side optimistic routing with direct `ask` when idle and `steer` or `inject` when busy | Smallest immediate code surface; no new Murmur process | Pushes retry and race handling into every caller; stale state decisions remain possible outside the actor boundary; weaker long-term architecture |
| Single ingress coordinator actor with native `ask` or `steer` or `inject` dispatch | Best long-term ownership boundary; actor model cleanly owns the delivery protocol; removes semantic session queue while keeping coordination deterministic; aligns the input contract to jido_ai | Introduces a new per-session coordinator component and requires a deliberate runtime refactor |

## Recommendation

Adopt the single ingress coordinator actor approach.

Murmur should switch to native `jido_ai` steering for active ReAct runs and replace its current session queue plus transformer workaround with a per-session single ingress coordinator actor. That change best advances both goals:

- it removes Murmur-owned runtime behavior that now duplicates upstream capabilities
- it lets Murmur benefit from native ReAct control semantics such as `expected_request_id`, runtime-owned per-run input queues, and upstream lifecycle events
- it gives Murmur one clear ownership boundary for delivery decisions instead of spreading ask-versus-steer logic across callers
- it aligns Murmur's ingress data contract to the structure that `jido_ai` already uses

The platform should not keep a Murmur-owned semantic mailbox. Instead it should keep only these Murmur-owned responsibilities:

- a per-session actor that decides whether an input becomes `ask`, `steer`, or `inject`
- preserving delivery across run-boundary races through retry from the coordinator actor
- injecting workspace-specific prompt context
- mapping Murmur's interaction and tracing metadata into a jido_ai-shaped control-input contract

The practical target architecture is:

1. All producers send canonical ingress input to one per-session ingress coordinator actor.
2. The coordinator starts `ask/await` immediately when the target agent is idle.
3. The coordinator uses `steer/3` for human-visible busy-run follow-up input.
4. The coordinator uses `inject/3` for inter-agent or programmatic busy-run follow-up input.
5. If runtime state changes while delivery is in flight, the coordinator re-reads state and retries from the new truth instead of relying on a session queue.
6. `MessageInjector` is split or reduced so it only handles Murmur-owned request shaping such as team instructions.
7. Murmur standardizes on a jido_ai-aligned ingress input contract built around `content`, `source`, `refs`, and optional `expected_request_id`.

This keeps Murmur's architecture actor-native, reduces maintenance burden, and makes upstream jido_ai evolution the default path instead of something Murmur has to work around.

## References

- `apps/jido_murmur/lib/jido_murmur/runner.ex`
- `apps/jido_murmur/lib/jido_murmur/pending_queue.ex`
- `apps/jido_murmur/lib/jido_murmur/message_injector.ex`
- `apps/jido_murmur/lib/jido_murmur/tell_action.ex`
- `apps/jido_murmur/lib/jido_murmur/team_instructions.ex`
- `apps/jido_murmur/lib/jido_murmur/composable_request_transformer.ex`
- `apps/jido_sql/lib/jido_sql/request_transformer.ex`
- `apps/murmur_demo/lib/murmur/agents/profiles/general_agent.ex`
- `apps/murmur_demo/lib/murmur/agents/profiles/arxiv_agent.ex`
- `apps/murmur_demo/lib/murmur/agents/profiles/sql_agent.ex`
- `apps/murmur_demo/test/murmur/agents/message_injector_test.exs`
- `apps/murmur_demo/test/murmur/agents/runner_test.exs`
- `deps/jido_ai/lib/jido_ai.ex`
- `deps/jido_ai/lib/jido_ai/agent.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/pending_input.ex`
- `deps/jido_ai/lib/jido_ai/pending_input_server.ex`
- `deps/jido_ai/lib/jido_ai/reasoning/react/runner.ex`
- `deps/jido_ai/guides/user/request_lifecycle_and_concurrency.md`