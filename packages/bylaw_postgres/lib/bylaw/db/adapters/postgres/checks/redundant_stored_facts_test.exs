defmodule Bylaw.Db.Adapters.Postgres.Checks.RedundantStoredFactsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.RedundantStoredFacts

  test "reviews each selected table once in deterministic order despite overlapping scopes" do
    assert :ok =
             run([table("z"), table("a"), table("other", "audit")],
               rules: [[where: [schemas: ["public"]]], [where: [tables: [~r/^[az]$/]]]]
             )

    assert_received {:review, first}
    assert %{version: 1, table: %{name: "a"}, invariant: %{version: 1}} = first
    assert_received {:review, second}
    assert second.table.name == "z"
    refute_received {:review, _}
  end

  test "except rules skip tables without calling the reviewer" do
    assert :ok = run([table("orders")], rules: [except: [tables: ["orders"]]])
    refute_received {:review, _}
  end

  test "validate false performs no catalogue query or review" do
    target = Postgres.target(query: fn _, _, _, _ -> flunk("disabled query") end)
    assert :ok = RedundantStoredFacts.validate(target, validate: false)
  end

  test "passes only no violation and justified exception results" do
    for result <- [:no_violation, :justified_exception] do
      assert :ok = run([table("orders")], reviewer: fn _ -> {:ok, result} end)
    end
  end

  test "reports violation and insufficient context as distinct issues" do
    for {result, category} <- [violation: :violation, insufficient_context: :inconclusive] do
      assert {:error, [issue]} = run([table("orders")], reviewer: fn _ -> {:ok, result} end)
      assert issue.meta.category == category
      assert issue.meta.review_result == result
      assert issue.meta.schema == "public"
      assert issue.meta.table == "orders"
    end
  end

  test "reports every tagged reviewer failure and continues other tables" do
    for reason <- [
          :not_configured,
          :timeout,
          :request_failed,
          :invalid_response,
          :input_too_large
        ] do
      parent = self()

      assert {:error, [issue]} =
               run([table("a"), table("b")],
                 reviewer: fn input ->
                   send(parent, {:continued, input.table.name})
                   if input.table.name == "a", do: {:error, reason}, else: {:ok, :no_violation}
                 end
               )

      assert issue.meta.category == :reviewer_failure
      assert issue.meta.reason == reason
      assert_received {:continued, "a"}
      assert_received {:continued, "b"}
    end
  end

  test "rejects malformed reviewer results without exposing their payload" do
    for bad <- [:ok, {:ok, :unknown}, {:error, "secret"}, %{token: "secret"}] do
      assert {:error, [issue]} = run([table("orders")], reviewer: fn _ -> bad end)
      assert issue.meta.category == :reviewer_failure
      assert issue.meta.reason == :invalid_response
      refute inspect(issue) =~ "secret"
    end
  end

  test "propagates caller bugs instead of disguising them as reviewer failures" do
    assert_raise RuntimeError, "caller bug", fn ->
      run([table("orders")], reviewer: fn _ -> raise "caller bug" end)
    end
  end

  test "supplies scoped deduplicated column exceptions without waiving review" do
    exception = %{columns: ["unit_price"], reason: "Preserves the agreed purchase price"}

    assert {:error, [issue]} =
             run([table("orders"), table("other")],
               rules: [
                 [where: [tables: ["orders"]], exceptions: [exception]],
                 [where: [tables: ["orders"]], exceptions: [exception]],
                 [where: [tables: ["other"]]]
               ],
               reviewer: fn input ->
                 send(self(), {:review, input})

                 if input.table.name == "orders",
                   do: {:ok, :violation},
                   else: {:ok, :no_violation}
               end
             )

    assert issue.meta.category == :violation
    assert_received {:review, %{table: %{name: "orders"}, exceptions: [^exception]}}
    assert_received {:review, %{table: %{name: "other"}, exceptions: []}}
  end

  test "reports nonexistent exception columns without reviewing bad context" do
    assert {:error, [issue]} =
             run([table("orders")],
               rules: [
                 exceptions: [
                   %{columns: ["missing"], reason: "Historical snapshot"}
                 ]
               ]
             )

    assert issue.meta.category == :invalid_exception
    assert issue.meta.columns == ["missing"]
    refute_received {:review, _}
  end

  test "rejects invalid reviewer and exception configuration" do
    target = target({:ok, []})

    for opts <- [
          [],
          [reviewer: nil],
          [reviewer: fn _, _ -> :ok end],
          [reviewer: &pass/1, rules: [exceptions: [%{columns: [], reason: "x"}]]],
          [reviewer: &pass/1, rules: [exceptions: [%{columns: ["id"], reason: " "}]]],
          [reviewer: &pass/1, rules: [where: [schema: ["public"]]]],
          [reviewer: &pass/1, unknown: true]
        ] do
      assert_raise ArgumentError, fn -> RedundantStoredFacts.validate(target, opts) end
    end
  end

  test "reports inspection failures without exposing query error details" do
    assert {:error, [issue]} =
             RedundantStoredFacts.validate(target({:error, "secret"}), reviewer: &pass/1)

    assert issue.meta.category == :inspection_failure
    assert issue.meta.reason == :query_failed
    refute inspect(issue) =~ "secret"
  end

  test "reads catalogue metadata only in a single statement without table data" do
    assert :ok = run([])
    assert_received {:query, sql, [], []}
    assert sql =~ "pg_catalog.pg_attribute"
    assert sql =~ "pg_get_constraintdef"
    assert sql =~ "pg_get_indexdef"
    assert sql =~ "pg_get_expr"
    refute sql =~ "SELECT *"
    refute_received {:query, _, _, _}
    refute_received {:review, _}
  end

  test "formatted table issues expose actionable identity and safe failure details" do
    for result <- [{:ok, :violation}, {:ok, :insufficient_context}, {:error, :timeout}] do
      assert {:error, [issue]} = run([table("orders")], reviewer: fn _ -> result end)
      formatted = Bylaw.Db.Issue.format(issue)
      assert formatted =~ ~s("public"."orders")
      if result == {:error, :timeout}, do: assert(formatted =~ "timeout")
    end

    assert {:error, [issue]} =
             run([table("orders")],
               rules: [
                 exceptions: [
                   %{columns: ["missing"], reason: "Historical value"}
                 ]
               ]
             )

    assert Bylaw.Db.Issue.format(issue) =~ ~s("public"."orders")
    assert Bylaw.Db.Issue.format(issue) =~ ~s("missing")
  end

  defp pass(_input), do: {:ok, :no_violation}

  defp run(tables, opts \\ []) do
    parent = self()

    reviewer = fn input ->
      send(parent, {:review, input})
      pass(input)
    end

    RedundantStoredFacts.validate(
      target({:ok, Enum.map(tables, &%{"table_evidence" => &1})}),
      Keyword.put_new(opts, :reviewer, reviewer)
    )
  end

  defp target(result) do
    parent = self()

    Postgres.target(
      query: fn _, sql, params, opts ->
        send(parent, {:query, sql, params, opts})
        result
      end
    )
  end

  defp table(name, schema \\ "public") do
    %{
      "schema" => schema,
      "name" => name,
      "kind" => "ordinary",
      "comment" => nil,
      "columns" => [
        %{
          "name" => "unit_price",
          "position" => 1,
          "type" => "numeric",
          "nullable" => false,
          "default" => nil,
          "generated_expression" => nil,
          "generated_kind" => "",
          "identity" => "",
          "comment" => nil,
          "type_details" => nil
        }
      ],
      "constraints" => [],
      "indexes" => []
    }
  end
end
