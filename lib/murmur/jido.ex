defmodule Murmur.Jido do
  @moduledoc "Jido integration for the Murmur application."

  use Jido, otp_app: :murmur, storage: {Murmur.Storage.Ecto, []}
end
