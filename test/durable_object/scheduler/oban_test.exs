defmodule DurableObject.Scheduler.ObanTest do
  @moduledoc """
  Tests for the Oban-based alarm scheduler.

  These tests verify the Oban scheduler implementation without requiring
  a full PostgreSQL database. We test the module's logic using Oban.Testing
  helpers where possible.
  """
  use ExUnit.Case, async: false

  # Skip all tests if Oban scheduler module isn't compiled (oban not available)
  @moduletag :oban_scheduler

  if Code.ensure_loaded?(DurableObject.Scheduler.Oban) do
    alias DurableObject.Scheduler.Oban, as: ObanScheduler

    describe "module availability" do
      test "Oban scheduler module is loaded when oban is available" do
        assert Code.ensure_loaded?(DurableObject.Scheduler.Oban)
      end

      test "Worker module is available" do
        assert Code.ensure_loaded?(DurableObject.Scheduler.Oban.Worker)
      end
    end

    describe "child_spec/1" do
      test "returns empty list (Oban manages its own supervision)" do
        assert ObanScheduler.child_spec([]) == []
        assert ObanScheduler.child_spec(oban_name: SomeOban) == []
      end
    end

    describe "oban_instance defaults" do
      # These tests verify that oban_instance defaults to Oban when not specified.
      # Without a running Oban instance, we get a RuntimeError about Oban not running,
      # which proves the default is being used (not a KeyError about missing option).

      test "schedule/4 defaults oban_instance to Oban" do
        assert_raise RuntimeError, ~r/No Oban instance named `Oban` is running/, fn ->
          ObanScheduler.schedule({TestModule, "test-id"}, :alarm, 1000, [])
        end
      end

      test "cancel/3 defaults oban_instance to Oban" do
        assert_raise RuntimeError, ~r/No Oban instance named `Oban` is running/, fn ->
          ObanScheduler.cancel({TestModule, "test-id"}, :alarm, [])
        end
      end

      test "cancel_all/2 defaults oban_instance to Oban" do
        assert_raise RuntimeError, ~r/No Oban instance named `Oban` is running/, fn ->
          ObanScheduler.cancel_all({TestModule, "test-id"}, [])
        end
      end

      test "list/2 defaults oban_instance to Oban" do
        assert_raise RuntimeError, ~r/No Oban instance named `Oban` is running/, fn ->
          ObanScheduler.list({TestModule, "test-id"}, [])
        end
      end
    end

    describe "Worker" do
      test "has correct oban worker options" do
        opts = DurableObject.Scheduler.Oban.Worker.__opts__()
        assert opts[:queue] == :durable_object_alarms
        assert opts[:max_attempts] == 3
      end

      test "new/2 creates job changeset with correct args" do
        args = %{
          "object_type" => "Elixir.TestModule",
          "object_id" => "test-123",
          "alarm_name" => "my_alarm"
        }

        changeset = DurableObject.Scheduler.Oban.Worker.new(args, schedule_in: 60)

        assert changeset.valid?
        assert changeset.changes.args == args
        assert changeset.changes.worker == "DurableObject.Scheduler.Oban.Worker"
      end

      test "new/2 respects queue option" do
        args = %{
          "object_type" => "Elixir.TestModule",
          "object_id" => "test-123",
          "alarm_name" => "my_alarm"
        }

        changeset =
          DurableObject.Scheduler.Oban.Worker.new(args, schedule_in: 60, queue: :custom_queue)

        assert changeset.valid?
        assert changeset.changes.queue == "custom_queue"
      end

      test "new/2 sets schedule_in correctly" do
        args = %{
          "object_type" => "Elixir.TestModule",
          "object_id" => "test-123",
          "alarm_name" => "my_alarm"
        }

        changeset = DurableObject.Scheduler.Oban.Worker.new(args, schedule_in: 300)

        assert changeset.valid?
        # scheduled_at should be ~300 seconds in the future
        scheduled_at = changeset.changes.scheduled_at
        now = DateTime.utc_now()
        diff = DateTime.diff(scheduled_at, now, :second)
        assert diff >= 299 and diff <= 301
      end
    end
  else
    @tag :skip
    test "Oban scheduler tests skipped - oban not available" do
      :ok
    end
  end
end
