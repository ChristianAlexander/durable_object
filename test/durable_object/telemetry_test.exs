defmodule DurableObject.TelemetryTest do
  use ExUnit.Case, async: true

  alias DurableObject.Telemetry

  describe "span/3" do
    test "executes function and returns {:ok, result} on success" do
      assert {:ok, 42} = Telemetry.span([:test, :operation], %{}, fn -> 42 end)
    end

    test "returns {:error, exception} on raise" do
      result =
        Telemetry.span([:test, :operation], %{}, fn ->
          raise ArgumentError, "test error"
        end)

      assert {:error, %ArgumentError{message: "test error"}} = result
    end

    test "returns {:error, {kind, reason}} on throw" do
      result =
        Telemetry.span([:test, :operation], %{}, fn ->
          throw(:test_throw)
        end)

      assert {:error, {:throw, :test_throw}} = result
    end

    test "emits start event with system_time" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-start-#{inspect(ref)}",
        [:test, :span, :start],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.span([:test, :span], %{key: "value"}, fn -> :ok end)

      assert_receive {:event, [:test, :span, :start], measurements, %{key: "value"}}
      assert is_integer(measurements.system_time)

      :telemetry.detach("test-start-#{inspect(ref)}")
    end

    test "emits stop event with duration on success" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-stop-#{inspect(ref)}",
        [:test, :span, :stop],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.span([:test, :span], %{key: "value"}, fn ->
        Process.sleep(10)
        :ok
      end)

      assert_receive {:event, [:test, :span, :stop], measurements, %{key: "value"}}
      assert is_integer(measurements.duration)
      assert measurements.duration > 0

      :telemetry.detach("test-stop-#{inspect(ref)}")
    end

    test "emits exception event with duration, kind, reason, and stacktrace on error" do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-exception-#{inspect(ref)}",
        [:test, :span, :exception],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:event, event, measurements, metadata})
        end,
        nil
      )

      Telemetry.span([:test, :span], %{key: "value"}, fn ->
        raise ArgumentError, "test"
      end)

      assert_receive {:event, [:test, :span, :exception], measurements, metadata}
      assert is_integer(measurements.duration)
      assert metadata.key == "value"
      assert metadata.kind == :error
      assert %ArgumentError{} = metadata.reason
      assert is_list(metadata.stacktrace)

      :telemetry.detach("test-exception-#{inspect(ref)}")
    end

    test "preserves metadata across all events" do
      ref = make_ref()
      test_pid = self()

      metadata = %{
        repo: SomeRepo,
        object_type: "Counter",
        object_id: "test-123"
      }

      :telemetry.attach_many(
        "test-metadata-#{inspect(ref)}",
        [
          [:test, :span, :start],
          [:test, :span, :stop]
        ],
        fn event, _measurements, meta, _ ->
          send(test_pid, {:event, event, meta})
        end,
        nil
      )

      Telemetry.span([:test, :span], metadata, fn -> :ok end)

      assert_receive {:event, [:test, :span, :start], ^metadata}
      assert_receive {:event, [:test, :span, :stop], ^metadata}

      :telemetry.detach("test-metadata-#{inspect(ref)}")
    end
  end
end
