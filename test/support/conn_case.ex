defmodule MurmurWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MurmurWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint MurmurWeb.Endpoint

      use MurmurWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MurmurWeb.ConnCase
    end
  end

  setup tags do
    Murmur.DataCase.setup_sandbox(tags)

    # Set global Mox stubs so any Runner Tasks spawned by
    # LiveView form submissions use the mock LLM (no real API calls)
    Mox.set_mox_global()

    Mox.stub(Murmur.Agents.LLM.Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, make_ref()}
    end)

    Mox.stub(Murmur.Agents.LLM.Mock, :await, fn _mod, _handle, _opts ->
      {:ok, "mock response"}
    end)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
