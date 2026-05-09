defmodule Bylaw.Db.Adapters.Postgres.EctoChangesetConstraints do
  @moduledoc false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.EctoChangesetConstraintOptions
  alias Bylaw.Db.Adapters.Postgres.Result
  alias Bylaw.Db.Adapters.Postgres.RuleOptions
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target
  alias Bylaw.Ecto.Changeset
  alias Bylaw.Ecto.Schema

  defmodule CatalogConstraint do
    @moduledoc false

    @type kind :: :unique | :foreign_key | :check

    @type t :: %__MODULE__{
            kind: kind(),
            schema: String.t(),
            table: String.t(),
            name: String.t(),
            columns: list(String.t())
          }

    defstruct kind: nil,
              schema: nil,
              table: nil,
              name: nil,
              columns: []
  end

  @type check_opt ::
          {:validate, boolean()}
          | {:otp_app, atom()}
          | {:paths, list(Path.t())}
          | {:schema_modules, list(module())}
          | {:rules, list(Keyword.t())}

  @type check_opts :: list(check_opt())

  @type config :: %{
          check: module(),
          kind: CatalogConstraint.kind(),
          name: atom(),
          helper: String.t(),
          label: String.t(),
          query: String.t(),
          query_error_message: String.t()
        }

  @row_keys %{
    "column_names" => :column_names,
    "constraint_name" => :constraint_name,
    "kind" => :kind,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc false
  @spec validate(target :: Target.t(), opts :: check_opts(), config :: config()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts, config) when is_list(opts) do
    opts = EctoChangesetConstraintOptions.normalize!(target, opts, config.name)

    if Keyword.get(opts, :validate, true) == true do
      validate_enabled(target, opts, config)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts, config) do
    raise ArgumentError,
          "expected #{config.name} opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts, _config) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts, _config) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  @doc false
  @spec validate_from_opts(opts :: Postgres.target_opts() | check_opts(), config :: config()) ::
          Check.result()
  def validate_from_opts(opts, config) when is_list(opts) do
    target =
      opts
      |> Keyword.take([:repo, :dynamic_repo, :query, :meta])
      |> Postgres.target()

    validate(target, Keyword.drop(opts, [:repo, :dynamic_repo, :query, :meta]), config)
  end

  def validate_from_opts(opts, config) do
    raise ArgumentError,
          "expected #{config.name} opts to be a keyword list, got: #{inspect(opts)}"
  end

  @doc false
  @spec compare(
          target :: Target.t(),
          schemas :: list(Schema.info()),
          candidates :: list(Changeset.Candidate.t()),
          constraints :: list(CatalogConstraint.t()),
          config :: config()
        ) :: Check.result()
  def compare(target, schemas, candidates, constraints, config) do
    issues =
      schemas
      |> Enum.flat_map(&schema_issues(target, &1, candidates, constraints, config))
      |> Enum.sort_by(&{&1.meta.schema_module, &1.meta.function, &1.meta.constraint})

    Result.to_check_result(issues)
  end

  defp validate_enabled(target, opts, config) do
    rules =
      RuleOptions.default_rules!(
        opts,
        config.name,
        EctoChangesetConstraintOptions.allowed_matcher_keys()
      )

    schemas = RuleOptions.filter(opts, :schemas, config.name)
    tables = RuleOptions.filter(opts, :tables, config.name)

    case catalog_constraints(target, rules, schemas, tables, config) do
      {:ok, constraints} ->
        schema_infos =
          opts
          |> schema_modules()
          |> Enum.map(&Schema.info/1)

        schema_modules = Enum.map(schema_infos, & &1.module)

        candidates =
          opts
          |> Keyword.fetch!(:paths)
          |> Changeset.candidates(schema_modules)

        compare(target, schema_infos, candidates, constraints, config)

      {:error, reason} ->
        {:error, [query_error_issue(target, rules, reason, config)]}
    end
  end

  defp catalog_constraints(target, rules, schemas, tables, config) do
    case Postgres.query(target, config.query, [schemas, tables], []) do
      {:ok, result} ->
        constraints =
          result
          |> Result.rows()
          |> Enum.filter(&matches_rules?(&1, rules))
          |> Enum.map(&catalog_constraint(&1, config.kind))

        {:ok, constraints}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schema_modules(opts) do
    modules =
      case Keyword.fetch(opts, :schema_modules) do
        {:ok, schema_modules} ->
          schema_modules

        :error ->
          opts
          |> Keyword.fetch!(:otp_app)
          |> Schema.modules()
      end

    Enum.filter(modules, &Schema.ecto_schema?/1)
  end

  defp schema_issues(target, schema, candidates, constraints, config) do
    schema_candidates = Enum.filter(candidates, &(&1.module == schema.module))
    table_constraints = Enum.filter(constraints, &constraint_for_schema?(&1, schema))

    Enum.flat_map(schema_candidates, fn candidate ->
      candidate_issues(target, schema, candidate, table_constraints, config)
    end)
  end

  defp constraint_for_schema?(constraint, schema) do
    constraint.table == schema.source and constraint.schema == schema_prefix(schema)
  end

  defp schema_prefix(%{prefix: nil}), do: "public"
  defp schema_prefix(%{prefix: prefix}), do: prefix

  defp candidate_issues(target, schema, candidate, constraints, config) do
    Enum.flat_map(constraints, fn constraint ->
      with {:ok, fields} <- constraint_fields(schema, constraint),
           true <- responsible_for_constraint?(candidate, fields),
           false <- matching_constraint_call?(schema, candidate, constraint, fields, config) do
        [issue(target, schema, candidate, constraint, fields, config)]
      else
        _skip -> []
      end
    end)
  end

  defp constraint_fields(schema, constraint) do
    fields =
      Enum.flat_map(constraint.columns, fn column ->
        case Map.fetch(schema.field_sources, column) do
          {:ok, field} -> [field]
          :error -> []
        end
      end)

    if Enum.count(fields) == Enum.count(constraint.columns) and not Enum.empty?(fields) do
      {:ok, fields}
    else
      :skip
    end
  end

  defp responsible_for_constraint?(candidate, fields) do
    field_set = MapSet.new(fields)
    candidate_field_set = MapSet.new(candidate.fields)

    MapSet.subset?(field_set, candidate_field_set)
  end

  defp matching_constraint_call?(schema, candidate, constraint, fields, config) do
    Enum.any?(candidate.constraints, fn call ->
      call.kind == config.kind and matching_call?(schema, call, constraint, fields)
    end)
  end

  defp matching_call?(_schema, %{name: %Regex{} = name}, constraint, _fields) do
    Regex.match?(name, constraint.name)
  end

  defp matching_call?(_schema, %{name: name, match: :exact}, constraint, _fields)
       when is_binary(name) do
    name == constraint.name
  end

  defp matching_call?(_schema, %{name: name, match: :suffix}, constraint, _fields)
       when is_binary(name) do
    String.ends_with?(constraint.name, name)
  end

  defp matching_call?(_schema, %{name: name, match: :prefix}, constraint, _fields)
       when is_binary(name) do
    String.starts_with?(constraint.name, name)
  end

  defp matching_call?(schema, call, constraint, fields) do
    call.fields == fields and constraint.name in inferred_names(schema, call.kind, fields)
  end

  defp inferred_names(schema, :unique, fields) do
    columns = Enum.map(fields, &field_source!(schema, &1))

    [schema.source, Enum.join(columns, "_"), "index"]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("_")
    |> List.wrap()
  end

  defp inferred_names(schema, :foreign_key, [field]) do
    ["#{schema.source}_#{field_source!(schema, field)}_fkey"]
  end

  defp inferred_names(_schema, :check, _fields), do: []

  defp inferred_names(_schema, _kind, _fields), do: []

  defp field_source!(schema, field) do
    Enum.find_value(schema.field_sources, fn
      {source, ^field} -> source
      _other -> nil
    end)
  end

  defp issue(target, schema, candidate, constraint, fields, config) do
    field_text = format_fields(fields)

    %Issue{
      check: config.check,
      target: target,
      message:
        "#{inspect(schema.module)}.#{candidate.function}/#{candidate.arity} casts #{field_text} for table #{inspect(schema.source)}, but Postgres has #{config.label} #{inspect(constraint.name)} and this function does not declare #{config.helper}(#{field_text}) or #{config.helper}(..., name: #{format_name_option(constraint.name)}).",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema_module: schema.module,
        table_schema: constraint.schema,
        table: schema.source,
        function: candidate.function,
        arity: candidate.arity,
        constraint: constraint.name,
        constraint_kind: constraint.kind,
        columns: constraint.columns,
        fields: fields
      }
    }
  end

  defp format_fields([field]), do: inspect(field)
  defp format_fields(fields), do: inspect(fields)

  defp format_name_option(name) do
    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*[!?]?$/, name) do
      ":#{name}"
    else
      inspect(name)
    end
  end

  defp catalog_constraint(row, expected_kind) do
    %CatalogConstraint{
      kind: expected_kind,
      schema: Result.value(row, "schema_name", @row_keys),
      table: Result.value(row, "table_name", @row_keys),
      name: Result.value(row, "constraint_name", @row_keys),
      columns: Result.value(row, "column_names", @row_keys)
    }
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matcher_value(row, :schema), do: Result.value(row, "schema_name", @row_keys)
  defp matcher_value(row, :table), do: Result.value(row, "table_name", @row_keys)
  defp matcher_value(row, :constraint), do: Result.value(row, "constraint_name", @row_keys)
  defp matcher_value(row, :column), do: Result.value(row, "column_names", @row_keys)

  defp query_error_issue(target, rules, reason, config) do
    %Issue{
      check: config.check,
      target: target,
      message: config.query_error_message,
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        rules: rules,
        reason: reason
      }
    }
  end
end
