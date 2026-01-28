defmodule DurableObject.TestRepo do
  @moduledoc """
  Ecto repo for testing DurableObject persistence.
  """
  use Ecto.Repo,
    otp_app: :durable_object,
    adapter: Ecto.Adapters.SQLite3
end
