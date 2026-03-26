defmodule Murmur.Agents.TableOwner do
  @moduledoc """
  Owns the ETS tables used by PendingQueue and Runner.

  By placing this GenServer in the supervision tree, the ETS tables
  survive individual process crashes (they die only if this owner dies,
  which triggers a supervisor restart that recreates them).
  """

  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    :ets.new(:murmur_pending_messages, [:named_table, :public, :duplicate_bag])
    :ets.new(:murmur_active_runners, [:set, :public, :named_table])
    {:ok, %{}}
  end
end
