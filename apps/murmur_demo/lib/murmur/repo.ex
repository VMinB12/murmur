defmodule Murmur.Repo do
  use Ecto.Repo,
    otp_app: :murmur_demo,
    adapter: Ecto.Adapters.Postgres
end
