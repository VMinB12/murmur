defmodule JidoMurmur.SupervisorTest do
  use ExUnit.Case

  describe "start_link/1" do
    test "starts the supervisor and its children" do
      # In umbrella, supervisor may already be running from murmur_demo
      case JidoMurmur.Supervisor.start_link([]) do
        {:ok, pid} ->
          assert Process.alive?(pid)
          assert Process.whereis(JidoMurmur.TableOwner) != nil
          Supervisor.stop(pid)

        {:error, {:already_started, pid}} ->
          assert Process.alive?(pid)
          assert Process.whereis(JidoMurmur.TableOwner) != nil
      end
    end

    test "child_spec uses correct module name" do
      spec = JidoMurmur.Supervisor.child_spec([])
      assert spec.id == JidoMurmur.Supervisor
      assert spec.start == {JidoMurmur.Supervisor, :start_link, [[]]}
    end
  end

  describe "supervision tree" do
    test "restarts TableOwner on crash" do
      # Ensure supervisor is running
      _sup_pid =
        case JidoMurmur.Supervisor.start_link([]) do
          {:ok, pid} -> pid
          {:error, {:already_started, pid}} -> pid
        end

      table_owner_pid = Process.whereis(JidoMurmur.TableOwner)
      assert table_owner_pid != nil

      ref = Process.monitor(table_owner_pid)
      Process.exit(table_owner_pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^table_owner_pid, :killed}

      # Give supervisor time to restart the child
      Process.sleep(50)

      new_pid = Process.whereis(JidoMurmur.TableOwner)
      assert new_pid != nil
      assert new_pid != table_owner_pid
    end
  end
end
