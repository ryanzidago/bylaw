defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints do
  @moduledoc """
  Validates `Ecto.Changeset.check_constraint/3` annotations for Postgres checks.

  The check discovers compiled Ecto schemas through reflection, parses source
  files for conservative changeset candidates, and only requires
  `check_constraint/3` when Postgres can associate a check constraint with
  fields that a candidate casts. Dynamic cast/change field lists and check
  expressions without catalog column metadata are skipped for v1.

  The common ExUnit setup only needs a repo and source paths. The repo is used
  to query the live test database catalog, and `paths` tells Bylaw where to
  parse source AST for user-defined changeset functions. When the repo can
  report `config()[:otp_app]`, schema module discovery is derived from it:

      assert :ok =
               Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints.validate(
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
  WHERE constraint_record.contype = 'c'
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
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}

  @type check_opts :: list(check_opt())

  @doc """
  Returns the option namespace used by this check.
  """
  @impl Bylaw.Db.Check
  @spec name() :: :ecto_changeset_check_constraints
  def name, do: :ecto_changeset_check_constraints

  @doc """
  Validates changeset check-constraint helpers for a Postgres target.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(target, opts), do: EctoChangesetConstraints.validate(target, opts, config())

  @doc """
  Builds a Postgres target from options and validates check-constraint helpers.
  """
  @spec validate(opts :: Postgres.validate_opts() | check_opts()) :: Check.result()
  def validate(opts), do: EctoChangesetConstraints.validate_from_opts(opts, config())

  defp config do
    %{
      check: __MODULE__,
      kind: :check,
      name: name(),
      helper: "check_constraint",
      label: "check constraint",
      query: @query,
      query_error_message: "could not inspect Postgres check constraints"
    }
  end
end
