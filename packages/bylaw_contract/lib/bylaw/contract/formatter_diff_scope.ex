defmodule Bylaw.Contract.FormatterDiffScope do
  @moduledoc false
  alias Bylaw.Contract.SourceSelection

  @git_env ~w(GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX GIT_SHALLOW_FILE GIT_COMMON_DIR)

  @doc false
  @spec base(options :: keyword()) :: {:ok, :all | String.t()} | {:error, term()}
  def base(options) do
    case Keyword.fetch(options, :diff_base) do
      {:ok, false} ->
        {:ok, :all}

      {:ok, value} ->
        reference(value)

      :error ->
        case System.get_env("BYLAW_CONTRACT_DIFF_BASE") do
          nil -> {:ok, :all}
          value -> reference(value)
        end
    end
  end

  defp reference(value) when is_binary(value) do
    if String.trim(value) == "" do
      {:error, :invalid_diff_base}
    else
      {:ok, value}
    end
  end

  defp reference(_), do: {:error, :invalid_diff_base}

  @doc false
  @spec options(modules :: list(module()), options :: keyword(), base :: tuple()) ::
          {:ok, keyword()} | {:error, term()}
  def options(_modules, _options, {:error, _} = error), do: error
  def options(_modules, options, {:ok, :all}), do: {:ok, observer_options(options)}

  def options(modules, options, {:ok, reference}) do
    directory = Keyword.get(options, :diff_root, File.cwd!())
    paths = Keyword.get(options, :diff_paths, ["lib"])

    with :ok <- valid_paths(paths),
         true <- is_binary(directory) or {:error, :invalid_diff_root},
         {:ok, root} <- git(directory, ["rev-parse", "--show-toplevel"]),
         prefix <- Path.relative_to(Path.expand(directory), root),
         paths <- Enum.map(paths, &relative_path(prefix, &1)),
         {:ok, head} <- git(root, ["rev-parse", "--verify", "HEAD^{commit}"]),
         {:ok, base} <-
           git(root, ["rev-parse", "--verify", "--end-of-options", reference <> "^{commit}"]),
         {:ok, merge_base} <- git(root, ["merge-base", base, head]),
         {:ok, status} <-
           git(root, [
             "status",
             "--porcelain",
             "--untracked-files=all",
             "--" | literal_paths(paths)
           ]),
         :ok <- clean(status),
         {:ok, names} <-
           git(
             root,
             [
               "diff",
               "--name-only",
               "--no-renames",
               "-z",
               merge_base,
               head,
               "--" | literal_paths(paths)
             ],
             false
           ),
         names <-
           String.split(names, <<0>>, trim: true)
           |> Enum.filter(&(Path.extname(&1) in [".ex", ".exs"])),
         {:ok, before} <- files(root, merge_base, names),
         {:ok, current} <- files(root, head, names),
         {:ok, selected} <- SourceSelection.select(before, current),
         :ok <- application_selection(modules, selected),
         :ok <- Bylaw.Contract.FormatterCompiledSource.validate(root, head, selected),
         {:ok, ^head} <- git(root, ["rev-parse", "HEAD"]) do
      {:ok, Keyword.put(observer_options(options), :only, Enum.sort(selected))}
    else
      {:error, _} = error -> error
      _ -> {:error, :tested_head_changed}
    end
  end

  defp observer_options(options), do: Keyword.drop(options, [:diff_base, :diff_root, :diff_paths])
  defp relative_path(".", path), do: path
  defp relative_path(prefix, path), do: Path.join(prefix, path)
  defp literal_paths(paths), do: Enum.map(paths, &(":(literal)" <> &1))

  defp valid_paths(paths) do
    if is_list(paths) and Enum.any?(paths) and
         Enum.all?(paths, fn path ->
           is_binary(path) and String.trim(path) != "" and Path.type(path) == :relative and
             not Enum.member?(Path.split(path), "..")
         end) do
      :ok
    else
      {:error, :invalid_diff_paths}
    end
  end

  defp clean(""), do: :ok
  defp clean(_), do: {:error, :dirty_source}

  defp application_selection(modules, selected) do
    unknown = selected |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.reject(&(&1 in modules))

    if Enum.empty?(unknown) do
      :ok
    else
      {:error, {:selected_module_not_in_application, unknown}}
    end
  end

  defp files(root, revision, names) do
    with {:ok, listing} <-
           git(root, ["ls-tree", "-r", "--full-tree", "--name-only", "-z", revision], false) do
      available = MapSet.new(String.split(listing, <<0>>, trim: true))

      Enum.reduce_while(names, {:ok, %{}}, fn path, {:ok, files} ->
        if MapSet.member?(available, path) do
          case git(root, ["show", revision <> ":" <> path], false) do
            {:ok, source} -> {:cont, {:ok, Map.put(files, path, source)}}
            error -> {:halt, error}
          end
        else
          {:cont, {:ok, files}}
        end
      end)
    end
  end

  @doc false
  @spec git(directory :: String.t(), arguments :: list(String.t()), trim :: boolean()) ::
          {:ok, String.t()} | {:error, term()}
  def git(directory, arguments, trim \\ true) do
    case System.cmd("git", arguments,
           cd: directory,
           stderr_to_stdout: true,
           env: Enum.map(@git_env, &{&1, nil})
         ) do
      {output, 0} ->
        if trim do
          {:ok, String.trim_trailing(output, "\n")}
        else
          {:ok, output}
        end

      {output, status} ->
        {:error, {:git_error, arguments, status, output}}
    end
  rescue
    error in [ArgumentError, ErlangError] ->
      {:error, {:git_unavailable, Exception.message(error)}}
  end
end
