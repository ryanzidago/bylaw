defmodule Bylaw.DbPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bylaw.Db
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  defmodule FailingCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def validate(target, _opts) do
      {:error,
       [
         %Issue{
           check: __MODULE__,
           message: "failed",
           target: target,
           meta: %{target_id: target.meta.id}
         }
       ]}
    end
  end

  property "validation preserves target issue order" do
    check all(target_ids <- list_of(integer(), min_length: 1)) do
      targets =
        Enum.map(target_ids, fn target_id ->
          %Target{adapter: __MODULE__, meta: %{id: target_id}}
        end)

      assert {:error, issues} = Db.validate(targets, [FailingCheck])
      assert Enum.map(issues, & &1.target) == targets
      assert Enum.map(issues, & &1.meta.target_id) == target_ids
    end
  end
end
