defmodule Bylaw.Ecto.Query.Checks.UtcDatetimeNaiveComparisonsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.UtcDatetimeNaiveComparisons
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Event do
    use Ecto.Schema

    schema "events" do
      field(:archived_at, :utc_datetime_usec)
      field(:inserted_at, :utc_datetime)
      field(:scheduled_at, :naive_datetime)
      field(:title, :string)
    end
  end

  defmodule StringEvent do
    use Ecto.Schema

    schema "string_events" do
      field(:inserted_at, :string)
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
      field(:inserted_at, :utc_datetime)
    end
  end

  describe "validate/3" do
    test "passes when there are no where predicates" do
      query = from(event in Event)

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "returns an issue when a utc datetime field is compared to a pinned naive datetime" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: event.inserted_at >= ^naive_datetime)

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.check == UtcDatetimeNaiveComparisons

      assert issue.message ==
               "expected UTC datetime field :inserted_at to be compared with DateTime values, got NaiveDateTime"

      assert issue.meta.operation == :all
      assert issue.meta.field == :inserted_at

      assert issue.meta.violations == [
               %{operator: :>=, value_type: :naive_datetime, value_source: :parameter}
             ]
    end

    test "returns an issue when a utc datetime usec field is compared to a pinned naive datetime" do
      query = from(event in Event, where: event.archived_at < ^~N[2026-01-01 00:00:00.000000])

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.field == :archived_at

      assert issue.meta.violations == [
               %{operator: :<, value_type: :naive_datetime, value_source: :parameter}
             ]
    end

    test "normalizes comparisons when the utc datetime field is on the right" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: ^naive_datetime <= event.inserted_at)

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.field == :inserted_at

      assert issue.meta.violations == [
               %{operator: :>=, value_type: :naive_datetime, value_source: :parameter}
             ]
    end

    test "returns an issue when a utc datetime field is compared to typed naive datetime params" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          where: event.inserted_at >= type(^naive_datetime, :naive_datetime)
        )

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.violations == [
               %{operator: :>=, value_type: :naive_datetime, value_source: :parameter}
             ]
    end

    test "returns an issue when a utc datetime field uses a naive datetime in predicate" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: event.inserted_at in ^[naive_datetime])

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.field == :inserted_at

      assert issue.meta.violations == [
               %{operator: :in, value_type: :naive_datetime, value_source: :parameter}
             ]
    end

    test "returns an issue when an in predicate contains a pinned naive datetime element" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: event.inserted_at in [^naive_datetime])

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.violations == [
               %{operator: :in, value_type: :naive_datetime, value_source: :parameter}
             ]
    end

    test "passes when a utc datetime field is compared to DateTime values" do
      start_at = start_at()

      query =
        from(event in Event,
          where: event.inserted_at >= ^start_at,
          where: event.inserted_at in ^[start_at]
        )

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "ignores naive datetime values compared to non-utc fields" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          where: event.scheduled_at >= ^naive_datetime,
          where: event.title == ^"published"
        )

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "returns an issue for every Ecto prepare_query operation" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: event.inserted_at >= ^naive_datetime)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} =
                 UtcDatetimeNaiveComparisons.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.field == :inserted_at
      end)
    end

    test "returns an issue when a comparison uses a dynamic expression" do
      naive_datetime = naive_datetime()
      predicate = dynamic([event], event.inserted_at >= ^naive_datetime)
      query = from(event in Event, where: ^predicate)

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.field == :inserted_at
    end

    test "returns an issue when comparisons use field/2 and a named root binding" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          as: :event,
          where: field(as(:event), :inserted_at) >= ^naive_datetime
        )

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.field == :inserted_at
    end

    test "returns one issue per utc datetime field" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          where: event.archived_at >= ^naive_datetime,
          where: event.inserted_at >= ^naive_datetime
        )

      assert {:error, [%Issue{} = archived_issue, %Issue{} = inserted_issue]} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert archived_issue.meta.field == :archived_at
      assert inserted_issue.meta.field == :inserted_at
    end

    test "detects direct naive datetime literals in supported raw query maps" do
      query = query_with_expr({:>=, [], [root_field(:inserted_at), naive_datetime()]})

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )

      assert issue.meta.violations == [
               %{operator: :>=, value_type: :naive_datetime, value_source: :literal}
             ]
    end

    test "detects tagged naive datetime values in supported raw query maps" do
      tagged = %Ecto.Query.Tagged{value: naive_datetime(), type: :naive_datetime}
      query = query_with_expr({:>=, [], [root_field(:inserted_at), tagged]})

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )

      assert issue.meta.violations == [
               %{operator: :>=, value_type: :naive_datetime, value_source: :tagged}
             ]
    end

    test "detects configured fields wrapped in type/2 on schema-less sources" do
      naive_datetime = naive_datetime()

      query =
        from(event in "events",
          where: type(field(event, :inserted_at), :utc_datetime) >= ^naive_datetime
        )

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )

      assert issue.meta.field == :inserted_at
    end

    test "matches configured fields referenced with binary field names" do
      naive_datetime = naive_datetime()
      query = from(event in "events", where: field(event, "inserted_at") >= ^naive_datetime)

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )

      assert issue.meta.field == :inserted_at

      assert issue.meta.violations == [
               %{operator: :>=, value_type: :naive_datetime, value_source: :parameter}
             ]
    end

    test "validates only explicitly configured fields when fields are configured" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          where: event.archived_at >= ^naive_datetime,
          where: event.inserted_at >= ^naive_datetime
        )

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )

      assert issue.meta.field == :inserted_at
    end

    test "validates configured fields even when the schema type is not utc datetime" do
      naive_datetime = naive_datetime()
      query = from(event in StringEvent, where: event.inserted_at >= ^naive_datetime)

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )

      assert issue.meta.field == :inserted_at
    end

    test "ignores configured fields that do not exist on the root schema" do
      query = from(event in GlobalEvent, where: event.title >= ^"a")

      assert :ok =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )
    end

    test "passes schema-less sources without configured fields" do
      naive_datetime = naive_datetime()
      query = from(event in "events", where: field(event, :inserted_at) >= ^naive_datetime)

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok =
               UtcDatetimeNaiveComparisons.validate(:stream, :not_a_query,
                 utc_datetime_naive_comparisons: [fields: [:inserted_at]]
               )
    end

    test "does not accept utc datetime comparisons from non-root bindings" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: calendar.inserted_at >= ^naive_datetime
        )

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "validates root utc datetime comparisons when joins are present" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: event.inserted_at >= ^naive_datetime
        )

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query, [])

      assert issue.meta.field == :inserted_at
    end

    test "does not accept utc datetime comparisons from named non-root bindings" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          as: :event,
          join: calendar in Calendar,
          as: :calendar,
          on: true,
          where: as(:calendar).inserted_at >= ^naive_datetime
        )

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "ignores utc datetime field-to-field comparisons" do
      query =
        from(event in Event,
          join: calendar in Calendar,
          on: true,
          where: event.inserted_at >= calendar.inserted_at
        )

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "ignores utc datetime comparisons hidden inside fragments" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: fragment("? >= ?", event.inserted_at, ^naive_datetime))

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "ignores utc datetime comparisons hidden inside exists subqueries" do
      naive_datetime = naive_datetime()

      query =
        from(event in Event,
          where:
            exists(
              from(other_event in Event,
                where: other_event.inserted_at >= ^naive_datetime
              )
            )
        )

      assert :ok = UtcDatetimeNaiveComparisons.validate(:all, query, [])
    end

    test "respects the explicit query-level escape hatch" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: event.inserted_at >= ^naive_datetime)

      assert :ok =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [validate: false]
               )
    end

    test "validates when validate is explicitly true" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: event.inserted_at >= ^naive_datetime)

      assert {:error, %Issue{} = issue} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [
                   fields: [:inserted_at],
                   validate: true
                 ]
               )

      assert issue.meta.field == :inserted_at
    end

    test "requires an explicit false escape hatch" do
      naive_datetime = naive_datetime()
      query = from(event in Event, where: event.inserted_at >= ^naive_datetime)

      assert {:error, %Issue{}} =
               UtcDatetimeNaiveComparisons.validate(:all, query,
                 utc_datetime_naive_comparisons: [
                   fields: [:inserted_at],
                   validate: nil
                 ]
               )
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        UtcDatetimeNaiveComparisons.validate(:all, query, :invalid)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        UtcDatetimeNaiveComparisons.validate(:all, query, [:invalid])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :utc_datetime_naive_comparisons opts to be a keyword list, got: :invalid",
                   fn ->
                     UtcDatetimeNaiveComparisons.validate(:all, query,
                       utc_datetime_naive_comparisons: :invalid
                     )
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :utc_datetime_naive_comparisons opts to be a keyword list, got: [:invalid]",
                   fn ->
                     UtcDatetimeNaiveComparisons.validate(:all, query,
                       utc_datetime_naive_comparisons: [:invalid]
                     )
                   end
    end

    test "raises when a check option is unknown" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "unknown :utc_datetime_naive_comparisons option: :unknown",
                   fn ->
                     UtcDatetimeNaiveComparisons.validate(:all, query,
                       utc_datetime_naive_comparisons: [unknown: true]
                     )
                   end
    end

    test "raises when fields are empty" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: []",
                   fn ->
                     UtcDatetimeNaiveComparisons.validate(:all, query,
                       utc_datetime_naive_comparisons: [fields: []]
                     )
                   end
    end

    test "raises when fields are not a list" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: :inserted_at",
                   fn ->
                     UtcDatetimeNaiveComparisons.validate(:all, query,
                       utc_datetime_naive_comparisons: [fields: :inserted_at]
                     )
                   end
    end

    test "raises when fields contain non-atoms" do
      query = from(event in Event)

      assert_raise ArgumentError,
                   ~s(expected :fields to contain only atoms, got: "inserted_at"),
                   fn ->
                     UtcDatetimeNaiveComparisons.validate(:all, query,
                       utc_datetime_naive_comparisons: [fields: [:inserted_at, "inserted_at"]]
                     )
                   end
    end
  end

  defp query_with_expr(expr) do
    %{aliases: %{}, wheres: [%{expr: expr, op: :and, params: []}]}
  end

  defp root_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}

  defp naive_datetime, do: ~N[2026-01-01 00:00:00]
  defp start_at, do: ~U[2026-01-01 00:00:00Z]
end
