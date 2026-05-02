defmodule Bylaw.Ecto.Query.Checks.DateDatetimeMixedComparisonsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.DateDatetimeMixedComparisons
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Event do
    use Ecto.Schema

    schema "events" do
      field(:event_date, :date)
      field(:published_on, :date)
      field(:inserted_at, :utc_datetime)
      field(:archived_at, :utc_datetime_usec)
      field(:scheduled_at, :naive_datetime)
      field(:reviewed_at, :naive_datetime_usec)
      field(:title, :string)

      has_many(:calendars, Bylaw.Ecto.Query.Checks.DateDatetimeMixedComparisonsTest.Calendar,
        foreign_key: :event_id
      )
    end
  end

  defmodule Calendar do
    use Ecto.Schema

    schema "calendars" do
      field(:event_id, :integer)
      field(:calendar_date, :date)
      field(:starts_at, :naive_datetime)
      field(:ends_at, :utc_datetime)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:event_id, :integer)
      field(:published_on, :date)
    end
  end

  describe "validate/3" do
    test "passes when there are no where predicates" do
      query = from(event in Event)

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "returns an issue when a date field is compared to a utc datetime field" do
      query = from(event in Event, where: event.event_date <= event.inserted_at)

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.check == DateDatetimeMixedComparisons

      assert issue.message ==
               "expected date field :event_date to compare with datetime fields only after explicit date truncation"

      assert issue.meta.operation == :all
      assert issue.meta.date_schema == Event
      assert issue.meta.date_binding_index == 0
      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :<=,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :inserted_at,
                 datetime_type: :utc_datetime
               }
             ]
    end

    test "returns an issue when a date field is compared to a naive datetime field" do
      query = from(event in Event, where: event.event_date > event.scheduled_at)

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.violations == [
               %{
                 operator: :>,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :scheduled_at,
                 datetime_type: :naive_datetime
               }
             ]
    end

    test "returns an issue for usec datetime fields" do
      query =
        from(event in Event,
          where: event.event_date == event.archived_at,
          where: event.published_on == event.reviewed_at
        )

      assert {:error, [%Issue{} = event_date_issue, %Issue{} = published_on_issue]} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert event_date_issue.meta.date_field == :event_date

      assert event_date_issue.meta.violations == [
               %{
                 operator: :==,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :archived_at,
                 datetime_type: :utc_datetime_usec
               }
             ]

      assert published_on_issue.meta.date_field == :published_on

      assert published_on_issue.meta.violations == [
               %{
                 operator: :==,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :reviewed_at,
                 datetime_type: :naive_datetime_usec
               }
             ]
    end

    test "normalizes comparisons when the date field is on the right" do
      query = from(event in Event, where: event.inserted_at > event.event_date)

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :<,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :inserted_at,
                 datetime_type: :utc_datetime
               }
             ]
    end

    test "returns an issue for every Ecto prepare_query operation" do
      query = from(event in Event, where: event.event_date <= event.inserted_at)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} =
                 DateDatetimeMixedComparisons.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.date_field == :event_date
      end)
    end

    test "detects comparisons inside dynamic expressions" do
      predicate = dynamic([event], event.event_date <= event.inserted_at)
      query = from(event in Event, where: ^predicate)

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date
    end

    test "detects comparisons that use field/2 and named bindings" do
      query =
        from(event in Event,
          as: :event,
          where: field(as(:event), :event_date) <= field(as(:event), :inserted_at)
        )

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date
    end

    test "detects comparisons inside or predicates" do
      query =
        from(event in Event,
          where: event.title == ^"draft",
          or_where: event.event_date != event.inserted_at
        )

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :!=,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :inserted_at,
                 datetime_type: :utc_datetime
               }
             ]
    end

    test "detects comparisons inside negated predicates" do
      query = from(event in Event, where: not (event.event_date < event.inserted_at))

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :<,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :inserted_at,
                 datetime_type: :utc_datetime
               }
             ]
    end

    test "detects comparisons across direct explicit joins" do
      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: event.event_date <= calendar.starts_at,
          where: calendar.calendar_date >= event.inserted_at
        )

      assert {:error, [%Issue{} = event_issue, %Issue{} = calendar_issue]} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert event_issue.meta.date_schema == Event
      assert event_issue.meta.date_binding_index == 0
      assert event_issue.meta.date_field == :event_date

      assert event_issue.meta.violations == [
               %{
                 operator: :<=,
                 datetime_schema: Calendar,
                 datetime_binding_index: 1,
                 datetime_field: :starts_at,
                 datetime_type: :naive_datetime
               }
             ]

      assert calendar_issue.meta.date_schema == Calendar
      assert calendar_issue.meta.date_binding_index == 1
      assert calendar_issue.meta.date_field == :calendar_date

      assert calendar_issue.meta.violations == [
               %{
                 operator: :>=,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :inserted_at,
                 datetime_type: :utc_datetime
               }
             ]
    end

    test "detects comparisons across association joins" do
      query =
        from(event in Event,
          join: calendar in assoc(event, :calendars),
          where: event.event_date <= calendar.starts_at
        )

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_schema == Event
      assert issue.meta.date_binding_index == 0
      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :<=,
                 datetime_schema: Calendar,
                 datetime_binding_index: 1,
                 datetime_field: :starts_at,
                 datetime_type: :naive_datetime
               }
             ]
    end

    test "detects comparisons in direct explicit join predicates" do
      query =
        from(event in Event,
          join: calendar in Calendar,
          on: event.event_date <= calendar.starts_at
        )

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_schema == Event
      assert issue.meta.date_binding_index == 0
      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :<=,
                 datetime_schema: Calendar,
                 datetime_binding_index: 1,
                 datetime_field: :starts_at,
                 datetime_type: :naive_datetime
               }
             ]
    end

    test "detects comparisons in having predicates" do
      query =
        from(event in Event,
          group_by: event.id,
          having: event.event_date <= event.inserted_at
        )

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date
    end

    test "detects comparisons in set operation branches" do
      safe_query = from(event in Event, where: event.event_date == ^Date.new!(2026, 1, 1))
      unsafe_query = from(event in Event, where: event.event_date <= event.inserted_at)
      query = union_all(safe_query, ^unsafe_query)

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date

      assert issue.meta.combination_path == [
               %{operation: :union_all, index: 0}
             ]
    end

    test "detects comparisons that use named join bindings" do
      query =
        from(event in Event,
          as: :event,
          join: calendar in Calendar,
          as: :calendar,
          on: true,
          where: as(:calendar).calendar_date >= as(:event).inserted_at
        )

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_schema == Calendar
      assert issue.meta.date_binding_index == 1
      assert issue.meta.date_field == :calendar_date
    end

    test "passes when the datetime field is explicitly truncated to date" do
      query =
        from(event in Event,
          where: event.event_date == type(event.inserted_at, :date),
          where: event.published_on == type(event.scheduled_at, :date),
          where: type(event.archived_at, :date) >= event.event_date
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "returns an issue when a date field is explicitly cast to datetime" do
      query =
        from(event in Event, where: type(event.event_date, :utc_datetime) <= event.inserted_at)

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date
    end

    test "returns an issue when a date field on the right is explicitly cast to datetime" do
      query =
        from(event in Event, where: event.inserted_at >= type(event.event_date, :utc_datetime))

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :<=,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :inserted_at,
                 datetime_type: :utc_datetime
               }
             ]
    end

    test "passes when date fields are compared to date fields" do
      query =
        from(event in Event,
          join: comment in Comment,
          on: comment.event_id == event.id,
          where: event.event_date == event.published_on,
          where: event.event_date == comment.published_on
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "passes when datetime fields are compared to datetime fields" do
      query =
        from(event in Event,
          where: event.inserted_at <= event.archived_at,
          where: event.scheduled_at <= event.reviewed_at
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "passes when temporal fields are compared to non-temporal fields" do
      query =
        from(event in Event,
          where: event.event_date == event.title,
          where: event.inserted_at == event.title
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "passes when date fields are compared to values" do
      event_date = Date.new!(2026, 1, 1)

      query =
        from(event in Event,
          where: event.event_date >= ^event_date,
          where: event.event_date <= ^DateTime.new!(event_date, ~T[00:00:00], "Etc/UTC")
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "ignores datetime comparisons hidden inside fragments" do
      query =
        from(event in Event,
          where: event.event_date == fragment("date(?)", event.inserted_at)
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "ignores datetime comparisons hidden inside exists subqueries" do
      query =
        from(event in Event,
          where:
            exists(
              from(other_event in Event,
                where: other_event.event_date == other_event.inserted_at
              )
            )
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "passes schema-less sources" do
      query =
        from(event in "events",
          where: field(event, :event_date) <= field(event, :inserted_at)
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "passes schema-less joins" do
      query =
        from(event in Event,
          join: calendar in "calendars",
          on: true,
          where: event.event_date <= field(calendar, :starts_at)
        )

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "detects comparisons in supported raw query maps" do
      query =
        query_with_expr({:<=, [], [field_expr(0, :event_date), field_expr(0, :inserted_at)]})

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_schema == Event
      assert issue.meta.date_binding_index == 0
      assert issue.meta.date_field == :event_date

      assert issue.meta.violations == [
               %{
                 operator: :<=,
                 datetime_schema: Event,
                 datetime_binding_index: 0,
                 datetime_field: :inserted_at,
                 datetime_type: :utc_datetime
               }
             ]
    end

    test "detects join comparisons in supported raw query maps" do
      query =
        query_with_expr(
          {:<=, [], [field_expr(0, :event_date), field_expr(1, :starts_at)]},
          joins: [%{source: {"calendars", Calendar}, on: %{expr: true}}]
        )

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query, [])

      assert issue.meta.date_schema == Event
      assert issue.meta.date_binding_index == 0

      assert issue.meta.violations == [
               %{
                 operator: :<=,
                 datetime_schema: Calendar,
                 datetime_binding_index: 1,
                 datetime_field: :starts_at,
                 datetime_type: :naive_datetime
               }
             ]
    end

    test "ignores malformed raw query predicate entries" do
      query = query_with_expr(:not_a_comparison)

      query =
        Map.merge(query, %{
          havings: [:malformed],
          joins: [:malformed]
        })

      assert :ok = DateDatetimeMixedComparisons.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = DateDatetimeMixedComparisons.validate(:stream, :not_a_query, [])
    end

    test "respects the explicit query-level escape hatch" do
      query = from(event in Event, where: event.event_date <= event.inserted_at)

      assert :ok =
               DateDatetimeMixedComparisons.validate(:all, query,
                 date_datetime_mixed_comparisons: [validate: false]
               )
    end

    test "validates when validate is explicitly true" do
      query = from(event in Event, where: event.event_date <= event.inserted_at)

      assert {:error, %Issue{} = issue} =
               DateDatetimeMixedComparisons.validate(:all, query,
                 date_datetime_mixed_comparisons: [validate: true]
               )

      assert issue.meta.date_field == :event_date
    end

    test "requires an explicit false escape hatch" do
      query = from(event in Event, where: event.event_date <= event.inserted_at)

      assert {:error, %Issue{}} =
               DateDatetimeMixedComparisons.validate(:all, query,
                 date_datetime_mixed_comparisons: [validate: nil]
               )
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        DateDatetimeMixedComparisons.validate(:all, query, :invalid)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        DateDatetimeMixedComparisons.validate(:all, query, [:invalid])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :date_datetime_mixed_comparisons opts to be a keyword list, got: :invalid",
                   fn ->
                     DateDatetimeMixedComparisons.validate(:all, query,
                       date_datetime_mixed_comparisons: :invalid
                     )
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :date_datetime_mixed_comparisons opts to be a keyword list, got: [:invalid]",
                   fn ->
                     DateDatetimeMixedComparisons.validate(:all, query,
                       date_datetime_mixed_comparisons: [:invalid]
                     )
                   end
    end

    test "raises when a check option is unknown" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "unknown :date_datetime_mixed_comparisons option: :unknown",
                   fn ->
                     DateDatetimeMixedComparisons.validate(:all, query,
                       date_datetime_mixed_comparisons: [unknown: true]
                     )
                   end
    end
  end

  defp query_with_expr(expr, attrs \\ []) do
    Map.merge(
      %{
        aliases: %{},
        from: %{source: {"events", Event}},
        joins: [],
        wheres: [%{expr: expr}]
      },
      Map.new(attrs)
    )
  end

  defp field_expr(binding_index, field),
    do: {{:., [], [{:&, [], [binding_index]}, field]}, [], []}
end
