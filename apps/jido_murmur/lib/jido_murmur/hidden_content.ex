defmodule JidoMurmur.HiddenContent do
  @moduledoc """
  Helpers for Murmur's hidden HTML comment envelope.

  Trusted programmatic messages can use this envelope to expose machine-visible
  metadata to the recipient while keeping the user-facing body suitable for
  markdown rendering.
  """

  @comment_prefix "<!-- murmur:"
  @comment_suffix " -->"

  @spec wrap_markdown(String.t(), keyword() | map()) :: String.t()
  def wrap_markdown(content, metadata)
      when is_binary(content) and (is_list(metadata) or is_map(metadata)) do
    serialized_metadata =
      metadata
      |> normalize_metadata()
      |> serialize_metadata()
      |> sanitize_comment_text()

    @comment_prefix <> " " <> serialized_metadata <> @comment_suffix <> "\n" <> content
  end

  @spec wrapped?(String.t()) :: boolean()
  def wrapped?(content) when is_binary(content), do: String.starts_with?(content, @comment_prefix)
  def wrapped?(_content), do: false

  defp normalize_metadata(metadata) when is_list(metadata) do
    Enum.map(metadata, fn {key, value} -> {normalize_key(key), normalize_value(value)} end)
  end

  defp normalize_metadata(metadata) when is_map(metadata) do
    metadata
    |> Enum.map(fn {key, value} -> {normalize_key(key), normalize_value(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp serialize_metadata(fields) do
    encoded_fields =
      Enum.map_join(fields, ",", fn {key, value} ->
        "#{Jason.encode!(key)}:#{Jason.encode!(value)}"
      end)

    "{" <> encoded_fields <> "}"
  end

  defp sanitize_comment_text(text), do: String.replace(text, "--", "\\u002d\\u002d")

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: inspect(key)

  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)

  defp normalize_value(%{} = value) do
    Map.new(value, fn {key, nested_value} ->
      {normalize_key(key), normalize_value(nested_value)}
    end)
  end

  defp normalize_value(value), do: value
end
