defmodule JidoMurmur.TestJidoEtsStorage do
  @moduledoc """
  Alternative Jido instance using ETS-backed storage for testing.

  Validates that JidoMurmur works with any Jido.Storage implementation,
  not just the default JidoMurmur.Storage.Ecto adapter.
  """
  use Jido, otp_app: :jido_murmur, storage: {Jido.Storage.ETS, [table: :jido_murmur_ets_test]}
end
