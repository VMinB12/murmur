defmodule Murmur.AgentCase do
  @moduledoc """
  Shared helpers for agent tests that need the LLM mock.

  Use this case template when testing Runner, TellAction, or any
  code path that triggers an LLM ask/await cycle.

  ## Usage

      use Murmur.AgentCase

  Then in your tests, call `stub_llm_success/1` or `expect_llm_ask/1`
  to configure the mock's behavior.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Mox
      import Murmur.AgentCase

      alias Murmur.Agents.LLM.Mock, as: LLMMock
    end
  end

  setup tags do
    Murmur.DataCase.setup_sandbox(tags)

    # Allow the mock to be called from any process (Runner spawns Tasks)
    Mox.set_mox_global()

    # Set a safe default stub so lingering Runner Tasks don't crash
    # after the test exits. Tests override with stub_llm_success/1 etc.
    Mox.stub(Murmur.Agents.LLM.Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, make_ref()}
    end)

    Mox.stub(Murmur.Agents.LLM.Mock, :await, fn _mod, _handle, _opts ->
      {:ok, "default mock response"}
    end)

    :ok
  end

  @doc """
  Wait for the Runner drain loop to finish for a given session.
  Polls the ETS active-runner table until the session key is gone.
  """
  def await_runner(session_id, timeout \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_runner(session_id, deadline)
  end

  defp do_await_runner(session_id, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      :timeout
    else
      case :ets.lookup(:murmur_active_runners, session_id) do
        [] ->
          :ok

        _ ->
          Process.sleep(50)
          do_await_runner(session_id, deadline)
      end
    end
  end

  @doc """
  Stub the LLM mock to return a successful response immediately.

  The ask returns a fake handle, and await returns the given response string.
  """
  def stub_llm_success(response \\ "Mock LLM response") do
    handle = make_ref()

    Mox.stub(Murmur.Agents.LLM.Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, handle}
    end)

    Mox.stub(Murmur.Agents.LLM.Mock, :await, fn _mod, _handle, _opts ->
      {:ok, response}
    end)

    handle
  end

  @doc """
  Stub the LLM mock to return an error from ask.
  """
  def stub_llm_ask_error(reason \\ :api_error) do
    Mox.stub(Murmur.Agents.LLM.Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:error, reason}
    end)
  end

  @doc """
  Stub the LLM mock to return an error from await.
  """
  def stub_llm_await_error(reason \\ :timeout) do
    handle = make_ref()

    Mox.stub(Murmur.Agents.LLM.Mock, :ask, fn _mod, _pid, _content, _ctx ->
      {:ok, handle}
    end)

    Mox.stub(Murmur.Agents.LLM.Mock, :await, fn _mod, _handle, _opts ->
      {:error, reason}
    end)

    handle
  end

  @doc """
  Expect exactly `n` ask calls with a custom function. Useful for
  asserting on content or tool context passed to the LLM.
  """
  def expect_llm_ask(n \\ 1, fun) do
    Mox.expect(Murmur.Agents.LLM.Mock, :ask, n, fun)
  end

  @doc """
  Expect exactly `n` await calls with a custom function.
  """
  def expect_llm_await(n \\ 1, fun) do
    Mox.expect(Murmur.Agents.LLM.Mock, :await, n, fun)
  end
end
