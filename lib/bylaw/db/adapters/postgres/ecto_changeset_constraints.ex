defmodule Bylaw.Db.Adapters.Postgres.EctoChangesetConstraints do
  @moduledoc false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target
  alias Bylaw.Ecto.Changeset
  alias Bylaw.Ecto.Schema

  defmodule CatalogConstraint do
    @moduledoc false

    @type kind :: :unique | :foreign_key

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
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}

  @type check_opts :: list(check_opt())

  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

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
    opts = check_opts!(target, opts, config.name)

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
  @spec validate_from_opts(opts :: Postgres.validate_opts() | check_opts(), config :: config()) ::
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

    result(issues)
  end

  defp validate_enabled(target, opts, config) do
    schemas = filter(opts, :schemas, config.name)
    tables = filter(opts, :tables, config.name)

    case catalog_constraints(target, schemas, tables, config) do
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
        {:error, [query_error_issue(target, schemas, tables, reason, config)]}
    end
  end

  defp catalog_constraints(target, schemas, tables, config) do
    case Postgres.query(target, config.query, [schemas, tables], []) do
      {:ok, result} ->
        constraints =
          result
          |> rows()
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

  defp rows(result) when is_map(result) do
    %{columns: columns, rows: rows} = result

    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp rows(rows) when is_list(rows), do: rows

  defp catalog_constraint(row, expected_kind) do
    %CatalogConstraint{
      kind: expected_kind,
      schema: value(row, "schema_name"),
      table: value(row, "table_name"),
      name: value(row, "constraint_name"),
      columns: value(row, "column_names")
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp check_opts!(target, opts, name) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError, "expected #{name} opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :otp_app, :paths, :schema_modules, :schemas, :tables]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown #{name} option: #{inspect(key)}"
      end
    end)

    opts = maybe_put_repo_otp_app(target, opts)

    validate_boolean_option!(opts, :validate, name)

    if Keyword.get(opts, :validate, true) == true do
      validate_schema_discovery_opts!(opts, name)
      validate_required_option!(opts, :paths, name)
      validate_schema_modules_option!(opts, name)
      validate_paths_option!(opts, name)
      validate_filter_option!(opts, :schemas, name)
      validate_filter_option!(opts, :tables, name)
    end

    opts
  end

  defp maybe_put_repo_otp_app(%{repo: repo}, opts) when is_atom(repo) and not is_nil(repo) do
    if Keyword.has_key?(opts, :otp_app) or Keyword.has_key?(opts, :schema_modules) do
      opts
    else
      case repo_otp_app(repo) do
        nil -> opts
        otp_app -> Keyword.put(opts, :otp_app, otp_app)
      end
    end
  end

  defp maybe_put_repo_otp_app(_target, opts), do: opts

  defp repo_otp_app(repo) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :config, 0) do
      repo.config()[:otp_app]
    end
  end

  defp validate_boolean_option!(opts, key, name) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "expected #{name} #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
  end

  defp validate_schema_discovery_opts!(opts, name) do
    if not Keyword.has_key?(opts, :otp_app) and not Keyword.has_key?(opts, :schema_modules) do
      raise ArgumentError, "expected #{name} opts to include :otp_app or :schema_modules"
    end
  end

  defp validate_required_option!(opts, key, name) do
    if not Keyword.has_key?(opts, key) do
      raise ArgumentError, "expected #{name} opts to include #{inspect(key)}"
    end
  end

  defp validate_schema_modules_option!(opts, name) do
    case Keyword.fetch(opts, :schema_modules) do
      {:ok, modules} when is_list(modules) ->
        if Enum.empty?(modules) or Enum.any?(modules, &(not is_atom(&1))) do
          raise_schema_modules_error!(name)
        end

      {:ok, _modules} ->
        raise_schema_modules_error!(name)

      :error ->
        :ok
    end
  end

  defp validate_paths_option!(opts, name) do
    case Keyword.fetch!(opts, :paths) do
      paths when is_list(paths) ->
        if Enum.empty?(paths) or Enum.any?(paths, &(not is_binary(&1))) do
          raise_paths_error!(name)
        end

      _paths ->
        raise_paths_error!(name)
    end
  end

  defp validate_filter_option!(opts, key, name) do
    case Keyword.fetch(opts, key) do
      {:ok, values} ->
        filter!(key, values, name)
        :ok

      :error ->
        :ok
    end
  end

  defp filter(opts, key, name) do
    values = Keyword.get(opts, key)

    filter!(key, values, name)
  end

  defp filter!(_key, nil, _name), do: nil

  defp filter!(key, values, name) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_filter_error!(key, name)
    end

    values
  end

  defp filter!(key, _values, name), do: raise_filter_error!(key, name)

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_paths_error!(name) do
    raise ArgumentError, "expected #{name} :paths to be a non-empty list of strings"
  end

  defp raise_schema_modules_error!(name) do
    raise ArgumentError, "expected #{name} :schema_modules to be a non-empty list of modules"
  end

  defp raise_filter_error!(key, name) do
    raise ArgumentError, "expected #{name} #{inspect(key)} to be a non-empty list of strings"
  end

  defp query_error_issue(target, schemas, tables, reason, config) do
    %Issue{
      check: config.check,
      target: target,
      message: config.query_error_message,
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schemas: schemas,
        tables: tables,
        reason: reason
      }
    }
  end

  defp value(row, key) do
    Map.get(row, key) || Map.fetch!(row, Map.fetch!(@row_keys, key))
  end
end
