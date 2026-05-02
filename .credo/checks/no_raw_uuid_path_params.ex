defmodule Bylaw.Credo.Check.Warning.NoRawUUIDPathParams do
  @moduledoc """
  Disallows reading UUID path params directly in API boundary code.

  API controllers and auth plugs should call
  `BylawWeb.API.ParamCasting.cast_uuidv7_params/2` as soon as they cross the
  HTTP boundary. That keeps malformed UUIDs from leaking into auth or context
  code where they would otherwise produce misleading `401` or `404` responses.

  ## Examples

  Bad:

      def show(conn, params) do
        run_id = params["id"]
        tenant_id = conn.path_params["tenant_id"]
      end

  Also bad:

      def call(conn, _opts) do
        tenant_id = Map.fetch!(conn.path_params, "tenant_id")
      end

  Good:

      def show(conn, _params) do
        with {:ok, %{"tenant_id" => tenant_id, "workspace_id" => workspace_id, "id" => run_id}} <-
               ParamCasting.cast_uuidv7_params(conn.path_params, ~w(tenant_id workspace_id id)) do
          ...
        end
      end
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: """
      Do not read UUID path params directly from `params`, `conn.params`, or
      `conn.path_params` in API controllers or auth plugs. Cast them once with
      `ParamCasting.cast_uuidv7_params/2` at the HTTP boundary so malformed
      values return a consistent `400 Bad Request`.
      """
    ]

  @fallback_uuid_path_param_names ~w(id tenant_id workspace_id conversation_id run_id)
  @router_path Path.expand("../../lib/bylaw_web/router.ex", __DIR__)
  @uuid_path_param_names (case File.read(@router_path) do
                            {:ok, router_source} ->
                              matches =
                                Regex.scan(~r/:([a-z_]+)/, router_source, capture: :all_but_first)

                              param_names = List.flatten(matches)

                              uuid_param_names =
                                Enum.filter(param_names, fn
                                  "id" -> true
                                  param_name -> String.ends_with?(param_name, "_id")
                                end)

                              MapSet.new(uuid_param_names)

                            {:error, _reason} ->
                              MapSet.new(@fallback_uuid_path_param_names)
                          end)

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    if api_boundary_file?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp api_boundary_file?(filename) do
    (String.starts_with?(filename, "lib/bylaw_web/controllers/api/v1/") and
       String.ends_with?(filename, "_controller.ex")) or
      (String.starts_with?(filename, "lib/bylaw_web/auth/") and
         String.ends_with?(filename, ".ex"))
  end

  defp traverse(
         {{:., meta, [Access, :get]}, call_meta, [source, key]} = ast,
         issues,
         issue_meta
       ) do
    maybe_add_issue(ast, issues, issue_meta, source, key, meta[:line] || call_meta[:line] || 0)
  end

  defp traverse(
         {{:., _meta, [{:__aliases__, _aliases_meta, [:Map]}, function]}, call_meta,
          [source, key | _rest]} =
           ast,
         issues,
         issue_meta
       )
       when function in [:get, :fetch, :fetch!] do
    maybe_add_issue(ast, issues, issue_meta, source, key, call_meta[:line] || 0)
  end

  defp traverse({:get_in, meta, [source, [key]]} = ast, issues, issue_meta) do
    maybe_add_issue(ast, issues, issue_meta, source, key, meta[:line] || 0)
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp maybe_add_issue(ast, issues, issue_meta, source, key, line_no) do
    if raw_path_param_source?(source) and uuid_path_param_name?(key) do
      {ast, [issue_for(issue_meta, key, line_no) | issues]}
    else
      {ast, issues}
    end
  end

  defp raw_path_param_source?({name, _meta, context})
       when name in [:params, :path_params] and is_atom(context),
       do: true

  defp raw_path_param_source?(
         {{:., _meta, [{:conn, _conn_meta, context}, field]}, _call_meta, []}
       )
       when field in [:params, :path_params] and is_atom(context),
       do: true

  defp raw_path_param_source?(_other), do: false

  defp issue_for(issue_meta, key, line_no) do
    format_issue(
      issue_meta,
      message:
        "Do not read raw UUID path param `#{key}` directly. Use `ParamCasting.cast_uuidv7_params/2` at the HTTP boundary.",
      trigger: key,
      line_no: line_no
    )
  end

  defp uuid_path_param_name?(name) when is_binary(name) do
    MapSet.member?(@uuid_path_param_names, name)
  end

  defp uuid_path_param_name?(_other), do: false
end
