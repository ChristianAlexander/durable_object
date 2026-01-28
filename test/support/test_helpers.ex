defmodule DurableObject.TestHelpers do
  @moduledoc """
  Test helpers for DurableObject tests.
  """

  @doc """
  Generates a unique object ID with the given prefix.
  Ensures no collisions between test runs.
  """
  def unique_id(prefix \\ "test") do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end
end
