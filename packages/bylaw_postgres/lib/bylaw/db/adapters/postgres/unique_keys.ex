defmodule Bylaw.Db.Adapters.Postgres.UniqueKeys do
  @moduledoc """
  Reads deterministic ordering keys from a Postgres database.

  `fetch!/1` returns unique database column sets keyed by
  `{database_schema, table}`:

      %{
        {"public", "posts"} => [
          ["id"],
          ["slug"],
          ["organisation_id", "sequence"]
        ]
      }

  Tables visible through the current Postgres search path also receive a
  `{nil, table}` entry. This lets unprefixed Ecto queries use the same catalogue
  without assuming that the visible schema is `public`.

  The catalogue includes primary keys and valid, immediate, full-table unique
  indexes over plain columns. Nullable unique keys are included only when every
  key column is `NOT NULL` or the index uses `NULLS NOT DISTINCT`.

  Partial indexes, expression indexes, invalid indexes, deferrable uniqueness,
  non-default operator classes, and non-default collations are excluded because
  they do not conservatively prove that a plain Ecto field ordering is unique.

  The functions are stateless. Every invocation performs one Postgres catalogue
  query.
  """

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Result
  alias Bylaw.Db.Target

  @query """
  SELECT
    namespace.nspname AS schema_name,
    table_class.relname AS table_name,
    ARRAY(
      SELECT attribute.attname
      FROM unnest(index_record.indkey) WITH ORDINALITY AS key(attnum, position)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = index_record.indrelid
       AND attribute.attnum = key.attnum
      WHERE key.position <= index_record.indnkeyatts
      ORDER BY key.position
    ) AS column_names,
    pg_catalog.pg_table_is_visible(table_class.oid) AS table_visible
  FROM pg_catalog.pg_index AS index_record
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = index_record.indrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = table_class.relnamespace
  JOIN pg_catalog.pg_class AS index_class
    ON index_class.oid = index_record.indexrelid
  JOIN pg_catalog.pg_am AS access_method
    ON access_method.oid = index_class.relam
  WHERE index_record.indisunique
    AND index_record.indisvalid
    AND index_record.indisready
    AND index_record.indislive
    AND index_record.indimmediate
    AND index_record.indpred IS NULL
    AND index_record.indexprs IS NULL
    AND table_class.relkind IN ('r', 'p')
    AND access_method.amname = 'btree'
    AND namespace.nspname <> 'information_schema'
    AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
    AND (
      COALESCE(
        (to_jsonb(index_record) ->> 'indnullsnotdistinct')::boolean,
        false
      )
      OR NOT EXISTS (
        SELECT 1
        FROM unnest(index_record.indkey) WITH ORDINALITY AS key(attnum, position)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = index_record.indrelid
         AND attribute.attnum = key.attnum
        WHERE key.position <= index_record.indnkeyatts
          AND NOT attribute.attnotnull
      )
    )
    AND NOT EXISTS (
      SELECT 1
      FROM unnest(
        index_record.indkey,
        index_record.indclass,
        index_record.indcollation
      ) WITH ORDINALITY AS key(attnum, opclass_oid, collation_oid, position)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = index_record.indrelid
       AND attribute.attnum = key.attnum
      JOIN pg_catalog.pg_opclass AS operator_class
        ON operator_class.oid = key.opclass_oid
      WHERE key.position <= index_record.indnkeyatts
        AND (
          NOT operator_class.opcdefault
          OR key.collation_oid <> attribute.attcollation
        )
    )
  ORDER BY schema_name, table_name, column_names

  """

  @typedoc """
  Database columns that together form one verified unique key.
  """
  @type unique_key :: nonempty_list(String.t())
  @typedoc """
  Verified unique keys keyed by database schema and table.

  A `nil` database schema represents an unqualified table visible through the
  current Postgres search path.
  """
  @type catalogue :: %{
          optional({String.t() | nil, String.t()}) => list(unique_key())
        }
  @typedoc """
  Option accepted by `fetch!/2`.
  """
  @type fetch_opt :: {:dynamic_repo, atom() | pid() | nil}
  @typedoc """
  Options accepted by `fetch!/2`.
  """
  @type fetch_opts :: list(fetch_opt())

  @row_keys %{
    "column_names" => :column_names,
    "schema_name" => :schema_name,
    "table_name" => :table_name,
    "table_visible" => :table_visible
  }

  @doc """
  Fetches verified unique keys from one Postgres repo.

  Raises when the repo cannot be inspected or returns malformed catalogue data.
  """
  @spec fetch!(repo :: module()) :: catalogue()
  def fetch!(repo), do: fetch!(repo, [])

  @doc """
  Fetches verified unique keys from one Postgres repo with options.

  The only supported option is `:dynamic_repo`. Pass a dynamic repo name or PID
  to run the catalogue query against that repo. The previously selected dynamic
  repo is restored after the query.
  """
  @spec fetch!(repo :: module(), opts :: fetch_opts()) :: catalogue()
  def fetch!(repo, opts) when is_atom(repo) and not is_nil(repo) and is_list(opts) do
    validate_opts!(opts)

    opts
    |> Keyword.put(:repo, repo)
    |> Postgres.target()
    |> fetch_target!()
  end

  def fetch!(repo, _opts) when not is_atom(repo) or is_nil(repo) do
    raise ArgumentError, "expected Postgres repo to be a module, got: #{inspect(repo)}"
  end

  def fetch!(_repo, opts) do
    raise ArgumentError,
          "expected Postgres unique key opts to be a keyword list, got: #{inspect(opts)}"
  end

  @doc false
  @spec fetch_target!(Target.t()) :: catalogue()
  def fetch_target!(%Target{adapter: Postgres} = target) do
    case Postgres.query(target, @query, [], []) do
      {:ok, result} ->
        result
        |> Result.rows()
        |> catalogue!()

      {:error, reason} ->
        raise RuntimeError,
              "could not inspect Postgres unique keys: #{inspect(reason)}"
    end
  end

  def fetch_target!(%Target{} = target) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def fetch_target!(target) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp catalogue!(rows) do
    rows
    |> Enum.reduce(%{}, &put_row!/2)
    |> Map.new(fn {source, unique_keys} ->
      {source, unique_keys |> Enum.uniq() |> Enum.sort()}
    end)
  end

  defp put_row!(row, catalogue) do
    schema_name = Result.value(row, "schema_name", @row_keys)
    table_name = Result.value(row, "table_name", @row_keys)
    column_names = Result.value(row, "column_names", @row_keys)
    table_visible = Result.value(row, "table_visible", @row_keys)

    validate_row!(schema_name, table_name, column_names, table_visible)

    catalogue
    |> Map.update({schema_name, table_name}, [column_names], &[column_names | &1])
    |> put_visible_table(table_visible, table_name, column_names)
  end

  defp put_visible_table(catalogue, true, table_name, column_names) do
    Map.update(catalogue, {nil, table_name}, [column_names], &[column_names | &1])
  end

  defp put_visible_table(catalogue, false, _table_name, _column_names), do: catalogue

  defp validate_row!(schema_name, table_name, column_names, table_visible)
       when is_binary(schema_name) and byte_size(schema_name) > 0 and is_binary(table_name) and
              byte_size(table_name) > 0 and is_list(column_names) and
              is_boolean(table_visible) do
    if Enum.empty?(column_names) or
         Enum.any?(column_names, &(not is_binary(&1) or byte_size(&1) == 0)) do
      raise_malformed_row!(schema_name, table_name, column_names, table_visible)
    end
  end

  defp validate_row!(schema_name, table_name, column_names, table_visible) do
    raise_malformed_row!(schema_name, table_name, column_names, table_visible)
  end

  defp raise_malformed_row!(schema_name, table_name, column_names, table_visible) do
    row = %{
      schema_name: schema_name,
      table_name: table_name,
      column_names: column_names,
      table_visible: table_visible
    }

    raise ArgumentError, "expected a valid Postgres unique key row, got: #{inspect(row)}"
  end

  defp validate_opts!(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected Postgres unique key opts to be a keyword list, got: #{inspect(opts)}"
    end

    Enum.each(opts, fn {key, _value} ->
      if key != :dynamic_repo do
        raise ArgumentError, "unknown Postgres unique key option: #{inspect(key)}"
      end
    end)
  end
end
