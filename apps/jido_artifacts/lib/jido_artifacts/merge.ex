defmodule JidoArtifacts.Merge do
  @moduledoc """
  Built-in merge helpers for artifact data.

  All helpers follow the signature `(existing :: term(), new :: term()) -> merged :: term()`.
  Pass these as the `:merge` option to `JidoArtifacts.Artifact.emit/4`.

  ## Examples

      # Append new items to an existing list
      Artifact.emit(ctx, "papers", new_papers, merge: &Merge.append/2)

      # Keep only the latest 50 items
      Artifact.emit(ctx, "papers", new_papers, merge: Merge.append_max(50))

      # Upsert by a key function
      Artifact.emit(ctx, "papers", new_papers, merge: Merge.upsert_by(& &1.id))
  """

  @doc """
  Appends new items to the existing list.

  If `existing` is nil, treats it as an empty list.
  """
  @spec append(term(), term()) :: list()
  def append(existing, new) do
    (existing || []) ++ List.wrap(new)
  end

  @doc """
  Prepends new items before the existing list.

  If `existing` is nil, treats it as an empty list.
  """
  @spec prepend(term(), term()) :: list()
  def prepend(existing, new) do
    List.wrap(new) ++ (existing || [])
  end

  @doc """
  Returns a merge function that appends then keeps only the last `max` items.
  """
  @spec append_max(pos_integer()) :: (term(), term() -> list())
  def append_max(max) when is_integer(max) and max > 0 do
    fn existing, new ->
      ((existing || []) ++ List.wrap(new))
      |> Enum.take(-max)
    end
  end

  @doc """
  Returns a merge function that prepends then keeps only the first `max` items.
  """
  @spec prepend_max(pos_integer()) :: (term(), term() -> list())
  def prepend_max(max) when is_integer(max) and max > 0 do
    fn existing, new ->
      (List.wrap(new) ++ (existing || []))
      |> Enum.take(max)
    end
  end

  @doc """
  Returns a merge function that upserts items by a key function.

  New items with a matching key replace existing items. New items with
  no match are appended.
  """
  @spec upsert_by((term() -> term())) :: (term(), term() -> list())
  def upsert_by(key_fn) when is_function(key_fn, 1) do
    fn existing, new ->
      existing_list = existing || []
      new_list = List.wrap(new)
      new_keys = MapSet.new(new_list, key_fn)

      kept = Enum.reject(existing_list, fn item -> MapSet.member?(new_keys, key_fn.(item)) end)
      kept ++ new_list
    end
  end
end
