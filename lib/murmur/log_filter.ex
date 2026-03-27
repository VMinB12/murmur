defmodule Murmur.LogFilter do
  @moduledoc """
  Erlang :logger filter that drops excessively verbose log messages.

  Targets the giant state dumps from Jido action execution and similarly
  noisy log lines that aren't useful during development.
  """

  @max_message_length 500

  @doc """
  Filter function for Erlang's :logger.

  Drops log events whose formatted message exceeds `@max_message_length`
  characters, except for :error and :critical levels which are always kept.
  """
  def filter(%{level: level} = log_event, _extra) when level in [:error, :critical, :alert, :emergency] do
    log_event
  end

  def filter(%{msg: {:string, msg}} = log_event, _extra) do
    if IO.iodata_length(msg) > @max_message_length, do: :stop, else: log_event
  end

  def filter(%{msg: {:report, _}} = log_event, _extra) do
    log_event
  end

  def filter(%{msg: {fmt, args}} = log_event, _extra) when is_list(fmt) or is_binary(fmt) do
    formatted = :io_lib.format(fmt, args)

    if IO.iodata_length(formatted) > @max_message_length, do: :stop, else: log_event
  rescue
    _ -> log_event
  end

  def filter(log_event, _extra), do: log_event
end
