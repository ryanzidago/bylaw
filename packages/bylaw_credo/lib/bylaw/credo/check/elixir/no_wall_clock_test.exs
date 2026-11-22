defmodule Bylaw.Credo.Check.Elixir.NoWallClockTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoWallClock

  test "reports the wall clock calls with their line" do
    """
    defmodule Sample do
      def a, do: DateTime.utc_now()
      def b, do: DateTime.now!("Europe/Berlin")
      def c, do: DateTime.now("Etc/UTC")
      def d, do: NaiveDateTime.utc_now()
      def e, do: NaiveDateTime.local_now()
      def f, do: Date.utc_today()
      def g, do: Time.utc_now()
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {2, "DateTime.utc_now"},
               {3, "DateTime.now!"},
               {4, "DateTime.now"},
               {5, "NaiveDateTime.utc_now"},
               {6, "NaiveDateTime.local_now"},
               {7, "Date.utc_today"},
               {8, "Time.utc_now"}
             ]
    end)
  end

  test "reports the system and Erlang clocks" do
    """
    defmodule Sample do
      def a, do: System.os_time(:second)
      def b, do: System.system_time()
      def c, do: :os.system_time(:millisecond)
      def d, do: :os.timestamp()
      def e, do: :erlang.system_time()
      def f, do: :erlang.timestamp()
      def g, do: :erlang.localtime()
      def h, do: :calendar.universal_time()
      def i, do: :calendar.local_time()
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == [
               "System.os_time",
               "System.system_time",
               ":os.system_time",
               ":os.timestamp",
               ":erlang.system_time",
               ":erlang.timestamp",
               ":erlang.localtime",
               ":calendar.universal_time",
               ":calendar.local_time"
             ]
    end)
  end

  test "reports a call inside another call, a capture, a default argument and a function tuple" do
    """
    defmodule Sample do
      def a(order), do: DateTime.compare(order.at, DateTime.utc_now())
      def b, do: Enum.map([1], &DateTime.utc_now/0)
      def c(now \\\\ DateTime.utc_now()), do: now
      def d, do: [autogenerate: {DateTime, :utc_now, []}]
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {2, "DateTime.utc_now"},
               {3, "DateTime.utc_now"},
               {4, "DateTime.utc_now"},
               {5, "{DateTime, :utc_now, []}"}
             ]
    end)
  end

  test "resolves aliases" do
    """
    defmodule Sample do
      alias DateTime, as: DT
      alias System, as: Sys

      def a, do: DT.utc_now()
      def b, do: Sys.os_time()
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["DateTime.utc_now", "System.os_time"]
    end)
  end

  test "allows monotonic time, timers and pure time functions" do
    """
    defmodule Sample do
      def a, do: System.monotonic_time(:millisecond)
      def b, do: :erlang.monotonic_time()
      def c, do: :erlang.unique_integer([:positive])
      def d, do: :timer.tc(fn -> :ok end)
      def e(at), do: DateTime.add(at, 3600, :second)
      def f, do: DateTime.from_unix!(0)
      def g, do: Date.new!(2026, 1, 1)
      def h, do: Process.send_after(self(), :tick, 10)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock)
    |> refute_issues()
  end

  test "allows the wall clock in a module listed in :allowed_modules" do
    """
    defmodule MyApp.Clock do
      def now, do: DateTime.utc_now()
      def today, do: Date.utc_today()
    end
    """
    |> to_source_file("lib/my_app/clock.ex")
    |> run_check(NoWallClock, allowed_modules: [MyApp.Clock])
    |> refute_issues()
  end

  test "allows the wall clock in modules nested in an allowed module" do
    """
    defmodule MyApp.Clock do
      defmodule Real do
        def now, do: DateTime.utc_now()
      end

      defmodule __MODULE__.Other do
        def now, do: DateTime.utc_now()
      end
    end
    """
    |> to_source_file("lib/my_app/clock.ex")
    |> run_check(NoWallClock, allowed_modules: [MyApp.Clock])
    |> refute_issues()
  end

  test "reports other modules in the same file and modules that only share a prefix" do
    """
    defmodule MyApp.Clock do
      def now, do: DateTime.utc_now()
    end

    defmodule MyApp.ClockSkew do
      def now, do: DateTime.utc_now()
    end

    defmodule MyApp.Orders do
      def now, do: DateTime.utc_now()
    end
    """
    |> to_source_file("lib/my_app/clock.ex")
    |> run_check(NoWallClock, allowed_modules: [MyApp.Clock])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.line_no) == [6, 10]
    end)
  end

  test "reports a nested module that is not under the allowed module" do
    """
    defmodule MyApp.Orders do
      defmodule Clock do
        def now, do: DateTime.utc_now()
      end
    end
    """
    |> to_source_file("lib/my_app/orders.ex")
    |> run_check(NoWallClock, allowed_modules: [MyApp.Clock])
    |> assert_issue()
  end

  test "reports test code too" do
    """
    defmodule MyApp.OrdersTest do
      use ExUnit.Case, async: true

      test "expires" do
        assert DateTime.utc_now()
      end
    end
    """
    |> to_source_file("test/my_app/orders_test.exs")
    |> run_check(NoWallClock)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "skips files matching :allowed_paths" do
    """
    defmodule MyApp.Repo.Migrations.Backfill do
      def up, do: DateTime.utc_now()
    end
    """
    |> to_source_file("priv/repo/migrations/20260101_backfill.exs")
    |> run_check(NoWallClock, allowed_paths: ["priv/repo/migrations/"])
    |> refute_issues()
  end

  test "reports the functions listed in :functions" do
    """
    defmodule Sample do
      def a, do: Timex.now()
      def b, do: DateTime.utc_now()
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock, functions: [{Timex, [:now]}])
    |> assert_issue(fn issue -> assert issue.trigger == "Timex.now" end)
  end

  test "names the allowed modules in the message" do
    """
    defmodule Sample do
      def a, do: DateTime.utc_now()
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock, allowed_modules: [MyApp.Clock])
    |> assert_issue(fn issue ->
      assert issue.message ==
               "Control time and chance: do not read the wall clock here; " <>
                 "call MyApp.Clock or take the time as an argument, so a test can set it."
    end)
  end

  test "does not resolve calls on a variable module" do
    """
    defmodule Sample do
      def a(clock), do: clock.utc_now()
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoWallClock)
    |> refute_issues()
  end
end
