defmodule Murmur.Storage.Ecto do
  @moduledoc """
  Ecto/PostgreSQL storage adapter implementing `Jido.Storage` behaviour.

  Stores agent checkpoints as JSONB rows and thread entries as individual rows
  with sequence ordering and optimistic concurrency control.
  """

  @behaviour Jido.Storage

  import Ecto.Query

  alias Jido.Thread
  alias Jido.Thread.Entry
  alias Jido.Thread.EntryNormalizer
  alias Murmur.Repo
  alias Murmur.Storage.Checkpoint
  alias Murmur.Storage.ThreadEntry

  # --- Checkpoints ---

  @impl true
  def get_checkpoint(key, _opts) do
    key_str = serialize_key(key)

    case Repo.get(Checkpoint, key_str) do
      nil -> :not_found
      %Checkpoint{data: data} -> {:ok, deserialize_checkpoint(data)}
    end
  end

  @impl true
  def put_checkpoint(key, data, _opts) do
    key_str = serialize_key(key)
    serialized = serialize_checkpoint(data)

    case Repo.get(Checkpoint, key_str) do
      nil ->
        Repo.insert!(%Checkpoint{key: key_str, data: serialized})

      existing ->
        existing
        |> Ecto.Changeset.change(data: serialized)
        |> Repo.update!()
    end

    :ok
  end

  @impl true
  def delete_checkpoint(key, _opts) do
    key_str = serialize_key(key)

    case Repo.get(Checkpoint, key_str) do
      nil -> :ok
      existing -> Repo.delete!(existing)
    end

    :ok
  end

  # --- Threads ---

  @impl true
  def load_thread(thread_id, _opts) do
    entries =
      Repo.all(
        from e in ThreadEntry,
          where: e.thread_id == ^thread_id,
          order_by: [asc: e.seq]
      )

    case entries do
      [] ->
        :not_found

      rows ->
        thread_entries = Enum.map(rows, &row_to_entry/1)
        {:ok, reconstruct_thread(thread_id, thread_entries)}
    end
  end

  @impl true
  def append_thread(thread_id, entries, opts) do
    expected_rev = Keyword.get(opts, :expected_rev)
    now = System.system_time(:millisecond)

    current_rev = get_current_rev(thread_id)

    case validate_expected_rev(expected_rev, current_rev) do
      :ok ->
        prepared = EntryNormalizer.normalize_many(entries, current_rev, now)

        Enum.each(prepared, fn entry ->
          Repo.insert!(%ThreadEntry{
            thread_id: thread_id,
            seq: entry.seq,
            kind: to_string(entry.kind),
            payload: entry.payload || %{},
            refs: entry.refs || %{},
            at: entry.at
          })
        end)

        load_thread(thread_id, opts)

      {:error, :conflict} ->
        {:error, :conflict}
    end
  end

  @impl true
  def delete_thread(thread_id, _opts) do
    Repo.delete_all(from e in ThreadEntry, where: e.thread_id == ^thread_id)
    :ok
  end

  # --- Private ---

  defp get_current_rev(thread_id) do
    Repo.one(
      from e in ThreadEntry,
        where: e.thread_id == ^thread_id,
        select: count(e.id)
    ) || 0
  end

  defp validate_expected_rev(nil, _current_rev), do: :ok
  defp validate_expected_rev(expected, current) when expected == current, do: :ok
  defp validate_expected_rev(_expected, _current), do: {:error, :conflict}

  defp row_to_entry(%ThreadEntry{} = row) do
    Entry.new(%{
      id: row.id,
      seq: row.seq,
      at: row.at,
      kind: String.to_existing_atom(row.kind),
      payload: row.payload || %{},
      refs: row.refs || %{}
    })
  end

  defp reconstruct_thread(thread_id, entries) do
    entry_count = length(entries)
    first = List.first(entries)
    last = List.last(entries)

    %Thread{
      id: thread_id,
      rev: entry_count,
      entries: entries,
      created_at: first && first.at,
      updated_at: last && last.at,
      metadata: %{},
      stats: %{entry_count: entry_count}
    }
  end

  defp serialize_key(key) when is_binary(key), do: key
  defp serialize_key(key) when is_tuple(key), do: key |> :erlang.term_to_binary() |> Base.encode64()
  defp serialize_key(key), do: inspect(key)

  defp serialize_checkpoint(data) do
    %{"__term__" => Base.encode64(:erlang.term_to_binary(data))}
  end

  defp deserialize_checkpoint(%{"__term__" => encoded}) do
    encoded |> Base.decode64!() |> :erlang.binary_to_term([:safe])
  end

  defp deserialize_checkpoint(data) when is_map(data), do: deep_from_serializable(data)

  defp deep_from_serializable(%{"__term__" => encoded}) do
    encoded |> Base.decode64!() |> :erlang.binary_to_term([:safe])
  end

  defp deep_from_serializable(%{"__tuple2__" => [a, b]}) do
    {deep_from_serializable(a), deep_from_serializable(b)}
  end

  defp deep_from_serializable(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key =
        case k do
          "__atom__:" <> atom_str -> String.to_existing_atom(atom_str)
          other -> other
        end

      {key, deep_from_serializable(v)}
    end)
  end

  defp deep_from_serializable(list) when is_list(list) do
    Enum.map(list, &deep_from_serializable/1)
  end

  defp deep_from_serializable("__atom__:" <> atom_str), do: String.to_existing_atom(atom_str)
  defp deep_from_serializable(value), do: value
end
