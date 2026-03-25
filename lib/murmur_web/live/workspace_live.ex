defmodule MurmurWeb.WorkspaceLive do
  use MurmurWeb, :live_view

  alias Murmur.Agents.{Catalog, PubSubBridge}
  alias Murmur.Chat
  alias Murmur.Workspaces

  @impl true
  def mount(%{"id" => workspace_id}, _session, socket) do
    workspace = Workspaces.get_workspace!(workspace_id)
    agent_sessions = Workspaces.list_agent_sessions(workspace_id)
    profiles = Catalog.list_profiles()

    # Build initial messages map from DB
    messages_map =
      Map.new(agent_sessions, fn session ->
        {session.id, Chat.list_messages(session.id)}
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
          topic = PubSubBridge.topic(workspace_id, session.id)
          Phoenix.PubSub.subscribe(Murmur.PubSub, topic)
          PubSubBridge.start_agent(session)

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

      {:ok, user_msg} =
        Chat.create_message(%{
          agent_session_id: session_id,
          role: "user",
          content: content,
          sender_name: "You"
        })

      topic = PubSubBridge.topic(socket.assigns.workspace.id, session_id)
      Phoenix.PubSub.broadcast(Murmur.PubSub, topic, {:new_message, session_id, user_msg})
      PubSubBridge.send_message(session, content)

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
        topic = PubSubBridge.topic(workspace.id, session.id)
        Phoenix.PubSub.subscribe(Murmur.PubSub, topic)
        PubSubBridge.start_agent(session)

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
    topic = PubSubBridge.topic(socket.assigns.workspace.id, session_id)
    Phoenix.PubSub.unsubscribe(Murmur.PubSub, topic)
    PubSubBridge.stop_agent(session_id)
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
  def handle_info({:new_message, session_id, message}, socket) do
    socket =
      update(socket, :messages, fn msgs ->
        Map.update(msgs, session_id, [message], &(&1 ++ [message]))
      end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({:status_change, session_id, status}, socket) do
    socket =
      socket
      |> update(:agent_statuses, &Map.put(&1, session_id, status))

    # Clear streaming tokens when going idle
    socket =
      if status == :idle do
        update(socket, :streaming_tokens, &Map.put(&1, session_id, ""))
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:message_completed, session_id, response}, socket) do
    {:ok, assistant_msg} =
      Chat.create_message(%{
        agent_session_id: session_id,
        role: "assistant",
        content: extract_response_content(response)
      })

    socket =
      socket
      |> update(:messages, fn msgs ->
        Map.update(msgs, session_id, [assistant_msg], &(&1 ++ [assistant_msg]))
      end)
      |> update(:streaming_tokens, &Map.put(&1, session_id, ""))

    {:noreply, socket}
  end

  @impl true
  def handle_info({:request_failed, session_id, reason}, socket) do
    {:ok, error_msg} =
      Chat.create_message(%{
        agent_session_id: session_id,
        role: "assistant",
        content: "⚠️ Error: #{inspect(reason)}"
      })

    socket =
      update(socket, :messages, fn msgs ->
        Map.update(msgs, session_id, [error_msg], &(&1 ++ [error_msg]))
      end)

    {:noreply, socket}
  end

  # Handle ReAct streaming events
  @impl true
  def handle_info(%{kind: :llm_delta, data: %{delta: _delta}} = _event, socket) do
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

  # Catch-all for other PubSub messages
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

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
