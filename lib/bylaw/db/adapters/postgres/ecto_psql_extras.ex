defmodule Bylaw.Db.Adapters.Postgres.EctoPsqlExtras do
  @moduledoc false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Target

  @spec query(Target.t(), atom(), keyword(), list(term())) :: {:ok, term()} | {:error, term()}
  def query(%Target{} = target, query_name, opts, params)
      when is_atom(query_name) and is_list(opts) and is_list(params) do
    if is_function(target.query, 4) do
      Postgres.query(target, query_label(query_name), params, [])
    else
      query_repo(target, query_name, opts)
    end
  end

  defp query_repo(target, query_name, opts) do
    with {:module, _module} <- Code.ensure_loaded(EctoPSQLExtras),
         :ok <- ensure_dynamic_repo_support(target) do
      {:ok,
       with_dynamic_repo(target, fn -> apply(EctoPSQLExtras, query_name, [target.repo, opts]) end)}
    else
      {:error, :nofile} -> {:error, {:missing_dependency, :ecto_psql_extras}}
      {:error, reason} -> {:error, reason}
    end
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp query_label(query_name), do: "ecto_psql_extras.#{query_name}"

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
