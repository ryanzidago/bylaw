defmodule Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrationsPropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.Ecto.NoDataChangesInSchemaMigrations

  property "literal SQL mutations are detected regardless of casing and leading trivia" do
    check all(
            statement <- randomly_cased_member_of(["INSERT", "UPDATE", "DELETE", "MERGE"]),
            trivia <- leading_sql_trivia()
          ) do
      sql = trivia <> statement <> " generated_statement"

      sql
      |> execute_source()
      |> to_source_file(migration_filename())
      |> run_check(NoDataChangesInSchemaMigrations)
      |> assert_issue(%{trigger: String.upcase(statement)})
    end
  end

  property "literal schema DDL remains accepted regardless of casing and leading trivia" do
    check all(
            statement <- randomly_cased_member_of(["CREATE", "ALTER", "DROP"]),
            trivia <- leading_sql_trivia()
          ) do
      sql = trivia <> statement <> " generated_statement"

      sql
      |> execute_source()
      |> to_source_file(migration_filename())
      |> run_check(NoDataChangesInSchemaMigrations)
      |> refute_issues()
    end
  end

  property "every literal SQL argument to execute/2 is classified independently" do
    check all(
            up_statement <- randomly_cased_member_of(["INSERT", "UPDATE", "DELETE", "MERGE"]),
            down_statement <-
              randomly_cased_member_of(["INSERT", "UPDATE", "DELETE", "MERGE"])
          ) do
      source =
        "defmodule Migration do\n  def change, do: execute(#{inspect(up_statement)}, #{inspect(down_statement)})\nend"

      issues =
        source
        |> to_source_file(migration_filename())
        |> run_check(NoDataChangesInSchemaMigrations)

      assert Enum.count(issues) == 2

      triggers = Enum.map(issues, & &1.trigger)

      assert Enum.sort(triggers) ==
               Enum.sort([String.upcase(up_statement), String.upcase(down_statement)])
    end
  end

  property "Repo mutations are detected through arbitrary alias namespace depth" do
    check all(
            namespace <- list_of(module_segment(), max_length: 4),
            operation <-
              member_of([
                "insert",
                "insert!",
                "insert_all",
                "insert_or_update",
                "insert_or_update!",
                "update",
                "update!",
                "update_all",
                "delete",
                "delete!",
                "delete_all"
              ])
          ) do
      repo = Enum.join(namespace, ".")

      repo =
        if repo == "" do
          "Repo"
        else
          repo <> ".Repo"
        end

      source = "defmodule Migration do\n  def up, do: #{repo}.#{operation}(:value)\nend"

      source
      |> to_source_file(migration_filename())
      |> run_check(NoDataChangesInSchemaMigrations)
      |> assert_issue(%{trigger: "#{repo}.#{operation}"})
    end
  end

  defp random_case(statement) do
    statement
    |> String.graphemes()
    |> Enum.map(fn character ->
      member_of([String.downcase(character), String.upcase(character)])
    end)
    |> fixed_list()
    |> map(&Enum.join/1)
  end

  defp randomly_cased_member_of(statements) do
    statements
    |> member_of()
    |> bind(&random_case/1)
  end

  defp leading_sql_trivia do
    trivia = [" ", "\t", "\n", "\r", "-- generated comment\n", "/* generated comment */"]
    map(list_of(member_of(trivia), max_length: 12), &Enum.join/1)
  end

  defp module_segment do
    gen all(
          first <- member_of(Enum.to_list(?A..?Z)),
          rest <- list_of(member_of(Enum.to_list(?a..?z)), max_length: 10)
        ) do
      List.to_string([first | rest])
    end
  end

  defp execute_source(sql) do
    "defmodule Migration do\n  def up, do: execute(#{inspect(sql)})\nend"
  end

  defp migration_filename do
    "priv/repo/migrations/20260801120000_generated_migration.exs"
  end
end
