defmodule JidoMurmur.TableOwner do
  @moduledoc """
  Owns the ETS tables used by PendingQueue and Runner.

  Named tables are prefixed with `jido_murmur_` to prevent collisions
  when running alongside other applications on the same BEAM node.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(:jido_murmur_pending_messages, [:named_table, :public, :duplicate_bag])
    :ets.new(:jido_murmur_active_runners, [:set, :public, :named_table])
    {:ok, %{}}
  end
end
