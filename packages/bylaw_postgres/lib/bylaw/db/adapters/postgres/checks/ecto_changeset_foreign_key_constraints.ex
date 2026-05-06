defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints do
  @moduledoc """
  Validates `Ecto.Changeset.foreign_key_constraint/3` annotations for Postgres FKs.

  The check discovers compiled Ecto schemas through reflection, parses source
  files for conservative changeset candidates, and only requires
  `foreign_key_constraint/3` when a candidate casts the local foreign-key field.
  Dynamic cast/change field lists are skipped for v1.

  The common ExUnit setup only needs a repo and source paths. The repo is used
  to query the live test database catalog, and `paths` tells Bylaw where to
  parse source AST for user-defined changeset functions. When the repo can
  report `config()[:otp_app]`, schema module discovery is derived from it:

      assert :ok =
               Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints.validate(
                 repo: MyApp.Repo,
                 paths: ["lib/my_app"]
               )
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
  @spec validate(opts :: Postgres.validate_opts() | check_opts()) :: Check.result()
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
