defmodule Bylaw.Credo.Check.Readability.NoFunctionCallInWithBodyTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Readability.NoFunctionCallInWithBody

  describe "reports function calls whose spec returns errors" do
    test "remote function call to module whose spec returns error" do
      """
      defmodule Example do
        def call do
          with {:ok, record_1} <- Enum.fetch([], 0) do
            File.read("path")
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> assert_issue(%{
        line_no: 4,
        message: ~r/Move fallible function calls/
      })
    end

    test "pipe chain ending in fallible function" do
      """
      defmodule Example do
        def call do
          with {:ok, path} <- get_path() do
            path
            |> File.read()
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> assert_issue(%{
        message: ~r/Move fallible function calls/
      })
    end

    test "remote function call whose spec returns an aliased result type" do
      """
      defmodule Example do
        def call do
          with {:ok, query} <- Enum.fetch([], 0) do
            Bylaw.Ecto.Query.Checks.RequiredOrder.validate(:all, query, [])
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> assert_issue(%{
        line_no: 4,
        message: ~r/Move fallible function calls/
      })
    end

    test "aliased remote function call whose spec returns error" do
      """
      defmodule Example do
        alias File, as: F

        def call do
          with {:ok, path} <- Enum.fetch([], 0) do
            F.read(path)
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> assert_issue(%{
        line_no: 6,
        message: ~r/Move fallible function calls/
      })
    end

    test "imported function call whose spec returns error" do
      """
      defmodule Example do
        import File, only: [read: 1]

        def call do
          with {:ok, path} <- Enum.fetch([], 0) do
            read(path)
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> assert_issue(%{
        line_no: 6,
        message: ~r/Move fallible function calls/
      })
    end
  end

  describe "does not report when spec is unknown" do
    test "local function call with no spec available" do
      """
      defmodule Example do
        def call do
          with {:ok, record} <- create_record() do
            do_something()
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "local function call in block with no spec available" do
      """
      defmodule Example do
        def call do
          with {:ok, record} <- create_record() do
            _ignored = side_effect()
            finalize(record)
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end
  end

  describe "does not report when spec proves function cannot return errors" do
    test "remote function call whose spec never returns error" do
      """
      defmodule Example do
        def call do
          with {:ok, items} <- fetch_items() do
            Enum.map(items, & &1.name)
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "pipe chain ending in non-fallible remote function" do
      """
      defmodule Example do
        def call do
          with {:ok, items} <- fetch_items() do
            items
            |> Enum.map(& &1.name)
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end
  end

  describe "does not report non-function-call returns" do
    test "ok tuple wrapping a value" do
      """
      defmodule Example do
        def call do
          with {:ok, record_1} <- create_record(),
               {:ok, record_2} <- create_record() do
            {:ok, record_2}
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "tagged tuple with custom tag" do
      """
      defmodule Example do
        def call do
          with {:ok, run} <- transition(run) do
            {:requires_action, run}
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "bare variable return" do
      """
      defmodule Example do
        def call do
          with {:ok, record} <- create_record() do
            record
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "atom return" do
      """
      defmodule Example do
        def call do
          with {:ok, _record} <- create_record() do
            :ok
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "with without else clause is ignored" do
      """
      defmodule Example do
        def call do
          with {:ok, record} <- create_record() do
            do_something(record)
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "list return" do
      """
      defmodule Example do
        def call do
          with {:ok, records} <- fetch_records() do
            [first | records]
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end

    test "map return" do
      """
      defmodule Example do
        def call do
          with {:ok, user} <- fetch_user(id) do
            %{name: user.name}
          else
            {:error, reason} -> {:error, reason}
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(NoFunctionCallInWithBody)
      |> refute_issues()
    end
  end
end
