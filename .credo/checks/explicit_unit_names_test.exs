defmodule Bylaw.Credo.Check.Readability.ExplicitUnitNamesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Readability.ExplicitUnitNames

  test "flags ambiguous function parameters" do
    """
    defmodule Example do
      def run(timeout) do
        timeout
      end
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> assert_issue(%{
      line_no: 2,
      trigger: "timeout",
      message: ~r/timeout_ms/
    })
  end

  test "allows bare amount for now" do
    """
    defmodule Example do
      def run do
        amount = Decimal.new("12.34")
        amount
      end
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> refute_issues()
  end

  test "flags bindings introduced in with clauses" do
    """
    defmodule Example do
      def run do
        with {:ok, timeout} <- fetch() do
          timeout
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> assert_issue(%{
      line_no: 3,
      trigger: "timeout"
    })
  end

  test "flags module attributes" do
    """
    defmodule Example do
      @request_timeout 5_000
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> assert_issue(%{
      line_no: 2,
      trigger: "request_timeout"
    })
  end

  test "allows identifiers with explicit time units" do
    """
    defmodule Example do
      def run(timeout_ms, timeout_in_seconds) do
        timeout_ms + timeout_in_seconds
      end
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> refute_issues()
  end

  test "allows identifiers with explicit currency units" do
    """
    defmodule Example do
      def run(amount_cents, price_usd) do
        amount_cents + price_usd
      end
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> refute_issues()
  end

  test "flags ambiguous monetary names that are still in scope" do
    """
    defmodule Example do
      def run do
        price = Decimal.new("12.34")
        price
      end
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> assert_issue(%{
      line_no: 3,
      trigger: "price",
      message: ~r/price_usd/
    })
  end

  test "flags ambiguous environment variable names" do
    """
    System.get_env("COMPLETION_TIMEOUT")
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> assert_issue(%{
      line_no: 1,
      trigger: "COMPLETION_TIMEOUT",
      message: ~r/COMPLETION_TIMEOUT_MS/
    })
  end

  test "allows explicit units in environment variable names" do
    """
    System.get_env("COMPLETION_TIMEOUT_MS")
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> refute_issues()
  end

  test "flags ambiguous application config keys" do
    """
    Application.get_env(:bylaw, :completion_timeout, 120_000)
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> assert_issue(%{
      line_no: 1,
      trigger: ":completion_timeout",
      message: ~r/:completion_timeout_ms/
    })
  end

  test "flags ambiguous config macro keys for the app" do
    """
    import Config

    config :bylaw, :completion_timeout, 5_000
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> assert_issue(%{
      line_no: 3,
      trigger: ":completion_timeout"
    })
  end

  test "ignores error atoms and other non-binding atoms" do
    """
    defmodule Example do
      def run, do: {:error, :timeout}
    end
    """
    |> to_source_file()
    |> run_check(ExplicitUnitNames)
    |> refute_issues()
  end
end
