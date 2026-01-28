# Start the TestRepo for persistence tests
{:ok, _} = DurableObject.TestRepo.start_link()

# Set sandbox mode for concurrent tests
Ecto.Adapters.SQL.Sandbox.mode(DurableObject.TestRepo, :manual)

ExUnit.start()
