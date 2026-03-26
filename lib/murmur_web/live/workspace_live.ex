defmodule MurmurWeb.WorkspaceLive do
  use MurmurWeb, :live_view

  alias Murmur.Agents.{Catalog, Runner, UITurn}
  alias Murmur.Workspaces

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
      |> assign(:streaming_tokens, Map.new(agent_sessions, &{&1.id, ""}))
      |> assign(:messages, messages_map)
      |> assign(:view_mode, :split)
      |> assign(:add_agent_form, to_form(%{"profile_id" => "", "display_name" => ""}, as: :agent))

    socket =
      if connected?(socket) do
        Enum.reduce(agent_sessions, socket, fn session, acc ->
          topic = agent_topic(workspace_id, session.id)
          Phoenix.PubSub.subscribe(Murmur.PubSub, topic)
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
  def handle_event(
        "send_message",
        %{"message" => %{"content" => content, "session_id" => session_id}},
        socket
      ) do
    content = String.trim(content)

    if content == "" do
      {:noreply, socket}
    else
      session = Workspaces.get_agent_session!(session_id)
      workspace_id = socket.assigns.workspace.id
      topic = agent_topic(workspace_id, session_id)

      # Add user message to local display immediately
      user_msg = %{
        id: Ecto.UUID.generate(),
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
  def handle_event(
        "add_agent",
        %{"agent" => %{"profile_id" => profile_id, "display_name" => display_name}},
        socket
      ) do
    workspace = socket.assigns.workspace

    case Workspaces.create_agent_session(workspace.id, %{
           "agent_profile_id" => profile_id,
           "display_name" => display_name
         }) do
      {:ok, session} ->
        topic = agent_topic(workspace.id, session.id)
        Phoenix.PubSub.subscribe(Murmur.PubSub, topic)
        ensure_agent_started(session)

        socket =
          socket
          |> update(:agent_sessions, &(&1 ++ [session]))
          |> update(:messages, &Map.put(&1, session.id, []))
          |> update(:agent_statuses, &Map.put(&1, session.id, :idle))
          |> update(:streaming_tokens, &Map.put(&1, session.id, ""))
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
    empty_tokens = Map.new(socket.assigns.agent_sessions, &{&1.id, ""})

    {:noreply,
     socket
     |> assign(:messages, empty_messages)
     |> assign(:agent_statuses, empty_statuses)
     |> assign(:streaming_tokens, empty_tokens)}
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
      |> update(:streaming_tokens, &Map.delete(&1, session_id))

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

    socket =
      socket
      |> update(:messages, &Map.put(&1, session_id, messages))
      |> update(:agent_statuses, &Map.put(&1, session_id, :idle))
      |> update(:streaming_tokens, &Map.put(&1, session_id, ""))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:request_failed, session_id, reason}, socket) do
    error_msg = %{
      id: Ecto.UUID.generate(),
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
        update(socket, :streaming_tokens, &Map.put(&1, session_id, ""))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:streaming_token, session_id, token}, socket) do
    socket =
      update(socket, :streaming_tokens, fn tokens ->
        Map.update(tokens, session_id, token, &(&1 <> token))
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
    _ -> :ok
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
      id: Ecto.UUID.generate(),
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
      profile_id = if session, do: session.agent_profile_id, else: nil

      Enum.map(msgs, fn msg ->
        Map.merge(msg, %{
          session_id: session_id,
          agent_name: agent_name,
          agent_color: agent_color(profile_id, agent_name)
        })
      end)
    end)
    |> Enum.sort_by(& &1.id)
  end

  @agent_colors [
    "bg-blue-500",
    "bg-emerald-500",
    "bg-violet-500",
    "bg-amber-500",
    "bg-rose-500",
    "bg-cyan-500",
    "bg-fuchsia-500",
    "bg-lime-500"
  ]

  @agent_text_colors [
    "text-blue-500",
    "text-emerald-500",
    "text-violet-500",
    "text-amber-500",
    "text-rose-500",
    "text-cyan-500",
    "text-fuchsia-500",
    "text-lime-500"
  ]

  @agent_bg_colors [
    "bg-blue-500/10",
    "bg-emerald-500/10",
    "bg-violet-500/10",
    "bg-amber-500/10",
    "bg-rose-500/10",
    "bg-cyan-500/10",
    "bg-fuchsia-500/10",
    "bg-lime-500/10"
  ]

  @doc false
  def agent_color(_profile_id, agent_name) do
    idx = :erlang.phash2(agent_name, length(@agent_colors))

    %{
      dot: Enum.at(@agent_colors, idx),
      text: Enum.at(@agent_text_colors, idx),
      bg: Enum.at(@agent_bg_colors, idx)
    }
  end

  defp append_assistant_message(messages, response) do
    content = extract_response_content(response)

    assistant_msg = %{
      id: Ecto.UUID.generate(),
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

  defp agent_header_class(profile_id) do
    case profile_id do
      "general_agent" -> "border-blue-500/20 bg-blue-500/5"
      "code_agent" -> "border-emerald-500/20 bg-emerald-500/5"
      _ -> "border-base-300 bg-base-200/30"
    end
  end

  defp agent_dot_class(profile_id) do
    case profile_id do
      "general_agent" -> "bg-blue-500"
      "code_agent" -> "bg-emerald-500"
      _ -> "bg-gray-500"
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
end
