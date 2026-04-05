defmodule MurmurWeb.WorkspaceLive do
  @moduledoc false
  use MurmurWeb, :live_view

  alias Jido.AI.Signal.LLMResponse
  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalUpdate
  alias JidoMurmur.Catalog
  alias JidoMurmur.Observability.ConversationCache
  alias JidoMurmur.Observability.SessionCache
  alias JidoMurmur.Topics
  alias JidoMurmur.Workspaces
  alias JidoTasks.Signals.TaskCreated
  alias JidoTasks.Signals.TaskUpdated
  alias JidoTasks.Tasks
  alias MurmurWeb.Artifacts.Actions, as: ArtifactActions
  alias MurmurWeb.Live.WorkspaceState

  require Logger

  @empty_stream %{content: "", thinking: "", tool_calls: [], usage: nil}

  @impl true
  def mount(%{"id" => workspace_id}, _session, socket) do
    workspace = Workspaces.get_workspace!(workspace_id)
    agent_sessions = Workspaces.list_agent_sessions(workspace_id)
    profiles = Catalog.list_profiles()

    # Build initial messages and artifacts from agent state or persisted storage
    messages_map =
      Map.new(agent_sessions, fn session ->
        {session.id, WorkspaceState.load_messages_for_session(session)}
      end)

    artifacts_map =
      Map.new(agent_sessions, fn session ->
        {session.id, WorkspaceState.load_artifacts_for_session(session)}
      end)

    socket =
      socket
      |> assign(:workspace, workspace)
      |> assign(:agent_sessions, agent_sessions)
      |> assign(:profiles, profiles)
      |> assign(:agent_statuses, Map.new(agent_sessions, &{&1.id, :idle}))
      |> assign(:streaming, Map.new(agent_sessions, &{&1.id, @empty_stream}))
      |> assign(:messages, messages_map)
      |> assign(:artifacts, artifacts_map)
      |> assign(:active_artifact, nil)
      |> assign(:view_mode, :split)
      |> assign(:show_task_board, false)
      |> assign(:tasks, Tasks.list_tasks(workspace_id))
      |> assign(:task_form, to_form(%{"title" => "", "description" => "", "assignee" => ""}, as: :task))
      |> assign(:editing_task, nil)
      |> assign(:add_agent_form, to_form(%{"profile_id" => "", "display_name" => ""}, as: :agent))

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Murmur.PubSub, Topics.workspace_tasks(workspace_id))

        Enum.reduce(agent_sessions, socket, fn session, acc ->
          Phoenix.PubSub.subscribe(Murmur.PubSub, Topics.agent_messages(workspace_id, session.id))
          Phoenix.PubSub.subscribe(Murmur.PubSub, Topics.agent_stream(workspace_id, session.id))
          Phoenix.PubSub.subscribe(Murmur.PubSub, Topics.agent_artifacts(workspace_id, session.id))
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
      topic = Topics.agent_messages(workspace_id, session_id)

      # Add user message to local display immediately
      user_msg = %{
        id: Uniq.UUID.uuid7(),
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
        Phoenix.PubSub.subscribe(Murmur.PubSub, Topics.agent_messages(workspace.id, session.id))
        Phoenix.PubSub.subscribe(Murmur.PubSub, Topics.agent_stream(workspace.id, session.id))
        Phoenix.PubSub.subscribe(Murmur.PubSub, Topics.agent_artifacts(workspace.id, session.id))
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

    Tasks.delete_tasks_for_workspace(socket.assigns.workspace.id)

    # Restart agents fresh (no history)
    Enum.each(socket.assigns.agent_sessions, fn session ->
      agent_module = Catalog.agent_module(session.agent_profile_id)
      SessionCache.put(session.id, session.workspace_id, session.display_name)

      Murmur.Jido.start_agent(agent_module,
        id: session.id,
        initial_state: %{workspace_id: session.workspace_id}
      )
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
     |> assign(:artifacts, empty_artifacts)
     |> assign(:active_artifact, nil)
     |> assign(:tasks, [])}
  end

  def handle_event("toggle_view_mode", _params, socket) do
    new_mode = if socket.assigns.view_mode == :split, do: :unified, else: :split
    {:noreply, assign(socket, :view_mode, new_mode)}
  end

  def handle_event("open_artifact", %{"session-id" => session_id, "name" => name}, socket) do
    {:noreply, assign(socket, :active_artifact, %{session_id: session_id, name: name})}
  end

  def handle_event("close_artifact", _params, socket) do
    {:noreply, assign(socket, :active_artifact, nil)}
  end

  def handle_event(
        "reexecute_query",
        params,
        socket
      ) do
    case ArtifactActions.handle("reexecute_query", params, socket.assigns.artifacts) do
      {:ok, updated_artifacts} ->
        {:noreply, assign(socket, :artifacts, updated_artifacts)}

      {:error, :artifact_not_found} ->
        {:noreply, put_flash(socket, :error, "The selected SQL artifact is no longer available.")}

      {:error, :query_not_found} ->
        {:noreply, put_flash(socket, :error, "The selected SQL query is no longer available.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Unable to refresh the selected SQL query.")}
    end
  end

  def handle_event("toggle_task_board", _params, socket) do
    {:noreply, assign(socket, :show_task_board, !socket.assigns.show_task_board)}
  end

  def handle_event("create_task", %{"task" => params}, socket) do
    workspace_id = socket.assigns.workspace.id

    attrs = %{
      title: params["title"],
      description: params["description"],
      assignee: params["assignee"],
      status: :todo
    }

    case Tasks.create_task(workspace_id, attrs, "human") do
      {:ok, task} ->
        signal =
          TaskCreated.new!(
            %{task: task},
            subject: TaskCreated.subject(workspace_id, task.id)
          )

        Phoenix.PubSub.broadcast(
          Murmur.PubSub,
          Topics.workspace_tasks(workspace_id),
          signal
        )

        notify_task_assignee(workspace_id, task, "You (human)")

        {:noreply,
         assign(socket, :task_form, to_form(%{"title" => "", "description" => "", "assignee" => ""}, as: :task))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create task.")}
    end
  end

  def handle_event("update_task_status", %{"task-id" => id, "status" => status}, socket) do
    task = Tasks.get_task!(id)
    status_atom = String.to_existing_atom(status)

    case Tasks.update_task(task, %{status: status_atom}) do
      {:ok, updated} ->
        signal =
          TaskUpdated.new!(
            %{task: updated},
            subject: TaskUpdated.subject(socket.assigns.workspace.id, updated.id)
          )

        Phoenix.PubSub.broadcast(
          Murmur.PubSub,
          Topics.workspace_tasks(socket.assigns.workspace.id),
          signal
        )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update task.")}
    end
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
    workspace_id = socket.assigns.workspace.id
    Phoenix.PubSub.unsubscribe(Murmur.PubSub, Topics.agent_messages(workspace_id, session_id))
    Phoenix.PubSub.unsubscribe(Murmur.PubSub, Topics.agent_stream(workspace_id, session_id))
    Phoenix.PubSub.unsubscribe(Murmur.PubSub, Topics.agent_artifacts(workspace_id, session_id))
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
      |> then(fn s ->
        if s.assigns.active_artifact && s.assigns.active_artifact.session_id == session_id do
          assign(s, :active_artifact, nil)
        else
          s
        end
      end)

    {:noreply, socket}
  end

  # --- PubSub Handlers ---

  @impl true
  def handle_info(%Jido.Signal{type: "murmur.message.completed", data: data}, socket) do
    session_id = data.session_id
    response = data.response

    # Try to reload full history from agent thread to capture thinking/tool calls.
    # Falls back to appending the response text if thread hasn't been populated
    # (e.g. when using a mock LLM adapter in tests).
    session = find_session(socket, session_id)
    current_messages = Map.get(socket.assigns.messages, session_id, [])

    messages =
      if session do
        loaded = WorkspaceState.load_messages_for_session(session)

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
  def handle_info(%Jido.Signal{type: "murmur.request.failed", data: data}, socket) do
    session_id = data.session_id
    reason = data.reason
    error_msg = %{
      id: Uniq.UUID.uuid7(),
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
  def handle_info(%Jido.Signal{type: "murmur.message.received", data: data}, socket) do
    session_id = data.session_id
    message = data.message

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
  def handle_info(%Jido.Signal{type: "ai.llm.delta", data: data} = signal, socket) do
    session_id = extract_session_id(signal)

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
  def handle_info(%Jido.Signal{type: "ai.llm.response"} = signal, socket) do
    session_id = extract_session_id(signal)

    # Ignore stale signals that arrive after the request has completed
    if Map.get(socket.assigns.agent_statuses, session_id) == :idle do
      {:noreply, socket}
    else
      tool_calls = LLMResponse.extract_tool_calls(signal)

      if tool_calls != [] do
        pending = Enum.map(tool_calls, &build_pending_tool_call/1)
        {:noreply, append_streaming_tool_calls(socket, session_id, pending)}
      else
        {:noreply, socket}
      end
    end
  end

  @impl true
  def handle_info(%Jido.Signal{type: "ai.tool.result", data: data} = signal, socket) do
    session_id = extract_session_id(signal)

    # Ignore stale signals that arrive after the request has completed
    if Map.get(socket.assigns.agent_statuses, session_id) == :idle do
      {:noreply, socket}
    else
      call_id = data[:call_id] || data["call_id"]
      tool_name = data[:tool_name] || data["tool_name"] || "tool"
      result = data[:result] || data["result"]
      formatted_result = format_tool_result(result)
      status = tool_result_status(result)

      completed = %{id: call_id, name: tool_name, result: formatted_result, status: status}
      {:noreply, merge_tool_result(socket, session_id, completed)}
    end
  end

  @impl true
  def handle_info(%Jido.Signal{type: "ai.usage", data: data} = signal, socket) do
    session_id = extract_session_id(signal)
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
          Map.update(s, :usage, usage, &merge_usage_or_set(&1, usage))
        end)
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "ai." <> _}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "artifact." <> _name, data: %SignalUpdate{} = data} = signal, socket) do
    session_id = extract_session_id(signal)
    artifact_name = data.name
    artifact_envelope = data.envelope

    socket =
      update(socket, :artifacts, fn artifacts ->
        session_artifacts = Map.get(artifacts, session_id, %{})

        updated =
          case artifact_envelope do
            %Envelope{} = envelope ->
              Map.put(session_artifacts, artifact_name, envelope)

            nil ->
              Map.delete(session_artifacts, artifact_name)
          end

        Map.put(artifacts, session_id, updated)
      end)

    socket =
      if is_nil(socket.assigns.active_artifact) do
        assign(socket, :active_artifact, %{session_id: session_id, name: artifact_name})
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "task.created", data: %{task: task}}, socket) do
    {:noreply, update(socket, :tasks, &(&1 ++ [task]))}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "task.updated", data: %{task: task}}, socket) do
    {:noreply,
     update(socket, :tasks, fn tasks ->
       Enum.map(tasks, fn t -> if t.id == task.id, do: task, else: t end)
     end)}
  end

  # Catch-all for other messages
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Agent Communication ---

  defp send_to_agent(session, _content, _topic) when is_nil(session), do: :ok

  defp send_to_agent(session, content, _topic) do
    JidoMurmur.Ingress.deliver(session, content)
  end

  defp notify_task_assignee(workspace_id, task, sender_name) do
    if task.assignee == "human" or task.assignee == sender_name do
      :ok
    else
      do_notify_task_assignee(workspace_id, task, sender_name)
    end
  end

  defp do_notify_task_assignee(workspace_id, task, sender_name) do
    case Workspaces.find_agent_session_by_name(workspace_id, task.assignee) do
      nil ->
        :ok

      target_session ->
        message = build_task_notification(task, sender_name)
        JidoMurmur.Ingress.deliver_programmatic(target_session, message,
          via: :task_assignment,
          sender_name: sender_name
        )
    end
  end

  defp build_task_notification(task, sender_name) do
    "[#{sender_name}] assigned you a task: \"#{task.title}\"" <>
      if(task.description && task.description != "",
        do: "\nDescription: #{task.description}",
        else: ""
      ) <>
      "\nTask ID: #{task.id}" <>
      "\nUse update_task to change its status when you start or complete it."
  end

  # --- Thread / State Helpers ---

  defp update_streaming(socket, session_id, field, delta) do
    update(socket, :streaming, fn streams ->
      Map.update(streams, session_id, Map.put(@empty_stream, field, delta), fn s ->
        Map.update(s, field, delta, &(&1 <> delta))
      end)
    end)
  end

  defp build_pending_tool_call(tc) do
    %{
      id: tc[:id] || tc["id"],
      name: tc[:name] || tc["name"] || "tool",
      args: tc[:arguments] || tc["arguments"] || %{},
      result: nil,
      status: :running
    }
  end

  defp append_streaming_tool_calls(socket, session_id, pending) do
    update(socket, :streaming, fn streams ->
      Map.update(streams, session_id, Map.put(@empty_stream, :tool_calls, pending), fn s ->
        Map.update(s, :tool_calls, pending, &(&1 ++ pending))
      end)
    end)
  end

  defp merge_tool_result(socket, session_id, %{id: call_id} = completed) do
    update(socket, :streaming, fn streams ->
      Map.update(streams, session_id, @empty_stream, fn s ->
        Map.update(s, :tool_calls, [], &update_or_append_tool_call(&1, call_id, completed))
      end)
    end)
  end

  defp update_or_append_tool_call(tcs, call_id, completed) do
    if call_id && Enum.any?(tcs, &(&1[:id] == call_id)),
      do: Enum.map(tcs, &maybe_merge_tool_call(&1, call_id, completed)),
      else: tcs ++ [completed]
  end

  defp maybe_merge_tool_call(%{id: id} = tc, call_id, completed) when id == call_id,
    do: Map.merge(tc, completed)

  defp maybe_merge_tool_call(tc, _call_id, _completed), do: tc

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

  defp merge_usage_or_set(nil, usage), do: usage
  defp merge_usage_or_set(prev, usage), do: merge_usage(prev, usage)

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

  defp cleanup_storage(session) do
    {adapter, opts} = Murmur.Jido.__jido_storage__()
    agent_module = Catalog.agent_module(session.agent_profile_id)
    checkpoint_key = {agent_module, session.id}

    adapter.delete_checkpoint(checkpoint_key, opts)
    adapter.delete_thread(session.id, opts)
    ConversationCache.delete(session.id)
  rescue
    e ->
      Logger.warning("Failed to cleanup storage for session #{session.id}: #{Exception.message(e)}")

      :ok
  end

  # --- Agent Lifecycle ---

  defp ensure_agent_started(session) do
    # Populate observability cache so the tracer can enrich spans
    SessionCache.put(session.id, session.workspace_id, session.display_name)

    case Murmur.Jido.whereis(session.id) do
      nil ->
        agent_module = Catalog.agent_module(session.agent_profile_id)

        # Try to restore agent from storage so it retains conversation history.
        # Falls back to a fresh agent if no checkpoint exists.
        {agent, extra_opts} =
          case Murmur.Jido.thaw(agent_module, session.id) do
            {:ok, thawed_agent} ->
              thawed_agent = put_in(thawed_agent.state[:workspace_id], session.workspace_id)
              {thawed_agent, [agent_module: agent_module]}

            {:error, :not_found} ->
              {agent_module, [initial_state: %{workspace_id: session.workspace_id}]}
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

  # --- Helpers ---

  defp extract_session_id(%Jido.Signal{subject: "/agents/" <> session_id}), do: session_id

  defp extract_session_id(%Jido.Signal{subject: subject}) when is_binary(subject) do
    case Regex.run(~r{/agents/([^/]+)$}, subject) do
      [_, session_id] -> session_id
      _ -> nil
    end
  end

  defp extract_session_id(_), do: nil

  defp find_session(socket, session_id) do
    Enum.find(socket.assigns.agent_sessions, &(&1.id == session_id))
  end

  defp send_to_target(socket, nil, _content) do
    {:noreply, put_flash(socket, :error, "No agents available. Add an agent first.")}
  end

  defp send_to_target(socket, target_session, content) do
    workspace_id = socket.assigns.workspace.id
    topic = Topics.agent_messages(workspace_id, target_session.id)

    user_msg = %{
      id: Uniq.UUID.uuid7(),
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

  defp append_assistant_message(messages, response) do
    content = extract_response_content(response)

    assistant_msg = %{
      id: Uniq.UUID.uuid7(),
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
end
