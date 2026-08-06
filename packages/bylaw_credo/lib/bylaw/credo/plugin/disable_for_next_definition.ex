defmodule Bylaw.Credo.Plugin.DisableForNextDefinition do
  @moduledoc """
  Adds structural, function-clause-level suppression to Credo.

  Enable the plugin in `.credo.exs`, then place a
  `# credo:disable-for-next-definition` comment before a `def` or `defp`.
  The plugin resolves the next definition's inclusive source range from Credo's
  token-annotated AST and hands that range back to Credo's standard
  config-comment filter.

      plugins: [
        {Bylaw.Credo.Plugin.DisableForNextDefinition, []}
      ]

      # credo:disable-for-next-definition Bylaw.Credo.Check.Elixir.NoRaise
      def run do
        raise "failure"
      end

  Omitting the check name suppresses every check in that definition. Each
  syntactic clause is a separate definition, so a directive before one clause
  of a multi-clause function applies only to that clause.
  """

  import Credo.Plugin

  @commands [
    Credo.CLI.Command.Diff.DiffCommand,
    Credo.CLI.Command.List.ListCommand,
    Credo.CLI.Command.Suggest.SuggestCommand
  ]

  @doc false
  @spec init(term()) :: term()
  def init(exec) do
    Enum.reduce(@commands, exec, fn command, exec ->
      append_task(exec, command, :prepare_analysis, __MODULE__.ResolveRanges)
    end)
  end

  defmodule ResolveRanges do
    @moduledoc false

    use Credo.Execution.Task

    alias Credo.Check.ConfigComment
    alias Credo.Execution
    alias Credo.SourceFile

    @boundary_forms [:defmodule, :defprotocol, :defimpl]
    @definition_forms [:def, :defp]
    @instruction "disable-for-next-definition"

    @doc false
    @impl Credo.Execution.Task
    @spec call(Execution.t(), keyword()) :: Execution.t()
    def call(%Execution{} = exec, _opts \\ []) do
      source_files =
        exec
        |> Execution.get_source_files()
        |> Map.new(&{&1.filename, &1})

      config_comment_map =
        Map.new(exec.config_comment_map, fn {filename, comments} ->
          source_file = Map.get(source_files, filename)
          {filename, comments ++ resolved_comments(source_file, comments)}
        end)

      %{exec | config_comment_map: config_comment_map}
    end

    defp resolved_comments(%SourceFile{status: :valid} = source_file, comments) do
      resolve(SourceFile.ast(source_file), comments)
    rescue
      _error -> []
    end

    defp resolved_comments(_source_file, _comments), do: []

    @doc false
    @spec resolve(term(), list(map())) :: list(map())
    def resolve(ast, comments) do
      case collect(ast) do
        {:ok, %{definitions: definitions, boundaries: boundaries}} ->
          comments
          |> Enum.filter(&(&1.instruction == @instruction))
          |> Enum.flat_map(&resolve_comment(&1, definitions, boundaries))

        :error ->
          []
      end
    end

    defp resolve_comment(comment, definitions, boundaries) do
      parent = containing_boundary(comment.line_no, boundaries)

      definition =
        definitions
        |> Enum.filter(&(&1.parent == parent and &1.first_line > comment.line_no))
        |> Enum.min_by(& &1.first_line, fn -> nil end)

      case definition do
        nil ->
          []

        definition ->
          if crosses_boundary?(comment.line_no, definition.first_line, parent, boundaries) do
            []
          else
            [
              %ConfigComment{
                instruction: "disable-for-lines",
                line_no: definition.first_line,
                line_no_end: definition.last_line,
                params: comment.params
              }
            ]
          end
      end
    end

    defp containing_boundary(line_no, boundaries) when is_integer(line_no) do
      boundaries
      |> Enum.filter(&(line_no > &1.first_line and line_no < &1.last_line))
      |> Enum.min_by(&(&1.last_line - &1.first_line), fn -> %{id: :root} end)
      |> Map.fetch!(:id)
    end

    defp containing_boundary(_line_no, _boundaries), do: :root

    defp crosses_boundary?(comment_line, definition_line, parent, boundaries) do
      Enum.any?(boundaries, fn boundary ->
        boundary.parent == parent and boundary.first_line > comment_line and
          boundary.first_line < definition_line
      end)
    end

    defp collect(ast) do
      if exact_ranges?(ast) do
        {_next_id, definitions, boundaries} = collect_node(ast, :root, {0, [], []})

        {:ok,
         %{
           definitions: Enum.sort_by(definitions, & &1.first_line),
           boundaries: boundaries
         }}
      else
        :error
      end
    end

    defp exact_ranges?({:quote, _meta, _arguments}), do: true

    defp exact_ranges?({form, meta, arguments})
         when (form in @boundary_forms or form in @definition_forms) and is_list(meta) and
                is_list(arguments) do
      match?({:ok, _first_line, _last_line}, ast_range(meta)) and exact_ranges?(arguments)
    end

    defp exact_ranges?({form, _meta, _arguments})
         when form in @boundary_forms or form in @definition_forms,
         do: false

    defp exact_ranges?(tuple) when is_tuple(tuple) do
      tuple
      |> Tuple.to_list()
      |> exact_ranges?()
    end

    defp exact_ranges?(list) when is_list(list), do: Enum.all?(list, &exact_ranges?/1)
    defp exact_ranges?(_node), do: true

    defp collect_node(
           {form, meta, arguments},
           parent,
           {next_id, definitions, boundaries}
         )
         when form in @boundary_forms and is_list(meta) and is_list(arguments) do
      case ast_range(meta) do
        {:ok, first_line, last_line} ->
          boundary = %{
            id: next_id,
            parent: parent,
            first_line: first_line,
            last_line: last_line
          }

          collect_nodes(arguments, next_id, {next_id + 1, definitions, [boundary | boundaries]})

        :error ->
          {next_id, definitions, boundaries}
      end
    end

    defp collect_node({form, meta, arguments}, parent, state)
         when form in @definition_forms and is_list(meta) and is_list(arguments) do
      state =
        case ast_range(meta) do
          {:ok, first_line, last_line} ->
            {next_id, definitions, boundaries} = state

            definition = %{parent: parent, first_line: first_line, last_line: last_line}
            {next_id, [definition | definitions], boundaries}

          :error ->
            state
        end

      collect_nodes(arguments, parent, state)
    end

    defp collect_node({:quote, _meta, _arguments}, _parent, state), do: state

    defp collect_node({_form, _meta, arguments}, parent, state) when is_list(arguments) do
      collect_nodes(arguments, parent, state)
    end

    defp collect_node(tuple, parent, state) when is_tuple(tuple) do
      tuple
      |> Tuple.to_list()
      |> collect_nodes(parent, state)
    end

    defp collect_node(list, parent, state) when is_list(list) do
      collect_nodes(list, parent, state)
    end

    defp collect_node(_node, _parent, state), do: state

    defp collect_nodes(nodes, parent, state) do
      Enum.reduce(nodes, state, &collect_node(&1, parent, &2))
    end

    defp ast_range(meta) do
      first_line = metadata_line(meta[:line])
      last_line = metadata_line(meta[:end]) || metadata_line(meta[:end_of_expression])

      if is_integer(first_line) and is_integer(last_line) and last_line >= first_line do
        {:ok, first_line, last_line}
      else
        :error
      end
    end

    defp metadata_line(line) when is_integer(line), do: line
    defp metadata_line(metadata) when is_list(metadata), do: metadata[:line]
    defp metadata_line(_metadata), do: nil
  end
end
