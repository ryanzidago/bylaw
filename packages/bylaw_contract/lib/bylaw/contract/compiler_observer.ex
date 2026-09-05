defmodule Bylaw.Contract.CompilerObserver do
  @moduledoc false

  @table __MODULE__

  @doc false
  @spec start() :: integer()
  def start do
    ensure_table()
    System.unique_integer([:positive, :monotonic])
  end

  @doc false
  @spec hit(
          token :: integer(),
          mfa :: {module(), atom(), arity()},
          clause :: pos_integer()
        ) :: :ok
  def hit(token, mfa, clause) do
    key = {token, mfa, clause}
    :ets.update_counter(@table, key, {2, 1}, {key, 0})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc false
  @spec counts(token :: integer()) ::
          %{{{module(), atom(), arity()}, pos_integer()} => non_neg_integer()}
  def counts(token) do
    ensure_table()

    Map.new(:ets.tab2list(@table), fn
      {{^token, mfa, clause}, count} -> {{mfa, clause}, count}
      _ -> {nil, nil}
    end)
    |> Map.delete(nil)
  end

  @doc false
  @spec stop(token :: integer()) :: :ok
  def stop(token) do
    if :ets.whereis(@table) != :undefined do
      :ets.match_delete(@table, {{token, :_, :_}, :_})
    end

    :ok
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    end

    :ok
  rescue
    ArgumentError -> :ok
  end
end
