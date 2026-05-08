defmodule Bylaw.Db.Adapters.Postgres.EctoChangesetConstraintOptions do
  @moduledoc false

  alias Bylaw.Db.Adapters.Postgres.RuleOptions

  @allowed_keys [:validate, :otp_app, :paths, :schema_modules, :rules, :schemas, :tables]
  @allowed_matcher_keys [:schema, :table, :constraint, :column]

  @type t :: Keyword.t()

  @doc false
  @spec normalize!(target :: term(), opts :: term(), check :: atom()) :: t()
  def normalize!(target, opts, check) when is_list(opts) do
    opts = RuleOptions.keyword_list!(opts, check)

    RuleOptions.validate_allowed_keys!(opts, @allowed_keys, check)

    opts = maybe_put_repo_otp_app(target, opts)

    RuleOptions.validate_boolean_option!(opts, :validate, check)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(opts, [:schemas, :tables], check)
      validate_schema_discovery_opts!(opts, check)
      validate_required_option!(opts, :paths, check)
      validate_schema_modules_option!(opts, check)
      validate_paths_option!(opts, check)
      RuleOptions.default_rules!(opts, check, @allowed_matcher_keys)
      RuleOptions.filter(opts, :schemas, check)
      RuleOptions.filter(opts, :tables, check)
    end

    opts
  end

  def normalize!(_target, opts, check) do
    RuleOptions.keyword_list!(opts, check)
  end

  @doc false
  @spec allowed_matcher_keys() :: list(atom())
  def allowed_matcher_keys, do: @allowed_matcher_keys

  defp maybe_put_repo_otp_app(%{repo: repo}, opts) when is_atom(repo) and not is_nil(repo) do
    if Keyword.has_key?(opts, :otp_app) or Keyword.has_key?(opts, :schema_modules) do
      opts
    else
      case repo_otp_app(repo) do
        nil -> opts
        otp_app -> Keyword.put(opts, :otp_app, otp_app)
      end
    end
  end

  defp maybe_put_repo_otp_app(_target, opts), do: opts

  defp repo_otp_app(repo) do
    if Code.ensure_loaded?(repo) and function_exported?(repo, :config, 0) do
      repo.config()[:otp_app]
    end
  end

  defp validate_schema_discovery_opts!(opts, check) do
    if not Keyword.has_key?(opts, :otp_app) and not Keyword.has_key?(opts, :schema_modules) do
      raise ArgumentError, "expected #{check} opts to include :otp_app or :schema_modules"
    end
  end

  defp validate_required_option!(opts, key, check) do
    if not Keyword.has_key?(opts, key) do
      raise ArgumentError, "expected #{check} opts to include #{inspect(key)}"
    end
  end

  defp validate_schema_modules_option!(opts, check) do
    case Keyword.fetch(opts, :schema_modules) do
      {:ok, modules} when is_list(modules) ->
        if Enum.empty?(modules) or Enum.any?(modules, &(not is_atom(&1))) do
          raise_schema_modules_error!(check)
        end

      {:ok, _modules} ->
        raise_schema_modules_error!(check)

      :error ->
        :ok
    end
  end

  defp validate_paths_option!(opts, check) do
    case Keyword.fetch!(opts, :paths) do
      paths when is_list(paths) ->
        if Enum.empty?(paths) or Enum.any?(paths, &(not is_binary(&1))) do
          raise_paths_error!(check)
        end

      _paths ->
        raise_paths_error!(check)
    end
  end

  defp raise_paths_error!(check) do
    raise ArgumentError, "expected #{check} :paths to be a non-empty list of strings"
  end

  defp raise_schema_modules_error!(check) do
    raise ArgumentError, "expected #{check} :schema_modules to be a non-empty list of modules"
  end
end
