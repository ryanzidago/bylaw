defmodule Bylaw.Credo.Check.Testing.NoGlobalStateInAsyncTestsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.NoGlobalStateInAsyncTests

  defp triggers(issues), do: Enum.map(issues, &{&1.line_no, &1.trigger})

  test "reports environment writes in an async test module, with the fix in the message" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        Application.put_env(:my_app, :key, :value)
        assert true
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
      assert issue.trigger == "Application.put_env"

      assert issue.message ==
               "Own your state: avoid `Application.put_env` in an async test - it changes state shared with every other test module running at the same time. " <>
                 "Pass the value in as an argument or an option, use an unnamed process, or set `async: false`."
    end)
  end

  test "reports every environment and logger write" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      setup do
        Application.put_env(:my_app, :a, 1)
        Application.put_env(:my_app, :b, :c, 2)
        Application.put_all_env(my_app: [a: 1])
        on_exit(fn -> Application.delete_env(:my_app, :a) end)
        System.put_env("A", "1")
        System.delete_env("A")
        Logger.configure(level: :debug)
        :ok
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issues(fn issues ->
      assert triggers(issues) == [
               {5, "Application.put_env"},
               {6, "Application.put_env"},
               {7, "Application.put_all_env"},
               {8, "Application.delete_env"},
               {9, "System.put_env"},
               {10, "System.delete_env"},
               {11, "Logger.configure"}
             ]
    end)
  end

  test "allows reading the environment" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "reads" do
        assert Application.get_env(:my_app, :key)
        assert Application.fetch_env!(:my_app, :key)
        assert System.get_env("HOME")
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> refute_issues()
  end

  test "ignores modules that are not async" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: false

      test "does something" do
        Application.put_env(:my_app, :key, :value)
        Process.register(self(), :my_test)
      end
    end

    defmodule OtherTest do
      use ExUnit.Case

      test "does something" do
        Application.put_env(:my_app, :key, :value)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> refute_issues()
  end

  test "treats any case module with async: true as async and checks each module on its own" do
    """
    defmodule AsyncTest do
      use MyApp.DataCase, async: true

      test "does something" do
        Application.put_env(:my_app, :key, :value)
      end
    end

    defmodule SyncTest do
      use MyApp.DataCase, async: false

      test "does something" do
        Application.put_env(:my_app, :key, :value)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "reports process registration under a fixed name, and allows a dynamic one" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "registers" do
        Process.register(self(), :fixed)
        Process.register(self(), __MODULE__)
        Process.register(self(), MyApp.Server)
        :erlang.register(:other, self())
        Process.register(self(), :"test_\#{System.unique_integer()}")
        Process.register(self(), name)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issues(fn issues ->
      assert triggers(issues) == [
               {5, "Process.register"},
               {6, "Process.register"},
               {7, "Process.register"},
               {8, ":erlang.register"}
             ]
    end)
  end

  test "reports named ETS tables and fixed persistent_term keys only" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      @key :my_key

      test "stores" do
        :ets.new(:shared, [:named_table, :public])
        :ets.new(:private_name, [:public])
        :ets.new(table_name, [:named_table])
        :ets.new(:set, [:set])
        :persistent_term.put({__MODULE__, :fault}, :timeout)
        :persistent_term.put(@key, 1)
        :persistent_term.erase(:my_key)
        :persistent_term.put({__MODULE__, id}, 1)
        :persistent_term.get({__MODULE__, :fault})
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issues(fn issues ->
      assert triggers(issues) == [
               {7, ":ets.new"},
               {11, ":persistent_term.put"},
               {12, ":persistent_term.put"},
               {13, ":persistent_term.erase"}
             ]
    end)
  end

  test "reports a fixed name option when starting a process, and allows others" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "starts" do
        start_supervised!({MyApp.Counter, name: MyApp.Counter})
        start_supervised!({MyApp.Counter, [name: :counter]})
        {:ok, _pid} = GenServer.start_link(MyApp.Counter, 0, name: __MODULE__)
        {:ok, _pid} = Agent.start_link(fn -> 0 end, name: {:global, :agent})
        start_supervised!({MyApp.Counter, name: :"c_\#{System.unique_integer()}"})
        start_supervised!({MyApp.Counter, name: name})
        start_supervised!({MyApp.Counter, name: {:via, Registry, {MyApp.Registry, :key}}})
        start_supervised!(MyApp.Counter)
        {:ok, _pid} = GenServer.start_link(MyApp.Counter, 0)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issues(fn issues ->
      assert triggers(issues) == [
               {5, "name: MyApp.Counter"},
               {6, "name: :counter"},
               {7, "name: __MODULE__"},
               {8, "name: {:global, :agent}"}
             ]
    end)
  end

  test "reports global Mox mode" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true
      import Mox

      setup :set_mox_global
      setup :set_mox_from_context
      setup :verify_on_exit!

      test "does something" do
        Mox.set_mox_global()
        Hammox.set_mox_global(%{})
        set_mox_global()
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issues(fn issues ->
      assert triggers(issues) == [
               {5, "setup :set_mox_global"},
               {10, "Mox.set_mox_global"},
               {11, "Hammox.set_mox_global"},
               {12, "set_mox_global"}
             ]
    end)
  end

  test "resolves aliases" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true
      alias Application, as: App

      test "does something" do
        App.put_env(:my_app, :key, :value)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests)
    |> assert_issue(fn issue -> assert issue.trigger == "Application.put_env" end)
  end

  test "ignores files that are not test files and honours :excluded_paths" do
    source = """
    defmodule MyApp.Helper do
      use ExUnit.Case, async: true

      def set, do: Application.put_env(:my_app, :key, :value)
    end
    """

    source
    |> to_source_file("lib/my_app/helper.ex")
    |> run_check(NoGlobalStateInAsyncTests)
    |> refute_issues()

    source
    |> to_source_file("test/legacy/helper_test.exs")
    |> run_check(NoGlobalStateInAsyncTests, excluded_paths: ["test/legacy/"])
    |> refute_issues()
  end

  test "reports the functions listed in :functions" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        MyApp.Settings.put(:key, 1)
        Application.put_env(:my_app, :key, 1)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoGlobalStateInAsyncTests, functions: [{MyApp.Settings, [:put]}])
    |> assert_issue(fn issue -> assert issue.trigger == "MyApp.Settings.put" end)
  end
end
