defmodule MurmurWeb.WorkspaceLive do
  @moduledoc false
  use MurmurWeb, :live_view

  alias JidoArtifacts.Envelope
  alias JidoArtifacts.SignalUpdate
  alias JidoMurmur.AgentHelper
  alias JidoMurmur.Catalog
  alias JidoMurmur.Topics
  alias JidoMurmur.Workspaces
  alias JidoTasks.Signals.TaskCreated
  alias JidoTasks.Signals.TaskUpdated
  alias JidoTasks.Tasks
  alias MurmurWeb.Artifacts.Actions, as: ArtifactActions
  alias MurmurWeb.Live.WorkspaceState

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
      |> assign(:messages, messages_map)
      |> assign(:pending_messages, Map.new(agent_sessions, &{&1.id, []}))
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
          AgentHelper.subscribe(session)
          AgentHelper.start_agent(session)

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
      queue_direct_message(socket, session, content)
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
        AgentHelper.subscribe(session)
        AgentHelper.start_agent(session)

        socket =
          socket
          |> update(:agent_sessions, &(&1 ++ [session]))
          |> update(:messages, &Map.put(&1, session.id, []))
          |> update(:pending_messages, &Map.put(&1, session.id, []))
          |> update(:agent_statuses, &Map.put(&1, session.id, :idle))
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
      AgentHelper.stop_agent(session.id)
      AgentHelper.cleanup_session_storage(session)
    end)

    Tasks.delete_tasks_for_workspace(socket.assigns.workspace.id)

    # Restart agents fresh (no history)
    Enum.each(socket.assigns.agent_sessions, fn session ->
      AgentHelper.start_fresh_agent(session)
    end)

    empty_messages = Map.new(socket.assigns.agent_sessions, &{&1.id, []})
    empty_pending_messages = Map.new(socket.assigns.agent_sessions, &{&1.id, []})
    empty_statuses = Map.new(socket.assigns.agent_sessions, &{&1.id, :idle})
    empty_artifacts = Map.new(socket.assigns.agent_sessions, &{&1.id, %{}})

    {:noreply,
     socket
     |> assign(:messages, empty_messages)
      |> assign(:pending_messages, empty_pending_messages)
     |> assign(:agent_statuses, empty_statuses)
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

        notify_task_assignee(workspace_id, task)

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
    AgentHelper.unsubscribe(session)
    AgentHelper.stop_agent(session_id)
    AgentHelper.cleanup_session_storage(session)
    Workspaces.delete_agent_session(session)

    socket =
      socket
      |> update(:agent_sessions, fn sessions ->
        Enum.reject(sessions, &(&1.id == session_id))
      end)
      |> update(:messages, &Map.delete(&1, session_id))
      |> update(:pending_messages, &Map.delete(&1, session_id))
      |> update(:agent_statuses, &Map.delete(&1, session_id))
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
  def handle_info(%Jido.Signal{type: "murmur.message.completed", data: %{session_id: session_id}}, socket) do
    {:noreply, update(socket, :agent_statuses, &Map.put(&1, session_id, :idle))}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "murmur.request.failed", data: data}, socket) do
    session_id = data.session_id
    reason = data.reason
    error_msg = JidoMurmur.DisplayMessage.assistant("⚠️ Error: #{inspect(reason)}")

    socket =
      socket
      |> update(:messages, fn msgs ->
        Map.update(msgs, session_id, [error_msg], &append_message(&1, error_msg))
      end)
      |> update(:agent_statuses, &Map.put(&1, session_id, :idle))

    {:noreply, socket}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "murmur.message.received", data: data}, socket) do
    session_id = data.session_id
    message = JidoMurmur.DisplayMessage.from_received(data.message)

    socket =
      socket
      |> update(:pending_messages, fn pending_messages ->
        remove_pending_message(pending_messages, session_id, client_ref(data.message))
      end)
      |> update(:messages, fn msgs ->
        Map.update(msgs, session_id, [message], &upsert_message(&1, message))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:status_change, session_id, status}, socket) do
    {:noreply, update(socket, :agent_statuses, &Map.put(&1, session_id, status))}
  end

  @impl true
  def handle_info(%Jido.Signal{type: "murmur.conversation.updated", data: %{session_id: session_id, message: message}}, socket) do
    socket =
      update(socket, :messages, fn messages_map ->
        Map.update(messages_map, session_id, [message], &upsert_message(&1, message))
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

  defp send_to_agent(session, _content, _client_ref) when is_nil(session), do: :agent_not_running

  defp send_to_agent(session, content, client_ref) do
    JidoMurmur.Ingress.deliver(session, content, refs: %{client_ref: client_ref})
  end

  defp notify_task_assignee(workspace_id, task) do
    if task.assignee == "human" do
      :ok
    else
      do_notify_task_assignee(workspace_id, task)
    end
  end

  defp do_notify_task_assignee(workspace_id, task) do
    case Workspaces.find_agent_session_by_name(workspace_id, task.assignee) do
      nil ->
        :ok

      target_session ->
        message = build_task_notification(task)
        JidoMurmur.Ingress.deliver_programmatic(target_session, message,
          via: :task_assignment,
          sender_name: "human",
          origin_actor: JidoMurmur.ActorIdentity.human()
        )
    end
  end

  defp build_task_notification(task) do
    "A human assigned you a task: \"#{task.title}\"" <>
      if(task.description && task.description != "",
        do: "\nDescription: #{task.description}",
        else: ""
      ) <>
      "\nTask ID: #{task.id}" <>
      "\nUse update_task to change its status when you start or complete it."
  end

  # --- Thread / State Helpers ---

  defp upsert_message(messages, message) do
    updated =
      case Enum.find_index(messages, &(&1.id == message.id)) do
        nil -> messages ++ [message]
        index -> List.replace_at(messages, index, message)
      end

    JidoMurmur.DisplayMessage.sort_messages(updated)
  end

  defp append_message(messages, message) do
    JidoMurmur.DisplayMessage.sort_messages(messages ++ [message])
  end

  defp append_pending_message(pending_messages, session_id, content, client_ref) do
    pending_message = pending_user_message(content, client_ref)
    Map.update(pending_messages, session_id, [pending_message], &append_message(&1, pending_message))
  end

  defp remove_pending_message(pending_messages, _session_id, nil), do: pending_messages

  defp remove_pending_message(pending_messages, session_id, client_ref) do
    Map.update(pending_messages, session_id, [], fn messages ->
      Enum.reject(messages, &(Map.get(&1, :client_ref) == client_ref))
    end)
  end

  defp pending_user_message(content, client_ref) do
    content
    |> JidoMurmur.DisplayMessage.user(id: "pending-" <> client_ref)
    |> Map.from_struct()
    |> Map.put(:client_ref, client_ref)
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

  defp send_to_target(socket, nil, _content) do
    {:noreply, put_flash(socket, :error, "No agents available. Add an agent first.")}
  end

  defp send_to_target(socket, target_session, content) do
    queue_direct_message(socket, target_session, content)
  end

  defp queue_direct_message(socket, session, content) do
    client_ref = Ecto.UUID.generate()

    case send_to_agent(session, content, client_ref) do
      :queued ->
        socket =
          socket
          |> update(:pending_messages, &append_pending_message(&1, session.id, content, client_ref))
          |> update(:agent_statuses, &Map.put(&1, session.id, :busy))

        {:noreply, socket}

      :agent_not_running ->
        {:noreply, put_flash(socket, :error, "The selected agent is not running.")}

      {:error, {:invalid_input, _reason}} ->
        {:noreply, put_flash(socket, :error, "Unable to send that message.")}
    end
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

  defp client_ref(message) when is_map(message) do
    Map.get(message, :client_ref) || Map.get(message, "client_ref")
  end

  defp client_ref(_message), do: nil
end
