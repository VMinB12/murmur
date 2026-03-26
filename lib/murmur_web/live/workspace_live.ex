defmodule MurmurWeb.WorkspaceLive do
  use MurmurWeb, :live_view

  alias Murmur.Agents.{Catalog, Runner}
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
    content = extract_response_content(response)

    assistant_msg = %{
      id: Ecto.UUID.generate(),
      role: "assistant",
      content: content,
      sender_name: nil
    }

    socket =
      socket
      |> update(:messages, fn msgs ->
        Map.update(msgs, session_id, [assistant_msg], &(&1 ++ [assistant_msg]))
      end)
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
      thread.entries
      |> Enum.filter(&(&1.kind in [:message, :ai_message]))
      |> Enum.map(fn entry ->
        %{
          id: entry.id || Ecto.UUID.generate(),
          role: to_string(entry.payload[:role] || entry.payload["role"] || "assistant"),
          content: entry.payload[:content] || entry.payload["content"] || "",
          sender_name: entry.payload[:sender_name] || entry.payload["sender_name"]
        }
      end)
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
