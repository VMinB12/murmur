defmodule JidoMurmur.Runner do
  @moduledoc """
  Executes a single ask/await run for an agent session.

  Delivery decisions are owned by `JidoMurmur.Ingress`. This module only
  starts a run, awaits its completion in the background, broadcasts
  completion or failure, and hibernates the agent afterward.
  """

  alias JidoMurmur.Catalog
  alias JidoMurmur.Ingress.{Input, Metadata}
  alias JidoMurmur.Observability
  alias JidoMurmur.Signals.MessageCompleted

  require Logger

  @active_table :jido_murmur_active_runners

  @type session_like :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t(),
          required(:agent_profile_id) => String.t(),
          required(:display_name) => String.t()
        }

  @doc false
  @spec start_run(session_like(), Input.t()) :: {:ok, String.t()} | {:error, term()}
  def start_run(session, %Input{} = input) do
    case JidoMurmur.jido_mod().whereis(session.id) do
      nil -> {:error, :agent_not_running}
      pid -> do_start_run(session, input, pid)
    end
  end

  @doc "Check if an agent session has an active run task."
  @spec active?(String.t()) :: boolean()
  def active?(session_id) do
    :ets.lookup(@active_table, session_id) != []
  end

  # --- Private ---

  defp do_start_run(session, input, pid) do
    case Input.metadata(input) do
      {:ok, metadata} ->
        run = build_run_context(session, metadata)

        observe_run_start(session, input, metadata, run)

        request_opts =
          [tool_context: run.tool_context, request_id: run.request_id]
          |> maybe_put_extra_refs(input.refs)

        case llm_adapter().ask(run.agent_module, pid, input.content, request_opts) do
          {:ok, req} ->
            :ets.insert(@active_table, {session.id, run.request_id})
            start_await_task(run.agent_module, req, session, run.topic, run.start_time, run.request_id)
            {:ok, run.request_id}

          {:error, reason} ->
            handle_start_failure(session, run, reason)
        end

      {:error, reason} ->
        {:error, {:invalid_input, reason}}
    end
  end

  defp build_run_context(session, metadata) do
    request_id = Uniq.UUID.uuid7()

    %{
      agent_module: Catalog.agent_module(session.agent_profile_id),
      topic: agent_topic(session),
      interaction_id: metadata.interaction_id,
      request_id: request_id,
      tool_context: Metadata.tool_context(metadata, session.display_name, request_id),
      start_time: System.monotonic_time()
    }
  end

  defp observe_run_start(session, input, metadata, run) do
    Observability.start_turn(%{
      request_id: run.request_id,
      agent_id: session.id,
      agent_name: session.display_name,
      session_id: run.interaction_id,
      workspace_id: session.workspace_id,
      interaction_id: run.interaction_id,
      input_value: input.content,
      message_count: 1,
      triggered_by_trace_id: metadata.sender_trace_id,
      sender_name: metadata.sender_name,
      hop_count: metadata.hop_count
    })

    :telemetry.execute(
      [:jido_murmur, :runner, :run, :start],
      %{system_time: System.system_time()},
      %{session_id: session.id, agent_module: run.agent_module, request_id: run.request_id}
    )
  end

  defp handle_start_failure(session, run, reason) do
    Observability.fail_turn(run.request_id, reason)

    :telemetry.execute(
      [:jido_murmur, :runner, :run, :exception],
      %{duration: System.monotonic_time() - run.start_time},
      %{session_id: session.id, request_id: run.request_id, reason: reason}
    )

    broadcast(run.topic, request_failed_signal(session, reason))
    {:error, reason}
  end

  defp start_await_task(agent_module, req, session, topic, start_time, request_id) do
    jido_mod = JidoMurmur.jido_mod()

    :telemetry.execute(
      [:jido_murmur, :runner, :loop_start],
      %{system_time: System.system_time()},
      %{session_id: session.id, request_id: request_id}
    )

    Task.Supervisor.start_child(jido_mod.task_supervisor_name(), fn ->
      try do
        handle_await(agent_module, req, session, topic, start_time, request_id)
      after
        try do
          :ets.delete(@active_table, session.id)
        rescue
          ArgumentError -> :ok
        end
      end
    end)
  end

  defp handle_await(agent_module, req, session, topic, start_time, request_id) do
    # A single ReAct run may loop for many iterations (LLM -> tools -> LLM ...)
    # and individual tool calls can be slow (for example arXiv or web scraping).
    # Use :infinity so the agent's own internal timeouts govern cancellation
    # rather than an arbitrary outer wall-clock limit.
    case llm_adapter().await(agent_module, req, timeout: :infinity) do
      {:ok, response} ->
        Observability.finish_turn(request_id, %{response: response})

        :telemetry.execute(
          [:jido_murmur, :runner, :run, :stop],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session.id, request_id: request_id}
        )

        hibernate_agent(session.id)

        signal =
          MessageCompleted.new!(
            %{session_id: session.id, response: response},
            subject: MessageCompleted.subject(session.workspace_id, session.id)
          )

        broadcast(topic, signal)

      {:error, reason} ->
        Observability.fail_turn(request_id, reason)

        :telemetry.execute(
          [:jido_murmur, :runner, :run, :exception],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session.id, request_id: request_id, reason: reason}
        )

        broadcast(topic, request_failed_signal(session, reason))
    end
  end

  defp llm_adapter do
    Application.get_env(:jido_murmur, :llm_adapter, JidoMurmur.LLM.Real)
  end

  defp hibernate_agent(session_id) do
    if Application.get_env(:jido_murmur, :skip_hibernate, false) do
      :ok
    else
      do_hibernate(session_id)
    end
  end

  defp do_hibernate(session_id) do
    jido_mod = JidoMurmur.jido_mod()

    with pid when is_pid(pid) <- jido_mod.whereis(session_id),
         {:ok, %{agent: agent}} <- Jido.AgentServer.state(pid),
         :ok <- jido_mod.hibernate(agent) do
      :ok
    else
      nil -> :ok
      {:error, reason} -> log_hibernate_error(session_id, reason)
    end
  rescue
    error ->
      Logger.error("Exception during hibernate for agent #{session_id}: #{Exception.message(error)}")
      :ok
  catch
    :exit, reason ->
      Logger.error("Exit during hibernate for agent #{session_id}: #{inspect(reason)}")
      :ok
  end

  defp log_hibernate_error(session_id, reason) do
    Logger.error("Failed to hibernate agent #{session_id}: #{inspect(reason)}")
    {:error, reason}
  end

  defp agent_topic(session) do
    JidoMurmur.Topics.agent_messages(session.workspace_id, session.id)
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(JidoMurmur.pubsub(), topic, message)
  end

  defp request_failed_signal(session, reason) do
    Jido.Signal.new!(
      "murmur.request.failed",
      %{session_id: session.id, reason: reason},
      source: "/jido_murmur/runner",
      subject: "/workspaces/#{session.workspace_id}/agents/#{session.id}"
    )
  end

  defp maybe_put_extra_refs(request_opts, refs) when map_size(refs) == 0, do: request_opts
  defp maybe_put_extra_refs(request_opts, refs), do: Keyword.put(request_opts, :extra_refs, refs)
end
