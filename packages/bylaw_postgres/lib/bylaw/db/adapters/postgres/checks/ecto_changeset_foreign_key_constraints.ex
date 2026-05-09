defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints do
  @moduledoc """
  Validates `Ecto.Changeset.foreign_key_constraint/3` annotations for Postgres FKs.

  ## Options

  The check discovers compiled Ecto schemas through reflection, parses source
  files for conservative changeset candidates, and only requires
  `foreign_key_constraint/3` when a candidate casts the local foreign-key field.
  Dynamic cast/change field lists are skipped for v1.


  The check needs source paths so Bylaw can parse source AST for user-defined
  changeset functions:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints,
   paths: ["lib/my_app"]}
  ```

  When the repo can report `config()[:otp_app]`, schema module discovery is
  derived from it.

  ## Example

  With a foreign key on `orders.account_id`, before:

  ```elixir
  def changeset(order, attrs) do
    order
    |> Ecto.Changeset.cast(attrs, [:account_id])
    |> Ecto.Changeset.validate_required([:account_id])
  end
  ```

  The database rejects missing accounts, but the caller may see a low-level
  constraint error instead of an `:account_id` changeset error.

  After, annotate the changeset with the matching constraint:

  ```elixir
  def changeset(order, attrs) do
    order
    |> Ecto.Changeset.cast(attrs, [:account_id])
    |> Ecto.Changeset.validate_required([:account_id])
    |> Ecto.Changeset.foreign_key_constraint(:account_id)
  end
  ```

  Ecto can report the invalid relationship through the changeset API.

  ## Notes

  The check skips dynamic `cast` or `change` field lists and foreign keys whose
  columns cannot be mapped to Ecto schema fields.

  ## Usage

  Add this module to the checks passed to
  `Bylaw.Db.Adapters.Postgres.validate/2`. See the
  [README usage section](readme.html#usage) for the full ExUnit setup.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.EctoChangesetConstraints
  alias Bylaw.Db.Check
  alias Bylaw.Db.Target

  @query """
  SELECT
    namespace.nspname AS schema_name,
    table_class.relname AS table_name,
    constraint_record.conname AS constraint_name,
    ARRAY(
      SELECT attribute.attname
      FROM unnest(constraint_record.conkey) WITH ORDINALITY AS key(attnum, position)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = constraint_record.conrelid
       AND attribute.attnum = key.attnum
      ORDER BY key.position
    ) AS column_names
  FROM pg_catalog.pg_constraint AS constraint_record
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = constraint_record.conrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = table_class.relnamespace
  WHERE constraint_record.contype = 'f'
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
  Validates changeset foreign-key constraint helpers for a Postgres target.

  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(target, opts), do: EctoChangesetConstraints.validate(target, opts, config())

  @doc """
  Builds a Postgres target from options and validates foreign-key helpers.

  """
  @spec validate(opts :: Postgres.target_opts() | check_opts()) :: Check.result()
  def validate(opts), do: EctoChangesetConstraints.validate_from_opts(opts, config())

  defp config do
    %{
      check: __MODULE__,
      kind: :foreign_key,
      name: :ecto_changeset_foreign_key_constraints,
      helper: "foreign_key_constraint",
      label: "foreign key constraint",
      query: @query,
      query_error_message: "could not inspect Postgres foreign key constraints"
    }
  end
end
