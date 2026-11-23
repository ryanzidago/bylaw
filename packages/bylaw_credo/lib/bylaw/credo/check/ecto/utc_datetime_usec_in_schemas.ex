defmodule Bylaw.Credo.Check.Ecto.UtcDatetimeUsecInSchemas do
  @moduledoc """
  Hold every instant in a database-backed Ecto schema as `:utc_datetime_usec`
  (or `:utc_datetime`, when the project settles for seconds).

  ## Examples

  Avoid:

        schema "orders" do
          field :placed_at, :naive_datetime
          field :shipped_at, :utc_datetime
          timestamps()
        end

  Prefer:

        schema "orders" do
          field :placed_at, :utc_datetime_usec
          field :shipped_at, :utc_datetime_usec
          timestamps(type: :utc_datetime_usec)
        end

  Principle: "one type for an instant".

  A `:naive_datetime` has no zone, so two code paths can disagree about
  whether it is local time or UTC, and nothing catches it. `:utc_datetime`
  and `:utc_datetime_usec` are always UTC. Choosing one precision for the
  whole project also stops a value from losing its microseconds on one path
  and keeping them on another, which breaks equality and ordering. The
  default precision is microseconds; the schema type does not decide the
  column, the migration does (see `UseTimestamptzInMigrations`).

  The check looks at `schema "..." do` blocks and reports a `field` of the
  wrong time type, also inside `{:array, type}`, and `timestamps/1` with a
  wrong `type:`, `inserted_at_type:` or `updated_at_type:`. A bare
  `timestamps/1` creates `:naive_datetime` fields, so it is reported unless
  the module sets `@timestamps_opts` with a type, or `:allow_bare_timestamps`
  is set. A wrong `type:` in `@timestamps_opts` is reported too.

  It does not report an `embedded_schema`, or an `embeds_one` and
  `embeds_many` block, because they back forms and JSON, which can hold what a
  person typed in local time. It does not report `:date`, `:time` and
  `:time_usec`, nor a type spelled in a string or a variable.

  Do not use this check in a project whose schemas deliberately hold a local
  wall-clock time in the database.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.UtcDatetimeUsecInSchemas,
           [precision: :second, allow_bare_timestamps: true]}
        ]
      }
    ]
  }
  ```

  - `:precision` - `:microsecond` requires `:utc_datetime_usec`; `:second`
    requires `:utc_datetime`. Defaults to `:microsecond`.
  - `:allow_bare_timestamps` - Whether `timestamps/1` without a type option is
    allowed, for schemas that get their `@timestamps_opts` from a shared
    `use` macro. Defaults to `false`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.UtcDatetimeUsecInSchemas, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:database],
    param_defaults: [precision: :microsecond, allow_bare_timestamps: false],
    explanations: [
      check: @moduledoc,
      params: [
        precision:
          "`:microsecond` requires `:utc_datetime_usec`, `:second` requires `:utc_datetime`.",
        allow_bare_timestamps:
          "Allow `timestamps/1` without a type option, for schemas whose `@timestamps_opts` come from a macro."
      ]
    ]

  @time_types [:naive_datetime, :naive_datetime_usec, :utc_datetime, :utc_datetime_usec]
  @timestamp_type_options [:type, :inserted_at_type, :updated_at_type]
  @embeds [:embeds_one, :embeds_many]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    params =
      params
      |> Params.get(__MODULE__)
      |> Map.new()

    issue_meta = IssueMeta.for(source_file, [])
    ast = Credo.SourceFile.ast(source_file)
    expected = expected_type(params.precision)
    ctx = %{expected: expected, params: params, issue_meta: issue_meta}

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:schema, _meta, [_source | _rest] = args} = node, issues ->
          case List.last(args) do
            [do: block] -> {node, schema_issues(block, ast, ctx) ++ issues}
            _other -> {node, issues}
          end

        {:@, meta, [{:timestamps_opts, _meta, [value]}]} = node, issues ->
          if schema?(ast) do
            {node, options_issues(value, meta, ctx) ++ issues}
          else
            {node, issues}
          end

        node, issues ->
          {node, issues}
      end)

    Enum.sort_by(issues, & &1.line_no)
  end

  defp expected_type(:second), do: :utc_datetime
  defp expected_type(_precision), do: :utc_datetime_usec

  defp schema?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:schema, _meta, [_source | _rest] = args} = node, acc ->
          {node, acc or match?([do: _block], List.last(args))}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp timestamps_opts?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:@, _meta, [{:timestamps_opts, _meta2, [_value]}]} = node, _acc -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  defp schema_issues(block, ast, ctx) do
    bare_ok? = ctx.params.allow_bare_timestamps or timestamps_opts?(ast)

    {_block, issues} =
      Macro.prewalk(block, [], fn
        {embed, _meta, args} = node, acc when embed in @embeds and is_list(args) ->
          if Enum.any?(args, &match?([do: _block], &1)) do
            {{:__skipped__, [], []}, acc}
          else
            {node, acc}
          end

        {:field, meta, [name, type | _rest]} = node, acc ->
          {node, field_issues(name, type, meta, ctx) ++ acc}

        {:timestamps, meta, args} = node, acc when is_list(args) or is_nil(args) ->
          {node, timestamps_issues(args, meta, bare_ok?, ctx) ++ acc}

        node, acc ->
          {node, acc}
      end)

    issues
  end

  defp field_issues(name, type, meta, ctx) do
    if wrong?(type, ctx.expected) do
      [issue(ctx, meta, "field", "Field `#{inspect_name(name)}` has type #{inspect_type(type)}")]
    else
      []
    end
  end

  defp timestamps_issues(args, meta, bare_ok?, ctx) do
    typed = typed_options(args)

    cond do
      Enum.any?(typed, fn {_key, type} -> wrong?(type, ctx.expected) end) ->
        [issue(ctx, meta, "timestamps", "`timestamps` uses a wrong time type")]

      typed == [] and not bare_ok? ->
        [
          issue(
            ctx,
            meta,
            "timestamps",
            "`timestamps` without a type option holds `:naive_datetime`"
          )
        ]

      true ->
        []
    end
  end

  defp options_issues(value, meta, ctx) do
    wrong =
      value
      |> typed_options()
      |> Enum.filter(fn {_key, type} -> wrong?(type, ctx.expected) end)

    if wrong == [] do
      []
    else
      [issue(ctx, meta, "@timestamps_opts", "`@timestamps_opts` uses a wrong time type")]
    end
  end

  defp typed_options([opts]) when is_list(opts), do: typed_options(opts)

  defp typed_options(opts) when is_list(opts) do
    Enum.filter(opts, fn
      {key, _value} -> key in @timestamp_type_options
      _other -> false
    end)
  end

  defp typed_options(_opts), do: []

  defp wrong?({:array, type}, expected), do: wrong?(type, expected)
  defp wrong?(type, expected) when type in @time_types, do: type != expected
  defp wrong?(_type, _expected), do: false

  defp inspect_name(name) when is_atom(name), do: inspect(name)
  defp inspect_name(_name), do: "..."

  defp inspect_type({:array, type}), do: "{:array, #{inspect(type)}}"
  defp inspect_type(type), do: inspect(type)

  defp issue(ctx, meta, trigger, subject) do
    format_issue(ctx.issue_meta,
      message: "#{subject} in a database-backed schema; use `#{inspect(ctx.expected)}`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
