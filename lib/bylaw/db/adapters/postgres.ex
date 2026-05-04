defmodule Bylaw.Db.Adapters.Postgres do
  @moduledoc """
  Postgres database adapter entrypoint.

  This adapter validates explicit targets. Each target represents one Postgres
  query source:

      target =
        Bylaw.Db.Adapters.Postgres.target(
          repo: MyApp.Repo
        )

      Bylaw.Db.Adapters.Postgres.validate([target], [
        Bylaw.Db.Postgres.Checks.ForeignKeyIndexes
      ])

  The `:repo` option expects an Ecto SQL repo at runtime. Bylaw keeps Ecto SQL as
  an optional integration; callers must have `ecto_sql` and a Postgres driver in
  their application when they use repo-backed targets.
  """

  @behaviour Bylaw.Db.Adapter

  alias Bylaw.Db
  alias Bylaw.Db.Check
  alias Bylaw.Db.Target

  @typedoc """
  Options accepted by `target/1`.
  """
  @type target_opts ::
          list(
            {:repo, module()}
            | {:dynamic_repo, atom() | pid() | nil}
            | {:query, Target.query_fun()}
            | {:meta, map()}
          )

  @doc """
  Builds a single Postgres validation target.

  Pass either `:repo` for an Ecto SQL-backed target or `:query` for a custom
  query callback used by tests or custom integrations.
  """

  @impl Bylaw.Db.Adapter
  @spec target(target_opts()) :: Target.t()
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
  Runs checks against a non-empty list of Postgres targets.

  Invalid target and check arguments raise `ArgumentError`.
  """

  @impl Bylaw.Db.Adapter
  @spec validate(list(Target.t()), list(Db.check_spec())) :: Check.result()
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
  @spec query(Target.t(), String.t(), list(term()), keyword()) :: {:ok, term()} | {:error, term()}
  def query(%Target{adapter: __MODULE__, query: query} = target, sql, params, opts)
      when is_function(query, 4) and is_binary(sql) and is_list(params) and is_list(opts) do
    query.(target, sql, params, opts)
  end

  def query(%Target{adapter: __MODULE__, repo: repo} = target, sql, params, opts)
      when is_atom(repo) and not is_nil(repo) and is_binary(sql) and is_list(params) and
             is_list(opts) do
    with {:module, _module} <- Code.ensure_loaded(Ecto.Adapters.SQL),
         :ok <- ensure_dynamic_repo_support(target) do
      with_dynamic_repo(target, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Ecto.Adapters.SQL, :query, [repo, sql, params, opts])
      end)
    else
      {:error, :nofile} -> {:error, {:missing_dependency, :ecto_sql}}
      {:error, reason} -> {:error, reason}
    end
  end

  def query(%Target{adapter: __MODULE__}, _sql, _params, _opts) do
    {:error, :missing_query_source}
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

  defp valid_query_source?(repo, query) do
    (is_atom(repo) and not is_nil(repo)) or is_function(query, 4)
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

  defp ensure_dynamic_repo_support(%Target{repo: repo}) do
    if function_exported?(repo, :get_dynamic_repo, 0) and
         function_exported?(repo, :put_dynamic_repo, 1) do
      :ok
    else
      {:error, {:dynamic_repo_not_supported, repo}}
    end
  end

  defp with_dynamic_repo(%Target{dynamic_repo: nil}, fun), do: fun.()

  defp with_dynamic_repo(%Target{repo: repo, dynamic_repo: dynamic_repo}, fun) do
    previous_dynamic_repo = repo.get_dynamic_repo()

    try do
      repo.put_dynamic_repo(dynamic_repo)
      fun.()
    after
      repo.put_dynamic_repo(previous_dynamic_repo)
    end
  end
end
