defmodule JidoMurmur.TableOwnerTest do
  use ExUnit.Case

  setup do
    # In umbrella, TableOwner may already be running from murmur_demo's supervisor.
    # We only need to verify the tables exist — don't restart if already running.
    case Process.whereis(JidoMurmur.TableOwner) do
      nil ->
        # Clean up any stale tables
        for table <- [:jido_murmur_pending_messages, :jido_murmur_active_runners] do
          if :ets.whereis(table) != :undefined do
            :ets.delete(table)
          end
        end

        {:ok, pid} = start_supervised(JidoMurmur.TableOwner)
        %{pid: pid}

      pid ->
        %{pid: pid}
    end
  end

  describe "start_link/1" do
    test "creates ETS tables on init" do
      assert :ets.whereis(:jido_murmur_pending_messages) != :undefined
      assert :ets.whereis(:jido_murmur_active_runners) != :undefined
    end

    test "pending_messages table is a duplicate_bag" do
      info = :ets.info(:jido_murmur_pending_messages)
      assert info[:type] == :duplicate_bag
    end

    test "active_runners table is a set" do
      info = :ets.info(:jido_murmur_active_runners)
      assert info[:type] == :set
    end

    test "tables are public" do
      assert :ets.info(:jido_murmur_pending_messages)[:protection] == :public
      assert :ets.info(:jido_murmur_active_runners)[:protection] == :public
    end

    test "tables are named tables" do
      assert :ets.info(:jido_murmur_pending_messages)[:named_table] == true
      assert :ets.info(:jido_murmur_active_runners)[:named_table] == true
    end
  end
end
