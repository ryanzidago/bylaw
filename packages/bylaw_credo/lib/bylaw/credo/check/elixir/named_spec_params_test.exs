defmodule Bylaw.Credo.Check.Elixir.NamedSpecParamsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NamedSpecParams

  describe "specs with more than 3 arguments" do
    test "reports when spec args are positional types without names" do
      """
      defmodule Example do
        @spec submit(UUIDv7.t(), UUIDv7.t(), UUIDv7.t(), UUIDv7.t(), list(map())) :: :ok
        def submit(tenant_id, workspace_id, run_id, message_id, tool_results) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end

    test "does not report when all spec args use named types" do
      """
      defmodule Example do
        @spec submit(
                tenant_id :: UUIDv7.t(),
                workspace_id :: UUIDv7.t(),
                run_id :: UUIDv7.t(),
                message_id :: UUIDv7.t(),
                tool_results :: list(map())
              ) :: :ok
        def submit(tenant_id, workspace_id, run_id, message_id, tool_results) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> refute_issues()
    end

    test "reports when some spec args are named and some are not" do
      """
      defmodule Example do
        @spec process(tenant_id :: UUIDv7.t(), UUIDv7.t(), integer(), boolean()) :: :ok
        def process(tenant_id, workspace_id, run_id, flag) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end
  end

  describe "specs with 3 or fewer arguments" do
    test "reports positional types with 3 args" do
      """
      defmodule Example do
        @spec create(UUIDv7.t(), integer(), boolean()) :: :ok
        def create(name, age, active) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end

    test "reports positional types with 2 args" do
      """
      defmodule Example do
        @spec fetch(UUIDv7.t(), integer()) :: :ok
        def fetch(id, limit) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end

    test "reports positional types with 1 arg" do
      """
      defmodule Example do
        @spec process(UUIDv7.t()) :: :ok
        def process(id), do: :ok
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end

    test "does not report named types with 1 arg" do
      """
      defmodule Example do
        @spec process(run_id :: UUIDv7.t()) :: :ok
        def process(run_id), do: :ok
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> refute_issues()
    end

    test "does not report zero-arg specs" do
      """
      defmodule Example do
        @spec run() :: :ok
        def run, do: :ok
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> refute_issues()
    end
  end

  describe "edge cases" do
    test "does not report specs on callbacks" do
      """
      defmodule Example do
        @callback handle(UUIDv7.t(), UUIDv7.t(), integer(), boolean()) :: :ok
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> refute_issues()
    end

    test "handles specs with default values (\\\\)" do
      """
      defmodule Example do
        @spec build(UUIDv7.t(), UUIDv7.t(), integer(), boolean()) :: :ok
        def build(a, b, c, d \\\\ true) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end

    test "handles multi-clause specs with when" do
      """
      defmodule Example do
        @spec convert(input, UUIDv7.t(), integer(), boolean()) :: :ok when input: UUIDv7.t() | atom()
        def convert(input, format, precision, strict) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end

    test "multiple args without names triggers issue" do
      """
      defmodule Example do
        @spec do_thing(UUIDv7.t(), UUIDv7.t(), integer(), boolean()) :: :ok
        def do_thing(a, b, c, d) do
          :ok
        end
      end
      """
      |> to_source_file()
      |> run_check(NamedSpecParams)
      |> assert_issue()
    end
  end
end
