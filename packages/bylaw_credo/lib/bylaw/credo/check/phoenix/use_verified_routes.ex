defmodule Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes do
  @moduledoc """
  Enforces Phoenix verified routes (`~p`) for application routes in the web layer.

  ## Examples

  Configure the Phoenix web boundary and one or more routers that define the
  routes to match:

  ```elixir
  {Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes,
   [
     web_paths: ["lib/my_app_web/"],
     endpoint_paths: ["lib/my_app_web/endpoint.ex"],
     router_paths: ["lib/my_app_web/router.ex"],
     conn_case_modules: [MyAppWeb.ConnCase],
     routers: [MyAppWeb.Router, MyAppWeb.AdminRouter]
   ]}
  ```


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

  The check only runs in configured web paths and tests using configured ConnCase
  modules. It only flags path strings that normalize to a route exposed by one
  of the configured routers or `:fallback_router_paths`. It ignores OpenAPI URI
  templates like `"/api/v1/tenants/{tenant_id}/..."` and HEEx route attributes
  for now.

  This check uses static AST analysis, so it favors clear source-level patterns over runtime behavior.
  Configure `:fallback_router_paths` when router modules are unavailable during Credo analysis.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes,
           [
             web_paths: ["lib/my_app_web/"],
             endpoint_paths: ["lib/my_app_web/endpoint.ex"],
             router_paths: ["lib/my_app_web/router.ex"],
             conn_case_modules: [MyAppWeb.ConnCase],
             routers: [MyAppWeb.Router, MyAppWeb.AdminRouter],
             fallback_router_paths: [
               "/api/v1/openapi",
               "/admin/users/:id"
             ]
           ]}
        ]
      }
    ]
  }
  ```

  - `:web_paths` - Paths containing files where route strings should be checked.
  - `:endpoint_paths` - Endpoint files to skip even when they match `:web_paths`.
  - `:router_paths` - Router files to skip even when they match `:web_paths`.
  - `:conn_case_modules` - Test case modules that identify request/controller tests.
  - `:routers` - Phoenix router modules whose route paths should be matched.
  - `:fallback_router_paths` - Route path patterns to use when router modules are unavailable.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Phoenix.UseVerifiedRoutes,
           [
             web_paths: ["lib/my_app_web/"],
             conn_case_modules: [MyAppWeb.ConnCase],
             routers: [MyAppWeb.Router]
           ]}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [
      web_paths: [],
      endpoint_paths: [],
      router_paths: [],
      conn_case_modules: [],
      routers: [],
      fallback_router_paths: []
    ],
    explanations: [
      check: @moduledoc,
      params: [
        web_paths: "Paths containing files where route strings should be checked.",
        endpoint_paths: "Endpoint files to skip even when they match `:web_paths`.",
        router_paths: "Router files to skip even when they match `:web_paths`.",
        conn_case_modules: "Test case modules that identify request/controller tests.",
        routers: "Phoenix router modules whose route paths should be matched.",
        fallback_router_paths: "Route path patterns to use when router modules are unavailable."
      ]
    ]

  @dynamic_marker "__bylaw_dynamic_segment__"
  @navigation_functions [:redirect, :push_navigate, :push_patch]
  @request_functions [:get, :post, :put, :patch, :delete, :head, :options]
  @route_helper_suffixes ["_location", "_path", "_url"]
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    opts = opts(params)

    if web_boundary_file?(source_file, opts) do
      issue_meta = IssueMeta.for(source_file, params)
      router_paths = router_paths(opts)

      source_file
      |> Credo.SourceFile.ast()
      |> find_ast_issues(issue_meta, router_paths)
    else
      []
    end
  end

  defp opts(params) do
    %{
      web_paths: Params.get(params, :web_paths, __MODULE__),
      endpoint_paths: Params.get(params, :endpoint_paths, __MODULE__),
      router_paths: Params.get(params, :router_paths, __MODULE__),
      conn_case_modules: Params.get(params, :conn_case_modules, __MODULE__),
      routers: Params.get(params, :routers, __MODULE__),
      fallback_router_paths: Params.get(params, :fallback_router_paths, __MODULE__)
    }
  end

  defp web_boundary_file?(source_file, opts) do
    filename = source_file.filename

    cond do
      path_matches?(filename, opts.endpoint_paths) ->
        false

      path_matches?(filename, opts.router_paths) ->
        false

      path_matches?(filename, opts.web_paths) ->
        true

      String.ends_with?(filename, "_test.exs") ->
        uses_conn_case?(source_file, opts.conn_case_modules)

      true ->
        false
    end
  end

  defp path_matches?(filename, path_patterns) do
    Enum.any?(path_patterns, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end

  defp uses_conn_case?(source_file, conn_case_modules) do
    conn_case_module_names = module_names(conn_case_modules)

    case Credo.SourceFile.ast(source_file) do
      {:ok, ast} -> ast_uses_conn_case?(ast, conn_case_module_names)
      ast when is_tuple(ast) -> ast_uses_conn_case?(ast, conn_case_module_names)
      _other -> false
    end
  end

  defp ast_uses_conn_case?(ast, conn_case_module_names) do
    ast
    |> Macro.prewalk(false, fn
      {:use, _meta, [{:__aliases__, _aliases_meta, module_parts} | _rest]} = node, _found? ->
        {node, module_name(module_parts) in conn_case_module_names}

      node, found? ->
        {node, found?}
    end)
    |> elem(1)
  end

  defp find_ast_issues({:ok, ast}, issue_meta, router_paths) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta, router_paths))
    |> elem(1)
  end

  defp find_ast_issues(ast, issue_meta, router_paths) when is_tuple(ast) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta, router_paths))
    |> elem(1)
  end

  defp find_ast_issues(_error, _issue_meta, _router_paths), do: []

  defp traverse({fun, meta, args} = ast, issues, issue_meta, router_paths)
       when fun in @request_functions do
    case request_route_expr(args, router_paths) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse({fun, meta, args} = ast, issues, issue_meta, router_paths)
       when fun in @navigation_functions do
    case keyword_route_expr(args, :to, router_paths) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse({:put_resp_header, meta, args} = ast, issues, issue_meta, router_paths) do
    case location_header_route_expr(args, router_paths) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(
         {fun, meta, [{name, _name_meta, _params}, [do: body]]} = ast,
         issues,
         issue_meta,
         router_paths
       )
       when fun in [:def, :defp] do
    if route_helper_name?(name) and route_expr_matches_router?(body, router_paths) do
      {ast, [issue_for(issue_meta, body, meta[:line] || 0, Atom.to_string(name)) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse({operator, meta, [left, right]} = ast, issues, issue_meta, router_paths)
       when operator in [:==, :!=, :===, :!==] do
    if route_expr_matches_router?(left, router_paths) or
         route_expr_matches_router?(right, router_paths) do
      route_expr = if route_expr_matches_router?(left, router_paths), do: left, else: right
      {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(
         {{:., _dot_meta, [_module, fun]}, meta, args} = ast,
         issues,
         issue_meta,
         router_paths
       )
       when fun in @request_functions do
    case request_route_expr(args, router_paths) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(
         {{:., _dot_meta, [_module, fun]}, meta, args} = ast,
         issues,
         issue_meta,
         router_paths
       )
       when fun in @navigation_functions do
    case keyword_route_expr(args, :to, router_paths) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(
         {{:., _dot_meta, [_module, :put_resp_header]}, meta, args} = ast,
         issues,
         issue_meta,
         router_paths
       ) do
    case location_header_route_expr(args, router_paths) do
      nil ->
        {ast, issues}

      route_expr ->
        {ast, [issue_for(issue_meta, route_expr, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta, _router_paths), do: {ast, issues}

  defp request_route_expr(args, router_paths) do
    cond do
      route_expr_matches_router?(Enum.at(args, 0), router_paths) -> Enum.at(args, 0)
      route_expr_matches_router?(Enum.at(args, 1), router_paths) -> Enum.at(args, 1)
      true -> nil
    end
  end

  defp keyword_route_expr(args, key, router_paths) do
    route_expr =
      Enum.find_value(args, fn
        list when is_list(list) -> Keyword.get(list, key)
        _other -> nil
      end)

    if route_expr_matches_router?(route_expr, router_paths), do: route_expr, else: nil
  end

  defp location_header_route_expr(args, router_paths) do
    cond do
      Enum.at(args, 0) == "location" and
          route_expr_matches_router?(Enum.at(args, 1), router_paths) ->
        Enum.at(args, 1)

      Enum.at(args, 1) == "location" and
          route_expr_matches_router?(Enum.at(args, 2), router_paths) ->
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

  defp route_expr_matches_router?(expr, router_paths) do
    case route_shape(expr) do
      nil -> nested_route_expr_matches_router?(expr, router_paths)
      shape -> route_matches_router?(shape, router_paths)
    end
  end

  defp nested_route_expr_matches_router?({:sigil_H, _meta, _args}, _router_paths), do: false
  defp nested_route_expr_matches_router?({:sigil_p, _meta, _args}, _router_paths), do: false

  defp nested_route_expr_matches_router?({form, _meta, args}, router_paths)
       when is_atom(form) and is_list(args) do
    Enum.any?(args, &route_expr_matches_router?(&1, router_paths))
  end

  defp nested_route_expr_matches_router?(list, router_paths) when is_list(list) do
    Enum.any?(list, &route_expr_matches_router?(&1, router_paths))
  end

  defp nested_route_expr_matches_router?({left, right}, router_paths) do
    route_expr_matches_router?(left, router_paths) or
      route_expr_matches_router?(right, router_paths)
  end

  defp nested_route_expr_matches_router?(_other, _router_paths), do: false

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

  defp route_matches_router?(shape, router_paths) do
    MapSet.member?(router_paths, shape)
  end

  defp router_paths(%{routers: routers, fallback_router_paths: fallback_router_paths}) do
    phoenix_router = Module.concat([Phoenix, Router])

    router_paths =
      if Code.ensure_loaded?(phoenix_router) do
        routers
        |> Enum.filter(&Code.ensure_loaded?/1)
        |> Enum.flat_map(fn router ->
          # credo:disable-for-next-line Credo.Check.Refactor.Apply
          apply(phoenix_router, :routes, [router])
        end)
        |> Enum.map(&normalize_router_path(&1.path))
      else
        []
      end

    MapSet.new(router_paths ++ fallback_paths(fallback_router_paths))
  end

  defp fallback_paths(fallback_router_paths) do
    Enum.map(fallback_router_paths, &normalize_router_path/1)
  end

  defp module_names(modules), do: Enum.map(modules, &module_name/1)

  defp module_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp module_name(module) when is_binary(module), do: module

  defp module_name(module_parts) when is_list(module_parts) do
    Enum.map_join(module_parts, ".", &Atom.to_string/1)
  end
end
