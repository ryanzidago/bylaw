defmodule Bylaw.Credo.RemoteCalls do
  @moduledoc false

  # Internal helpers for checks that keep calls to a library in one place.
  #
  # Collects the remote calls and imports in a file's AST with their modules
  # resolved through the file's aliases (`alias Req`, `alias Req, as: R` and
  # `alias Mint.{HTTP1, HTTP2}`). A call on a variable module, such as
  # `client.get(url)`, is not resolved and not returned. Module names stay
  # strings, such as `"Req.Request"` or `":httpc"`, so reading a file never
  # creates atoms.

  @typedoc false
  @type call :: %{module: String.t(), function: atom(), line: non_neg_integer()}

  @doc false
  @spec calls(Macro.t()) :: list(call())
  def calls(ast) do
    aliases = aliases(ast)

    ast
    |> Macro.prewalk([], fn node, acc -> {node, call(node, aliases) ++ acc} end)
    |> elem(1)
    |> Enum.reverse()
  end

  @doc false
  @spec within?(String.t(), String.t()) :: boolean()
  def within?(module, name) do
    module == name or String.starts_with?(module, name <> ".")
  end

  @doc false
  @spec module_name(atom() | String.t()) :: String.t()
  def module_name(module) when is_binary(module), do: module
  def module_name(module) when is_atom(module), do: inspect(module)

  @doc false
  @spec matches_path?(String.t(), list(String.t() | Regex.t())) :: boolean()
  def matches_path?(filename, paths) do
    Enum.any?(paths, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end

  @doc false
  @spec trigger(call()) :: String.t()
  def trigger(%{module: module, function: :import}), do: "import #{module}"
  def trigger(%{module: module, function: function}), do: "#{module}.#{function}"

  defp call({{:., meta, [module_ast, function]}, call_meta, _args}, aliases)
       when is_atom(function) do
    case resolve(module_ast, aliases) do
      nil -> []
      module -> [%{module: module, function: function, line: line(call_meta, meta)}]
    end
  end

  defp call({:import, meta, [module_ast | _opts]}, aliases) do
    case resolve(module_ast, aliases) do
      nil -> []
      module -> [%{module: module, function: :import, line: line(meta, [])}]
    end
  end

  defp call(_node, _aliases), do: []

  defp line(meta, fallback), do: Keyword.get(meta, :line) || Keyword.get(fallback, :line, 0)

  defp resolve({:__aliases__, _meta, [first | rest]}, aliases) when is_atom(first) do
    aliases
    |> Map.get(first, [first])
    |> Enum.concat(rest)
    |> Enum.map_join(".", &Atom.to_string/1)
  end

  defp resolve(module, _aliases) when is_atom(module) and module not in [nil, true, false],
    do: inspect(module)

  defp resolve(_module_ast, _aliases), do: nil

  defp aliases(ast) do
    ast
    |> Macro.prewalk(%{}, fn node, acc -> {node, Map.merge(acc, alias_entries(node))} end)
    |> elem(1)
  end

  defp alias_entries({:alias, _meta, [{:__aliases__, _alias_meta, [first | _rest] = parts}]})
       when is_atom(first),
       do: %{List.last(parts) => parts}

  defp alias_entries(
         {:alias, _meta, [{:__aliases__, _alias_meta, [first | _rest] = parts}, opts]}
       )
       when is_atom(first) and is_list(opts) do
    case Keyword.get(opts, :as) do
      {:__aliases__, _as_meta, [name]} -> %{name => parts}
      _other -> %{List.last(parts) => parts}
    end
  end

  defp alias_entries(
         {:alias, _meta,
          [
            {{:., _dot_meta, [{:__aliases__, _base_meta, [first | _rest] = base}, :{}]},
             _call_meta, children}
          ]}
       )
       when is_atom(first) do
    for {:__aliases__, _child_meta, child} <- children,
        into: %{},
        do: {List.last(child), base ++ child}
  end

  defp alias_entries(_node), do: %{}
end
