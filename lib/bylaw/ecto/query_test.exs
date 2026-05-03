defmodule Bylaw.Ecto.QueryTest do
  use ExUnit.Case, async: true

  alias Bylaw.Ecto.Query
  alias Bylaw.Ecto.Query.Issue

  defmodule PassingCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(_operation, _query, _opts), do: :ok
  end

  defmodule FailingCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(operation, _query, opts) do
      {:error,
       %Issue{
         check: __MODULE__,
         message: "failed",
         meta: %{operation: operation, opts: opts}
       }}
    end
  end

  defmodule MultiIssueCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(_operation, _query, _opts) do
      {:error,
       [
         %Issue{check: __MODULE__, message: "first"},
         %Issue{check: __MODULE__, message: "second"}
       ]}
    end
  end

  defmodule OptionCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(_operation, _query, opts) do
      if Keyword.get(opts, :fail, false) do
        {:error, %Issue{check: __MODULE__, message: "failed"}}
      else
        :ok
      end
    end
  end

  defmodule InvalidReturnCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(_operation, _query, _opts), do: :error
  end

  describe "validate/3" do
    test "returns ok when every check passes" do
      assert :ok = Query.validate(:all, :query, [PassingCheck])
    end

    test "normalizes single and multiple issues" do
      assert {:error, issues} =
               Query.validate(:all, :query, [
                 PassingCheck,
                 {FailingCheck, sample: true},
                 MultiIssueCheck
               ])

      assert [
               %Issue{check: FailingCheck, message: "failed", meta: %{opts: [sample: true]}},
               %Issue{check: MultiIssueCheck, message: "first"},
               %Issue{check: MultiIssueCheck, message: "second"}
             ] = issues
    end

    test "uses the last spec for a repeated check module" do
      assert :ok =
               Query.validate(:all, :query, [
                 {OptionCheck, fail: true},
                 {OptionCheck, fail: false}
               ])
    end

    test "raises for malformed checks" do
      assert_raise ArgumentError,
                   "expected :not_a_module to be a query check module",
                   fn ->
                     Query.validate(:all, :query, [{:not_a_module, :bad}])
                   end

      assert_raise ArgumentError, "expected NotLoadedCheck to be a query check module", fn ->
        Query.validate(:all, :query, [NotLoadedCheck])
      end
    end

    test "raises for malformed check options" do
      assert_raise ArgumentError, "expected check opts to be a keyword list, got: [:bad]", fn ->
        Query.validate(:all, :query, [{PassingCheck, [:bad]}])
      end
    end

    test "raises for malformed check results" do
      assert_raise ArgumentError,
                   "expected #{inspect(InvalidReturnCheck)}.validate/3 to return :ok or {:error, issue_or_issues}, got: :error",
                   fn ->
                     Query.validate(:all, :query, [InvalidReturnCheck])
                   end
    end
  end
end
