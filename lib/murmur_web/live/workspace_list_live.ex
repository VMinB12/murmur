defmodule MurmurWeb.WorkspaceListLive do
  use MurmurWeb, :live_view

  alias Murmur.Workspaces

  @impl true
  def mount(_params, _session, socket) do
    workspaces = Workspaces.list_workspaces()

    socket =
      socket
      |> assign(:workspaces, workspaces)
      |> assign(:form, to_form(%{"name" => ""}, as: :workspace))

    {:ok, socket}
  end

  @impl true
  def handle_event("create_workspace", %{"workspace" => %{"name" => name}}, socket) do
    case Workspaces.create_workspace(%{name: name}) do
      {:ok, workspace} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/workspaces/#{workspace.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
