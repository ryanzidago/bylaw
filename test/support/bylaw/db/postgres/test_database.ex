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
  @timeout 15_000

  @spec schema() :: String.t()
  def schema, do: @schema

  @spec pg_schema() :: String.t()
  def pg_schema, do: @pg_schema

  @spec start_repo!() :: pid()
  def start_repo! do
    case TestRepo.start_link() do
      {:ok, pid} ->
        pid

      {:error, {:already_started, pid}} ->
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
    query!("DROP SCHEMA IF EXISTS #{quote_identifier(@schema)} CASCADE")
    query!("DROP SCHEMA IF EXISTS #{quote_identifier(@pg_schema)} CASCADE")

    create_fixture_schema!(@schema)
    create_pg_named_fixture_schema!(@pg_schema)

    Sandbox.mode(TestRepo, :manual)
  end

  @spec query!(String.t()) :: term()
  def query!(sql) do
    SQL.query!(TestRepo, sql, [], timeout: @timeout)
  end

  defp create_fixture_schema!(schema) do
    query!("CREATE SCHEMA #{quote_identifier(schema)}")
    create_users!(schema)
    create_orders_missing_index!(schema)
    create_indexed_orders!(schema)
    create_partial_orders!(schema)
    create_ordered_orders!(schema)
    create_accounts!(schema)
    create_events!(schema)
    create_included_events!(schema)
  end

  defp create_pg_named_fixture_schema!(schema) do
    query!("CREATE SCHEMA #{quote_identifier(schema)}")
    create_users!(schema)
    create_orders_missing_index!(schema)
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

  defp table(schema, name), do: quote_identifier(schema) <> "." <> quote_identifier(name)

  defp quote_identifier(identifier) do
    escaped = String.replace(identifier, ~s("), ~s(""))
    ~s("#{escaped}")
  end
end
