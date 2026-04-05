defmodule JidoMurmur.TableOwner do
  @moduledoc """
  Owns the ETS tables used by Runner and observability.

  Named tables are prefixed with `jido_murmur_` to prevent collisions
  when running alongside other applications on the same BEAM node.
  """
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  alias JidoMurmur.Observability.ConversationCache
  alias JidoMurmur.Observability.SessionCache
  alias JidoMurmur.Observability.Store

  @impl true
  def init(_opts) do
    :ets.new(:jido_murmur_active_runners, [:set, :public, :named_table])
    ConversationCache.create_table()
    SessionCache.create_table()
    Store.create_tables()
    {:ok, %{}}
  end
end
