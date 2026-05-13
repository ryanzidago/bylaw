defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints do
  @moduledoc """
  Validates `Ecto.Changeset.foreign_key_constraint/3` annotations for Postgres FKs.

  ## Examples

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
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints,
   paths: ["lib/my_app"]}
  ```

  Run globally for explicit schema modules:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints,
   paths: ["lib/my_app/billing"],
   schema_modules: [MyApp.Billing.Invoice, MyApp.Billing.Payment]}
  ```

  Run only for matching rule scopes:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints,
   paths: ["lib/my_app"],
   rules: [where: [schemas: ["public"]], except: [[tables: ["events"], columns: ["actor_id"]]]]}
  ```

  The check discovers compiled Ecto schemas through reflection, parses source
  files for conservative changeset candidates, and only requires
  `foreign_key_constraint/3` when a candidate casts the local foreign-key field.

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
      kind: :foreign_key,
      name: :ecto_changeset_foreign_key_constraints,
      helper: "foreign_key_constraint",
      label: "foreign key constraint",
      query: @query,
      query_error_message: "could not inspect Postgres foreign key constraints"
    }
  end
end
