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

  The repo argument expects an Ecto SQL repo at runtime. Bylaw keeps Ecto SQL as
  an optional integration; callers must have `ecto_sql` and a Postgres driver in
  their application when they use repo-backed targets.

  ## Rules DSL

  Every built-in Postgres check can be scoped with `rules:`. Scope is shared
  across checks; each check defines any additional rule options it needs. Checks
  with default behavior can be passed as bare modules to run globally. Use
  `{Check, rules: [...]}` when a check needs required rule options or should run
  only for matching database objects.

  Shared scope keys are `where:` and `except:`. `where:` applies a rule when any
  matcher matches, and `except:` suppresses a rule that would otherwise match.
  Matchers use plural keys with non-empty list values, such as `schemas:`,
  `tables:`, `columns:`, `constraints:`, `types:`, `referenced_tables:`, and
  `referenced_columns:` where supported by the check.

  Top-level `validate: false` disables the whole check. Checks with no
  check-specific rule options accept only shared scope keys inside rules.
  Checks with required rule options document those options in their module docs
  with copyable rule examples.

  ## Examples

      Bylaw.Db.Adapters.Postgres.validate(
        MyApp.Repo,
        [
          Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes
        ]
      )
  """

  @behaviour Bylaw.Db.Adapter

  alias Bylaw.Db
  alias Bylaw.Db.Check
  alias Bylaw.Db.Target

  @typedoc false
  @type target_opt ::
          {:repo, module()}
          | {:dynamic_repo, atom() | pid() | nil}
          | {:query, Target.query_fun()}
          | {:meta, map()}

  @typedoc false
  @type target_opts :: list(target_opt())

  @typedoc """
  Option accepted by `validate/3`.
  """
  @type validate_opt :: {:dynamic_repo, atom() | pid() | nil}

  @typedoc """
  Options accepted by `validate/3`.
  """
  @type validate_opts :: list(validate_opt())

  @doc false
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
  Runs checks against one Postgres repo.

  Pass the repo and checks. Use `:dynamic_repo` when validating a specific
  dynamic repo with `validate/3`. To validate multiple repos, call this function
  once per repo.
  """
  @impl Bylaw.Db.Adapter
  @spec validate(repo :: module(), checks :: list(Db.check_spec())) :: Check.result()
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
  Runs checks against one Postgres repo with options.

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

  @doc false
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
