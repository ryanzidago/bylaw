defmodule Bylaw.Contract.Instrumenter do
  @moduledoc false

  # Derives the properties of a module from its abstract code and @specs, then
  # reloads the module so that exercising a property bumps a counter.
  #
  # Each clause keeps its name, arity, patterns and guards; only a prologue is
  # added to its body. A guard rejection is detected by a generated helper that
  # re-evaluates the earlier clauses in order until one accepts the call. Return
  # values are captured only for functions that are not part of a call cycle,
  # because capturing them removes tail-call optimisation.

  alias Bylaw.Contract.CallCycles
  alias Bylaw.Contract.Counters
  alias Bylaw.Contract.Property

  @max_clauses 64
  @load_label ~c"bylaw-contract"
  @argument_names List.to_tuple(for position <- 1..255, do: :"_@bylaw_argument_#{position}")
  @internal_prefixes ["__", "MACRO-", "module_info", "bylaw$"]

  @type original :: %{module: module(), binary: binary(), filename: charlist()}

  @type result :: %{
          original: original() | nil,
          properties: list(Property.t()),
          counters: :counters.counters_ref() | nil,
          loaded_md5: binary() | nil,
          descriptors: tuple(),
          warnings: list(String.t())
        }

  @doc false
  @spec instrument(module :: module(), targets :: list(map()), token :: integer()) :: result()
  def instrument(module, targets, token) do
    case fetch(module) do
      {:ok, original, forms} -> instrument_forms(module, targets, token, original, forms)
      {:error, reason} -> unassessable(module, targets, reason)
    end
  rescue
    exception -> unassessable(module, targets, Exception.message(exception))
  end

  @doc false
  @spec restore(original :: original()) :: :ok | {:error, String.t()}
  def restore(%{module: module, binary: binary, filename: filename}) do
    with true <- :code.soft_purge(module),
         {:module, ^module} <- :code.load_binary(module, filename, binary) do
      :code.soft_purge(module)
      :ok
    else
      _failure ->
        {:error, "#{inspect(module)} could not be restored while processes still use it"}
    end
  end

  @doc false
  @spec replaced?(module :: module(), loaded_md5 :: binary() | nil) :: boolean()
  def replaced?(_module, nil), do: false

  def replaced?(module, loaded_md5) do
    module.module_info(:md5) != loaded_md5
  catch
    :error, :undef -> true
  end

  defp fetch(module) do
    with {^module, binary, filename} <- :code.get_object_code(module),
         {:ok, {^module, [{:abstract_code, {:raw_abstract_v1, forms}}]}} <-
           :beam_lib.chunks(binary, [:abstract_code]) do
      {:ok, %{module: module, binary: binary, filename: filename}, forms}
    else
      :error ->
        {:error, "its compiled BEAM file is unavailable"}

      {:ok, {^module, [{:abstract_code, :no_abstract_code}]}} ->
        {:error, "it has no debug information"}

      other ->
        {:error, "its abstract code could not be read: #{inspect(other)}"}
    end
  end

  defp instrument_forms(module, targets, token, original, forms) do
    analysis = analyze(module, targets, forms)

    if map_size(analysis.plans) == 0 do
      %{
        original: nil,
        properties: analysis.properties,
        counters: nil,
        loaded_md5: nil,
        descriptors: {},
        warnings: analysis.warnings
      }
    else
      counters = :counters.new(max(analysis.slot - 1, 1), [:write_concurrency])
      rewritten = inject(forms, module, token, analysis.plans)

      case load(module, rewritten, compile_source(original.binary)) do
        :ok ->
          %{
            original: original,
            properties: analysis.properties,
            counters: counters,
            loaded_md5: module.module_info(:md5),
            descriptors: List.to_tuple(Enum.reverse(analysis.descriptors)),
            warnings: analysis.warnings
          }

        {:error, reason} ->
          failed = unassessable(module, [], reason)
          marked = Enum.map(analysis.properties, &mark_unassessable(&1, reason))
          %{failed | properties: marked, warnings: failed.warnings ++ analysis.warnings}
      end
    end
  end

  defp unassessable(module, targets, reason) do
    %{
      original: nil,
      properties:
        Enum.map(targets, &(&1 |> spec_property(nil, nil) |> mark_unassessable(reason))),
      counters: nil,
      loaded_md5: nil,
      descriptors: {},
      warnings: ["#{inspect(module)} cannot be observed: #{reason}"]
    }
  end

  @doc false
  @spec mark_unassessable(property :: Property.t(), reason :: String.t()) :: Property.t()
  def mark_unassessable(property, reason),
    do: %{property | status: :unassessable, reason: reason}

  # Analysis

  defp analyze(module, targets, forms) do
    file = source_file(module)
    lines = source_lines(file)
    {own_targets, generated_targets} = Enum.split_with(targets, &own_spec?(&1, file, lines))

    context = %{
      module: module,
      file: file,
      lines: lines,
      exports: exports(forms),
      recursive: CallCycles.recursive(forms, module),
      targets: Enum.group_by(own_targets, &{&1.function, &1.arity})
    }

    initial = %{
      slot: 1,
      index: 0,
      plans: %{},
      properties: [],
      descriptors: [],
      warnings: []
    }

    analysis =
      Enum.reduce(forms, initial, fn
        {:function, _annotation, name, arity, clauses}, acc ->
          plan_function({name, arity}, clauses, context, acc)

        _form, acc ->
          acc
      end)

    present = for {:function, _, name, arity, _} <- forms, into: MapSet.new(), do: {name, arity}
    missing = Map.drop(context.targets, MapSet.to_list(present))

    missing_properties =
      for {{name, arity}, missing_targets} <- missing, target <- missing_targets do
        target
        |> spec_property(nil, context.file)
        |> mark_unassessable("#{name}/#{arity} was not found in the module's debug information")
      end

    generated_properties =
      Enum.map(generated_targets, fn target ->
        target
        |> spec_property(nil, file)
        |> mark_unassessable("its @spec is generated by a macro")
      end)

    %{
      analysis
      | properties: generated_properties ++ missing_properties ++ analysis.properties
    }
  end

  defp plan_function({name, _arity} = function, clauses, context, acc) do
    count = Enum.count(clauses)
    public? = MapSet.member?(context.exports, function) and observable?(name, clauses)

    structural? =
      public? and count >= 2 and count <= @max_clauses and
        defined_in_source?(name, clauses, context.lines)

    specs = Map.get(context.targets, function, [])

    cond do
      structural? or not Enum.empty?(specs) ->
        acc
        |> warn_too_many_clauses(
          public? and count > @max_clauses,
          context.module,
          function,
          count
        )
        |> allocate(function, clauses, structural?, specs, context)

      true ->
        warn_too_many_clauses(
          acc,
          public? and count > @max_clauses,
          context.module,
          function,
          count
        )
    end
  end

  defp warn_too_many_clauses(acc, false, _module, _function, _count), do: acc

  defp warn_too_many_clauses(acc, true, module, {name, arity}, count) do
    warning =
      "#{inspect(module)}.#{name}/#{arity} has #{count} clauses; clause properties are not " <>
        "observed beyond #{@max_clauses}"

    %{acc | warnings: [warning | acc.warnings]}
  end

  defp allocate(acc, {name, arity} = function, clauses, structural?, specs, context) do
    count = Enum.count(clauses)
    base = %{module: context.module, function: name, arity: arity, file: context.file}

    {clause_properties, clause_slots, acc} =
      if structural? do
        clause_properties(acc, base, clauses)
      else
        {[], %{}, acc}
      end

    {rejection_properties, rejection_slots, acc} =
      if structural? do
        rejection_properties(acc, base, clauses, count)
      else
        {[], %{}, acc}
      end

    recursive? = MapSet.member?(context.recursive, function)
    {inputs, returns} = Enum.split_with(specs, &(&1.kind != :return_alternative))
    {supported_inputs, spec_properties_in, acc} = allocate_targets(acc, inputs, context, false)

    {supported_returns, spec_properties_out, acc} =
      allocate_targets(acc, returns, context, recursive?)

    acc =
      if recursive? and not Enum.empty?(returns) do
        warning =
          "#{inspect(context.module)}.#{name}/#{arity} is recursive: its return alternatives " <>
            "are unassessable because observing returns would remove tail-call optimisation"

        %{acc | warnings: [warning | acc.warnings]}
      else
        acc
      end

    {index, descriptors, next_index} =
      if Enum.empty?(supported_inputs) and Enum.empty?(supported_returns) do
        {nil, acc.descriptors, acc.index}
      else
        descriptor = %{
          arguments:
            Enum.map(supported_inputs, fn {target, hit, unknown} ->
              {target.argument, {hit, unknown, target.match_type}}
            end),
          returns:
            Enum.map(supported_returns, fn {target, hit, unknown} ->
              {hit, unknown, target.match_type}
            end)
        }

        {acc.index, [descriptor | acc.descriptors], acc.index + 1}
      end

    plan = %{
      index: index,
      arguments?: not Enum.empty?(supported_inputs),
      returns?: not Enum.empty?(supported_returns),
      clause_slots: clause_slots,
      rejection_slots: rejection_slots,
      count: count
    }

    %{
      acc
      | plans: Map.put(acc.plans, function, plan),
        index: next_index,
        descriptors: descriptors,
        properties:
          clause_properties ++
            rejection_properties ++ spec_properties_in ++ spec_properties_out ++ acc.properties
    }
  end

  defp clause_properties(acc, base, clauses) do
    {properties, slots, slot} =
      clauses
      |> Enum.with_index(1)
      |> Enum.reduce({[], %{}, acc.slot}, fn {clause, position}, {properties, slots, slot} ->
        property =
          struct!(Property, %{
            id: {:clause, base.module, base.function, base.arity, position},
            kind: :clause,
            module: base.module,
            function: base.function,
            arity: base.arity,
            clause: position,
            file: base.file,
            line: clause_line(clause),
            slot: slot
          })

        {[property | properties], Map.put(slots, position, slot), slot + 1}
      end)

    {properties, slots, %{acc | slot: slot}}
  end

  defp rejection_properties(acc, base, clauses, count) do
    {properties, slots, slot} =
      clauses
      |> Enum.with_index(1)
      |> Enum.filter(fn {{:clause, _, patterns, guards, _}, position} ->
        not Enum.empty?(guards) and position < count and
          later_clause_may_accept?(patterns, Enum.drop(clauses, position))
      end)
      |> Enum.reduce({[], %{}, acc.slot}, fn {clause, position}, {properties, slots, slot} ->
        property =
          struct!(Property, %{
            id: {:guard_rejection, base.module, base.function, base.arity, position},
            kind: :guard_rejection,
            module: base.module,
            function: base.function,
            arity: base.arity,
            clause: position,
            file: base.file,
            line: clause_line(clause),
            slot: slot
          })

        {[property | properties], Map.put(slots, position, slot), slot + 1}
      end)

    {properties, slots, %{acc | slot: slot}}
  end

  # A rejected call can only fall through to a later clause whose patterns could
  # match the same arguments. Anything unsure counts as overlapping.
  defp later_clause_may_accept?(patterns, later) do
    Enum.any?(later, fn {:clause, _, later_patterns, _guards, _body} ->
      patterns |> Enum.zip(later_patterns) |> Enum.all?(fn {a, b} -> overlap?(a, b) end)
    end)
  end

  defp overlap?({:var, _, _}, _other), do: true
  defp overlap?(_pattern, {:var, _, _}), do: true

  defp overlap?({:match, _, left, right}, other),
    do: overlap?(left, other) and overlap?(right, other)

  defp overlap?(pattern, {:match, _, left, right}),
    do: overlap?(pattern, left) and overlap?(pattern, right)

  defp overlap?(a, b) do
    case {shape(a), shape(b)} do
      {{:literal, type, value}, {:literal, type, other}} ->
        value == other

      {{:tuple, left}, {:tuple, right}} ->
        Enum.count(left) == Enum.count(right) and pairwise_overlap?(left, right)

      {{:cons, head, tail}, {:cons, other_head, other_tail}} ->
        overlap?(head, other_head) and overlap?(tail, other_tail)

      {:unknown, _other} ->
        true

      {_pattern, :unknown} ->
        true

      {kind, kind} ->
        true

      {{:literal, _, _}, _other} ->
        false

      {_pattern, {:literal, _, _}} ->
        false

      {{:list, _}, {:list, _}} ->
        true

      {{:list, _}, {:cons, _, _}} ->
        true

      {{:cons, _, _}, {:list, _}} ->
        true

      {_pattern, _other} ->
        false
    end
  end

  defp pairwise_overlap?(left, right),
    do: left |> Enum.zip(right) |> Enum.all?(fn {a, b} -> overlap?(a, b) end)

  defp shape({:atom, _, value}), do: {:literal, :atom, value}
  defp shape({:integer, _, value}), do: {:literal, :integer, value}
  defp shape({:char, _, value}), do: {:literal, :integer, value}
  defp shape({:float, _, value}), do: {:literal, :float, value}
  defp shape({:tuple, _, elements}), do: {:tuple, elements}
  defp shape({:cons, _, head, tail}), do: {:cons, head, tail}
  defp shape({nil, _}), do: {:list, :empty}
  defp shape({:string, _, _chars}), do: {:list, :string}
  defp shape({:map, _, _fields}), do: :map
  defp shape({:bin, _, _segments}), do: :binary
  defp shape(_other), do: :unknown

  defp allocate_targets(acc, targets, context, recursive?) do
    {supported, properties, acc} =
      Enum.reduce(targets, {[], [], acc}, fn target, {supported, properties, acc} ->
        property = spec_property(target, nil, context.file)

        cond do
          recursive? ->
            reason = "recursive function: observing returns would remove tail-call optimisation"
            {supported, [mark_unassessable(property, reason) | properties], acc}

          not target.supported? ->
            reason = "the type cannot be assessed"
            {supported, [mark_unassessable(property, reason) | properties], acc}

          true ->
            hit = acc.slot
            unknown = acc.slot + 1
            property = %{property | slot: hit, unknown_slot: unknown}

            {[{target, hit, unknown} | supported], [property | properties],
             %{acc | slot: acc.slot + 2}}
        end
      end)

    {Enum.reverse(supported), properties, acc}
  end

  defp spec_property(target, slot, file) do
    struct!(Property, %{
      id: target.id,
      kind: target.kind,
      module: target.module,
      function: target.function,
      arity: target.arity,
      argument: Map.get(target, :argument),
      label: target.label,
      file: target.spec_file || file,
      line: target.spec_line,
      source: target.spec_source,
      slot: slot
    })
  end

  defp exports(forms) do
    for {:attribute, _annotation, :export, exports} <- forms,
        {name, arity} <- exports,
        into: MapSet.new(),
        do: {name, arity}
  end

  defp observable?(name, clauses) do
    not String.starts_with?(Atom.to_string(name), @internal_prefixes) and
      not Enum.any?(clauses, fn {:clause, annotation, _, _, _} ->
        :erl_anno.generated(annotation)
      end)
  end

  # Clauses generated by macros point at the line that invoked the macro, not at a
  # definition of the function, so their properties would be meaningless.
  defp source_lines(nil), do: nil

  defp source_lines(file) do
    case File.read(file) do
      {:ok, content} -> content |> String.split("\n") |> List.to_tuple()
      {:error, _reason} -> nil
    end
  end

  defp defined_in_source?(_name, _clauses, nil), do: true

  defp defined_in_source?(name, clauses, lines) do
    pattern =
      Regex.compile!(
        "^\\s*(defp?|defmacrop?|defdelegate)\\s+\\(?#{Regex.escape(Atom.to_string(name))}(?![\\w?!])"
      )

    clause_lines = Enum.map(clauses, &clause_line/1)

    distinct_lines? = clause_lines == Enum.uniq(clause_lines)

    distinct_lines? and
      Enum.all?(clause_lines, fn line ->
        line >= 1 and line <= tuple_size(lines) and
          source_declares?(pattern, elem(lines, line - 1))
      end)
  end

  defp source_declares?(pattern, line),
    do: Regex.match?(pattern, line) and not String.contains?(line, "unquote")

  # A spec generated by a macro is not on a line of the module's own file that
  # declares it.
  defp own_spec?(%{spec_file: nil}, _file, _lines), do: true
  defp own_spec?(_target, _file, nil), do: true

  defp own_spec?(target, file, lines) do
    line = target.spec_line

    pattern =
      Regex.compile!(
        "^\\s*@(spec|callback)\\s+\\(?#{Regex.escape(Atom.to_string(target.function))}(?![\\w?!])"
      )

    Path.expand(to_string(target.spec_file)) == Path.expand(to_string(file)) and
      is_integer(line) and line >= 1 and line <= tuple_size(lines) and
      Regex.match?(pattern, elem(lines, line - 1))
  end

  defp source_file(module) do
    case module.module_info(:compile)[:source] do
      nil -> nil
      source -> to_string(source)
    end
  end

  # Introspection such as module_info(:compile)[:source] must keep working.
  defp compile_source(binary) do
    case :beam_lib.chunks(binary, [:compile_info]) do
      {:ok, {_module, [compile_info: info]}} -> Keyword.get(info, :source)
      _unavailable -> nil
    end
  end

  defp source_option(nil), do: []
  defp source_option(source), do: [{:source, source}]

  defp clause_line({:clause, annotation, _patterns, _guards, _body}),
    do: :erl_anno.line(annotation)

  # Injection

  defp inject(forms, module, token, plans) do
    Enum.flat_map(forms, fn
      {:function, _annotation, name, arity, _clauses} = form ->
        case Map.fetch(plans, {name, arity}) do
          {:ok, plan} -> inject_function(form, module, token, plan)
          :error -> [form]
        end

      form ->
        [form]
    end)
  end

  defp inject_function({:function, annotation, name, arity, clauses}, module, token, plan) do
    context = %{module: module, token: token, plan: plan, name: name, arity: arity}

    rewritten =
      clauses
      |> Enum.with_index(1)
      |> Enum.map(&inject_clause(&1, context))

    [{:function, annotation, name, arity, rewritten} | rejection_helper(clauses, context)]
  end

  defp inject_clause({{:clause, annotation, patterns, guards, body}, position}, context) do
    %{plan: plan, arity: arity} = context
    chain? = Enum.any?(Map.keys(plan.rejection_slots), &(&1 < position))
    variables = Enum.map(1..arity//1, &argument_variable(annotation, &1))

    patterns =
      if plan.arguments? or chain? do
        patterns
        |> Enum.zip(variables)
        |> Enum.map(fn {pattern, variable} -> {:match, annotation, variable, pattern} end)
      else
        patterns
      end

    prologue =
      clause_hit(plan, position, annotation, context) ++
        rejection_chain(chain?, annotation, variables, context) ++
        argument_call(plan, annotation, variables, context)

    body =
      if plan.returns? do
        capture_return(body, annotation, context)
      else
        body
      end

    {:clause, annotation, patterns, guards, prologue ++ body}
  end

  defp clause_hit(plan, position, annotation, context) do
    case Map.fetch(plan.clause_slots, position) do
      {:ok, slot} -> [hit_form(annotation, context, slot)]
      :error -> []
    end
  end

  defp rejection_chain(false, _annotation, _variables, _context), do: []

  defp rejection_chain(true, annotation, variables, context) do
    [
      {:call, annotation, {:atom, annotation, helper_name(context)},
       [{:integer, annotation, 1} | variables]}
    ]
  end

  defp argument_call(%{arguments?: false}, _annotation, _variables, _context), do: []

  defp argument_call(plan, annotation, variables, context) do
    [
      counters_call(annotation, :call, [
        {:integer, annotation, context.token},
        {:atom, annotation, context.module},
        {:integer, annotation, plan.index},
        {:tuple, annotation, variables}
      ])
    ]
  end

  defp capture_return(body, annotation, context) do
    {init, [last]} = Enum.split(body, -1)
    result = {:var, annotation, :_@bylaw_result}

    init ++
      [
        {:match, annotation, result, last},
        counters_call(annotation, :return, [
          {:integer, annotation, context.token},
          {:atom, annotation, context.module},
          {:integer, annotation, context.plan.index},
          result
        ]),
        result
      ]
  end

  defp rejection_helper(_clauses, %{plan: %{rejection_slots: slots}}) when map_size(slots) == 0,
    do: []

  defp rejection_helper(clauses, context) do
    %{plan: plan, arity: arity} = context
    name = helper_name(context)
    annotation = clauses |> hd() |> elem(1)

    helper_clauses =
      for {{:clause, clause_annotation, patterns, guards, _body}, position} <-
            Enum.with_index(clauses, 1),
          position < plan.count do
        variables = Enum.map(1..arity//1, &argument_variable(clause_annotation, &1))

        next =
          {:call, clause_annotation, {:atom, clause_annotation, name},
           [{:integer, clause_annotation, position + 1} | variables]}

        pattern = {:tuple, clause_annotation, patterns}

        accepted =
          {:clause, clause_annotation, [pattern], guards, [{:atom, clause_annotation, :ok}]}

        otherwise = {:clause, clause_annotation, [{:var, clause_annotation, :_}], [], [next]}

        case_clauses =
          case Map.fetch(plan.rejection_slots, position) do
            {:ok, slot} ->
              rejected =
                {:clause, clause_annotation, [pattern], [],
                 [hit_form(clause_annotation, context, slot), next]}

              [accepted, rejected, otherwise]

            :error ->
              [accepted, otherwise]
          end

        {:clause, clause_annotation, [{:integer, clause_annotation, position} | variables], [],
         [{:case, clause_annotation, {:tuple, clause_annotation, variables}, case_clauses}]}
      end

    fallback =
      {:clause, annotation, List.duplicate({:var, annotation, :_}, arity + 1), [],
       [{:atom, annotation, :ok}]}

    [{:function, annotation, name, arity + 1, helper_clauses ++ [fallback]}]
  end

  # The generated name is bounded by the number of observed functions.
  # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
  defp helper_name(%{name: name, arity: arity}), do: :"bylaw$rejections$#{name}$#{arity}"

  defp hit_form(annotation, context, slot) do
    counters_call(annotation, :hit, [
      {:integer, annotation, context.token},
      {:atom, annotation, context.module},
      {:integer, annotation, slot}
    ])
  end

  defp counters_call(annotation, function, arguments) do
    {:call, annotation,
     {:remote, annotation, {:atom, annotation, Counters}, {:atom, annotation, function}},
     arguments}
  end

  defp argument_variable(annotation, position),
    do: {:var, annotation, elem(@argument_names, position - 1)}

  # Loading

  defp load(module, forms, source) do
    with true <- :code.soft_purge(module),
         {:ok, binary} <- compile(module, forms, source),
         {:module, ^module} <- :code.load_binary(module, @load_label, binary) do
      :ok
    else
      false -> {:error, "processes still use an earlier version of the module"}
      {:error, reason} -> {:error, reason}
      other -> {:error, inspect(other)}
    end
  end

  defp compile(module, forms, source) do
    options = [:return_errors, :debug_info | source_option(source)]

    case :compile.forms(forms, options) do
      {:ok, ^module, binary} ->
        {:ok, binary}

      {:ok, ^module, binary, _warnings} ->
        {:ok, binary}

      {:error, errors, _warnings} ->
        {:error, "instrumented code did not compile: #{inspect(errors)}"}
    end
  end
end
