defmodule Bylaw.Db.Adapters.Postgres do
  @moduledoc """
  Postgres database adapter entrypoint.

  This adapter validates one Postgres repo per call:

      Bylaw.Db.Adapters.Postgres.validate(
        MyApp.Repo,
        [
          Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes
        ]
      )

  Pass `:dynamic_repo` when the call should run against one dynamic repo.
  Validate multiple repos by calling `validate/2` or `validate/3` once per repo.

  The `:repo` option expects an Ecto SQL repo at runtime. Bylaw keeps Ecto SQL as
  an optional integration; callers must have `ecto_sql` and a Postgres driver in
  their application when they use repo-backed targets.

  ## Examples

      iex> query = fn _target, _sql, _params, _opts -> {:ok, %{rows: [[1]]}} end
      iex> target = Bylaw.Db.Adapters.Postgres.target(query: query, meta: %{database: :primary})
      iex> target.adapter
      Bylaw.Db.Adapters.Postgres
      iex> target.meta
      %{database: :primary}
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
  Option accepted by `validate/3`.
  """
  @type validate_opt :: {:dynamic_repo, atom() | pid() | nil}

  @typedoc """
  Options accepted by `validate/3`.
  """
  @type validate_opts :: list(validate_opt())

  @doc """
  Builds a single Postgres validation target.

  Pass either `:repo` for an Ecto SQL-backed target or `:query` for a custom
  query callback used by tests or custom integrations.

  ## Examples

      iex> query = fn _target, _sql, _params, _opts -> {:ok, %{rows: []}} end
      iex> target = Bylaw.Db.Adapters.Postgres.target(query: query)
      iex> is_function(target.query, 4)
      true

      iex> Bylaw.Db.Adapters.Postgres.target([])
      ** (ArgumentError) expected Postgres target to include :repo or a four-arity :query
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
  Builds one Postgres target and runs checks against it.

  Pass the repo and checks. Use `:dynamic_repo` when validating a specific
  dynamic repo with `validate/3`. To validate multiple repos, call this function
  once per repo.

  This function also serves the lower-level `Bylaw.Db.Adapter` callback when the
  first argument is a list of Postgres targets.
  """
  @impl Bylaw.Db.Adapter
  @spec validate(repo :: module(), checks :: list(Db.check_spec())) :: Check.result()
  @spec validate(targets :: list(Target.t()), checks :: list(Db.check_spec())) :: Check.result()
  def validate(repo, checks) when is_atom(repo) and not is_nil(repo) do
    validate(repo, checks, [])
  end

  def validate(targets, checks) when is_list(targets) do
    checks = validate_checks!(checks)

    validate_postgres_targets!(targets)
    Enum.each(targets, &validate_postgres_target!/1)

    Db.validate(targets, checks)
  end

  def validate(repo, _checks) do
    raise ArgumentError,
          "expected Postgres repo to be a module or Postgres targets to be a list, got: #{inspect(repo)}"
  end

  @doc """
  Builds one Postgres target with options and runs checks against it.

  The only supported option is `:dynamic_repo`.
  """
  @spec validate(repo :: module(), checks :: list(Db.check_spec()), opts :: validate_opts()) ::
          Check.result()
  def validate(repo, checks, opts) when is_atom(repo) and not is_nil(repo) do
    keyword_list!(opts, "Postgres validation opts")
    validate_validate_opts!(opts)

    target =
      opts
      |> Keyword.put(:repo, repo)
      |> target()

    validate([target], validate_checks!(checks))
  end

  def validate(repo, _checks, _opts) do
    raise ArgumentError,
          "expected Postgres repo to be a module, got: #{inspect(repo)}"
  end

  @doc """
  Executes introspection SQL for a Postgres target.

  Repo-backed targets use `Ecto.Adapters.SQL.query/4`. If `:dynamic_repo` is set,
  the adapter temporarily routes the current process to that dynamic repo and
  restores the previous value afterward.

  ## Examples

      iex> query = fn target, sql, params, opts ->
      ...>   {:ok, %{adapter: target.adapter, sql: sql, params: params, opts: opts}}
      ...> end
      iex> target = Bylaw.Db.Adapters.Postgres.target(query: query)
      iex> Bylaw.Db.Adapters.Postgres.query(target, "select $1", [1], timeout: 1_000)
      {:ok, %{adapter: Bylaw.Db.Adapters.Postgres, params: [1], sql: "select $1", opts: [timeout: 1000]}}
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

  defp validate_validate_opts!(opts) do
    allowed_keys = [:dynamic_repo]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown Postgres validation option: #{inspect(key)}"
      end
    end)

    :ok
  end

  defp valid_repo?(repo), do: is_atom(repo) and not is_nil(repo)

  defp valid_query_source?(repo, query) do
    valid_repo?(repo) or is_function(query, 4)
  end

  defp keyword_list!(opts, label) do
    if not is_list(opts) or not Keyword.keyword?(opts) do
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
