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

  defmodule RequiredOptionCheck do
    @behaviour Bylaw.Ecto.Query.Check

    @impl Bylaw.Ecto.Query.Check
    def validate(_operation, _query, opts) do
      if Keyword.fetch!(opts, :field) == :present do
        :ok
      else
        {:error, [%Issue{check: __MODULE__, message: "missing field"}]}
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

  describe "validate/4" do
    test "with empty call-site opts preserves base check behavior" do
      assert {:error, [%Issue{check: OptionCheck}]} =
               Query.validate(:all, :query, [{OptionCheck, fail: true}], [])
    end

    test "with false disables all checks" do
      assert :ok = Query.validate(:all, :query, [{OptionCheck, fail: true}], false)
    end

    test "call-site validate false replaces an existing configured check and disables it" do
      query = from(post in "posts", limit: 1)

      assert :ok =
               Query.validate(:all, query, [RequiredOrder], [
                 {RequiredOrder, validate: false}
               ])
    end

    test "call-site rules replace configured rules entirely" do
      base_rules = [fields: [:organization_id]]
      call_site_rules = [fields: [:account_id]]

      assert {:error, [%Issue{meta: %{opts: [rules: ^call_site_rules]}}]} =
               Query.validate(:all, :query, [{FailingCheck, rules: base_rules}], [
                 {FailingCheck, rules: call_site_rules}
               ])
    end

    test "call-site bare existing check replaces configured options with defaults" do
      assert :ok = Query.validate(:all, :query, [{OptionCheck, fail: true}], [OptionCheck])
    end

    test "call-site new check appends after base checks" do
      assert {:error,
              [
                %Issue{check: FailingCheck},
                %Issue{check: MultiIssueCheck, message: "first"},
                %Issue{check: MultiIssueCheck, message: "second"}
              ]} = Query.validate(:all, :query, [FailingCheck], [MultiIssueCheck])
    end

    test "duplicate call-site checks raise a clear error" do
      assert_raise ArgumentError, "duplicate query check: #{inspect(OptionCheck)}", fn ->
        Query.validate(:all, :query, [], [OptionCheck, {OptionCheck, fail: true}])
      end
    end

    test "invalid call-site specs raise existing-style errors" do
      assert_raise ArgumentError, "expected check opts to be a keyword list, got: [:bad]", fn ->
        Query.validate(:all, :query, [], [{PassingCheck, [:bad]}])
      end

      assert_raise ArgumentError, "expected :not_a_module to be a query check module", fn ->
        Query.validate(:all, :query, [], [:not_a_module])
      end

      assert_raise ArgumentError,
                   "expected call-site Bylaw opts to be false or a list, got: :bad",
                   fn ->
                     Query.validate(:all, :query, [], :bad)
                   end
    end

    test "works with Ecto repo call opts shape" do
      repo_opts = [bylaw: [{OptionCheck, fail: true}]]

      assert {:error, [%Issue{check: OptionCheck}]} =
               Query.validate(:all, :query, [PassingCheck], Keyword.get(repo_opts, :bylaw, []))
    end
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
