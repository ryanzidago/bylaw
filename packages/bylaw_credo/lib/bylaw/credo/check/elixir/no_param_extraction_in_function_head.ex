defmodule Bylaw.Credo.Check.Elixir.NoParamExtractionInFunctionHead do
  @moduledoc """
  Prevents destructuring map/struct parameters in function heads just to extract values.

  ## Examples

  Avoid:

        def perform(%Oban.Job{args: args, attempt: attempt, max_attempts: max_attempts}) do
          ...
        end

        def create_user(%{email: email, role: role} = attrs) do
          ...
        end

        def perform(%Oban.Job{args: %{"invoice_id" => invoice_id, "tenant_id" => tenant_id}}) do
          ...
        end

        Enum.map(jobs, fn %Oban.Job{args: args} -> process(args) end)

  Prefer:

        def perform(%Oban.Job{} = job) do
          with {:ok, invoice_id} <- fetch_required_arg(job.args, "invoice_id", :missing_invoice_id),
               {:ok, tenant_id} <- fetch_required_arg(job.args, "tenant_id", :missing_tenant_id) do
            ...
          end
        end

        def create_user(attrs) do
          with {:ok, email} <- Map.fetch(attrs, :email) do
            role = Map.get(attrs, :role, :member)
            ...
          end
        end

        Enum.map(jobs, fn %Oban.Job{} = job -> process(job.args) end)

  ## Notes

  Function heads have two jobs: naming parameters and selecting which clause
  runs. When they also pull values out of maps and structs, clause selection
  and data extraction become harder to distinguish.

  Moving extraction into the function body keeps the head focused on what the
  clause accepts and makes missing-data handling more explicit.

  Pattern matching in function heads is fine when it does real dispatch work -
  deciding *which clause runs*, not pulling data out for later use.

  Examples of dispatch-oriented pattern matching:

        def fetch_user(nil), do: {:error, :missing_user_id}
        def fetch_user(user_id), do: Accounts.get_user(user_id)

        def process(%{type: :email} = notification), do: send_email(notification)
        def process(%{type: :sms} = notification), do: send_sms(notification)

        def perform(%Oban.Job{args: %{"invoice_id" => _}} = job) do
          invoice_id = Map.fetch!(job.args, "invoice_id")
          ...
        end

        def perform(%Oban.Job{}), do: {:discard, :missing_invoice_id}

        def create(conn, %{"_json" => list}) when is_list(list) do
          ...
        end

        def handle_result({:ok, value}), do: {:ok, value}
        def handle_result({:error, reason}), do: {:error, reason}

  This check uses static AST analysis, so it favors clear source-level patterns over runtime behavior.

  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoParamExtractionInFunctionHead, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    explanations: [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.SourceFile.ast()
    |> find_violations(issue_meta)
  end

  defp find_violations({:ok, ast}, issue_meta) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
  end

  defp find_violations(ast, issue_meta) when is_tuple(ast) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
  end

  defp find_violations(_error, _issue_meta), do: []

  # def/defp with when guard
  defp traverse(
         {fun, _def_meta, [{:when, _when_meta, [{_name, _name_meta, params} | guards]} | _body]} =
           node,
         issues,
         issue_meta
       )
       when fun in [:def, :defp] and is_list(params) do
    guard_vars = collect_guard_variables(guards)
    new_issues = Enum.flat_map(params, &find_extractions(&1, issue_meta, guard_vars, &1))
    {node, new_issues ++ issues}
  end

  # def/defp without guard
  defp traverse(
         {fun, _def_meta, [{_name, _name_meta, params} | _body]} = node,
         issues,
         issue_meta
       )
       when fun in [:def, :defp] and is_list(params) do
    new_issues = Enum.flat_map(params, &find_extractions(&1, issue_meta, MapSet.new(), &1))
    {node, new_issues ++ issues}
  end

  # fn clause: fn params -> body end
  defp traverse(
         {:->, _arrow_meta, [params, _body]} = node,
         issues,
         issue_meta
       )
       when is_list(params) do
    new_issues = Enum.flat_map(params, &find_extractions(&1, issue_meta, MapSet.new(), &1))
    {node, new_issues ++ issues}
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  # Match operator: check both sides
  defp find_extractions({:=, _match_meta, [left, right]}, issue_meta, guard_vars, whole_param) do
    find_extractions(left, issue_meta, guard_vars, whole_param) ++
      find_extractions(right, issue_meta, guard_vars, whole_param)
  end

  # Struct pattern: %Struct{fields...}
  defp find_extractions(
         {:%, meta, [_struct, {:%{}, _map_meta, fields}]} = pattern,
         issue_meta,
         guard_vars,
         whole_param
       )
       when is_list(fields) do
    if any_field_extracts_variable?(fields, guard_vars) do
      [create_issue(issue_meta, meta, pattern, whole_param, guard_vars)]
    else
      []
    end
  end

  # Map pattern: %{fields...}
  defp find_extractions({:%{}, meta, fields} = pattern, issue_meta, guard_vars, whole_param)
       when is_list(fields) do
    if any_field_extracts_variable?(fields, guard_vars) do
      [create_issue(issue_meta, meta, pattern, whole_param, guard_vars)]
    else
      []
    end
  end

  defp find_extractions(_node, _issue_meta, _guard_vars, _whole_param), do: []

  defp any_field_extracts_variable?(fields, guard_vars) do
    Enum.any?(fields, fn
      {_key, value} -> contains_variable_binding?(value, guard_vars)
      _other -> false
    end)
  end

  # Variable binding (not underscore-prefixed, not used in guard)
  defp contains_variable_binding?({name, _var_meta, context}, guard_vars)
       when is_atom(name) and is_atom(context) do
    name_string = Atom.to_string(name)

    not String.starts_with?(name_string, "_") and
      not MapSet.member?(guard_vars, name)
  end

  # Pin operator - not a binding
  defp contains_variable_binding?({:^, _pin_meta, _pin_args}, _guard_vars), do: false

  # Match operator
  defp contains_variable_binding?({:=, _match_meta, [left, right]}, guard_vars) do
    contains_variable_binding?(left, guard_vars) or
      contains_variable_binding?(right, guard_vars)
  end

  # Nested struct
  defp contains_variable_binding?(
         {:%, _struct_meta, [_struct, {:%{}, _map_meta, fields}]},
         guard_vars
       )
       when is_list(fields) do
    any_field_extracts_variable?(fields, guard_vars)
  end

  # Nested map
  defp contains_variable_binding?({:%{}, _map_meta, fields}, guard_vars) when is_list(fields) do
    any_field_extracts_variable?(fields, guard_vars)
  end

  # 3+ element tuple
  defp contains_variable_binding?({:{}, _tuple_meta, elements}, guard_vars) do
    Enum.any?(elements, &contains_variable_binding?(&1, guard_vars))
  end

  # List
  defp contains_variable_binding?(list, guard_vars) when is_list(list) do
    Enum.any?(list, &contains_variable_binding?(&1, guard_vars))
  end

  # 2-element tuple (literal in AST)
  defp contains_variable_binding?({a, b}, guard_vars) do
    contains_variable_binding?(a, guard_vars) or
      contains_variable_binding?(b, guard_vars)
  end

  # Literals (atoms, numbers, strings, etc.)
  defp contains_variable_binding?(_literal, _guard_vars), do: false

  defp collect_guard_variables(guards) do
    guards
    |> Macro.prewalk(MapSet.new(), fn
      {name, _meta, context} = node, acc when is_atom(name) and is_atom(context) ->
        {node, MapSet.put(acc, name)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp create_issue(issue_meta, meta, pattern, whole_param, guard_vars) do
    trigger = Macro.to_string(pattern)

    format_issue(
      issue_meta,
      message: message_for(pattern, whole_param, guard_vars, trigger),
      trigger: trigger,
      line_no: meta[:line] || 0
    )
  end

  defp message_for(pattern, whole_param, guard_vars, trigger) do
    binding_name = binding_name_for_param(whole_param) || suggested_binding_name(pattern)

    rewritten_pattern =
      pattern
      |> dispatch_only_pattern(guard_vars)
      |> Macro.to_string()

    example_head = "#{rewritten_pattern} = #{binding_name}"

    action =
      if binding_name_for_param(whole_param) do
        "keep the whole param binding"
      else
        "bind the whole param"
      end

    "Keep function heads for clause selection. Instead of `#{trigger}`, #{action} and use a head like " <>
      "`#{example_head}`, then read the needed values from `#{binding_name}` in the body" <>
      access_hint(pattern, binding_name) <> "."
  end

  defp binding_name_for_param({:=, _meta, [left, right]}) do
    binding_name_for_node(left) || binding_name_for_node(right)
  end

  defp binding_name_for_param(_param), do: nil

  defp binding_name_for_node({name, _meta, context}) when is_atom(name) and is_atom(context) do
    name_string = Atom.to_string(name)

    if String.starts_with?(name_string, "_"), do: nil, else: name_string
  end

  defp binding_name_for_node(_node), do: nil

  defp suggested_binding_name({:%, _meta, [struct, _fields]}) do
    struct
    |> struct_name()
    |> Macro.underscore()
  end

  defp suggested_binding_name(_pattern), do: "value"

  defp struct_name({:__aliases__, _meta, segments}) do
    segments
    |> List.last()
    |> Atom.to_string()
  end

  defp struct_name(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp dispatch_only_pattern({name, _meta, context}, guard_vars)
       when is_atom(name) and is_atom(context) do
    if preserve_binding?(name, guard_vars), do: Macro.var(name, nil), else: Macro.var(:_, nil)
  end

  defp dispatch_only_pattern({:^, _pin_meta, _pin_args} = pin, _guard_vars), do: pin

  defp dispatch_only_pattern({:=, meta, [left, right]}, guard_vars) do
    {:=, meta,
     [dispatch_only_pattern(left, guard_vars), dispatch_only_pattern(right, guard_vars)]}
  end

  defp dispatch_only_pattern(
         {:%, meta, [struct, {:%{}, map_meta, fields}]},
         guard_vars
       )
       when is_list(fields) do
    kept_fields =
      fields
      |> Enum.map(&dispatch_only_struct_field(&1, guard_vars))
      |> Enum.reject(&is_nil/1)

    {:%, meta, [struct, {:%{}, map_meta, kept_fields}]}
  end

  defp dispatch_only_pattern({:%{}, meta, fields}, guard_vars) when is_list(fields) do
    transformed_fields =
      Enum.map(fields, fn
        {key, value} -> {key, dispatch_only_pattern(value, guard_vars)}
        other -> other
      end)

    {:%{}, meta, transformed_fields}
  end

  defp dispatch_only_pattern({:{}, meta, elements}, guard_vars) when is_list(elements) do
    {:{}, meta, Enum.map(elements, &dispatch_only_pattern(&1, guard_vars))}
  end

  defp dispatch_only_pattern(list, guard_vars) when is_list(list) do
    Enum.map(list, &dispatch_only_pattern(&1, guard_vars))
  end

  defp dispatch_only_pattern({left, right}, guard_vars) do
    {dispatch_only_pattern(left, guard_vars), dispatch_only_pattern(right, guard_vars)}
  end

  defp dispatch_only_pattern(literal, _guard_vars), do: literal

  defp dispatch_only_struct_field({key, value}, guard_vars) do
    transformed_value = dispatch_only_pattern(value, guard_vars)

    if simple_extract_binding?(value, guard_vars) do
      nil
    else
      {key, transformed_value}
    end
  end

  defp dispatch_only_struct_field(other, _guard_vars), do: other

  defp simple_extract_binding?({name, _meta, context}, guard_vars)
       when is_atom(name) and is_atom(context) do
    not preserve_binding?(name, guard_vars)
  end

  defp simple_extract_binding?(_value, _guard_vars), do: false

  defp preserve_binding?(name, guard_vars) do
    name_string = Atom.to_string(name)
    String.starts_with?(name_string, "_") or MapSet.member?(guard_vars, name)
  end

  defp access_hint(pattern, binding_name) do
    case single_atom_field(pattern) do
      {:ok, field_name} -> " (for example `#{binding_name}.#{field_name}`)"
      :error -> ""
    end
  end

  defp single_atom_field({:%, _meta, [_struct, {:%{}, _map_meta, [{field_name, value}]}]}) do
    if simple_field_value?(value), do: {:ok, field_name}, else: :error
  end

  defp single_atom_field({:%{}, _meta, [{field_name, value}]}) when is_atom(field_name) do
    if simple_field_value?(value), do: {:ok, field_name}, else: :error
  end

  defp single_atom_field(_pattern), do: :error

  defp simple_field_value?({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: true

  defp simple_field_value?(_value), do: false
end
