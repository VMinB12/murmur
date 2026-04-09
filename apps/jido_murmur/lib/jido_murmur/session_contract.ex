defmodule JidoMurmur.SessionContract do
  @moduledoc """
  Shared Murmur-owned session boundary types.

  These types describe the stable session maps passed across ingress,
  projection, and runner boundaries without forcing each module to redefine its
  own `session_like` contract.
  """

  @typedoc "Stable session identity used by read-side boundaries."
  @type identity :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t(),
          optional(atom()) => any()
        }

  @typedoc "Session contract required to route work to a specific agent session."
  @type target :: %{
          required(:id) => String.t(),
          required(:workspace_id) => String.t(),
          required(:agent_profile_id) => String.t(),
          required(:display_name) => String.t(),
          optional(atom()) => any()
        }
end
