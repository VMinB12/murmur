defmodule JidoMurmur.Case do
  @moduledoc """
  Test case template for jido_murmur tests with Ecto sandbox checkout.

  ## Usage

      use JidoMurmur.Case

  Or for async tests:

      use JidoMurmur.Case, async: true
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      alias Ecto.Adapters.SQL.Sandbox
      alias JidoMurmur.Storage.Checkpoint
      alias JidoMurmur.Storage.ThreadEntry
      alias JidoMurmur.Workspaces.AgentSession
      alias JidoMurmur.Workspaces.Workspace
    end
  end

  alias Ecto.Adapters.SQL.Sandbox

  setup tags do
    pid = Sandbox.start_owner!(JidoMurmur.repo(), shared: !tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
