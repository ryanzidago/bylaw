defmodule Bylaw.Ecto.Query.CheckOptions do
  @moduledoc false

  # `label` distinguishes top-level Bylaw option lists from nested check option
  # lists in exception messages.
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

  # Most checks can reject unknown options centrally. Checks with more detailed
  # option validation pass `:any` and validate their own shape.
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

  # Only explicit `validate: false` disables a check; missing or truthy values
  # keep validation enabled.
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  # Configured checks use `:any` by default and may opt into `:all` when every
  # configured key must match. Any other value is treated as invalid config.
  @spec match!(keyword()) :: :any | :all
  def match!(opts) do
    case Keyword.get(opts, :match, :any) do
      match when match in [:any, :all] ->
        match

      match ->
        raise ArgumentError, "expected :match to be :any or :all, got: #{inspect(match)}"
    end
  end

  # Required field/key options must be non-empty so a configured check cannot
  # silently become a no-op through ambiguous empty input.
  @spec fetch_non_empty_atoms!(keyword(), atom()) :: list(atom())
  def fetch_non_empty_atoms!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} ->
        non_empty_atoms!(value, key)

      :error ->
        raise ArgumentError, "missing required #{inspect(key)} option"
    end
  end

  # Shared validator for `:keys` and `:fields` style options. Empty lists,
  # non-lists, and non-atom members are all configuration errors.
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

  # Pass `:any` when a check validates its own option keys; otherwise reject
  # unknown keys early so typos do not silently disable enforcement.
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
