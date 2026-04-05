defmodule JidoMurmur.Ingress.Coordinator do
  @moduledoc """
  Per-session coordinator that owns ask-versus-steer delivery decisions.
  """

  use GenServer

  alias Jido.Agent.Strategy.State, as: StratState
  alias JidoMurmur.Catalog
  alias JidoMurmur.Ingress.Input
  alias JidoMurmur.Runner

  require Logger

  @max_route_attempts 4
  @retry_delay_ms 10

  def start_link(opts) do
    session = Keyword.fetch!(opts, :session)
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, %{session: session}, name: name)
  end

  @impl true
  def init(state), do: {:ok, Map.put(state, :pending_request_id, nil)}

  @impl true
  def handle_call({:deliver, session, %Input{} = input}, _from, state) do
    state = %{state | session: session}
    {result, next_state} = route_input(session, input, state, @max_route_attempts)
    {:reply, result, next_state}
  end

  defp route_input(session, input, state, attempts_left) when attempts_left > 0 do
    case runtime_snapshot(session) do
      :agent_not_running ->
        {:agent_not_running, %{state | pending_request_id: nil}}

      %{active_request_id: active_request_id} = snapshot when is_binary(active_request_id) ->
        deliver_control(session, input, snapshot, active_request_id, state, attempts_left)

      %{active_request_id: nil, runner_active?: true} = snapshot
      when is_binary(state.pending_request_id) ->
        deliver_control(session, input, snapshot, state.pending_request_id, state, attempts_left)

      %{active_request_id: nil, runner_active?: true} ->
        Process.sleep(@retry_delay_ms)
        route_input(session, input, state, attempts_left - 1)

      %{active_request_id: nil} ->
        case Runner.start_run(session, input) do
          {:ok, request_id} -> {:queued, %{state | pending_request_id: request_id}}
          {:error, {:rejected, :busy, _message}} -> retry(session, input, state, attempts_left)
          {:error, _reason} -> {:queued, state}
        end
    end
  end

  defp route_input(_session, _input, state, _attempts_left), do: {:queued, state}

  defp deliver_control(session, input, snapshot, active_request_id, state, attempts_left) do
    control_opts = [
      expected_request_id: input.expected_request_id || active_request_id,
      source: input.source,
      extra_refs: input.refs
    ]

    result =
      case Input.control_kind(input) do
        :steer -> llm_adapter().steer(snapshot.agent_module, snapshot.pid, input.content, control_opts)
        :inject -> llm_adapter().inject(snapshot.agent_module, snapshot.pid, input.content, control_opts)
      end

    case result do
      {:ok, _agent} ->
        {:queued, %{state | pending_request_id: active_request_id}}

      {:error, {:rejected, :idle}} ->
        retry(session, input, %{state | pending_request_id: nil}, attempts_left)

      {:error, {:rejected, :request_mismatch}} ->
        retry(session, input, %{state | pending_request_id: nil}, attempts_left)

      {:error, reason} ->
        Logger.warning("Ingress control delivery failed for #{session.id}: #{inspect(reason)}")
        {:queued, state}
    end
  end

  defp retry(session, input, state, attempts_left) do
    Process.sleep(@retry_delay_ms)
    route_input(session, input, state, attempts_left - 1)
  end

  defp runtime_snapshot(session) do
    jido_mod = JidoMurmur.jido_mod()

    case jido_mod.whereis(session.id) do
      nil ->
        :agent_not_running

      pid ->
        case Jido.AgentServer.state(pid) do
          {:ok, %{agent: agent}} ->
            strategy_state = StratState.get(agent, %{})

            %{
              pid: pid,
              agent_module: Catalog.agent_module(session.agent_profile_id),
              active_request_id: Map.get(strategy_state, :active_request_id),
              strategy_status: Map.get(strategy_state, :status),
              runner_active?: Runner.active?(session.id)
            }

          _ ->
            :agent_not_running
        end
    end
  end

  defp llm_adapter do
    Application.get_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Real)
  end
end
