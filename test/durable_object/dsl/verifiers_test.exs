defmodule DurableObject.Dsl.VerifiersTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  describe "ValidateHandlers verifier" do
    test "valid modules compile without errors" do
      # These modules have all handlers implemented
      # The fact that they compile means the verifier passed
      assert Code.ensure_loaded?(DurableObject.DslTest.BasicCounter)
      assert Code.ensure_loaded?(DurableObject.DslTest.MinimalCounter)
      assert Code.ensure_loaded?(DurableObject.DslTest.ChatRoom)
    end

    test "warns for missing handler with no args" do
      # Verifiers run in after_verify and emit warnings
      output =
        capture_io(:stderr, fn ->
          defmodule MissingNoArgsHandler do
            use DurableObject.Dsl

            state do
              field(:count, :integer, default: 0)
            end

            handlers do
              handler(:missing)
            end
          end
        end)

      assert output =~ "`handle_missing/1` is not defined"
    end

    test "warns for missing handler with args" do
      output =
        capture_io(:stderr, fn ->
          defmodule MissingArgsHandler do
            use DurableObject.Dsl

            state do
              field(:count, :integer, default: 0)
            end

            handlers do
              handler(:increment, args: [:amount])
            end
          end
        end)

      assert output =~ "`handle_increment/2` is not defined"
    end

    test "warns for handler with wrong arity" do
      output =
        capture_io(:stderr, fn ->
          defmodule WrongArityHandler do
            use DurableObject.Dsl

            state do
              field(:count, :integer, default: 0)
            end

            handlers do
              # Declared with 2 args, so expects handle_add/3 (2 args + state)
              handler(:add, args: [:a, :b])
            end

            # But we only define handle_add/2 (1 arg + state)
            def handle_add(a, state) do
              {:reply, a, state}
            end
          end
        end)

      assert output =~ "`handle_add/3` is not defined"
    end

    test "accepts handler with correct arity" do
      # This should compile without warnings about handlers
      output =
        capture_io(:stderr, fn ->
          defmodule CorrectArityHandler do
            use DurableObject.Dsl

            state do
              field(:count, :integer, default: 0)
            end

            handlers do
              handler(:add, args: [:a, :b])
            end

            def handle_add(a, b, state) do
              {:reply, a + b, state}
            end
          end
        end)

      refute output =~ "`handle_add/3` is not defined"
      assert Code.ensure_loaded?(DurableObject.Dsl.VerifiersTest.CorrectArityHandler)
    end
  end
end
