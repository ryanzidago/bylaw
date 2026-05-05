defmodule Bylaw.Db.Adapters.Postgres do
  @moduledoc """
  Postgres database adapter entrypoint.

  This adapter validates explicit targets. Each target represents one Postgres
  query source:

      Bylaw.Db.Adapters.Postgres.validate(
        repo: MyApp.Repo,
        checks: [
          Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
          {Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType, type: "uuid"}
        ]
      )

  Or configure the target and checks once:

      config :bylaw, Bylaw.Db.Adapters.Postgres,
        repo: MyApp.Repo,
        checks: [
          {Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType,
           rules: [[where: [schema: "public"], type: "uuid"]],
           except: [[table: "schema_migrations"]]},
          {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
           rules: [[where: [schema: "public"], columns: ["tenant_id"]]],
           except: [[table: "schema_migrations"]]}
        ]

      Bylaw.Db.Adapters.Postgres.validate()

  The `:repo` option expects an Ecto SQL repo at runtime. Bylaw keeps Ecto SQL as
  an optional integration; callers must have `ecto_sql` and a Postgres driver in
  their application when they use repo-backed targets.
  """

  @behaviour Bylaw.Db.Adapter

  alias Bylaw.Db
  alias Bylaw.Db.Check
  alias Bylaw.Db.Target

  @typedoc """
  Option accepted by `target/1`.
  """
  @type target_opt ::
          {:repo, module()}
          | {:dynamic_repo, atom() | pid() | nil}
          | {:query, Target.query_fun()}
          | {:meta, map()}

  @typedoc """
  Options accepted by `target/1`.
  """
  @type target_opts :: list(target_opt())

  @typedoc """
  Option accepted by configured validation.
  """
  @type validate_opt ::
          {:checks, list(Db.check_spec())}
          | target_opt()
          | {:target, target_opts() | Target.t()}
          | {:targets, list(target_opts() | Target.t())}

  @typedoc """
  Options accepted by configured validation.
  """
  @type validate_opts :: list(validate_opt())

  @doc """
  Builds a single Postgres validation target.

  Pass either `:repo` for an Ecto SQL-backed target or `:query` for a custom
  query callback used by tests or custom integrations.
  """

  @impl Bylaw.Db.Adapter
  @spec target(opts :: target_opts()) :: Target.t()
  def target(opts) when is_list(opts) do
    keyword_list!(opts, "Postgres target opts")
    validate_target_opts!(opts)

    %Target{
      adapter: __MODULE__,
      repo: Keyword.get(opts, :repo),
      dynamic_repo: Keyword.get(opts, :dynamic_repo),
      query: Keyword.get(opts, :query),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  def target(opts) do
    raise ArgumentError,
          "expected Postgres target opts to be a keyword list, got: #{inspect(opts)}"
  end

  @doc """
  Runs checks from `config :bylaw, Bylaw.Db.Adapters.Postgres`.

  The configured value must include `:checks` and either top-level target
  options like `repo: MyApp.Repo`, a single `:target`, or a non-empty `:targets`
  list.
  """
  @spec validate() :: Check.result()
  def validate do
    :bylaw
    |> Application.get_env(__MODULE__, [])
    |> validate()
  end

  @doc """
  Builds Postgres targets from configuration and runs configured checks.

  This is the convenient consumer-facing entrypoint for one-off validation.
  Pass `:checks` plus either top-level target options, `:target`, or `:targets`.
  """
  @spec validate(opts :: validate_opts()) :: Check.result()
  def validate(opts) when is_list(opts) do
    keyword_list!(opts, "Postgres validation config")
    validate_config_opts!(opts)

    opts
    |> config_targets!()
    |> validate(config_checks!(opts))
  end

  def validate(opts) do
    raise ArgumentError,
          "expected Postgres validation config to be a keyword list, got: #{inspect(opts)}"
  end

  @doc """
  Runs checks against a non-empty list of Postgres targets.

  Invalid target and check arguments raise `ArgumentError`.
  """

  @impl Bylaw.Db.Adapter
  @spec validate(targets :: list(Target.t()), checks :: list(Db.check_spec())) :: Check.result()
  def validate(targets, checks) do
    checks = validate_checks!(checks)

    validate_postgres_targets!(targets)
    Enum.each(targets, &validate_postgres_target!/1)

    Db.validate(targets, checks)
  end

  @doc """
  Executes introspection SQL for a Postgres target.

  Repo-backed targets use `Ecto.Adapters.SQL.query/4`. If `:dynamic_repo` is set,
  the adapter temporarily routes the current process to that dynamic repo and
  restores the previous value afterward.
  """

  @impl Bylaw.Db.Adapter
  @spec query(
          target :: Target.t(),
          sql :: String.t(),
          params :: list(term()),
          opts :: Bylaw.Db.Adapter.query_opts()
        ) :: {:ok, term()} | {:error, term()}
  def query(%Target{adapter: __MODULE__} = target, sql, params, opts)
      when is_binary(sql) and is_list(params) and is_list(opts) do
    cond do
      is_function(target.query, 4) ->
        target.query.(target, sql, params, opts)

      valid_repo?(target.repo) ->
        repo_query(target, sql, params, opts)

      true ->
        {:error, :missing_query_source}
    end
  end

  def query(%Target{adapter: __MODULE__}, _sql, _params, _opts) do
    {:error, :missing_query_source}
  end

  defp repo_query(target, sql, params, opts) do
    with {:module, _module} <- Code.ensure_loaded(Ecto.Adapters.SQL),
         :ok <- ensure_dynamic_repo_support(target) do
      with_dynamic_repo(target, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Ecto.Adapters.SQL, :query, [target.repo, sql, params, opts])
      end)
    else
      {:error, :nofile} -> {:error, {:missing_dependency, :ecto_sql}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_target_opts!(opts) do
    allowed_keys = [:repo, :dynamic_repo, :query, :meta]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown Postgres target option: #{inspect(key)}"
      end
    end)

    if not valid_query_source?(Keyword.get(opts, :repo), Keyword.get(opts, :query)) do
      raise ArgumentError, "expected Postgres target to include :repo or a four-arity :query"
    end
  end

  defp validate_config_opts!(opts) do
    allowed_keys = [:checks, :repo, :dynamic_repo, :query, :meta, :target, :targets]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown Postgres validation option: #{inspect(key)}"
      end
    end)

    has_top_level_target_opts? =
      opts
      |> Keyword.take([:repo, :dynamic_repo, :query, :meta])
      |> Enum.any?()

    target_source_count =
      Enum.count(
        [
          Keyword.has_key?(opts, :target),
          Keyword.has_key?(opts, :targets),
          has_top_level_target_opts?
        ],
        & &1
      )

    if target_source_count != 1 do
      raise ArgumentError,
            "expected Postgres validation config to include exactly one target source"
    end

    :ok
  end

  defp config_targets!(opts) do
    cond do
      Keyword.has_key?(opts, :target) ->
        [config_target!(Keyword.fetch!(opts, :target))]

      Keyword.has_key?(opts, :targets) ->
        opts
        |> Keyword.fetch!(:targets)
        |> config_targets_from_list!()

      true ->
        opts
        |> Keyword.take([:repo, :dynamic_repo, :query, :meta])
        |> target()
        |> List.wrap()
    end
  end

  defp config_target!(%Target{adapter: __MODULE__} = target), do: target

  defp config_target!(%Target{} = target) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  defp config_target!(opts) when is_list(opts) do
    keyword_list!(opts, "Postgres validation target opts")
    target(opts)
  end

  defp config_target!(target) do
    raise ArgumentError,
          "expected Postgres validation target to be a target or keyword list, got: #{inspect(target)}"
  end

  defp config_targets_from_list!(targets) when is_list(targets) do
    if Enum.empty?(targets) do
      raise ArgumentError, "expected Postgres validation :targets to be a non-empty list"
    end

    Enum.map(targets, &config_target!/1)
  end

  defp config_targets_from_list!(targets) do
    raise ArgumentError,
          "expected Postgres validation :targets to be a non-empty list, got: #{inspect(targets)}"
  end

  defp config_checks!(opts) do
    case Keyword.fetch(opts, :checks) do
      {:ok, checks} -> validate_checks!(checks)
      :error -> raise(ArgumentError, "expected Postgres validation config to include :checks")
    end
  end

  defp valid_repo?(repo), do: is_atom(repo) and not is_nil(repo)

  defp valid_query_source?(repo, query) do
    valid_repo?(repo) or is_function(query, 4)
  end

  defp keyword_list!(opts, label) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError, "expected #{label} to be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp validate_postgres_target!(%Target{adapter: __MODULE__} = target) do
    if not valid_query_source?(target.repo, target.query) do
      raise ArgumentError, "expected Postgres target to include :repo or a four-arity :query"
    end

    :ok
  end

  defp validate_postgres_target!(target) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  defp validate_postgres_targets!([]),
    do: raise(ArgumentError, "expected at least one Postgres target")

  defp validate_postgres_targets!(targets) when is_list(targets), do: :ok

  defp validate_postgres_targets!(targets) do
    raise ArgumentError, "expected Postgres targets to be a list, got: #{inspect(targets)}"
  end

  defp validate_checks!(checks) when is_list(checks), do: checks

  defp validate_checks!(checks) do
    raise ArgumentError, "expected checks to be a list, got: #{inspect(checks)}"
  end

  defp ensure_dynamic_repo_support(%Target{dynamic_repo: nil}), do: :ok

  defp ensure_dynamic_repo_support(%Target{} = target) do
    if function_exported?(target.repo, :get_dynamic_repo, 0) and
         function_exported?(target.repo, :put_dynamic_repo, 1) do
      :ok
    else
      {:error, {:dynamic_repo_not_supported, target.repo}}
    end
  end

  defp with_dynamic_repo(%Target{dynamic_repo: nil}, fun), do: fun.()

  defp with_dynamic_repo(%Target{} = target, fun) do
    previous_dynamic_repo = target.repo.get_dynamic_repo()

    try do
      target.repo.put_dynamic_repo(target.dynamic_repo)
      fun.()
    after
      target.repo.put_dynamic_repo(previous_dynamic_repo)
    end
  end
end
