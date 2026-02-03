defmodule DurableObject.Testing do
  @moduledoc """
  Test helpers for DurableObject applications.

  Provides ergonomic helpers for testing Durable Objects. See the
  [Testing Guide](testing.html) for detailed examples and patterns.

  ## Usage

      defmodule MyApp.CounterTest do
        use ExUnit.Case
        use DurableObject.Testing, repo: MyApp.Repo

        test "increment works" do
          {:ok, 1} = Counter.increment("test-counter", 1)
          assert_persisted Counter, "test-counter", count: 1
        end
      end

  **Important:** You must `use ExUnit.Case` before `use DurableObject.Testing`.

  ## Options

    * `:repo` - The Ecto repo (required, or set via application config)
    * `:prefix` - Table prefix for multi-tenancy (optional)

  ## Helpers

    * `perform_handler/4` - Unit test handler logic without GenServer/DB
    * `perform_alarm_handler/3` - Unit test alarm handler logic
    * `assert_persisted/4` - Assert object state in database
    * `get_persisted_state/3` - Fetch persisted state for custom assertions
    * `assert_alarm_scheduled/4` - Assert alarm exists
    * `refute_alarm_scheduled/4` - Assert alarm does not exist
    * `all_scheduled_alarms/3` - List all alarms for an object
    * `fire_alarm/4` - Execute alarm immediately (bypasses scheduler)
    * `drain_alarms/3` - Execute all pending alarms
    * `assert_eventually/2` - Poll until condition is true

  ## Limitations

    * Tests cannot be `async: true` (sandbox runs in shared mode)
    * `fire_alarm/4` starts the object if not running
    * `drain_alarms/3` can hang on infinite alarm loops (use `:max_iterations`)
  """

  import Ecto.Query
  alias DurableObject.Storage.Schemas.{Object, Alarm}

  @doc """
  Sets up DurableObject test helpers.

  Injects a `setup` callback that:
  1. Checks out an Ecto sandbox connection
  2. Sets sandbox mode to `{:shared, self()}` for cross-process access
  3. Stores repo and prefix in process dictionary for helper functions

  **Important:** You must `use ExUnit.Case` before `use DurableObject.Testing`
  because this macro injects a `setup` callback.

  ## Options

    * `:repo` - The Ecto repo (required, or set via application config)
    * `:prefix` - Table prefix for multi-tenancy (optional)

  ## Example

      defmodule MyApp.CounterTest do
        use ExUnit.Case        # Must come first!
        use DurableObject.Testing, repo: MyApp.Repo

        test "increment works" do
          {:ok, 1} = Counter.increment("test-1", 1)
          assert_persisted Counter, "test-1", count: 1
        end
      end
  """
  defmacro __using__(opts) do
    quote do
      import DurableObject.Testing

      @durable_object_test_opts unquote(opts)

      setup context do
        DurableObject.Testing.__setup__(@durable_object_test_opts, context)
      end
    end
  end

  @doc false
  def __setup__(opts, _context) do
    repo = Keyword.get(opts, :repo) || Application.get_env(:durable_object, :repo)
    prefix = Keyword.get(opts, :prefix)

    if repo do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)
      # Note: {:shared, self()} mode means tests cannot be async: true
      # This is required because DurableObject processes run in separate PIDs
      # and need access to the same sandbox connection.
      Ecto.Adapters.SQL.Sandbox.mode(repo, {:shared, self()})
    end

    # Store in process dictionary for helper functions to access
    # Note: This means helpers only work in the test process, not in spawned processes
    Process.put(:durable_object_test_repo, repo)
    Process.put(:durable_object_test_prefix_opt, prefix)

    {:ok, %{repo: repo, prefix: prefix}}
  end

  # ===========================================================================
  # Unit Testing Helpers
  # ===========================================================================

  @doc """
  Executes a handler function directly, bypassing GenServer and persistence.

  This is useful for unit testing handler logic in isolation. The handler
  function `handle_<name>/N` is called directly with the provided args and state.

  Note: This does NOT validate that the handler is declared in the DSL's
  `handlers` block - it only checks if the function exists. This means you
  can test private helper handlers that aren't exposed via the DSL.

  ## Examples

      # Handler that takes no args - calls handle_increment(state)
      assert {:reply, 1, %{count: 1}} =
        perform_handler(Counter, :increment, [], %{count: 0})

      # Handler that takes args - calls handle_increment_by(5, state)
      assert {:reply, 5, %{count: 5}} =
        perform_handler(Counter, :increment_by, [5], %{count: 0})

      # Handler that returns error
      assert {:error, :invalid_amount} =
        perform_handler(Counter, :increment_by, [-1], %{count: 0})

  ## Parameters

    * `module` - The DurableObject module
    * `handler_name` - The handler name (atom), will call `handle_<name>/N`
    * `args` - List of arguments to pass before state
    * `state` - The state map to pass as the last argument

  ## Returns

  Returns whatever the handler returns (not wrapped):

    * `{:reply, result, new_state}` - Handler returned a reply with state change
    * `{:reply, result, new_state, {:schedule_alarm, name, delay}}` - Reply with alarm
    * `{:reply, result}` - Read-only handler (no state change)
    * `{:noreply, new_state}` - Handler returned no reply
    * `{:noreply, new_state, {:schedule_alarm, name, delay}}` - No reply with alarm
    * `{:error, reason}` - Handler returned an error
    * `{:error, {:unknown_handler, name}}` - Handler function doesn't exist
  """
  @spec perform_handler(module(), atom(), list(), map()) ::
          {:reply, term(), map()}
          | {:reply, term(), map(), {:schedule_alarm, atom(), pos_integer()}}
          | {:reply, term()}
          | {:noreply, map()}
          | {:noreply, map(), {:schedule_alarm, atom(), pos_integer()}}
          | {:error, term()}
  def perform_handler(module, handler_name, args, state) when is_map(state) do
    handler_fn = :"handle_#{handler_name}"

    if function_exported?(module, handler_fn, length(args) + 1) do
      apply(module, handler_fn, args ++ [state])
    else
      {:error, {:unknown_handler, handler_name}}
    end
  end

  @doc """
  Executes an alarm handler directly, bypassing GenServer and persistence.

  This is useful for unit testing alarm handler logic in isolation. The
  `handle_alarm/2` callback is called directly with the alarm name and state.

  Note: Unlike regular handlers, alarm handlers are dispatched through a single
  `handle_alarm(alarm_name, state)` function that pattern matches on the alarm name.

  ## Examples

      assert {:noreply, %{count: 0}} =
        perform_alarm_handler(Counter, :daily_reset, %{count: 42})

      # Alarm that reschedules itself
      assert {:noreply, %{count: 0}, {:schedule_alarm, :daily_reset, 86400000}} =
        perform_alarm_handler(Counter, :daily_reset, %{count: 42})

  ## Parameters

    * `module` - The DurableObject module
    * `alarm_name` - The alarm name (atom)
    * `state` - The state map

  ## Returns

  Returns whatever the handler returns (not wrapped):

    * `{:noreply, new_state}` - Alarm handler completed
    * `{:noreply, new_state, {:schedule_alarm, name, delay}}` - Completed with reschedule
    * `{:error, reason}` - Handler returned an error
    * `{:error, :no_alarm_handler}` - Module has no `handle_alarm/2` function

  Note: If `handle_alarm/2` exists but doesn't have a clause for the given
  alarm name, this will raise a `FunctionClauseError` (not return an error tuple).
  """
  @spec perform_alarm_handler(module(), atom(), map()) ::
          {:noreply, map()}
          | {:noreply, map(), {:schedule_alarm, atom(), pos_integer()}}
          | {:error, term()}
  def perform_alarm_handler(module, alarm_name, state) when is_map(state) do
    if function_exported?(module, :handle_alarm, 2) do
      apply(module, :handle_alarm, [alarm_name, state])
    else
      {:error, :no_alarm_handler}
    end
  end

  # ===========================================================================
  # Alarm Assertion Helpers
  # ===========================================================================

  @doc """
  Asserts that an alarm is scheduled for the given object.

  Queries the `durable_object_alarms` table directly to check if an alarm
  with the given name exists for the object.

  ## Options

    * `:within` - Assert alarm is scheduled within this duration from now (milliseconds).
      If the alarm's `scheduled_at` is further in the future, the assertion fails.
    * `:repo` - Ecto repo (defaults to test case repo from process dictionary)
    * `:prefix` - Table prefix for multi-tenancy

  ## Examples

      assert_alarm_scheduled Counter, "user-123", :cleanup
      assert_alarm_scheduled Counter, "user-123", :cleanup, within: :timer.hours(1)

  ## Raises

  Raises `ExUnit.AssertionError` if:
    * No alarm with the given name is scheduled
    * `:within` is specified and the alarm is scheduled beyond that window
  """
  def assert_alarm_scheduled(module, object_id, alarm_name, opts \\ []) do
    {repo, prefix} = get_repo_and_prefix(opts)
    within = Keyword.get(opts, :within)

    alarm = get_alarm(repo, module, object_id, alarm_name, prefix)

    if alarm do
      if within do
        now = DateTime.utc_now()
        max_time = DateTime.add(now, within, :millisecond)

        if DateTime.compare(alarm.scheduled_at, max_time) == :gt do
          raise ExUnit.AssertionError,
            message: """
            Expected alarm #{inspect(alarm_name)} to be scheduled within #{within}ms.

            Alarm is scheduled at: #{DateTime.to_iso8601(alarm.scheduled_at)}
            Maximum expected time: #{DateTime.to_iso8601(max_time)}
            """
        end
      end

      :ok
    else
      raise ExUnit.AssertionError,
        message: """
        Expected alarm #{inspect(alarm_name)} to be scheduled for #{inspect(module)}:#{object_id}.

        No alarm with that name exists.
        """
    end
  end

  @doc """
  Asserts that no alarm with the given name is scheduled.

  ## Options

    * `:repo` - Ecto repo (defaults to test case repo from process dictionary)
    * `:prefix` - Table prefix for multi-tenancy

  ## Examples

      refute_alarm_scheduled Counter, "user-123", :cleanup

  ## Raises

  Raises `ExUnit.AssertionError` if an alarm with the given name exists.
  """
  def refute_alarm_scheduled(module, object_id, alarm_name, opts \\ []) do
    {repo, prefix} = get_repo_and_prefix(opts)

    alarm = get_alarm(repo, module, object_id, alarm_name, prefix)

    if alarm do
      raise ExUnit.AssertionError,
        message: """
        Expected no alarm #{inspect(alarm_name)} to be scheduled for #{inspect(module)}:#{object_id}.

        Found alarm scheduled at: #{DateTime.to_iso8601(alarm.scheduled_at)}
        """
    end

    :ok
  end

  @doc """
  Returns all scheduled alarms for the given object.

  Useful for detailed assertions on alarm state when `assert_alarm_scheduled`
  is not sufficient.

  ## Options

    * `:repo` - Ecto repo (defaults to test case repo from process dictionary)
    * `:prefix` - Table prefix for multi-tenancy

  ## Examples

      alarms = all_scheduled_alarms(Counter, "user-123")
      assert length(alarms) == 2
      assert Enum.any?(alarms, & &1.name == :cleanup)

  ## Returns

  A list of maps with `:name` (atom) and `:scheduled_at` (DateTime), sorted
  by `scheduled_at` ascending (earliest first).
  """
  @spec all_scheduled_alarms(module(), String.t(), keyword()) ::
          [%{name: atom(), scheduled_at: DateTime.t()}]
  def all_scheduled_alarms(module, object_id, opts \\ []) do
    {repo, prefix} = get_repo_and_prefix(opts)
    object_type = to_string(module)

    from(a in Alarm,
      where: a.object_type == ^object_type,
      where: a.object_id == ^object_id,
      select: %{name: a.alarm_name, scheduled_at: a.scheduled_at},
      order_by: [asc: a.scheduled_at]
    )
    |> repo.all(prefix: prefix)
    |> Enum.map(fn alarm ->
      %{alarm | name: String.to_existing_atom(alarm.name)}
    end)
  end

  # ===========================================================================
  # Alarm Execution Helpers
  # ===========================================================================

  @doc """
  Fires a specific scheduled alarm immediately, bypassing scheduler timing.

  Runs the alarm handler deterministically without waiting for scheduler polling.
  The alarm is deleted after successful execution (unless the handler reschedules
  the same alarm).

  **Important:** This function starts the DurableObject if it's not running.
  If your test depends on the object NOT being started, use `perform_alarm_handler/3`
  for unit testing instead.

  ## How It Works

  1. Verifies the alarm exists in the database
  2. Calls `DurableObject.call(module, object_id, :__fire_alarm__, [alarm_name])`
  3. If successful, checks if the alarm was rescheduled (by comparing `scheduled_at`)
  4. Deletes the alarm only if it wasn't rescheduled

  ## Options

    * `:repo` - Ecto repo (defaults to test case repo from process dictionary)
    * `:prefix` - Table prefix for multi-tenancy

  ## Examples

      :ok = Counter.schedule_alarm("user-123", :cleanup, :timer.hours(1))
      fire_alarm(Counter, "user-123", :cleanup)
      refute_alarm_scheduled Counter, "user-123", :cleanup

  ## Returns

    * `:ok` - Alarm was fired successfully
    * `{:error, reason}` - The alarm handler returned an error

  ## Raises

  Raises `ArgumentError` if no alarm with the given name is scheduled.
  """
  def fire_alarm(module, object_id, alarm_name, opts \\ []) do
    {repo, prefix} = get_repo_and_prefix(opts)
    object_type = to_string(module)

    # Verify the alarm exists
    alarm = get_alarm(repo, module, object_id, alarm_name, prefix)

    unless alarm do
      raise ArgumentError,
            "No alarm #{inspect(alarm_name)} scheduled for #{inspect(module)}:#{object_id}"
    end

    # Fire the alarm by calling the object's __fire_alarm__ handler
    # Note: This will start the object if not running
    case DurableObject.call(module, object_id, :__fire_alarm__, [alarm_name],
           repo: repo,
           prefix: prefix
         ) do
      {:ok, _result} ->
        # Delete the alarm only if it wasn't rescheduled
        # We detect rescheduling by comparing scheduled_at timestamps
        current_alarm = get_alarm(repo, module, object_id, alarm_name, prefix)

        if current_alarm &&
             DateTime.compare(current_alarm.scheduled_at, alarm.scheduled_at) == :eq do
          # Alarm wasn't rescheduled (same timestamp), delete it
          from(a in Alarm,
            where: a.object_type == ^object_type,
            where: a.object_id == ^object_id,
            where: a.alarm_name == ^to_string(alarm_name)
          )
          |> repo.delete_all(prefix: prefix)
        end

        # If timestamps differ, alarm was rescheduled - leave it

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fires all scheduled alarms for an object, regardless of scheduled time.

  Useful for testing alarm chains or ensuring all cleanup alarms run.
  Alarms are fired in scheduled order (earliest first). If firing an alarm
  schedules a new alarm, it will also be fired (recursively).

  **Warning:** This can hang or raise if alarms reschedule indefinitely.
  Use the `:max_iterations` option to protect against infinite loops.

  ## Options

    * `:repo` - Ecto repo (defaults to test case repo from process dictionary)
    * `:prefix` - Table prefix for multi-tenancy
    * `:max_iterations` - Maximum number of alarms to fire (default: 100).
      Raises if exceeded.

  ## Examples

      # Fire all alarms including any that get scheduled during execution
      {:ok, 2} = drain_alarms(Counter, "user-123")

      # With custom iteration limit for alarm chains
      {:ok, _count} = drain_alarms(Counter, "user-123", max_iterations: 10)

  ## Returns

    * `{:ok, count}` - All alarms were drained, returns number of alarms fired

  ## Raises

  Raises if `:max_iterations` is exceeded (possible infinite alarm loop).
  """
  def drain_alarms(module, object_id, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 100)
    remaining = do_drain_alarms(module, object_id, opts, max_iterations)
    {:ok, max_iterations - remaining}
  end

  defp do_drain_alarms(_module, _object_id, _opts, 0) do
    raise "drain_alarms exceeded maximum iterations - possible infinite alarm loop"
  end

  defp do_drain_alarms(module, object_id, opts, remaining) do
    case all_scheduled_alarms(module, object_id, opts) do
      [] ->
        remaining

      alarms ->
        [first | _rest] = alarms
        fire_alarm(module, object_id, first.name, opts)
        do_drain_alarms(module, object_id, opts, remaining - 1)
    end
  end

  # ===========================================================================
  # State Assertion Helpers
  # ===========================================================================

  @doc """
  Asserts that an object's state was persisted to the database.

  Can optionally assert on specific field values.

  ## Options

    * `:repo` - Ecto repo (defaults to test case repo from process dictionary)
    * `:prefix` - Table prefix for multi-tenancy

  ## Examples

      # Assert object exists in DB (any state)
      assert_persisted Counter, "user-123"

      # Assert specific fields (keyword list)
      assert_persisted Counter, "user-123", count: 5

      # Assert specific fields (map)
      assert_persisted Counter, "user-123", %{count: 5, name: "test"}

      # With explicit options
      assert_persisted Counter, "user-123", [count: 5], repo: MyRepo

  ## Raises

  Raises `ExUnit.AssertionError` if:
    * No state is persisted for the object
    * Any expected field value doesn't match the persisted value
  """
  def assert_persisted(module, object_id, expected \\ nil, opts \\ []) do
    {repo, prefix} = get_repo_and_prefix(opts)
    state = get_persisted_state_raw(repo, module, object_id, prefix)

    unless state do
      raise ExUnit.AssertionError,
        message: """
        Expected #{inspect(module)}:#{object_id} to be persisted.

        No state found in database.
        """
    end

    if expected do
      expected_map = if is_map(expected), do: expected, else: Map.new(expected)

      Enum.each(expected_map, fn {key, expected_value} ->
        key_str = to_string(key)
        actual_value = Map.get(state, key_str)

        if actual_value != expected_value do
          raise ExUnit.AssertionError,
            message: """
            Expected persisted state for #{inspect(module)}:#{object_id} to have #{inspect(key)} = #{inspect(expected_value)}.

            Got: #{inspect(actual_value)}
            Full state: #{inspect(state)}
            """
        end
      end)
    end

    :ok
  end

  @doc """
  Returns the persisted state for an object, or `nil` if not found.

  Useful for custom assertions beyond what `assert_persisted/4` provides.
  Top-level field keys are returned as atoms. Keys within field values
  remain as strings (the raw DB form), regardless of the `object_keys` setting.

  ## Options

    * `:repo` - Ecto repo (defaults to test case repo from process dictionary)
    * `:prefix` - Table prefix for multi-tenancy

  ## Examples

      state = get_persisted_state(Counter, "user-123")
      assert state.count > 0
      assert state.name =~ ~r/test/

      # Nested keys are always strings, even with object_keys: :atoms!
      assert state.metadata == %{"foo" => "bar"}

      # Returns nil if not persisted
      assert nil == get_persisted_state(Counter, "nonexistent")
  """
  @spec get_persisted_state(module(), String.t(), keyword()) :: map() | nil
  def get_persisted_state(module, object_id, opts \\ []) do
    {repo, prefix} = get_repo_and_prefix(opts)

    case get_persisted_state_raw(repo, module, object_id, prefix) do
      nil ->
        nil

      state ->
        Map.new(state, fn {k, v} -> {String.to_existing_atom(k), v} end)
    end
  end

  # ===========================================================================
  # Async Helper
  # ===========================================================================

  @doc """
  Polls a condition until it returns truthy or times out.

  **Use sparingly** - prefer deterministic assertions when possible. This is
  intended for testing truly asynchronous behavior where you can't control
  timing (e.g., waiting for a process to terminate).

  ## Options

    * `:timeout` - Maximum wait in milliseconds (default: 5000)
    * `:interval` - Polling interval in milliseconds (default: 50)

  ## Examples

      # Wait for object to shut down
      assert_eventually fn ->
        DurableObject.whereis(Counter, id) == nil
      end, timeout: 1000

      # With custom interval for expensive checks
      assert_eventually fn ->
        get_persisted_state(Counter, id) != nil
      end, timeout: 2000, interval: 100

  ## Returns

    * `:ok` - Condition became truthy

  ## Raises

  Raises `ExUnit.AssertionError` if the condition doesn't become truthy
  within the timeout. The error message is generic ("Condition did not
  become true within timeout") - consider wrapping in a more descriptive
  assertion if needed.

  ## Implementation Note

  Uses `System.monotonic_time/1` for timeout tracking, which is not affected
  by system clock changes. The condition function is called once immediately,
  then after each interval until timeout.
  """
  def assert_eventually(condition_fn, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    interval = Keyword.get(opts, :interval, 50)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_assert_eventually(condition_fn, interval, deadline)
  end

  defp do_assert_eventually(condition_fn, interval, deadline) do
    if condition_fn.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        raise ExUnit.AssertionError,
          message: "Condition did not become true within timeout"
      else
        Process.sleep(interval)
        do_assert_eventually(condition_fn, interval, deadline)
      end
    end
  end

  # ===========================================================================
  # Private Helpers
  # ===========================================================================

  defp get_repo_and_prefix(opts) do
    repo =
      Keyword.get(opts, :repo) ||
        Process.get(:durable_object_test_repo) ||
        Application.get_env(:durable_object, :repo)

    prefix =
      Keyword.get(opts, :prefix) ||
        Process.get(:durable_object_test_prefix_opt)

    unless repo do
      raise ArgumentError, """
      No repo configured for DurableObject.Testing.

      Either:
        1. Use `use DurableObject.Testing, repo: MyApp.Repo`
        2. Pass `repo: MyApp.Repo` option to the helper function
        3. Set `config :durable_object, repo: MyApp.Repo` in config
      """
    end

    {repo, prefix}
  end

  defp get_alarm(repo, module, object_id, alarm_name, prefix) do
    object_type = to_string(module)

    from(a in Alarm,
      where: a.object_type == ^object_type,
      where: a.object_id == ^object_id,
      where: a.alarm_name == ^to_string(alarm_name)
    )
    |> repo.one(prefix: prefix)
  end

  defp get_persisted_state_raw(repo, module, object_id, prefix) do
    object_type = to_string(module)

    case from(o in Object,
           where: o.object_type == ^object_type and o.object_id == ^object_id
         )
         |> repo.one(prefix: prefix) do
      nil -> nil
      object -> object.state
    end
  end
end
