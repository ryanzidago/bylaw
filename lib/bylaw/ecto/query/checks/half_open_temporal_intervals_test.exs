defmodule Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervalsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Event do
    use Ecto.Schema

    schema "events" do
      field(:event_date, :date)
      field(:starts_at, :time)
      field(:ends_at, :time_usec)
      field(:scheduled_at, :naive_datetime)
      field(:occurred_at, :utc_datetime)
      field(:archived_at, :utc_datetime_usec)
      field(:published_at, :naive_datetime_usec)
      field(:title, :string)
    end
  end

  defmodule StringEvent do
    use Ecto.Schema

    schema "string_events" do
      field(:occurred_at, :string)
      field(:title, :string)
    end
  end

  defmodule GlobalEvent do
    use Ecto.Schema

    schema "global_events" do
      field(:title, :string)
    end
  end

  defmodule Calendar do
    use Ecto.Schema

    schema "calendars" do
      field(:occurred_at, :utc_datetime)
    end
  end

  describe "validate/3" do
    test "passes when there are no where predicates" do
      query = from(event in Event)

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "passes when a temporal interval uses half-open boundaries" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          where: event.occurred_at >= ^start_at,
          where: event.occurred_at < ^end_at
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "passes when date, time, and datetime ranges use half-open boundaries" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          where: event.event_date >= ^Date.new!(2026, 1, 1),
          where: event.event_date < ^Date.new!(2026, 2, 1),
          where: event.starts_at >= ^~T[09:00:00],
          where: event.starts_at < ^~T[17:00:00],
          where: event.occurred_at >= ^start_at,
          where: event.occurred_at < ^end_at
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "passes when equivalent half-open boundaries put the field on the right" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          where: ^start_at <= event.occurred_at,
          where: ^end_at > event.occurred_at
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "ignores non-range predicates on date/time fields" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          where: event.occurred_at == ^start_at,
          where: event.occurred_at != ^end_at,
          where: event.occurred_at in ^[start_at, end_at],
          where: not is_nil(event.occurred_at)
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "ignores negated half-open temporal interval comparisons" do
      end_at = end_at()

      query = from(event in Event, where: not (event.occurred_at <= ^end_at))

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "passes when half-open boundaries use dynamic expressions" do
      start_at = start_at()
      end_at = end_at()

      predicate =
        dynamic([event], event.occurred_at >= ^start_at and event.occurred_at < ^end_at)

      query = from(event in Event, where: ^predicate)

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "passes when half-open boundaries use field/2 and a named root binding" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          as: :event,
          where: field(as(:event), :occurred_at) >= ^start_at,
          where: field(as(:event), :occurred_at) < ^end_at
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "returns an issue when an upper boundary is inclusive" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          where: event.occurred_at >= ^start_at,
          where: event.occurred_at <= ^end_at
        )

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.check == HalfOpenTemporalIntervals

      assert issue.message ==
               "expected half-open temporal interval predicates on :occurred_at to use >= for starts and < for ends"

      assert issue.meta.operation == :all
      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "returns an issue when a lower boundary is exclusive" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          where: event.occurred_at > ^start_at,
          where: event.occurred_at < ^end_at
        )

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :lower, operator: :>, expected_operator: :>=}
             ]
    end

    test "returns an issue when invalid boundaries use dynamic expressions" do
      end_at = end_at()
      predicate = dynamic([event], event.occurred_at <= ^end_at)
      query = from(event in Event, where: ^predicate)

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "returns an issue when invalid boundaries use field/2" do
      end_at = end_at()
      query = from(event in Event, where: field(event, :occurred_at) <= ^end_at)

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "normalizes invalid boundaries when the field is on the right" do
      start_at = start_at()
      end_at = end_at()

      query =
        from(event in Event,
          where: ^start_at < event.occurred_at,
          where: ^end_at >= event.occurred_at
        )

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.violations == [
               %{boundary: :lower, operator: :>, expected_operator: :>=},
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "returns an issue for every Ecto prepare_query operation when a boundary is not half-open" do
      end_at = end_at()
      query = from(event in Event, where: event.occurred_at <= ^end_at)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} =
                 HalfOpenTemporalIntervals.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.field == :occurred_at
      end)
    end

    test "returns an issue when an invalid boundary appears in an or_where predicate" do
      end_at = end_at()

      query =
        from(event in Event,
          where: event.title == ^"public",
          or_where: event.occurred_at <= ^end_at
        )

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "returns an issue when an invalid boundary appears inside an or expression" do
      end_at = end_at()

      query =
        from(event in Event,
          where: event.title == ^"public" or event.occurred_at <= ^end_at
        )

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.field == :occurred_at
    end

    test "returns one issue per field with invalid boundaries" do
      start_at = start_at()

      query =
        from(event in Event,
          where: event.event_date <= ^Date.new!(2026, 2, 1),
          where: event.occurred_at > ^start_at
        )

      assert {:error, [%Issue{} = date_issue, %Issue{} = timestamp_issue]} =
               HalfOpenTemporalIntervals.validate(:all, query, [])

      assert date_issue.meta.field == :event_date
      assert timestamp_issue.meta.field == :occurred_at
    end

    test "infers all supported date/time schema field types" do
      query =
        from(event in Event,
          where: event.event_date <= ^Date.new!(2026, 2, 1),
          where: event.starts_at <= ^~T[09:00:00],
          where: event.ends_at <= ^~T[17:00:00.000000],
          where: event.scheduled_at <= ^~N[2026-02-01 00:00:00],
          where: event.occurred_at <= ^end_at(),
          where: event.archived_at <= ^end_at(),
          where: event.published_at <= ^~N[2026-02-01 00:00:00.000000]
        )

      assert {:error, issues} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert Enum.map(issues, & &1.meta.field) == [
               :archived_at,
               :ends_at,
               :event_date,
               :occurred_at,
               :published_at,
               :scheduled_at,
               :starts_at
             ]
    end

    test "ignores non-date/time schema fields when fields are inferred" do
      query = from(event in Event, where: event.title <= ^"z")

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "validates configured fields even when the schema type is not date/time" do
      query = from(event in StringEvent, where: event.occurred_at <= ^"2026-02-01")

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])

      assert issue.meta.field == :occurred_at
    end

    test "deduplicates configured fields" do
      end_at = end_at()
      query = from(event in Event, where: event.occurred_at <= ^end_at)

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query,
                 fields: [:occurred_at, :occurred_at]
               )

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "validates only explicitly configured fields when fields are configured" do
      end_at = end_at()

      query =
        from(event in Event,
          where: event.event_date <= ^Date.new!(2026, 2, 1),
          where: event.occurred_at < ^end_at
        )

      assert :ok =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])
    end

    test "validates configured fields on schema-less sources" do
      end_at = end_at()
      query = from(event in "events", where: field(event, :occurred_at) <= ^end_at)

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])

      assert issue.meta.field == :occurred_at
    end

    test "matches configured fields referenced with binary field names" do
      end_at = end_at()
      query = from(event in "events", where: field(event, "occurred_at") <= ^end_at)

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "validates configured fields on named schema-less root bindings" do
      end_at = end_at()

      query =
        from(event in "events",
          as: :event,
          where: field(as(:event), :occurred_at) <= ^end_at
        )

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])

      assert issue.meta.field == :occurred_at
    end

    test "validates half-open temporal intervals from named root bindings" do
      end_at = end_at()

      query =
        from(event in Event,
          as: :event,
          where: as(:event).occurred_at <= ^end_at
        )

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.field == :occurred_at
    end

    test "passes schema-less sources without configured fields" do
      end_at = end_at()
      query = from(event in "events", where: field(event, :occurred_at) <= ^end_at)

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok =
               HalfOpenTemporalIntervals.validate(:stream, :not_a_query, fields: [:occurred_at])
    end

    test "ignores configured fields that do not exist on the root schema" do
      query = from(event in GlobalEvent, where: event.title <= ^"z")

      assert :ok =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])
    end

    test "does not accept half-open temporal intervals from non-root bindings" do
      end_at = end_at()

      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: calendar.occurred_at <= ^end_at
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "validates root half-open temporal intervals when joins are present" do
      end_at = end_at()

      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: event.occurred_at <= ^end_at
        )

      assert {:error, %Issue{} = issue} = HalfOpenTemporalIntervals.validate(:all, query, [])

      assert issue.meta.field == :occurred_at
    end

    test "does not accept half-open temporal intervals from named non-root bindings" do
      end_at = end_at()

      query =
        from(event in Event,
          as: :event,
          join: calendar in Calendar,
          as: :calendar,
          on: true,
          where: as(:calendar).occurred_at <= ^end_at
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "ignores date/time comparisons to joined fields" do
      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: event.occurred_at <= calendar.occurred_at
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "ignores date/time field-to-field comparisons" do
      query = from(event in Event, where: event.occurred_at <= event.published_at)

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "ignores invalid half-open temporal intervals hidden inside fragments" do
      end_at = end_at()
      query = from(event in Event, where: fragment("? <= ?", event.occurred_at, ^end_at))

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "ignores invalid half-open temporal intervals hidden inside exists subqueries" do
      end_at = end_at()

      query =
        from(event in Event,
          where:
            exists(
              from(other_event in Event,
                where: other_event.occurred_at <= ^end_at
              )
            )
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "detects invalid boundaries in supported raw query maps" do
      query =
        query_with_expr({:<=, [], [root_field(:occurred_at), pinned_param(0)]})

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "detects invalid field/2 boundaries in supported raw query maps" do
      query =
        query_with_expr({:>, [], [root_field_call(:occurred_at), pinned_param(0)]})

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :lower, operator: :>, expected_operator: :>=}
             ]
    end

    test "detects invalid boundaries when configured fields are wrapped in type/2" do
      end_at = end_at()

      query =
        from(event in "events",
          where: type(field(event, :occurred_at), :utc_datetime) <= ^end_at
        )

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])

      assert issue.meta.field == :occurred_at

      assert issue.meta.violations == [
               %{boundary: :upper, operator: :<=, expected_operator: :<}
             ]
    end

    test "ignores field-to-field comparisons when the other field uses a string name" do
      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: event.occurred_at <= field(calendar, "occurred_at")
        )

      assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
    end

    test "ignores malformed raw where entries" do
      query = %{aliases: %{}, wheres: [%{op: :and}]}

      assert :ok =
               HalfOpenTemporalIntervals.validate(:all, query, fields: [:occurred_at])
    end

    test "respects the explicit query-level escape hatch" do
      end_at = end_at()
      query = from(event in Event, where: event.occurred_at <= ^end_at)

      assert :ok =
               HalfOpenTemporalIntervals.validate(:all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      end_at = end_at()
      query = from(event in Event, where: event.occurred_at <= ^end_at)

      assert {:error, %Issue{} = issue} =
               HalfOpenTemporalIntervals.validate(:all, query,
                 fields: [:occurred_at],
                 validate: true
               )

      assert issue.meta.field == :occurred_at
    end

    test "requires an explicit false escape hatch" do
      end_at = end_at()
      query = from(event in Event, where: event.occurred_at <= ^end_at)

      assert {:error, %Issue{}} =
               HalfOpenTemporalIntervals.validate(:all, query,
                 fields: [:occurred_at],
                 validate: nil
               )
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        HalfOpenTemporalIntervals.validate(:all, query, :invalid)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        HalfOpenTemporalIntervals.validate(:all, query, [:invalid])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :invalid",
                   fn ->
                     HalfOpenTemporalIntervals.validate(:all, query, :invalid)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [:invalid]",
                   fn ->
                     HalfOpenTemporalIntervals.validate(:all, query, [:invalid])
                   end
    end

    test "raises when a check option is unknown" do
      query = from(event in Event)

      assert_raise ArgumentError, "unknown option: :unknown", fn ->
        HalfOpenTemporalIntervals.validate(:all, query, unknown: true)
      end
    end

    test "raises when fields are empty" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: []",
                   fn ->
                     HalfOpenTemporalIntervals.validate(:all, query, fields: [])
                   end
    end

    test "raises when fields are not a list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: :occurred_at",
                   fn ->
                     HalfOpenTemporalIntervals.validate(:all, query, fields: :occurred_at)
                   end
    end

    test "raises when fields contain non-atoms" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   ~s(expected :fields to contain only atoms, got: "occurred_at"),
                   fn ->
                     HalfOpenTemporalIntervals.validate(:all, query,
                       fields: [:occurred_at, "occurred_at"]
                     )
                   end
    end
  end

  defp query_with_expr(expr) do
    %{aliases: %{}, wheres: [%{expr: expr, op: :and, params: []}]}
  end

  defp root_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}
  defp root_field_call(field), do: {:field, [], [{:&, [], [0]}, field]}
  defp pinned_param(index), do: {:^, [], [index]}

  defp start_at, do: ~U[2026-01-01 00:00:00Z]
  defp end_at, do: ~U[2026-02-01 00:00:00Z]
end
