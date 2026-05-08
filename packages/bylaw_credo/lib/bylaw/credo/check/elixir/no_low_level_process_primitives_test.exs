defmodule Bylaw.Credo.Check.Elixir.NoLowLevelProcessPrimitivesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoLowLevelProcessPrimitives

  describe "Process" do
    test "reports Process.put" do
      """
      defmodule Example do
        def run do
          Process.put(:key, :value)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Process.put"
      end)
    end

    test "reports Process.get" do
      """
      defmodule Example do
        def run do
          Process.get(:key)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Process.get"
      end)
    end

    test "reports Process.send_after" do
      """
      defmodule Example do
        def run do
          Process.send_after(self(), :tick, 1_000)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Process.send_after"
      end)
    end

    test "reports Process.flag" do
      """
      defmodule Example do
        def run do
          Process.flag(:trap_exit, true)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Process.flag"
      end)
    end
  end

  describe "GenServer" do
    test "reports GenServer.start_link" do
      """
      defmodule Example do
        def run do
          GenServer.start_link(MyServer, [])
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == "GenServer.start_link"
      end)
    end

    test "reports GenServer.call" do
      """
      defmodule Example do
        def run(server) do
          GenServer.call(server, :get)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == "GenServer.call"
      end)
    end

    test "reports GenServer.cast" do
      """
      defmodule Example do
        def run(server) do
          GenServer.cast(server, {:update, :value})
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == "GenServer.cast"
      end)
    end
  end

  describe "ETS" do
    test "reports :ets.new" do
      """
      defmodule Example do
        def run do
          :ets.new(:my_table, [:set, :public])
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == ":ets.new"
      end)
    end

    test "reports :ets.insert" do
      """
      defmodule Example do
        def run(table) do
          :ets.insert(table, {:key, :value})
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == ":ets.insert"
      end)
    end

    test "reports :ets.lookup" do
      """
      defmodule Example do
        def run(table) do
          :ets.lookup(table, :key)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issue(fn issue ->
        assert issue.trigger == ":ets.lookup"
      end)
    end
  end

  describe "multiple calls" do
    test "reports mixed primitives in a single module" do
      """
      defmodule Example do
        def run do
          Process.put(:key, :value)
          GenServer.call(MyServer, :get)
          :ets.lookup(:table, :key)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> assert_issues(fn issues ->
        assert Enum.count(issues) == 3
      end)
    end
  end

  describe "excluded paths" do
    test "respects excluded_paths with string prefix" do
      """
      defmodule Example do
        def run do
          Process.put(:key, :value)
        end
      end
      """
      |> to_source_file("lib/my_app/worker.ex")
      |> run_check(NoLowLevelProcessPrimitives, excluded_paths: ["lib/my_app/worker"])
      |> refute_issues()
    end

    test "respects excluded_paths with regex" do
      """
      defmodule Example do
        def run do
          GenServer.call(MyServer, :get)
        end
      end
      """
      |> to_source_file("lib/my_app/gen_server_impl.ex")
      |> run_check(NoLowLevelProcessPrimitives, excluded_paths: [~r/gen_server/])
      |> refute_issues()
    end
  end

  describe "allowed modules" do
    test "does not report Agent (indistinguishable from aliased app modules)" do
      """
      defmodule Example do
        def run(agent) do
          Agent.get(agent, & &1)
          Agent.update(agent, fn s -> s end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> refute_issues()
    end

    test "does not report Task.async" do
      """
      defmodule Example do
        def run do
          Task.async(fn -> :ok end)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> refute_issues()
    end

    test "does not report Task.await" do
      """
      defmodule Example do
        def run(task) do
          Task.await(task)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> refute_issues()
    end

    test "does not report plain function calls" do
      """
      defmodule Example do
        def run do
          Enum.map([1, 2, 3], & &1 * 2)
        end
      end
      """
      |> to_source_file()
      |> run_check(NoLowLevelProcessPrimitives)
      |> refute_issues()
    end
  end
end
