defmodule MurmurWeb.Artifacts.Actions do
  @moduledoc """
  Demo-owned artifact actions.

  Artifact-specific mutations, such as re-running a SQL query for a rendered
  artifact, live here rather than in the generic workspace LiveView.
  """

  alias JidoArtifacts.Envelope
  alias JidoSql.QueryResult

  @sql_results_name "sql_results"

  @spec handle(String.t(), map(), map()) :: {:ok, map()} | {:error, atom()}
  def handle("reexecute_query", params, artifacts) when is_map(params) and is_map(artifacts) do
    with {:ok, session_id} <- fetch_string(params, "session-id"),
         {:ok, sql} <- fetch_string(params, "sql"),
         {:ok, index} <- parse_index(params["index"]) do
      reexecute_query(artifacts, session_id, sql, index)
    end
  end

  def handle(_event, _params, _artifacts), do: {:error, :unsupported_action}

  @spec reexecute_query(map(), String.t(), String.t(), non_neg_integer()) :: {:ok, map()} | {:error, atom()}
  def reexecute_query(artifacts, session_id, sql, index)
      when is_map(artifacts) and is_binary(session_id) and is_binary(sql) and is_integer(index) and index >= 0 do
    with {:ok, session_artifacts} <- fetch_session_artifacts(artifacts, session_id),
         {:ok, envelope, query_list} <- fetch_query_list(session_artifacts),
         {:ok, _query_item} <- fetch_query_item(query_list, index) do
      %Envelope{} = envelope
      {result_key, result_value} = execute_query(sql)

      updated_list =
        List.update_at(query_list, index, fn item ->
          item
          |> Map.put(result_key, result_value)
          |> Map.delete(other_result_key(result_key))
        end)

      updated_artifact = %{envelope | data: updated_list}
      updated_session_artifacts = Map.put(session_artifacts, @sql_results_name, updated_artifact)

      {:ok, Map.put(artifacts, session_id, updated_session_artifacts)}
    end
  end

  defp fetch_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :invalid_params}
    end
  end

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {value, ""} when value >= 0 -> {:ok, value}
      _ -> {:error, :invalid_index}
    end
  end

  defp parse_index(_index), do: {:error, :invalid_index}

  defp fetch_session_artifacts(artifacts, session_id) do
    case Map.fetch(artifacts, session_id) do
      {:ok, session_artifacts} when is_map(session_artifacts) -> {:ok, session_artifacts}
      _ -> {:error, :artifact_not_found}
    end
  end

  defp fetch_query_list(session_artifacts) do
    case Map.get(session_artifacts, @sql_results_name) do
      %Envelope{data: query_list} = envelope when is_list(query_list) -> {:ok, envelope, query_list}
      _ -> {:error, :artifact_not_found}
    end
  end

  defp fetch_query_item(query_list, index) do
    case Enum.fetch(query_list, index) do
      {:ok, query_item} -> {:ok, query_item}
      :error -> {:error, :query_not_found}
    end
  end

  defp execute_query(sql) do
    case JidoSql.query_executor().execute(JidoSql.repo(), sql) do
      {:ok, %QueryResult{} = result} -> {"loaded_result", result}
      {:error, reason} -> {"loaded_error", format_error(reason)}
    end
  end

  defp other_result_key("loaded_result"), do: "loaded_error"
  defp other_result_key(_key), do: "loaded_result"

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
