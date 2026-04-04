# Data Contract: LLM Observability & Tracing

## Purpose

This document defines the export contract for ticket 010.

It translates the OpenInference attribute model into the subset Murmur will emit for agent-turn, LLM, and tool spans so Arize Phoenix can render traces correctly.

This is the normative contract for:

- which attributes Murmur emits
- which span kinds carry which data
- how chat conversations are flattened into indexed OpenInference message attributes
- which Murmur-specific metadata is added on top of the OpenInference surface

The Python constants supplied during specification are the reference vocabulary. Murmur does not need to emit every available OpenInference attribute immediately, but any emitted attribute should follow the names and semantics defined here.

## Contract Principles

1. Root agent-turn spans are summary-oriented.
2. LLM spans are the canonical detailed message view.
3. Tool spans are the canonical detailed tool execution view.
4. Phoenix rendering is part of the contract, not an accidental by-product.
5. Structured chat data takes precedence over flattened text summaries when both are available.

## Supported Span Kinds

| Span kind | OpenInference value | Purpose |
|---|---|---|
| Agent turn | `AGENT` | One executed react loop owned by `Runner` |
| LLM call | `LLM` | One model invocation inside a turn |
| Tool call | `TOOL` | One tool execution inside a turn |

## Global Attribute Contract

These attributes are shared across multiple span kinds when the data exists.

| Attribute | Required | Notes |
|---|---|---|
| `openinference.span.kind` | Yes | One of `AGENT`, `LLM`, `TOOL` |
| `session.id` | Yes | Phoenix session grouping key. Direct user chat reuses a discussion-scoped `murmur.interaction_id` while the conversation remains active, then rolls to a new interaction after the configured inactivity timeout; cross-agent or workflow messages use an explicitly propagated `murmur.interaction_id` |
| `input.value` | Conditional | Summary text only; not the canonical structured conversation view |
| `input.mime_type` | Optional | Use `text/plain` for summaries, `application/json` only when exporting a serialized JSON object |
| `output.value` | Conditional | Summary output only; not sufficient on its own for LLM spans |
| `output.mime_type` | Optional | Same rule as `input.mime_type` |
| `metadata` | Optional | JSON-stringified metadata when a generic metadata payload is needed |
| `tag.tags` | Optional | Reserved for categorical tags |
| `user.id` | Optional | Not yet required for ticket 010 |

## Murmur-Specific Metadata

These keys are outside the core OpenInference vocabulary but are part of Murmur's trace contract.

| Attribute | Required | Purpose |
|---|---|---|
| `murmur.agent_id` | Yes on agent, llm, tool | Concrete agent session id |
| `murmur.agent_name` | Yes on agent, llm, tool | Human-readable agent display name |
| `murmur.workspace_id` | Yes on agent, llm, tool | Workspace correlation key |
| `murmur.request_id` | Yes on agent, llm, tool | One react-loop request id |
| `murmur.interaction_id` | Yes on agent, llm, tool when available | Cross-agent workflow correlation key |
| `murmur.triggered_by_trace_id` | Optional on agent | Originating trace id for idle-started work |
| `murmur.sender_name` | Optional | Human-readable source of a steering or injected message |
| `murmur.injected_message_count` | Optional on agent | Number of messages injected during an active turn |
| `murmur.llm_call_id` | Yes on LLM | Correlates ReqLLM, streaming signals, and final response |
| `murmur.tool_call_id` | Yes on tool | Correlates tool start and tool result |
| `murmur.llm.thinking_content` | Optional on LLM | Captured reasoning/thinking content when surfaced by the model/runtime |
| `murmur.message.kind` | Optional event attribute | Distinguishes `direct`, `steering`, or future message classes |

## Agent Turn Span Contract

Agent-turn spans are for trace boundaries and quick scanning. They are not the primary place for full message history.

### Required Attributes

| Attribute | Notes |
|---|---|
| `openinference.span.kind = AGENT` | Required |
| `session.id` | Phoenix grouping key. Direct user turns default to the current discussion interaction id and roll to a new interaction after inactivity; cross-agent or workflow turns use an explicit propagated interaction id |
| `murmur.agent_id` | Agent session id |
| `murmur.agent_name` | Display name |
| `murmur.workspace_id` | Workspace correlation |
| `murmur.request_id` | Unique per executed turn |
| `murmur.interaction_id` | Shared across related multi-agent work when available |

### Optional Summary Attributes

| Attribute | Notes |
|---|---|
| `input.value` | Summary text for the drained message batch |
| `output.value` | Summary text for the turn result |
| `murmur.message_count` | Number of messages drained into the turn |
| `murmur.injected_message_count` | Number of injected messages |
| `murmur.triggered_by_trace_id` | For idle-started cross-agent work |
| `murmur.sender_name` | For externally triggered turns |

### Event Contract

Injected messages should be recorded as events on the agent-turn span with:

- `murmur.message.kind`
- `murmur.interaction_id`
- `murmur.sender_name`
- `murmur.sender_trace_id`
- `murmur.message.content`

## LLM Span Contract

LLM spans are the canonical detailed conversation spans.

### Required Attributes

| Attribute | Notes |
|---|---|
| `openinference.span.kind = LLM` | Required |
| `llm.model_name` | Model identifier |
| `llm.provider` or provider-equivalent metadata | Preferred when available |
| `llm.system` | Provider/system family when known |
| `gen_ai.system` | Keep when Phoenix/OpenInference tooling already expects it |
| `gen_ai.request.model` | Preserve current compatibility field |
| `session.id` | Phoenix grouping key. Direct user turns default to the current discussion interaction id and roll to a new interaction after inactivity; cross-agent or workflow turns use an explicit propagated interaction id |
| `murmur.agent_id` | Agent session id |
| `murmur.agent_name` | Display name |
| `murmur.workspace_id` | Workspace correlation |
| `murmur.request_id` | Parent turn request |
| `murmur.llm_call_id` | Request-local LLM call correlation |

### Required Conversation Rendering Attributes

LLM spans must preserve chat conversations using indexed message attributes rooted at:

- `llm.input_messages.N.*`
- `llm.output_messages.N.*`

Phoenix should be able to reconstruct the conversation from these keys alone.

### Input Message Shape

For each input message at index `N`, emit:

| Attribute pattern | Required | Notes |
|---|---|---|
| `llm.input_messages.N.message.role` | Yes | `system`, `user`, `assistant`, `tool`, or other supported role |
| `llm.input_messages.N.message.content` | Conditional | Plain text content when available |
| `llm.input_messages.N.message.name` | Optional | Message or function name |
| `llm.input_messages.N.message.tool_call_id` | Optional | For tool-role messages tied to a call |
| `llm.input_messages.N.message.function_call_name` | Optional | For function-style message formats if needed |
| `llm.input_messages.N.message.function_call_arguments_json` | Optional | JSON string arguments for function-style messages |

If the message contains tool calls, emit indexed tool call data beneath:

| Attribute pattern | Required | Notes |
|---|---|---|
| `llm.input_messages.N.message.tool_calls.M.tool_call.function.name` | Yes for tool call entries | Tool/function name |
| `llm.input_messages.N.message.tool_calls.M.tool_call.function.arguments` | Optional | JSON string arguments |
| `llm.input_messages.N.message.tool_calls.M.tool_call.id` | Optional | Stable tool call id if available |

### Output Message Shape

At least one assistant output message must be materialized on every successful LLM span.

For each output message at index `N`, emit:

| Attribute pattern | Required | Notes |
|---|---|---|
| `llm.output_messages.N.message.role` | Yes | Usually `assistant` |
| `llm.output_messages.N.message.content` | Conditional | Assistant text content when available |
| `llm.output_messages.N.message.name` | Optional | Assistant/function name when applicable |

If the assistant message contains tool calls, emit:

| Attribute pattern | Required | Notes |
|---|---|---|
| `llm.output_messages.N.message.tool_calls.M.tool_call.function.name` | Yes for tool call entries | Tool/function name |
| `llm.output_messages.N.message.tool_calls.M.tool_call.function.arguments` | Optional | JSON string arguments |
| `llm.output_messages.N.message.tool_calls.M.tool_call.id` | Optional | Stable tool call id if available |

### Summary And Compatibility Attributes

These are still useful, but secondary to the structured message contract.

| Attribute | Required | Notes |
|---|---|---|
| `input.value` | Optional | Summary of latest or effective user-visible prompt content |
| `output.value` | Optional | Summary of assistant text content |
| `gen_ai.response.finish_reasons` | Optional | Finish state |
| `llm.latency_ms` | Optional | Current Murmur compatibility field |
| `llm.token_count.prompt` | Optional | Prompt tokens |
| `llm.token_count.completion` | Optional | Completion tokens |
| `llm.token_count.total` | Optional | Total tokens |
| `gen_ai.usage.input_tokens` | Optional | Compatibility field |
| `gen_ai.usage.output_tokens` | Optional | Compatibility field |

### Streaming Rule

During streaming, Murmur may accumulate deltas incrementally, but the final exported LLM span must satisfy the output-message contract as though the assistant message had been available atomically.

That means:

- streamed text is accumulated into `llm.output_messages.0.message.content`
- streamed tool-call metadata is preserved if the final turn contains tool calls
- `output.value` may mirror the final assistant text, but it does not replace the structured output message

## Tool Span Contract

Tool spans represent concrete tool execution, not the assistant's decision to request a tool.

### Required Attributes

| Attribute | Notes |
|---|---|
| `openinference.span.kind = TOOL` | Required |
| `tool.name` | Tool/function name |
| `session.id` | Phoenix grouping key. Direct user turns default to the current discussion interaction id and roll to a new interaction after inactivity; cross-agent or workflow turns use an explicit propagated interaction id |
| `murmur.agent_id` | Agent session id |
| `murmur.agent_name` | Display name |
| `murmur.workspace_id` | Workspace correlation |
| `murmur.request_id` | Parent turn request |
| `murmur.tool_call_id` | Tool call correlation id |

### Optional Attributes

| Attribute | Notes |
|---|---|
| `tool.parameters` | JSON string schema or invocation parameter payload when available |
| `tool.id` | Tool result id corresponding to the tool call |
| `input.value` | Encoded tool arguments |
| `output.value` | Encoded tool result |
| `llm.latency_ms` | Compatibility duration field |
| `error` | Boolean error marker |
| `error.message` | Error details |

## Attribute Families Deferred For Now

The Python reference includes a much larger OpenInference surface. Murmur is not required to emit all of it in ticket 010.

These families are explicitly deferred unless later implementation work makes them necessary:

- embedding attributes
- retriever and reranker attributes
- prompt registry attributes (`prompt.vendor`, `prompt.id`, `prompt.url`)
- multimodal content arrays beyond text, image, and audio placeholders
- graph node attributes unless Phoenix visualization requires them
- full cost attributes (`llm.cost.*`) unless Murmur begins calculating provider cost data itself

## Enum And Value Contract

### OpenInference Span Kind Values

- `AGENT`
- `LLM`
- `TOOL`

Other OpenInference span kinds from the reference are reserved but out of scope for ticket 010.

### MIME Types

- `text/plain`
- `application/json`

### LLM Provider/System Values

Normalize to lowercase provider/system identifiers when known, such as:

- `openai`
- `anthropic`
- `google`
- `azure`
- `aws`
- `xai`
- `deepseek`
- `groq`

## Phoenix Rendering Requirements

For Phoenix to render the richer message-oriented UI that ticket 010 now requires:

1. LLM spans must exist as child spans, not only as attributes folded into the agent span.
2. Input conversations must be emitted through indexed `llm.input_messages.*` paths.
3. Assistant output must be emitted through indexed `llm.output_messages.*` paths.
4. Assistant tool calls must remain attached to assistant output messages.
5. Tool-role messages must remain visible in later input conversations.

If Phoenix shows only the agent-turn span's `input.value` and `output.value`, the contract is not satisfied.

## Validation Rules

An implementation satisfies this contract when all of the following are true:

1. One executed react loop produces one root `AGENT` span.
2. At least one child `LLM` span is visible when a model call occurred.
3. The `LLM` span contains ordered `llm.input_messages.*` data for the effective model conversation.
4. The `LLM` span contains at least one `llm.output_messages.*` assistant message on success.
5. Tool-calling assistant replies preserve their tool calls in output-message attributes.
6. Tool-role messages remain visible in subsequent input-message attributes.
7. Streaming responses finish with the same structured output-message shape as non-streaming responses.
8. Root `AGENT` spans remain concise summaries rather than duplicating full message history.