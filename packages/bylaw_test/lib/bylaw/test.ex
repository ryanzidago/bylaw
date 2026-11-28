defmodule Bylaw.Test do
  @moduledoc "Assertions shared by Bylaw consumer test tasks."

  @run_key {__MODULE__, :selected_repos}

  @doc """
  Fails when `repo` is selected by the active `bylaw_test.without_ecto_repo` run.

  The assertion is a no-op during ordinary ExUnit runs and when the repo was not
  selected for the active task.
  """
  @spec require_repo!(module(), map()) :: :ok
  def require_repo!(repo, exunit_context) when is_atom(repo) and is_map(exunit_context) do
    case :persistent_term.get(@run_key, :inactive) do
      :inactive ->
        :ok

      selected when is_list(selected) ->
        if repo in selected do
          case_module = Map.get(exunit_context, :module) || Map.get(exunit_context, :case)

          raise ExUnit.AssertionError,
            message:
              "#{inspect(repo)} is required by case #{inspect(case_module)}, " <>
                "which cannot run in a without-repo test"
        end

        :ok
    end
  end

  @doc false
  @spec activate_run(list(module())) :: :ok
  def activate_run(repos) when is_list(repos) do
    :persistent_term.put(@run_key, repos)
    :ok
  end

  @doc false
  @spec deactivate_run() :: :ok
  def deactivate_run do
    :persistent_term.erase(@run_key)
    :ok
  end
end
