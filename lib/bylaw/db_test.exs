defmodule Bylaw.DbTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  defmodule PassingCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def name, do: :passing_check

    @impl Bylaw.Db.Check
    def validate(_target, _opts), do: :ok
  end

  defmodule FailingCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def name, do: :failing_check

    @impl Bylaw.Db.Check
    def validate(target, opts) do
      {:error,
       %Issue{
         check: __MODULE__,
         target: target,
         message: "failed",
         meta: %{opts: opts, target: target.name}
       }}
    end
  end

  defmodule MultiIssueCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def name, do: :multi_issue_check

    @impl Bylaw.Db.Check
    def validate(target, _opts) do
      {:error,
       [
         %Issue{check: __MODULE__, target: target, message: "first"},
         %Issue{check: __MODULE__, target: target, message: "second"}
       ]}
    end
  end

  describe "validate/2" do
    test "returns :ok when every check passes" do
      target = target(:primary)

      assert :ok = Db.validate(target, [PassingCheck])
    end

    test "passes check-specific options to tuple checks" do
      target = target(:primary)

      assert {:error, %Issue{} = issue} = Db.validate(target, [{FailingCheck, sample: true}])

      assert issue.meta.opts == [sample: true]
    end

    test "collects issues across multiple targets" do
      targets = [target(:primary), target(:analytics)]

      assert {:error, issues} = Db.validate(targets, [FailingCheck])

      assert Enum.map(issues, & &1.meta.target) == [:primary, :analytics]
    end

    test "preserves multiple issues returned by one check" do
      target = target(:primary)

      assert {:error, issues} = Db.validate(target, [MultiIssueCheck])

      assert Enum.map(issues, & &1.message) == ["first", "second"]
    end

    test "raises for malformed check specs" do
      target = target(:primary)

      assert_raise ArgumentError, ~r/expected a check module or {check, opts}/, fn ->
        Db.validate(target, [{"not a module", []}])
      end
    end

    test "raises for missing targets" do
      assert_raise ArgumentError, ~r/expected a database target or list of targets/, fn ->
        Db.validate(nil, [PassingCheck])
      end
    end
  end

  defp target(name) do
    %Target{
      adapter: __MODULE__,
      name: name,
      schema: "public"
    }
  end
end
