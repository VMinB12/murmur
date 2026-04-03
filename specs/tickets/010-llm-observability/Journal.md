# Journal: LLM Observability & Tracing

## 2026-04-03

- Reviewed the first implementation slice in Phoenix after replacing AgentObs.
- Observed a drift between the earlier ticket intent and the current rendered result: the trace view exposed only summary `input.value` and `output.value` text on the agent turn, while the earlier LLM-oriented view had surfaced structured input messages.
- Refined the ticket contract so Phoenix message-oriented rendering is now explicit: LLM child spans must preserve ordered input conversations and structured assistant output messages, including assistant tool calls and tool-role messages where applicable.
- Kept the root turn span as a summary-oriented trace node in the plan and decisions to avoid duplicating long conversations at multiple levels.
- Added `data-contract.md` as the ticket-local OpenInference export contract, using the provided Python attribute reference as the vocabulary baseline and narrowing it to the Murmur span kinds and Phoenix rendering needs relevant to ticket 010.
- Confirmed the latest Phoenix result still shows only the root turn span because the live `jido_ai` ReAct runtime does not expose a usable public child-span lifecycle for LLM and tool execution, even though it tracks `llm_call_id`, `tool_call_id`, and internal runtime events.
- Recorded an upstream-ready issue draft in `github-issue-jido-ai-react-runtime-child-spans.md` rather than hot-patching `jido_ai`, since the missing observability surface is in the dependency runtime itself.