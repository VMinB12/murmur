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
      alias JidoMurmur.Workspaces.Workspace
      alias JidoMurmur.Workspaces.AgentSession
      alias JidoMurmur.Storage.Checkpoint
      alias JidoMurmur.Storage.ThreadEntry
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(JidoMurmur.repo(), shared: !tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
