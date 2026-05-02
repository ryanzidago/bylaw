defmodule Bylaw.Db.Postgres.Checks.ForeignKeyIndexesIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.Checks.ForeignKeyIndexes

  @moduletag :postgres
  @moduletag timeout: 30_000

  @default_postgres_url "postgres://localhost:5432/bylaw_test"

  setup_all do
    url = System.get_env("BYLAW_POSTGRES_URL", @default_postgres_url)

    {:ok, conn} =
      url
      |> connection_opts()
      |> Postgrex.start_link()

    on_exit(fn ->
      if Process.alive?(conn) do
        GenServer.stop(conn)
      end
    end)

    {:ok, conn: conn}
  end

  setup %{conn: conn} do
    schema = "bylaw_fk_indexes_#{System.unique_integer([:positive])}"

    query!(conn, "CREATE SCHEMA #{quote_identifier(schema)}")

    on_exit(fn ->
      query!(conn, "DROP SCHEMA IF EXISTS #{quote_identifier(schema)} CASCADE")
    end)

    {:ok, schema: schema, target: target(conn)}
  end

  test "reports actual foreign keys without supporting indexes", %{
    conn: conn,
    schema: schema,
    target: target
  } do
    create_single_column_fk!(conn, schema)

    assert {:error, %Issue{} = issue} =
             Postgres.validate(target, [{ForeignKeyIndexes, schemas: [schema]}])

    assert issue.message ==
             "expected foreign key orders_user_id_fkey on #{schema}.orders to have a supporting index"

    assert issue.meta.schema == schema
    assert issue.meta.table == "orders"
    assert issue.meta.constraint == "orders_user_id_fkey"
    assert issue.meta.columns == ["user_id"]
  end

  test "passes when actual foreign keys have supporting indexes", %{
    conn: conn,
    schema: schema,
    target: target
  } do
    create_single_column_fk!(conn, schema)
    query!(conn, "CREATE INDEX orders_user_id_idx ON #{table(schema, "orders")} (user_id)")

    assert :ok = Postgres.validate(target, [{ForeignKeyIndexes, schemas: [schema]}])
  end

  test "ignores partial indexes", %{conn: conn, schema: schema, target: target} do
    create_single_column_fk!(conn, schema)

    query!(
      conn,
      "CREATE INDEX orders_user_id_partial_idx ON #{table(schema, "orders")} (user_id) WHERE user_id IS NOT NULL"
    )

    assert {:error, %Issue{} = issue} =
             Postgres.validate(target, [{ForeignKeyIndexes, schemas: [schema]}])

    assert issue.meta.constraint == "orders_user_id_fkey"
  end

  test "requires foreign key columns to be leading index columns", %{
    conn: conn,
    schema: schema,
    target: target
  } do
    create_single_column_fk!(conn, schema)

    query!(
      conn,
      "CREATE INDEX orders_status_user_id_idx ON #{table(schema, "orders")} (status, user_id)"
    )

    assert {:error, %Issue{} = issue} =
             Postgres.validate(target, [{ForeignKeyIndexes, schemas: [schema]}])

    assert issue.meta.constraint == "orders_user_id_fkey"
  end

  test "passes when composite foreign key columns are the leading index columns", %{
    conn: conn,
    schema: schema,
    target: target
  } do
    query!(conn, """
    CREATE TABLE #{table(schema, "accounts")} (
      tenant_id bigint NOT NULL,
      account_id bigint NOT NULL,
      PRIMARY KEY (tenant_id, account_id)
    )
    """)

    query!(conn, """
    CREATE TABLE #{table(schema, "events")} (
      id bigint PRIMARY KEY,
      tenant_id bigint NOT NULL,
      account_id bigint NOT NULL,
      CONSTRAINT events_account_fkey
        FOREIGN KEY (tenant_id, account_id)
        REFERENCES #{table(schema, "accounts")} (tenant_id, account_id)
    )
    """)

    query!(
      conn,
      "CREATE INDEX events_account_idx ON #{table(schema, "events")} (account_id, tenant_id)"
    )

    assert :ok = Postgres.validate(target, [{ForeignKeyIndexes, schemas: [schema]}])
  end

  test "applies schema and table scope", %{conn: conn, schema: schema, target: target} do
    other_schema = "#{schema}_other"

    query!(conn, "CREATE SCHEMA #{quote_identifier(other_schema)}")

    on_exit(fn ->
      query!(conn, "DROP SCHEMA IF EXISTS #{quote_identifier(other_schema)} CASCADE")
    end)

    create_single_column_fk!(conn, schema)
    create_single_column_fk!(conn, other_schema)

    assert {:error, %Issue{} = issue} =
             Postgres.validate(target, [
               {ForeignKeyIndexes, schemas: [schema], tables: ["orders"]}
             ])

    assert issue.meta.schema == schema
    assert issue.meta.table == "orders"
  end

  defp target(conn) do
    Postgres.target(
      query: fn _target, sql, params, opts ->
        Postgrex.query(conn, sql, params, opts)
      end
    )
  end

  defp connection_opts(url) do
    uri = URI.parse(url)

    unless uri.scheme in ["postgres", "postgresql"] do
      raise ArgumentError, "expected BYLAW_POSTGRES_URL to use postgres:// or postgresql://"
    end

    {username, password} = credentials(uri)

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      database: database!(uri),
      username: username,
      password: password,
      timeout: 15_000,
      connect_timeout: 15_000,
      prepare: :unnamed
    ]
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
    |> maybe_enable_ssl(uri)
  end

  defp credentials(%URI{userinfo: nil}), do: {nil, nil}

  defp credentials(%URI{userinfo: userinfo}) do
    case String.split(userinfo, ":", parts: 2) do
      [username, password] -> {URI.decode(username), URI.decode(password)}
      [username] -> {URI.decode(username), nil}
    end
  end

  defp database!(%URI{path: "/" <> database}) when byte_size(database) > 0 do
    URI.decode(database)
  end

  defp database!(_uri),
    do: raise(ArgumentError, "expected BYLAW_POSTGRES_URL to include a database")

  defp maybe_enable_ssl(opts, %URI{query: query}) when is_binary(query) do
    query_params = URI.decode_query(query)

    if query_params["sslmode"] == "require" do
      Keyword.put(opts, :ssl, true)
    else
      opts
    end
  end

  defp maybe_enable_ssl(opts, _uri), do: opts

  defp create_single_column_fk!(conn, schema) do
    query!(conn, """
    CREATE TABLE #{table(schema, "users")} (
      id bigint PRIMARY KEY
    )
    """)

    query!(conn, """
    CREATE TABLE #{table(schema, "orders")} (
      id bigint PRIMARY KEY,
      user_id bigint NOT NULL,
      status text NOT NULL DEFAULT 'open',
      CONSTRAINT orders_user_id_fkey
        FOREIGN KEY (user_id)
        REFERENCES #{table(schema, "users")} (id)
    )
    """)
  end

  defp query!(conn, sql) when is_pid(conn) do
    Postgrex.query!(conn, sql, [], timeout: 15_000)
  end

  defp query!(nil, _sql), do: raise("Postgres integration connection not configured")

  defp table(schema, name), do: quote_identifier(schema) <> "." <> quote_identifier(name)

  defp quote_identifier(identifier) do
    escaped = String.replace(identifier, ~s("), ~s(""))
    ~s("#{escaped}")
  end
end
