defmodule JidoMurmurWeb do
  @moduledoc """
  Pre-built LiveView components for jido_murmur multi-agent chat.

  ## Usage

  Import all components at once:

      import JidoMurmurWeb.Components

  Or import individual component modules:

      alias JidoMurmurWeb.Components.ChatMessage
      alias JidoMurmurWeb.Components.StreamingIndicator
  """

  use Phoenix.Component

  @doc """
  Renders a hero icon.

  Delegates to a `<span>` with the icon name as a CSS class, matching the
  pattern used by Phoenix-generated `core_components.ex`. Your application
  must include the `heroicons` dependency for the icons to render visually.

  ## Examples

      <JidoMurmurWeb.icon name="hero-chat-bubble-left" class="w-4 h-4" />
  """
  attr :name, :string, required: true
  attr :class, :string, default: nil

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end
end
