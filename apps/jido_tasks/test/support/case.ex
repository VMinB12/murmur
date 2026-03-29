defmodule JidoTasks.Case do
  @moduledoc """
  Test case template for jido_tasks tests with Ecto sandbox checkout.

  ## Usage

      use JidoTasks.Case

  Or for async tests:

      use JidoTasks.Case, async: true
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query
      alias JidoTasks.Task
      alias JidoTasks.Tasks
    end
  end

  alias Ecto.Adapters.SQL.Sandbox

  setup tags do
    pid = Sandbox.start_owner!(JidoTasks.repo(), shared: !tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
