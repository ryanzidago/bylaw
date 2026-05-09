defmodule Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes do
  @moduledoc """
  Enforces Phoenix verified routes (`~p`) for application routes in the web layer.

  ## Examples

  This check is intentionally narrow:

  - it only runs in `BylawWeb` files and in tests using `BylawWeb.ConnCase`
  - it only flags path strings that normalize to a real router path
  - it ignores OpenAPI URI templates like `"/api/v1/tenants/{tenant_id}/..."`
  - it ignores HEEx route attributes for now
  Avoid:

        conn |> get("/api/v1/openapi")

        defp workspace_path(tenant_id, workspace_id) do
          "/api/v1/tenants/\#{tenant_id}/workspaces/\#{workspace_id}"
        end

        assert location == "/api/v1/tenants/\#{tenant.id}/workspaces/\#{workspace.id}"
  Prefer:

        conn |> get(~p"/api/v1/openapi")

        defp workspace_path(tenant_id, workspace_id) do
          ~p"/api/v1/tenants/\#{tenant_id}/workspaces/\#{workspace_id}"
        end

        assert location == ~p"/api/v1/tenants/\#{tenant.id}/workspaces/\#{workspace.id}"

        params = %{filters: %{0 => %{field: "name", op: "==", value: "Staging"}}}
        conn |> get(~p"/api/v1/tenants/\#{tenant_id}/workspaces?\#{params}")

  ## Notes

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
          {Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [check: @moduledoc]

  @dynamic_marker "__bylaw_dynamic_segment__"
  @fallback_router_paths [
    "/api/v1/openapi",
    "/api/v1/tenants/:tenant_id/workspaces/:workspace_id",
    "/api/v1/tenants/:tenant_id/workspaces/:workspace_id/runs/:run_id"
  ]
  @navigation_functions [:redirect, :push_navigate, :push_patch]
  @request_functions [:get, :post, :put, :patch, :delete, :head, :options]
  @route_helper_suffixes ["_location", "_path", "_url"]
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    if web_boundary_file?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> find_ast_issues(issue_meta)
    else
      []
    end
  end

  defp web_boundary_file?(source_file) do
    filename = source_file.filename

    cond do
      filename in ["lib/bylaw_web/endpoint.ex", "lib/bylaw_web/router.ex"] ->
        false

      String.starts_with?(filename, "lib/bylaw_web/") ->
        true

      String.ends_with?(filename, "_test.exs") ->
        uses_conn_case?(source_file)

      true ->
        false
    end
  end

  defp uses_conn_case?(source_file) do
    case Credo.SourceFile.ast(source_file) do
      {:ok, ast} -> ast_uses_conn_case?(ast)
      ast when is_tuple(ast) -> ast_uses_conn_case?(ast)
      _other -> false
    end
  end

  defp ast_uses_conn_case?(ast) do
    ast
    |> Macro.prewalk(false, fn
      {:use, _meta, [{:__aliases__, _aliases_meta, [:BylawWeb, :ConnCase]} | _rest]} = node,
      _found? ->
        {node, true}

      node, found? ->
        {node, found?}
    end)
    |> elem(1)
  end

  defp find_ast_issues({:ok, ast}, issue_meta) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
  end

  defp find_ast_issues(ast, issue_meta) when is_tuple(ast) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
  end

  defp find_ast_issues(_error, _issue_meta), do: []

  defp traverse({fun, meta, args} = ast, issues, issue_meta) when fun in @request_functions do
    case request_route_expr(args) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse({fun, meta, args} = ast, issues, issue_meta) when fun in @navigation_functions do
    case keyword_route_expr(args, :to) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse({:put_resp_header, meta, args} = ast, issues, issue_meta) do
    case location_header_route_expr(args) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(
         {fun, meta, [{name, _name_meta, _params}, [do: body]]} = ast,
         issues,
         issue_meta
       )
       when fun in [:def, :defp] do
    if route_helper_name?(name) and route_expr_matches_router?(body) do
      {ast, [issue_for(issue_meta, body, meta[:line] || 0, Atom.to_string(name)) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse({operator, meta, [left, right]} = ast, issues, issue_meta)
       when operator in [:==, :!=, :===, :!==] do
    if route_expr_matches_router?(left) or route_expr_matches_router?(right) do
      route_expr = if route_expr_matches_router?(left), do: left, else: right
      {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(
         {{:., _dot_meta, [_module, fun]}, meta, args} = ast,
         issues,
         issue_meta
       )
       when fun in @request_functions do
    case request_route_expr(args) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(
         {{:., _dot_meta, [_module, fun]}, meta, args} = ast,
         issues,
         issue_meta
       )
       when fun in @navigation_functions do
    case keyword_route_expr(args, :to) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(
         {{:., _dot_meta, [_module, :put_resp_header]}, meta, args} = ast,
         issues,
         issue_meta
       ) do
    case location_header_route_expr(args) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp request_route_expr(args) do
    cond do
      route_expr_matches_router?(Enum.at(args, 0)) -> Enum.at(args, 0)
      route_expr_matches_router?(Enum.at(args, 1)) -> Enum.at(args, 1)
      true -> nil
    end
  end

  defp keyword_route_expr(args, key) do
    route_expr =
      Enum.find_value(args, fn
        list when is_list(list) -> Keyword.get(list, key)
        _other -> nil
      end)

    if route_expr_matches_router?(route_expr), do: route_expr, else: nil
  end

  defp location_header_route_expr(args) do
    cond do
      Enum.at(args, 0) == "location" and route_expr_matches_router?(Enum.at(args, 1)) ->
        Enum.at(args, 1)

      Enum.at(args, 1) == "location" and route_expr_matches_router?(Enum.at(args, 2)) ->
        Enum.at(args, 2)

      true ->
        nil
    end
  end

  defp route_helper_name?(name) when is_atom(name) do
    name_string = Atom.to_string(name)
    Enum.any?(@route_helper_suffixes, &String.ends_with?(name_string, &1))
  end

  defp route_helper_name?(_other), do: false

  defp issue_for(issue_meta, route_expr, line_no, trigger_override \\ nil) do
    trigger = trigger_override || route_trigger(route_expr)

    format_issue(
      issue_meta,
      message:
        "Use Phoenix verified routes (`~p`) instead of literal or interpolated route strings that match router paths.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp route_trigger(expr) do
    case route_shape(expr) do
      nil -> Macro.to_string(expr)
      shape -> "/" <> Enum.join(shape, "/")
    end
  end

  defp route_expr_matches_router?(expr) do
    case route_shape(expr) do
      nil -> nested_route_expr_matches_router?(expr)
      shape -> route_matches_router?(shape)
    end
  end

  defp nested_route_expr_matches_router?({:sigil_H, _meta, _args}), do: false
  defp nested_route_expr_matches_router?({:sigil_p, _meta, _args}), do: false

  defp nested_route_expr_matches_router?({form, _meta, args})
       when is_atom(form) and is_list(args) do
    Enum.any?(args, &route_expr_matches_router?/1)
  end

  defp nested_route_expr_matches_router?(list) when is_list(list) do
    Enum.any?(list, &route_expr_matches_router?/1)
  end

  defp nested_route_expr_matches_router?({left, right}) do
    route_expr_matches_router?(left) or route_expr_matches_router?(right)
  end

  defp nested_route_expr_matches_router?(_other), do: false

  defp route_shape(expr) when is_binary(expr), do: normalize_candidate_path(expr)

  defp route_shape({:<<>>, _meta, parts}) when is_list(parts) do
    parts
    |> Enum.map_join("", &binary_part_to_string/1)
    |> normalize_candidate_path()
  end

  defp route_shape({:__block__, _meta, exprs}) when is_list(exprs) do
    exprs
    |> List.last()
    |> route_shape()
  end

  defp route_shape(_other), do: nil

  defp binary_part_to_string(part) when is_binary(part), do: part
  defp binary_part_to_string(_part), do: @dynamic_marker

  defp normalize_candidate_path(path) when is_binary(path) do
    cond do
      not String.starts_with?(path, "/") -> nil
      String.contains?(path, "{") -> nil
      true -> normalize_path_segments(path)
    end
  end

  defp normalize_router_path(path) do
    stripped_path = strip_query_and_fragment(path)
    normalized_path = Regex.replace(~r/:[a-zA-Z_][a-zA-Z0-9_]*/, stripped_path, @dynamic_marker)

    split_segments(normalized_path)
  end

  defp normalize_path_segments(path) do
    path
    |> strip_query_and_fragment()
    |> split_segments()
    |> Enum.map(fn segment ->
      if String.contains?(segment, @dynamic_marker),
        do: dynamic_markerized_segment(segment),
        else: segment
    end)
  end

  defp dynamic_markerized_segment(segment) do
    Regex.replace(~r/#{Regex.escape(@dynamic_marker)}+/, segment, @dynamic_marker)
  end

  defp strip_query_and_fragment(path) do
    path
    |> String.split(["?", "#"], parts: 2)
    |> hd()
  end

  defp split_segments(path) do
    String.split(path, "/", trim: true)
  end

  defp route_matches_router?(shape) do
    MapSet.member?(router_paths(), shape)
  end

  defp router_paths do
    phoenix_router = Module.concat([Phoenix, Router])

    if Code.ensure_loaded?(BylawWeb.Router) and Code.ensure_loaded?(phoenix_router) do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(phoenix_router, :routes, [BylawWeb.Router])
      |> Enum.map(&normalize_router_path(&1.path))
      |> MapSet.new()
    else
      fallback_router_paths()
    end
  end

  defp fallback_router_paths do
    @fallback_router_paths
    |> Enum.map(&normalize_router_path/1)
    |> MapSet.new()
  end
end
