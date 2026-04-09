defmodule JidoMurmur.Ingress do
  @moduledoc """
  Public ingress API for per-session message delivery.

  All producers should hand input to this module instead of independently
  deciding whether to call `ask`, `steer`, or `inject`.
  """

  alias JidoMurmur.Ingress.Coordinator
  alias JidoMurmur.Ingress.Input
  alias JidoMurmur.Ingress.ProgrammaticDelivery
  alias JidoMurmur.Ingress.VisibleMessage
  alias JidoMurmur.SessionContract

  @registry __MODULE__.Registry
  @supervisor __MODULE__.Supervisor

  @invalid_input_reasons [
    :empty_content,
    :missing_source,
    :invalid_source,
    :invalid_refs,
    :missing_workspace_id,
    :invalid_workspace_id,
    :invalid_sender_name,
    :invalid_origin_actor,
    :invalid_sender_trace_id,
    :invalid_hop_count,
    :invalid_expected_request_id
  ]

  @type session_like :: SessionContract.target()

  @spec registry_name() :: module()
  def registry_name, do: @registry

  @spec supervisor_name() :: module()
  def supervisor_name, do: @supervisor

  @spec deliver(session_like(), String.t(), list()) ::
          :queued | :agent_not_running | {:error, {:invalid_input, Input.validation_error()}}
  def deliver(%{id: _, workspace_id: _, agent_profile_id: _, display_name: _} = session, content, opts \\ [])
      when is_binary(content) and is_list(opts) do
    refs = VisibleMessage.attach_identity_refs(Keyword.get(opts, :refs, %{}))

    case Input.direct_message(session, content, Keyword.put(opts, :refs, refs)) do
      {:ok, input} ->
        deliver_visible_message(session, input, Keyword.get(opts, :kind, :steering))

      {:error, :empty_content} ->
        :queued

      {:error, reason} when reason in @invalid_input_reasons ->
        {:error, {:invalid_input, reason}}
    end
  end

  @spec deliver_programmatic(session_like(), String.t(), list()) ::
          :queued | :agent_not_running | {:error, {:invalid_input, Input.validation_error()}}
  def deliver_programmatic(%{id: _, workspace_id: _, agent_profile_id: _, display_name: _} = session, content, opts \\ [])
      when is_binary(content) and is_list(opts) do
    ProgrammaticDelivery.deliver(session, content, opts)
  end

  @spec deliver_input(session_like(), Input.t()) ::
          :queued | :agent_not_running | {:error, {:invalid_input, Input.validation_error()}}
  def deliver_input(%{id: _, workspace_id: _, agent_profile_id: _, display_name: _} = session, %Input{} = input) do
    case Input.validate(input) do
      :ok ->
        deliver_to_coordinator(session, input)

      {:error, reason} when reason in @invalid_input_reasons ->
        {:error, {:invalid_input, reason}}
    end
  end

  @spec coordinator_name(String.t()) :: {:via, Registry, {module(), String.t()}}
  def coordinator_name(session_id) when is_binary(session_id) do
    {:via, Registry, {@registry, session_id}}
  end

  @spec ensure_started(session_like()) :: {:ok, pid()} | {:error, :agent_not_running}
  def ensure_started(%{id: _, workspace_id: _, agent_profile_id: _, display_name: _} = session) do
    name = coordinator_name(session.id)

    case GenServer.whereis(name) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        start_child(session, name)
    end
  end

  defp start_child(session, name) do
    spec = {Coordinator, session: session, name: name}

    case DynamicSupervisor.start_child(@supervisor, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, {:already_present, _}} -> {:ok, GenServer.whereis(name)}
      {:error, _reason} -> {:error, :agent_not_running}
    end
  end

  defp deliver_visible_message(session, %Input{} = input, kind) do
    message = VisibleMessage.build_message(input, kind)

    case ensure_started(session) do
      {:ok, pid} ->
        _ = JidoMurmur.ConversationProjector.put_received_message(session, message)

        case deliver_to_coordinator(pid, session, input) do
          :queued ->
            VisibleMessage.broadcast_received(session, message)
            :queued

          :agent_not_running ->
            :agent_not_running
        end

      {:error, :agent_not_running} ->
        :agent_not_running
    end
  end

  defp deliver_to_coordinator(session, %Input{} = input) do
    case ensure_started(session) do
      {:ok, pid} -> deliver_to_coordinator(pid, session, input)
      {:error, :agent_not_running} -> :agent_not_running
    end
  end

  defp deliver_to_coordinator(pid, session, %Input{} = input) when is_pid(pid) do
    GenServer.call(pid, {:deliver, session, input})
  end
end
