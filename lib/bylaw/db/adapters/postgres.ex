defmodule Bylaw.Db.Adapters.Postgres do
  @moduledoc """
  Postgres database adapter entrypoint.

  This adapter validates explicit targets. Each target represents one
  adapter/database/schema combination:

      target =
        Bylaw.Db.Adapters.Postgres.target(:primary_public,
          repo: MyApp.Repo,
          schema: "public"
        )

      Bylaw.Db.Adapters.Postgres.validate(target, [
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

  @ecto_sql Module.concat([Ecto, Adapters, SQL])

  @typedoc """
  Options accepted by `target/2`.
  """
  @type target_opts ::
          list(
            {:repo, module()}
            | {:dynamic_repo, atom() | pid() | nil}
            | {:schema, String.t()}
            | {:query, Target.query_fun()}
            | {:meta, map()}
          )

  @doc """
  Builds a single Postgres validation target.

  Pass either `:repo` for an Ecto SQL-backed target or `:query` for a custom
  query callback used by tests or custom integrations. `:schema` is required.
  """

  @impl Bylaw.Db.Adapter
  @spec target(atom(), target_opts()) :: Target.t()
  def target(name, opts) when is_atom(name) and is_list(opts) do
    validate_target_opts!(opts)

    %Target{
      adapter: __MODULE__,
      name: name,
      repo: Keyword.get(opts, :repo),
      dynamic_repo: Keyword.get(opts, :dynamic_repo),
      schema: fetch_schema!(opts),
      query: Keyword.get(opts, :query),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @doc """
  Runs checks against one Postgres target or a list of Postgres targets.
  """

  @impl Bylaw.Db.Adapter
  @spec validate(Target.t() | list(Target.t()), list(Db.check_spec())) :: Check.result()
  def validate(target_or_targets, checks) when is_list(checks) do
    targets = postgres_targets!(target_or_targets)

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
      when is_atom(repo) and is_binary(sql) and is_list(params) and is_list(opts) do
    with {:module, _module} <- Code.ensure_loaded(@ecto_sql),
         :ok <- ensure_dynamic_repo_support(target) do
      with_dynamic_repo(target, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(@ecto_sql, :query, [repo, sql, params, opts])
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
    allowed_keys = [:repo, :dynamic_repo, :schema, :query, :meta]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown Postgres target option: #{inspect(key)}"
      end
    end)

    if is_nil(Keyword.get(opts, :repo)) and not is_function(Keyword.get(opts, :query), 4) do
      raise ArgumentError, "expected Postgres target to include :repo or a four-arity :query"
    end
  end

  defp fetch_schema!(opts) do
    case Keyword.fetch(opts, :schema) do
      {:ok, schema} when is_binary(schema) and byte_size(schema) > 0 ->
        schema

      {:ok, schema} ->
        raise ArgumentError,
              "expected Postgres target :schema to be a non-empty string, got: #{inspect(schema)}"

      :error ->
        raise ArgumentError, "missing required Postgres target option: :schema"
    end
  end

  defp validate_postgres_target!(%Target{adapter: __MODULE__}), do: :ok

  defp validate_postgres_target!(target) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  defp postgres_targets!(%Target{} = target), do: [target]
  defp postgres_targets!(targets) when is_list(targets), do: targets

  defp postgres_targets!(target) do
    raise ArgumentError, "expected a Postgres target or list of targets, got: #{inspect(target)}"
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
