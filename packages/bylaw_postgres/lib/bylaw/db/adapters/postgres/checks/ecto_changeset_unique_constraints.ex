defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraints do
  @moduledoc """
  Validates `Ecto.Changeset.unique_constraint/3` annotations for Postgres indexes.

  ## Examples

  With a unique index on `users.email`, before:

  ```elixir
  def changeset(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, [:email])
    |> Ecto.Changeset.validate_required([:email])
  end
  ```

  The database protects uniqueness, but an insert conflict can bubble up as a
  database error instead of a changeset error attached to `:email`.

  After, annotate the changeset with the matching constraint:

  ```elixir
  def changeset(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, [:email])
    |> Ecto.Changeset.validate_required([:email])
    |> Ecto.Changeset.unique_constraint(:email)
  end
  ```

  Ecto can translate the database constraint violation into a normal changeset
  error for callers.

  ## Notes

  The check skips dynamic `cast` or `change` field lists, expression indexes,
  partial indexes, primary keys, and unique indexes whose columns cannot be
  mapped to Ecto schema fields.

  ## Options

  The check discovers compiled Ecto schemas through reflection, parses source
  files for conservative changeset candidates, and only requires
  `unique_constraint/3` when a candidate casts all fields covered by a unique
  Postgres index. Dynamic cast/change field lists are skipped for v1.


  The check needs source paths so Bylaw can parse source AST for user-defined
  changeset functions:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraints,
   paths: ["lib/my_app"]}
  ```

  When the repo can report `config()[:otp_app]`, schema module discovery is
  derived from it.

  ## Usage

  Add this module to the checks passed to
  `Bylaw.Db.Adapters.Postgres.validate/2`. See the
  [README usage section](readme.html#usage) for the full ExUnit setup.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres.EctoChangesetConstraints
  alias Bylaw.Db.Check
  alias Bylaw.Db.Target

  @query """
  SELECT
    namespace.nspname AS schema_name,
    table_class.relname AS table_name,
    index_class.relname AS constraint_name,
    ARRAY(
      SELECT attribute.attname
      FROM unnest(index_record.indkey) WITH ORDINALITY AS key(attnum, position)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = index_record.indrelid
       AND attribute.attnum = key.attnum
      WHERE key.position <= index_record.indnkeyatts
      ORDER BY key.position
    ) AS column_names
  FROM pg_catalog.pg_index AS index_record
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = index_record.indrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = table_class.relnamespace
  JOIN pg_catalog.pg_class AS index_class
    ON index_class.oid = index_record.indexrelid
  WHERE index_record.indisunique
    AND index_record.indisvalid
    AND NOT index_record.indisprimary
    AND index_record.indpred IS NULL
    AND index_record.indexprs IS NULL
    AND table_class.relkind IN ('r', 'p')
    AND namespace.nspname <> 'information_schema'
    AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
    AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
    AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
  ORDER BY schema_name, table_name, constraint_name

  """

  @type check_opt ::
          {:validate, boolean()}
          | {:otp_app, atom()}
          | {:paths, list(Path.t())}
          | {:schema_modules, list(module())}
          | {:rules, list(keyword())}

  @type check_opts :: list(check_opt())

  @doc """
  Validates changeset unique-constraint helpers for a Postgres target.

  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(target, opts), do: EctoChangesetConstraints.validate(target, opts, config())

  defp config do
    %{
      check: __MODULE__,
      kind: :unique,
      name: :ecto_changeset_unique_constraints,
      helper: "unique_constraint",
      label: "unique index",
      query: @query,
      query_error_message: "could not inspect Postgres unique indexes"
    }
  end
end
