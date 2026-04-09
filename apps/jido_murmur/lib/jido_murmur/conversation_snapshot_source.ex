defmodule JidoMurmur.ConversationSnapshotSource do
  @moduledoc """
  Internal boundary for sourcing replay-ready conversation entries.

  The projector consumes this normalized source contract instead of performing
  ad hoc runtime lookup, thaw-driven recovery, or storage selection itself.
  """

  require Logger

  alias JidoMurmur.SessionContract

  @enforce_keys [:entries, :persisted_rev, :source]
  defstruct [:entries, :persisted_rev, :source]

  @type source :: :live_thread | :storage

  @type t :: %__MODULE__{
          entries: list(),
          persisted_rev: non_neg_integer(),
          source: source()
        }

  @spec load(SessionContract.identity()) :: t()
  def load(%{id: session_id, workspace_id: workspace_id})
      when is_binary(session_id) and is_binary(workspace_id) do
    case load_from_live_thread(session_id) do
      %__MODULE__{} = source -> source
      nil -> load_from_storage(session_id)
    end
  end

  @spec from_agent(map()) :: t() | nil
  def from_agent(%{state: %{__thread__: %{entries: entries} = thread}}) when is_list(entries) do
    build_source(:live_thread, thread)
  end

  def from_agent(_agent), do: nil

  defp load_from_live_thread(session_id) do
    jido_mod = JidoMurmur.jido_mod()

    case safe_whereis(jido_mod, session_id) do
      pid when is_pid(pid) ->
        case Jido.AgentServer.state(pid) do
          {:ok, %{agent: agent}} -> from_agent(agent)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp load_from_storage(session_id) do
    {adapter, opts} = JidoMurmur.jido_mod().__jido_storage__()

    case adapter.load_thread(session_id, opts) do
      {:ok, %{entries: entries} = thread} when is_list(entries) ->
        build_source(:storage, thread)

      :not_found ->
        empty_source(:storage)

      _ ->
        empty_source(:storage)
    end
  rescue
    error ->
      Logger.warning(
        "Failed to load persisted conversation thread for snapshot #{session_id}: #{Exception.message(error)}"
      )

      empty_source(:storage)
  end

  defp build_source(source, %{entries: entries} = thread) when is_list(entries) do
    %__MODULE__{
      entries: entries,
      persisted_rev: normalize_persisted_rev(Map.get(thread, :rev), entries),
      source: source
    }
  end

  defp empty_source(source) do
    %__MODULE__{entries: [], persisted_rev: 0, source: source}
  end

  defp normalize_persisted_rev(rev, _entries) when is_integer(rev) and rev >= 0, do: rev
  defp normalize_persisted_rev(_rev, entries), do: length(entries)

  defp safe_whereis(jido_mod, session_id) do
    jido_mod.whereis(session_id)
  rescue
    ArgumentError -> nil
  end
end
