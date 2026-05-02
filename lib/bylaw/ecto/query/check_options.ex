defmodule Bylaw.Ecto.Query.CheckOptions do
  @moduledoc """
  Option parsing helpers for Ecto query checks.

  Query checks usually receive one top-level Bylaw keyword list and then read
  their own namespaced options from it:

      [
        mandatory_where_keys: [
          validate: true,
          keys: [:organisation_id]
        ]
      ]

  This module keeps the validation rules consistent across built-in and custom
  checks. Helpers fail with `ArgumentError` when options are malformed, because
  invalid check configuration is a caller error and should be caught before a
  query is allowed to run.
  """

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
  Fetches and validates the option list for `check_name`.

  The function expects the top-level `opts` to be a keyword list. It returns the
  nested option list stored under `check_name`, or an empty list when the check
  has no configured options.

  `allowed_keys` controls nested option validation:

    * pass a list of atoms to reject unknown nested option keys
    * pass `:any` when the check performs more detailed option validation itself

  A malformed top-level option list, malformed nested option list, or unknown
  nested key raises `ArgumentError`.
  """
  @spec fetch!(list(), atom(), :any | list(atom())) :: list()
  def fetch!(opts, check_name, allowed_keys) when is_list(opts) do
    keyword_list!(opts, "opts")

    opts
    |> Keyword.get(check_name, [])
    |> normalize_check_opts!(check_name, allowed_keys)
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

  Returns `:ok` when every option key is allowed. The `check_name` is included in
  the error message to point callers at the misconfigured check namespace.
  """
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
