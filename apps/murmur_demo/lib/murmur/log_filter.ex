defmodule Murmur.LogFilter do
  @moduledoc """
  Erlang :logger filter that truncates excessively verbose log messages.

  Targets the giant state dumps from Jido action execution and similarly
  noisy log lines that aren't useful during development. Messages beyond
  the max length are truncated with a suffix indicating the original size.
  """

  @max_message_length 500

  @doc """
  Filter function for Erlang's :logger.

  Truncates log events whose formatted message exceeds `@max_message_length`
  characters, except for :error and :critical levels which are always kept intact.
  """
  def filter(%{level: level} = log_event, _extra) when level in [:error, :critical, :alert, :emergency] do
    log_event
  end

  def filter(%{msg: {:string, msg}} = log_event, _extra) do
    len = IO.iodata_length(msg)

    if len > @max_message_length do
      truncated = msg |> IO.iodata_to_binary() |> binary_part(0, @max_message_length)
      %{log_event | msg: {:string, "#{truncated}... [truncated, #{len} bytes total]"}}
    else
      log_event
    end
  end

  def filter(%{msg: {:report, _}} = log_event, _extra) do
    log_event
  end

  def filter(%{msg: {fmt, args}} = log_event, _extra) when is_list(fmt) or is_binary(fmt) do
    formatted = IO.iodata_to_binary(:io_lib.format(fmt, args))
    len = byte_size(formatted)

    if len > @max_message_length do
      truncated = binary_part(formatted, 0, @max_message_length)
      %{log_event | msg: {:string, "#{truncated}... [truncated, #{len} bytes total]"}}
    else
      log_event
    end
  rescue
    _ -> log_event
  end

  def filter(log_event, _extra), do: log_event
end
