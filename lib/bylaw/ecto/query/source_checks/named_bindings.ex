defmodule Bylaw.Ecto.Query.SourceChecks.NamedBindings do
  @moduledoc """
  Validates Ecto query source code for strict named binding style.

  This check parses Elixir source and validates the query shape before Ecto
  expands it into a runtime query struct. It is intentionally source-based
  because runtime queries retain named binding aliases but not enough source
  information to prove whether a predicate used `as(:name)` or a local binding
  variable.

  The check requires every `from` root and join to declare an `:as` alias. When
  query expressions reference a binding, they must use `as(:name)` or
  `parent_as(:name)` instead of positional binding lists, local binding
  variables, or keyword field shortcuts. Association join sources and joined
  preloads may still use binding variables where Ecto requires them.

      source = "from(post in Post, as: :post, where: as(:post).id == ^id)"

      Bylaw.Ecto.Query.SourceChecks.NamedBindings.validate(source)
  """

  alias Bylaw.Ecto.Query.Issue

  @join_keys [
    :join,
    :inner_join,
    :left_join,
    :right_join,
    :cross_join,
    :cross_lateral_join,
    :full_join,
    :inner_lateral_join,
    :left_lateral_join
  ]

  @binding_call_names [
    :where,
    :or_where,
    :having,
    :or_having,
    :select,
    :select_merge,
    :order_by,
    :group_by,
    :distinct,
    :preload,
    :windows,
    :update
  ]

  @implicit_keyword_reference_keys [:where, :or_where, :having, :or_having, :on]
  @implicit_atom_reference_keys [
    :select,
    :select_merge,
    :order_by,
    :group_by,
    :distinct,
    :windows
  ]
  @query_construct_names [:from, :dynamic, :join] ++ @binding_call_names

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:named_bindings, check_opts()})
  @type result :: :ok | {:error, list(Issue.t())}

  @doc """
  Returns the option namespace used by this source check.
  """
  @spec name() :: :named_bindings
  def name, do: :named_bindings

  @doc """
  Validates Ecto query source code for strict named binding style.

  The check is enabled by default. Set `named_bindings: [validate: false]` to
  skip validation for a caller-managed exception.

  Supported options:

      [
        named_bindings: [
          validate: true
        ]
      ]
  """
  @spec validate(String.t(), opts()) :: result()
  def validate(source, opts \\ [])

  def validate(source, opts) when is_binary(source) and is_list(opts) do
    check_opts = check_opts!(opts)

    if enabled?(check_opts) do
      source
      |> Code.string_to_quoted!(columns: true)
      |> validate_quoted()
    else
      :ok
    end
  end

  def validate(source, _opts) when not is_binary(source) do
    raise ArgumentError, "expected source to be a string, got: #{inspect(source)}"
  end

  def validate(_source, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp check_opts!(opts) do
    opts
    |> Keyword.get(name(), [])
    |> normalize_check_opts!()
  end

  defp normalize_check_opts!(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Enum.each(opts, &validate_check_opt!/1)
      opts
    else
      raise ArgumentError,
            "expected #{inspect(name())} opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp normalize_check_opts!(opts) do
    raise ArgumentError,
          "expected #{inspect(name())} opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_check_opt!({:validate, _value}), do: :ok

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  defp validate_quoted(quoted) do
    {_quoted, issues} =
      Macro.prewalk(quoted, [], fn node, issues ->
        {node, issues ++ issues_for_node(node)}
      end)

    if Enum.empty?(issues), do: :ok, else: {:error, issues}
  end

  defp issues_for_node(node) do
    case query_call(node) do
      {:from, meta, args} ->
        from_issues(meta, args)

      {:join, meta, args} ->
        join_call_issues(meta, args)

      {:dynamic, meta, args} ->
        binding_call_issues(:dynamic, meta, args)

      {name, meta, args} when name in @binding_call_names ->
        binding_call_issues(name, meta, args)

      _call ->
        []
    end
  end

  defp from_issues(meta, args) do
    {root_vars, kw, scan_nodes, binding_list} = from_parts(args)

    root_as_issues(meta, kw) ++
      binding_list_issues(:from, binding_list) ++
      join_keyword_as_issues(kw) ++
      keyword_expression_issues(kw, root_vars, scan_nodes)
  end

  defp from_parts([kw]) when is_list(kw) do
    {[], kw, [], []}
  end

  defp from_parts([{:in, _meta, [binding, source]}]) do
    {root_bindings, binding_list} = from_binding_parts(binding)
    {root_bindings, [], [source], binding_list}
  end

  defp from_parts([{:in, _meta, [binding, source]}, kw]) when is_list(kw) do
    {root_bindings, binding_list} = from_binding_parts(binding)
    {root_bindings, kw, [source], binding_list}
  end

  defp from_parts([_source, kw]) when is_list(kw) do
    {[], kw, [], []}
  end

  defp from_parts([source]) do
    {[], [], [source], []}
  end

  defp from_parts(_args), do: {[], [], [], []}

  defp from_binding_parts(binding) when is_list(binding) do
    binding_list = binding_list_if_present(binding)

    if Enum.empty?(binding_list) do
      {[binding], []}
    else
      {binding_asts_from_list(binding_list), binding_list}
    end
  end

  defp from_binding_parts(binding), do: {[binding], []}

  defp root_as_issues(meta, kw) do
    if root_has_as?(kw) do
      []
    else
      [
        issue(
          "expected Ecto query root binding to declare an :as alias",
          :missing_root_as,
          meta,
          %{binding: :root}
        )
      ]
    end
  end

  defp root_has_as?(kw) do
    Enum.reduce_while(kw, false, fn
      {key, _value}, found? when key in @join_keys ->
        {:halt, found?}

      {:as, _value}, _found? ->
        {:halt, true}

      _entry, found? ->
        {:cont, found?}
    end)
  end

  defp join_keyword_as_issues(kw) do
    {current_join, issues} =
      Enum.reduce(kw, {nil, []}, fn
        {key, value}, {current_join, issues} when key in @join_keys ->
          {new_join(key, value), close_join(current_join, issues)}

        {:as, _value}, {nil, issues} ->
          {nil, issues}

        {:as, _value}, {current_join, issues} ->
          {%{current_join | has_as?: true}, issues}

        _entry, {current_join, issues} ->
          {current_join, issues}
      end)

    close_join(current_join, issues)
  end

  defp new_join(key, value) do
    %{key: key, line: line(value), column: column(value), has_as?: false}
  end

  defp close_join(nil, issues), do: issues

  defp close_join(%{has_as?: true}, issues), do: issues

  defp close_join(join, issues) do
    issues ++
      [
        issue(
          "expected Ecto query join binding to declare an :as alias",
          :missing_join_as,
          join,
          %{join: join.key}
        )
      ]
  end

  defp keyword_expression_issues(kw, root_bindings, scan_nodes) do
    binding_vars =
      kw
      |> join_binding_vars()
      |> Kernel.++(root_bindings)
      |> binding_var_names()

    kw_issues =
      Enum.flat_map(kw, fn
        {key, value} when key in @join_keys ->
          join_source_expression_issues(value, binding_vars)

        {:as, _value} ->
          []

        {key, value} ->
          expression_issues(key, value, binding_vars)
      end)

    binding_reference_issues(scan_nodes, binding_vars) ++ kw_issues
  end

  defp join_binding_vars(kw) do
    Enum.flat_map(kw, fn
      {key, {:in, _meta, [binding, _source]}} when key in @join_keys -> [binding]
      _entry -> []
    end)
  end

  defp join_source_expression_issues({:in, _meta, [_binding, source]}, binding_vars) do
    binding_reference_issues(source, binding_vars)
  end

  defp join_source_expression_issues(source, binding_vars) do
    binding_reference_issues(source, binding_vars)
  end

  defp join_call_issues(meta, args) do
    case join_call_parts(args) do
      nil ->
        []

      {binding_list, join_expr, opts} ->
        binding_vars =
          [join_expr_binding(join_expr) | binding_vars_from_list(binding_list)]
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()

        join_as_issues(meta, opts) ++
          binding_list_issues(:join, binding_list) ++
          join_call_expression_issues(join_expr, opts, binding_vars)
    end
  end

  defp join_call_parts(args) do
    case normalize_join_args(args) do
      [_qualifier, binding_list, join_expr, opts]
      when is_list(opts) ->
        {binding_list_if_present(binding_list), join_expr, opts}

      [_qualifier, binding_list, join_expr]
      when is_list(binding_list) ->
        {binding_list_if_present(binding_list), join_expr, []}

      [_qualifier, join_expr, opts] when is_list(opts) ->
        {[], join_expr, opts}

      [_qualifier, join_expr] ->
        {[], join_expr, []}

      _args ->
        nil
    end
  end

  defp normalize_join_args([_query, qualifier | rest] = args) do
    if join_qualifier?(qualifier), do: [qualifier | rest], else: args
  end

  defp normalize_join_args(args), do: args

  defp join_qualifier?(qualifier) do
    qualifier in [
      :inner,
      :left,
      :right,
      :cross,
      :cross_lateral,
      :full,
      :inner_lateral,
      :left_lateral
    ]
  end

  defp binding_list_if_present(list) when is_list(list) do
    if binding_list_ast?(list), do: list, else: []
  end

  defp binding_list_if_present(_expr), do: []

  defp join_expr_binding({:in, _meta, [binding, _source]}) do
    binding_var_name(binding)
  end

  defp join_expr_binding(_expr), do: nil

  defp join_as_issues(meta, opts) do
    if Keyword.has_key?(opts, :as) do
      []
    else
      [
        issue(
          "expected Ecto query join binding to declare an :as alias",
          :missing_join_as,
          meta,
          %{join: :join}
        )
      ]
    end
  end

  defp join_call_expression_issues(join_expr, opts, binding_vars) do
    join_source_expression_issues(join_expr, binding_vars) ++
      Enum.flat_map(opts, fn
        {:as, _value} ->
          []

        {key, value} ->
          expression_issues(key, value, binding_vars)
      end)
  end

  defp binding_call_issues(:dynamic, _meta, [binding_list, expr])
       when is_list(binding_list) do
    binding_vars = binding_vars_from_list(binding_list) |> MapSet.new()

    binding_list_issues(:dynamic, binding_list) ++
      binding_reference_issues(expr, binding_vars)
  end

  defp binding_call_issues(:dynamic, _meta, [_expr]), do: []

  defp binding_call_issues(name, _meta, args) do
    {binding_list, exprs} = binding_call_parts(args)
    binding_vars = binding_vars_from_list(binding_list) |> MapSet.new()

    binding_list_issues(name, binding_list) ++
      Enum.flat_map(exprs, fn expr ->
        expression_issues(name, expr, binding_vars)
      end)
  end

  defp expression_issues(:preload, expr, binding_vars) do
    preload_reference_issues(expr, binding_vars)
  end

  defp expression_issues(key, expr, binding_vars) do
    implicit_reference_issues(expr, key) ++ binding_reference_issues(expr, binding_vars)
  end

  defp binding_call_parts([binding_list | exprs]) when is_list(binding_list) do
    if binding_list_ast?(binding_list) do
      {binding_list, exprs}
    else
      {[], [binding_list | exprs]}
    end
  end

  defp binding_call_parts([_query, binding_list | exprs]) when is_list(binding_list) do
    if binding_list_ast?(binding_list) do
      {binding_list, exprs}
    else
      {[], [binding_list | exprs]}
    end
  end

  defp binding_call_parts(args), do: {[], args}

  defp binding_list_issues(_name, []), do: []

  defp binding_list_issues(name, binding_list) do
    [
      issue(
        "expected Ecto query #{name} to use as(:name) references instead of a binding list",
        :binding_list,
        binding_list,
        %{macro: name}
      )
    ]
  end

  defp binding_list_ast?([]), do: false

  defp binding_list_ast?(list) when is_list(list) do
    Enum.all?(list, &binding_list_element?/1)
  end

  defp binding_list_ast?(_expr), do: false

  defp binding_list_element?({name, binding}) when is_atom(name) do
    variable_ast?(binding) or ellipsis_ast?(binding)
  end

  defp binding_list_element?({{:^, _meta, [_name]}, binding}) do
    variable_ast?(binding) or ellipsis_ast?(binding)
  end

  defp binding_list_element?(binding) do
    variable_ast?(binding) or ellipsis_ast?(binding)
  end

  defp binding_asts_from_list(binding_list) do
    Enum.flat_map(binding_list, fn
      {_name, binding} -> [binding]
      binding -> [binding]
    end)
  end

  defp binding_vars_from_list(binding_list) do
    binding_list
    |> binding_asts_from_list()
    |> binding_var_names()
  end

  defp binding_var_names(bindings) do
    bindings
    |> Enum.map(&binding_var_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp binding_var_name({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    if ellipsis_name?(name), do: nil, else: name
  end

  defp binding_var_name(_binding), do: nil

  defp implicit_reference_issues(expr, key)
       when key in @implicit_keyword_reference_keys and is_list(expr) do
    if Keyword.keyword?(expr) and not Enum.empty?(expr) do
      [
        issue(
          "expected Ecto query #{key} to use as(:name) references instead of keyword field shortcuts",
          :implicit_binding_reference,
          expr,
          %{macro: key}
        )
      ]
    else
      []
    end
  end

  defp implicit_reference_issues(expr, key) when key in @implicit_atom_reference_keys do
    if implicit_atom_reference?(expr) do
      [
        issue(
          "expected Ecto query #{key} to use as(:name) references instead of implicit field shortcuts",
          :implicit_binding_reference,
          expr,
          %{macro: key}
        )
      ]
    else
      []
    end
  end

  defp implicit_reference_issues(_expr, _key), do: []

  defp implicit_atom_reference?(field) when is_atom(field), do: field not in [true, false, nil]

  defp implicit_atom_reference?(list) when is_list(list) do
    Enum.any?(list, fn
      {_direction, field} -> implicit_atom_reference?(field)
      field -> implicit_atom_reference?(field)
    end)
  end

  defp implicit_atom_reference?(_expr), do: false

  defp binding_reference_issues(nodes, binding_vars)
       when is_list(nodes) and is_struct(binding_vars, MapSet) do
    Enum.flat_map(nodes, &binding_reference_issues(&1, binding_vars))
  end

  defp binding_reference_issues(node, binding_vars) when is_list(binding_vars) do
    binding_reference_issues(node, MapSet.new(binding_vars))
  end

  defp binding_reference_issues(node, binding_vars) when is_struct(binding_vars, MapSet) do
    collect_binding_reference_issues(node, binding_vars)
  end

  defp preload_reference_issues(nodes, binding_vars)
       when is_list(nodes) and is_struct(binding_vars, MapSet) do
    Enum.flat_map(nodes, &preload_reference_issues(&1, binding_vars))
  end

  defp preload_reference_issues(node, binding_vars) when is_list(binding_vars) do
    preload_reference_issues(node, MapSet.new(binding_vars))
  end

  defp preload_reference_issues({:^, _meta, [_expr]}, _binding_vars), do: []

  defp preload_reference_issues({name, _meta, context}, binding_vars)
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    if MapSet.member?(binding_vars, name),
      do: [],
      else: binding_reference_issues(name, binding_vars)
  end

  defp preload_reference_issues(
         {{:., _dot_meta, [_source, field]}, _meta, []} = node,
         binding_vars
       )
       when is_atom(field) do
    binding_reference_issues(node, binding_vars)
  end

  defp preload_reference_issues({:field, _meta, [_source, _field]} = node, binding_vars) do
    binding_reference_issues(node, binding_vars)
  end

  defp preload_reference_issues(tuple, binding_vars) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> preload_reference_issues(binding_vars)
  end

  defp preload_reference_issues(list, binding_vars) when is_list(list) do
    Enum.flat_map(list, &preload_reference_issues(&1, binding_vars))
  end

  defp preload_reference_issues(expr, binding_vars),
    do: binding_reference_issues(expr, binding_vars)

  defp collect_binding_reference_issues({:^, _meta, [_expr]}, _binding_vars), do: []

  defp collect_binding_reference_issues({:as, _meta, [_name]}, _binding_vars), do: []

  defp collect_binding_reference_issues({:parent_as, _meta, [_name]}, _binding_vars), do: []

  defp collect_binding_reference_issues({name, _meta, args}, _binding_vars)
       when is_atom(name) and is_list(args) and name in @query_construct_names,
       do: []

  defp collect_binding_reference_issues(
         {{:., _dot_meta, [_module, name]}, _meta, args},
         _binding_vars
       )
       when is_atom(name) and is_list(args) and name in @query_construct_names,
       do: []

  defp collect_binding_reference_issues(
         {{:., meta, [source, field]}, call_meta, []},
         binding_vars
       )
       when is_atom(field) do
    case binding_var_name(source) do
      variable when is_atom(variable) and not is_nil(variable) ->
        if MapSet.member?(binding_vars, variable) do
          [binding_reference_issue(variable, meta ++ call_meta, :field_access)]
        else
          collect_binding_reference_issues(source, binding_vars)
        end

      nil ->
        collect_binding_reference_issues(source, binding_vars)
    end
  end

  defp collect_binding_reference_issues({:field, meta, [source, _field]}, binding_vars) do
    call_reference_issues(:field, meta, source, binding_vars)
  end

  defp collect_binding_reference_issues({:assoc, _meta, [source, association]}, binding_vars) do
    if assoc_binding_source?(source, binding_vars) do
      collect_binding_reference_issues(association, binding_vars)
    else
      collect_binding_reference_issues(source, binding_vars) ++
        collect_binding_reference_issues(association, binding_vars)
    end
  end

  defp collect_binding_reference_issues({name, meta, context}, binding_vars)
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    if MapSet.member?(binding_vars, name) do
      [binding_reference_issue(name, meta, :bare_binding)]
    else
      []
    end
  end

  defp collect_binding_reference_issues(tuple, binding_vars) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> collect_binding_reference_issues(binding_vars)
  end

  defp collect_binding_reference_issues(list, binding_vars) when is_list(list) do
    Enum.flat_map(list, &collect_binding_reference_issues(&1, binding_vars))
  end

  defp collect_binding_reference_issues(_expr, _binding_vars), do: []

  defp call_reference_issues(function, meta, source, binding_vars) do
    case binding_var_name(source) do
      variable when is_atom(variable) and not is_nil(variable) ->
        if MapSet.member?(binding_vars, variable) do
          [binding_reference_issue(variable, meta, function)]
        else
          collect_binding_reference_issues(source, binding_vars)
        end

      nil ->
        collect_binding_reference_issues(source, binding_vars)
    end
  end

  defp assoc_binding_source?(source, binding_vars) do
    case binding_var_name(source) do
      variable when is_atom(variable) and not is_nil(variable) ->
        MapSet.member?(binding_vars, variable)

      nil ->
        false
    end
  end

  defp binding_reference_issue(variable, meta, reference) do
    issue(
      "expected Ecto query binding reference #{variable} to use as(:name)",
      :binding_variable_reference,
      meta,
      %{variable: variable, reference: reference}
    )
  end

  defp query_call({name, meta, args}) when is_atom(name) and is_list(args), do: {name, meta, args}

  defp query_call({{:., _dot_meta, [_module, name]}, meta, args})
       when is_atom(name) and is_list(args),
       do: {name, meta, args}

  defp query_call(_node), do: nil

  defp variable_ast?({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    not ellipsis_name?(name)
  end

  defp variable_ast?(_expr), do: false

  defp ellipsis_ast?({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    ellipsis_name?(name)
  end

  defp ellipsis_ast?(_expr), do: false

  defp ellipsis_name?(name), do: name == :...

  defp issue(message, reason, meta_source, extra_meta) do
    %Issue{
      check: __MODULE__,
      message: message,
      meta:
        %{
          reason: reason,
          line: line(meta_source),
          column: column(meta_source)
        }
        |> Map.merge(extra_meta)
    }
  end

  defp line(%{line: line}), do: line
  defp line(meta) when is_list(meta), do: Keyword.get(meta, :line)
  defp line({_name, meta, _args}) when is_list(meta), do: Keyword.get(meta, :line)
  defp line(_value), do: nil

  defp column(%{column: column}), do: column
  defp column(meta) when is_list(meta), do: Keyword.get(meta, :column)
  defp column({_name, meta, _args}) when is_list(meta), do: Keyword.get(meta, :column)
  defp column(_value), do: nil
end
