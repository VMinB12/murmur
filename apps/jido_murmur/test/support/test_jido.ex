defmodule JidoMurmur.TestJido do
  @moduledoc false
  use Jido, otp_app: :jido_murmur, storage: {JidoMurmur.Storage.Ecto, []}
end
