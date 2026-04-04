defmodule JidoMurmur.Runner do
  @moduledoc """
  Manages the ask/await lifecycle for an agent session.

  All incoming messages are enqueued in `PendingQueue` first. A single
  drain-loop Task per session pulls messages off the queue, combines
  them, and sends exactly ONE `ask()` at a time. This avoids concurrent
  asks which corrupt the agent's `last_request_id` tracking.

  Messages arriving while the LLM is processing are either:
  - Injected mid-turn by `MessageInjector` (before the next LLM call)
  - Picked up by the drain loop after the current request completes
  """

  alias JidoMurmur.Catalog
  alias JidoMurmur.Observability
  alias JidoMurmur.Observability.ConversationCache
  alias JidoMurmur.PendingQueue
  alias JidoMurmur.Signals.MessageCompleted

  require Logger

  @active_table :jido_murmur_active_runners

  @type session_like :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t(),
          required(:agent_profile_id) => String.t(),
          required(:display_name) => String.t()
        }

  @doc """
  Send a message to an agent session.

  The message is enqueued and a drain loop is started if one isn't
  already running for this session.

  Returns `:queued` or `:agent_not_running`.
  """
  @spec send_message(session_like(), String.t(), keyword()) :: :queued | :agent_not_running
  def send_message(session, content, opts \\ []) do
    jido_mod = JidoMurmur.jido_mod()
    pid = jido_mod.whereis(session.id)

    if pid do
      PendingQueue.enqueue(
        session.id,
        Observability.build_message_envelope(content, ensure_interaction_id(session, opts))
      )

      maybe_start_loop(session)
      :queued
    else
      :agent_not_running
    end
  end

  @doc "Check if an agent session has a drain-loop running."
  @spec active?(String.t()) :: boolean()
  def active?(session_id) do
    :ets.lookup(@active_table, session_id) != []
  end

  # --- Private ---

  defp maybe_start_loop(session) do
    jido_mod = JidoMurmur.jido_mod()

    if :ets.insert_new(@active_table, {session.id, true}) do
      :telemetry.execute(
        [:jido_murmur, :runner, :loop_start],
        %{system_time: System.system_time()},
        %{session_id: session.id}
      )

      Task.Supervisor.start_child(jido_mod.task_supervisor_name(), fn ->
        try do
          run_loop(session)
        after
          try do
            :ets.delete(@active_table, session.id)
          rescue
            ArgumentError -> :ok
          end
        end
      end)
    end

    :ok
  end

  defp run_loop(session) do
    case PendingQueue.drain_envelopes(session.id) do
      [] ->
        :done

      envelopes ->
        process_batch(session, envelopes)
        run_loop(session)
    end
  rescue
    # ETS table may be gone if TableOwner shut down (e.g. during test teardown)
    ArgumentError -> :ok
  end

  defp process_batch(session, envelopes) do
    jido_mod = JidoMurmur.jido_mod()
    pid = jido_mod.whereis(session.id)
    if is_nil(pid), do: throw(:agent_gone)

    agent_module = Catalog.agent_module(session.agent_profile_id)
    topic = agent_topic(session)
    combined = envelopes_to_content(envelopes)
    interaction_id = envelopes_to_interaction_id(envelopes)
    conversation_session_id = interaction_id || session.id
    sender_trace_id = envelopes_to_sender_trace_id(envelopes)
    sender_name = envelopes_to_sender_name(envelopes)
    request_id = Uniq.UUID.uuid7()

    tool_ctx = %{
      workspace_id: session.workspace_id,
      sender_name: session.display_name,
      interaction_id: interaction_id,
      request_id: request_id
    }

    start_time = System.monotonic_time()

    Observability.start_turn(%{
      request_id: request_id,
      agent_id: session.id,
      agent_name: session.display_name,
      session_id: conversation_session_id,
      workspace_id: session.workspace_id,
      interaction_id: interaction_id,
      input_value: combined,
      message_count: length(envelopes),
      triggered_by_trace_id: sender_trace_id,
      sender_name: sender_name
    })

    :telemetry.execute(
      [:jido_murmur, :runner, :send_message, :start],
      %{system_time: System.system_time()},
      %{session_id: session.id, agent_module: agent_module, request_id: request_id}
    )

    request_opts = [tool_context: tool_ctx, request_id: request_id]

    case llm_adapter().ask(agent_module, pid, combined, request_opts) do
      {:ok, req} ->
        handle_await(agent_module, req, session, topic, start_time, request_id)

      {:error, reason} ->
        Observability.fail_turn(request_id, reason)

        :telemetry.execute(
          [:jido_murmur, :runner, :send_message, :exception],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session.id, request_id: request_id, reason: reason}
        )

        broadcast(topic, request_failed_signal(session, reason))
    end
  catch
    :agent_gone -> :ok
  end

  defp handle_await(agent_module, req, session, topic, start_time, request_id) do
    # A single ReAct run may loop for many iterations (LLM → tools → LLM …)
    # and individual tool calls can be slow (e.g. arXiv, web scraping).
    # Use :infinity so the agent's own internal timeouts govern cancellation
    # rather than an arbitrary outer wall-clock limit.
    case llm_adapter().await(agent_module, req, timeout: :infinity) do
      {:ok, response} ->
        Observability.finish_turn(request_id, %{response: response})

        :telemetry.execute(
          [:jido_murmur, :runner, :send_message, :stop],
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
          [:jido_murmur, :runner, :send_message, :exception],
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
    e ->
      Logger.error("Exception during hibernate for agent #{session_id}: #{Exception.message(e)}")
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

  defp ensure_interaction_id(session, opts) do
    interaction_id =
      ConversationCache.resolve(session.id,
        interaction_id: Keyword.get(opts, :interaction_id),
        kind: Keyword.get(opts, :kind, :direct),
        now_ms: Keyword.get(opts, :sent_at_ms, System.monotonic_time(:millisecond))
      )

    Keyword.put(opts, :interaction_id, interaction_id)
  end

  defp envelopes_to_content(envelopes) do
    Enum.map_join(envelopes, "\n\n", & &1.content)
  end

  defp envelopes_to_interaction_id(envelopes) do
    Enum.find_value(envelopes, &Map.get(&1, :interaction_id)) || Observability.next_interaction_id()
  end

  defp envelopes_to_sender_trace_id(envelopes) do
    Enum.find_value(envelopes, &Map.get(&1, :sender_trace_id))
  end

  defp envelopes_to_sender_name(envelopes) do
    Enum.find_value(envelopes, &Map.get(&1, :sender_name))
  end
end
