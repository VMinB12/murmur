defmodule JidoMurmurWeb.Components.AgentSelector do
  @moduledoc """
  Renders an agent profile selector dialog for adding agents to a workspace.

  ## Example

      <.agent_selector profiles={@profiles} />
  """

  use Phoenix.Component

  @doc """
  Renders an add-agent dialog with profile selection and display name input.

  ## Attributes

    * `profiles` — List of agent profile maps with `:id` and `:description`.
    * `form` — Form data for the agent creation form.
    * `dialog_id` — DOM ID for the dialog element (default: `"add-agent-dialog"`).
    * `on_submit` — Event name for form submission (default: `"add_agent"`).
  """
  attr :profiles, :list, required: true
  attr :form, :any, required: true
  attr :dialog_id, :string, default: "add-agent-dialog"
  attr :on_submit, :string, default: "add_agent"

  def agent_selector(assigns) do
    ~H"""
    <dialog id={@dialog_id} class="modal">
      <div class="modal-box">
        <h3 class="font-bold text-lg mb-4">Add Agent to Workspace</h3>
        <.form for={@form} id="add-agent-form" phx-submit={@on_submit} class="space-y-4">
          <div class="form-control">
            <label class="label"><span class="label-text">Agent Profile</span></label>
            <select name="agent[profile_id]" class="select select-bordered w-full" required>
              <option value="" disabled selected>Choose a profile...</option>
              <%= for profile <- @profiles do %>
                <option value={profile.id}>{profile.id} — {profile.description}</option>
              <% end %>
            </select>
          </div>
          <div class="form-control">
            <label class="label"><span class="label-text">Display Name</span></label>
            <input
              type="text"
              name="agent[display_name]"
              class="input input-bordered w-full"
              placeholder="e.g. Research Assistant"
              required
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">
                Must be unique within this workspace
              </span>
            </label>
          </div>
          <div class="modal-action">
            <button
              type="button"
              class="btn"
              onclick={"document.getElementById('#{@dialog_id}').close()"}
            >
              Cancel
            </button>
            <button
              type="submit"
              class="btn btn-primary"
              onclick={"document.getElementById('#{@dialog_id}').close()"}
            >
              Add Agent
            </button>
          </div>
        </.form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button>close</button>
      </form>
    </dialog>
    """
  end
end
