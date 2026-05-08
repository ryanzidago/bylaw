defmodule Bylaw.Credo.Check.Phoenix.ContextFunctionNaming do
  @moduledoc """
  Enforces consistent naming conventions for context lookup functions based on
  their return types, staying close to the `Ecto.Repo` conventions
  (e.g. `Repo.get/2` returns `record | nil`, `Repo.get!/2` raises).
  `fetch_*` extends this with a tagged-tuple variant for explicit error handling.

  The convention is:

  - `get_*`   -> returns `record | nil`   (like `Repo.get/2`)
  - `get_*!`  -> returns `record` / raises (like `Repo.get!/2`)
  - `fetch_*` -> returns `{:ok, record} | {:error, reason}`
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: """
      Context lookup functions must follow a naming convention that signals their
      return type, consistent with `Ecto.Repo` (e.g. `Repo.get/2`, `Repo.get!/2`):

      - `get_*`   functions return `record | nil`
      - `get_*!`  functions return `record` (raise on not found)
      - `fetch_*` functions return `{:ok, record} | {:error, reason}`

      This should be refactored:

          @spec get_workspace(binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
          def get_workspace(id), do: ...

      Into this:

          @spec fetch_workspace(binary()) :: {:ok, Workspace.t()} | {:error, :not_found}
          def fetch_workspace(id), do: ...

      Or this:

          @spec get_workspace(binary()) :: Workspace.t() | nil
          def get_workspace(id), do: ...
      """,
      params: [
        excluded_paths: "List of paths or regex to exclude from this check"
      ]
    ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)

    case ignore_path?(source_file.filename, Params.get(params, :excluded_paths, __MODULE__)) do
      true ->
        []

      false ->
        Credo.Code.prewalk(source_file, &walk/2, ctx).issues
    end
  end

  defp walk(
         {:@, _meta, [{:spec, _spec_meta, [{:"::", _op_meta, [call, return_type]}]}]} = ast,
         ctx
       ) do
    {ast, check_spec(ctx, call, return_type)}
  end

  defp walk(
         {:@, _meta,
          [
            {:spec, _spec_meta,
             [{:when, _when_meta, [{:"::", _op_meta, [call, return_type]} | _constraints]}]}
          ]} = ast,
         ctx
       ) do
    {ast, check_spec(ctx, call, return_type)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp check_spec(ctx, call, return_type) do
    case extract_function_name(call) do
      nil ->
        ctx

      {name_str, meta} ->
        tagged_tuple_kind = tagged_tuple_kind(return_type)
        allows_nil = contains_nil?(return_type)
        maybe_add_naming_issue(ctx, name_str, meta, tagged_tuple_kind, allows_nil)
    end
  end

  defp maybe_add_naming_issue(ctx, name_str, meta, tagged_tuple_kind, allows_nil) do
    has_any_tagged_tuple = tagged_tuple_kind != :none

    cond do
      get_prefix_without_bang?(name_str) and has_any_tagged_tuple ->
        add_get_returns_tagged_tuple_issue(ctx, name_str, meta)

      fetch_prefix?(name_str) and tagged_tuple_kind != :ok_and_error ->
        add_fetch_missing_contract_issue(ctx, name_str, meta)

      get_bang?(name_str) ->
        maybe_add_bang_issue(ctx, name_str, meta, has_any_tagged_tuple, allows_nil)

      true ->
        ctx
    end
  end

  defp maybe_add_bang_issue(ctx, name_str, meta, has_any_tagged_tuple, allows_nil) do
    cond do
      has_any_tagged_tuple -> add_bang_returns_tagged_tuple_issue(ctx, name_str, meta)
      allows_nil -> add_bang_allows_nil_issue(ctx, name_str, meta)
      true -> ctx
    end
  end

  defp get_prefix_without_bang?(name_str), do: get_prefix?(name_str) and not bang?(name_str)
  defp get_bang?(name_str), do: bang?(name_str) and get_prefix?(name_str)

  defp add_get_returns_tagged_tuple_issue(ctx, name_str, meta) do
    put_issue(
      ctx,
      format_issue(
        ctx,
        message:
          "`#{name_str}` returns tagged tuples but uses `get_` prefix. " <>
            "Rename to `#{to_fetch_name(name_str)}` or change return type to `record | nil`.",
        trigger: name_str,
        line_no: meta[:line]
      )
    )
  end

  defp add_fetch_missing_contract_issue(ctx, name_str, meta) do
    put_issue(
      ctx,
      format_issue(
        ctx,
        message:
          "`#{name_str}` uses `fetch_` prefix but does not return " <>
            "`{:ok, record} | {:error, reason}`. " <>
            "Return tagged tuples or rename to `get_` prefix.",
        trigger: name_str,
        line_no: meta[:line]
      )
    )
  end

  defp add_bang_returns_tagged_tuple_issue(ctx, name_str, meta) do
    put_issue(
      ctx,
      format_issue(
        ctx,
        message:
          "`#{name_str}` returns tagged tuples but uses bang (`!`) suffix. " <>
            "Bang functions should return the record directly or raise.",
        trigger: name_str,
        line_no: meta[:line]
      )
    )
  end

  defp add_bang_allows_nil_issue(ctx, name_str, meta) do
    put_issue(
      ctx,
      format_issue(
        ctx,
        message:
          "`#{name_str}` allows `nil` but uses bang (`!`) suffix. " <>
            "Bang functions should return the record directly or raise.",
        trigger: name_str,
        line_no: meta[:line]
      )
    )
  end

  defp extract_function_name({name, meta, args}) when is_atom(name) and is_list(args) do
    {Atom.to_string(name), meta}
  end

  defp extract_function_name(_ast), do: nil

  defp get_prefix?(name), do: String.starts_with?(name, "get_")
  defp fetch_prefix?(name), do: String.starts_with?(name, "fetch_")
  defp bang?(name), do: String.ends_with?(name, "!")

  defp to_fetch_name("get_" <> rest), do: "fetch_" <> String.trim_trailing(rest, "!")

  defp tagged_tuple_kind({:|, _meta, [left, right]}) do
    merge_tagged_tuple_kinds(tagged_tuple_kind(left), tagged_tuple_kind(right))
  end

  defp tagged_tuple_kind({:ok, _type}), do: :ok
  defp tagged_tuple_kind({:error, _type}), do: :error
  defp tagged_tuple_kind(_other), do: :none

  defp merge_tagged_tuple_kinds(:none, kind), do: kind
  defp merge_tagged_tuple_kinds(kind, :none), do: kind
  defp merge_tagged_tuple_kinds(:ok, :error), do: :ok_and_error
  defp merge_tagged_tuple_kinds(:error, :ok), do: :ok_and_error
  defp merge_tagged_tuple_kinds(:ok_and_error, _right), do: :ok_and_error
  defp merge_tagged_tuple_kinds(_left, :ok_and_error), do: :ok_and_error
  defp merge_tagged_tuple_kinds(kind, kind), do: kind

  defp contains_nil?({:|, _meta, [left, right]}) do
    contains_nil?(left) or contains_nil?(right)
  end

  defp contains_nil?(nil), do: true
  defp contains_nil?(_other), do: false

  defp ignore_path?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &matches?(filename, &1))
  end

  defp matches?(filename, %Regex{} = regex), do: Regex.match?(regex, filename)
  defp matches?(filename, path) when is_binary(path), do: String.contains?(filename, path)
end
