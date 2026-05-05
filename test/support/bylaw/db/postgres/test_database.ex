defmodule Bylaw.Db.Postgres.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :bylaw,
    adapter: Ecto.Adapters.Postgres
end

defmodule Bylaw.Db.Postgres.TestDatabase do
  @moduledoc false

  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox

  @schema "bylaw_fk_index_fixtures"
  @pg_schema "pgapp_fk_index_fixtures"
  @scoped_schema "bylaw_scoped_fk_fixtures"
  @timeout 15_000

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec pg_schema() :: String.t()
  def pg_schema, do: @pg_schema

  @spec scoped_schema() :: String.t()
  def scoped_schema, do: @scoped_schema

  @spec start_repo!() :: pid()
  def start_repo! do
    case TestRepo.start_link() do
      {:ok, pid} ->
        # credo:disable-for-next-line Bylaw.Credo.Check.NoLowLevelProcessPrimitives
        Process.unlink(pid)
        pid

      {:error, {:already_started, pid}} ->
        # credo:disable-for-next-line Bylaw.Credo.Check.NoLowLevelProcessPrimitives
        Process.unlink(pid)
        pid

      {:error, reason} ->
        raise """
        could not start Bylaw Postgres test repo: #{inspect(reason)}

        Run `mix test.postgres` to recreate the test database, or set
        BYLAW_POSTGRES_URL to a disposable Postgres test database.
        """
    end
  end

  @spec reset_fixtures!() :: :ok
  def reset_fixtures! do
    Sandbox.mode(TestRepo, :auto)

    query!("DROP SCHEMA IF EXISTS #{quote_identifier(@schema)} CASCADE")
    query!("DROP SCHEMA IF EXISTS #{quote_identifier(@pg_schema)} CASCADE")
    query!("DROP SCHEMA IF EXISTS #{quote_identifier(@scoped_schema)} CASCADE")

    create_fixture_schema!(@schema)
    create_pg_named_fixture_schema!(@pg_schema)
    create_scoped_fixture_schema!(@scoped_schema)

    Sandbox.mode(TestRepo, :manual)
  end

  @spec query!(sql :: String.t()) :: term()
  def query!(sql) do
    SQL.query!(TestRepo, sql, [], timeout: @timeout)
  end

  defp create_fixture_schema!(schema) do
    query!("CREATE SCHEMA #{quote_identifier(schema)}")
    create_users!(schema)
    create_orders_missing_index!(schema)
    create_indexed_orders!(schema)
    create_nullable_orders!(schema)
    create_partial_orders!(schema)
    create_ordered_orders!(schema)
    create_accounts!(schema)
    create_events!(schema)
    create_included_events!(schema)
    create_action_messages!(schema)
    create_duplicate_indexes!(schema)
    create_uuid_primary_key!(schema)
    create_bigint_primary_key!(schema)
    create_missing_primary_key!(schema)
    create_composite_uuid_primary_key!(schema)
    create_composite_mixed_primary_key!(schema)
  end

  defp create_pg_named_fixture_schema!(schema) do
    query!("CREATE SCHEMA #{quote_identifier(schema)}")
    create_users!(schema)
    create_orders_missing_index!(schema)
    create_nullable_orders!(schema)
    create_duplicate_indexes!(schema)
  end

  defp create_scoped_fixture_schema!(schema) do
    query!("CREATE SCHEMA #{quote_identifier(schema)}")
    create_scoped_customers!(schema)
    create_scoped_orders_missing_scope!(schema)
    create_scoped_orders_with_scope!(schema)
    create_global_statuses!(schema)
    create_scoped_orders_with_global_status!(schema)
    create_global_imports!(schema)
  end

  defp create_users!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "users")} (
      id bigint PRIMARY KEY
    )
    """)
  end

  defp create_orders_missing_index!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "orders")} (
      id bigint PRIMARY KEY,
      user_id bigint NOT NULL,
      account_id bigint NOT NULL,
      status text NOT NULL DEFAULT 'open',
      CONSTRAINT orders_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES #{table(schema, "users")} (id)
    )
    """)
  end

  defp create_indexed_orders!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "indexed_orders")} (
      id bigint PRIMARY KEY,
      user_id bigint NOT NULL,
      CONSTRAINT indexed_orders_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES #{table(schema, "users")} (id)
    )
    """)

    query!("""
    CREATE INDEX indexed_orders_user_id_idx
      ON #{table(schema, "indexed_orders")} (user_id)
    """)
  end

  defp create_nullable_orders!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "nullable_orders")} (
      id bigint PRIMARY KEY,
      user_id bigint,
      CONSTRAINT nullable_orders_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES #{table(schema, "users")} (id)
    )
    """)

    query!("""
    CREATE INDEX nullable_orders_user_id_idx
      ON #{table(schema, "nullable_orders")} (user_id)
    """)
  end

  defp create_partial_orders!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "partial_orders")} (
      id bigint PRIMARY KEY,
      user_id bigint NOT NULL,
      CONSTRAINT partial_orders_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES #{table(schema, "users")} (id)
    )
    """)

    query!("""
    CREATE INDEX partial_orders_user_id_partial_idx
      ON #{table(schema, "partial_orders")} (user_id)
      WHERE user_id IS NOT NULL
    """)
  end

  defp create_ordered_orders!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "ordered_orders")} (
      id bigint PRIMARY KEY,
      user_id bigint NOT NULL,
      status text NOT NULL DEFAULT 'open',
      CONSTRAINT ordered_orders_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES #{table(schema, "users")} (id)
    )
    """)

    query!("""
    CREATE INDEX ordered_orders_status_user_id_idx
      ON #{table(schema, "ordered_orders")} (status, user_id)
    """)
  end

  defp create_accounts!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "accounts")} (
      tenant_id bigint NOT NULL,
      account_id bigint NOT NULL,
      PRIMARY KEY (tenant_id, account_id)
    )
    """)
  end

  defp create_events!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "events")} (
      id bigint PRIMARY KEY,
      tenant_id bigint NOT NULL,
      account_id bigint NOT NULL,
      CONSTRAINT events_account_fkey
        FOREIGN KEY (tenant_id, account_id)
        REFERENCES #{table(schema, "accounts")} (tenant_id, account_id)
    )
    """)

    query!("""
    CREATE INDEX events_account_idx
      ON #{table(schema, "events")} (account_id, tenant_id)
    """)
  end

  defp create_included_events!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "included_events")} (
      id bigint PRIMARY KEY,
      tenant_id bigint NOT NULL,
      account_id bigint NOT NULL,
      CONSTRAINT included_events_account_fkey
        FOREIGN KEY (tenant_id, account_id)
        REFERENCES #{table(schema, "accounts")} (tenant_id, account_id)
    )
    """)

    query!("""
    CREATE INDEX included_events_tenant_include_account_idx
      ON #{table(schema, "included_events")} (tenant_id)
      INCLUDE (account_id)
    """)
  end

  defp create_action_messages!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "action_messages")} (
      id bigint PRIMARY KEY,
      owner_user_id bigint NOT NULL,
      status_user_id bigint NOT NULL,
      CONSTRAINT action_messages_owner_user_id_fkey
        FOREIGN KEY (owner_user_id)
        REFERENCES #{table(schema, "users")} (id)
        ON DELETE CASCADE
        ON UPDATE RESTRICT,
      CONSTRAINT action_messages_status_user_id_fkey
        FOREIGN KEY (status_user_id)
        REFERENCES #{table(schema, "users")} (id)
        ON DELETE RESTRICT
        ON UPDATE RESTRICT
    )
    """)

    query!("""
    CREATE INDEX action_messages_owner_user_id_idx
      ON #{table(schema, "action_messages")} (owner_user_id)
    """)

    query!("""
    CREATE INDEX action_messages_status_user_id_idx
      ON #{table(schema, "action_messages")} (status_user_id)
    """)
  end

  defp create_duplicate_indexes!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "duplicate_indexes")} (
      id bigint PRIMARY KEY,
      status text NOT NULL,
      note text
    )
    """)

    query!("""
    CREATE INDEX duplicate_indexes_status_idx
      ON #{table(schema, "duplicate_indexes")} (status)
    """)

    query!("""
    CREATE INDEX duplicate_indexes_status_duplicate_idx
      ON #{table(schema, "duplicate_indexes")} (status)
    """)

    query!("""
    CREATE INDEX duplicate_indexes_status_note_idx
      ON #{table(schema, "duplicate_indexes")} (status, note)
    """)
  end

  defp create_uuid_primary_key!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "uuid_primary_key")} (
      id uuid PRIMARY KEY
    )
    """)
  end

  defp create_bigint_primary_key!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "bigint_primary_key")} (
      id bigint PRIMARY KEY
    )
    """)
  end

  defp create_missing_primary_key!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "missing_primary_key")} (
      id uuid NOT NULL
    )
    """)
  end

  defp create_composite_uuid_primary_key!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "composite_uuid_primary_key")} (
      tenant_id uuid NOT NULL,
      account_id uuid NOT NULL,
      PRIMARY KEY (tenant_id, account_id)
    )
    """)
  end

  defp create_composite_mixed_primary_key!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "composite_mixed_primary_key")} (
      tenant_id uuid NOT NULL,
      account_id bigint NOT NULL,
      PRIMARY KEY (tenant_id, account_id)
    )
    """)
  end

  defp create_scoped_customers!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "scoped_customers")} (
      id bigint PRIMARY KEY,
      tenant_id bigint NOT NULL,
      name text NOT NULL,
      UNIQUE (tenant_id, id)
    )
    """)
  end

  defp create_scoped_orders_missing_scope!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "scoped_orders_missing_scope")} (
      id bigint PRIMARY KEY,
      tenant_id bigint NOT NULL,
      customer_id bigint NOT NULL,
      CONSTRAINT scoped_orders_missing_scope_customer_id_fkey
        FOREIGN KEY (customer_id)
        REFERENCES #{table(schema, "scoped_customers")} (id)
    )
    """)
  end

  defp create_scoped_orders_with_scope!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "scoped_orders_with_scope")} (
      id bigint PRIMARY KEY,
      tenant_id bigint NOT NULL,
      customer_id bigint NOT NULL,
      CONSTRAINT scoped_orders_with_scope_customer_id_fkey
        FOREIGN KEY (tenant_id, customer_id)
        REFERENCES #{table(schema, "scoped_customers")} (tenant_id, id)
    )
    """)
  end

  defp create_global_statuses!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "global_statuses")} (
      id bigint PRIMARY KEY,
      name text NOT NULL
    )
    """)
  end

  defp create_scoped_orders_with_global_status!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "scoped_orders_with_global_status")} (
      id bigint PRIMARY KEY,
      tenant_id bigint NOT NULL,
      status_id bigint NOT NULL,
      CONSTRAINT scoped_orders_with_global_status_status_id_fkey
        FOREIGN KEY (status_id)
        REFERENCES #{table(schema, "global_statuses")} (id)
    )
    """)
  end

  defp create_global_imports!(schema) do
    query!("""
    CREATE TABLE #{table(schema, "global_imports")} (
      id bigint PRIMARY KEY,
      customer_id bigint NOT NULL,
      CONSTRAINT global_imports_customer_id_fkey
        FOREIGN KEY (customer_id)
        REFERENCES #{table(schema, "scoped_customers")} (id)
    )
    """)
  end

  defp table(schema, name), do: quote_identifier(schema) <> "." <> quote_identifier(name)

  defp quote_identifier(identifier) do
    escaped = String.replace(identifier, ~s("), ~s(""))
    ~s("#{escaped}")
  end
end
