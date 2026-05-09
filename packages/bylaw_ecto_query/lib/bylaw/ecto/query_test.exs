defmodule Bylaw.Ecto.QueryTest do
  use ExUnit.Case, async: true

  doctest Bylaw.Ecto.Query

  import Ecto.Query

  alias Bylaw.Ecto.Query
  alias Bylaw.Ecto.Query.Checks.RequiredOrder
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
       [
         %Issue{
           check: __MODULE__,
           message: "failed",
           meta: %{operation: operation, opts: opts}
         }
       ]}
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
        {:error, [%Issue{check: __MODULE__, message: "failed"}]}
      else
        :ok
      end
    end
  end

  defmodule EmptyIssueCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(_operation, _query, _opts), do: {:error, []}
  end

  defmodule InvalidIssueCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(_operation, _query, _opts), do: {:error, [:bad]}
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

    test "raises when checks are not a list" do
      assert_raise ArgumentError, "expected checks to be a list, got: :bad", fn ->
        Query.validate(:all, :query, :bad)
      end
    end

    test "collects check issue lists" do
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

    test "raises for duplicate check modules" do
      assert_raise ArgumentError, "duplicate query check: #{inspect(OptionCheck)}", fn ->
        Query.validate(:all, :query, [
          {OptionCheck, fail: true},
          {OptionCheck, fail: false}
        ])
      end
    end

    test "runs built-in checks from module specs" do
      query = from(post in "posts", limit: 1)

      assert {:error, [%Issue{check: RequiredOrder}]} =
               Query.validate(:all, query, [RequiredOrder])
    end

    test "passes check-specific opts to built-in checks" do
      query = from(post in "posts", limit: 1)

      assert :ok = Query.validate(:all, query, [{RequiredOrder, validate: false}])
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

      assert_raise ArgumentError, "expected String to be a query check module", fn ->
        Query.validate(:all, :query, [String])
      end
    end

    test "raises for malformed check options" do
      assert_raise ArgumentError, "expected check opts to be a keyword list, got: [:bad]", fn ->
        Query.validate(:all, :query, [{PassingCheck, [:bad]}])
      end
    end

    test "raises for malformed check results" do
      assert_raise ArgumentError,
                   "expected #{inspect(InvalidReturnCheck)}.validate/3 to return :ok or {:error, non_empty_issue_list}, got: :error",
                   fn ->
                     Query.validate(:all, :query, [InvalidReturnCheck])
                   end

      assert_raise ArgumentError,
                   "expected #{inspect(EmptyIssueCheck)}.validate/3 to return :ok or {:error, non_empty_issue_list}, got: {:error, []}",
                   fn ->
                     Query.validate(:all, :query, [EmptyIssueCheck])
                   end

      assert_raise ArgumentError,
                   "expected #{inspect(InvalidIssueCheck)}.validate/3 to return :ok or {:error, non_empty_issue_list}, got: {:error, [:bad]}",
                   fn ->
                     Query.validate(:all, :query, [InvalidIssueCheck])
                   end
    end
  end
end
