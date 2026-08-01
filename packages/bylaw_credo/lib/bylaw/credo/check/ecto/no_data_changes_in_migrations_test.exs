defmodule Bylaw.Credo.Check.Ecto.NoDataChangesInMigrationsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.NoDataChangesInMigrations

  test "reports direct Repo row mutations in migration files" do
    """
    defmodule Example.Repo.Migrations.ChangeAccounts do
      use Ecto.Migration

      def up do
        Repo.insert(%Account{})
        Repo.insert!(%Account{})
        Repo.insert_all(Account, [%{status: :active}])
        Repo.insert_or_update(%Ecto.Changeset{})
        Repo.insert_or_update!(%Ecto.Changeset{})
        MyApp.Repo.update(%Ecto.Changeset{})
        MyApp.Repo.update!(%Ecto.Changeset{})
        MyApp.Repo.update_all(Account, set: [status: :active])
        Repo.delete(%Account{})
        Repo.delete!(%Account{})
        Repo.delete_all(Account)
      end
    end
    """
    |> to_source_file(migration_filename())
    |> run_check(NoDataChangesInMigrations)
    |> assert_issues(11)
    |> assert_issues_match([
      %{line_no: 5, trigger: "Repo.insert"},
      %{line_no: 6, trigger: "Repo.insert!"},
      %{line_no: 7, trigger: "Repo.insert_all"},
      %{line_no: 8, trigger: "Repo.insert_or_update"},
      %{line_no: 9, trigger: "Repo.insert_or_update!"},
      %{line_no: 10, trigger: "MyApp.Repo.update"},
      %{line_no: 11, trigger: "MyApp.Repo.update!"},
      %{line_no: 12, trigger: "MyApp.Repo.update_all"},
      %{line_no: 13, trigger: "Repo.delete"},
      %{line_no: 14, trigger: "Repo.delete!"},
      %{line_no: 15, trigger: "Repo.delete_all"}
    ])
  end

  test "reports literal SQL row mutations in migration files" do
    """
    defmodule Example.Repo.Migrations.BackfillAccounts do
      use Ecto.Migration

      def up do
        execute("INSERT INTO accounts (status) VALUES ('active')")
        execute("  update accounts SET status = 'active'")
        execute("\nDELETE FROM accounts WHERE status = 'closed'", "SELECT 1")
        execute("MERGE INTO accounts USING imported_accounts ON accounts.id = imported_accounts.id")
      end
    end
    """
    |> to_source_file(migration_filename())
    |> run_check(NoDataChangesInMigrations)
    |> assert_issues(4)
    |> assert_issues_match([
      %{line_no: 5, trigger: "INSERT"},
      %{line_no: 6, trigger: "UPDATE"},
      %{line_no: 7, trigger: "DELETE"},
      %{line_no: 9, trigger: "MERGE"}
    ])
  end

  test "reports a realistic batched backfill embedded in a migration" do
    """
    defmodule MyApp.Repo.Migrations.BackfillMissingOrganisationIds do
      use Ecto.Migration

      def up do
        query = from invoice in "invoices", where: is_nil(invoice.organisation_id)

        query
        |> limit(500)
        |> MyApp.Repo.update_all(set: [organisation_id: "org_01JQX8K9N7"])
      end
    end
    """
    |> to_source_file("apps/my_app/priv/repo/migrations/20260801120000_backfill_org_ids.exs")
    |> run_check(NoDataChangesInMigrations)
    |> assert_issue(%{
      line_no: 9,
      trigger: "MyApp.Repo.update_all",
      message: ~r/data-migration script or explicit release task/
    })
  end

  test "does not report schema DDL in migration files" do
    """
    defmodule Example.Repo.Migrations.AddAccounts do
      use Ecto.Migration

      def change do
        create table(:accounts) do
          add :status, :string
        end

        create index(:accounts, [:status])
        execute("CREATE INDEX CONCURRENTLY accounts_status_idx ON accounts (status)")
        execute("ALTER TABLE accounts VALIDATE CONSTRAINT accounts_status_check", "")
        execute("DROP INDEX CONCURRENTLY accounts_status_idx")
      end
    end
    """
    |> to_source_file(migration_filename())
    |> run_check(NoDataChangesInMigrations)
    |> refute_issues()
  end

  test "does not report dynamic SQL that cannot be classified confidently" do
    """
    defmodule Example.Repo.Migrations.RunStatement do
      use Ecto.Migration

      def up do
        execute(statement())
        execute("UPDATE " <> table_name() <> " SET active = true")
        run_backfill()
      end
    end
    """
    |> to_source_file(migration_filename())
    |> run_check(NoDataChangesInMigrations)
    |> refute_issues()
  end

  test "does not inspect files outside migration directories" do
    """
    defmodule Example.Accounts do
      def deactivate_all do
        Repo.update_all(Account, set: [active: false])
        execute("DELETE FROM expired_sessions")
      end
    end
    """
    |> to_source_file("lib/example/accounts.ex")
    |> run_check(NoDataChangesInMigrations)
    |> refute_issues()
  end

  defp migration_filename do
    "priv/repo/migrations/20260801120000_change_accounts.exs"
  end
end
