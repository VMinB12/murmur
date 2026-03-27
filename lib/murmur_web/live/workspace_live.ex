defmodule MurmurWeb.WorkspaceLive do
  @moduledoc false
  use MurmurWeb, :live_view

  alias Jido.Signal.ID
  alias Murmur.Agents.Artifact
  alias Murmur.Agents.Catalog
  alias Murmur.Agents.Runner
  alias Murmur.Agents.StreamingPlugin
  alias Murmur.Agents.UITurn
  alias Murmur.Workspaces

  require Logger

  @empty_stream %{content: "", thinking: "", tool_calls: [], usage: nil}

  @impl true
  def mount(%{"id" => workspace_id}, _session, socket) do
    workspace = Workspaces.get_workspace!(workspace_id)
    agent_sessions = Workspaces.list_agent_sessions(workspace_id)
    profiles = Catalog.list_profiles()

    # Build initial messages map from agent threads or persisted storage
    messages_map =
      Map.new(agent_sessions, fn session ->
        {session.id, load_messages_for_session(session)}
      end)

    socket =
      socket
      |> assign(:workspace, workspace)
      |> assign(:agent_sessions, agent_sessions)
      |> assign(:profiles, profiles)
      |> assign(:agent_statuses, Map.new(agent_sessions, &{&1.id, :idle}))
      |> assign(:streaming, Map.new(agent_sessions, &{&1.id, @empty_stream}))
      |> assign(:messages, messages_map)
      |> assign(:artifacts, Map.new(agent_sessions, &{&1.id, %{}}))
      |> assign(:view_mode, :split)
      |> assign(:add_agent_form, to_form(%{"profile_id" => "", "display_name" => ""}, as: :agent))

    socket =
      if connected?(socket) do
        Enum.reduce(agent_sessions, socket, fn session, acc ->
          topic = agent_topic(workspace_id, session.id)
          Phoenix.PubSub.subscribe(Murmur.PubSub, topic)
          Phoenix.PubSub.subscribe(Murmur.PubSub, StreamingPlugin.stream_topic(session.id))
          Phoenix.PubSub.subscribe(Murmur.PubSub, Artifact.artifact_topic(session.id))
          ensure_agent_started(session)

          status = get_agent_status(session.id)
          update(acc, :agent_statuses, &Map.put(&1, session.id, status))
        end)
      else
        socket
      end

    {:ok, socket}
  end

  # --- Events ---

  @impl true
  def handle_event("send_message", %{"message" => %{"content" => content, "session_id" => session_id}}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      session = Workspaces.get_agent_session!(session_id)
      workspace_id = socket.assigns.workspace.id
      topic = agent_topic(workspace_id, session_id)

      # Add user message to local display immediately
      user_msg = %{
        id: ID.generate!(),
        role: "user",
        content: content,
        sender_name: "You"
      }

      socket =
        socket
        |> update(:messages, fn msgs ->
          Map.update(msgs, session_id, [user_msg], &(&1 ++ [user_msg]))
        end)
        |> update(:agent_statuses, &Map.put(&1, session_id, :busy))

      # Send to agent via ask/await in an async task
      send_to_agent(session, content, topic)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("add_agent", %{"agent" => %{"profile_id" => profile_id, "display_name" => display_name}}, socket) do
    workspace = socket.assigns.workspace

    case Workspaces.create_agent_session(workspace.id, %{
           "agent_profile_id" => profile_id,
           "display_name" => display_name
         }) do
      {:ok, session} ->
        topic = agent_topic(workspace.id, session.id)
        Phoenix.PubSub.subscribe(Murmur.PubSub, topic)
        Phoenix.PubSub.subscribe(Murmur.PubSub, StreamingPlugin.stream_topic(session.id))
        Phoenix.PubSub.subscribe(Murmur.PubSub, Artifact.artifact_topic(session.id))
        ensure_agent_started(session)

        socket =
          socket
          |> update(:agent_sessions, &(&1 ++ [session]))
          |> update(:messages, &Map.put(&1, session.id, []))
          |> update(:agent_statuses, &Map.put(&1, session.id, :idle))
          |> update(:streaming, &Map.put(&1, session.id, @empty_stream))
          |> update(:artifacts, &Map.put(&1, session.id, %{}))
          |> assign(
            :add_agent_form,
            to_form(%{"profile_id" => "", "display_name" => ""}, as: :agent)
          )

        {:noreply, socket}

      {:error, :max_agents_reached} ->
        {:noreply, put_flash(socket, :error, "Maximum of 8 agents per workspace reached.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :add_agent_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("clear_team", _params, socket) do
    Enum.each(socket.assigns.agent_sessions, fn session ->
      stop_agent(session.id)
      cleanup_storage(session)
    end)

    # Restart agents fresh (no history)
    Enum.each(socket.assigns.agent_sessions, fn session ->
      agent_module = Catalog.agent_module(session.agent_profile_id)

      Murmur.Jido.start_agent(agent_module, id: session.id)
    end)

    empty_messages = Map.new(socket.assigns.agent_sessions, &{&1.id, []})
    empty_statuses = Map.new(socket.assigns.agent_sessions, &{&1.id, :idle})
    empty_streaming = Map.new(socket.assigns.agent_sessions, &{&1.id, @empty_stream})
    empty_artifacts = Map.new(socket.assigns.agent_sessions, &{&1.id, %{}})

    {:noreply,
     socket
     |> assign(:messages, empty_messages)
     |> assign(:agent_statuses, empty_statuses)
     |> assign(:streaming, empty_streaming)
     |> assign(:artifacts, empty_artifacts)}
  end

  def handle_event("toggle_view_mode", _params, socket) do
    new_mode = if socket.assigns.view_mode == :split, do: :unified, else: :split
    {:noreply, assign(socket, :view_mode, new_mode)}
  end

  def handle_event("send_unified_message", %{"message" => %{"content" => content}}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      {target_session, actual_content} = resolve_target_agent(content, socket.assigns)
      send_to_target(socket, target_session, actual_content)
    end
  end

  def handle_event("remove_agent", %{"session-id" => session_id}, socket) do
    session = Workspaces.get_agent_session!(session_id)
    topic = agent_topic(socket.assigns.workspace.id, session_id)
    Phoenix.PubSub.unsubscribe(Murmur.PubSub, topic)
    Phoenix.PubSub.unsubscribe(Murmur.PubSub, StreamingPlugin.stream_topic(session_id))
    Phoenix.PubSub.unsubscribe(Murmur.PubSub, Artifact.artifact_topic(session_id))
    stop_agent(session_id)
    cleanup_storage(session)
    Workspaces.delete_agent_session(session)

    socket =
      socket
      |> update(:agent_sessions, fn sessions ->
        Enum.reject(sessions, &(&1.id == session_id))
      end)
      |> update(:messages, &Map.delete(&1, session_id))
      |> update(:agent_statuses, &Map.delete(&1, session_id))
      |> update(:streaming, &Map.delete(&1, session_id))
      |> update(:artifacts, &Map.delete(&1, session_id))

    {:noreply, socket}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info({:message_completed, session_id, response}, socket) do
    # Try to reload full history from agent thread to capture thinking/tool calls.
    # Falls back to appending the response text if thread hasn't been populated
    # (e.g. when using a mock LLM adapter in tests).
    session = find_session(socket, session_id)
    current_messages = Map.get(socket.assigns.messages, session_id, [])

    messages =
      if session do
        loaded = load_messages_for_session(session)

        if length(loaded) > length(current_messages) do
          loaded
        else
          append_assistant_message(current_messages, response)
        end
      else
        append_assistant_message(current_messages, response)
      end

    # Transfer accumulated usage from streaming state to the last assistant message
    stream_state = Map.get(socket.assigns.streaming, session_id, @empty_stream)

    messages =
      if stream_state.usage do
        attach_usage_to_last_assistant(messages, stream_state.usage)
      else
        messages
      end

    socket =
      socket
      |> update(:messages, &Map.put(&1, session_id, messages))
      |> update(:agent_statuses, &Map.put(&1, session_id, :idle))
      |> update(:streaming, &Map.put(&1, session_id, @empty_stream))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:request_failed, session_id, reason}, socket) do
    error_msg = %{
      id: ID.generate!(),
      role: "assistant",
      content: "⚠️ Error: #{inspect(reason)}",
      sender_name: nil
    }

    socket =
      socket
      |> update(:messages, fn msgs ->
        Map.update(msgs, session_id, [error_msg], &(&1 ++ [error_msg]))
      end)
      |> update(:agent_statuses, &Map.put(&1, session_id, :idle))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:new_message, session_id, message}, socket) do
    socket =
      update(socket, :messages, fn msgs ->
        Map.update(msgs, session_id, [message], &(&1 ++ [message]))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:status_change, session_id, status}, socket) do
    socket = update(socket, :agent_statuses, &Map.put(&1, session_id, status))

    socket =
      if status == :idle do
        update(socket, :streaming, &Map.put(&1, session_id, @empty_stream))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_signal, session_id, %{type: "ai.llm.delta", data: data}}, socket) do
    case data do
      %{delta: delta, chunk_type: :content} when is_binary(delta) and delta != "" ->
        {:noreply, update_streaming(socket, session_id, :content, delta)}

      %{delta: delta, chunk_type: :thinking} when is_binary(delta) and delta != "" ->
        {:noreply, update_streaming(socket, session_id, :thinking, delta)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:agent_signal, session_id, %{type: "ai.tool.result", data: data}}, socket) do
    tool_call = %{
      name: data[:tool_name] || data["tool_name"] || "tool",
      result: format_tool_result(data[:result] || data["result"]),
      status: tool_result_status(data[:result] || data["result"])
    }

    socket =
      update(socket, :streaming, fn streams ->
        Map.update(streams, session_id, Map.put(@empty_stream, :tool_calls, [tool_call]), fn s ->
          Map.update(s, :tool_calls, [tool_call], &(&1 ++ [tool_call]))
        end)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_signal, session_id, %{type: "ai.usage", data: data}}, socket) do
    usage = %{
      input_tokens: data[:input_tokens] || data["input_tokens"] || 0,
      output_tokens: data[:output_tokens] || data["output_tokens"] || 0,
      total_tokens: data[:total_tokens] || data["total_tokens"] || 0,
      model: data[:model] || data["model"],
      duration_ms: data[:duration_ms] || data["duration_ms"]
    }

    # Accumulate usage across multiple LLM calls in a ReAct loop
    socket =
      update(socket, :streaming, fn streams ->
        Map.update(streams, session_id, Map.put(@empty_stream, :usage, usage), fn s ->
          Map.update(s, :usage, usage, fn
            nil -> usage
            prev -> merge_usage(prev, usage)
          end)
        end)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:agent_signal, _session_id, _signal}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:artifact_update, session_id, name, data, mode}, socket) do
    socket =
      update(socket, :artifacts, fn artifacts ->
        session_artifacts = Map.get(artifacts, session_id, %{})

        updated =
          case mode do
            :append ->
              existing = Map.get(session_artifacts, name, [])
              Map.put(session_artifacts, name, existing ++ List.wrap(data))

            _replace ->
              Map.put(session_artifacts, name, data)
          end

        Map.put(artifacts, session_id, updated)
      end)

    {:noreply, socket}
  end

  # Catch-all for other messages
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Agent Communication ---

  defp send_to_agent(session, _content, _topic) when is_nil(session), do: :ok

  defp send_to_agent(session, content, _topic) do
    Runner.send_message(session, content)
  end

  # --- Thread / State Helpers ---

  defp update_streaming(socket, session_id, field, delta) do
    update(socket, :streaming, fn streams ->
      Map.update(streams, session_id, Map.put(@empty_stream, field, delta), fn s ->
        Map.update(s, field, delta, &(&1 <> delta))
      end)
    end)
  end

  defp format_tool_result({:ok, result, _effects}), do: truncate_result(inspect(result))
  defp format_tool_result({:error, reason, _effects}), do: truncate_result("Error: #{inspect(reason)}")
  defp format_tool_result({:ok, result}), do: truncate_result(inspect(result))
  defp format_tool_result({:error, reason}), do: truncate_result("Error: #{inspect(reason)}")
  defp format_tool_result(other), do: truncate_result(inspect(other))

  defp truncate_result(str) when byte_size(str) > 500, do: String.slice(str, 0, 500) <> "…"
  defp truncate_result(str), do: str

  defp tool_result_status({:ok, _, _}), do: :completed
  defp tool_result_status({:ok, _}), do: :completed
  defp tool_result_status({:error, _, _}), do: :error
  defp tool_result_status({:error, _}), do: :error
  defp tool_result_status(_), do: :completed

  defp merge_usage(prev, new) do
    %{
      input_tokens: (prev.input_tokens || 0) + (new.input_tokens || 0),
      output_tokens: (prev.output_tokens || 0) + (new.output_tokens || 0),
      total_tokens: (prev.total_tokens || 0) + (new.total_tokens || 0),
      model: new.model || prev.model,
      duration_ms: sum_duration(prev.duration_ms, new.duration_ms)
    }
  end

  defp sum_duration(nil, nil), do: nil
  defp sum_duration(a, nil), do: a
  defp sum_duration(nil, b), do: b
  defp sum_duration(a, b), do: a + b

  defp attach_usage_to_last_assistant(messages, usage) do
    messages
    |> Enum.reverse()
    |> do_attach_usage(usage)
    |> Enum.reverse()
  end

  defp do_attach_usage([%{role: "assistant"} = msg | rest], usage) do
    [Map.put(msg, :usage, usage) | rest]
  end

  defp do_attach_usage(other, _usage), do: other

  defp load_messages_for_session(session) do
    pid = Murmur.Jido.whereis(session.id)

    if pid do
      case Jido.AgentServer.state(pid) do
        {:ok, %{agent: agent}} -> project_thread(agent)
        _ -> load_messages_from_storage(session)
      end
    else
      load_messages_from_storage(session)
    end
  end

  defp load_messages_from_storage(session) do
    agent_module = Catalog.agent_module(session.agent_profile_id)

    case Murmur.Jido.thaw(agent_module, session.id) do
      {:ok, agent} -> project_thread(agent)
      {:error, :not_found} -> []
    end
  end

  defp project_thread(agent) do
    thread = get_in_thread(agent)

    if thread do
      UITurn.project_entries(thread.entries)
    else
      []
    end
  end

  defp get_in_thread(%{state: %{__thread__: thread}}) when not is_nil(thread), do: thread
  defp get_in_thread(_), do: nil

  defp cleanup_storage(session) do
    {adapter, opts} = Murmur.Jido.__jido_storage__()
    agent_module = Catalog.agent_module(session.agent_profile_id)
    checkpoint_key = {agent_module, session.id}

    adapter.delete_checkpoint(checkpoint_key, opts)
    adapter.delete_thread(session.id, opts)
  rescue
    e ->
      Logger.warning("Failed to cleanup storage for session #{session.id}: #{Exception.message(e)}")

      :ok
  end

  # --- Agent Lifecycle ---

  defp ensure_agent_started(session) do
    case Murmur.Jido.whereis(session.id) do
      nil ->
        agent_module = Catalog.agent_module(session.agent_profile_id)

        # Try to restore agent from storage so it retains conversation history.
        # Falls back to a fresh agent if no checkpoint exists.
        {agent, extra_opts} =
          case Murmur.Jido.thaw(agent_module, session.id) do
            {:ok, thawed_agent} -> {thawed_agent, [agent_module: agent_module]}
            {:error, :not_found} -> {agent_module, []}
          end

        case Murmur.Jido.start_agent(agent, [id: session.id] ++ extra_opts) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, {:already_registered, _pid}} -> :ok
          _ -> :ok
        end

      _pid ->
        :ok
    end
  end

  defp stop_agent(session_id) do
    case Murmur.Jido.whereis(session_id) do
      nil -> :ok
      _pid -> Murmur.Jido.stop_agent(session_id)
    end
  end

  defp agent_topic(workspace_id, session_id) do
    "workspace:#{workspace_id}:agent:#{session_id}"
  end

  # --- Helpers ---

  defp find_session(socket, session_id) do
    Enum.find(socket.assigns.agent_sessions, &(&1.id == session_id))
  end

  defp send_to_target(socket, nil, _content) do
    {:noreply, put_flash(socket, :error, "No agents available. Add an agent first.")}
  end

  defp send_to_target(socket, target_session, content) do
    workspace_id = socket.assigns.workspace.id
    topic = agent_topic(workspace_id, target_session.id)

    user_msg = %{
      id: ID.generate!(),
      role: "user",
      content: content,
      sender_name: "You"
    }

    socket =
      socket
      |> update(:messages, fn msgs ->
        Map.update(msgs, target_session.id, [user_msg], &(&1 ++ [user_msg]))
      end)
      |> update(:agent_statuses, &Map.put(&1, target_session.id, :busy))

    send_to_agent(target_session, content, topic)
    {:noreply, socket}
  end

  defp resolve_target_agent(content, assigns) do
    sessions = assigns.agent_sessions

    case Regex.run(~r/^@(\S+)\s+(.*)$/s, content) do
      [_, mention, rest] ->
        target =
          Enum.find(sessions, fn s ->
            String.downcase(s.display_name) == String.downcase(mention)
          end)

        if target, do: {target, String.trim(rest)}, else: {List.first(sessions), content}

      _ ->
        {List.first(sessions), content}
    end
  end

  def unified_timeline(messages_map, agent_sessions) do
    session_index = Map.new(agent_sessions, &{&1.id, &1})

    messages_map
    |> Enum.flat_map(fn {session_id, msgs} ->
      session = Map.get(session_index, session_id)
      agent_name = if session, do: session.display_name, else: "unknown"
      profile_id = if session, do: session.agent_profile_id

      Enum.map(msgs, fn msg ->
        Map.merge(msg, %{
          session_id: session_id,
          agent_name: agent_name,
          agent_color: Catalog.agent_color(profile_id, agent_name)
        })
      end)
    end)
    |> Enum.sort_by(& &1.id)
  end

  defp append_assistant_message(messages, response) do
    content = extract_response_content(response)

    assistant_msg = %{
      id: ID.generate!(),
      role: "assistant",
      content: content,
      sender_name: nil
    }

    messages ++ [assistant_msg]
  end

  defp extract_response_content(response) when is_binary(response), do: response
  defp extract_response_content(%{result: result}) when is_binary(result), do: result
  defp extract_response_content(%{content: content}) when is_binary(content), do: content
  defp extract_response_content(response), do: inspect(response)

  defp get_agent_status(agent_session_id) do
    pid = Murmur.Jido.whereis(agent_session_id)
    if pid, do: fetch_agent_status(pid), else: :idle
  end

  defp fetch_agent_status(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, %{status: :busy}} -> :busy
      _ -> :idle
    end
  end

  # --- Artifact Helpers ---

  @doc false
  def artifact_item_label(item) when is_map(item) do
    # Try common label fields in priority order
    item[:title] || item["title"] ||
      item[:name] || item["name"] ||
      item[:label] || item["label"] ||
      item[:summary] || item["summary"] ||
      inspect(item, limit: 80)
  end

  def artifact_item_label(item) when is_binary(item), do: item
  def artifact_item_label(item), do: inspect(item, limit: 80)
end
