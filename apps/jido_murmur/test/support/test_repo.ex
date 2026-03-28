defmodule JidoMurmur.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :jido_murmur,
    adapter: Ecto.Adapters.Postgres
end
