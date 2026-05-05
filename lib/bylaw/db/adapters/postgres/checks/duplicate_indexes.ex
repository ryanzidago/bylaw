defmodule Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes do
  @moduledoc """
  Validates that Postgres does not have duplicate indexes.

  The check uses `ecto_psql_extras` to find groups of indexes with the same set
  of columns, opclass, expression, and predicate.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.EctoPsqlExtras
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @type check_opts :: list({:validate, boolean()})
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "idx1" => :idx1,
    "idx2" => :idx2,
    "idx3" => :idx3,
    "idx4" => :idx4,
    "size" => :size
  }

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Db.Check
  @spec name() :: :duplicate_indexes
  def name, do: :duplicate_indexes

  @doc """
  Validates that the target does not have duplicate indexes.

  The check is enabled by default. Pass `validate: false` to skip it.
  """

  @impl Bylaw.Db.Check
  @spec validate(Target.t(), check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_duplicate_indexes(target)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected duplicate_indexes opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_duplicate_indexes(target) do
    case EctoPsqlExtras.query(target, :duplicate_indexes, [format: :raw], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.map(&issue(target, &1))
        |> result()

      {:error, reason} ->
        {:error, [query_error_issue(target, reason)]}
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

  defp rows(rows) when is_list(rows) do
    Enum.map(rows, fn
      [size, idx1, idx2, idx3, idx4] ->
        %{"size" => size, "idx1" => idx1, "idx2" => idx2, "idx3" => idx3, "idx4" => idx4}

      row ->
        row
    end)
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp check_opts!(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected duplicate_indexes opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown duplicate_indexes option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)

    opts
  end

  defp validate_boolean_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "expected duplicate_indexes #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
  end

  @spec issue(Target.t(), result_row()) :: Issue.t()
  defp issue(target, row) do
    indexes = indexes(row)

    %Issue{
      check: __MODULE__,
      target: target,
      message: "expected duplicate indexes #{Enum.join(indexes, ", ")} to be consolidated",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        size: value(row, "size"),
        indexes: indexes,
        source: :ecto_psql_extras
      }
    }
  end

  @spec query_error_issue(Target.t(), term()) :: Issue.t()
  defp query_error_issue(target, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres duplicate indexes",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        reason: reason
      }
    }
  end

  defp indexes(row) do
    ["idx1", "idx2", "idx3", "idx4"]
    |> Enum.map(&value(row, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp value(row, key) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(row, Map.fetch!(@row_keys, key))
    end
  end
end
