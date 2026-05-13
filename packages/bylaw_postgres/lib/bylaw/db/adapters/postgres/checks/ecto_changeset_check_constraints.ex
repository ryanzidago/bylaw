defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints do
  @moduledoc """
  Validates `Ecto.Changeset.check_constraint/3` annotations for Postgres checks.

  ## Examples

  With a check constraint on `users.age`, before:

  ```elixir
  def changeset(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, [:age])
    |> Ecto.Changeset.validate_number(:age, greater_than_or_equal_to: 13)
  end
  ```

  The database still protects the invariant, but a constraint failure may reach
  callers as a database error instead of a changeset error attached to `:age`.

  After, annotate the changeset with the matching check constraint:

  ```elixir
  def changeset(user, attrs) do
    user
    |> Ecto.Changeset.cast(attrs, [:age])
    |> Ecto.Changeset.validate_number(:age, greater_than_or_equal_to: 13)
    |> Ecto.Changeset.check_constraint(:age, name: :users_age_check)
  end
  ```

  Ecto can turn the database rejection into a normal changeset error.

  ## Notes

  The check skips dynamic `cast` or `change` field lists, check expressions
  without catalog column metadata, and constraints whose columns cannot be
  mapped to Ecto schema fields.

  ## Options

    * `:validate` - explicit `false` disables this check.
    * `:paths` - required non-empty list of source paths to parse for
      changeset functions.
    * `:otp_app` - OTP app used for compiled schema discovery. When the target
      repo can report `config()[:otp_app]`, this is inferred.
    * `:schema_modules` - explicit non-empty list of schema modules to inspect
      instead of discovering schemas from `:otp_app`.
    * `:rules` - optional rule keyword list or non-empty list of rule keyword
      lists. Rules use only shared scope keys.

  This check requires `:paths` and schema discovery from the target repo's
  inferred `:otp_app`, explicit `:otp_app`, or explicit `:schema_modules`, so
  bare-module configuration is not valid.

  Run globally for discovered schemas:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints,
   paths: ["lib/my_app"]}
  ```

  Run globally for explicit schema modules:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints,
   paths: ["lib/my_app/catalog"],
   schema_modules: [MyApp.Catalog.Product, MyApp.Catalog.Price]}
  ```

  Run only for matching rule scopes:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints,
   paths: ["lib/my_app"],
   rules: [
     where: [schemas: ["public"]],
     except: [[tables: ["legacy_products"], constraints: ["legacy_price_check"]]]
   ]}
  ```

  The check discovers compiled Ecto schemas through reflection, parses source
  files for conservative changeset candidates, and only requires
  `check_constraint/3` when Postgres can associate a check constraint with
  fields that a candidate casts.

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
          | {:rules, keyword() | list(keyword())}

  @type check_opts :: list(check_opt())

  @doc """
  Implements the `Bylaw.Db.Check` validation callback.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(target, opts), do: EctoChangesetConstraints.validate(target, opts, config())

  defp config do
    %{
      check: __MODULE__,
      kind: :check,
      name: :ecto_changeset_check_constraints,
      helper: "check_constraint",
      label: "check constraint",
      query: @query,
      query_error_message: "could not inspect Postgres check constraints"
    }
  end
end
