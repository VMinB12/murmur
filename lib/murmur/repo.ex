defmodule Murmur.Repo do
  use Ecto.Repo,
    otp_app: :murmur,
    adapter: Ecto.Adapters.Postgres
end
