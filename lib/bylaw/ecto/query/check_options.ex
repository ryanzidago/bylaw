defmodule Bylaw.Ecto.Query.CheckOptions do
  @moduledoc false

  @doc false
  @spec keyword_list!(term(), String.t()) :: keyword()
  def keyword_list!(opts, label) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
    else
      raise ArgumentError, "expected #{label} to be a keyword list, got: #{inspect(opts)}"
    end
  end

  def keyword_list!(opts, label) do
    raise ArgumentError, "expected #{label} to be a keyword list, got: #{inspect(opts)}"
  end

  @doc false
  @spec fetch!(list(), atom(), :any | list(atom())) :: list()
  def fetch!(opts, check_name, allowed_keys) when is_list(opts) do
    keyword_list!(opts, "opts")

    opts
    |> Keyword.get(check_name, [])
    |> normalize_check_opts!(check_name, allowed_keys)
  end

  @doc false
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  @doc false
  @spec match!(keyword()) :: :any | :all
  def match!(opts) do
    case Keyword.get(opts, :match, :any) do
      match when match in [:any, :all] ->
        match

      match ->
        raise ArgumentError, "expected :match to be :any or :all, got: #{inspect(match)}"
    end
  end

  @doc false
  @spec fetch_non_empty_atoms!(keyword(), atom()) :: list(atom())
  def fetch_non_empty_atoms!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        non_empty_atoms!(value, key)

      :error ->
        raise ArgumentError, "missing required #{inspect(key)} option"
    end
  end

  @doc false
  @spec non_empty_atoms!(term(), atom()) :: list(atom())
  def non_empty_atoms!([], key) do
    raise ArgumentError,
          "expected #{inspect(key)} to be a non-empty list of atoms, got: []"
  end

  def non_empty_atoms!(values, key) when is_list(values), do: Enum.map(values, &atom!(&1, key))

  def non_empty_atoms!(values, key) do
    raise ArgumentError,
          "expected #{inspect(key)} to be a non-empty list of atoms, got: #{inspect(values)}"
  end

  @doc false
  @spec validate_allowed_keys!(keyword(), atom(), list(atom())) :: :ok
  def validate_allowed_keys!(opts, check_name, allowed_keys) do
    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown #{inspect(check_name)} option: #{inspect(key)}"
      end
    end)
  end

  defp normalize_check_opts!(opts, _check_name, :any) when is_list(opts), do: opts

  defp normalize_check_opts!(opts, check_name, allowed_keys) when is_list(opts) do
    if Keyword.keyword?(opts) do
      validate_allowed_keys!(opts, check_name, allowed_keys)
      opts
    else
      raise ArgumentError,
            "expected #{inspect(check_name)} opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp normalize_check_opts!(opts, check_name, _allowed_keys) do
    raise ArgumentError,
          "expected #{inspect(check_name)} opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp atom!(value, _key) when is_atom(value), do: value

  defp atom!(value, key) do
    raise ArgumentError,
          "expected #{inspect(key)} to contain only atoms, got: #{inspect(value)}"
  end
end
