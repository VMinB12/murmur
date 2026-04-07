defmodule JidoMurmur.TellAction do
  @moduledoc """
  Jido Action for inter-agent "tell" communication.

  Allows an agent to send a message to another agent in the same workspace.
  Routes by target display_name. Respects the configured inter-agent hop limit.
  """

  @intents ~w(notify request delegate handoff reply ack progress complete decline error cancel)

  @description String.trim("""
  Send an asynchronous message to another agent in the workspace.

  Use this when you need to coordinate with a specific agent. `tell` always returns delivery status only. It never waits for a downstream reply.

  Choose `intent` to describe why you are sending the message:

  - `notify`: You only need to inform another agent. Treat the message as one-way information. No response is required.
  - `request`: You need information, analysis, or a decision from another agent. Send a response.
  - `delegate`: You want another agent to complete a bounded piece of work while you remain responsible for the broader goal. Send a response and, if you accept the work, carry it out.
  - `handoff`: You want another agent to take over ownership or lead the next phase of work. Send a response and, if you accept the handoff, act as the new owner or lead.
  - `reply`: You are answering a previous `request`, `delegate`, or `handoff`. Treat the message as the requested answer or result.
  - `ack`: You want to confirm receipt, understanding, or acceptance. Treat the message as confirmation, not a final result.
  - `progress`: You want to report ongoing work that is not yet finished. Treat the message as an interim update.
  - `complete`: You want to report that requested, delegated, or handed-off work is finished. Treat the message as the final completion or result.
  - `decline`: You cannot or will not take on the requested or delegated work. Treat the message as an explicit refusal.
  - `error`: You attempted the work but failed to complete it. Treat the message as a failure report.
  - `cancel`: You want another agent to stop, ignore, or abandon previously requested work. Stop or abandon that work if possible.
  """)

  use Jido.Action,
    name: "tell",
    description: @description,
    schema: [
      target_agent: [type: :string, required: true, doc: "The display name of the target agent"],
      intent: [
        type: {:in, @intents},
        required: true,
        doc: "Why you are sending this tell. Must be one of: #{Enum.join(@intents, ", ")}."
      ],
      message: [
        type: :string,
        required: true,
        doc: "The markdown-capable body to send. Murmur adds a hidden metadata envelope automatically."
      ]
    ]

  alias Jido.Tracing.Context, as: TracingContext
  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Config
  alias JidoMurmur.HiddenContent
  alias JidoMurmur.Ingress
  alias JidoMurmur.Workspaces

  @doc false
  def intents, do: @intents

  @impl true
  def run(params, context) do
    case validate_run_params(params) do
      {:ok, validated_params} -> do_run(validated_params, context)
      {:error, message} -> {:error, message}
    end
  end

  defp do_run(params, context) do
    workspace_id = context[:workspace_id]
    hop_count = context[:hop_count] || 0

    with :ok <- validate_hop_count(hop_count),
         {:ok, sender_name} <- current_actor_name(context),
         %{} = target <- Workspaces.find_agent_session_by_name(workspace_id, params.target_agent) do
      hidden_message =
        HiddenContent.wrap_markdown(params.message,
          sender: sender_name,
          intent: params.intent
        )

      case deliver_message(target, hidden_message,
             sender_name: sender_name,
             origin_actor: ActorIdentity.agent(sender_name),
             sender_trace_id: sender_trace_id(),
             hop_count: hop_count + 1
           ) do
        :queued ->
          {:ok, %{delivered: true, target: params.target_agent}}

        :agent_not_running ->
          {:error, "Failed to deliver to '#{params.target_agent}': :agent_not_running"}

        {:error, {:invalid_input, reason}} ->
          {:error, "Failed to deliver to '#{params.target_agent}': #{inspect(reason)}"}
      end
    else
      {:error, {:hop_limit_reached, max_hops}} ->
        {:ok,
         %{
           delivered: false,
           target: params.target_agent,
           blocked: :hop_limit_reached,
           hop_count: hop_count,
           hop_limit: max_hops,
           message:
             "Tell not sent: inter-agent hop limit (#{max_hops}) reached at hop #{hop_count}."
         }}

      {:error, :missing_current_actor} ->
        {:error, "Tell unavailable: missing current actor identity."}

      {:error, _} = error ->
        error

      nil -> {:error, "Agent '#{params.target_agent}' not found in this workspace."}
    end
  end

  defp validate_hop_count(hop_count) when is_integer(hop_count) and hop_count >= 0 do
    max_hops = Config.tell_hop_limit()

    if hop_count >= max_hops do
      {:error, {:hop_limit_reached, max_hops}}
    else
      :ok
    end
  end

  defp validate_hop_count(_), do: {:error, :invalid_hop_count}

  defp deliver_message(target_session, message, opts) do
    Ingress.deliver_programmatic(target_session, message,
      kind: :tell,
      via: :steering,
      sender_name: Keyword.fetch!(opts, :sender_name),
      origin_actor: Keyword.get(opts, :origin_actor),
      sender_trace_id: Keyword.get(opts, :sender_trace_id),
      refs: %{hop_count: Keyword.fetch!(opts, :hop_count)}
    )
  end

  defp current_actor_name(context) do
    case context[:current_actor] do
      %ActorIdentity{} = actor ->
        case ActorIdentity.display_name(actor) do
          name when is_binary(name) -> {:ok, name}
          _ -> {:error, :missing_current_actor}
        end

      _ ->
        case context[:sender_name] do
          name when is_binary(name) -> {:ok, name}
          _ -> {:error, :missing_current_actor}
        end
    end
  end

  defp sender_trace_id do
    case TracingContext.get() do
      %{trace_id: trace_id} when is_binary(trace_id) -> trace_id
      _ -> nil
    end
  end

  defp validate_run_params(params) when is_map(params) do
    params
    |> Enum.to_list()
    |> NimbleOptions.validate(schema())
    |> case do
      {:ok, validated_params} -> {:ok, Map.new(validated_params)}
      {:error, %NimbleOptions.ValidationError{message: message}} -> {:error, message}
    end
  end

  defp validate_run_params(_params), do: {:error, "Invalid parameters: expected a map."}
end
