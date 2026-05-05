defmodule Bylaw.DbTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  defmodule PassingCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def validate(_target, _opts), do: :ok
  end

  defmodule FailingCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def validate(target, opts) do
      {:error,
       [
         %Issue{
           check: __MODULE__,
           target: target,
           message: "failed",
           meta: %{opts: opts, target: target.meta.label}
         }
       ]}
    end
  end

  defmodule MultiIssueCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def validate(target, _opts) do
      {:error,
       [
         %Issue{check: __MODULE__, target: target, message: "first"},
         %Issue{check: __MODULE__, target: target, message: "second"}
       ]}
    end
  end

  defmodule EmptyIssueCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def validate(_target, _opts), do: {:error, []}
  end

  defmodule InvalidIssueCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def validate(_target, _opts), do: {:error, [:bad]}
  end

  describe "validate/2" do
    test "returns :ok when every check passes" do
      target = target(:primary)

      assert :ok = Db.validate([target], [PassingCheck])
    end

    test "passes check-specific options to tuple checks" do
      target = target(:primary)

      assert {:error, [%Issue{} = issue]} = Db.validate([target], [{FailingCheck, sample: true}])

      assert issue.meta.opts == [sample: true]
    end

    test "collects issues across multiple targets" do
      targets = [target(:primary), target(:analytics)]

      assert {:error, issues} = Db.validate(targets, [FailingCheck])

      assert Enum.map(issues, & &1.meta.target) == [:primary, :analytics]
    end

    test "preserves multiple issues returned by one check" do
      target = target(:primary)

      assert {:error, issues} = Db.validate([target], [MultiIssueCheck])

      assert Enum.map(issues, & &1.message) == ["first", "second"]
    end

    test "raises when a failing check returns no issues" do
      target = target(:primary)

      assert_raise ArgumentError, ~r/expected #{inspect(EmptyIssueCheck)}.validate\/2/, fn ->
        Db.validate([target], [EmptyIssueCheck])
      end
    end

    test "raises when a failing check returns invalid issues" do
      target = target(:primary)

      assert_raise ArgumentError, ~r/expected #{inspect(InvalidIssueCheck)}.validate\/2/, fn ->
        Db.validate([target], [InvalidIssueCheck])
      end
    end

    test "raises for malformed check specs" do
      target = target(:primary)

      assert_raise ArgumentError, ~r/expected a check module or {check, opts}/, fn ->
        Db.validate([target], [{"not a module", []}])
      end
    end

    test "raises for malformed check options" do
      target = target(:primary)

      assert_raise ArgumentError, ~r/expected check opts to be a keyword list/, fn ->
        Db.validate([target], [{PassingCheck, [:not_keyword]}])
      end
    end

    test "raises for malformed check lists" do
      target = target(:primary)

      assert_raise ArgumentError, ~r/expected checks to be a list/, fn ->
        Db.validate([target], PassingCheck)
      end
    end

    test "raises for missing targets" do
      assert_raise ArgumentError, ~r/expected database targets to be a list/, fn ->
        Db.validate(nil, [PassingCheck])
      end
    end

    test "raises for empty target lists" do
      assert_raise ArgumentError, ~r/expected at least one database target/, fn ->
        Db.validate([], [PassingCheck])
      end
    end
  end

  defp target(label) do
    %Target{
      adapter: __MODULE__,
      meta: %{label: label}
    }
  end
end
