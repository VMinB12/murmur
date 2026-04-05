defmodule JidoMurmur.TableOwnerTest do
  use ExUnit.Case

  setup do
    # In umbrella, TableOwner may already be running from murmur_demo's supervisor.
    # We only need to verify the tables exist — don't restart if already running.
    case Process.whereis(JidoMurmur.TableOwner) do
      nil ->
        # Clean up any stale tables
        for table <- [
              :jido_murmur_active_runners,
              :jido_murmur_obs_turns,
              :jido_murmur_obs_agent_turns,
              :jido_murmur_obs_llm_spans,
              :jido_murmur_obs_tool_spans,
              :jido_murmur_obs_tool_inputs,
              :jido_murmur_obs_req_llm_lookup,
              :jido_murmur_obs_sessions
            ] do
          if :ets.whereis(table) != :undefined do
            :ets.delete(table)
          end
        end

        pid = start_supervised!(JidoMurmur.TableOwner)
        %{pid: pid}

      pid ->
        %{pid: pid}
    end
  end

  describe "start_link/1" do
    test "creates ETS tables on init" do
      assert :ets.whereis(:jido_murmur_active_runners) != :undefined
      assert :ets.whereis(:jido_murmur_obs_turns) != :undefined
      assert :ets.whereis(:jido_murmur_obs_llm_spans) != :undefined
      assert :ets.whereis(:jido_murmur_obs_sessions) != :undefined
    end

    test "active_runners table is a set" do
      info = :ets.info(:jido_murmur_active_runners)
      assert info[:type] == :set
    end

    test "observability tables are sets" do
      assert :ets.info(:jido_murmur_obs_turns)[:type] == :set
      assert :ets.info(:jido_murmur_obs_agent_turns)[:type] == :set
      assert :ets.info(:jido_murmur_obs_llm_spans)[:type] == :set
      assert :ets.info(:jido_murmur_obs_tool_spans)[:type] == :set
    end

    test "tables are public" do
      assert :ets.info(:jido_murmur_active_runners)[:protection] == :public
      assert :ets.info(:jido_murmur_obs_turns)[:protection] == :public
      assert :ets.info(:jido_murmur_obs_sessions)[:protection] == :public
    end

    test "tables are named tables" do
      assert :ets.info(:jido_murmur_active_runners)[:named_table] == true
      assert :ets.info(:jido_murmur_obs_turns)[:named_table] == true
      assert :ets.info(:jido_murmur_obs_sessions)[:named_table] == true
    end
  end
end
