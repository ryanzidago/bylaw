defmodule Bylaw.Ecto.Query.CheckOptions do
  @moduledoc false

  @doc """
  Returns `opts` when it is a keyword list, otherwise raises `ArgumentError`.

  `label` is used in the exception message so callers can distinguish the
  top-level Bylaw option list from a nested check-specific option list.
  """
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

  @doc """
  Returns validated check-specific options.

  `allowed_keys` controls option validation:

    * pass a list of atoms to reject unknown option keys
    * pass `:any` when the check performs more detailed option validation itself

  A malformed option list or unknown key raises `ArgumentError`.
  """
  @spec normalize!(term(), :any | list(atom())) :: keyword()
  def normalize!(opts, allowed_keys) when is_list(opts) do
    if Keyword.keyword?(opts) do
      validate_allowed_keys!(opts, allowed_keys)
      opts
    else
      raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  def normalize!(opts, _allowed_keys) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  @doc """
  Returns whether a check should run for the given check-specific options.

  Only `validate: false` disables a check. Missing `:validate`, `validate: true`,
  and other values keep the check enabled.
  """
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  @doc """
  Returns the configured match mode.

  The accepted values are `:any` and `:all`; the default is `:any`. Any other
  value raises `ArgumentError`.
  """
  @spec match!(keyword()) :: :any | :all
  def match!(opts) do
    case Keyword.get(opts, :match, :any) do
      match when match in [:any, :all] ->
        match

      match ->
        raise ArgumentError, "expected :match to be :any or :all, got: #{inspect(match)}"
    end
  end

  @doc """
  Fetches `key` from `opts` and validates it as a non-empty list of atoms.

  This is useful for check options such as `:keys` or `:fields`, where an empty
  list would make the check configuration ambiguous. Missing keys and invalid
  values raise `ArgumentError`.
  """
  @spec fetch_non_empty_atoms!(keyword(), atom()) :: list(atom())
  def fetch_non_empty_atoms!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        non_empty_atoms!(value, key)

      :error ->
        raise ArgumentError, "missing required #{inspect(key)} option"
    end
  end

  @doc """
  Validates `values` as a non-empty list of atoms.

  Returns the atom list unchanged when valid. Empty lists, non-lists, and lists
  containing non-atoms raise `ArgumentError`.
  """
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

  @doc """
  Raises when `opts` contains keys outside `allowed_keys`.

  Returns `:ok` when every option key is allowed. Pass `:any` to allow all keys.
  """
  @spec validate_allowed_keys!(keyword(), :any | list(atom())) :: :ok
  def validate_allowed_keys!(_opts, :any), do: :ok

  def validate_allowed_keys!(opts, allowed_keys) do
    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown option: #{inspect(key)}"
      end
    end)
  end

  defp atom!(value, _key) when is_atom(value), do: value

  defp atom!(value, key) do
    raise ArgumentError,
          "expected #{inspect(key)} to contain only atoms, got: #{inspect(value)}"
  end
end
