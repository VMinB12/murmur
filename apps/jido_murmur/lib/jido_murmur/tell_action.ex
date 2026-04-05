defmodule JidoMurmur.TellAction do
  @moduledoc """
  Jido Action for inter-agent "tell" communication.

  Allows an agent to send a message to another agent in the same workspace.
  Routes by target display_name. Respects the configured inter-agent hop limit.
  """

  use Jido.Action,
    name: "tell",
    description:
      "Send a message to another agent in the workspace. Use when you need help from or want to communicate with a specific agent.",
    schema: [
      target_agent: [type: :string, required: true, doc: "The display name of the target agent"],
      message: [type: :string, required: true, doc: "The message to send to the target agent"]
    ]

  alias Jido.Tracing.Context, as: TracingContext
  alias JidoMurmur.ActorIdentity
  alias JidoMurmur.Config
  alias JidoMurmur.Ingress
  alias JidoMurmur.Workspaces

  @impl true
  def run(params, context) do
    workspace_id = context[:workspace_id]
    hop_count = context[:hop_count] || 0
    interaction_id = context[:interaction_id]

    with :ok <- validate_hop_count(hop_count),
         {:ok, sender_name} <- current_actor_name(context),
         %{} = target <- Workspaces.find_agent_session_by_name(workspace_id, params.target_agent) do
      prefixed_message = "[#{sender_name}]: #{params.message}"

      case deliver_message(target, prefixed_message,
             interaction_id: interaction_id,
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
      via: :steering,
      interaction_id: Keyword.get(opts, :interaction_id),
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
end
