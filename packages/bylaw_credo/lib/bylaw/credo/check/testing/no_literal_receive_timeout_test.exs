defmodule Bylaw.Credo.Check.Testing.NoLiteralReceiveTimeoutTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.NoLiteralReceiveTimeout

  test "reports literal timeouts of assert_receive and refute_receive, with the fix" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "waits" do
        assert_receive {:done, _}, 500
        refute_receive {:done, _}, 50
        assert_receive {:done, _}, 500, "no message"
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoLiteralReceiveTimeout)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {5, "assert_receive"},
               {6, "refute_receive"},
               {7, "assert_receive"}
             ]

      assert hd(issues).message ==
               "Same world everywhere: do not write the timeout of `assert_receive` as a literal; " <>
                 "take it from one shared helper or module attribute that a loaded machine can scale."
    end)
  end

  test "reports computed literal durations" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "waits" do
        assert_receive :a, :timer.seconds(1)
        assert_receive :b, :timer.minutes(1)
        assert_receive :c, to_timeout(second: 1)
        assert_receive :d, 2 * 1_000
        assert_receive(:e, 100)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoLiteralReceiveTimeout)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [5, 6, 7, 8, 9] end)
  end

  test "allows a variable, an attribute, a helper call and a scaled literal" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      @receive_timeout 500

      test "waits", %{timeout: timeout} do
        assert_receive :a, @receive_timeout
        assert_receive :b, timeout
        assert_receive :c, MyApp.TestTimeout.receive()
        assert_receive :d, scale(500)
        assert_receive :e, :timer.seconds(timeout)
        assert_receive :f, timeout * 2
        assert_receive :g, to_timeout(second: timeout)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoLiteralReceiveTimeout)
    |> refute_issues()
  end

  test "allows a call without a timeout, a zero timeout and :infinity" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "waits" do
        assert_receive :a
        refute_receive :b
        refute_receive :c, 0
        assert_receive :d, :infinity
        assert_received :e
        refute_received :f
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoLiteralReceiveTimeout)
    |> refute_issues()
  end

  test "does not report a receive timeout with an unrelated 500 elsewhere in the call" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "waits" do
        assert_receive {:count, 500}, @receive_timeout
        assert_receive {:count, 500}
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoLiteralReceiveTimeout)
    |> refute_issues()
  end

  test "reports the helpers listed in :functions at their timeout position" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "waits" do
        assert_push "event", %{}, 200
        assert_push "event", %{}
        assert_eventually(fn -> true end, 1_000)
        assert_receive :a, 100
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoLiteralReceiveTimeout,
      functions: [{:assert_push, 3}, {:assert_eventually, 2}]
    )
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {5, "assert_push"},
               {7, "assert_eventually"}
             ]
    end)
  end

  test "checks test support files and honours :excluded_paths" do
    source = """
    defmodule MyApp.Helpers do
      defmacro await(pattern), do: quote(do: assert_receive(unquote(pattern), 100))
      def other, do: assert_receive(:x, 100)
    end
    """

    source
    |> to_source_file("test/support/helpers.ex")
    |> run_check(NoLiteralReceiveTimeout)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 3] end)

    source
    |> to_source_file("test/support/helpers.ex")
    |> run_check(NoLiteralReceiveTimeout, excluded_paths: ["test/support/helpers.ex"])
    |> refute_issues()
  end

  test "ignores library code" do
    """
    defmodule MyApp.Worker do
      def run, do: assert_receive(:x, 100)
    end
    """
    |> to_source_file("lib/my_app/worker.ex")
    |> run_check(NoLiteralReceiveTimeout)
    |> refute_issues()
  end
end
