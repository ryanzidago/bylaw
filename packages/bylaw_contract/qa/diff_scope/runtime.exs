defmodule BylawDiffScope.Runtime do
  @moduledoc false
  @checks [
    Bylaw.Contract.Check.Typespec,
    Bylaw.Contract.Check.FunctionClauses,
    Bylaw.Contract.Check.ElixirCompiler
  ]

  @doc false
  @spec checks(MapSet.t()) :: list({module(), keyword()})
  def checks(selection) do
    Enum.map(@checks, fn check ->
      {Module.concat(BylawDiffScope, check), [selection: selection]}
    end)
  end

  @doc false
  @spec install!(String.t()) :: :ok
  def install!(package) do
    for {name, loader, filter} <- [
          {"typespec", "Specs", :specs},
          {"function_clauses", "StructuralCoverage", :structural},
          {"elixir_compiler", "CompilerInference", :compiler}
        ] do
      source = File.read!(Path.join(package, "lib/bylaw/contract/check/#{name}.ex"))
      original = Enum.find(@checks, &(Macro.underscore(List.last(Module.split(&1))) == name))
      replacement = Module.concat(BylawDiffScope, original)

      source =
        replace_once!(
          source,
          "defmodule #{inspect(original)} do",
          "defmodule #{inspect(replacement)} do"
        )

      source =
        case filter do
          :compiler ->
            source
            |> replace_once!(
              "def init(modules, opts, context) do",
              "def init(modules, opts, context) do\n    {selection, opts} = Keyword.pop!(opts, :selection)\n    context = Map.put(context, :selection, selection)\n    modules = BylawDiffScope.Runtime.modules(modules, selection)"
            )
            |> replace_once!(
              "loaded = #{loader}.load(modules)",
              "loaded = #{loader}.load(modules) |> BylawDiffScope.Runtime.compiler(context.selection)"
            )

          _ ->
            source
            |> replace_once!("def init(modules, [],", "def init(modules, [selection: selection],")
            |> replace_once!(
              "loaded = #{loader}.load(modules)",
              "modules = BylawDiffScope.Runtime.modules(modules, selection)\n    loaded = #{loader}.load(modules) |> BylawDiffScope.Runtime.#{filter}(selection)"
            )
        end

      Code.compile_string(source, "diff-scope-prototype/#{name}.ex")
    end

    :ok
  end

  @doc false
  @spec modules(list(module()), MapSet.t()) :: list(module())
  def modules(modules, selection) do
    selected_modules = MapSet.new(selection, &elem(&1, 0))
    Enum.filter(modules, &MapSet.member?(selected_modules, &1))
  end

  @doc false
  @spec specs(map(), MapSet.t()) :: map()
  def specs(loaded, selection),
    do: filter_fields(loaded, [:input_classes, :boundaries, :return_alternatives], selection)

  @doc false
  @spec structural(map(), MapSet.t()) :: map()
  def structural(loaded, selection) do
    loaded = filter_fields(loaded, [:clauses, :arities], selection)

    classifiers =
      Enum.flat_map(loaded.classifiers, fn classifier ->
        mfas = Enum.filter(classifier.mfa_classifiers, &MapSet.member?(selection, &1.mfa))
        if Enum.empty?(mfas), do: [], else: [%{classifier | mfa_classifiers: mfas}]
      end)

    %{loaded | classifiers: classifiers}
  end

  @doc false
  @spec compiler(map(), MapSet.t()) :: map()
  def compiler(loaded, selection) do
    filter_fields(loaded, [:return_alternatives, :inference_rules], selection)
    |> Map.update!(:authored_mfas, &MapSet.intersection(&1, selection))
  end

  defp filter_fields(loaded, fields, selection) do
    Enum.reduce(fields, loaded, fn field, data ->
      Map.update!(
        data,
        field,
        &Enum.filter(&1, fn target ->
          MapSet.member?(selection, {target.module, target.function, target.arity})
        end)
      )
    end)
  end

  defp replace_once!(source, before, after_text) do
    case String.split(source, before) do
      [left, right] -> left <> after_text <> right
      _ -> raise "prototype source boundary changed: #{inspect(before)}"
    end
  end
end
