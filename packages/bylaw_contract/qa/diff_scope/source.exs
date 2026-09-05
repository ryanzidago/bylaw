defmodule BylawDiffScope.Source do
  @moduledoc false
  @git_local_env ~w(GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX GIT_SHALLOW_FILE GIT_COMMON_DIR)

  @doc false
  @spec base(keyword(), String.t() | nil) :: {:ok, String.t() | :all} | {:error, list(map())}
  def base(options, environment) do
    case Keyword.get(options, :diff_base, environment) do
      value when value in [nil, false] -> {:ok, :all}
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, [%{code: :invalid_base}]}
    end
  end

  @doc false
  @spec select(map(), map()) ::
          {:ok, MapSet.t({module(), atom(), arity()})} | {:error, list(map())}
  def select(before_files, after_files),
    do: Bylaw.Contract.SourceSelection.select(before_files, after_files)

  @doc false
  @spec git_select(String.t(), String.t(), list(String.t())) ::
          {:ok, map()} | {:error, list(map())}
  def git_select(directory, reference, paths \\ ["lib"]) do
    with {:ok, ref} when ref != :all <- base([diff_base: reference], nil),
         {:ok, head} <- git(directory, ["rev-parse", "--verify", "HEAD^{commit}"]),
         {:ok, base} <-
           git(directory, ["rev-parse", "--verify", "--end-of-options", ref <> "^{commit}"]),
         {:ok, merge_base} <- git(directory, ["merge-base", base, head]),
         {:ok, status} <-
           git(directory, ["status", "--porcelain", "--untracked-files=all", "--" | paths]),
         :ok <- clean(status),
         {:ok, names} <-
           git(directory, [
             "diff",
             "--name-only",
             "--no-renames",
             "-z",
             merge_base,
             head,
             "--" | paths
           ]),
         names <-
           names
           |> String.split(<<0>>, trim: true)
           |> Enum.filter(&(Path.extname(&1) in [".ex", ".exs"])),
         {:ok, before} <- revision_files(directory, merge_base, names),
         {:ok, current} <- revision_files(directory, head, names),
         {:ok, selected} <- select(before, current) do
      {:ok, %{head: head, base: base, merge_base: merge_base, selected: selected, files: names}}
    else
      {:error, _} = error -> error
      _ -> {:error, [%{code: :invalid_base}]}
    end
  end

  defp clean(""), do: :ok
  defp clean(_), do: {:error, [%{code: :dirty_source}]}

  defp revision_files(directory, revision, names) do
    with {:ok, listing} <- git(directory, ["ls-tree", "-r", "--name-only", "-z", revision]) do
      available = MapSet.new(String.split(listing, <<0>>, trim: true))

      Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, files} ->
        if MapSet.member?(available, name) do
          case git(directory, ["show", revision <> ":" <> name], false) do
            {:ok, text} -> {:cont, {:ok, Map.put(files, name, text)}}
            error -> {:halt, error}
          end
        else
          {:cont, {:ok, files}}
        end
      end)
    end
  end

  defp git(directory, args, trim \\ true) do
    if !File.dir?(directory), do: raise(ArgumentError, "repository directory is unavailable")

    case System.cmd("git", args,
           cd: directory,
           stderr_to_stdout: true,
           env: Enum.map(@git_local_env, &{&1, nil})
         ) do
      {output, 0} ->
        {:ok, if(trim, do: String.trim_trailing(output, "\n"), else: output)}

      {output, status} ->
        {:error, [%{code: :git_error, command: args, status: status, detail: output}]}
    end
  rescue
    error in [ErlangError, ArgumentError] ->
      {:error, [%{code: :git_unavailable, detail: Exception.message(error)}]}
  end
end
