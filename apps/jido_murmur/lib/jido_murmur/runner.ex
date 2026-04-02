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
  @spec send_message(session_like(), String.t()) :: :queued | :agent_not_running
  def send_message(session, content) do
    jido_mod = JidoMurmur.jido_mod()
    pid = jido_mod.whereis(session.id)

    if pid do
      PendingQueue.enqueue(session.id, content)
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
    case PendingQueue.drain(session.id) do
      [] ->
        :done

      messages ->
        process_batch(session, Enum.join(messages, "\n\n"))
        run_loop(session)
    end
  rescue
    # ETS table may be gone if TableOwner shut down (e.g. during test teardown)
    ArgumentError -> :ok
  end

  defp process_batch(session, combined) do
    jido_mod = JidoMurmur.jido_mod()
    pid = jido_mod.whereis(session.id)
    if is_nil(pid), do: throw(:agent_gone)

    agent_module = Catalog.agent_module(session.agent_profile_id)
    topic = agent_topic(session)

    tool_ctx = %{
      workspace_id: session.workspace_id,
      sender_name: session.display_name
    }

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:jido_murmur, :runner, :send_message, :start],
      %{system_time: System.system_time()},
      %{session_id: session.id, agent_module: agent_module}
    )

    case llm_adapter().ask(agent_module, pid, combined, tool_ctx) do
      {:ok, req} ->
        handle_await(agent_module, req, session, topic, start_time)

      {:error, reason} ->
        :telemetry.execute(
          [:jido_murmur, :runner, :send_message, :exception],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session.id, reason: reason}
        )

        broadcast(topic, request_failed_signal(session, reason))
    end
  catch
    :agent_gone -> :ok
  end

  defp handle_await(agent_module, req, session, topic, start_time) do
    # A single ReAct run may loop for many iterations (LLM → tools → LLM …)
    # and individual tool calls can be slow (e.g. arXiv, web scraping).
    # Use :infinity so the agent's own internal timeouts govern cancellation
    # rather than an arbitrary outer wall-clock limit.
    case llm_adapter().await(agent_module, req, timeout: :infinity) do
      {:ok, response} ->
        :telemetry.execute(
          [:jido_murmur, :runner, :send_message, :stop],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session.id}
        )

        hibernate_agent(session.id)

        signal =
          MessageCompleted.new!(
            %{session_id: session.id, response: response},
            subject: MessageCompleted.subject(session.workspace_id, session.id)
          )

        broadcast(topic, signal)

      {:error, reason} ->
        :telemetry.execute(
          [:jido_murmur, :runner, :send_message, :exception],
          %{duration: System.monotonic_time() - start_time},
          %{session_id: session.id, reason: reason}
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
end
