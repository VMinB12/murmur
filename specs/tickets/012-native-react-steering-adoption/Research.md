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
- draining busy-agent follow-up messages from `JidoMurmur.PendingQueue` into the next LLM turn via `JidoMurmur.MessageInjector`

That split matters because only the second concern overlaps with native `jido_ai` steering.

Relevant code:

- `apps/jido_murmur/lib/jido_murmur/message_injector.ex`
- `apps/jido_murmur/lib/jido_murmur/team_instructions.ex`
- `apps/jido_sql/lib/jido_sql/request_transformer.ex`

Implication: even if Murmur adopts native `steer/3` and `inject/3`, Murmur still needs request-transformer support for dynamic prompt enrichment and package-specific context injection such as SQL schema hints.

### 2. Murmur's current delivery model is session-scoped, not run-scoped

Today all inbound messages go through `JidoMurmur.Runner.send_message/3`, which:

- writes a message envelope into the ETS-backed `JidoMurmur.PendingQueue`
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

### 5. Native steering does not replace Murmur's idle wake-up semantics

This is the main limit.

Murmur's current behavior lets a `tell` or user message reach an idle target agent by queueing the message and starting a new run. Native `inject/3` cannot do that because idle targets are rejected. The same applies to any follow-up that arrives after the active run has already sealed.

This means a direct one-for-one replacement is not enough. Murmur still needs a wrapper policy:

- when the target agent is idle, start a new `ask/await` path
- when the target agent is busy, use native `steer/3` or `inject/3`
- when a busy-path control call rejects because the run just ended, fall back to a new run instead of silently dropping the message

Implication: Murmur should not blindly replace its queue with upstream steering. It should replace the busy-agent path while preserving a Murmur-owned fallback for idle and race-boundary cases.

### 6. Murmur's current message envelope is richer than upstream pending input

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
- Murmur metadata such as `interaction_id`, `kind`, `sender_name`, and `sender_trace_id` move into `extra_refs`

Implication: Murmur can adopt native steering, but it should first define a new control-input contract instead of trying to preserve the current session-envelope shape unchanged.

### 7. Adopting native steering would reduce code, but not as much as a superficial reading suggests

What Murmur could likely remove or simplify:

- custom mid-run queue draining in `MessageInjector`
- some `PendingQueue` usage and the tests that exist only to validate busy-agent injection semantics
- some bespoke runtime reasoning around how follow-up messages reach the next LLM turn

What Murmur would still own:

- direct `ask/await` orchestration for new runs
- team instruction injection
- SQL schema injection and any future package-specific request shaping
- observability and conversation metadata mapping
- idle fallback behavior and race handling around run completion

Implication: the right comparison is not "custom code versus zero code". The real comparison is "custom mid-run runtime behavior versus a thinner Murmur wrapper around native `jido_ai` control calls."

### 8. The migration surface is manageable and well bounded

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

### 9. There is already some spec and dependency drift worth capturing

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
| Keep Murmur's current PendingQueue + MessageInjector flow | No refactor now; preserves current semantics exactly | Maintains a custom runtime path that now overlaps with upstream; keeps Murmur coupled to a workaround that `jido_ai` 2.1 was designed to replace |
| Hybrid adoption: use native `steer/3` and `inject/3` for active runs, keep Murmur-owned idle fallback and request transformers | Best maintenance reduction for lowest risk; aligns with upstream runtime semantics; preserves Murmur-specific prompt shaping and wake-up behavior; enables contract cleanup | Still requires a Murmur wrapper layer; cannot delete all queueing and routing code in one pass |
| Full rewrite around native steering only, remove Murmur ingress queue entirely | Maximum upstream alignment; potentially smallest long-term runtime surface | Changes idle and burst-message semantics; requires broader redesign of ingress, observability, and race handling; not necessary to realize most of the benefit |

## Recommendation

Adopt the hybrid approach.

Murmur should switch to native `jido_ai` steering for active ReAct runs and stop treating `MessageInjector` as the primary mechanism for busy-agent follow-up delivery. That change directly advances both goals:

- it removes Murmur-owned runtime behavior that now duplicates upstream capabilities
- it lets Murmur benefit from native ReAct control semantics such as `expected_request_id`, runtime-owned per-run input queues, and upstream lifecycle events

At the same time, Murmur should not attempt a literal one-step replacement of its entire ingress path. The platform still needs Murmur-owned behavior for:

- waking idle agents
- preserving delivery across run-boundary races
- injecting workspace-specific prompt context
- mapping Murmur's interaction and tracing metadata into the upstream control-input contract

The practical target architecture is:

1. `Runner` chooses between starting a new `ask/await` run or steering an existing one.
2. `steer/3` is used for human follow-up input on an active run.
3. `inject/3` is used for inter-agent or programmatic input on an active run.
4. `MessageInjector` is split or reduced so it only handles Murmur-owned request shaping such as team instructions.
5. Murmur documents and tests a new control-input metadata contract built on `content`, `source`, and `extra_refs` instead of the current custom session-envelope assumption.

This keeps the refactor focused on the part that has become redundant while preserving the Murmur-specific behavior that upstream does not intend to own.

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