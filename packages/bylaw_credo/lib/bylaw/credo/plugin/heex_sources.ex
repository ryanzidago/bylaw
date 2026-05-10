defmodule Bylaw.Credo.Plugin.HEExSources do
  @moduledoc """
  Loads standalone `.html.heex` templates into Credo source files.

  Credo only parses Elixir source files during its normal source-loading step.
  Enable this plugin when checks need to run against standalone Phoenix HEEx
  templates.

  Credo discovers embedded `~H` templates in `.ex` and `.exs` files by default.
  This plugin adds standalone Phoenix `.html.heex` templates to the source files
  passed to Credo checks.

      plugins: [
        {Bylaw.Credo.Plugin.HEExSources, []}
      ]
  """

  import Credo.Plugin

  @commands [
    Credo.CLI.Command.Diff.DiffCommand,
    Credo.CLI.Command.Info.InfoCommand,
    Credo.CLI.Command.List.ListCommand,
    Credo.CLI.Command.Suggest.SuggestCommand
  ]

  # Registers the HEEx source-loading task in Credo's command pipelines.
  @doc false
  @spec init(term()) :: term()
  def init(exec) do
    Enum.reduce(@commands, exec, fn command, exec ->
      append_task(exec, command, :load_and_validate_source_files, __MODULE__.LoadSourceFiles)
    end)
  end

  defmodule LoadSourceFiles do
    @moduledoc false

    use Credo.Execution.Task

    alias Credo.Execution
    alias Credo.Service.SourceFileAST
    alias Credo.Service.SourceFileLines
    alias Credo.Service.SourceFileSource
    alias Credo.SourceFile

    @extension ".html.heex"
    @wildcard "**/*.html.heex"

    @doc false
    @spec call(Execution.t(), keyword()) :: Execution.t()
    def call(%Execution{} = exec, _opts \\ []) do
      source_files = Execution.get_source_files(exec)

      known_filenames =
        MapSet.new(source_files, &Path.expand(&1.filename, Execution.working_dir(exec)))

      heex_source_files =
        exec
        |> find_filenames()
        |> Enum.reject(&MapSet.member?(known_filenames, &1))
        |> Enum.map(&to_source_file/1)

      Execution.put_source_files(exec, source_files ++ heex_source_files)
    end

    @doc false
    @spec find_filenames(Execution.t()) :: list(String.t())
    def find_filenames(%Execution{files: %{included: included, excluded: excluded}} = exec) do
      working_dir = Execution.working_dir(exec)
      excluded = List.wrap(excluded)

      included
      |> List.wrap()
      |> Enum.flat_map(&find_included(working_dir, &1))
      |> Enum.uniq()
      |> Enum.reject(&excluded?(working_dir, &1, excluded))
      |> Enum.sort()
    end

    def find_filenames(%Execution{}), do: []

    defp find_included(working_dir, pattern) when is_binary(pattern) do
      path = Path.expand(pattern, working_dir)

      cond do
        String.ends_with?(path, @extension) and File.regular?(path) ->
          [path]

        File.dir?(path) ->
          path
          |> Path.join(@wildcard)
          |> Path.wildcard()

        wildcard?(path) ->
          path
          |> heex_wildcards()
          |> Enum.flat_map(&Path.wildcard/1)
          |> Enum.flat_map(&find_path/1)

        true ->
          []
      end
    end

    defp find_included(_working_dir, _pattern), do: []

    defp find_path(path) do
      cond do
        String.ends_with?(path, @extension) and File.regular?(path) ->
          [Path.expand(path)]

        File.dir?(path) ->
          path
          |> Path.join(@wildcard)
          |> Path.wildcard()

        true ->
          []
      end
    end

    defp wildcard?(path) do
      String.contains?(path, ["*", "{", "}", "?", "[", "]"])
    end

    defp heex_wildcards(path) do
      Enum.uniq([path | derived_heex_wildcards(path)])
    end

    defp derived_heex_wildcards(path) do
      if String.ends_with?(path, "*.{ex,exs}") do
        [String.replace_suffix(path, "*.{ex,exs}", "*.html.heex")]
      else
        []
      end
    end

    defp excluded?(working_dir, filename, excluded_patterns) do
      relative_filename = Path.relative_to(filename, working_dir)

      Enum.any?(excluded_patterns, fn
        pattern when is_binary(pattern) ->
          expanded_pattern = Path.expand(pattern, working_dir)

          Credo.Sources.filename_matches?(filename, expanded_pattern) ||
            Credo.Sources.filename_matches?(relative_filename, pattern)

        %Regex{} = pattern ->
          String.match?(filename, pattern) || String.match?(relative_filename, pattern)

        _pattern ->
          false
      end)
    end

    defp to_source_file(filename) do
      source = File.read!(filename)
      lines = Credo.Code.to_lines(source)

      hash =
        :sha256
        |> :crypto.hash(source)
        |> Base.encode16()

      source_file = %SourceFile{
        filename: Path.relative_to_cwd(filename),
        hash: hash,
        status: :valid
      }

      SourceFileAST.put(source_file, [])
      SourceFileLines.put(source_file, lines)
      SourceFileSource.put(source_file, source)

      source_file
    end
  end
end
